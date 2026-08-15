function Get-SPCStorageWaste {
    <#
    .SYNOPSIS
        Scans SharePoint Online sites to quantify storage waste and identify cost optimization opportunities.

    .DESCRIPTION
        Get-SPCStorageWaste analyzes SharePoint Online site collections to detect and measure storage consumption
        across critical waste vectors: first-stage recycle bin, second-stage recycle bin, historical document
        version sprawl, and Preservation Hold Libraries (PHL).

        The cmdlet calculates financial waste based on the standard Microsoft 365 SharePoint extra storage cost
        model ($0.20/GB/month or $2,400/TB/year), enabling IT Administrators and Directors to quantify immediate
        cost avoidance and reclaim storage capacity before reaching tenant quota limits.

    .PARAMETER SiteUrl
        One or more SharePoint Online site collection URLs to scan. When omitted, all sites in the tenant
        are enumerated and evaluated using Microsoft Graph usage reports.
        Supports pipeline input by value and property name.

    .PARAMETER IncludeRecycleBin
        Specifies whether to inspect first-stage (End-User) and second-stage (Site Collection Administrator)
        recycle bins. Enabled by default ($true).

    .PARAMETER IncludeVersions
        When specified, performs an in-depth version sprawl analysis across document libraries to calculate
        prunable version storage (simulating a 50-version, 90-day retention threshold).

    .PARAMETER IncludePreservationHold
        When specified, audits the Preservation Hold Library (PHL) created by Microsoft Purview retention
        and eDiscovery holds to measure locked storage consumption.

    .PARAMETER Top
        Limits the output to the top N sites with the highest total recoverable waste (in MB). Default is 0 (all sites).

    .INPUTS
        System.String[]
            Accepts site collection URLs from the pipeline.

    .OUTPUTS
        SPC.StorageWasteSummary
            Returns custom objects containing site storage metrics, recycle bin breakdowns, version waste,
            preservation hold usage, total waste in MB, and potential monthly/annual cost savings in USD.

    .EXAMPLE
        Get-SPCStorageWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Marketing' -IncludeVersions -IncludePreservationHold

        Scans the 'Marketing' site collection, performing a full audit including 1st/2nd stage recycle bins,
        document version sprawl, and Preservation Hold Library sizes.

    .EXAMPLE
        Get-SPCStorageWaste -Top 10 -IncludeVersions | Export-SPCStorageReport -Format HTML -OutputPath 'C:\Reports'

        Discovers all tenant sites, identifies the top 10 sites with the highest storage waste including version sprawl,
        and generates an interactive executive HTML ROI dashboard.

    .EXAMPLE
        $sites = @('https://contoso.sharepoint.com/sites/Legal', 'https://contoso.sharepoint.com/sites/Engineering')
        $sites | Get-SPCStorageWaste -IncludeRecycleBin | Where-Object TotalWasteMB -gt 51200 | ForEach-Object {
            Clear-SPCRecycleBin -SiteUrl $_.SiteUrl -OlderThanDays 30 -DryRun
        }

        Pipes specific high-capacity sites into Get-SPCStorageWaste, filters for sites with more than 50 GB of waste,
        and previews safe recycle bin remediation using -DryRun.

    .NOTES
        Requires an active SPClean connection initialized via Connect-SPCTenant.
        When scanning all sites without specifying -SiteUrl, Microsoft Graph Site Usage reports are utilized.

    .LINK
        Get-SPCVersionWaste
    .LINK
        Get-SPCPreservationHoldWaste
    .LINK
        Get-SPCInactiveSite
    .LINK
        Clear-SPCRecycleBin
    .LINK
        Export-SPCStorageReport
    #>
    [CmdletBinding(DefaultParameterSetName = 'AllSites')]
    [OutputType('SPC.StorageWasteSummary')]
    param(
        [Parameter(ParameterSetName = 'SpecificSites', Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$SiteUrl,

        [Parameter()]
        [switch]$IncludeRecycleBin = $true,

        [Parameter()]
        [switch]$IncludeVersions,

        [Parameter()]
        [switch]$IncludePreservationHold,

        [Parameter()]
        [ValidateRange(0, 50000)]
        [int]$Top = 0
    )

    begin {
        Test-SPCConnection
        Write-Verbose "Get-SPCStorageWaste: Initializing discovery scan. IncludeRecycleBin=$IncludeRecycleBin, IncludeVersions=$IncludeVersions, IncludePHL=$IncludePreservationHold"
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
        $pipelineUrls = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'SpecificSites') {
            foreach ($url in $SiteUrl) {
                if (-not [string]::IsNullOrWhiteSpace($url)) {
                    $pipelineUrls.Add($url)
                }
            }
        }
    }

    end {
        $targetUrls = if ($PSCmdlet.ParameterSetName -eq 'SpecificSites') {
            $pipelineUrls
        } else {
            $usageReport = Get-SPCGraphSiteUsageInternal -Period 'D7'
            $urls = [System.Collections.Generic.List[string]]::new()
            if ($null -ne $usageReport) {
                foreach ($row in $usageReport) {
                    if (-not [string]::IsNullOrWhiteSpace($row.SiteUrl)) {
                        $urls.Add($row.SiteUrl)
                    }
                }
            }
            $urls
        }

        $totalSites = $targetUrls.Count
        $currentIndex = 0

        foreach ($url in $targetUrls) {
            $currentIndex++
            Write-Progress -Activity "Scanning Storage Waste" -Status ("Processing site {0} of {1}: {2}" -f $currentIndex, $totalSites, $url) -PercentComplete (($currentIndex / [Math]::Max(1, $totalSites)) * 100)

            try {
                $siteConn = Connect-SPCSiteInternal -SiteUrl $url -Context $script:SPCContext
                $web = Get-PnPWeb -Connection $siteConn
                $site = Get-PnPSite -Connection $siteConn
                if ($null -ne $site -and ($null -eq $site.Usage -or $null -eq $site.Usage.Storage)) {
                    Get-PnPProperty -ClientObject $site -Property Usage -Connection $siteConn -ErrorAction SilentlyContinue | Out-Null
                }

                $storageUsedMB = if ($null -ne $site.Usage -and $null -ne $site.Usage.Storage) { [Math]::Round(($site.Usage.Storage / 1MB), 2) } else { 0.0 }
                $storageAllocatedMB = if ($null -ne $site.Usage -and $null -ne $site.Usage.StorageQuota) { [Math]::Round(($site.Usage.StorageQuota / 1MB), 2) } else { 0.0 }
                $storageUsedPercent = if ($storageAllocatedMB -gt 0) { [Math]::Round(($storageUsedMB / $storageAllocatedMB) * 100, 2) } else { 0.0 }

                # 1. Recycle Bin
                $rb1MB = 0.0
                $rb2MB = 0.0
                if ($IncludeRecycleBin) {
                    $allRbItems = Get-PnPRecycleBinItem -Connection $siteConn -RowLimit 5000
                    $rbItems1 = if ($null -ne $allRbItems) { @($allRbItems | Where-Object { $_.ItemState -eq 'FirstStageRecycleBin' }) } else { @() }
                    $rbItems2 = if ($null -ne $allRbItems) { @($allRbItems | Where-Object { $_.ItemState -eq 'SecondStageRecycleBin' }) } else { @() }
                    $rb1MB = [Math]::Round((($rbItems1 | Measure-Object -Property Size -Sum).Sum / 1MB), 2)
                    $rb2MB = [Math]::Round((($rbItems2 | Measure-Object -Property Size -Sum).Sum / 1MB), 2)
                }
                $totalRecycleBinMB = [Math]::Round(($rb1MB + $rb2MB), 2)

                # 2. Version Waste
                $versionWasteMB = 0.0
                if ($IncludeVersions) {
                    $vw = Get-SPCVersionWaste -SiteUrl $url -KeepVersions 50 -OlderThanDays 90 -ErrorAction SilentlyContinue
                    if ($null -ne $vw) {
                        $versionWasteMB = [Math]::Round((($vw | Measure-Object -Property RecoverableStorageMB -Sum).Sum), 2)
                    }
                }

                # 3. Preservation Hold Library
                $phlMB = 0.0
                if ($IncludePreservationHold) {
                    $phl = Get-SPCPreservationHoldWaste -SiteUrl @($url) -ErrorAction SilentlyContinue
                    if ($null -ne $phl) {
                        $phlMB = [Math]::Round((($phl | Measure-Object -Property PHLSizeMB -Sum).Sum), 2)
                    }
                }

                # Note: PreservationHoldMB is excluded from TotalWasteMB because PHL is compliance-locked
                # by Microsoft Purview policies and cannot be purged via standard remediation cmdlets.
                $totalWasteMB = [Math]::Round(($totalRecycleBinMB + $versionWasteMB), 2)
                $potentialMonthlyUSD = [Math]::Round((($totalWasteMB / 1024) * 0.20), 2)
                $potentialAnnualUSD  = [Math]::Round(($potentialMonthlyUSD * 12), 2)

                $siteTitle = if ($null -ne $web -and $null -ne $web.Title) { $web.Title } else { 'Site' }

                $record = [PSCustomObject][ordered]@{
                    PSTypeName                = 'SPC.StorageWasteSummary'
                    SiteUrl                   = $url
                    SiteTitle                 = $siteTitle
                    StorageUsedMB             = $storageUsedMB
                    StorageAllocatedMB        = $storageAllocatedMB
                    StorageUsedPercent        = $storageUsedPercent
                    RecycleBin1stStageMB      = $rb1MB
                    RecycleBin2ndStageMB      = $rb2MB
                    TotalRecycleBinMB         = $totalRecycleBinMB
                    VersionWasteMB            = $versionWasteMB
                    PreservationHoldMB        = $phlMB
                    TotalWasteMB              = $totalWasteMB
                    PotentialMonthlySavingUSD = $potentialMonthlyUSD
                    PotentialAnnualSavingUSD  = $potentialAnnualUSD
                    ScannedAt                 = (Get-Date).ToUniversalTime()
                }
                $results.Add($record)
            }
            catch {
                Write-Warning "Get-SPCStorageWaste: Failed to scan site '$url': $($_.Exception.Message)"
            }
        }

        Write-Progress -Activity "Scanning Storage Waste" -Completed
        $sorted = $results | Sort-Object -Property TotalWasteMB -Descending
        if ($Top -gt 0) {
            $sorted | Select-Object -First $Top
        } else {
            $sorted
        }
    }
}
