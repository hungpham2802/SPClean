# Thin PS wrappers for PnP
if (Get-Command -Name 'Remove-PnPUser' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
    $__pnpRemoveUser = Get-Command 'Remove-PnPUser' -Module PnP.PowerShell
    function Remove-PnPUser {
        [CmdletBinding()] param([string]$LoginName, [object]$Connection, [switch]$Confirm, [switch]$Force)
        $params = @{}; foreach ($k in $PSBoundParameters.Keys) { $params[$k] = $PSBoundParameters[$k] }
        if ($params.ContainsKey('LoginName')) { $params['Identity'] = $params['LoginName']; $params.Remove('LoginName') | Out-Null }
        $params.Remove('Confirm') | Out-Null
        $params['Force'] = $true
        & $__pnpRemoveUser @params
    }
}
    function Get-PnPRoleAssignment {
        [CmdletBinding()]
        param([string] $LoginName, [Parameter()] [object] $Connection)
        try {
            $u = Get-PnPUser -LoginName $LoginName -Connection $Connection -ErrorAction SilentlyContinue
            if (-not $u) { return @() }
            $res = @()
            $webPerms = Get-PnPWebPermission -PrincipalId $u.Id -Connection $Connection -ErrorAction SilentlyContinue
            if ($webPerms) {
                foreach ($wp in $webPerms) {
                    $res += [PSCustomObject]@{ Scope = 'Web'; ScopeUrl = ''; RoleDefinitionId = $wp.Name }
                }
            }
            $lists = Get-PnPList -Connection $Connection -Includes HasUniqueRoleAssignments, RootFolder.ServerRelativeUrl | Where-Object HasUniqueRoleAssignments
            foreach ($l in $lists) {
                $roleAssignments = Get-PnPProperty -ClientObject $l -Property RoleAssignments -Connection $Connection
                foreach ($ra in $roleAssignments) {
                    $Connection.Context.Load($ra.Member)
                    $Connection.Context.Load($ra.RoleDefinitionBindings)
                    $Connection.Context.ExecuteQuery()
                    if ($ra.Member.Id -eq $u.Id) {
                        foreach ($rd in $ra.RoleDefinitionBindings) {
                            $res += [PSCustomObject]@{ Scope = 'List'; ScopeUrl = $l.RootFolder.ServerRelativeUrl; RoleDefinitionId = $rd.Name; ListId = $l.Id }
                        }
                    }
                }
            }
            return $res
        } catch { throw }
    }
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
if (Get-Command -Name 'Add-PnPGroupMember' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
    $__pnpAddGroupMember = Get-Command 'Add-PnPGroupMember' -Module PnP.PowerShell
    function Add-PnPGroupMember {
        [CmdletBinding()] param([string]$LoginName, [string]$Group, [object]$Connection)
        $params = @{}; foreach ($k in $PSBoundParameters.Keys) { $params[$k] = $PSBoundParameters[$k] }
        & $__pnpAddGroupMember @params
    }
}

function Repair-SPCMismatchUser {
    <#
    .SYNOPSIS
        Remediates User ID Mismatches by removing the stale UIL entry and optionally restoring permissions.
    .DESCRIPTION
        Implements Microsoft's recommended workflow for resolving Site User ID Mismatches.
        Never modifies the UIL ObjectId directly.
    .PARAMETER InputObject
        One or more [SPC.MismatchUser] objects.
    .PARAMETER Mode
        ReportOnly: Preview actions.
        Clean: Remove stale UIL entry.
        CleanAndRestore: Remove stale UIL entry and re-grant permissions to new Entra identity.
    .PARAMETER CreateSnapshot
        Export a JSON permission snapshot BEFORE removal.
    .PARAMETER SnapshotPath
        Directory for snapshot files.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]] $InputObject,

        [Parameter()]
        [ValidateSet('ReportOnly', 'Clean', 'CleanAndRestore')]
        [string] $Mode = 'ReportOnly',

        [Parameter()]
        [switch] $CreateSnapshot,

        [Parameter()]
        [string] $SnapshotPath,

        [Parameter()]
        [switch] $Force
    )

    begin {
        Test-SPCConnection

        if ($Mode -in @('Clean', 'CleanAndRestore') -and -not $WhatIfPreference) {
            Assert-SPCProLicense -Feature 'MismatchRemediation'
        }
        if ($CreateSnapshot -and -not $WhatIfPreference) {
            Assert-SPCProLicense -Feature 'SnapshotBackup'
        }

        $collected = [System.Collections.Generic.List[PSCustomObject]]::new()
    }
    process {
        foreach ($item in $InputObject) { $collected.Add($item) }
    }
    end {
        $connectToSite = {
            param([string] $Url, [PSCustomObject] $Ctx)
            $tenantId = if ($Ctx.TenantName -match '\.') { $Ctx.TenantName } else { "$($Ctx.TenantName).onmicrosoft.com" }
            switch ($Ctx.AuthMethod) {
                'Interactive' {
                    $token = Get-PnPAccessToken -ResourceTypeName SharePoint -Connection $Ctx.PnPContext
                    Connect-PnPOnline -Url $Url -AccessToken $token -ReturnConnection
                }
                'AppOnly' {
                    if ($Ctx._CertificatePath) {
                        if ($null -ne $Ctx._CertificatePassword) {
                            Connect-PnPOnline -Url $Url -ClientId $Ctx._ClientId -Tenant $tenantId -CertificatePath $Ctx._CertificatePath -CertificatePassword $Ctx._CertificatePassword -ReturnConnection
                        } else {
                            Connect-PnPOnline -Url $Url -ClientId $Ctx._ClientId -Tenant $tenantId -CertificatePath $Ctx._CertificatePath -ReturnConnection
                        }
                    } elseif ($Ctx._CertificateThumbprint) {
                        Connect-PnPOnline -Url $Url -ClientId $Ctx._ClientId -Tenant $tenantId -Thumbprint $Ctx._CertificateThumbprint -ReturnConnection
                    } else {
                        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Ctx._ClientSecret)
                        try {
                            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                            Connect-PnPOnline -Url $Url -ClientId $Ctx._ClientId -ClientSecret $plain -ReturnConnection
                        } finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
                    }
                }
            }
        }

        if ($CreateSnapshot -and [string]::IsNullOrWhiteSpace($SnapshotPath)) {
            $ts = (Get-Date).ToString('yyyyMMddHHmmss')
            $SnapshotPath = ".\SPClean_Snapshots\$ts"
        }

        $ctx = $script:SPCContext
        $siteCache = @{}

        foreach ($item in $collected) {
            if ($Mode -eq 'ReportOnly' -or $WhatIfPreference) {
                Write-Information "WhatIf: Would run mode $Mode for user $($item.DisplayName) ($($item.UPN)) on site $($item.SiteUrl)." -InformationAction Continue
                continue
            }

            if (-not $Force -and -not $PSCmdlet.ShouldProcess("$($item.UPN) at $($item.SiteUrl)", "Repair-SPCMismatchUser ($Mode)")) { continue }

            if ($item.Status -eq 'GuestMismatch') {
                Write-Warning "Repair-SPCMismatchUser: Skipping Guest user $($item.UPN) at $($item.SiteUrl). Remediation for guests is not supported."
                continue
            }

            if ($item.Status -in @('Healthy', 'Unknown')) {
                Write-Warning "Repair-SPCMismatchUser: Skipping user $($item.UPN) with status $($item.Status)."
                continue
            }

            if (-not $siteCache.ContainsKey($item.SiteUrl)) {
                try {
                    $siteCache[$item.SiteUrl] = & $connectToSite -Url $item.SiteUrl -Ctx $ctx
                } catch {
                    Write-Error "Repair-SPCMismatchUser: Cannot connect to '$($item.SiteUrl)'. $_"
                    continue
                }
            }
            $siteConn = $siteCache[$item.SiteUrl]
            
            $removed = $false
            $restoredCount = 0
            $snapPerms = @()
            $snapGroups = @()
            
            try {
                if ($Mode -in @('Clean', 'CleanAndRestore')) {
                    # 1. Pre-validation: ensure UPN is valid and active in Entra ID
                    if (-not $item.EntraObjectId) {
                        throw "Validation Failed: No valid EntraObjectId found for UPN $($item.UPN)."
                    }

                    # 2. Extract permissions
                    $directPerms = Get-PnPRoleAssignment -LoginName $item.LoginName -Connection $siteConn -ErrorAction SilentlyContinue
                    $userGroups = if ($item.GroupMemberships) { $item.GroupMemberships } else { @() }
                    
                    $snapPermList = [System.Collections.Generic.List[hashtable]]::new()
                    foreach ($ra in $directPerms) {
                        if ($ra.Scope -eq 'List') {
                            $snapPermList.Add(@{ scope = $ra.ScopeUrl; scopeType = 'List'; listId = $ra.ListId; permissionLevel = [string]$ra.RoleDefinitionId; inheritanceStatus = 'Direct' })
                        } else {
                            $snapPermList.Add(@{ scope = $item.SiteUrl; scopeType = 'Web'; permissionLevel = [string]$ra.RoleDefinitionId; inheritanceStatus = 'Direct' })
                        }
                    }
                    $snapGroupList = [System.Collections.Generic.List[hashtable]]::new()
                    foreach ($g in $userGroups) {
                        $snapGroupList.Add(@{ groupId = 0; groupName = [string]$g })
                    }
                    $snapPerms = @($snapPermList)
                    $snapGroups = @($snapGroupList)

                    # 3. Create snapshot
                    if ($CreateSnapshot) {
                        Save-SPCPermissionSnapshot -UserLoginName $item.LoginName -UserDisplayName $item.DisplayName -UserUPN $item.UPN `
                            -TenantName $ctx.TenantName -SiteUrl $item.SiteUrl -Permissions $snapPerms -GroupMemberships $snapGroups -SnapshotPath $SnapshotPath | Out-Null
                    }

                    # 4. Remove stale identity
                    Remove-PnPUser -LoginName $item.LoginName -Connection $siteConn -Confirm:$false -Force -ErrorAction Stop
                    $removed = $true
                    Write-Verbose "Repair-SPCMismatchUser: Removed stale UIL entry for $($item.UPN)"
                }

                if ($Mode -eq 'CleanAndRestore' -and $removed) {
                    # 5. Re-grant permissions (PnP will automatically re-resolve UPN to new ObjectId)
                    # We pass the UPN directly as LoginName. SharePoint converts it to i:0#.f|membership|upn
                    $newLoginName = "i:0#.f|membership|$($item.UPN)"

                    foreach ($p in $snapPerms) {
                        try {
                            $lvl = $p.permissionLevel
                            if ($p.scopeType -eq 'List') {
                                if ($lvl -match '^\d+$') { Set-PnPListPermission -Identity $p.listId -User $newLoginName -AddRole ([int]$lvl) -Connection $siteConn -ErrorAction Stop }
                                else { Set-PnPListPermission -Identity $p.listId -User $newLoginName -AddRole $lvl -Connection $siteConn -ErrorAction Stop }
                            } else {
                                if ($lvl -match '^\d+$') { Add-PnPRoleAssignment -LoginName $newLoginName -RoleDefinitionId ([int]$lvl) -Connection $siteConn -ErrorAction Stop }
                                else { Add-PnPRoleAssignment -LoginName $newLoginName -RoleDefinitionName $lvl -Connection $siteConn -ErrorAction Stop }
                            }
                            $restoredCount++
                        } catch { Write-Warning "Failed to restore role $($p.permissionLevel) for $($item.UPN): $_" }
                    }

                    foreach ($g in $snapGroups) {
                        try {
                            Add-PnPGroupMember -LoginName $newLoginName -Group $g.groupName -Connection $siteConn -ErrorAction Stop
                            $restoredCount++
                        } catch { Write-Warning "Failed to restore group $($g.groupName) for $($item.UPN): $_" }
                    }
                    Write-Verbose "Repair-SPCMismatchUser: Restored $restoredCount permissions/groups for $($item.UPN) using new identity."
                }

                # Emit result
                $res = [PSCustomObject][ordered]@{
                    SiteUrl = $item.SiteUrl
                    UPN = $item.UPN
                    RemovedFromUIL = $removed
                    PermissionsRestored = $restoredCount
                    Status = 'Success'
                    ErrorMessage = $null
                    RemediatedAt = (Get-Date).ToUniversalTime()
                }
                $res.PSObject.TypeNames.Insert(0, 'SPC.MismatchRepairResult')
                $res

            } catch {
                Write-Error "Repair-SPCMismatchUser: Failed to process $($item.UPN) at $($item.SiteUrl). $_"
                $res = [PSCustomObject][ordered]@{
                    SiteUrl = $item.SiteUrl
                    UPN = $item.UPN
                    RemovedFromUIL = $removed
                    PermissionsRestored = $restoredCount
                    Status = 'Failed'
                    ErrorMessage = $_.Exception.Message
                    RemediatedAt = (Get-Date).ToUniversalTime()
                }
                $res.PSObject.TypeNames.Insert(0, 'SPC.MismatchRepairResult')
                $res
            }
        }
    }
}
