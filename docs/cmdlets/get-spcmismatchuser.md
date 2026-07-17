# Get-SPCMismatchUser

## SYNOPSIS
Scans one or more site collections to identify "User ID Mismatch" issues.

## SYNTAX

```powershell
Get-SPCMismatchUser [[-SiteUrl] <String[]>] [-AllSites] [-ExcludeSiteUrl <String[]>] [-ThrottleLimit <Int32>] [<CommonParameters>]
```

## DESCRIPTION
The `Get-SPCMismatchUser` cmdlet detects "User ID Mismatch" issues across SharePoint Online sites.
This mismatch occurs when a user's Entra ID account is permanently deleted and a new account is created with the exact same User Principal Name (UPN). SharePoint caches the old Entra ID Object ID in its User Information List (UIL). When the user attempts to log in, SharePoint compares their new Entra Object ID against the cached one, finds a mismatch, and returns an "Access Denied" error, even if the user appears to have permissions.

The cmdlet works by retrieving all users in the site's UIL, batch querying Entra ID for their current Object IDs, and comparing the live `EntraObjectId` with the cached `SharePointAadObjectId`.

## EXAMPLES

### Example 1: Scan a single site
```powershell
Get-SPCMismatchUser -SiteUrl "https://contoso.sharepoint.com/sites/Marketing"
```
Scans the Marketing site collection for users with mismatched IDs.

### Example 2: Scan all sites in the tenant
```powershell
Get-SPCMismatchUser -AllSites
```
Discovers all site collections in the tenant and scans them concurrently.

### Example 3: Filter for Mismatched users only
```powershell
Get-SPCMismatchUser -AllSites | Where-Object Status -eq 'StaleIdentity'
```
Scans all sites and returns only users who have a confirmed User ID Mismatch.

## PARAMETERS

### `-SiteUrl`
One or more SharePoint site collection URLs to scan. Accepts pipeline input.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: None

Required: False
Position: 0
Default value: None
Accept pipeline input: True (ByValue, ByPropertyName)
Accept wildcard characters: False
```

### `-AllSites`
Scans all site collections in the tenant.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: None

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### `-ExcludeSiteUrl`
An array of URLs or wildcard patterns to exclude when scanning `-AllSites`.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: None

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: True
```

### `-ThrottleLimit`
The maximum number of concurrent site connections to use during `-AllSites` scans. Default is 3, maximum is 10.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases: None

Required: False
Position: Named
Default value: 3
Accept pipeline input: False
Accept wildcard characters: False
```

## OUTPUTS

### `SPC.MismatchUser`
Returns custom objects containing details about the user's mismatch status. Properties include `UPN`, `DisplayName`, `SiteUrl`, `Status`, `EntraObjectId`, and `SharePointAadObjectId`.
