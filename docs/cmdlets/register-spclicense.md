# Register-SPCLicense

Validates and activates a SPClean license key. Writes the key to `%APPDATA%\SPClean\license.lic` and clears the in-memory cache so the new tier takes effect immediately in the current session.

## Synopsis

```powershell
Register-SPCLicense
    -LicenseKey <string>
    [-Force]
    [-WhatIf]
    [-Confirm]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-LicenseKey` | `string` | ✅ | The license key in format `SPCLEAN-PRO-<payload>-<sig>` or `SPCLEAN-CONSULTANT-<payload>-<sig>` |
| `-Force` | switch | | Overwrite an existing `license.lic` without prompting |
| `-WhatIf` | switch | | Validate the key and show what would change, without writing the file |
| `-Confirm` | switch | | Prompt for confirmation before writing |

## Returns

`SPC.LicenseInfo` reflecting the newly activated license.

## Key validation

Keys are validated entirely offline using HMAC-SHA256 — no internet connection is required. A key encodes the license tier and email address in a URL-safe Base64 payload, and carries a fixed-length 43-character signature.

## Examples

=== "Activate"

    ```powershell
    Register-SPCLicense -LicenseKey 'SPCLEAN-PRO-<payload>-<sig>'
    ```

=== "Validate without writing (WhatIf)"

    ```powershell
    # Verify the key is valid before committing
    Register-SPCLicense -LicenseKey 'SPCLEAN-PRO-<payload>-<sig>' -WhatIf
    ```

## Error codes

| Code | Meaning |
| --- | --- |
| `ERR-LIC-001` | Key format is invalid or HMAC signature does not match |
| `ERR-LIC-002` | Key has expired |
| `ERR-LIC-003` | Feature requires a Pro or Consultant license |
| `ERR-LIC-004` | Feature requires a Consultant license |

## See also

- [Get-SPCLicenseInfo](get-spclicenseinfo.md)
- [Licensing](../licensing.md)
