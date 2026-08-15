# Cmdlet Reference

SPClean exports 16 cmdlets grouped by module and function.

## Permission Hygiene & Orphaned Users

| Cmdlet | Type | Description |
| --- | --- | --- |
| [Connect-SPCTenant](connect-spctenant.md) | Auth | Establish a SharePoint Online + Graph session |
| [Disconnect-SPCTenant](disconnect-spctenant.md) | Auth | Clear the module connection state |
| [Get-SPCOrphanedUser](get-spcorphaneduser.md) | Scan | Scan sites and return orphaned user objects |
| [Get-SPCPrivilegedUser](get-spcprivilegeduser.md) | Scan | Get the top privileged users across the tenant |
| [Get-SPCOverPermissionedUser](get-spcoverpermissioneduser.md) | Scan | Identify users with excessive direct permission assignments |
| [Get-SPCGuestAccess](get-spcguestaccess.md) | Scan | List all external/guest users with access to a site |
| [Get-SPCMismatchUser](get-spcmismatchuser.md) | Scan | Scan sites to identify User ID Mismatch issues |
| [Repair-SPCMismatchUser](repair-spcmismatchuser.md) | Remediate | Repair User ID Mismatch issues safely |
| [Remove-SPCOrphanedUser](remove-spcorphaneduser.md) | Remediate | Remove orphaned users from UILs and revoke direct permissions |
| [Restore-SPCOrphanedUser](restore-spcorphaneduser.md) | Remediate | Re-apply permissions from a JSON snapshot |
| [Export-SPCReport](export-spcreport.md) | Report | Generate CSV, HTML, or JSON reports from scan results |
| [New-SPCScanSchedule](new-spcscanschedule.md) | Util | Register a Windows Scheduled Task for automated scans |
| [Register-SPCLicense](register-spclicense.md) | Util | Validate and activate a license key |
| [Get-SPCLicenseInfo](get-spclicenseinfo.md) | Util | Return the current license status |

## Storage Optimization

| Cmdlet | Type | Description |
| --- | --- | --- |
| [Get-SPCStorageWaste](Get-SPCStorageWaste.md) | Scan | Discover and quantify storage waste across recycle bins, versions, and PHL |
| [Get-SPCVersionWaste](Get-SPCVersionWaste.md) | Scan | Analyze document library version sprawl and calculate recoverable MB |
| [Get-SPCPreservationHoldWaste](Get-SPCPreservationHoldWaste.md) | Scan | Audit Preservation Hold Library locked storage and alert levels |
| [Get-SPCInactiveSite](Get-SPCInactiveSite.md) | Scan | Identify dormant/stale SharePoint sites and calculate cost avoidance |
| [Clear-SPCRecycleBin](Clear-SPCRecycleBin.md) | Remediate | Purge 1st & 2nd stage recycle bins safely with Purview hold protection |
| [Optimize-SPCFileVersion](Optimize-SPCFileVersion.md) | Remediate | Trim redundant historical versions and update library version limits |
| [Export-SPCStorageReport](Export-SPCStorageReport.md) | Report | Generate Executive HTML ROI Dashboards and CSV reports |

---

## License requirements

| Feature | Free | Pro | Consultant |
| --- | :---: | :---: | :---: |
| **Permission Hygiene** | | | |
| `Get-SPCOrphanedUser`, `Get-SPCMismatchUser` | ✅ | ✅ | ✅ |
| `Export-SPCReport -Format CSV\|JSON` | ✅ | ✅ | ✅ |
| `Export-SPCReport -Format HTML` | — | ✅ | ✅ |
| `Remove-SPCOrphanedUser -CreateSnapshot` | — | ✅ | ✅ |
| `Restore-SPCOrphanedUser` | — | ✅ | ✅ |
| `New-SPCScanSchedule` | — | ✅ | ✅ |
| **Storage Optimization** | | | |
| Storage & Version Scans (`Get-SPC*Waste`, `Get-SPCInactiveSite`) | ✅ | ✅ | ✅ |
| CSV Reports (`Export-SPCStorageReport -Format CSV`) | ✅ | ✅ | ✅ |
| Simulation Modes (`-DryRun` / `-WhatIf`) | ✅ | ✅ | ✅ |
| Executive HTML ROI Dashboard (`Export-SPCStorageReport -Format HTML`) | — | ✅ | ✅ |
| Live Recycle Bin Purge (`Clear-SPCRecycleBin`) | — | ✅ | ✅ |
| Live File Version Trimming (`Optimize-SPCFileVersion`) | — | ✅ | ✅ |
| White-Label Dashboard Branding (`-CompanyLogoUrl`, `-ClientName`) | — | — | ✅ |

See [Licensing](../licensing.md) for details and pricing.

