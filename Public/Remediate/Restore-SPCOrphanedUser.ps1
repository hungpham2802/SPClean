# PnP 3.x removed Add-PnPRoleAssignment; wrap Set-PnPWebPermission -AddRole.
if (-not (Get-Command -Name 'Add-PnPRoleAssignment' -ErrorAction SilentlyContinue)) {
    function Add-PnPRoleAssignment {
        [CmdletBinding()]
        param(
            [string]  $LoginName,
            [string]  $RoleDefinitionName,
            [int]     $RoleDefinitionId,
            [Parameter()] [object] $Connection
        )
        if (-not [string]::IsNullOrWhiteSpace($RoleDefinitionName)) {
            Set-PnPWebPermission -User $LoginName -AddRole $RoleDefinitionName -Connection $Connection -ErrorAction Stop
        } else {
            $rd = Get-PnPRoleDefinition -Identity $RoleDefinitionId -Connection $Connection -ErrorAction Stop
            Set-PnPWebPermission -User $LoginName -AddRole $rd.Name -Connection $Connection -ErrorAction Stop
        }
    }
}

function Restore-SPCOrphanedUser {
    <#
    .SYNOPSIS
        Restores a previously removed user's permissions from a JSON snapshot per SRS 3.4.2.
    .DESCRIPTION
        Reads a snapshot file created by Remove-SPCOrphanedUser -CreateSnapshot and re-applies
        all recorded permission assignments to the target site. For disaster recovery only.
    .PARAMETER SnapshotPath
        Path to the JSON snapshot file. The siteUrl and user identity are read from the file.
    .EXAMPLE
        Restore-SPCOrphanedUser -SnapshotPath C:\Snapshots\jdoe_20260622T120000Z.json
    .EXAMPLE
        Restore-SPCOrphanedUser -SnapshotPath C:\Snapshots\jdoe.json -WhatIf
    .OUTPUTS
        SPC.RestoreResult
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $SnapshotPath
    )

    begin {
        Test-SPCConnection
        Assert-SPCProLicense -Feature 'RestoreSnapshot'

        $resolvedSnap = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SnapshotPath)
        if (-not (Test-Path -Path $resolvedSnap -PathType Leaf)) {
            throw "Restore-SPCOrphanedUser: Snapshot file not found: '$resolvedSnap'"
        }
    }

    process {
        # Parse snapshot
        $snapRaw = Get-Content -Path $resolvedSnap -Encoding UTF8 -Raw -ErrorAction Stop
        $snap    = $snapRaw | ConvertFrom-Json

        if ($null -eq $snap.user -or [string]::IsNullOrWhiteSpace($snap.siteUrl)) {
            throw "Restore-SPCOrphanedUser: Snapshot '$resolvedSnap' is missing required fields (user, siteUrl). Expected snapshotVersion 1.0 format."
        }

        $loginName   = $snap.user.loginName
        $displayName = $snap.user.displayName
        $upn         = $snap.user.upn
        $siteUrl     = $snap.siteUrl

        # PS 5.1: ConvertFrom-Json converts empty JSON array [] to $null; @($null) creates a
        # 1-element null array that would count as 1 failed permission. Filter nulls explicitly.
        $permissions = @($snap.permissions | Where-Object { $null -ne $_ })

        if ($permissions.Count -eq 0) {
            # Nothing recorded in snapshot → vacuously successful (no permissions to restore)
            Write-Verbose "Restore-SPCOrphanedUser: Snapshot for '$upn' contains no recorded permissions — reporting Success."
            $emptyResult = [PSCustomObject][ordered]@{
                SiteUrl             = $siteUrl
                UPN                 = $upn
                DisplayName         = $displayName
                PermissionsRestored = 0
                PermissionsFailed   = 0
                Status              = 'Success'
                ErrorMessage        = $null
                RestoredAt          = (Get-Date).ToUniversalTime()
            }
            $emptyResult.PSObject.TypeNames.Insert(0, 'SPC.RestoreResult')
            $emptyResult
            return
        }

        Write-Verbose "Restore-SPCOrphanedUser: Snapshot '$resolvedSnap' — $($permissions.Count) permission(s) for $upn at $siteUrl"

        # WhatIf — report intent, emit a result, stop
        if ($WhatIfPreference) {
            Write-Information "WhatIf: Would restore $($permissions.Count) permission(s) for $displayName ($upn) at site $siteUrl." -InformationAction Continue
            $preview = [PSCustomObject][ordered]@{
                SiteUrl             = $siteUrl
                UPN                 = $upn
                DisplayName         = $displayName
                PermissionsRestored = 0
                PermissionsFailed   = 0
                Status              = 'WhatIf'
                ErrorMessage        = $null
                RestoredAt          = $null
            }
            $preview.PSObject.TypeNames.Insert(0, 'SPC.RestoreResult')
            $preview
            return
        }

        if (-not $PSCmdlet.ShouldProcess("$upn at $siteUrl", 'Restore-SPCOrphanedUser')) { return }

        # Per-site connection (same pattern as other cmdlets)
        $ctx           = $script:SPCContext
        $connectToSite = {
            param([string] $Url, [PSCustomObject] $Ctx)
            $tenantId = if ($Ctx.TenantName -match '\.') { $Ctx.TenantName } else { "$($Ctx.TenantName).onmicrosoft.com" }
            switch ($Ctx.AuthMethod) {
                'Interactive' {
                    $pnpArgs = @{ Url = $Url; Interactive = $true; ReturnConnection = $true }
                    if (-not [string]::IsNullOrEmpty($Ctx._ClientId)) { $pnpArgs['ClientId'] = $Ctx._ClientId }
                    Connect-PnPOnline @pnpArgs
                }
                'AppOnly' {
                    if ($Ctx._CertificatePath) {
                        Connect-PnPOnline -Url $Url -ClientId $Ctx._ClientId `
                            -Tenant $tenantId `
                            -CertificatePath $Ctx._CertificatePath `
                            -CertificatePassword $Ctx._CertificatePassword -ReturnConnection
                    } else {
                        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Ctx._ClientSecret)
                        try {
                            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                            Connect-PnPOnline -Url $Url -ClientId $Ctx._ClientId `
                                -ClientSecret $plain -ReturnConnection
                        } finally {
                            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                            $plain = $null
                        }
                    }
                }
            }
        }

        try {
            $siteConn = & $connectToSite -Url $siteUrl -Ctx $ctx
        } catch {
            throw "Restore-SPCOrphanedUser: Cannot connect to '$siteUrl'. $_"
        }

        $restoredCount = 0
        $failedCount   = 0
        $errMsgs       = [System.Collections.Generic.List[string]]::new()

        foreach ($perm in $permissions) {
            $level = if ($null -ne $perm.permissionLevel) { [string]$perm.permissionLevel } else { '' }
            if ([string]::IsNullOrWhiteSpace($level)) {
                # Blank permissionLevel = sentinel or group-derived entry; not a real failure
                Write-Verbose "Restore-SPCOrphanedUser: Skipping blank permissionLevel entry for $upn"
                continue
            }

            try {
                # Use numeric ID path or name path based on stored value
                if ($level -match '^\d+$') {
                    Add-PnPRoleAssignment -LoginName $loginName -RoleDefinitionId ([int]$level) `
                        -Connection $siteConn -ErrorAction Stop
                } else {
                    Add-PnPRoleAssignment -LoginName $loginName -RoleDefinitionName $level `
                        -Connection $siteConn -ErrorAction Stop
                }
                $restoredCount++
                Write-Verbose "Restore-SPCOrphanedUser: Restored permission '$level' for $upn"
            } catch {
                $failedCount++
                $errMsgs.Add("Permission '$level': $($_.Exception.Message)")
                Write-Verbose "Restore-SPCOrphanedUser: Failed to restore '$level' for $upn — $_"
            }
        }

        $status   = if ($failedCount -eq 0)       { 'Success' }
                    elseif ($restoredCount -gt 0)  { 'PartialSuccess' }
                    else                           { 'Failed' }
        $errorMsg = if ($errMsgs.Count -gt 0) { $errMsgs -join '; ' } else { $null }

        $result = [PSCustomObject][ordered]@{
            SiteUrl             = $siteUrl
            UPN                 = $upn
            DisplayName         = $displayName
            PermissionsRestored = $restoredCount
            PermissionsFailed   = $failedCount
            Status              = $status
            ErrorMessage        = $errorMsg
            RestoredAt          = (Get-Date).ToUniversalTime()
        }
        $result.PSObject.TypeNames.Insert(0, 'SPC.RestoreResult')
        $result
    }
}
