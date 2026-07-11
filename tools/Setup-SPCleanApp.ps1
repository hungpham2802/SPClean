<#
.SYNOPSIS
    Automates the creation of an Entra ID Application Registration for the SPClean tool.
.DESCRIPTION
    Creates a new App Registration with all necessary API permissions required by SPClean (Graph API and SharePoint API).
    Generates a self-signed certificate for AppOnly authentication, which is stored locally in the CurrentUser certificate store.
    You must be a Global Administrator or Application Administrator to run this setup.
.EXAMPLE
    .\Setup-SPCleanApp.ps1 -TenantName "contoso"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$TenantName,

    [Parameter(Mandatory=$false)]
    [string]$ApplicationName = "SPClean App"
)

$tenantDomain = if ($TenantName -match '\.') { $TenantName } else { "$TenantName.onmicrosoft.com" }

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " SPClean - App Registration Setup" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "Tenant: $tenantDomain" -ForegroundColor White
Write-Host "App Name: $ApplicationName" -ForegroundColor White
Write-Host ""
Write-Host "This script will:"
Write-Host "1. Open a browser for you to sign in (requires Global Admin)."
Write-Host "2. Create a new Entra ID App Registration."
Write-Host "3. Assign necessary Microsoft Graph and SharePoint API permissions."
Write-Host "4. Generate a self-signed certificate and store it in your Windows Certificate Store (CurrentUser)."
Write-Host "5. Configure http://localhost for Interactive login."
Write-Host ""

$graphAppPerms = @("User.Read.All", "Directory.Read.All", "AuditLog.Read.All", "Sites.FullControl.All")
$spAppPerms    = @("Sites.FullControl.All")
$graphDelPerms = @("User.Read.All", "Directory.Read.All", "AuditLog.Read.All")
$spDelPerms    = @("AllSites.FullControl")

# We use PnP PowerShell's Register-PnPEntraIDApp
# Note: Register-PnPEntraIDApp also configures http://localhost as a Mobile and Desktop app redirect URI by default
try {
    Register-PnPEntraIDApp -ApplicationName $ApplicationName `
        -Tenant $tenantDomain `
        -Store CurrentUser `
        -GraphApplicationPermissions $graphAppPerms `
        -SharePointApplicationPermissions $spAppPerms `
        -GraphDelegatePermissions $graphDelPerms `
        -SharePointDelegatePermissions $spDelPerms
}
catch {
    Write-Error "Failed to register application. Error: $_"
    exit
}

Write-Host ""
Write-Host "✅ App Registration setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "⚠️ IMPORTANT NEXT STEP:" -ForegroundColor Red
Write-Host "1. Go to Entra Admin Center (https://entra.microsoft.com/)" -ForegroundColor Yellow
Write-Host "2. Navigate to App registrations -> All applications -> '$ApplicationName'" -ForegroundColor Yellow
Write-Host "3. Go to 'API Permissions'" -ForegroundColor Yellow
Write-Host "4. Click the 'Grant admin consent for $TenantName' button!" -ForegroundColor Red
Write-Host ""
Write-Host "After granting consent, you can connect to SPClean using the Client ID and the installed Certificate Thumbprint." -ForegroundColor Cyan
