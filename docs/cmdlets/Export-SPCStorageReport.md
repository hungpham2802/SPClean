# Export-SPCStorageReport

Compiles storage waste assessments, inactive sites, document library version sprawl, and preservation hold data into standalone interactive HTML Executive ROI Dashboards and CSV data exports.

## Synopsis

```powershell
Export-SPCStorageReport
    -StorageWasteData       <SPC.StorageWasteSummary[]>
    [-InactiveSiteData      <SPC.InactiveSite[]>]
    [-VersionWasteData      <SPC.VersionWasteDetail[]>]
    [-PreservationHoldData  <SPC.PreservationHoldWaste[]>]
    [-OutputPath            <string>]
    [-Format                <string>]
    [-UnitPricePerGB        <double>]
    [-CompanyLogoUrl        <string>]
    [-ClientName            <string>]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-StorageWasteData` | `SPC.StorageWasteSummary[]`| Yes | Storage waste dataset from `Get-SPCStorageWaste`. Accepts pipeline input |
| `-InactiveSiteData` | `SPC.InactiveSite[]` | | Inactive sites dataset from `Get-SPCInactiveSite` |
| `-VersionWasteData` | `SPC.VersionWasteDetail[]` | | Version sprawl dataset from `Get-SPCVersionWaste` |
| `-PreservationHoldData`| `SPC.PreservationHoldWaste[]`| | PHL dataset from `Get-SPCPreservationHoldWaste` |
| `-OutputPath` | `string` | | Directory path to save generated reports (Default: `.\Reports`) |
| `-Format` | `string` | | Output format: `HTML`, `CSV`, or `All` (Default: `All`) |
| `-UnitPricePerGB` | `double` | | Cost per GB/month in USD (Default: `0.20`, Range: `0.01-10.0`) |
| `-CompanyLogoUrl` | `string` | | Custom logo URL for white-label branding `[Consultant]` |
| `-ClientName` | `string` | | Organization/client name for dashboard header `[Consultant]` |

## Returns

`SPC.ReportExportSummary` objects with the following properties:

| Property | Type | Description |
| --- | --- | --- |
| `HtmlDashboardPath` | `string` | File path to the generated HTML dashboard (if generated) |
| `CsvSummaryPath` | `string` | File path to the generated storage waste summary CSV |
| `CsvInactivePath` | `string` | File path to the generated inactive sites CSV |
| `TotalWasteGB` | `double` | Total recoverable storage across all sites in GB |
| `MonthlySavingsUSD` | `double` | Estimated monthly cost avoidance in USD |
| `AnnualSavingsUSD` | `double` | Estimated annual cost avoidance in USD |
| `ExportedAt` | `DateTime` | UTC timestamp of report generation |

## Examples

=== "Export top 20 waste sites"

    ```powershell
    Get-SPCStorageWaste -Top 20 |
        Export-SPCStorageReport -Format All -OutputPath '.\StorageReports'
    ```

=== "Comprehensive multi-vector dashboard"

    ```powershell
    $waste = Get-SPCStorageWaste -IncludeVersions
    $inactive = Get-SPCInactiveSite -InactiveDays 180
    $versions = Get-SPCVersionWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Engineering'
    $phl = Get-SPCPreservationHoldWaste

    Export-SPCStorageReport -StorageWasteData $waste `
        -InactiveSiteData $inactive `
        -VersionWasteData $versions `
        -PreservationHoldData $phl `
        -Format HTML
    ```

=== "MSP white-label client report"

    ```powershell
    Get-SPCStorageWaste | Export-SPCStorageReport `
        -Format HTML `
        -CompanyLogoUrl 'https://msp.example.com/assets/logo.png' `
        -ClientName 'Fabrikam International' `
        -UnitPricePerGB 0.25 `
        -OutputPath 'C:\ClientDeliverables'
    ```

## Notes

- CSV export is completely free without a license.
- Generating the interactive HTML ROI dashboard requires a **Pro** or **Consultant** license.
- Custom branding parameters (`-CompanyLogoUrl`, `-ClientName`) require a **Consultant** license.

## See also

- [Get-SPCStorageWaste](Get-SPCStorageWaste.md)
- [Get-SPCInactiveSite](Get-SPCInactiveSite.md)
- [Get-SPCVersionWaste](Get-SPCVersionWaste.md)
- [Get-SPCPreservationHoldWaste](Get-SPCPreservationHoldWaste.md)
- [Clear-SPCRecycleBin](Clear-SPCRecycleBin.md)
- [Optimize-SPCFileVersion](Optimize-SPCFileVersion.md)
