<#
.SYNOPSIS
    Re-seeds SPCleanTest with 3 orphaned users so the integration tests can pass.

.DESCRIPTION
    AC-07 (Remove + Snapshot) is DESTRUCTIVE: it removes all orphaned users from the
    test site in each test run. After each run, the test site must be re-seeded before
    the next run.

    SharePoint cannot add soft-deleted Entra users via ensureuser (UPN was renamed
    on deletion). This script:
      1. Restores the 3 soft-deleted accounts from Entra recycle bin
      2. Adds each to the SPCleanTest Members group (ensureuser works while they're active)
      3. Deletes them from Entra again (they become orphaned in the SP UIL)

    Requires:
      - Microsoft.Graph.Authentication + Microsoft.Graph.Users modules
      - Global Admin (or User Administrator + SharePoint Admin) account credentials
      - App cert credentials in SPC_* env vars (for the SP connection)

.NOTES
    Run once after each test run that executed AC-07.
    The 3 user Object IDs are fixed (same accounts each time, unless permanently purged).
#>

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users

[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $TenantName        = $env:SPC_TENANT_NAME,
    [string] $ClientId          = $env:SPC_CLIENT_ID,
    [string] $CertificatePath   = $env:SPC_CERT_PATH,
    [string] $CertificatePassword = $env:SPC_CERT_PASSWORD,
    [string] $TestSiteUrl       = $env:SPC_TEST_SITE_ORPHAN
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Object IDs of the 3 soft-deleted test accounts ───────────────────────────
# Replace these placeholder GUIDs with the real Entra Object IDs from your tenant.
# Find Object IDs in Entra Admin Center → Users → select user → Object ID,
# or: Get-MgUser -Filter "displayName eq 'Test User'" | Select-Object Id
$testUserIds = @{
    'testorphan1' = '00000000-0000-0000-0000-000000000001'   # TODO: replace with real Object ID
    'testorphan2' = '00000000-0000-0000-0000-000000000002'   # TODO: replace with real Object ID
    'testorphan3' = '00000000-0000-0000-0000-000000000003'   # TODO: replace with real Object ID
}

$tenantId    = if ($TenantName -match '\.') { $TenantName } else { "$TenantName.onmicrosoft.com" }
$membersGroup = 'SPCleanTest Members'

Write-Host "=== SPCleanTest Re-seeder ===" -ForegroundColor Cyan
Write-Host "Tenant    : $tenantId"
Write-Host "Test site : $TestSiteUrl"
Write-Host ""

# ─── Step 1: Connect to Microsoft Graph (delegated, requires GA) ──────────────
Write-Host "[1/4] Connecting to Microsoft Graph (interactive)..."
Connect-MgGraph -TenantId $tenantId -Scopes "User.ReadWrite.All" -NoWelcome

# ─── Step 2: Restore soft-deleted accounts ────────────────────────────────────
Write-Host "[2/4] Restoring soft-deleted Entra accounts..."
$restoredUpns = @{}
foreach ($key in $testUserIds.Keys) {
    $objectId = $testUserIds[$key]
    try {
        $restored = Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/directory/deletedItems/$objectId/restore" `
            -Body @{} -ContentType 'application/json'
        $restoredUpns[$key] = $restored.userPrincipalName
        Write-Host "  Restored $key → UPN: $($restored.userPrincipalName)" -ForegroundColor Green
    } catch {
        Write-Warning "  Could not restore $key (id $objectId): $($_.Exception.Message)"
        Write-Warning "  The account may have been permanently purged. Create a replacement account."
    }
}

if ($restoredUpns.Count -eq 0) {
    Write-Error "No accounts were restored. Cannot continue."
    exit 1
}

# Small pause for Entra replication
Write-Host "  Waiting 10s for Entra replication..."
Start-Sleep -Seconds 10

# ─── Step 3: Add restored accounts to SPCleanTest via PnP ────────────────────
Write-Host "[3/4] Adding accounts to SPCleanTest Members group..."
$certPass = ConvertTo-SecureString $CertificatePassword -AsPlainText -Force
$testConn = Connect-PnPOnline -Url $TestSiteUrl -ClientId $ClientId `
    -Tenant $tenantId -CertificatePath $CertificatePath -CertificatePassword $certPass `
    -ReturnConnection

foreach ($key in $restoredUpns.Keys) {
    $upn      = $restoredUpns[$key]
    $login    = "i:0#.f|membership|$upn"
    try {
        Add-PnPGroupMember -LoginName $login -Group $membersGroup -Connection $testConn -ErrorAction Stop
        Write-Host "  Added $key to '$membersGroup'" -ForegroundColor Green
    } catch {
        Write-Warning "  Could not add $key ($login): $($_.Exception.Message)"
    }
}

# ─── Step 4: Delete accounts from Entra again (make them orphaned) ───────────
Write-Host "[4/4] Deleting accounts from Entra (creating orphan state)..."
foreach ($key in $restoredUpns.Keys) {
    $objectId = $testUserIds[$key]
    try {
        Invoke-MgGraphRequest -Method DELETE `
            -Uri "https://graph.microsoft.com/v1.0/users/$objectId" | Out-Null
        Write-Host "  Deleted $key from Entra" -ForegroundColor Green
    } catch {
        Write-Warning "  Could not delete ${key}: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "=== Re-seeding complete ===" -ForegroundColor Cyan

# ─── Verify ──────────────────────────────────────────────────────────────────
Write-Host "Verifying SPCleanTest UIL..."
$uilUsers = Get-PnPUser -Connection $testConn | Where-Object { $_.LoginName -like 'i:0#.f|membership|*' }
Write-Host "UIL users on test site:"
$uilUsers | ForEach-Object { Write-Host "  $($_.LoginName)" }

Write-Host ""
Write-Host "Wait ~30 seconds for Entra deletion to propagate, then run:"
Write-Host "  Invoke-Pester Tests/Integration/ -Output Detailed"
