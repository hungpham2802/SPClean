# Module-level license cache — populated by Get-SPCLicenseInfo, cleared by Register-SPCLicense
# and Disconnect-SPCTenant. Not persisted across PowerShell sessions.
$script:SPCLicenseCache = $null

$script:GumroadApiUrl = 'https://api.gumroad.com/v2/licenses/verify'
$script:GumroadProductIds = @{
    PRO        = 'iHSmQlH-l22861DgO1u0AQ=='
    CONSULTANT = 'uMyAGbh6U5LWF_T8wur4bg=='
}
$script:LicenseCacheMaxAgeDays = 7

$script:LicenseFilePath = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
    Join-Path $env:APPDATA 'SPClean\license.lic'
} else {
    Join-Path $HOME '.config/SPClean/license.lic'
}

function Invoke-GumroadVerifyInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$LicenseKey,
        [Parameter(Mandatory)] [ValidateSet('PRO','CONSULTANT')] [string]$Tier,
        [bool]$IncrementUses = $true
    )
    $productId = $script:GumroadProductIds[$Tier]
    $body = @{
        product_id           = $productId
        license_key          = $LicenseKey
        increment_uses_count = $IncrementUses.ToString().ToLower()
    }
    try {
        $response = Invoke-RestMethod -Method POST -Uri $script:GumroadApiUrl `
                        -Body $body -ErrorAction Stop
        return [PSCustomObject]@{
            Success   = [bool]$response.success
            Tier      = $Tier
            Email     = $response.purchase.email
            Refunded  = ($response.purchase.refunded -eq $true) -or
                        ($response.purchase.chargebacked -eq $true)
            IsTesting = ($response.purchase.test -eq $true)
        }
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($statusCode -eq 404) {
            return [PSCustomObject]@{ Success = $false; Tier = $Tier }
        }
        throw ("ERR-LIC-NET-001: Cannot reach Gumroad API to verify license. " +
               "Check internet connection and try again. Detail: $($_.Exception.Message)")
    }
}

function Test-SPCLicenseKeyInternal {
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] [string]$LicenseKey
    )

    $makeInvalid = {
        param([string]$Reason)
        [PSCustomObject]@{
            IsValid       = $false
            Tier          = $null
            Email         = $null
            IsTesting     = $false
            FailureReason = $Reason
        }
    }

    # 1. Trim
    $key = $LicenseKey.Trim()

    # 2. Validate UUID format
    $guid = [System.Guid]::empty
    if (-not [System.Guid]::TryParse($key, [ref]$guid)) {
        return (& $makeInvalid 'MalformedFormat')
    }

    # 3. Try PRO
    $result = $null
    try {
        $result = Invoke-GumroadVerifyInternal -LicenseKey $key -Tier 'PRO' -IncrementUses $true
    }
    catch {
        return (& $makeInvalid 'NetworkError')
    }

    # 4. If PRO failed, try CONSULTANT
    if (-not $result.Success) {
        try {
            $result = Invoke-GumroadVerifyInternal -LicenseKey $key -Tier 'CONSULTANT' -IncrementUses $true
        }
        catch {
            return (& $makeInvalid 'NetworkError')
        }
    }

    # 5. Both tiers failed
    if (-not $result.Success) {
        return (& $makeInvalid 'InvalidKey')
    }

    # 6. Check refunded
    if ($result.Refunded) {
        return (& $makeInvalid 'Refunded')
    }

    # 7. Valid
    return [PSCustomObject]@{
        IsValid       = $true
        Tier          = $result.Tier
        Email         = $result.Email
        IsTesting     = $result.IsTesting
        FailureReason = $null
    }
}

function Get-SPCLicenseDataInternal {
    # Returns [PSCustomObject]@{ Status; LicData }
    # Status: 'Unlicensed' | 'Invalid' | 'Active' | 'Revoked'

    if (-not (Test-Path $script:LicenseFilePath)) {
        return [PSCustomObject]@{ Status = 'Unlicensed'; LicData = $null }
    }

    try {
        $json = Get-Content -Path $script:LicenseFilePath -Raw -Encoding UTF8 -ErrorAction Stop
        $data = $json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "SPClean: License file is malformed and could not be read."
        return [PSCustomObject]@{ Status = 'Invalid'; LicData = $null }
    }

    if ([string]::IsNullOrWhiteSpace($data.licenseKey) -or
        [string]::IsNullOrWhiteSpace($data.lastVerifiedAt) -or
        $data.tier -notin @('PRO', 'CONSULTANT')) {
        Write-Warning "SPClean: License file is missing or has invalid required fields."
        return [PSCustomObject]@{ Status = 'Invalid'; LicData = $null }
    }

    try {
        $lastVerified = [datetime]::Parse(
            $data.lastVerifiedAt,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind)
    }
    catch {
        Write-Warning "SPClean: License file has invalid lastVerifiedAt timestamp."
        return [PSCustomObject]@{ Status = 'Invalid'; LicData = $null }
    }

    $ageDays = ([datetime]::UtcNow - $lastVerified).TotalDays

    if ($ageDays -lt $script:LicenseCacheMaxAgeDays) {
        return [PSCustomObject]@{ Status = 'Active'; LicData = $data }
    }

    # Re-verify (cache >= 7 days old)
    try {
        $verify = Invoke-GumroadVerifyInternal -LicenseKey $data.licenseKey -Tier $data.tier -IncrementUses $false

        if ($verify.Refunded) {
            Remove-Item $script:LicenseFilePath -Force -ErrorAction SilentlyContinue
            return [PSCustomObject]@{ Status = 'Revoked'; LicData = $null }
        }

        $data.lastVerifiedAt = [datetime]::UtcNow.ToString('o')
        $data | ConvertTo-Json | Set-Content -Path $script:LicenseFilePath -Encoding UTF8 -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ Status = 'Active'; LicData = $data }
    }
    catch {
        $ageDaysRounded = [Math]::Floor($ageDays)
        Write-Warning "Cannot re-verify license (offline). Using cached status (last verified $ageDaysRounded days ago)."
        return [PSCustomObject]@{ Status = 'Active'; LicData = $data }
    }
}

function Assert-SPCProLicense {
    param([Parameter(Mandatory)] [string]$Feature)
    $info = Get-SPCLicenseInfo
    if ($info.Status -eq 'Active' -and $info.Tier -in @('PRO', 'CONSULTANT')) { return }
    throw "ERR-LIC-003: '$Feature' requires a Pro or Consultant license. → Purchase Pro: https://ngochung47.gumroad.com/l/spclean-pro or Consultant: https://ngochung47.gumroad.com/l/spclean-consultant"
}

function Assert-SPCConsultantLicense {
    param([Parameter(Mandatory)] [string]$Feature)
    $info = Get-SPCLicenseInfo
    if ($info.Status -eq 'Active' -and $info.Tier -eq 'CONSULTANT') { return }
    throw "ERR-LIC-004: '$Feature' requires a Consultant license. → Upgrade: https://ngochung47.gumroad.com/l/spclean-consultant"
}
