# Get-SPCGuestAccess

## SYNOPSIS
Lists all external/guest users with access to a site collection.

## DESCRIPTION
This cmdlet scans a specific site collection to list all external or guest users (users with `#EXT#` in their UPN) who have access to the site. This includes access granted through direct assignments or group memberships.

## SYNTAX

```powershell
Get-SPCGuestAccess 
    [-SiteUrl <String>] 
    [<CommonParameters>]
```

## EXAMPLES

### Example 1
```powershell
Get-SPCGuestAccess -SiteUrl "https://contoso.sharepoint.com/sites/Ext"
```
Returns a list of external guest users who have access to the specified site.

## PARAMETERS

### -SiteUrl
The URL of the SharePoint Online site collection to scan.

## INPUTS
### None

## OUTPUTS
### System.Management.Automation.PSCustomObject
Returns custom objects containing information about guest users and their access.
