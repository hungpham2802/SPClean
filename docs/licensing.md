# Licensing

SPClean uses a **key-based license** verified entirely offline â€” no internet check, no phone-home.

## Tiers

| Feature | Free | Pro | Consultant |
| --- | :---: | :---: | :---: |
| **Price** | $0 forever | **$79 / tenant / year** | **$149 / year** |
| Orphan detection (`Get-SPCOrphanedUser`) | âœ… | âœ… | âœ… |
| CSV and JSON reports | âœ… | âœ… | âœ… |
| Unlimited sites per scan | âœ… | âœ… | âœ… |
| HTML report with risk badges and sorting | â€” | âœ… | âœ… |
| Snapshot backup before removal (`-CreateSnapshot`) | â€” | âœ… | âœ… |
| Restore permissions from snapshot | â€” | âœ… | âœ… |
| Scheduled automated scans | â€” | âœ… | âœ… |
| **Unlimited tenants** | â€” | â€” | âœ… |
| White-label HTML report (`-BrandingName`) | â€” | â€” | âœ… |
| Priority support | â€” | â€” | âœ… |
| Intended use | Personal / evaluation | Single-org admin | MSP / multi-tenant consultant |

!!! info "Free tier"
    **Free** lets you scan every site and export CSV/JSON reports without a key â€” enough to identify and audit orphans. **Pro** and **Consultant** unlock the full remediation and automation workflow.

[â†’ Purchase on Gumroad](https://ngochung47.gumroad.com/){ .md-button .md-button--primary }

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

The key is validated online against the Gumroad API, written to `%APPDATA%\SPClean\license.lic`, and takes effect immediately â€” no restart required. The status is cached locally for 7 days to support offline use before requiring a background re-verification.

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
â†’ Purchase at: https://ngochung47.gumroad.com/
â†’ Register with: Register-SPCLicense -LicenseKey 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX'
```

!!! tip "-WhatIf is never gated"
    `-WhatIf` on all write cmdlets always works without a license â€” preview is never restricted.

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

- [`Register-SPCLicense`](cmdlets/register-spclicense.md) â€” activate a key
- [`Get-SPCLicenseInfo`](cmdlets/get-spclicenseinfo.md) â€” inspect current status
