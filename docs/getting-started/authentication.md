# Authentication

SPClean supports two authentication methods. You must connect before using any other cmdlet.

---

## Automated App Registration Setup (Recommended)

If you are a Global Administrator, you can use the included setup script to automatically create an Entra ID Application Registration with all required permissions and certificates. This replaces the manual setup steps in Methods A and B.

```powershell
# Navigate to the tools directory
cd .\tools

# Run the setup script (replace 'contoso' with your tenant name)
.\Setup-SPCleanApp.ps1 -TenantName "contoso"
```

The script will:
1. Open a browser for you to sign in.
2. Create an App Registration named **SPClean App**.
3. Assign all required Microsoft Graph and SharePoint permissions.
4. Generate a self-signed certificate and store it in your Windows Certificate Store (`CurrentUser`).
5. Configure `http://localhost` for Interactive login.

**Important:** After the script completes, you must go to the Entra Admin Center and click **Grant admin consent** for the newly created app!

---

## Method A — Interactive (delegated, for manual use)

Requires an Entra app registration configured for delegated auth.

### One-time app registration setup

1. Go to **Entra Admin Center → App registrations → New registration**
2. **Authentication blade:**
    - Add platform → **Mobile and desktop applications**
    - Add **both** redirect URIs:
        - `http://localhost` ← required for browser-based interactive login (PnP opens a random localhost port)
        - `https://login.microsoftonline.com/common/oauth2/nativeclient`
    - Enable **Allow public client flows = Yes**
3. **API permissions** → Add **delegated** permissions:
    - Microsoft Graph: `User.Read.All`, `Directory.Read.All`, `AuditLog.Read.All`
    - SharePoint: `AllSites.FullControl`
4. **Grant admin consent**

!!! warning "Missing `http://localhost` → AADSTS50011"
    PnP PowerShell 3.x interactive auth opens a browser and redirects to `http://localhost:<random-port>`. If `http://localhost` is not listed under Mobile and desktop redirect URIs, Azure AD will reject with **AADSTS50011: redirect URI does not match**. Adding the port-less `http://localhost` covers all ports.

### Connect

```powershell
Connect-SPCTenant -TenantName contoso -ClientId '<your-app-client-id>'
```

A browser window opens for sign-in. You must authenticate with an account that has **SharePoint Administrator** or **Global Administrator** privileges to connect to the tenant.

!!! note "Site Collection Administrator Requirement"
    Scanning or modifying individual sites requires **Site Collection Administrator (SCA)** privileges on those specific sites. If you are a SharePoint Admin but not an SCA of the target sites, use the `-AddTempSiteCollectionAdmin` switch on cmdlets like `Get-SPCOrphanedUser` to automatically elevate your permissions during execution.

---

## Method B — AppOnly / certificate (automation and scheduled tasks)

Requires an Entra app registration with a certificate credential.

### One-time app registration setup

1. Go to **Entra Admin Center → App registrations → New registration**
2. **Certificates & secrets** → upload a `.pfx` or `.cer` certificate
3. **API permissions** → Add **application** permissions:
    - Microsoft Graph: `User.Read.All`, `Directory.Read.All`, `AuditLog.Read.All`, `Sites.FullControl.All`
    - SharePoint: `Sites.FullControl.All`
4. **Grant admin consent**

### Connect

```powershell
# Sử dụng file PFX:
$certPwd = Read-Host -AsSecureString 'Certificate password'
Connect-SPCTenant -TenantName contoso `
    -AuthMethod AppOnly `
    -ClientId    '<your-app-client-id>' `
    -CertificatePath C:\certs\spclean.pfx `
    -CertificatePassword $certPwd

# Hoặc sử dụng Thumbprint (chứng chỉ đã được install vào máy):
Connect-SPCTenant -TenantName contoso `
    -AuthMethod AppOnly `
    -ClientId    '<your-app-client-id>' `
    -CertificateThumbprint '1234567890ABCDEF'
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

!!! warning "Legacy Authentication / Limited Functionality"
    Connecting with Client Secret uses legacy authentication (ACS-based) and provides limited functionality. It does not work with Microsoft Graph and limits cmdlets related to Microsoft Teams, Planner, Flow, and M365 Groups. It is highly recommended to use Certificate-based authentication or Interactive authentication instead.

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
| `AuditLog.Read.All` | Application | Microsoft Graph | Read user sign-in activity |
| `Sites.FullControl.All` | Application | SharePoint | Per-site connections |

### Interactive (manual)

| Permission | Type | API | Purpose |
| --- | --- | --- | --- |
| `AllSites.FullControl` | Delegated | SharePoint | PnP site connections |
| `User.Read.All` | Delegated | Microsoft Graph | Verify Entra account status |
| `Directory.Read.All` | Delegated | Microsoft Graph | Detect soft-deleted accounts |
| `AuditLog.Read.All` | Delegated | Microsoft Graph | Read user sign-in activity |

All permissions require **admin consent**.

---

## Next step

[Quick Start →](quickstart.md){ .md-button .md-button--primary }
