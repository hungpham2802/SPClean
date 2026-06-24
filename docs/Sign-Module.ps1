<#
.SYNOPSIS
    Signs all SPClean module files with an Authenticode certificate.

.DESCRIPTION
    Applies Set-AuthenticodeSignature to every .ps1 and .psd1 in the module tree.
    Requires a code-signing certificate. Options:
      1. Commercial EV cert from DigiCert/Sectigo/GlobalSign (recommended for distribution)
      2. Self-signed cert created by this script (trusted only on this machine)

    Run this after every code change before publishing.

.PARAMETER CertThumbprint
    Thumbprint of an existing cert in Cert:\CurrentUser\My. If omitted, the script
    offers to create a self-signed cert.

.PARAMETER CreateSelfSigned
    Creates a self-signed code-signing cert (Cert:\CurrentUser\My) and uses it.
    Useful for dev/test; NOT trusted by other machines unless the cert is exported
    and added to their Trusted Publishers store.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $CertThumbprint,
    [switch] $CreateSelfSigned
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path $PSScriptRoot -Parent

# ─── Resolve / create certificate ────────────────────────────────────────────
if ($CreateSelfSigned) {
    Write-Host "Creating self-signed code-signing certificate..."
    $cert = New-SelfSignedCertificate -Subject 'CN=SPClean Code Signing' `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyUsage DigitalSignature `
        -Type CodeSigningCert `
        -NotAfter (Get-Date).AddYears(3)
    Write-Host "  Created: $($cert.Thumbprint) — $($cert.Subject)"
} elseif ($CertThumbprint) {
    $cert = Get-Item "Cert:\CurrentUser\My\$CertThumbprint" -ErrorAction Stop
    Write-Host "Using cert: $($cert.Subject) [$CertThumbprint]"
} else {
    # List available code-signing certs and prompt
    $available = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.3' }
    if ($available.Count -eq 0) {
        Write-Host "No code-signing certificate found in Cert:\CurrentUser\My."
        Write-Host "Re-run with -CreateSelfSigned to create one, or supply -CertThumbprint."
        exit 1
    }
    Write-Host "Available code-signing certificates:"
    $available | ForEach-Object { Write-Host "  $($_.Thumbprint)  $($_.Subject)" }
    Write-Error "Specify -CertThumbprint <value> from the list above."
}

# ─── Collect files to sign ────────────────────────────────────────────────────
$files = Get-ChildItem -Path $moduleRoot -Recurse -Include '*.ps1','*.psd1' |
    Where-Object { $_.FullName -notmatch '\\Tests\\' -and $_.FullName -notmatch '\\docs\\' }

Write-Host ""
Write-Host "Files to sign ($($files.Count)):"
$files | ForEach-Object { Write-Host "  $($_.FullName -replace [regex]::Escape($moduleRoot), '.')" }
Write-Host ""

# ─── Sign ─────────────────────────────────────────────────────────────────────
$signed   = 0
$failed   = 0
foreach ($f in $files) {
    if (-not $PSCmdlet.ShouldProcess($f.Name, 'Set-AuthenticodeSignature')) { continue }
    try {
        $result = Set-AuthenticodeSignature -FilePath $f.FullName -Certificate $cert `
            -TimestampServer 'http://timestamp.digicert.com' -ErrorAction Stop
        if ($result.Status -eq 'Valid') {
            Write-Host "  Signed: $($f.Name)" -ForegroundColor Green
            $signed++
        } else {
            Write-Warning "  Unexpected status '$($result.Status)' for $($f.Name)"
            $failed++
        }
    } catch {
        Write-Warning "  Failed to sign $($f.Name): $_"
        $failed++
    }
}

Write-Host ""
Write-Host "=== Signing complete: $signed signed, $failed failed ==="

# ─── Verify ───────────────────────────────────────────────────────────────────
if ($signed -gt 0) {
    Write-Host ""
    Write-Host "Verifying signatures..."
    $files | ForEach-Object {
        $sig = Get-AuthenticodeSignature -FilePath $_.FullName
        $color = if ($sig.Status -eq 'Valid') { 'Green' } else { 'Red' }
        Write-Host "  $($sig.Status.ToString().PadRight(12)) $($_.Name)" -ForegroundColor $color
    }
}
