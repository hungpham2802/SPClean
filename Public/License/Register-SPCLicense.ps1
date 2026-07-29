function Register-SPCLicense {
    <#
    .SYNOPSIS
        Registers an SPClean license key on the current machine.
    .DESCRIPTION
        Validates the provided UUID license key via the Gumroad API, writes a
        license.lic file, and activates paid features (HTML report, scheduled scan,
        permission snapshots, restore). Requires internet access on first run.
        Obtain your key from your Gumroad purchase email after buying at
        https://ngochung47.gumroad.com/.
    .PARAMETER LicenseKey
        The UUID license key from your Gumroad purchase email.
        Format: XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX
    .PARAMETER Force
        Overwrite an existing license.lic without prompting. Use in unattended
        or CI/CD scenarios.
    .EXAMPLE
        Register-SPCLicense -LicenseKey '6F0E4C97-B72A4E69-A11BF6C4-AF6517E7'

        Validates and registers the key, prompting for confirmation if a license
        is already present.
    .EXAMPLE
        Register-SPCLicense -LicenseKey $env:SPCLEAN_LICENSE_KEY -Force

        Non-interactive registration for CI/CD pipelines.
    .OUTPUTS
        SPC.LicenseInfo
    .NOTES
        Purchase SPClean Pro at https://ngochung47.gumroad.com/l/spclean-pro or Consultant at https://ngochung47.gumroad.com/l/spclean-consultant
        The license.lic file is stored per-user in $env:APPDATA\SPClean\ (Windows)
        or $HOME/.config/SPClean/ (Linux/macOS).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $LicenseKey,

        [Parameter()]
        [switch] $Force
    )

    process {
        $trimmedKey = $LicenseKey.Trim()

        $result = Test-SPCLicenseKeyInternal -LicenseKey $trimmedKey

        if (-not $result.IsValid) {
            if ($result.FailureReason -eq 'NetworkError') {
                throw "ERR-LIC-NET-001: Cannot reach Gumroad API to verify license. Check internet connection and try again."
            }
            throw "ERR-LIC-001: Invalid license key: $($result.FailureReason). Verify the key from your Gumroad purchase email."
        }

        $tenantName = $null
        if ($result.Tier -eq 'PRO') {
            if (-not $script:SPCContext -or -not $script:SPCContext.TenantName) {
                throw "ERR-LIC-005: You must connect to a SharePoint tenant using Connect-SPCTenant before registering a PRO license."
            }
            $tenantName = $script:SPCContext.TenantName
        }

        $licPath = $script:LicenseFilePath
        $licDir  = Split-Path $licPath -Parent

        if ((Test-Path -Path $licPath -PathType Leaf) -and -not $Force) {
            $overwrite = $PSCmdlet.ShouldContinue(
                'Overwrite existing license?',
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
                throw "ERR-LIC-002: Cannot create license directory '${licDir}': $($_.Exception.Message)"
            }
        }

        $now = [datetime]::UtcNow
        $licContent = [ordered]@{
            licenseKey     = $trimmedKey
            tier           = $result.Tier
            email          = $result.Email
            purchasedAt    = if ($result.PurchasedAt) { $result.PurchasedAt.ToUniversalTime().ToString('o') } else { $now.ToString('o') }
            registeredTenant = $tenantName
            isTesting      = $result.IsTesting
            registeredAt   = $now.ToString('o')
            lastVerifiedAt = $now.ToString('o')
        }

        try {
            $json = $licContent | ConvertTo-Json -Compress
            [System.IO.File]::WriteAllText($licPath, $json, [System.Text.UTF8Encoding]::new($false))
        } catch {
            throw "ERR-LIC-002: Cannot write license file to '${licPath}': $($_.Exception.Message)"
        }

        $script:SPCLicenseCache = $null

        if ($result.IsTesting) {
            Write-Warning "Test purchase detected. This key is for testing only — do not use in production."
        }

        $output = [PSCustomObject][ordered]@{
            Tier             = $result.Tier
            Email            = $result.Email
            RegisteredTenant = $tenantName
            RegisteredAt     = $now
            LastVerifiedAt = $now
            Status         = 'Active'
            IsTesting      = $result.IsTesting
        }
        $output.PSObject.TypeNames.Insert(0, 'SPC.LicenseInfo')

        Write-Information "SPClean $($result.Tier) license registered. Valid for 1 year from purchase date." -InformationAction Continue

        $output
    }
}
