function Export-SPCStorageReport {
    <#
    .SYNOPSIS
        Generates Executive HTML ROI Dashboards and CSV reports for SharePoint Online storage optimization.

    .DESCRIPTION
        Export-SPCStorageReport compiles storage waste, inactive sites, version sprawl, and preservation hold audit data
        into standalone Executive HTML Dashboards and structured CSV reports.

        Key Features:
        - Financial ROI Calculations: Quantifies reclaimed capacity in gigabytes and calculates immediate monthly and
          annualized dollar savings using custom unit storage pricing ($0.20/GB/month default).
        - Multi-Format Export: Supports HTML, CSV, or both (All).
        - White-Label Branding: Pro and Consultant tiers unlock custom company logo URLs and client names for MSPs and consultants.

    .PARAMETER StorageWasteData
        An array of storage waste objects output by Get-SPCStorageWaste.
        Accepts pipeline input.

    .PARAMETER InactiveSiteData
        Optional array of inactive site objects output by Get-SPCInactiveSite to embed into the report.

    .PARAMETER VersionWasteData
        Optional array of document library version sprawl details output by Get-SPCVersionWaste.

    .PARAMETER PreservationHoldData
        Optional array of Preservation Hold Library audit objects output by Get-SPCPreservationHoldWaste.

    .PARAMETER OutputPath
        The directory path where generated HTML and CSV report files will be saved. Default is '.\Reports'.

    .PARAMETER Format
        The export format: 'HTML', 'CSV', or 'All'. Default is 'All'. Note that HTML requires a Pro or Consultant license.

    .PARAMETER UnitPricePerGB
        The monthly cost in USD per gigabyte of extra SharePoint Online storage. Default is 0.20 ($0.20/GB/month).
        Range: 0.01 to 10.0.

    .PARAMETER CompanyLogoUrl
        Custom URL or data URI for company branding logo on the HTML dashboard. Requires Consultant license.

    .PARAMETER ClientName
        Custom client or organization name displayed on the HTML dashboard. Requires Consultant license.

    .INPUTS
        SPC.StorageWasteSummary[]
            Accepts storage waste objects from the pipeline.

    .OUTPUTS
        SPC.ReportExportSummary
            Returns a custom summary object containing paths to generated HTML and CSV files, total waste in GB,
            and estimated monthly/annual cost savings.

    .EXAMPLE
        Get-SPCStorageWaste -Top 20 | Export-SPCStorageReport -Format All -OutputPath 'C:\StorageReports'

        Generates both HTML Executive Dashboard and CSV reports for the top 20 storage-wasting sites.

    .EXAMPLE
        $waste = Get-SPCStorageWaste -IncludeVersions
        $inactive = Get-SPCInactiveSite -InactiveDays 180
        $versions = Get-SPCVersionWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Legal'
        Export-SPCStorageReport -StorageWasteData $waste -InactiveSiteData $inactive -VersionWasteData $versions -Format HTML

        Combines storage waste, inactive sites, and detailed version bloat into a comprehensive Executive HTML Dashboard.

    .EXAMPLE
        Get-SPCStorageWaste | Export-SPCStorageReport -Format HTML -CompanyLogoUrl 'https://contoso.com/logo.png' -ClientName 'Fabrikam Corp' -UnitPricePerGB 0.25

        Generates a white-labeled client report for an MSP engagement with custom pricing of $0.25/GB/mo.

    .NOTES
        HTML report generation requires a Pro or Consultant tier license.
        Custom branding (-CompanyLogoUrl, -ClientName) requires a Consultant tier license.

    .LINK
        Get-SPCStorageWaste
        Get-SPCInactiveSite
        Get-SPCVersionWaste
        Get-SPCPreservationHoldWaste
    #>
    [CmdletBinding()]
    [OutputType('SPC.ReportExportSummary')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [PSCustomObject[]]$StorageWasteData,

        [Parameter()]
        [PSCustomObject[]]$InactiveSiteData,

        [Parameter()]
        [PSCustomObject[]]$VersionWasteData,

        [Parameter()]
        [PSCustomObject[]]$PreservationHoldData,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = ".\Reports",

        [Parameter()]
        [ValidateSet('HTML', 'CSV', 'All')]
        [string]$Format = 'All',

        [Parameter()]
        [ValidateRange(0.01, 10.0)]
        [double]$UnitPricePerGB = 0.20,

        [Parameter()]
        [string]$CompanyLogoUrl,

        [Parameter()]
        [string]$ClientName
    )

    begin {
        Test-SPCConnection

        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }

        $isHtmlRequested = $Format -in @('HTML', 'All')
        if ($isHtmlRequested) {
            Assert-SPCProLicense -Feature 'Export-SPCStorageReport:HTML'
        }

        if (-not [string]::IsNullOrWhiteSpace($CompanyLogoUrl) -or -not [string]::IsNullOrWhiteSpace($ClientName)) {
            Assert-SPCConsultantLicense -Feature 'Export-SPCStorageReport:WhiteLabel'
        }

        $allStorageWaste = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        if ($StorageWasteData) {
            foreach ($item in $StorageWasteData) {
                $allStorageWaste.Add($item)
            }
        }
    }

    end {
        $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $wasteArray = $allStorageWaste.ToArray()
        
        $csvSummaryPath = $null
        $csvInactivePath = $null
        $htmlPath = $null

        # 1. Export CSV
        if ($Format -in @('CSV', 'All')) {
            $csvSummaryPath = Join-Path $OutputPath "Storage_Waste_Summary_$timestamp.csv"
            $wasteArray | Export-Csv -Path $csvSummaryPath -NoTypeInformation -Encoding UTF8

            if ($InactiveSiteData) {
                $csvInactivePath = Join-Path $OutputPath "Inactive_Sites_$timestamp.csv"
                $InactiveSiteData | Export-Csv -Path $csvInactivePath -NoTypeInformation -Encoding UTF8
            }
        }

        # 2. Export HTML Dashboard
        if ($isHtmlRequested) {
            $htmlPath = Join-Path $OutputPath "SPClean_Storage_ROI_Dashboard_$timestamp.html"
            $targetLogo = $CompanyLogoUrl
            $targetClient = $ClientName

            New-SPCStorageDashboardHtmlInternal `
                -OutputPath $htmlPath `
                -StorageWasteData $wasteArray `
                -InactiveSiteData $InactiveSiteData `
                -VersionWasteData $VersionWasteData `
                -PreservationHoldData $PreservationHoldData `
                -UnitPricePerGB $UnitPricePerGB `
                -CompanyLogoUrl $targetLogo `
                -ClientName $targetClient
        }

        $totalWasteMB = ($wasteArray | Measure-Object -Property TotalWasteMB -Sum).Sum
        $totalWasteGB = [Math]::Round(($totalWasteMB / 1024), 2)
        $monthlySavings = [Math]::Round(($totalWasteGB * $UnitPricePerGB), 2)
        $annualSavings  = [Math]::Round(($monthlySavings * 12), 2)

        [PSCustomObject][ordered]@{
            PSTypeName        = 'SPC.ReportExportSummary'
            HtmlDashboardPath = $htmlPath
            CsvSummaryPath    = $csvSummaryPath
            CsvInactivePath   = $csvInactivePath
            TotalWasteGB      = $totalWasteGB
            MonthlySavingsUSD = $monthlySavings
            AnnualSavingsUSD  = $annualSavings
            ExportedAt        = (Get-Date).ToUniversalTime()
        }
    }
}
