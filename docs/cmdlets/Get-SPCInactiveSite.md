# Get-SPCInactiveSite

Discovers dormant, inactive, and stale SharePoint Online sites across the tenant using Microsoft Graph activity reports, providing cost avoidance metrics and lifecycle governance recommendations.

## Synopsis

```powershell
Get-SPCInactiveSite
    [-InactiveDays          <int>]
    [-IncludeTeamSitesOnly]
    [-MinStorageMB          <double>]
    [-Top                   <int>]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-InactiveDays` | `int` | | Inactivity threshold in days without file/page actions (Default: `180`, Range: `30-1825`) |
| `-IncludeTeamSitesOnly`| switch | | Filter to return only M365 Group-connected Team Sites |
| `-MinStorageMB` | `double` | | Filter for sites consuming at least this much storage in MB |
| `-Top` | `int` | | Limit output to top N largest inactive sites (Default: 0 for all) |

## Returns

`SPC.InactiveSite` objects with the following properties:

| Property | Type | Description |
| --- | --- | --- |
| `SiteUrl` | `string` | Site collection URL |
| `SiteTitle` | `string` | Site collection title |
| `GroupId` | `string` | Associated Microsoft 365 Group ID (if applicable) |
| `Template` | `string` | SharePoint web template (e.g. `GROUP#0`, `SITEPAGEPUBLISHING#0`) |
| `StorageUsedMB` | `double` | Current storage consumption in MB |
| `FileCount` | `int64` | Total file count within the site |
| `LastActivityDate` | `DateTime`| Last recorded activity timestamp from Graph usage reports |
| `InactiveDays` | `int` | Number of days since last recorded activity |
| `LockState` | `string` | SharePoint lock status (`Unlock`, `ReadOnly`, `NoAccess`) |
| `OwnerUPN` | `string` | Primary site owner or group creator UPN |
| `MonthlyCostAvoidanceUSD`| `double`| Potential monthly cost savings if site is archived/deleted |
| `Recommendation` | `string` | Suggested governance action (`Review with Owner`, `Set ReadOnly`, `Archive or Delete`) |

## Recommendation matrix

| Inactive Days | Recommendation | Action Description |
| --- | --- | --- |
| **30 – 179 days** | `Review with Owner` | Send automated or manual notification to site owner to confirm ongoing need |
| **180 – 364 days** | `Set ReadOnly` | Lock site to prevent further edits while retaining read access for users |
| **365+ days** | `Archive or Delete` | Move content to cold storage / Microsoft 365 Archive or delete site collection |

## Examples

=== "Find sites inactive for 6 months"

    ```powershell
    Get-SPCInactiveSite -InactiveDays 180
    ```

=== "Find top 20 heavy inactive sites"

    ```powershell
    Get-SPCInactiveSite -InactiveDays 365 -MinStorageMB 10240 -Top 20
    ```

=== "Filter Team Sites for ReadOnly locking"

    ```powershell
    Get-SPCInactiveSite -IncludeTeamSitesOnly -InactiveDays 90 |
        Where-Object Recommendation -eq 'Set ReadOnly' |
        Export-SPCStorageReport -Format CSV -OutputPath '.\Governance'
    ```

## Notes

- Requires an active connection established by `Connect-SPCTenant`.
- Leverages Microsoft Graph Site Usage API (`Get-SPCGraphSiteUsageInternal`) to efficiently aggregate activity across tenant sites.

## See also

- [Get-SPCStorageWaste](Get-SPCStorageWaste.md)
- [Export-SPCStorageReport](Export-SPCStorageReport.md)
