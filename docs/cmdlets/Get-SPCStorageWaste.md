# Get-SPCStorageWaste

Scans SharePoint Online site collections to detect and quantify storage waste across first/second stage recycle bins, version history sprawl, and Preservation Hold Libraries (PHL), calculating immediate cost avoidance opportunities.

## Synopsis

```powershell
Get-SPCStorageWaste
    [-SiteUrl                   <string[]>]
    [-IncludeRecycleBin]
    [-IncludeVersions]
    [-IncludePreservationHold]
    [-Top                       <int>]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-SiteUrl` | `string[]` | | One or more site collection URLs. Accepts pipeline input |
| `-IncludeRecycleBin` | switch | | Inspect 1st stage (End-User) and 2nd stage (SCA) recycle bins. Default: `$true` |
| `-IncludeVersions` | switch | | Calculate prunable version history sprawl across document libraries |
| `-IncludePreservationHold`| switch | | Audit Preservation Hold Library (PHL) locked storage |
| `-Top` | `int` | | Limit output to top N sites by total waste in MB (Default: 0 for all) |

## Returns

`SPC.StorageWasteSummary` objects with the following properties:

| Property | Type | Description |
| --- | --- | --- |
| `SiteUrl` | `string` | Site collection URL |
| `SiteTitle` | `string` | Site collection title |
| `StorageUsedMB` | `double` | Total current storage consumption in MB |
| `StorageAllocatedMB` | `double` | Site storage quota in MB |
| `StorageUsedPercent` | `double` | Percentage of allocated quota consumed |
| `RecycleBin1stStageMB` | `double` | Storage consumed by 1st stage recycle bin |
| `RecycleBin2ndStageMB` | `double` | Storage consumed by 2nd stage recycle bin |
| `TotalRecycleBinMB` | `double` | Combined recycle bin storage |
| `VersionWasteMB` | `double` | Estimated recoverable storage from historical version sprawl |
| `PreservationHoldMB` | `double` | Storage consumed by Preservation Hold Library |
| `TotalWasteMB` | `double` | Total recoverable waste across recycle bins and versions |
| `PotentialMonthlySavingUSD`| `double` | Estimated monthly cost savings ($0.20/GB/month) |
| `PotentialAnnualSavingUSD` | `double` | Estimated annualized cost savings ($2,400/TB/year) |
| `ScannedAt` | `DateTime` | UTC timestamp of scan execution |

## Examples

=== "Single site audit"

    ```powershell
    Get-SPCStorageWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Marketing' -IncludeVersions -IncludePreservationHold
    ```

=== "Tenant-wide top 10 discovery"

    ```powershell
    Get-SPCStorageWaste -Top 10 -IncludeVersions | Export-SPCStorageReport -Format HTML -OutputPath '.\Reports'
    ```

=== "Pipeline to recycle bin cleanup"

    ```powershell
    Get-SPCStorageWaste -IncludeRecycleBin | Where-Object TotalWasteMB -gt 51200 | ForEach-Object {
        Clear-SPCRecycleBin -SiteUrl $_.SiteUrl -OlderThanDays 30 -DryRun
    }
    ```

## Notes

- Requires an active connection established by `Connect-SPCTenant`.
- All site enumeration uses Microsoft Graph Usage API (`Get-SPCGraphSiteUsageInternal`) for maximum speed across thousands of sites.
- Calculations use the standard M365 extra storage rate of **$0.20/GB/month** ($2.40/GB/year).

## See also

- [Get-SPCVersionWaste](Get-SPCVersionWaste.md)
- [Get-SPCPreservationHoldWaste](Get-SPCPreservationHoldWaste.md)
- [Get-SPCInactiveSite](Get-SPCInactiveSite.md)
- [Clear-SPCRecycleBin](Clear-SPCRecycleBin.md)
- [Export-SPCStorageReport](Export-SPCStorageReport.md)
