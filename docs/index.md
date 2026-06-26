---
hide:
  - toc
---

# SPClean

> **PowerShell toolkit for SharePoint Online permission hygiene.**  
> Find orphaned users, score risk, generate reports, and remove safely — without enterprise-software pricing.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?style=flat&logo=powershell&logoColor=white)](https://www.powershellgallery.com/packages/SPClean)
[![PSGallery](https://img.shields.io/powershellgallery/v/SPClean?label=PSGallery&color=5391FE&logo=powershell&logoColor=white)](https://www.powershellgallery.com/packages/SPClean)
[![PSGallery Downloads](https://img.shields.io/powershellgallery/dt/SPClean?label=Downloads&color=28a745)](https://www.powershellgallery.com/packages/SPClean)
[![License](https://img.shields.io/badge/License-MIT-28a745?style=flat)](https://github.com/hungpham2802/SPClean/blob/main/LICENSE)
[![Status](https://img.shields.io/badge/Status-Beta-ffc107?style=flat)]()

---

## Why SPClean

Every SharePoint tenant accumulates **orphaned users** — accounts that remain in site permission lists long after the employee left, the contractor finished, or the guest expired. Microsoft has no built-in tool to find and clean them at scale.

The result: deleted accounts still holding active permissions, compliance reports that flag ghost identities, and hours of manual cleanup per tenant.

SPClean fixes this in minutes:

```powershell
Connect-SPCTenant -TenantName contoso -ClientId '<app-id>'

# Scan all sites, export a colour-coded HTML report
Get-SPCOrphanedUser -AllSites | Export-SPCReport -Format HTML -IncludeSummary

# Preview what would be removed — no changes made
Get-SPCOrphanedUser -AllSites | Remove-SPCOrphanedUser -WhatIf

# Remove HIGH-risk orphans with a snapshot backup
Get-SPCOrphanedUser -AllSites |
    Where-Object RiskLevel -eq 'HIGH' |
    Remove-SPCOrphanedUser -CreateSnapshot -SnapshotPath C:\Snapshots
```

---

## What SPClean does

| Capability | Detail |
| --- | --- |
| **Detect** | Scans site User Information Lists and cross-checks with Entra ID to identify deleted, soft-deleted, disabled, and guest-orphaned accounts |
| **Score risk** | Classifies each orphan as HIGH / MEDIUM / LOW based on account state and active permission assignments |
| **Report** | Exports CSV, JSON, or self-contained HTML reports with sortable columns and colour-coded risk badges |
| **Remove safely** | Removes users from UILs and revokes direct role assignments — with `-WhatIf` preview and JSON snapshot backup |
| **Restore** | Re-applies permissions from a snapshot after accidental removal |
| **Schedule** | Registers a Windows Scheduled Task that runs unattended scans using AppOnly auth |

---

[Get Started →](getting-started/installation.md){ .md-button .md-button--primary }
[Cmdlet Reference →](cmdlets/index.md){ .md-button }
[Licensing →](licensing.md){ .md-button }
