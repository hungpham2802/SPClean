@{
    RootModule        = 'SPClean.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = 'a9e193ea-b393-4c4a-ac23-ab50dceef965'
    Author            = 'David Pham'          
    CompanyName       = 'M365Automation.com'       
    Copyright         = '(c) 2026 David Pham. Licensed under the MIT License.'
    Description       = 'Keep your SharePoint Online environment clean, secure, and compliant. SPClean helps Microsoft 365 administrators quickly discover orphaned users, stale identities, and disconnected guest accounts that can create security and governance risks. With automated detection, detailed reporting, and remediation capabilities, SPClean turns hours of manual investigation into a repeatable and scalable process. Supports App-Only authentication, scheduled execution, permission snapshots, and HTML/CSV/JSON reporting.'
    PowerShellVersion = '7.0'

    RequiredModules   = @(
        @{ ModuleName = 'PnP.PowerShell'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0' }
    )

    FunctionsToExport = @(
        'Connect-SPCTenant'
        'Disconnect-SPCTenant'
        'Get-SPCOrphanedUser'
        'Get-SPCMismatchUser'
        'Export-SPCReport'
        'Remove-SPCOrphanedUser'
        'Restore-SPCOrphanedUser'
        'Repair-SPCMismatchUser'
        'New-SPCScanSchedule'
        'Register-SPCLicense'
        'Get-SPCLicenseInfo'
        'Get-SPCGuestAccess'
        'Get-SPCPrivilegedUser'
        'Get-SPCOverPermissionedUser'
        'Get-SPCPermissionHealthScore'
        'Get-SPCBrokenInheritance'
        'Compare-SPCPermissionSnapshot'
        'Invoke-SPCDashboardReport'
        'Invoke-SPCPermissionAnalytics'
        'Get-SPCStorageWaste'
        'Get-SPCInactiveSite'
        'Get-SPCVersionWaste'
        'Get-SPCPreservationHoldWaste'
        'Clear-SPCRecycleBin'
        'Optimize-SPCFileVersion'
        'Export-SPCStorageReport'
    )

    CmdletsToExport   = @()
    AliasesToExport   = @(
        'Invoke-SPCDashboardReportV1'
        'Invoke-SPCPermissionAnalyticsV2'
    )
    VariablesToExport = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('SharePoint', 'SPO', 'SharePointOnline', 'Orphaned',
                'Cleanup', 'M365', 'MicrosoftGraph', 'PnP',
                'Governance', 'Remediation', 'EntraID', 'Storage', 'Optimization')
            ProjectUri   = 'https://github.com/hungpham2802/SPClean'
            LicenseUri   = 'https://github.com/hungpham2802/SPClean/blob/main/LICENSE'
            ReleaseNotes = @'
## 2.0.0 - 2026-08-15
- Major Feature: SharePoint Online Storage Optimization & Digital Waste Management.
- New Scan Cmdlets: `Get-SPCStorageWaste`, `Get-SPCInactiveSite`, `Get-SPCVersionWaste`, `Get-SPCPreservationHoldWaste`.
- New Remediation Cmdlets: `Clear-SPCRecycleBin` (safe 1st & 2nd stage purge with `-DryRun` / `-WhatIf`), `Optimize-SPCFileVersion` (version history trimming and policy enforcement).
- New Reporting Cmdlet: `Export-SPCStorageReport` (Executive standalone HTML ROI Dashboard with interactive slider and CSV audit dataset).
- Security & Compliance: Non-destructive Microsoft Purview Preservation Hold Library (PHL) immunity protection.
- Architecture: Centralized PnP wrapper layer in `Private/PnPWrappers.ps1` with PnP 3.2.0 compatibility and zero unmanaged memory residue (`ZeroFreeBSTR`).
- Performance: Exponential backoff with jitter retry on Microsoft Graph 429 throttling and automatic fallback to SharePoint Online Admin API.

## 1.6.0 - 2026-08-14
- Security: Connect-SPCTenant pipeline output sanitized to remove raw GraphAccessToken; provides IsGraphConnected and TokenExpiresAt.
- Security: Get-SPCOrphanedUser escapes single quotes and URI encodes UPNs in Graph OData queries.
- Refactor: Standardized cmdlet names Invoke-SPCDashboardReport and Invoke-SPCPermissionAnalytics with backward-compatible aliases.
- Refactor: Centralized per-site connection logic into Private/Connect-SPCSiteInternal.ps1.
- Refactor: Renamed scoring engine to Measure-SPCScoreInternal adhering to PowerShell approved verbs.
- Refactor: Separated skippedCount from errorCount in Remove-SPCOrphanedUser.
- Architecture: Snapshot schema bumped to v1.1 with isEmptyPermissionSet flag; Restore-SPCOrphanedUser supports both v1.0 and v1.1.

## 1.5.2 - 2026-08-01
- Feature: Permission Health Score calculation and broken inheritance analytics.

## 1.3.0 - 2026-07-17
- Feature: Added `Get-SPCMismatchUser` to detect User ID Mismatches between SharePoint UIL and Entra ID.
- Feature: Added `Repair-SPCMismatchUser` to automatically backup, clean, and restore Web and List level permissions for mismatched users.

## 1.2.3 - 2026-07-15
- Fix: Guest users are now correctly skipped during Mismatch Repair.

## 1.1.6 - 2026-06-27
- Fix: New-SPCScanSchedule scheduled task no longer opens a visible PowerShell window (-WindowStyle Hidden added)

## 1.1.5 - 2026-06-27
- Fix: New-SPCScanSchedule incorrectly detected Windows as non-Windows (Get-Variable $IsWindows unreliable inside module scope); replaced with [System.Environment]::OSVersion.Platform check

## 1.1.4 - 2026-06-27
- Fix: New-SPCScanSchedule -OutputPath alias added (parameter was named -ReportOutputPath, causing ParameterNotFound error)
- Docs: Restore-SPCOrphanedUser limitations - clarify soft-deleted accounts must be restored in Entra first

## 1.1.3 - 2026-06-27
- Fix: Export-SPCReport HTML footer shows correct version instead of System.Object[]

## 1.1.2 - 2026-06-27
- Fix: CI publish workflow now injects HMAC secret before packaging (license key validation works in published module)
- Fix: Interactive auth docs - add http://localhost redirect URI requirement (AADSTS50011)

## 1.1.1 - 2026-06-27
- Fix: exclude .git folder from PSGallery package

## 1.1.0 - 2026-06-26
- Register-SPCLicense: offline HMAC-SHA256 license key activation
- Get-SPCLicenseInfo: query current tier (FREE / PRO / CONSULTANT)
- Feature gates: HTML report, CreateSnapshot, Restore, Schedule require Pro/Consultant
- MkDocs Material documentation site (https://hungpham2802.github.io/SPClean)

## 1.0.0 - 2026-06-22
- Connect-SPCTenant: Interactive and AppOnly (certificate/secret) auth
- Get-SPCOrphanedUser: detects Deleted, SoftDeleted, Disabled, GuestOrphaned accounts
- Export-SPCReport: CSV, HTML (colour-coded risk badges), JSON output
- Remove-SPCOrphanedUser: removes users with WhatIf/Confirm/CreateSnapshot support
- Restore-SPCOrphanedUser: re-applies permissions from JSON snapshot
- New-SPCScanSchedule: Windows Scheduled Task automation
'@
        }
    }
}
