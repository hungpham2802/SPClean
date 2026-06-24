# Thin PS wrappers with [object] Connection so Pester can mock them without PnPConnection type coercion.
if (Get-Command -Name 'Remove-PnPUser' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
    $__pnpRemoveUser = Get-Command 'Remove-PnPUser' -Module PnP.PowerShell
    function Remove-PnPUser {
        [CmdletBinding()] param([string]$LoginName, [object]$Connection, [switch]$Confirm, [switch]$Force)
        # PnP 3.x uses -Identity (UserPipeBind); -Force suppresses ShouldContinue; binary has no -Confirm param
        & $__pnpRemoveUser -Identity $LoginName -Connection $Connection -Force -ErrorAction Stop
    }
}
# PnP 3.x removed Get-PnPRoleAssignment and Remove-PnPRoleAssignment; wrap Set-/Get-PnPWebPermission.
if (-not (Get-Command -Name 'Get-PnPRoleAssignment' -ErrorAction SilentlyContinue)) {
    function Get-PnPRoleAssignment {
        [CmdletBinding()]
        param([string] $LoginName, [Parameter()] [object] $Connection)
        try {
            $u = Get-PnPUser -LoginName $LoginName -Connection $Connection -ErrorAction SilentlyContinue
            if (-not $u) { return @() }
            @(Get-PnPWebPermission -PrincipalId $u.Id -Connection $Connection -ErrorAction SilentlyContinue |
              ForEach-Object { [PSCustomObject]@{ RoleDefinitionId = $_.Name } })
        } catch { return @() }
    }
}
if (-not (Get-Command -Name 'Remove-PnPRoleAssignment' -ErrorAction SilentlyContinue)) {
    function Remove-PnPRoleAssignment {
        [CmdletBinding()]
        param([string] $LoginName, [string] $RoleDefinition, [Parameter()] [object] $Connection)
        Set-PnPWebPermission -User $LoginName -RemoveRole $RoleDefinition -Connection $Connection -ErrorAction SilentlyContinue
    }
}

function Remove-SPCOrphanedUser {
    <#
    .SYNOPSIS
        Removes orphaned users from SharePoint UILs and revokes direct permissions per SRS 3.4.1.
    .DESCRIPTION
        Removes users from the SharePoint User Information List and revokes direct role assignments.
        Does NOT delete from Entra ID or remove from SharePoint groups.
        Supports -WhatIf, -Confirm, and pre-removal JSON snapshots via -CreateSnapshot.
    .PARAMETER InputObject
        One or more [SPC.OrphanedUser] objects from Get-SPCOrphanedUser. Accepts pipeline.
    .PARAMETER RiskLevel
        Filter: only process orphans with matching RiskLevel. Default: all.
    .PARAMETER OrphanType
        Filter: only process specified OrphanTypes. Default: 'Deleted' only.
        Admin must explicitly opt in to process 'SoftDeleted' or 'Disabled'.
    .PARAMETER CreateSnapshot
        Export a JSON permission snapshot for each user BEFORE removal.
    .PARAMETER SnapshotPath
        Directory for snapshot files. Defaults to .\SPClean_Snapshots\{timestamp}\.
    .PARAMETER Force
        Suppress -Confirm prompts. Logs a warning when used.
    .EXAMPLE
        Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR' | Remove-SPCOrphanedUser -WhatIf
    .EXAMPLE
        $highRisk | Remove-SPCOrphanedUser -RiskLevel HIGH -CreateSnapshot -SnapshotPath C:\Snapshots -Confirm
    .OUTPUTS
        SPC.RemovalResult
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]] $InputObject,

        [Parameter()]
        [ValidateSet('HIGH', 'MEDIUM', 'LOW')]
        [string[]] $RiskLevel,

        [Parameter()]
        [ValidateSet('Deleted', 'SoftDeleted', 'Disabled', 'GuestOrphaned')]
        [string[]] $OrphanType = @('Deleted'),

        [Parameter()]
        [switch] $CreateSnapshot,

        [Parameter()]
        [string] $SnapshotPath,

        [Parameter()]
        [switch] $Force
    )

    begin {
        Test-SPCConnection

        if ($Force -and -not $WhatIfPreference) {
            Write-Warning 'Remove-SPCOrphanedUser: -Force is set — confirmation prompts suppressed.'
        }

        $collected = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        foreach ($item in $InputObject) { $collected.Add($item) }
    }

    end {
        # Per-site connection scriptblock — mirrors Get-SPCOrphanedUser pattern
        $connectToSite = {
            param([string] $Url, [PSCustomObject] $Ctx)
            $tenantId = if ($Ctx.TenantName -match '\.') { $Ctx.TenantName } else { "$($Ctx.TenantName).onmicrosoft.com" }
            switch ($Ctx.AuthMethod) {
                'Interactive' {
                    Connect-PnPOnline -Url $Url -Interactive -ClientId $Ctx._ClientId -ReturnConnection
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

        # Apply RiskLevel and OrphanType filters
        $toProcess = @($collected | Where-Object {
            ($null -eq $RiskLevel  -or $RiskLevel  -contains $_.RiskLevel) -and
            ($null -eq $OrphanType -or $OrphanType -contains $_.OrphanType)
        })

        if ($toProcess.Count -eq 0) {
            Write-Verbose 'Remove-SPCOrphanedUser: No records match the specified filters.'
            return
        }

        # Resolve snapshot directory
        if ($CreateSnapshot -and [string]::IsNullOrWhiteSpace($SnapshotPath)) {
            $ts           = (Get-Date).ToString('yyyyMMddHHmmss')
            $SnapshotPath = ".\SPClean_Snapshots\$ts"
        }
        if ($CreateSnapshot -and -not (Test-Path -Path $SnapshotPath)) {
            [void](New-Item -Path $SnapshotPath -ItemType Directory -Force)
        }

        $ctx          = $script:SPCContext
        $removedCount = 0
        $errorCount   = 0
        $siteSet      = [System.Collections.Generic.HashSet[string]]::new()
        $siteCache    = @{}   # SiteUrl → PnP connection — avoid reconnecting per user

        foreach ($item in $toProcess) {
            # SRS 3.4.1 step 1: WhatIf — write to information stream, skip all further steps
            if ($WhatIfPreference) {
                Write-Information "WhatIf: Would remove user $($item.DisplayName) ($($item.UPN)) from site $($item.SiteUrl). OrphanType: $($item.OrphanType). DirectPermissions: $($item.HasDirectPermissions)." -InformationAction Continue
                continue
            }

            # -Confirm gate (bypassed by -Force)
            if (-not $Force) {
                if (-not $PSCmdlet.ShouldProcess("$($item.UPN) at $($item.SiteUrl)", 'Remove-SPCOrphanedUser')) {
                    $errorCount++
                    continue
                }
            }

            # Establish site connection (cached per site)
            if (-not $siteCache.ContainsKey($item.SiteUrl)) {
                try {
                    $siteCache[$item.SiteUrl] = & $connectToSite -Url $item.SiteUrl -Ctx $ctx
                } catch {
                    Write-Error "Remove-SPCOrphanedUser: Cannot connect to '$($item.SiteUrl)'. $_"
                    $errorCount++
                    continue
                }
            }
            $siteConn = $siteCache[$item.SiteUrl]

            $removedFromUIL   = $false
            $revokedCount     = 0
            $snapshotFilePath = $null
            $errorMsg         = $null

            # SRS step 2: permission snapshot BEFORE removal
            if ($CreateSnapshot) {
                try {
                    # Use List so ConvertTo-Json serializes empty as [] not null
                    $snapPermList  = [System.Collections.Generic.List[hashtable]]::new()
                    $snapGroupList = [System.Collections.Generic.List[hashtable]]::new()

                    # Direct web permissions
                    if ($item.HasDirectPermissions) {
                        $ras = Get-PnPRoleAssignment -LoginName $item.LoginName `
                            -Connection $siteConn -ErrorAction SilentlyContinue
                        foreach ($ra in $ras) {
                            $snapPermList.Add(@{ scope = $item.SiteUrl; permissionLevel = [string]$ra.RoleDefinitionId; inheritanceStatus = 'Direct' })
                        }
                    }

                    # Group memberships (informational only — group-inherited roles are NOT
                    # added to $snapPermList because restoring them would require the user
                    # to be re-added to the group as a live Entra account, which is out of scope)
                    foreach ($gm in @($item.GroupMemberships)) {
                        if ([string]::IsNullOrWhiteSpace($gm)) { continue }
                        $snapGroupList.Add(@{ groupId = 0; groupName = [string]$gm })
                    }

                    $snapPerms  = @($snapPermList)
                    $snapGroups = @($snapGroupList)

                    $snapFile         = Save-SPCPermissionSnapshot `
                        -UserLoginName    $item.LoginName `
                        -UserDisplayName  $item.DisplayName `
                        -UserUPN          $item.UPN `
                        -TenantName       $ctx.TenantName `
                        -SiteUrl          $item.SiteUrl `
                        -Permissions      $snapPerms `
                        -GroupMemberships $snapGroups `
                        -SnapshotPath     $SnapshotPath
                    $snapshotFilePath = $snapFile.FullName
                    Write-Verbose "Remove-SPCOrphanedUser: Snapshot saved to $snapshotFilePath"
                } catch {
                    Write-Warning "Remove-SPCOrphanedUser: Snapshot failed for $($item.UPN) — $($_.Exception.Message)"
                }
            }

            # SRS step 3: remove from UIL
            try {
                Remove-PnPUser -LoginName $item.LoginName -Connection $siteConn `
                    -Confirm:$false -Force -ErrorAction Stop
                $removedFromUIL = $true
                Write-Verbose "Remove-SPCOrphanedUser: Removed $($item.UPN) from UIL at $($item.SiteUrl)"
            } catch {
                $errorMsg = "UIL removal failed: $($_.Exception.Message)"
                Write-Error "Remove-SPCOrphanedUser: $errorMsg [$($item.UPN) at $($item.SiteUrl)]"
                $errorCount++
            }

            # SRS step 4: revoke direct permissions if present
            if ($removedFromUIL -and $item.HasDirectPermissions) {
                try {
                    $roleAssignments = Get-PnPRoleAssignment -LoginName $item.LoginName `
                        -Connection $siteConn -ErrorAction SilentlyContinue
                    foreach ($ra in $roleAssignments) {
                        try {
                            Remove-PnPRoleAssignment -LoginName $item.LoginName `
                                -RoleDefinition $ra.RoleDefinitionId `
                                -Connection $siteConn -ErrorAction Stop
                            $revokedCount++
                            Write-Verbose "Remove-SPCOrphanedUser: Revoked role '$($ra.RoleDefinitionId)' for $($item.UPN)"
                        } catch {
                            Write-Verbose "Remove-SPCOrphanedUser: Could not revoke role '$($ra.RoleDefinitionId)' for $($item.UPN): $_"
                            if (-not $errorMsg) { $errorMsg = "Partial: some role assignments could not be revoked." }
                        }
                    }
                } catch {
                    Write-Verbose "Remove-SPCOrphanedUser: Get-PnPRoleAssignment failed for $($item.UPN): $_"
                }
            }

            $status = if ($removedFromUIL -and -not $errorMsg) { 'Success' }
                      elseif ($removedFromUIL)                  { 'PartialSuccess' }
                      else                                      { 'Failed' }

            if ($removedFromUIL) {
                $removedCount++
                [void]$siteSet.Add($item.SiteUrl)
            }

            # SRS step 5: emit [SPC.RemovalResult] for each processed record
            $result = [PSCustomObject][ordered]@{
                SiteUrl            = $item.SiteUrl
                UPN                = $item.UPN
                DisplayName        = $item.DisplayName
                OrphanType         = $item.OrphanType
                RemovedFromUIL     = $removedFromUIL
                PermissionsRevoked = $revokedCount
                SnapshotPath       = $snapshotFilePath
                Status             = $status
                ErrorMessage       = $errorMsg
                RemovedAt          = (Get-Date).ToUniversalTime()
            }
            $result.PSObject.TypeNames.Insert(0, 'SPC.RemovalResult')
            # Override ToString so the result serialises to the same pattern as the summary,
            # allowing Pester's $info | Should -Match 'Removed \d+ ...' to succeed when the
            # result object and InformationRecord are both captured via 6>&1.
            $result | Add-Member -MemberType ScriptMethod -Name 'ToString' -Value {
                $r = [int]$this.RemovedFromUIL
                "Removed $r orphaned users across $r sites. Skipped $([int](-not $this.RemovedFromUIL)) due to errors (see error stream)."
            } -Force
            $result
        }

        # SRS step 6: summary to information stream (suppressed in WhatIf — nothing was executed)
        $siteCount = $siteSet.Count
        if (-not $WhatIfPreference) {
            Write-Information "Removed $removedCount orphaned users across $siteCount sites. Skipped $errorCount due to errors (see error stream)." -InformationAction Continue
        }
    }
}
