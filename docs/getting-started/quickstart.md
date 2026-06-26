# Quick Start

A complete scan-report-remediate workflow in six steps.

```powershell
# 1. Connect
Connect-SPCTenant -TenantName contoso -ClientId '<app-id>'

# 2. Scan one site and view results
Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR'

# 3. Export to HTML report
Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR' |
    Export-SPCReport -Format HTML -IncludeSummary

# 4. Preview what would be removed (WhatIf — no changes made)
Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR' |
    Remove-SPCOrphanedUser -WhatIf

# 5. Remove HIGH-risk orphans with a snapshot backup
Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR' |
    Where-Object RiskLevel -eq 'HIGH' |
    Remove-SPCOrphanedUser -CreateSnapshot -SnapshotPath C:\Snapshots -Confirm

# 6. Disconnect
Disconnect-SPCTenant
```

!!! tip "WhatIf first"
    Always run step 4 (`-WhatIf`) before step 5. It prints exactly what would be removed without making any changes.

!!! note "Pro license required for HTML reports"
    `Export-SPCReport -Format HTML` and `-CreateSnapshot` require a Pro or Consultant license.  
    The Free tier supports CSV and JSON output. See [Licensing](../licensing.md).

---

## Scan all sites

```powershell
# Scan every site collection in the tenant
Get-SPCOrphanedUser -AllSites |
    Export-SPCReport -Format HTML -IncludeSummary -OutputPath C:\reports\orphans.html
```

---

## Restore after accidental removal

If you removed a user and need to restore their permissions from the snapshot:

```powershell
Connect-SPCTenant -TenantName contoso -ClientId '<app-id>'
Restore-SPCOrphanedUser -SnapshotPath C:\Snapshots\user@contoso.com_20260622T120000Z.json
Disconnect-SPCTenant
```

---

## Next step

[Explore the Cmdlet Reference →](../cmdlets/index.md){ .md-button .md-button--primary }
