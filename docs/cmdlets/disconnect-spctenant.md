# Disconnect-SPCTenant

Clears the SPClean module connection state and disconnects both PnP and Microsoft Graph sessions.

## Synopsis

```powershell
Disconnect-SPCTenant
```

## Parameters

None.

## Returns

Nothing. This cmdlet never throws — it is safe to call even when no connection is active.

## Behavior

- Disconnects the active PnP.PowerShell session
- Disconnects the Microsoft Graph session
- Clears `$script:SPCContext` (the module-level connection object)
- Clears the license cache (`$script:SPCLicenseCache`)

## Examples

```powershell
# Standard disconnect after a scan session
Connect-SPCTenant -TenantName contoso -ClientId '<app-id>'
Get-SPCOrphanedUser -AllSites | Export-SPCReport -Format CSV
Disconnect-SPCTenant
```

## See also

- [Connect-SPCTenant](connect-spctenant.md)
