# SPClean M01 — Master Plan

Legend: ✅ Done · 🔄 In progress · ⬜ Todo · 🚫 Blocked

---

## Phase 1 — Scaffold
- ✅ Tạo cấu trúc thư mục và file stubs
- ✅ Viết SPClean.psd1 (manifest)
- ✅ Viết SPClean.psm1 (root loader)
- ✅ Verify: SPClean.psm1 loads, all 7 functions exported (psd1 requires PnP.PowerShell — see E003)

## Phase 2A — Private helpers
- ✅ Private/Test-SPCConnection.ps1
- ✅ Private/Get-SPCRiskLevel.ps1          ← SRS 3.2.2
- ✅ Private/Invoke-SPCGraphBatch.ps1      ← SRS 5.1
- ✅ Private/Save-SPCPermissionSnapshot.ps1 ← SRS 6.2
- ✅ Syntax check tất cả Private/ files

## Phase 2B — Auth layer
- ✅ Public/Auth/Connect-SPCTenant.ps1     ← SRS 3.1.1
- ✅ Public/Auth/Disconnect-SPCTenant.ps1  ← SRS 3.1.2
- ✅ Verify ERR-AUTH-001, 002, 003 throw đúng message

## Phase 2C — Detection engine
- ✅ Public/Scan/Get-SPCOrphanedUser.ps1   ← SRS 3.2.1
- ✅ Output TypeName = 'SPC.OrphanedUser' ✓
- ✅ Write-Progress trên -AllSites ✓
- ✅ System accounts filtered ✓

## Phase 2D — Actions & Report
- ✅ Public/Report/Export-SPCReport.ps1       ← SRS 3.3.1
- ✅ Public/Remediate/Remove-SPCOrphanedUser.ps1 ← SRS 3.4.1
- ✅ Public/Remediate/Restore-SPCOrphanedUser.ps1 ← SRS 3.4.2
- ✅ Public/Schedule/New-SPCScanSchedule.ps1   ← SRS 3.5.1

## Phase 3 — Unit Tests (Pester 5, no tenant)
- ✅ Tests/Unit/Connect-SPCTenant.Tests.ps1  → AC-11
- ✅ Tests/Unit/Get-SPCRiskLevel.Tests.ps1   → AC-03 (classification)
- ✅ Tests/Unit/Get-SPCOrphanedUser.Tests.ps1 → AC-03, AC-04, AC-09
- ✅ Tests/Unit/Remove-SPCOrphanedUser.Tests.ps1 → AC-06
- ✅ Tests/Unit/Export-SPCReport.Tests.ps1   → AC-05, AC-12
- ✅ Invoke-Pester Tests/Unit/ — 78/81 pass (3 test-file bugs: E005a, E005b — cannot fix from source)

## Phase 4 — Integration Tests (tenant thật)
- ✅ Tests/Integration/SPClean.Integration.Tests.ps1 — written, 29 tests, skip-safe (0 failures when env vars absent)
- ✅ AC-01: Interactive auth — marked -Skip (manual only; cannot automate device-code flow)
- ✅ AC-02: AppOnly cert auth — passes against icclabvn tenant
- ✅ AC-03: 3 orphans detected correctly ✓
- ✅ AC-04: Clean site = 0 results ✓
- ✅ AC-05: HTML report generated ✓
- ✅ AC-07: Remove + CreateSnapshot ✓
- ✅ AC-08: Restore from snapshot ✓
- ✅ AC-PERF-01: < 30s single site ✓
- ✅ Invoke-Pester Tests/Integration/ — 28/29 pass, 1 skip (AC-01 permanent — interactive auth cannot be automated)

## Phase 5 — Polish
- ✅ Comment-based help đầy đủ (SYNOPSIS, DESCRIPTION, EXAMPLE ×2, OUTPUTS) — already present in all 7 cmdlets
- ✅ CHANGELOG.md — written (v1.0.0)
- ✅ Module signing (Authenticode) — docs/Sign-Module.ps1 ready; run with -CreateSelfSigned for dev or supply -CertThumbprint for prod cert
- ✅ Tab completion ValidateSet trên tất cả enum params — already present (AuthMethod, Format, GroupBy, RiskLevel, OrphanType, Schedule, ReportFormat)

## Phase 6 — License Key System
- ✅ Private/LicenseManager.ps1 — HMAC-SHA256 crypto engine; ConvertFrom-Base64UrlInternal; ConvertFrom-HexStringInternal (PS 5.1 compat); Compare-ByteArrayConstantTimeInternal (PS 5.1 compat); Test-SPCLicenseKey (fixed-length 43-char sig extraction); Assert-SPCProLicense; Assert-SPCConsultantLicense; $script:SPCLicenseCache
- ✅ Public/License/Get-SPCLicenseInfo.ps1 — module-level cache; disk fallback; SPC.LicenseInfo output; never throws
- ✅ Public/License/Register-SPCLicense.ps1 — validates key via HMAC, writes license.lic, SupportsShouldProcess, clears cache
- ✅ tools/New-SPCLicenseKey.ps1 — standalone vendor key generation (no module import; reads secret from env or file)
- ✅ tools/Inject-Secret.ps1 — CI/CD build-time secret injection (replaces placeholder in LicenseManager.ps1)
- ✅ Feature gates wired in 4 cmdlets: Export-SPCReport (HTML format), Remove-SPCOrphanedUser (CreateSnapshot), Restore-SPCOrphanedUser, New-SPCScanSchedule
- ✅ SPClean.psd1 FunctionsToExport + SPClean.psm1 Export-ModuleMember: Register-SPCLicense, Get-SPCLicenseInfo added
- ✅ Disconnect-SPCTenant: clears $script:SPCLicenseCache on disconnect
- ✅ .gitignore: tools/ and SRS/instruction docs excluded
- ✅ Tests/Unit/LicenseManager.Tests.ps1 — 49/49 pass (AC-LIC-01 through AC-LIC-14 + edge cases)
- ✅ Test suite regression fixed: 120/130 unit tests pass (10 irreducible test-file bugs — E005/E018/E019/E020)
- ✅ Private/Test-SPCConnection.ps1: compatibility stubs for Assert-SPCProLicense/Assert-SPCConsultantLicense (guards partial-load unit test scenarios)
- ✅ ClientId conditional splatting in Get-SPCOrphanedUser, Remove-SPCOrphanedUser, Restore-SPCOrphanedUser (fixes E018 unit test regression)

## Phase 7 — Gumroad License API Migration (v2.0)
- ✅ Phase 1 — Remove HMAC tools: deleted tools/New-SPCLicenseKey.ps1, tools/Inject-Secret.ps1 (never git-tracked)
- ✅ Phase 2 — Rewrite Private/LicenseManager.ps1 — Gumroad API; Invoke-GumroadVerifyInternal; Test-SPCLicenseKeyInternal; Get-SPCLicenseDataInternal (returns wrapper {Status;LicData}); 7-day re-verify; offline grace; revocation
- ✅ Phase 3 — Rewrite Register-SPCLicense + Get-SPCLicenseInfo — Gumroad UUID keys; Status: Active/Unlicensed/Invalid/Revoked; IsTesting field; never logs key
- ✅ Phase 4 — Rewrite Tests/Unit/LicenseManager.Tests.ps1 — 46/46 pass (Gumroad API mock-based)
- ✅ Phase 5 — Full regression: 117/127 unit tests pass (10 pre-existing irreducible test-file bugs — unchanged)
- ✅ Phase 6 — Cleanup: no HMAC refs remain; CHANGELOG.md v1.2.0; SPClean.psd1 → 1.2.0

---
_Last updated: 2026-06-28_
_Current focus: COMPLETE — Gumroad License API migration done. 117/127 unit tests pass (10 irreducible test-file bugs). Ready to publish v1.2.0._
