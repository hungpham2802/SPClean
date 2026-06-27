# Export-SPCReport

Generates a report from orphaned user pipeline input in CSV, HTML, or JSON format.

!!! info "License requirement"
    **HTML format** requires a Pro or Consultant license. CSV and JSON are available on the Free tier.

## Synopsis

```powershell
Export-SPCReport
    -InputObject  <SPC.OrphanedUser[]>
    [-Format      CSV | HTML | JSON]
    [-OutputPath  <string>]
    [-GroupBy     Site | RiskLevel | OrphanType]
    [-IncludeSummary]
    [-PassThru]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-InputObject` | `SPC.OrphanedUser[]` | ✅ | Accepts pipeline input |
| `-Format` | `CSV \| HTML \| JSON` | | Output format. Default: `CSV` |
| `-OutputPath` | `string` | | Full path for the output file. Default: auto-named file in the current directory |
| `-GroupBy` | `Site \| RiskLevel \| OrphanType` | | Sort/group rows by field. Default: `Site` |
| `-IncludeSummary` | switch | | Prepend a summary card with totals and breakdown by risk level |
| `-PassThru` | switch | | Pass input `SPC.OrphanedUser` objects through the pipeline after writing the report |

## Returns

`SPC.ReportResult` with properties:

| Property | Description |
| --- | --- |
| `FilePath` | Absolute path to the generated file |
| `Format` | The format used (`CSV`, `HTML`, or `JSON`) |
| `TotalOrphansReported` | Count of records written |
| `GeneratedAt` | UTC timestamp |

## Format notes

### CSV

- UTF-8 with BOM (Excel-compatible)
- 11 columns covering all `SPC.OrphanedUser` properties
- Sorted by the `-GroupBy` field

### HTML

- Self-contained — all CSS and JavaScript are inlined; no external dependencies
- Colour-coded risk badges: **HIGH** (red), **MEDIUM** (amber), **LOW** (green)
- Sortable columns via click
- Optional summary card with totals and breakdown chart when `-IncludeSummary` is used

### JSON

- Root object grouped by the `-GroupBy` field
- Optional `summary` block when `-IncludeSummary` is used

## Notes

- **HTML format is gated** — `Export-SPCReport -Format HTML` requires a Pro or Consultant license. Calling it on the Free tier raises `ERR-LIC-003`.
- CSV format is always available with no license requirement.
- The output file path is returned in `SPC.ReportResult.FilePath` regardless of whether `-OutputPath` was specified, so you can pipe or capture it for further processing.

## Examples

=== "HTML report with summary"

    ```powershell
    # Generate a self-contained HTML report for all sites, with a summary card
    Get-SPCOrphanedUser -AllSites |
        Export-SPCReport -Format HTML -IncludeSummary -OutputPath C:\reports\orphans.html
    ```

=== "CSV grouped by risk level"

    ```powershell
    # Export a free-tier CSV report, rows sorted by risk level
    Get-SPCOrphanedUser -SiteUrl $url |
        Export-SPCReport -Format CSV -GroupBy RiskLevel -OutputPath C:\reports\orphans.csv
    ```

=== "JSON with pass-through"

    ```powershell
    # Export to JSON and continue piping the original objects downstream
    $orphans = Get-SPCOrphanedUser -SiteUrl $url |
        Export-SPCReport -Format JSON -PassThru

    # $orphans still contains the SPC.OrphanedUser objects for further processing
    $orphans | Where-Object RiskLevel -eq 'HIGH'
    ```

## See also

- [Get-SPCOrphanedUser](get-spcorphaneduser.md)
- [Remove-SPCOrphanedUser](remove-spcorphaneduser.md)
- [Licensing](../licensing.md)
