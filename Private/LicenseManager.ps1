# Module-level license cache — populated by Get-SPCLicenseInfo, cleared by Register-SPCLicense
# and Disconnect-SPCTenant. Not persisted across PowerShell sessions.
$script:SPCLicenseCache = $null

function ConvertFrom-Base64UrlInternal {
    param([string]$InputString)
    $s = $InputString.Replace('-', '+').Replace('_', '/')
    switch ($s.Length % 4) {
        2 { $s += '==' }
        3 { $s += '=' }
    }
    [System.Convert]::FromBase64String($s)
}

function ConvertFrom-HexStringInternal {
    param([string]$Hex)
    $bytes = [byte[]]::new($Hex.Length / 2)
    for ($i = 0; $i -lt $Hex.Length; $i += 2) {
        $bytes[$i / 2] = [System.Convert]::ToByte($Hex.Substring($i, 2), 16)
    }
    $bytes
}

function Compare-ByteArrayConstantTimeInternal {
    param([byte[]]$A, [byte[]]$B)
    if ($A.Length -ne $B.Length) { return $false }
    $result = 0
    for ($i = 0; $i -lt $A.Length; $i++) {
        $result = $result -bor ($A[$i] -bxor $B[$i])
    }
    return ($result -eq 0)
}

function Get-SPCLicensePathInternal {
    Join-Path ([System.Environment]::GetFolderPath('ApplicationData')) 'SPClean' 'license.lic'
}

function Get-SPCSecretKeyBytesInternal {
    # THIS VALUE IS REPLACED AT BUILD TIME BY tools/Inject-Secret.ps1
    # DO NOT COMMIT A REAL KEY HERE
    $hexSecret = 'REPLACE_AT_BUILD_TIME_DO_NOT_COMMIT'
    ConvertFrom-HexStringInternal -Hex $hexSecret
}

function Test-SPCLicenseKey {
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] [string]$LicenseKey,
        [Parameter(Mandatory)] [byte[]]$SecretKeyBytes
    )

    $makeResult = {
        param([bool]$Valid, [string]$Reason, [string]$Tier, [string]$Email,
              [string]$LicId, $Exp, $Iss)
        $r = [PSCustomObject][ordered]@{
            IsValid       = $Valid
            Tier          = $Tier
            Email         = $Email
            LicenseId     = $LicId
            ExpiresAt     = $Exp
            IssuedAt      = $Iss
            FailureReason = $Reason
        }
        $r.PSObject.TypeNames.Insert(0, 'SPC.LicenseValidation')
        $r
    }

    # Step 1: trim
    $trimmed = $LicenseKey.Trim()

    # Step 2: split on '-' with limit 3
    $parts = $trimmed -split '-', 3
    if ($parts.Count -ne 3 -or $parts[0] -ne 'SPCLEAN') {
        return (& $makeResult $false 'MalformedFormat' $null $null $null $null $null)
    }

    $tier      = $parts[1]
    $remainder = $parts[2]

    # Step 3: validate tier
    if ($tier -notin @('PRO', 'CONSULTANT')) {
        return (& $makeResult $false 'InvalidTier' $null $null $null $null $null)
    }

    # Step 4: extract sig (always exactly 43 Base64URL chars: HMAC-SHA256 = 32 bytes)
    # Using fixed-length avoids ambiguity when sig contains '-' chars (valid in Base64URL)
    $sigB64Len = 43
    $sepPos    = $remainder.Length - $sigB64Len - 1
    if ($sepPos -lt 1 -or $remainder[$sepPos] -ne [char]'-') {
        return (& $makeResult $false 'MalformedFormat' $null $null $null $null $null)
    }
    $payloadB64 = $remainder.Substring(0, $sepPos)
    $sigB64     = $remainder.Substring($sepPos + 1)

    # Step 5: decode sig
    try {
        $sigBytes = ConvertFrom-Base64UrlInternal -InputString $sigB64
    } catch {
        return (& $makeResult $false 'Base64DecodeFailure' $null $null $null $null $null)
    }

    # Step 6: HMAC check BEFORE JSON decode (prevent oracle attacks)
    $hmac        = $null
    $expectedSig = $null
    try {
        $hmac        = [System.Security.Cryptography.HMACSHA256]::new($SecretKeyBytes)
        $expectedSig = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payloadB64))
    } finally {
        if ($null -ne $hmac) { $hmac.Dispose() }
    }

    if (-not (Compare-ByteArrayConstantTimeInternal -A $expectedSig -B $sigBytes)) {
        return (& $makeResult $false 'SignatureMismatch' $null $null $null $null $null)
    }

    # Step 7: decode payload
    try {
        $payloadBytes = ConvertFrom-Base64UrlInternal -InputString $payloadB64
        $payloadJson  = [System.Text.Encoding]::UTF8.GetString($payloadBytes)
    } catch {
        return (& $makeResult $false 'Base64DecodeFailure' $null $null $null $null $null)
    }

    # Step 8: parse JSON
    try {
        $payload = $payloadJson | ConvertFrom-Json
    } catch {
        return (& $makeResult $false 'InvalidPayloadJson' $null $null $null $null $null)
    }

    foreach ($field in @('tier', 'expiry', 'licenseId', 'email', 'issuedAt')) {
        if ($null -eq $payload.$field -or [string]::IsNullOrWhiteSpace([string]$payload.$field)) {
            return (& $makeResult $false 'InvalidPayloadJson' $null $null $null $null $null)
        }
    }

    # Step 9: check expiry
    try {
        $expiry = [datetime]::Parse(
            $payload.expiry,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind)
    } catch {
        return (& $makeResult $false 'InvalidPayloadJson' $null $null $null $null $null)
    }
    if ($expiry -le [datetime]::UtcNow) {
        return (& $makeResult $false 'Expired' $null $null $null $null $null)
    }

    # Step 10: check issuedAt (allow 5-minute clock skew)
    try {
        $issuedAt = [datetime]::Parse(
            $payload.issuedAt,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind)
    } catch {
        return (& $makeResult $false 'InvalidPayloadJson' $null $null $null $null $null)
    }
    if ($issuedAt -gt [datetime]::UtcNow.AddMinutes(5)) {
        return (& $makeResult $false 'FutureIssuedAt' $null $null $null $null $null)
    }

    # Step 11: all checks passed
    return (& $makeResult $true $null $payload.tier $payload.email $payload.licenseId $expiry $issuedAt)
}

function Assert-SPCProLicense {
    param([Parameter(Mandatory)] [string]$Feature)
    $info = Get-SPCLicenseInfo
    if ($info.Status -eq 'Active' -and $info.Tier -in @('PRO', 'CONSULTANT')) { return }
    throw "ERR-LIC-003: '$Feature' requires a Pro or Consultant license.`nCurrent status: $($info.Status).`n→ Purchase at: https://spclean.gumroad.com`n→ Register with: Register-SPCLicense -LicenseKey 'SPCLEAN-PRO-...'"
}

function Assert-SPCConsultantLicense {
    param([Parameter(Mandatory)] [string]$Feature)
    $info = Get-SPCLicenseInfo
    if ($info.Status -eq 'Active' -and $info.Tier -eq 'CONSULTANT') { return }
    throw "ERR-LIC-004: '$Feature' requires a Consultant license.`nCurrent status: $($info.Status). Tier: $($info.Tier).`n→ Upgrade at: https://spclean.gumroad.com"
}
