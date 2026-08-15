# Get-SPCVersionWaste

Analyzes document library file version sprawl within SharePoint Online site collections to measure historical version overhead and calculate recoverable storage capacity.

## Synopsis

```powershell
Get-SPCVersionWaste
    -SiteUrl            <string>
    [-LibraryTitle      <string[]>]
    [-KeepVersions      <int>]
    [-OlderThanDays     <int>]
    [-TopFiles          <int>]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-SiteUrl` | `string` | Yes | The target SharePoint Online site collection URL. Accepts pipeline input |
| `-LibraryTitle` | `string[]` | | Filter by specific document library titles |
| `-KeepVersions` | `int` | | Simulated count of major versions to retain (Default: `50`, Range: `1-50000`) |
| `-OlderThanDays` | `int` | | Minimum age in days for versions to be considered prunable (Default: `90`, Range: `0-3650`) |
| `-TopFiles` | `int` | | Number of bloated files to report per library (Default: `50`, Range: `1-500`) |

## Returns

`SPC.VersionWasteDetail` objects with the following properties:

| Property | Type | Description |
| --- | --- | --- |
| `SiteUrl` | `string` | Site collection URL |
| `LibraryTitle` | `string` | Document library display title |
| `ItemCount` | `int` | Total item count in the document library |
| `CurrentFilesSizeMB` | `double` | Storage occupied by latest versions in MB |
| `HistoricalVersionsSizeMB`| `double`| Storage occupied by historical versions in MB |
| `TotalLibrarySizeMB` | `double` | Combined library storage in MB |
| `BloatRatio` | `double` | Ratio of total size relative to current file size (e.g. `4.5x`) |
| `ConfiguredMaxVersions` | `int` | Library's configured major version limit |
| `SimulatedKeepVersions` | `int` | KeepVersions threshold used for simulation |
| `RecoverableStorageMB` | `double` | Total storage that can be reclaimed in MB |
| `RecoverablePercent` | `double` | Percentage of library storage that is recoverable |
| `TopBloatedFiles` | `PSCustomObject[]`| Detailed list of top bloated files |

### TopBloatedFiles Object Structure

| Property | Type | Description |
| --- | --- | --- |
| `FileUrl` | `string` | Server-relative file path |
| `FileName` | `string` | File name |
| `VersionCount` | `int` | Total version count for the file |
| `CurrentSizeMB` | `double` | Size of current version in MB |
| `VersionsSizeMB` | `double` | Combined size of historical versions in MB |
| `RecoverableMB` | `double` | Recoverable storage for this specific file in MB |

## Examples

=== "Audit site libraries"

    ```powershell
    Get-SPCVersionWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Finance'
    ```

=== "Custom simulation thresholds"

    ```powershell
    Get-SPCVersionWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Engineering' `
        -LibraryTitle 'Project CAD Files' `
        -KeepVersions 20 `
        -OlderThanDays 60
    ```

=== "Pipeline to remediation"

    ```powershell
    Get-SPCVersionWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Legal' |
        Where-Object BloatRatio -gt 3.0 |
        ForEach-Object {
            Optimize-SPCFileVersion -SiteUrl $_.SiteUrl -LibraryTitle $_.LibraryTitle -KeepVersions 50 -OlderThanDays 90 -DryRun
        }
    ```

## Notes

- Requires an active connection established by `Connect-SPCTenant`.
- Read-only discovery cmdlet; does not alter or prune file versions. Use `Optimize-SPCFileVersion` to apply remediation.

## See also

- [Optimize-SPCFileVersion](Optimize-SPCFileVersion.md)
- [Get-SPCStorageWaste](Get-SPCStorageWaste.md)
- [Export-SPCStorageReport](Export-SPCStorageReport.md)
