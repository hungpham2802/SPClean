function Get-SPCVersionWaste {
    <#
    .SYNOPSIS
        Analyzes document library file version sprawl and calculates recoverable storage capacity.

    .DESCRIPTION
        Get-SPCVersionWaste inspects document libraries within a SharePoint Online site collection to measure
        the storage footprint consumed by historical file versions. It calculates total current file size versus
        historical version size and determines the bloat ratio.

        Based on simulated retention policies (-KeepVersions and -OlderThanDays), the cmdlet calculates exact
        recoverable storage in megabytes and identifies bloated individual files that consume disproportionate
        storage capacity.

    .PARAMETER SiteUrl
        The full URL of the SharePoint Online site collection to inspect.
        Supports pipeline input by value and property name.

    .PARAMETER LibraryTitle
        Optional list of specific document library titles to analyze. When omitted, all visible, non-system
        document libraries are evaluated.

    .PARAMETER KeepVersions
        The number of major historical versions to simulate retaining for each file. Default is 50.
        Versions exceeding this count are calculated as prunable/recoverable. Range: 1 to 50,000.

    .PARAMETER OlderThanDays
        The age threshold in days for historical versions to be eligible for pruning. Default is 90 days.
        Versions newer than this threshold are preserved in simulation calculations. Range: 0 to 3,650.

    .PARAMETER TopFiles
        Maximum number of bloated files to include in the TopBloatedFiles property per library. Default is 50.
        Range: 1 to 500.

    .INPUTS
        System.String
            Accepts site collection URLs from the pipeline.

    .OUTPUTS
        SPC.VersionWasteDetail
            Returns custom objects containing library-level metrics, item count, current vs history storage,
            bloat ratio, simulated recoverable storage (MB and percentage), and a collection of top bloated files.

    .EXAMPLE
        Get-SPCVersionWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Finance'

        Analyzes all document libraries in the Finance site using default thresholds (keep 50 versions, older than 90 days).

    .EXAMPLE
        Get-SPCVersionWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Engineering' -LibraryTitle 'Project CAD Files' -KeepVersions 20 -OlderThanDays 60

        Analyzes the 'Project CAD Files' library, simulating an aggressive version retention policy keeping 20 versions older than 60 days.

    .EXAMPLE
        Get-SPCVersionWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Legal' | Where-Object BloatRatio -gt 3.0 | ForEach-Object {
            Optimize-SPCFileVersion -SiteUrl $_.SiteUrl -LibraryTitle $_.LibraryTitle -KeepVersions 50 -OlderThanDays 90 -DryRun
        }

        Identifies document libraries where version history is more than 3x larger than the active files, and pipes them to Optimize-SPCFileVersion for preview.

    .NOTES
        Requires an active SPClean connection initialized via Connect-SPCTenant.
        Does NOT modify or trim any file versions; use Optimize-SPCFileVersion for remediation.

    .LINK
        Optimize-SPCFileVersion
    .LINK
        Get-SPCStorageWaste
    .LINK
        Export-SPCStorageReport
    #>
    [CmdletBinding()]
    [OutputType('SPC.VersionWasteDetail')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteUrl,

        [Parameter()]
        [string[]]$LibraryTitle,

        [Parameter()]
        [ValidateRange(1, 50000)]
        [int]$KeepVersions = 50,

        [Parameter()]
        [ValidateRange(0, 3650)]
        [int]$OlderThanDays = 90,

        [Parameter()]
        [ValidateRange(1, 500)]
        [int]$TopFiles = 50
    )

    begin {
        Test-SPCConnection
    }

    process {
        $siteConn = Connect-SPCSiteInternal -SiteUrl $SiteUrl -Context $script:SPCContext
        $lists = Get-PnPList -Connection $siteConn

        $docLibs = @()
        if ($null -ne $lists) {
            $docLibs = @($lists | Where-Object {
                $_.BaseTemplate -eq 101 -and -not $_.Hidden -and
                $_.Title -notin @('FormServerTemplates', 'Style Library', 'PreservationHoldLibrary', 'Preservation Hold Library', 'Site Assets', 'Site Pages')
            })
        }

        if ($LibraryTitle) {
            $docLibs = @($docLibs | Where-Object { $_.Title -in $LibraryTitle })
        }

        foreach ($lib in $docLibs) {
            Write-Verbose "Analyzing Library: $($lib.Title) on $SiteUrl"
            $items = Get-PnPListItem -List $lib -Connection $siteConn -PageSize 500
            
            $currentSizeTotal = 0.0
            $historySizeTotal = 0.0
            $recoverableTotal = 0.0
            $bloatedFilesList = [System.Collections.Generic.List[PSCustomObject]]::new()
            $now = (Get-Date).ToUniversalTime()

            if ($null -ne $items) {
                foreach ($item in $items) {
                    $isItemFile = if ($item.FileSystemObjectType) {
                        $item.FileSystemObjectType.ToString() -eq 'File'
                    } else { $true }

                    if ($isItemFile) {
                        $file = Get-PnPProperty -ClientObject $item -Property File -Connection $siteConn
                        $targetObj = if ($null -ne $file) { $file } else { $item }
                        $versions = Get-PnPProperty -ClientObject $targetObj -Property Versions -Connection $siteConn
                        
                        $fileLength = [int64]0
                        if ($null -ne $file -and $null -ne $file.Length) {
                            $fileLength = [int64]$file.Length
                        } elseif ($null -ne $item.Length) {
                            $fileLength = [int64]$item.Length
                        }
                        $fileSizeMB = [Math]::Round(($fileLength / 1MB), 4)
                        $currentSizeTotal += $fileSizeMB

                        $verCount = if ($null -ne $versions) { $versions.Count } else { 0 }
                        if ($verCount -gt 0) {
                            $verSizeMB = [Math]::Round((($versions | Measure-Object -Property Length -Sum).Sum / 1MB), 4)
                            $historySizeTotal += $verSizeMB

                            # Calculate recoverable based on simulated KeepVersions and OlderThanDays
                            $prunableVersions = @($versions | Where-Object {
                                if ($null -ne $_.Created) {
                                    $vAgeDays = ($now - $_.Created.ToUniversalTime()).TotalDays
                                    $vAgeDays -ge $OlderThanDays
                                } else { $false }
                            })

                            $prunableByCount = if ($verCount -gt $KeepVersions) {
                                @($versions | Select-Object -First ($verCount - $KeepVersions))
                            } else { @() }

                            $combinedPrune = [System.Collections.Generic.List[object]]::new()
                            foreach ($pv in $prunableVersions) { $combinedPrune.Add($pv) }
                            foreach ($pc in $prunableByCount) {
                                if (-not ($combinedPrune | Where-Object { $_.VersionLabel -eq $pc.VersionLabel })) {
                                    $combinedPrune.Add($pc)
                                }
                            }

                            $recoverableFileMB = [Math]::Round((($combinedPrune | Measure-Object -Property Length -Sum).Sum / 1MB), 4)
                            $recoverableTotal += $recoverableFileMB

                            if ($verSizeMB -gt 1.0) {
                                $bloatedFilesList.Add([PSCustomObject]@{
                                    FileUrl             = $item['FileRef']
                                    FileName            = $item['FileLeafRef']
                                    VersionCount        = $verCount
                                    CurrentSizeMB       = $fileSizeMB
                                    VersionsSizeMB      = $verSizeMB
                                    RecoverableMB       = $recoverableFileMB
                                })
                            }
                        }
                    }
                }
            }

            $totalLibMB = [Math]::Round(($currentSizeTotal + $historySizeTotal), 2)
            $bloatRatio = if ($currentSizeTotal -gt 0) { [Math]::Round(($totalLibMB / $currentSizeTotal), 2) } else { 1.0 }
            $recovPct   = if ($totalLibMB -gt 0) { [Math]::Round(($recoverableTotal / $totalLibMB * 100), 2) } else { 0.0 }

            $topBloated = @($bloatedFilesList | Sort-Object -Property RecoverableMB -Descending | Select-Object -First $TopFiles)

            [PSCustomObject][ordered]@{
                PSTypeName               = 'SPC.VersionWasteDetail'
                SiteUrl                  = $SiteUrl
                LibraryTitle             = $lib.Title
                ItemCount                = $lib.ItemCount
                CurrentFilesSizeMB       = [Math]::Round($currentSizeTotal, 2)
                HistoricalVersionsSizeMB = [Math]::Round($historySizeTotal, 2)
                TotalLibrarySizeMB       = $totalLibMB
                BloatRatio               = $bloatRatio
                ConfiguredMaxVersions    = $lib.MajorVersionLimit
                SimulatedKeepVersions    = $KeepVersions
                RecoverableStorageMB     = [Math]::Round($recoverableTotal, 2)
                RecoverablePercent       = $recovPct
                TopBloatedFiles          = $topBloated
            }
        }
    }
}
