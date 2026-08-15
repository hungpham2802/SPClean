function Optimize-SPCFileVersion {
    <#
    .SYNOPSIS
        Optimizes document library storage by safely trimming redundant historical file versions.

    .DESCRIPTION
        Optimize-SPCFileVersion trims old historical file versions across document libraries within a SharePoint
        Online site collection based on configurable version count (-KeepVersions) and age (-OlderThanDays) criteria.

        Key Capabilities:
        - Version Trimming: Identifies and deletes excessive intermediate versions while preserving the latest major versions.
        - Library Policy Adjustment: Optionally updates document library settings (-ApplyPolicyToLibrary) to enforce
          MajorVersionLimit going forward, preventing future version sprawl.
        - Simulation & Safety: Fully supports -DryRun and -WhatIf modes to preview potential storage reclamation before taking action.
        - Immutable Audit Logging: Detailed logs recording every file processed, versions removed, and bytes freed are saved to CSV.

    .PARAMETER SiteUrl
        The full URL of the SharePoint Online site collection to optimize.
        Supports pipeline input by value and property name.

    .PARAMETER LibraryTitle
        Optional list of document library titles to optimize. When omitted, all visible, non-system document
        libraries in the site collection are processed.

    .PARAMETER KeepVersions
        The number of recent major historical versions to retain for each file. Default is 50. Range: 1 to 50,000.

    .PARAMETER OlderThanDays
        The minimum age (in days) that a version must have to be eligible for trimming. Default is 90 days. Range: 0 to 3,650.

    .PARAMETER ApplyPolicyToLibrary
        When specified, updates the document library configuration's MajorVersionLimit to match -KeepVersions.

    .PARAMETER DryRun
        Executes in simulation mode. No versions are removed and no policies are changed, but storage savings are calculated.

    .PARAMETER AuditLogPath
        Custom file path for the append-only CSV audit log. If omitted, a timestamped CSV file is created in the current directory.

    .PARAMETER Force
        Suppresses interactive confirmation prompts during execution.

    .INPUTS
        System.String
            Accepts site collection URLs from the pipeline.

    .OUTPUTS
        SPC.FileVersionOptimizeResult
            Returns custom objects containing site URL, count of libraries processed, files optimized, versions removed,
            storage freed in MB, monthly/annual cost savings in USD, policy update status, simulation flag, and audit log path.

    .EXAMPLE
        Optimize-SPCFileVersion -SiteUrl 'https://contoso.sharepoint.com/sites/Engineering' -KeepVersions 30 -OlderThanDays 60 -DryRun

        Simulates trimming file versions older than 60 days while retaining 30 versions on the Engineering site.

    .EXAMPLE
        Optimize-SPCFileVersion -SiteUrl 'https://contoso.sharepoint.com/sites/Marketing' -LibraryTitle 'Brand Assets' -KeepVersions 20 -ApplyPolicyToLibrary -Force

        Trims redundant versions in the 'Brand Assets' library and configures the library to retain a maximum of 20 major versions.

    .EXAMPLE
        Get-SPCVersionWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Finance' | Where-Object BloatRatio -gt 2.0 | ForEach-Object {
            Optimize-SPCFileVersion -SiteUrl $_.SiteUrl -LibraryTitle $_.LibraryTitle -KeepVersions 50 -OlderThanDays 90
        }

        Identifies bloated document libraries using Get-SPCVersionWaste and immediately optimizes them.

    .NOTES
        Requires an active SPClean connection initialized via Connect-SPCTenant.
        Live execution requires a Pro or Consultant tier license.

    .LINK
        Get-SPCVersionWaste
        Get-SPCStorageWaste
        Export-SPCStorageReport
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType('SPC.FileVersionOptimizeResult')]
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
        [switch]$ApplyPolicyToLibrary,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [string]$AuditLogPath,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Test-SPCConnection
        $isSimulation = $DryRun.IsPresent -or $WhatIfPreference

        if (-not $isSimulation) {
            Assert-SPCProLicense -Feature 'Optimize-SPCFileVersion'
        }

        if ([string]::IsNullOrWhiteSpace($AuditLogPath)) {
            $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
            $AuditLogPath = Join-Path (Get-Location) "SPClean_VersionTrim_Audit_$timestamp.csv"
        }
    }

    process {
        if (-not $Force -and -not $isSimulation) {
            if (-not $PSCmdlet.ShouldProcess("Site: $SiteUrl [KeepVersions: $KeepVersions, OlderThan: $OlderThanDays days]", "Trim File Versions")) {
                return
            }
        }

        $trimResult = Invoke-SPCVersionTrimmingInternal `
            -SiteUrl $SiteUrl `
            -LibraryTitle $LibraryTitle `
            -KeepVersions $KeepVersions `
            -OlderThanDays $OlderThanDays `
            -ApplyPolicy $ApplyPolicyToLibrary.IsPresent `
            -DryRun $isSimulation `
            -AuditLogPath $AuditLogPath

            $freedMB = if ($null -ne $trimResult -and $null -ne $trimResult.StorageFreedMB) { $trimResult.StorageFreedMB } else { 0.0 }
            $monthlySaved = [Math]::Round((($freedMB / 1024) * 0.20), 2)
            $annualSaved  = [Math]::Round(($monthlySaved * 12), 2)

            $libProcessed = if ($null -ne $trimResult -and $null -ne $trimResult.LibrariesProcessed) { $trimResult.LibrariesProcessed } else { 0 }
            $filesOptimized = if ($null -ne $trimResult -and $null -ne $trimResult.FilesOptimizedCount) { $trimResult.FilesOptimizedCount } else { 0 }
            $verRemoved = if ($null -ne $trimResult -and $null -ne $trimResult.VersionsRemovedCount) { $trimResult.VersionsRemovedCount } else { 0 }

            [PSCustomObject][ordered]@{
                PSTypeName           = 'SPC.FileVersionOptimizeResult'
                SiteUrl              = $SiteUrl
                LibrariesProcessed   = $libProcessed
                FilesOptimizedCount  = $filesOptimized
                VersionsRemovedCount = $verRemoved
                StorageFreedMB       = $freedMB
                MonthlyCostSavedUSD  = $monthlySaved
                AnnualCostSavedUSD   = $annualSaved
                PolicyUpdated        = $ApplyPolicyToLibrary.IsPresent
                IsDryRun             = $isSimulation
                AuditLogFilePath     = $AuditLogPath
                ExecutedAt           = (Get-Date).ToUniversalTime()
            }
    }
}
