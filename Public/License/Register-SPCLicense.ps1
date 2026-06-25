function Register-SPCLicense {
    <#
    .SYNOPSIS
        Registers an SPClean license key on the current machine.
    .DESCRIPTION
        Validates the provided license key, writes a license.lic file to
        $env:APPDATA\SPClean\, and activates paid features (HTML report,
        scheduled scan, permission snapshots, restore). Run once after purchasing.
    .PARAMETER LicenseKey
        The full license key string: SPCLEAN-PRO-... or SPCLEAN-CONSULTANT-...
        Obtain from your Gumroad purchase receipt.
    .PARAMETER Force
        Overwrite an existing license.lic without prompting. Use in unattended
        or CI/CD scenarios.
    .EXAMPLE
        Register-SPCLicense -LicenseKey 'SPCLEAN-PRO-eyJ...'

        Validates and registers the key, prompting for confirmation if a license
        is already present.
    .EXAMPLE
        Register-SPCLicense -LicenseKey $env:SPCLEAN_LICENSE_KEY -Force

        Non-interactive registration for CI/CD pipelines.
    .OUTPUTS
        SPC.LicenseInfo
    .NOTES
        Purchase SPClean Pro or Consultant at https://spclean.gumroad.com
        The license.lic file is stored per-user and is not transferable between machines.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $LicenseKey,

        [Parameter()]
        [switch] $Force
    )

    begin {
        $trimmedKey = $LicenseKey.Trim()
        $keyPreview = if ($trimmedKey.Length -ge 20) { $trimmedKey.Substring(0, 20) + '...' } else { '(short key)' }
    }

    process {
        $secretBytes = $null
        try {
            $secretBytes = Get-SPCSecretKeyBytesInternal
            $validation  = Test-SPCLicenseKey -LicenseKey $trimmedKey -SecretKeyBytes $secretBytes
        } finally {
            if ($null -ne $secretBytes) {
                [System.Array]::Clear($secretBytes, 0, $secretBytes.Length)
            }
        }

        if (-not $validation.IsValid) {
            throw "ERR-LIC-001: Invalid license key ($keyPreview): $($validation.FailureReason). Verify the key and try again."
        }

        $licPath = Get-SPCLicensePathInternal
        $licDir  = Split-Path $licPath -Parent

        if ((Test-Path -Path $licPath -PathType Leaf) -and -not $Force) {
            $overwrite = $PSCmdlet.ShouldContinue(
                'A license is already registered. Overwrite?',
                'Register-SPCLicense'
            )
            if (-not $overwrite) {
                Write-Information 'Register-SPCLicense: Registration cancelled — existing license kept.' -InformationAction Continue
                return
            }
        }

        if (-not (Test-Path -Path $licDir -PathType Container)) {
            try {
                [void](New-Item -Path $licDir -ItemType Directory -Force -ErrorAction Stop)
            } catch {
                throw "ERR-LIC-002: Cannot create license directory '$licDir': $($_.Exception.Message)"
            }
        }

        $registeredAt = [datetime]::UtcNow
        $licContent   = [ordered]@{
            licenseKey   = $trimmedKey
            tier         = $validation.Tier
            email        = $validation.Email
            licenseId    = $validation.LicenseId
            expiresAt    = $validation.ExpiresAt.ToString('o')
            issuedAt     = $validation.IssuedAt.ToString('o')
            registeredAt = $registeredAt.ToString('o')
        }

        try {
            $json = $licContent | ConvertTo-Json -Compress
            [System.IO.File]::WriteAllText($licPath, $json, [System.Text.UTF8Encoding]::new($false))
        } catch {
            throw "ERR-LIC-002: Cannot write license file to '$licPath': $($_.Exception.Message)"
        }

        $script:SPCLicenseCache = $null

        $result = [PSCustomObject][ordered]@{
            Tier         = $validation.Tier
            Email        = $validation.Email
            LicenseId    = $validation.LicenseId
            ExpiresAt    = $validation.ExpiresAt
            RegisteredAt = $registeredAt
            Status       = 'Active'
        }
        $result.PSObject.TypeNames.Insert(0, 'SPC.LicenseInfo')

        Write-Information "SPClean $($validation.Tier) license registered successfully. Valid until $($validation.ExpiresAt.ToString('yyyy-MM-dd'))." -InformationAction Continue

        $result
    }
}
