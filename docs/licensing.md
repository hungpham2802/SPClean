# Licensing

SPClean uses a **key-based license** verified entirely offline — no internet check, no phone-home.

## Tiers

| Feature | Free | Pro | Consultant |
| --- | :---: | :---: | :---: |
| **Price** | $0 forever | **$79 / tenant / year** | **$149 / year** |
| Orphan detection (`Get-SPCOrphanedUser`) | ✅ | ✅ | ✅ |
| CSV and JSON reports | ✅ | ✅ | ✅ |
| Unlimited sites per scan | ✅ | ✅ | ✅ |
| HTML report with risk badges and sorting | — | ✅ | ✅ |
| Snapshot backup before removal (`-CreateSnapshot`) | — | ✅ | ✅ |
| Restore permissions from snapshot | — | ✅ | ✅ |
| Scheduled automated scans | — | ✅ | ✅ |
| **Unlimited tenants** | — | — | ✅ |
| White-label HTML report (`-BrandingName`) | — | — | 🔜 v1.1 |
| Priority support | — | — | ✅ |
| Intended use | Personal / evaluation | Single-org admin | MSP / multi-tenant consultant |

!!! info "Free tier"
    **Free** lets you scan every site and export CSV/JSON reports without a key — enough to identify and audit orphans. **Pro** and **Consultant** unlock the full remediation and automation workflow.

[→ Purchase on Gumroad](https://hungpham2802.gumroad.com){ .md-button .md-button--primary }

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

After purchasing from [Gumroad](https://hungpham2802.gumroad.com) you will receive a key in the format `SPCLEAN-PRO-…` by email.

```powershell
Register-SPCLicense -LicenseKey 'SPCLEAN-PRO-<payload>-<sig>'
```

The key is validated offline (HMAC-SHA256), written to `%APPDATA%\SPClean\license.lic`, and takes effect immediately — no restart required.

Verify activation:

```powershell
Get-SPCLicenseInfo
```

```
Status      : Active
Tier        : PRO
Email       : you@contoso.com
ExpiresAt   : 2027-06-25 00:00:00
```

---

## What happens when a feature requires a license

```
Export-SPCReport: ERR-LIC-003: 'HTMLReport' requires a Pro or Consultant license.
Current status: Unlicensed.
→ Purchase at: https://hungpham2802.gumroad.com
→ Register with: Register-SPCLicense -LicenseKey 'SPCLEAN-PRO-...'
```

!!! tip "-WhatIf is never gated"
    `-WhatIf` on all write cmdlets always works without a license — preview is never restricted.

---

## Error codes

| Code | Meaning |
| --- | --- |
| `ERR-LIC-001` | Key format is invalid or signature does not match |
| `ERR-LIC-002` | Key has expired |
| `ERR-LIC-003` | Feature requires a Pro or Consultant license |
| `ERR-LIC-004` | Feature requires a Consultant license |

---

## See also

- [`Register-SPCLicense`](cmdlets/register-spclicense.md) — activate a key
- [`Get-SPCLicenseInfo`](cmdlets/get-spclicenseinfo.md) — inspect current status
