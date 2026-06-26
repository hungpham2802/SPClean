# Installation

## Requirements

| Requirement | Minimum version |
| --- | --- |
| PowerShell | 5.1 or 7+ |
| PnP.PowerShell | 2.0.0 (tested on 3.2.0) |
| Microsoft.Graph.Authentication | 2.0.0 (tested on 2.38.0) |
| SharePoint Online role | Site Collection Administrator (single site) or SharePoint Administrator (all sites) |
| Entra ID role | At least User Administrator (read-only scan) |

## Install dependencies

```powershell
Install-Module PnP.PowerShell                 -Scope CurrentUser -Force
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
```

## Install SPClean

=== "PSResourceGet (recommended)"

    ```powershell
    Install-PSResource -Name SPClean
    ```

=== "PowerShellGet (legacy)"

    ```powershell
    Install-Module -Name SPClean
    ```

[![PSGallery](https://img.shields.io/powershellgallery/v/SPClean?label=PSGallery&color=5391FE&logo=powershell&logoColor=white)](https://www.powershellgallery.com/packages/SPClean)
[![PSGallery Downloads](https://img.shields.io/powershellgallery/dt/SPClean?label=Downloads&color=28a745)](https://www.powershellgallery.com/packages/SPClean)

## Install from source

```powershell
# Import directly from the cloned repo
Import-Module .\SPClean\SPClean.psd1 -Force

# Or copy to your module path for auto-load
Copy-Item .\SPClean -Destination "$HOME\Documents\PowerShell\Modules\SPClean" -Recurse
Import-Module SPClean
```

## Verify the import

```powershell
Get-Command -Module SPClean
```

Expected cmdlets:

```
Connect-SPCTenant
Disconnect-SPCTenant
Get-SPCOrphanedUser
Export-SPCReport
Remove-SPCOrphanedUser
Restore-SPCOrphanedUser
New-SPCScanSchedule
Register-SPCLicense
Get-SPCLicenseInfo
```

---

## Next step

[Set up authentication →](authentication.md){ .md-button .md-button--primary }
