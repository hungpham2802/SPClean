# Licensing

SPClean uses a **key-based license** verified entirely offline — no internet check, no phone-home.

## Tiers

| Feature | Free | Pro | Consultant |
| --- | :---: | :---: | :---: |
| **Price** | $0 forever | **$199 / tenant / year** | **$399 / year** |
| **Scope & Tenants** | Single / Multi | Single tenant | **Unlimited tenants** |
| **Permission Hygiene** | | | |
| Orphan & Mismatch detection (`Get-SPCOrphanedUser`, `Get-SPCMismatchUser`) | ✅ | ✅ | ✅ |
| CSV and JSON reports (`Export-SPCReport`) | ✅ | ✅ | ✅ |
| Unlimited sites per scan | ✅ | ✅ | ✅ |
| HTML report with risk badges and sorting | — | ✅ | ✅ |
| Snapshot backup before removal (`-CreateSnapshot`) | — | ✅ | ✅ |
| Restore permissions from snapshot (`Restore-SPCOrphanedUser`) | — | ✅ | ✅ |
| Scheduled automated scans (`New-SPCScanSchedule`) | — | ✅ | ✅ |
| **Storage Optimization** | | | |
| Storage waste discovery (`Get-SPCStorageWaste`) | ✅ | ✅ | ✅ |
| Version sprawl analytics (`Get-SPCVersionWaste`) | ✅ | ✅ | ✅ |
| Inactive site & cost avoidance detection (`Get-SPCInactiveSite`) | ✅ | ✅ | ✅ |
| Preservation Hold Library auditing (`Get-SPCPreservationHoldWaste`) | ✅ | ✅ | ✅ |
| WhatIf / DryRun simulation modes | ✅ | ✅ | ✅ |
| Storage CSV reports (`Export-SPCStorageReport -Format CSV`) | ✅ | ✅ | ✅ |
| Executive HTML ROI Dashboard (`Export-SPCStorageReport -Format HTML`) | — | ✅ | ✅ |
| Live 1st/2nd stage recycle bin purge (`Clear-SPCRecycleBin`) | — | ✅ | ✅ |
| Live document version trimming (`Optimize-SPCFileVersion`) | — | ✅ | ✅ |
| Automated document library version policy enforcement | — | ✅ | ✅ |
| **Enterprise & MSP Features** | | | |
| White-label HTML reports & dashboards (`-CompanyLogoUrl`, `-ClientName`) | — | — | ✅ |
| Priority technical support | — | — | ✅ |
| Intended use | Personal / evaluation | Single-org admin | MSP / multi-tenant consultant |

!!! info "Free tier"
    **Free** lets you scan every site collection, identify orphaned identities, analyze storage waste, and export CSV/JSON reports without a key — enough to perform comprehensive discovery and audits. **Pro** and **Consultant** unlock automated remediation, executive HTML ROI dashboards, and enterprise automation.

[→ Purchase on Gumroad](https://ngochung47.gumroad.com/){ .md-button .md-button--primary }

---

## Check your current license status

```powershell
Get-SPCLicenseInfo
```

Example output (unlicensed):

```
Status      : Unlicensed
Tier        : FREE
Email       :
ExpiresAt   :
```

---

## Activate a license

After purchasing from [Gumroad](https://ngochung47.gumroad.com/) you will receive a license key in standard UUID format by email.

```powershell
Register-SPCLicense -LicenseKey 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX'
```

The key is validated online against the Gumroad API, written to `%APPDATA%\SPClean\license.lic`, and takes effect immediately — no restart required. The status is cached locally for 7 days to support offline use before requiring a background re-verification.

Verify activation:

```powershell
Get-SPCLicenseInfo
```

```
Status      : Active
Tier        : PRO
Email       : you@contoso.com
ExpiresAt   : 2027-06-22T12:00:00.0000000Z
```

---

## What happens when a feature requires a license

```
Export-SPCReport: ERR-LIC-003: 'HTMLReport' requires a Pro or Consultant license.
Current status: Unlicensed.
→ Purchase at: https://ngochung47.gumroad.com/
→ Register with: Register-SPCLicense -LicenseKey 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX'
```

!!! tip "-WhatIf is never gated"
    `-WhatIf` on all write cmdlets always works without a license — preview is never restricted.

---

## Error codes

| Code | Meaning |
| --- | --- |
| `ERR-LIC-001` | Key format is invalid or cannot reach the API |
| `ERR-LIC-002` | Cannot write license file to disk |
| `ERR-LIC-003` | Feature requires a Pro or Consultant license |
| `ERR-LIC-004` | Feature requires a Consultant license |

---

## See also

- [`Register-SPCLicense`](cmdlets/register-spclicense.md) — activate a key
- [`Get-SPCLicenseInfo`](cmdlets/get-spclicenseinfo.md) — inspect current status
