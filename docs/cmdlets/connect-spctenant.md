# Connect-SPCTenant

Establishes a session to SharePoint Online and Microsoft Graph for all SPClean cmdlets.

## Synopsis

```powershell
Connect-SPCTenant
    -TenantName           <string>
    [-AuthMethod          Interactive | AppOnly]
    [-ClientId            <string>]
    [-CertificateThumbprint <string>]
    [-CertificatePath     <string>]
    [-CertificatePassword <SecureString>]
    [-ClientSecret        <SecureString>]
```

## Parameters

| Parameter | Type | Required | Description |
| --- | --- | :---: | --- |
| `-TenantName` | `string` | âœ… | Short name (`contoso`), full domain (`contoso.onmicrosoft.com`), or SharePoint root URL |
| `-AuthMethod` | `Interactive \| AppOnly` | | Authentication method. Default: `Interactive` |
| `-ClientId` | `string` | | Entra App Registration client ID. Required for Interactive and AppOnly |
| `-CertificateThumbprint` | `string` | | Thumbprint of the certificate installed in the local store. AppOnly only |
| `-CertificatePath` | `string` | | Path to `.pfx` certificate file. AppOnly only |
| `-CertificatePassword` | `SecureString` | | Password for the `.pfx` file. AppOnly only |
| `-ClientSecret` | `SecureString` | | Client secret. AppOnly alternative to certificate |

## Returns

`SPC.ConnectionInfo`

## Error codes

| Code | Condition |
| --- | --- |
| `ERR-AUTH-001` | Cannot resolve tenant URL from TenantName |
| `ERR-AUTH-002` | Authentication failed â€” invalid credentials or insufficient permissions |
| `ERR-AUTH-003` | AppOnly auth requires `-ClientId` and one of `-CertificateThumbprint`, `-CertificatePath` or `-ClientSecret` |
| `ERR-AUTH-004` | Interactive auth requires `-ClientId` in PnP.PowerShell 3.x |

## Examples

=== "Interactive"

    ```powershell
    Connect-SPCTenant -TenantName contoso -ClientId '<delegated-app-id>'
    ```

=== "AppOnly â€” Certificate File"

    ```powershell
    $certPwd = Read-Host -AsSecureString 'Certificate password'
    Connect-SPCTenant -TenantName contoso `
        -AuthMethod      AppOnly `
        -ClientId        '<app-id>' `
        -CertificatePath C:\certs\spclean.pfx `
        -CertificatePassword $certPwd
    ```

=== "AppOnly â€” Certificate Thumbprint"

    ```powershell
    Connect-SPCTenant -TenantName contoso `
        -AuthMethod            AppOnly `
        -ClientId              '<app-id>' `
        -CertificateThumbprint '1234567890ABCDEF'
    ```

=== "AppOnly â€” Client Secret"

    !!! warning "Legacy Authentication / Limited Functionality"
        Connecting with Client Secret uses legacy authentication (ACS-based) and provides limited functionality. It does not work with Microsoft Graph and limits cmdlets related to Microsoft Teams, Planner, Flow, and M365 Groups. It is highly recommended to use Certificate-based authentication or Interactive authentication instead.

    ```powershell
    $secret = Read-Host -AsSecureString 'Client secret'
    Connect-SPCTenant -TenantName contoso `
        -AuthMethod   AppOnly `
        -ClientId     '<app-id>' `
        -ClientSecret $secret
    ```

## See also

- [Authentication setup](../getting-started/authentication.md)
- [Disconnect-SPCTenant](disconnect-spctenant.md)
