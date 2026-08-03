# Get-SPCOverPermissionedUser

## SYNOPSIS
Identifies users with a high number of direct permission assignments across the tenant.

## DESCRIPTION
This cmdlet scans all site collections to find users who have excessive direct permissions (breaking role inheritance) rather than being properly managed via SharePoint groups. It returns the top 20 users with the highest count of direct permissions.

## SYNTAX

```powershell
Get-SPCOverPermissionedUser 
    [-ClientId <String>] 
    [-Thumbprint <String>] 
    [-Tenant <String>] 
    [<CommonParameters>]
```

## EXAMPLES

### Example 1
```powershell
Get-SPCOverPermissionedUser -ClientId "app-id" -Thumbprint "cert-thumb" -Tenant "tenant.onmicrosoft.com"
```
Returns the top 20 over-permissioned users.

## PARAMETERS

### -ClientId
The App ID (Client ID) of the Entra ID application registration.

### -Thumbprint
The thumbprint of the certificate used for AppOnly authentication.

### -Tenant
The tenant domain name (e.g., `contoso.onmicrosoft.com`).

## INPUTS
### None

## OUTPUTS
### System.Management.Automation.PSCustomObject
Returns custom objects representing the over-permissioned users.
