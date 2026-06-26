# Authentication

SPClean supports two authentication methods. You must connect before using any other cmdlet.

---

## Method A — Interactive (delegated, for manual use)

Requires an Entra app registration configured for delegated auth.

### One-time app registration setup

1. Go to **Entra Admin Center → App registrations → New registration**
2. **Authentication blade:**
    - Add platform → Mobile and desktop applications
    - Redirect URI: `https://login.microsoftonline.com/common/oauth2/nativeclient`
    - Enable **Allow public client flows = Yes**
3. **API permissions** → Add **delegated** permissions:
    - Microsoft Graph: `User.Read.All`, `Directory.Read.All`
    - SharePoint: `AllSites.FullControl`
4. **Grant admin consent**

### Connect

```powershell
Connect-SPCTenant -TenantName contoso -ClientId '<your-app-client-id>'
```

A browser window opens for sign-in. Use an account with SharePoint Admin or Site Collection Admin rights.

---

## Method B — AppOnly / certificate (automation and scheduled tasks)

Requires an Entra app registration with a certificate credential.

### One-time app registration setup

1. Go to **Entra Admin Center → App registrations → New registration**
2. **Certificates & secrets** → upload a `.pfx` or `.cer` certificate
3. **API permissions** → Add **application** permissions:
    - Microsoft Graph: `User.Read.All`, `Directory.Read.All`, `Sites.FullControl.All`
    - SharePoint: `Sites.FullControl.All`
4. **Grant admin consent**

### Connect

```powershell
$certPwd = Read-Host -AsSecureString 'Certificate password'
Connect-SPCTenant -TenantName contoso `
    -AuthMethod AppOnly `
    -ClientId    '<your-app-client-id>' `
    -CertificatePath C:\certs\spclean.pfx `
    -CertificatePassword $certPwd
```

---

## Method C — AppOnly / client secret

```powershell
$secret = Read-Host -AsSecureString 'Client secret'
Connect-SPCTenant -TenantName contoso `
    -AuthMethod AppOnly `
    -ClientId    '<your-app-client-id>' `
    -ClientSecret $secret
```

!!! warning "Certificate preferred for automation"
    Client secrets expire and must be rotated manually. Use certificate auth for scheduled tasks.

---

## Disconnect

```powershell
Disconnect-SPCTenant
```

Clears the module connection state and disconnects both PnP and Microsoft Graph sessions.

---

## Permission requirements

### AppOnly (automation)

| Permission | Type | API | Purpose |
| --- | --- | --- | --- |
| `Sites.FullControl.All` | Application | Microsoft Graph | Read UIL, remove users |
| `User.Read.All` | Application | Microsoft Graph | Verify Entra account status |
| `Directory.Read.All` | Application | Microsoft Graph | Detect soft-deleted accounts |
| `Sites.FullControl.All` | Application | SharePoint | Per-site connections |

### Interactive (manual)

| Permission | Type | API | Purpose |
| --- | --- | --- | --- |
| `AllSites.FullControl` | Delegated | SharePoint | PnP site connections |
| `User.Read.All` | Delegated | Microsoft Graph | Verify Entra account status |
| `Directory.Read.All` | Delegated | Microsoft Graph | Detect soft-deleted accounts |

All permissions require **admin consent**.

---

## Next step

[Quick Start →](quickstart.md){ .md-button .md-button--primary }
