# Cmdlet Reference

SPClean exports 9 cmdlets grouped by function.

| Cmdlet | Type | Description |
| --- | --- | --- |
| [Connect-SPCTenant](connect-spctenant.md) | Auth | Establish a SharePoint Online + Graph session |
| [Disconnect-SPCTenant](disconnect-spctenant.md) | Auth | Clear the module connection state |
| [Get-SPCOrphanedUser](get-spcorphaneduser.md) | Read | Scan sites and return orphaned user objects |
| [Export-SPCReport](export-spcreport.md) | Report | Generate CSV, HTML, or JSON reports from scan results |
| [Remove-SPCOrphanedUser](remove-spcorphaneduser.md) | Write | Remove orphaned users from UILs and revoke direct permissions |
| [Restore-SPCOrphanedUser](restore-spcorphaneduser.md) | Write | Re-apply permissions from a JSON snapshot |
| [New-SPCScanSchedule](new-spcscanschedule.md) | Util | Register a Windows Scheduled Task for automated scans |
| [Register-SPCLicense](register-spclicense.md) | Util | Validate and activate a license key |
| [Get-SPCLicenseInfo](get-spclicenseinfo.md) | Util | Return the current license status |

---

## Typical workflow

```
Connect-SPCTenant
       ↓
Get-SPCOrphanedUser   →   Export-SPCReport
       ↓
Remove-SPCOrphanedUser  (with -CreateSnapshot)
       ↓
Restore-SPCOrphanedUser  (if rollback needed)
       ↓
Disconnect-SPCTenant
```

---

## License requirements

| Feature | Free | Pro | Consultant |
| --- | :---: | :---: | :---: |
| `Get-SPCOrphanedUser` | ✅ | ✅ | ✅ |
| `Export-SPCReport -Format CSV\|JSON` | ✅ | ✅ | ✅ |
| `Export-SPCReport -Format HTML` | — | ✅ | ✅ |
| `Remove-SPCOrphanedUser -CreateSnapshot` | — | ✅ | ✅ |
| `Restore-SPCOrphanedUser` | — | ✅ | ✅ |
| `New-SPCScanSchedule` | — | ✅ | ✅ |

See [Licensing](../licensing.md) for details and pricing.
