@{
    RootModule        = 'SPClean.psm1'
    ModuleVersion     = '1.3.1'
    GUID              = 'a9e193ea-b393-4c4a-ac23-ab50dceef965'
    Author            = 'David Pham'          
    CompanyName       = 'M365Automation.com'       
    Copyright         = '(c) 2026 David Pham. Licensed under the MIT License.'
    Description       = 'Detects, reports, and remediates orphaned users in SharePoint Online. Identifies accounts in the User Information List whose Entra ID state is Deleted, SoftDeleted, Disabled, or GuestOrphaned. Supports AppOnly (certificate) and Interactive authentication, HTML/CSV/JSON reports, permission snapshots, and Windows Scheduled Task automation.'
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
    )

    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('SharePoint', 'SPO', 'SharePointOnline', 'Orphaned',
                'Cleanup', 'M365', 'MicrosoftGraph', 'PnP',
                'Governance', 'Remediation', 'EntraID')
            ProjectUri   = 'https://github.com/hungpham2802/SPClean'
            LicenseUri   = 'https://github.com/hungpham2802/SPClean/blob/main/LICENSE'
            ReleaseNotes = @'
## 1.3.0 - 2026-07-17
- Feature (Module 2): Added `Get-SPCMismatchUser` to detect User ID Mismatches between SharePoint UIL and Entra ID.
- Feature (Module 2): Added `Repair-SPCMismatchUser` to automatically backup, clean, and restore Web and List level permissions for mismatched users.

## 1.2.3 - 2026-07-15
- Fix: Guest users are now correctly skipped during Mismatch Repair.

## 1.1.6 - 2026-06-27
- Fix: New-SPCScanSchedule scheduled task no longer opens a visible PowerShell window (-WindowStyle Hidden added)

## 1.1.5 â€” 2026-06-27
- Fix: New-SPCScanSchedule incorrectly detected Windows as non-Windows (Get-Variable $IsWindows unreliable inside module scope); replaced with [System.Environment]::OSVersion.Platform check

## 1.1.4 â€” 2026-06-27
- Fix: New-SPCScanSchedule -OutputPath alias added (parameter was named -ReportOutputPath, causing ParameterNotFound error)
- Docs: Restore-SPCOrphanedUser limitations â€” clarify soft-deleted accounts must be restored in Entra first

## 1.1.3 â€” 2026-06-27
- Fix: Export-SPCReport HTML footer shows correct version instead of System.Object[]

## 1.1.2 â€” 2026-06-27
- Fix: CI publish workflow now injects HMAC secret before packaging (license key validation works in published module)
- Fix: Interactive auth docs â€” add http://localhost redirect URI requirement (AADSTS50011)

## 1.1.1 â€” 2026-06-27
- Fix: exclude .git folder from PSGallery package

## 1.1.0 â€” 2026-06-26
- Register-SPCLicense: offline HMAC-SHA256 license key activation
- Get-SPCLicenseInfo: query current tier (FREE / PRO / CONSULTANT)
- Feature gates: HTML report, CreateSnapshot, Restore, Schedule require Pro/Consultant
- MkDocs Material documentation site (https://hungpham2802.github.io/SPClean)

## 1.0.0 â€” 2026-06-22
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
