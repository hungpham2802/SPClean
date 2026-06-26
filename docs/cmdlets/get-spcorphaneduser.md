# Get-SPCOrphanedUser

Scans one or more SharePoint site collections, cross-checks the User Information List against Entra ID, and returns orphaned user objects.

## Synopsis

```powershell
Get-SPCOrphanedUser
    [-SiteUrl        <string[]>]
    [-AllSites]
    [-IncludeGuests]
    [-IncludeDisabled]
    [-ExcludeSiteUrl <string[]>]
    [-ThrottleLimit  <int>]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-SiteUrl` | `string[]` | | One or more site collection URLs. Accepts pipeline input |
| `-AllSites` | switch | | Scan all site collections in the tenant. Mutually exclusive with `-SiteUrl` |
| `-IncludeGuests` | switch | | Include orphaned external (`#EXT#`) guest accounts |
| `-IncludeDisabled` | switch | | Include Entra-disabled accounts (not yet deleted) |
| `-ExcludeSiteUrl` | `string[]` | | URL patterns to skip when using `-AllSites`. Supports wildcards |
| `-ThrottleLimit` | `int` | | Maximum concurrent site connections. Default: `3`, maximum: `10` |

## Returns

`SPC.OrphanedUser` objects with the following properties:

| Property | Type | Description |
| --- | --- | --- |
| `UPN` | `string` | User principal name |
| `DisplayName` | `string` | Display name from the User Information List |
| `LoginName` | `string` | SharePoint claim string (e.g. `i:0#.f\|membership\|user@contoso.com`) |
| `SiteUrl` | `string` | Site collection URL |
| `SiteTitle` | `string` | Site collection display name |
| `OrphanType` | `string` | `Deleted`, `SoftDeleted`, `Disabled`, or `GuestOrphaned` |
| `RiskLevel` | `string` | `HIGH`, `MEDIUM`, or `LOW` |
| `HasDirectPermissions` | `bool` | Whether the user has direct role assignments (not just group membership) |
| `GroupMemberships` | `string[]` | SharePoint groups the user belongs to |
| `DetectedAt` | `DateTime` | UTC timestamp of detection |

## Risk scoring

| Level | Condition |
| --- | --- |
| **HIGH** | `Deleted` or `GuestOrphaned` with active direct permission assignments |
| **MEDIUM** | `SoftDeleted` (still accessible until permanently purged) or `Disabled` with direct permissions |
| **LOW** | `Deleted` with no active permissions — UIL entry only |

## Examples

=== "Single site"

    ```powershell
    Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR'
    ```

=== "Multiple sites"

    ```powershell
    Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR',
                                  'https://contoso.sharepoint.com/sites/Finance'
    ```

=== "All sites, exclude OneDrive"

    ```powershell
    Get-SPCOrphanedUser -AllSites -ExcludeSiteUrl '*-my.sharepoint.com/*'
    ```

=== "All sites, include guests and disabled"

    ```powershell
    Get-SPCOrphanedUser -AllSites -IncludeGuests -IncludeDisabled
    ```

## Pipeline usage

```powershell
# Scan → filter → report
Get-SPCOrphanedUser -AllSites |
    Where-Object RiskLevel -eq 'HIGH' |
    Export-SPCReport -Format HTML -IncludeSummary

# Scan → filter → remove (with WhatIf preview first)
Get-SPCOrphanedUser -SiteUrl $url |
    Where-Object OrphanType -eq 'Deleted' |
    Remove-SPCOrphanedUser -WhatIf
```

## Notes

- Requires an active connection established by `Connect-SPCTenant`.
- System accounts (`SHAREPOINT\system`, `NT AUTHORITY\*`, claim type `c:0(.s|true)`) are automatically filtered and never returned.
- `AllSites` uses `Write-Progress` to display a progress bar across the tenant scan.
- Detection uses Microsoft Graph batch requests for efficient Entra ID lookups.

## See also

- [Export-SPCReport](export-spcreport.md)
- [Remove-SPCOrphanedUser](remove-spcorphaneduser.md)
