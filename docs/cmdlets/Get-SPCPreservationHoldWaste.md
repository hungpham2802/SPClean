# Get-SPCPreservationHoldWaste

Discovers and audits Preservation Hold Libraries (PHL) created by Microsoft Purview retention policies and compliance holds, measuring locked storage growth and assessing compliance alert thresholds.

## Synopsis

```powershell
Get-SPCPreservationHoldWaste
    [-SiteUrl                <string[]>]
    [-WarningThresholdMB     <double>]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-SiteUrl` | `string[]` | | One or more site collection URLs. Accepts pipeline input |
| `-WarningThresholdMB` | `double` | | Storage threshold in MB for 'Warning' alert (Default: `5120` MB). Critical is `2x` warning |

## Returns

`SPC.PreservationHoldWaste` objects with the following properties:

| Property | Type | Description |
| --- | --- | --- |
| `SiteUrl` | `string` | Site collection URL |
| `SiteTitle` | `string` | Site collection title |
| `HasPreservationHold` | `bool` | Whether an active Preservation Hold Library is present |
| `PHLFileCount` | `int` | Number of items preserved in the PHL |
| `PHLSizeMB` | `double` | Total size of items in the PHL in MB |
| `PercentOfSiteStorage`| `double` | Percentage of total site storage consumed by the PHL |
| `ComplianceHoldActive`| `bool` | Indicates compliance hold protection is enforced |
| `AlertLevel` | `string` | Risk/capacity alert level (`Normal`, `Warning`, `Critical`) |
| `ComplianceNote` | `string` | Explanatory note regarding Purview retention status |

## Examples

=== "Single site PHL inspection"

    ```powershell
    Get-SPCPreservationHoldWaste -SiteUrl 'https://contoso.sharepoint.com/sites/LegalArchive'
    ```

=== "Tenant-wide threshold alert"

    ```powershell
    Get-SPCPreservationHoldWaste -WarningThresholdMB 10240 |
        Where-Object AlertLevel -in @('Warning', 'Critical')
    ```

=== "Export PHL audit to CSV"

    ```powershell
    Get-SPCPreservationHoldWaste -SiteUrl (Get-Content C:\sites.txt) |
        Export-Csv -Path 'C:\Reports\PHL_Audit.csv' -NoTypeInformation
    ```

## Notes

- Requires an active connection established by `Connect-SPCTenant`.
- **Compliance Safety**: Items inside Preservation Hold Libraries are legally protected and cannot be purged directly via PowerShell. To remediate PHL bloat, retention policies must be adjusted in Microsoft Purview Compliance Center.

## See also

- [Get-SPCStorageWaste](Get-SPCStorageWaste.md)
- [Get-SPCVersionWaste](Get-SPCVersionWaste.md)
- [Export-SPCStorageReport](Export-SPCStorageReport.md)
