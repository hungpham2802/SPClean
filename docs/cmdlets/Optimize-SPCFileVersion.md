# Optimize-SPCFileVersion

Optimizes document library storage by trimming redundant historical versions exceeding retention criteria and optionally updates library version limits to prevent future sprawl.

## Synopsis

```powershell
Optimize-SPCFileVersion
    -SiteUrl                <string>
    [-LibraryTitle          <string[]>]
    [-KeepVersions          <int>]
    [-OlderThanDays         <int>]
    [-ApplyPolicyToLibrary]
    [-DryRun]
    [-AuditLogPath          <string>]
    [-Force]
    [-WhatIf]
    [-Confirm]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-SiteUrl` | `string` | Yes | Target site collection URL. Accepts pipeline input |
| `-LibraryTitle` | `string[]` | | Filter by specific document library titles |
| `-KeepVersions` | `int` | | Number of recent major versions to preserve (Default: `50`, Range: `1-50000`) |
| `-OlderThanDays` | `int` | | Minimum age in days for versions to be trimmed (Default: `90`, Range: `0-3650`) |
| `-ApplyPolicyToLibrary`| switch | | Update library `MajorVersionLimit` setting to match `-KeepVersions` |
| `-DryRun` | switch | | Simulation mode: preview trimmed files and freed storage without deleting |
| `-AuditLogPath` | `string` | | Path to write the CSV audit log. Auto-generated if omitted |
| `-Force` | switch | | Suppress interactive confirmation prompts |
| `-WhatIf` | switch | | Standard PowerShell preview mode |
| `-Confirm` | switch | | Prompt before trimming versions |

## Returns

`SPC.FileVersionOptimizeResult` objects with the following properties:

| Property | Type | Description |
| --- | --- | --- |
| `SiteUrl` | `string` | Site collection URL |
| `LibrariesProcessed` | `int` | Number of document libraries evaluated |
| `FilesOptimizedCount` | `int` | Total count of files with trimmed versions |
| `VersionsRemovedCount`| `int` | Total count of historical versions pruned |
| `StorageFreedMB` | `double` | Storage capacity reclaimed in MB |
| `MonthlyCostSavedUSD` | `double` | Monthly cost savings ($0.20/GB/month) |
| `AnnualCostSavedUSD` | `double` | Annualized cost savings ($2,400/TB/year) |
| `PolicyUpdated` | `bool` | Whether library `MajorVersionLimit` was updated |
| `IsDryRun` | `bool` | Whether operation was executed in simulation mode |
| `AuditLogFilePath` | `string` | Path to the append-only CSV audit file |
| `ExecutedAt` | `DateTime` | UTC timestamp of execution |

## Examples

=== "Simulation preview"

    ```powershell
    Optimize-SPCFileVersion -SiteUrl 'https://contoso.sharepoint.com/sites/Engineering' `
        -KeepVersions 30 `
        -OlderThanDays 60 `
        -DryRun
    ```

=== "Trim versions and enforce policy"

    ```powershell
    Optimize-SPCFileVersion -SiteUrl 'https://contoso.sharepoint.com/sites/Marketing' `
        -LibraryTitle 'Brand Assets' `
        -KeepVersions 20 `
        -ApplyPolicyToLibrary `
        -Force
    ```

=== "Pipeline from version audit"

    ```powershell
    Get-SPCVersionWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Finance' |
        Where-Object BloatRatio -gt 2.0 |
        ForEach-Object {
            Optimize-SPCFileVersion -SiteUrl $_.SiteUrl -LibraryTitle $_.LibraryTitle -KeepVersions 50 -OlderThanDays 90
        }
    ```

## Notes

- Requires an active connection established by `Connect-SPCTenant`.
- `-DryRun` and `-WhatIf` work without a license.
- Live version trimming requires a **Pro** or **Consultant** license.

## See also

- [Get-SPCVersionWaste](Get-SPCVersionWaste.md)
- [Get-SPCStorageWaste](Get-SPCStorageWaste.md)
- [Export-SPCStorageReport](Export-SPCStorageReport.md)
