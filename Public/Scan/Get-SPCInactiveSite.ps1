function Get-SPCInactiveSite {
    <#
    .SYNOPSIS
        Identifies inactive, dormant, or stale SharePoint Online sites across the tenant.

    .DESCRIPTION
        Get-SPCInactiveSite correlates Microsoft Graph Site Usage activity metrics across 30, 90, or 180-day
        reporting windows to discover dormant site collections. It identifies sites with no recent file or page
        activity, calculates potential monthly cost avoidance, and provides actionable governance recommendations
        (e.g., 'Review with Owner', 'Set ReadOnly', or 'Archive or Delete').

    .PARAMETER InactiveDays
        The inactivity threshold in days. Sites with no recorded activity for longer than this value are flagged.
        Default is 180 days. Range: 30 to 1,825 days.

    .PARAMETER IncludeTeamSitesOnly
        Filters results to include only Microsoft 365 Group-connected Team Sites (Group-backed sites).

    .PARAMETER MinStorageMB
        Filters results to include only inactive sites consuming at least the specified storage capacity in megabytes.
        Default is 0 MB.

    .PARAMETER Top
        Limits output to the top N inactive sites with the largest storage consumption. Default is 0 (all matching sites).

    .INPUTS
        None.
            Does not accept pipeline input.

    .OUTPUTS
        SPC.InactiveSite
            Returns custom objects containing site URL, title, Group ID, template, storage used in MB,
            file count, last activity date, inactive days, lock state, owner UPN, monthly cost avoidance, and recommendation.

    .EXAMPLE
        Get-SPCInactiveSite -InactiveDays 180

        Finds all tenant sites that have had no user activity in the last 180 days.

    .EXAMPLE
        Get-SPCInactiveSite -InactiveDays 365 -MinStorageMB 10240 -Top 20

        Discovers the top 20 inactive sites that have been dormant for over a year and occupy at least 10 GB of storage.

    .EXAMPLE
        Get-SPCInactiveSite -IncludeTeamSitesOnly -InactiveDays 90 | Where-Object Recommendation -eq 'Set ReadOnly' |
            Export-SPCStorageReport -Format CSV -OutputPath 'C:\Governance'

        Finds inactive Team Sites dormant for 90+ days, filtering for sites recommended for ReadOnly locking, and exports to CSV.

    .NOTES
        Requires an active SPClean connection initialized via Connect-SPCTenant.
        Relies on Microsoft Graph Reports API (`Get-SPCGraphSiteUsageInternal`).

    .LINK
        Get-SPCStorageWaste
        Export-SPCStorageReport
    #>
    [CmdletBinding()]
    [OutputType('SPC.InactiveSite')]
    param(
        [Parameter()]
        [ValidateRange(30, 1825)]
        [int]$InactiveDays = 180,

        [Parameter()]
        [switch]$IncludeTeamSitesOnly,

        [Parameter()]
        [ValidateRange(0, [double]::MaxValue)]
        [double]$MinStorageMB = 0,

        [Parameter()]
        [ValidateRange(0, 10000)]
        [int]$Top = 0
    )

    begin {
        Test-SPCConnection
        Write-Verbose "Get-SPCInactiveSite: Querying Graph Site Usage..."
        $reportPeriod = if ($InactiveDays -gt 90) { 'D180' } elseif ($InactiveDays -gt 30) { 'D90' } else { 'D30' }
        $usageData = Get-SPCGraphSiteUsageInternal -Period $reportPeriod
        $inactiveSites = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        $now = (Get-Date).ToUniversalTime()

        if ($null -ne $usageData) {
            foreach ($row in $usageData) {
                $lastActivity = $row.LastActivityDate
                $daysInactive = if ($null -eq $lastActivity) { 9999 } else { [int]($now - $lastActivity.ToUniversalTime()).TotalDays }

                if ($daysInactive -ge $InactiveDays) {
                    if ($IncludeTeamSitesOnly -and -not $row.IsTeamSite) {
                        continue
                    }

                    if ($row.StorageUsedMB -lt $MinStorageMB) {
                        continue
                    }

                    $costAvoidance = [Math]::Round((($row.StorageUsedMB / 1024) * 0.20), 2)
                    $recommendation = if ($daysInactive -ge 365) { 'Archive or Delete' } elseif ($daysInactive -ge 180) { 'Set ReadOnly' } else { 'Review with Owner' }

                    $record = [PSCustomObject][ordered]@{
                        PSTypeName             = 'SPC.InactiveSite'
                        SiteUrl                = $row.SiteUrl
                        SiteTitle              = $row.SiteTitle
                        GroupId                = $row.GroupId
                        Template               = $row.Template
                        StorageUsedMB          = $row.StorageUsedMB
                        FileCount              = $row.FileCount
                        LastActivityDate       = $lastActivity
                        InactiveDays           = $daysInactive
                        LockState              = $row.LockState
                        OwnerUPN               = $row.OwnerUPN
                        MonthlyCostAvoidanceUSD= $costAvoidance
                        Recommendation         = $recommendation
                    }
                    $inactiveSites.Add($record)
                }
            }
        }
    }

    end {
        $sorted = $inactiveSites | Sort-Object -Property StorageUsedMB -Descending
        if ($Top -gt 0) {
            $sorted | Select-Object -First $Top
        } else {
            $sorted
        }
    }
}
