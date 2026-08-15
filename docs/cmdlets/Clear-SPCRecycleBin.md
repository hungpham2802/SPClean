# Clear-SPCRecycleBin

Safely purges deleted items older than a specified retention threshold from first-stage (End-User) and/or second-stage (Site Collection Administrator) recycle bins with automatic Purview Hold immunity and append-only audit logging.

## Synopsis

```powershell
Clear-SPCRecycleBin
    -SiteUrl            <string[]>
    [-OlderThanDays     <int>]
    [-FirstStageOnly | -SecondStageOnly]
    [-DryRun]
    [-AuditLogPath      <string>]
    [-Force]
    [-WhatIf]
    [-Confirm]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-SiteUrl` | `string[]` | Yes | One or more site collection URLs. Accepts pipeline input |
| `-OlderThanDays` | `int` | | Minimum age in days since deletion for items to be purged (Default: `30`, Range: `0-180`) |
| `-SecondStageOnly` | switch | | Target only the 2nd stage (SCA) recycle bin |
| `-FirstStageOnly` | switch | | Target only the 1st stage (End-User) recycle bin |
| `-DryRun` | switch | | Simulation mode: calculate storage and log items without deleting |
| `-AuditLogPath` | `string` | | Path to write the CSV audit log. Auto-generated if omitted |
| `-Force` | switch | | Suppress interactive confirmation prompts |
| `-WhatIf` | switch | | Standard PowerShell preview mode |
| `-Confirm` | switch | | Prompt before deleting items |

## Returns

`SPC.RecycleBinClearResult` objects with the following properties:

| Property | Type | Description |
| --- | --- | --- |
| `SiteUrl` | `string` | Site collection URL |
| `StageProcessed` | `string` | Stages processed (`1stStage`, `2ndStage`, or `Both`) |
| `ItemsDeletedCount`| `int` | Number of items purged (or simulated) |
| `StorageFreedMB` | `double` | Storage reclaimed in MB |
| `MonthlyCostSavedUSD`| `double`| Monthly cost savings ($0.20/GB/month) |
| `IsDryRun` | `bool` | Whether the operation was run in simulation mode |
| `AuditLogFilePath` | `string` | Path to the append-only CSV audit file |
| `ExecutedAt` | `DateTime` | UTC timestamp of execution |
| `Status` | `string` | Operation status (`Success`, `PartialSuccess`, `Simulated`) |

## Safety & Compliance Protections

> [!IMPORTANT]
> **Microsoft Purview Hold Immunity**
> Prior to executing any purge action, `Clear-SPCRecycleBin` executes `Test-SPCPurviewHoldInternal` against the target site collection. If an active Purview Retention Policy, Legal Hold, or eDiscovery Hold is detected, the purge operation is automatically aborted for that site, and a compliance skip record is written to the audit log (`SKIPPED_COMPLIANCE_HOLD`).

## Examples

=== "Preview purge with DryRun"

    ```powershell
    Clear-SPCRecycleBin -SiteUrl 'https://contoso.sharepoint.com/sites/Marketing' `
        -OlderThanDays 30 `
        -DryRun
    ```

=== "Purge second-stage recycle bins across top waste sites"

    ```powershell
    Get-SPCStorageWaste -Top 5 | ForEach-Object {
        Clear-SPCRecycleBin -SiteUrl $_.SiteUrl -SecondStageOnly -OlderThanDays 14 -Force
    }
    ```

=== "Purge with custom audit log path"

    ```powershell
    Clear-SPCRecycleBin -SiteUrl 'https://contoso.sharepoint.com/sites/Finance' `
        -OlderThanDays 60 `
        -AuditLogPath 'C:\Audit\Finance_RecycleBin_Purge.csv'
    ```

## Notes

- Requires an active connection established by `Connect-SPCTenant`.
- `-DryRun` and `-WhatIf` are fully functional without a license.
- Executing live remediation without `-DryRun` requires a **Pro** or **Consultant** license.

## See also

- [Get-SPCStorageWaste](Get-SPCStorageWaste.md)
- [Optimize-SPCFileVersion](Optimize-SPCFileVersion.md)
- [Export-SPCStorageReport](Export-SPCStorageReport.md)
