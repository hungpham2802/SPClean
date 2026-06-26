# New-SPCScanSchedule

Generates a self-contained scan script and registers a Windows Scheduled Task that runs unattended orphan scans using AppOnly authentication.

!!! info "License requirement"
    Requires a Pro or Consultant license.

!!! warning "Windows only"
    `New-SPCScanSchedule` uses `Register-ScheduledTask` which is only available on Windows. On non-Windows systems the cmdlet writes the scan script and outputs the equivalent cron expression but does not register a task.

## Synopsis

```powershell
New-SPCScanSchedule
    -TenantName          <string>
    -ClientId            <string>
    -CertificatePath     <string>
    -CertificatePassword <SecureString>
    [-Schedule           Daily | Weekly | Monthly]
    [-ScheduleAt         <datetime>]
    [-ReportFormat       HTML | CSV | JSON]
    [-ReportOutputPath   <string>]
    [-TaskName           <string>]
    [-WhatIf]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-TenantName` | `string` | ✅ | Short tenant name or full domain |
| `-ClientId` | `string` | ✅ | Entra App Registration client ID (AppOnly) |
| `-CertificatePath` | `string` | ✅ | Path to `.pfx` certificate |
| `-CertificatePassword` | `SecureString` | ✅ | Password for the `.pfx` file |
| `-Schedule` | `Daily \| Weekly \| Monthly` | | Recurrence. Mutually exclusive with `-ScheduleAt` |
| `-ScheduleAt` | `datetime` | | One-time execution at this date/time |
| `-ReportFormat` | `HTML \| CSV \| JSON` | | Format for the generated report. Default: `HTML` |
| `-ReportOutputPath` | `string` | | Directory for generated reports |
| `-TaskName` | `string` | | Windows Task Scheduler task name. Default: `SPClean_OrphanedUserScan` |
| `-WhatIf` | switch | | Show what task would be registered without creating it |

## Returns

`SPC.ScheduleResult` with properties:

| Property | Description |
| --- | --- |
| `TaskName` | Registered task name |
| `ScriptPath` | Path to the generated scan script |
| `Schedule` | Recurrence type or one-time datetime |
| `NextRun` | Scheduled next execution time |
| `Status` | `Registered` or `ScriptOnly` (non-Windows) |

## Security note

The certificate password is encrypted using Windows DPAPI (`ConvertFrom-SecureString`) and stored in the generated script. It is only decryptable by the **same Windows user account on the same machine** that ran `New-SPCScanSchedule`. The plain-text password is never written to disk.

## Example

```powershell
$certPwd = Read-Host -AsSecureString 'Certificate password'

New-SPCScanSchedule -TenantName contoso `
    -ClientId            '<app-id>' `
    -CertificatePath     C:\certs\spclean.pfx `
    -CertificatePassword $certPwd `
    -Schedule            Weekly `
    -ReportFormat        HTML `
    -ReportOutputPath    C:\Reports\SPClean
```

## Full workflow

```powershell
# 1. Verify credentials work
$certPwd = Read-Host -AsSecureString 'Certificate password'
Connect-SPCTenant -TenantName contoso -AuthMethod AppOnly `
    -ClientId '<app-id>' -CertificatePath C:\certs\spclean.pfx -CertificatePassword $certPwd

# 2. Register the scheduled task
New-SPCScanSchedule -TenantName contoso `
    -ClientId        '<app-id>' `
    -CertificatePath C:\certs\spclean.pfx `
    -CertificatePassword $certPwd `
    -Schedule        Weekly `
    -ReportFormat    HTML `
    -ReportOutputPath C:\Reports\SPClean

Disconnect-SPCTenant
```

## See also

- [Authentication — AppOnly / certificate](../getting-started/authentication.md)
