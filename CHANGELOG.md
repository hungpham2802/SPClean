# Changelog

All notable changes to SPClean are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow [Semantic Versioning](https://semver.org/).

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
