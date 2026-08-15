function Save-SPCPermissionSnapshot {
    <#
    .SYNOPSIS
        Saves a JSON snapshot of a user's permissions before removal per SRS 6.2 (Schema v1.1).
    .DESCRIPTION
        Serializes user permissions and group memberships to JSON snapshot format v1.1.
        Supports empty permission sets via isEmptyPermissionSet boolean flag and empty array [].
    .OUTPUTS
        [System.IO.FileInfo]
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

        $isEmpty = ($permList.Count -eq 0)

        # SRS 6.2 schema v1.1
        $snapshot = [ordered]@{
            '$schema'            = 'https://m365automation.com/schemas/spclean/snapshot-v1.1.json'
            snapshotVersion      = '1.1'
            createdAt            = (Get-Date).ToUniversalTime().ToString('o')
            tenantName           = $TenantName
            siteUrl              = $SiteUrl
            user                 = [ordered]@{
                loginName   = $UserLoginName
                displayName = $UserDisplayName
                upn         = $UserUPN
            }
            isEmptyPermissionSet = $isEmpty
            permissions          = $permList
            groupMemberships     = $groupList
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
