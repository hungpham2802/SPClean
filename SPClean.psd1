@{
    RootModule        = 'SPClean.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = 'a9e193ea-b393-4c4a-ac23-ab50dceef965'
    Author            = 'Hung Pham'          # TODO: replace with your name
    CompanyName       = 'Community'       # TODO: replace or set to 'Community'
    Copyright         = '(c) 2026 Hung Pham. Licensed under the MIT License.'
    Description       = 'Detects, reports, and remediates orphaned users in SharePoint Online. Identifies accounts in the User Information List whose Entra ID state is Deleted, SoftDeleted, Disabled, or GuestOrphaned. Supports AppOnly (certificate) and Interactive authentication, HTML/CSV/JSON reports, permission snapshots, and Windows Scheduled Task automation.'
    PowerShellVersion = '5.1'

    RequiredModules   = @(
        @{ ModuleName = 'PnP.PowerShell'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0' }
    )

    FunctionsToExport = @(
        'Connect-SPCTenant'
        'Disconnect-SPCTenant'
        'Get-SPCOrphanedUser'
        'Export-SPCReport'
        'Remove-SPCOrphanedUser'
        'Restore-SPCOrphanedUser'
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
## 1.1.0 — 2026-06-26
- Register-SPCLicense: offline HMAC-SHA256 license key activation
- Get-SPCLicenseInfo: query current tier (FREE / PRO / CONSULTANT)
- Feature gates: HTML report, CreateSnapshot, Restore, Schedule require Pro/Consultant
- MkDocs Material documentation site (https://hungpham2802.github.io/spclean)

## 1.0.0 — 2026-06-22
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
