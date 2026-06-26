# Get-SPCLicenseInfo

Returns the current SPClean license status from the module cache or disk. Never throws — safe to call at any time, including before `Connect-SPCTenant`.

## Synopsis

```powershell
Get-SPCLicenseInfo
```

## Parameters

None.

## Returns

`SPC.LicenseInfo` with the following properties:

| Property | Type | Description |
| --- | --- | --- |
| `Status` | `string` | `Active`, `Expired`, `Invalid`, or `Unlicensed` |
| `Tier` | `string` | `FREE`, `PRO`, or `CONSULTANT` |
| `Email` | `string` | Email address the license was issued to |
| `ExpiresAt` | `DateTime?` | License expiry date (UTC). Empty for unlicensed |
| `RegisteredAt` | `DateTime?` | Date the license was registered on this machine |
| `LicenseId` | `string` | Unique license identifier embedded in the key |

## Examples

=== "Check status"

    ```powershell
    Get-SPCLicenseInfo
    ```

    Unlicensed output:
    ```
    Status      : Unlicensed
    Tier        : FREE
    Email       :
    ExpiresAt   :
    RegisteredAt:
    LicenseId   :
    ```

    Active output:
    ```
    Status      : Active
    Tier        : PRO
    Email       : you@contoso.com
    ExpiresAt   : 2027-06-25 00:00:00
    RegisteredAt: 2026-06-25 09:14:00
    LicenseId   : abc123
    ```

=== "Conditional guard"

    ```powershell
    if ((Get-SPCLicenseInfo).Status -ne 'Active') {
        Write-Warning 'HTML reports and scheduled scans require a Pro license.'
        Write-Warning 'Purchase at: https://hungpham2802.gumroad.com'
    }
    ```

## Notes

- The cmdlet checks the module-level cache first. If the cache is empty it reads `%APPDATA%\SPClean\license.lic` from disk and re-verifies the HMAC signature.
- If no license file exists, `Status = Unlicensed` and `Tier = FREE` are returned (no error).
- After calling `Register-SPCLicense`, the cache is cleared and `Get-SPCLicenseInfo` will reflect the new key immediately.

## See also

- [Register-SPCLicense](register-spclicense.md)
- [Licensing](../licensing.md)
