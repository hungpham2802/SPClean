# Changelog

All notable changes to SPClean are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow [Semantic Versioning](https://semver.org/).

---

## [1.1.3] — 2026-06-27

[PowerShell Gallery](https://www.powershellgallery.com/packages/SPClean/1.1.3) · [GitHub](https://github.com/hungpham2802/SPClean/releases/tag/v1.1.3)

### Fixed
- `Export-SPCReport` HTML footer: version displayed as `System.Object[]` when multiple module instances loaded. Fixed by adding `Select-Object -First 1` when calling `Get-Module SPClean`.

---

## [1.1.2] — 2026-06-27

[PowerShell Gallery](https://www.powershellgallery.com/packages/SPClean/1.1.2) · [GitHub](https://github.com/hungpham2802/SPClean/releases/tag/v1.1.2)

### Fixed
- CI publish workflow: inject HMAC secret into `Private/LicenseManager.ps1` before packaging — published module now validates license keys correctly (previously shipped with placeholder, breaking `Register-SPCLicense`)
- Interactive auth documentation: add `http://localhost` as required redirect URI for Mobile and desktop platform (missing entry caused AADSTS50011 on first-time app setup)

---

## [1.1.1] — 2026-06-27

[PowerShell Gallery](https://www.powershellgallery.com/packages/SPClean/1.1.1) · [GitHub](https://github.com/hungpham2802/SPClean/releases/tag/v1.1.1)

### Fixed
- Exclude `.git` folder from PSGallery package by removing it before `Publish-PSResource` runs in CI

---

## [1.1.0] — 2026-06-26

[PowerShell Gallery](https://www.powershellgallery.com/packages/SPClean/1.1.0) · [GitHub](https://github.com/hungpham2802/SPClean/releases/tag/v1.1.0)

### Added
- **Register-SPCLicense** — activates a `SPCLEAN-PRO-…` or `SPCLEAN-CONSULTANT-…` key; validated offline via HMAC-SHA256 with no network calls; writes `%APPDATA%\SPClean\license.lic`; supports `-WhatIf`, `-Confirm`, `-Force`
- **Get-SPCLicenseInfo** — returns current license status (`Active` / `Expired` / `Invalid` / `Unlicensed`), tier (`FREE` / `PRO` / `CONSULTANT`), email, expiry, and registration date; reads from in-memory cache then disk; never throws
- **License feature gates** — HTML report (`Export-SPCReport -Format HTML`), permission snapshot (`Remove-SPCOrphanedUser -CreateSnapshot`), restore (`Restore-SPCOrphanedUser`), and scheduled scan (`New-SPCScanSchedule`) now require a Pro or Consultant license; `-WhatIf` on all write cmdlets remains ungated
- **`Private/LicenseManager.ps1`** — crypto engine: `Test-SPCLicenseKey` (fixed-length 43-char sig extraction), `Assert-SPCProLicense`, `Assert-SPCConsultantLicense`, `$script:SPCLicenseCache`; PS 5.1-compatible Base64URL and constant-time byte comparison helpers
- **MkDocs Material documentation site** at `https://hungpham2802.github.io/spclean` — Getting Started, full cmdlet reference (one page per cmdlet), Licensing section with pricing and activation guide

### Changed
- `Disconnect-SPCTenant` now clears `$script:SPCLicenseCache` on disconnect
- `SPClean.psd1` FunctionsToExport updated to include `Register-SPCLicense` and `Get-SPCLicenseInfo`
- Interactive auth `$connectToSite` blocks now use conditional splatting for `-ClientId` to avoid empty-string parameter rejection in PnP 3.x when ClientId is null

### Fixed
- `Private/Test-SPCConnection.ps1` — added no-op compatibility stubs for `Assert-SPCProLicense` / `Assert-SPCConsultantLicense` so existing unit tests that dot-source this file directly do not fail with `CommandNotFoundException`

### Security
- License keys are verified with constant-time byte comparison to prevent timing attacks
- HMAC secret is injected at CI build time via `tools/Inject-Secret.ps1`; the placeholder value in source is non-functional

---

## [1.0.0] — 2026-06-23

[PowerShell Gallery](https://www.powershellgallery.com/packages/SPClean/1.0.0) · [GitHub](https://github.com/hungpham2802/SPClean/releases/tag/v1.0.0)

### Added
- **Connect-SPCTenant** — AppOnly (certificate or client secret) and interactive authentication against SharePoint Online and Microsoft Graph (SRS 3.1.1)
- **Disconnect-SPCTenant** — clears module connection state, disconnects PnP and MgGraph sessions (SRS 3.1.2)
- **Get-SPCOrphanedUser** — detects orphaned users in a site's User Information List by cross-referencing Entra ID via Graph batch API; classifies as `Deleted`, `SoftDeleted`, `Disabled`, or `GuestOrphaned`; supports `-AllSites` enumeration with progress reporting (SRS 3.2.1)
- **Export-SPCReport** — exports orphaned user findings to CSV, HTML, or JSON; HTML output is self-contained with colour-coded risk badges (`HIGH`/#dc3545, `MEDIUM`/#ffc107, `LOW`/#28a745) and sortable columns (SRS 3.3.1)
- **Remove-SPCOrphanedUser** — removes orphaned users from the SharePoint UIL with mandatory `-WhatIf`/`-Confirm` support; optional `-CreateSnapshot` saves a JSON permission snapshot before removal (SRS 3.4.1)
- **Restore-SPCOrphanedUser** — re-applies permissions from a snapshot file created by `Remove-SPCOrphanedUser -CreateSnapshot`; supports `-WhatIf` (SRS 3.4.2)
- **New-SPCScanSchedule** — generates a standalone scan script and registers a Windows Scheduled Task (Daily/Weekly/Monthly) or produces a cron expression on non-Windows hosts (SRS 3.5.1)
- **Private helpers**: `Test-SPCConnection` (connection guard), `Get-SPCRiskLevel` (SRS 3.2.2 risk classification), `Invoke-SPCGraphBatch` (Graph `$batch` with 429 exponential backoff), `Save-SPCPermissionSnapshot` (SRS 6.2 snapshot schema)
- **Pester 5 unit tests** — 78/81 passing; 3 irreducible failures are bugs in the test file (E005a, E005b)
- **Pester 5 integration tests** — 29 tests, skip-safe when `SPC_*` env vars absent

### Security
- `SecureString` parameters never converted to plain text or logged
- All write cmdlets support `-WhatIf` and `-Confirm`
- No data transmitted to third-party endpoints — only `graph.microsoft.com` and SharePoint tenant URLs
- Permission snapshots stored locally; snapshot path configurable

### Notes
- Requires PnP.PowerShell 2.0.0+ and Microsoft.Graph.Authentication 2.0.0+
- Tested against PnP.PowerShell 3.2.0 and Microsoft.Graph.Authentication 2.38.0
- PowerShell 5.1 compatible; PS 7+ also supported
