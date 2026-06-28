function Get-SPCLicenseInfo {
    <#
    .SYNOPSIS
        Returns the currently registered SPClean license status.
    .DESCRIPTION
        Reads license status from the module cache or disk. Never throws —
        returns a status object whether licensed or not. Re-verifies against
        Gumroad API after 7 days; falls back to cached status when offline.
        Use this to check license tier before calling paid features.
    .EXAMPLE
        Get-SPCLicenseInfo

        Returns the current license status. Status will be 'Active', 'Revoked',
        'Invalid', or 'Unlicensed'.
    .EXAMPLE
        if ((Get-SPCLicenseInfo).Status -ne 'Active') {
            Write-Warning 'SPClean Pro license required for this operation.'
        }
    .OUTPUTS
        SPC.LicenseInfo
    .NOTES
        Purchase SPClean Pro or Consultant at https://hungpham2802.gumroad.com
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $makeInfo = {
        param([string]$Status, [string]$Tier, [string]$Email,
              $RegisteredAt, $LastVerifiedAt, [bool]$IsTesting)
        $r = [PSCustomObject][ordered]@{
            Tier           = $Tier
            Email          = $Email
            RegisteredAt   = $RegisteredAt
            LastVerifiedAt = $LastVerifiedAt
            Status         = $Status
            IsTesting      = $IsTesting
        }
        $r.PSObject.TypeNames.Insert(0, 'SPC.LicenseInfo')
        $r
    }

    # Step 1: return from memory cache if LastVerifiedAt < 7 days
    if ($null -ne $script:SPCLicenseCache) {
        $cached = $script:SPCLicenseCache
        if ($null -ne $cached.LastVerifiedAt) {
            $cacheAgeDays = ([datetime]::UtcNow - $cached.LastVerifiedAt).TotalDays
            if ($cacheAgeDays -lt $script:LicenseCacheMaxAgeDays) {
                return $cached
            }
        }
        $script:SPCLicenseCache = $null
    }

    # Step 2: read from disk (Get-SPCLicenseDataInternal handles 7-day re-verify)
    $diskResult = Get-SPCLicenseDataInternal

    if ($diskResult.Status -ne 'Active') {
        return (& $makeInfo $diskResult.Status $null $null $null $null $false)
    }

    # Step 3: parse timestamps and build result
    $data = $diskResult.LicData
    $registeredAt   = $null
    $lastVerifiedAt = $null
    try {
        if (-not [string]::IsNullOrWhiteSpace($data.registeredAt)) {
            $registeredAt = [datetime]::Parse(
                $data.registeredAt,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind)
        }
        if (-not [string]::IsNullOrWhiteSpace($data.lastVerifiedAt)) {
            $lastVerifiedAt = [datetime]::Parse(
                $data.lastVerifiedAt,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind)
        }
    } catch {}

    $result = & $makeInfo 'Active' $data.tier $data.email $registeredAt $lastVerifiedAt ($data.isTesting -eq $true)

    $script:SPCLicenseCache = $result
    $result
}
