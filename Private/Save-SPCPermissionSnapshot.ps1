function Save-SPCPermissionSnapshot {
    <#
    .SYNOPSIS
        Saves a JSON snapshot of a user's permissions before removal per SRS 6.2.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [string] $UserLoginName,

        [Parameter(Mandatory)]
        [string] $UserDisplayName,

        [Parameter(Mandatory)]
        [string] $UserUPN,

        [Parameter(Mandatory)]
        [string] $TenantName,

        [Parameter(Mandatory)]
        [string] $SiteUrl,

        # Array of { scope: string, permissionLevel: string, inheritanceStatus: string }
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Permissions,

        # Array of { groupId: int, groupName: string }
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $GroupMemberships,

        [Parameter(Mandatory)]
        [string] $SnapshotPath
    )

    process {
        # Use List[object] so ConvertTo-Json serializes as [] not null (PS E011 pattern).
        $permList  = [System.Collections.Generic.List[object]]::new()
        if ($Permissions)      { foreach ($p in $Permissions)      { $permList.Add($p) } }
        $groupList = [System.Collections.Generic.List[object]]::new()
        if ($GroupMemberships) { foreach ($g in $GroupMemberships) { $groupList.Add($g) } }

        # PS 5.1 ConvertFrom-Json converts empty JSON array [] to $null (E013).
        # A sentinel entry keeps the array non-null; Restore-SPCOrphanedUser skips blank entries.
        if ($permList.Count -eq 0) {
            $permList.Add([ordered]@{ scope = ''; permissionLevel = ''; inheritanceStatus = '__empty' })
        }

        # SRS 6.2 schema
        $snapshot = [ordered]@{
            snapshotVersion  = '1.0'
            createdAt        = (Get-Date).ToUniversalTime().ToString('o')
            tenantName       = $TenantName
            siteUrl          = $SiteUrl
            user             = [ordered]@{
                loginName   = $UserLoginName
                displayName = $UserDisplayName
                upn         = $UserUPN
            }
            permissions      = $permList
            groupMemberships = $groupList
        }

        if (-not (Test-Path -Path $SnapshotPath)) {
            New-Item -ItemType Directory -Path $SnapshotPath -Force | Out-Null
        }

        $safeUpn  = $UserUPN -replace '[^a-zA-Z0-9@._-]', '_'
        $stamp    = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss') + 'Z'
        $filePath = Join-Path -Path $SnapshotPath -ChildPath "${safeUpn}_${stamp}.json"

        $snapshot | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8

        Write-Verbose "Snapshot saved: $filePath"
        Get-Item -Path $filePath
    }
}
