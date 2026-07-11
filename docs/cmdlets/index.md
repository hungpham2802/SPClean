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
       â†“
Get-SPCOrphanedUser   â†’   Export-SPCReport
       â†“
Remove-SPCOrphanedUser  (with -CreateSnapshot)
       â†“
Restore-SPCOrphanedUser  (if rollback needed)
       â†“
Disconnect-SPCTenant
```

---

## License requirements

| Feature | Free | Pro | Consultant |
| --- | :---: | :---: | :---: |
| `Get-SPCOrphanedUser` | âœ… | âœ… | âœ… |
| `Export-SPCReport -Format CSV\|JSON` | âœ… | âœ… | âœ… |
| `Export-SPCReport -Format HTML` | â€” | âœ… | âœ… |
| `Remove-SPCOrphanedUser -CreateSnapshot` | â€” | âœ… | âœ… |
| `Restore-SPCOrphanedUser` | â€” | âœ… | âœ… |
| `New-SPCScanSchedule` | â€” | âœ… | âœ… |

See [Licensing](../licensing.md) for details and pricing.
