function Get-SPCPreservationHoldWaste {
    <#
    .SYNOPSIS
        Audits Preservation Hold Library (PHL) storage consumption and compliance hold locks.

    .DESCRIPTION
        Get-SPCPreservationHoldWaste discovers and measures the storage consumed by Preservation Hold Libraries (PHL)
        across SharePoint Online sites. These libraries are automatically provisioned and managed by Microsoft Purview
        Retention Policies, Retention Labels, or eDiscovery / Litigation Holds.

        Items inside a Preservation Hold Library are legally locked and cannot be directly deleted or altered by
        administrators. This cmdlet provides visibility into PHL storage growth, flags compliance hold statuses,
        and assigns risk alert levels (Normal, Warning, Critical) based on user-defined capacity thresholds.

    .PARAMETER SiteUrl
        One or more SharePoint Online site collection URLs to audit. When omitted, all sites in the tenant
        are evaluated using Microsoft Graph usage reports.
        Supports pipeline input by value and property name.

    .PARAMETER WarningThresholdMB
        The storage threshold in megabytes for triggering a 'Warning' alert level. Sites with PHL storage
        exceeding 2x this threshold are categorized as 'Critical'. Default is 5120 MB (5 GB).
        Range: 1 to 1,048,576 MB.

    .INPUTS
        System.String[]
            Accepts site collection URLs from the pipeline.

    .OUTPUTS
        SPC.PreservationHoldWaste
            Returns custom objects containing site URL, title, PHL presence, file count, size in MB,
            percentage of total site storage consumed by PHL, compliance hold state, alert level, and compliance notes.

    .EXAMPLE
        Get-SPCPreservationHoldWaste -SiteUrl 'https://contoso.sharepoint.com/sites/LegalArchive'

        Audits the Preservation Hold Library on the 'LegalArchive' site, measuring file count and size.

    .EXAMPLE
        Get-SPCPreservationHoldWaste -WarningThresholdMB 10240 | Where-Object AlertLevel -in @('Warning', 'Critical')

        Scans the entire tenant for Preservation Hold Libraries exceeding 10 GB (Warning) or 20 GB (Critical).

    .EXAMPLE
        Get-SPCPreservationHoldWaste -SiteUrl (Get-Content C:\sites.txt) | Export-Csv -Path 'C:\PHL_Audit.csv' -NoTypeInformation

        Audits a batch of site collections from a text file and exports the compliance hold metrics to CSV.

    .NOTES
        Requires an active SPClean connection initialized via Connect-SPCTenant.
        Preservation Hold Libraries are immutable by design and cannot be purged directly without modifying
        retention policies in Microsoft Purview Compliance Center.

    .LINK
        Get-SPCStorageWaste
        Get-SPCVersionWaste
        Export-SPCStorageReport
    #>
    [CmdletBinding(DefaultParameterSetName = 'AllSites')]
    [OutputType('SPC.PreservationHoldWaste')]
    param(
        [Parameter(ParameterSetName = 'SpecificSites', ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$SiteUrl,

        [Parameter()]
        [ValidateRange(1, 1048576)]
        [double]$WarningThresholdMB = 5120
    )

    begin {
        Test-SPCConnection
        $pipelineUrls = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($SiteUrl) {
            foreach ($url in $SiteUrl) {
                if (-not [string]::IsNullOrWhiteSpace($url)) {
                    $pipelineUrls.Add($url)
                }
            }
        }
    }

    end {
        $targetUrls = if ($pipelineUrls.Count -gt 0) {
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

        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($url in $targetUrls) {
            try {
                $siteConn = Connect-SPCSiteInternal -SiteUrl $url -Context $script:SPCContext
                $web = Get-PnPWeb -Connection $siteConn
                $siteTitle = if ($null -ne $web -and $null -ne $web.Title) { $web.Title } else { 'Site' }

                $phlList = Get-PnPList -Identity "PreservationHoldLibrary" -Connection $siteConn -ErrorAction SilentlyContinue
                if ($null -eq $phlList) {
                    $phlList = Get-PnPList -Identity "Preservation Hold Library" -Connection $siteConn -ErrorAction SilentlyContinue
                }

                $site = Get-PnPSite -Connection $siteConn
                if ($null -ne $site -and ($null -eq $site.Usage -or $null -eq $site.Usage.Storage)) {
                    Get-PnPProperty -ClientObject $site -Property Usage -Connection $siteConn -ErrorAction SilentlyContinue | Out-Null
                }
                $storageBytes = if ($null -ne $site -and $null -ne $site.Usage -and $null -ne $site.Usage.Storage) { [int64]$site.Usage.Storage } else { [int64]0 }
                $totalSiteMB = [Math]::Round(($storageBytes / 1MB), 2)

                if ($null -ne $phlList) {
                    $items = Get-PnPListItem -List $phlList -Connection $siteConn -PageSize 1000
                    $phlBytes = [int64]0
                    if ($null -ne $items) {
                        foreach ($it in $items) {
                            $fSize = 0
                            if ($it -is [System.Collections.IDictionary] -or $null -ne $it['File_x0020_Size']) {
                                $fSize = $it['File_x0020_Size']
                            } elseif ($it.File_x0020_Size) {
                                $fSize = $it.File_x0020_Size
                            }
                            $phlBytes += [int64]$fSize
                        }
                    }
                    $phlSizeMB = [Math]::Round(($phlBytes / 1MB), 2)
                    $pctSite = if ($totalSiteMB -gt 0) { [Math]::Round(($phlSizeMB / $totalSiteMB * 100), 2) } else { 0.0 }
                    
                    $alertLevel = if ($phlSizeMB -ge ($WarningThresholdMB * 2)) { 'Critical' } elseif ($phlSizeMB -ge $WarningThresholdMB) { 'Warning' } else { 'Normal' }

                    $results.Add([PSCustomObject][ordered]@{
                        PSTypeName           = 'SPC.PreservationHoldWaste'
                        SiteUrl              = $url
                        SiteTitle            = $siteTitle
                        HasPreservationHold  = $true
                        PHLFileCount         = $phlList.ItemCount
                        PHLSizeMB            = $phlSizeMB
                        PercentOfSiteStorage = $pctSite
                        ComplianceHoldActive = $true
                        AlertLevel           = $alertLevel
                        ComplianceNote       = 'Under Microsoft Purview Retention Policy - Immutable'
                    })
                } else {
                    $results.Add([PSCustomObject][ordered]@{
                        PSTypeName           = 'SPC.PreservationHoldWaste'
                        SiteUrl              = $url
                        SiteTitle            = $siteTitle
                        HasPreservationHold  = $false
                        PHLFileCount         = 0
                        PHLSizeMB            = 0.0
                        PercentOfSiteStorage = 0.0
                        ComplianceHoldActive = $false
                        AlertLevel           = 'Normal'
                        ComplianceNote       = 'No active PHL detected'
                    })
                }
            }
            catch {
                Write-Warning "Get-SPCPreservationHoldWaste: Error querying site '$url': $($_.Exception.Message)"
            }
        }
        $results | ForEach-Object { $_ }
    }
}
