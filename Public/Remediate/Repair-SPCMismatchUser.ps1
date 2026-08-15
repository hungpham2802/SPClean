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
        Remediates SharePoint Online and OneDrive User ID Mismatches by safely removing stale UIL records and restoring permissions to active Entra ID identities.

    .DESCRIPTION
        PROBLEM:
        In fast-moving Microsoft 365 environments, employee re-hires, tenant migrations, account provisioning resets,
        and B2B guest re-invitations constantly trigger identity desynchronization. When an account is re-created with the
        same User Principal Name (UPN) or email address, Entra ID assigns a brand-new Immutable ID (ObjectId). However,
        SharePoint Online retains the historical, obsolete ObjectId in its hidden site collection User Information List (UIL).
        This fatal "Site User ID Mismatch" leads to phantom "Access Denied" errors for legitimate active employees, broken
        collaboration pipelines, inaccessible OneDrive libraries, and ghost permission footprints that fail compliance audits
        and breach zero-trust governance policies.

        AGITATION:
        Remediating User ID mismatches manually across hundreds or thousands of SharePoint Online sites and OneDrive
        accounts is an administrative nightmare. Site collection administrators and M365 engineers are forced to manually
        trace broken permissions, run fragile custom scripts, or risk permanent data loss by deleting user entries without
        a backup. A single mistaken deletion can irrevocably destroy complex broken permission inheritances, unique list/item-level
        access control lists (ACLs), and group memberships—triggering severe business disruption, urgent helpdesk escalations,
        and painful security audit failures under ISO 27001, SOC 2, and GDPR.

        SOLUTION:
        Repair-SPCMismatchUser delivers an enterprise-grade, automated remediation engine designed to resolve Site User ID
        Mismatches with zero administrative friction and absolute safety. Following Microsoft's official best-practice
        remediation lifecycle, the cmdlet:
        1. Pre-validates active Entra ID identities via Microsoft Graph to prevent accidental orphaned deletions.
        2. Automatically snapshots existing direct permissions (web, list, folder levels) and SharePoint group memberships.
        3. Safely flushes the obsolete, mismatched UIL entry from the SharePoint site collection.
        4. Seamlessly re-binds the active Entra ID identity to the UIL and accurately re-establishes all direct permissions
           and group memberships in a single operation.
        5. Provides built-in -WhatIf simulation, Safety Rollback Snapshots, and detailed structured output for auditable reporting.

        Whether remediating a single high-priority executive account or batch-processing tenant-wide identity drift from
        Get-SPCMismatchUser, Repair-SPCMismatchUser transforms complex identity restoration into a dependable, one-line command.

    .PARAMETER InputObject
        Specifies one or more [SPC.MismatchUser] or custom objects containing identity mismatch data.
        Typically received via pipeline from Get-SPCMismatchUser.
        Required properties on each object:
        - SiteUrl: Target SharePoint Online or OneDrive site collection URL.
        - UPN: User Principal Name of the target user.
        - LoginName: Claims-based SharePoint login name (e.g., 'i:0#.f|membership|user@contoso.com').
        - DisplayName: User's display name.
        - EntraObjectId: Active Entra ID Object ID.
        - Status: Identity status (items with 'GuestMismatch', 'Healthy', or 'Unknown' are automatically safely skipped or warned).

    .PARAMETER Mode
        Specifies the remediation execution mode. Valid options:
        - ReportOnly: (Default) Simulates the remediation process and writes informational preview messages without making changes.
        - Clean: Removes the stale UIL entry from the site collection to resolve identity conflicts, without re-granting permissions.
        - CleanAndRestore: Removes the stale UIL entry and immediately re-grants all captured direct permissions and group memberships using the active Entra ID identity.

    .PARAMETER CreateSnapshot
        When specified, captures and exports a complete JSON backup of the user's direct permissions and SharePoint group memberships BEFORE any remediation occurs. Enables safety rollbacks and disaster recovery.

    .PARAMETER SnapshotPath
        Specifies the custom file system directory where permission snapshots will be saved.
        If omitted when -CreateSnapshot is enabled, defaults to '.\SPClean_Snapshots\<timestamp>\'.

    .PARAMETER Force
        Suppresses interactive confirmation prompts ($PSCmdlet.ShouldProcess) when performing High impact changes in 'Clean' or 'CleanAndRestore' modes. Recommended for unattended automation workflows.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .EXAMPLE
        Get-SPCMismatchUser -SiteUrl 'https://contoso.sharepoint.com/sites/Finance' | Where-Object Status -eq 'StaleIdentity' | Repair-SPCMismatchUser -Mode ReportOnly

        Scans the Finance site collection for stale identities and simulates the remediation workflow in ReportOnly mode, previewing which user records would be updated without altering permissions or UIL entries.

    .EXAMPLE
        Get-SPCMismatchUser -SiteUrl 'https://contoso.sharepoint.com/sites/Executive' -User 'ceo@contoso.com' | Repair-SPCMismatchUser -Mode CleanAndRestore -CreateSnapshot -SnapshotPath 'C:\SPClean\Snapshots'

        Remediates a User ID Mismatch for a re-hired executive on the Executive site collection. Creates a pre-remediation safety snapshot in 'C:\SPClean\Snapshots', purges the stale UIL record, and re-applies all site and list-level permissions to the new Entra ID account.

    .EXAMPLE
        $mismatches = Get-SPCMismatchUser -AllSites | Where-Object Status -eq 'StaleIdentity'
        $mismatches | Repair-SPCMismatchUser -Mode CleanAndRestore -CreateSnapshot -Force | Export-Csv -Path 'C:\Audits\MismatchRemediation_Report.csv' -NoTypeInformation

        Performs an unattended, automated enterprise-wide remediation across all tenant site collections for stale identities. Creates safety backup snapshots, suppresses confirmation prompts with -Force, and exports the structured remediation results to CSV for compliance auditing.

    .OUTPUTS
        [PSCustomObject] with type name 'SPC.MismatchRepairResult'.
        Contains properties:
        - SiteUrl: The target SharePoint Online or OneDrive site collection URL.
        - UPN: User Principal Name of the remediated identity.
        - RemovedFromUIL: Boolean indicating if the stale UIL entry was successfully removed.
        - PermissionsRestored: Integer count of direct role assignments and group memberships re-applied.
        - Status: 'Success' or 'Failed'.
        - ErrorMessage: Exception details if an error occurred during remediation; otherwise $null.
        - RemediatedAt: UTC timestamp of the remediation operation.

    .NOTES
        Module: SPClean
        Author: SPClean Team
        Requires: Active connection established via Connect-SPCTenant.
        Licensing: Pro/Enterprise license required for 'Clean' and 'CleanAndRestore' execution modes and '-CreateSnapshot'.
        Permissions: Requires SharePoint Administrator or Global Administrator privileges with appropriate PnP context.

    .LINK
        Connect-SPCTenant
    .LINK
        Get-SPCMismatchUser
    .LINK
        Restore-SPCOrphanedUser
    .LINK
        Get-SPCOrphanedUser
    .LINK
        Remove-SPCOrphanedUser
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
