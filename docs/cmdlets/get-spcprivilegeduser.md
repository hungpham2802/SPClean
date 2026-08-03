# Get-SPCPrivilegedUser

## SYNOPSIS
Gets the top 20 privileged users across the SharePoint tenant.

## DESCRIPTION
This cmdlet scans all site collections to identify users who are Site Collection Administrators, members of the default Owners group, or have direct 'Full Control' assignments. It aggregates this data by UserPrincipalName and returns the top 20 users with the most privileged access.

## SYNTAX

```powershell
Get-SPCPrivilegedUser 
    [-ClientId <String>] 
    [-Thumbprint <String>] 
    [-Tenant <String>] 
    [<CommonParameters>]
```

## EXAMPLES

### Example 1
```powershell
Get-SPCPrivilegedUser -ClientId "app-id" -Thumbprint "cert-thumb" -Tenant "tenant.onmicrosoft.com"
```
Returns the top 20 privileged users in the tenant.

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
Returns custom objects representing the top privileged users.
