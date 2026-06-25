function Get-SPCLicenseInfo {
    <#
    .SYNOPSIS
        Returns the currently registered SPClean license status.
    .DESCRIPTION
        Reads license status from the module cache or disk. Never throws —
        returns a status object whether licensed or not. Use this to check
        license tier before calling paid features.
    .EXAMPLE
        Get-SPCLicenseInfo

        Returns the current license status. Status will be 'Active', 'Expired',
        'Invalid', or 'Unlicensed'.
    .EXAMPLE
        if ((Get-SPCLicenseInfo).Status -ne 'Active') {
            Write-Warning 'SPClean Pro license required for this operation.'
        }
    .OUTPUTS
        SPC.LicenseInfo
    .NOTES
        Purchase SPClean Pro or Consultant at https://spclean.gumroad.com
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $makeInfo = {
        param([string]$Status, [string]$Tier, [string]$Email, [string]$LicId,
              $ExpiresAt, $RegisteredAt, [string]$FailureReason)
        $r = [PSCustomObject][ordered]@{
            Tier          = $Tier
            Email         = $Email
            LicenseId     = $LicId
            ExpiresAt     = $ExpiresAt
            RegisteredAt  = $RegisteredAt
            Status        = $Status
            FailureReason = $FailureReason
        }
        $r.PSObject.TypeNames.Insert(0, 'SPC.LicenseInfo')
        $r
    }

    $unlicensed = { & $makeInfo 'Unlicensed' 'FREE' $null $null $null $null $null }

    # Step 1: return from cache if valid and not expired
    if ($null -ne $script:SPCLicenseCache) {
        $cached = $script:SPCLicenseCache
        if ($cached.Status -eq 'Active' -and $null -ne $cached.ExpiresAt -and
            $cached.ExpiresAt -gt [datetime]::UtcNow) {
            return $cached
        }
        $script:SPCLicenseCache = $null
    }

    # Step 2: read from disk
    $licPath = Get-SPCLicensePathInternal
    if (-not (Test-Path -Path $licPath -PathType Leaf)) {
        return (& $unlicensed)
    }

    $licRaw = $null
    try {
        $licRaw = Get-Content -Path $licPath -Encoding UTF8 -Raw -ErrorAction Stop
        $lic    = $licRaw | ConvertFrom-Json
    } catch {
        Write-Verbose "Get-SPCLicenseInfo: Cannot read license.lic — $($_.Exception.Message)"
        return (& $makeInfo 'Invalid' $null $null $null $null $null 'CorruptFile')
    }

    if ([string]::IsNullOrWhiteSpace($lic.licenseKey)) {
        return (& $makeInfo 'Invalid' $null $null $null $null $null 'MissingLicenseKey')
    }

    # Step 3: re-verify key
    $secretBytes = $null
    $validation  = $null
    try {
        $secretBytes = Get-SPCSecretKeyBytesInternal
        $validation  = Test-SPCLicenseKey -LicenseKey $lic.licenseKey -SecretKeyBytes $secretBytes
    } catch {
        Write-Verbose "Get-SPCLicenseInfo: Verification error — $($_.Exception.Message)"
        return (& $makeInfo 'Invalid' $null $null $null $null $null 'VerificationError')
    } finally {
        if ($null -ne $secretBytes) {
            [System.Array]::Clear($secretBytes, 0, $secretBytes.Length)
        }
    }

    if (-not $validation.IsValid) {
        $status = if ($validation.FailureReason -eq 'Expired') { 'Expired' } else { 'Invalid' }
        return (& $makeInfo $status $null $null $null $null $null $validation.FailureReason)
    }

    $registeredAt = $null
    try {
        if (-not [string]::IsNullOrWhiteSpace($lic.registeredAt)) {
            $registeredAt = [datetime]::Parse(
                $lic.registeredAt,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind)
        }
    } catch {}

    # Step 5: populate cache and return
    $result = & $makeInfo 'Active' $validation.Tier $validation.Email $validation.LicenseId `
        $validation.ExpiresAt $registeredAt $null

    $script:SPCLicenseCache = $result
    $result
}
