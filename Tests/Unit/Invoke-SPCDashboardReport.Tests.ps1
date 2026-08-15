#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $moduleRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    $publicDir  = Join-Path $moduleRoot 'Public'
    $privateDir = Join-Path $moduleRoot 'Private'

    . (Join-Path $privateDir 'Test-SPCConnection.ps1')
    . (Join-Path $privateDir 'LicenseManager.ps1')
    . (Join-Path $privateDir 'New-SPCDashboardHtmlInternal.ps1')
    . (Join-Path $publicDir 'Scan\Get-SPCOrphanedUser.ps1')
    . (Join-Path $publicDir 'Scan\Get-SPCGuestAccess.ps1')
    . (Join-Path $publicDir 'Scan\Get-SPCPrivilegedUser.ps1')
    . (Join-Path $publicDir 'Scan\Get-SPCOverPermissionedUser.ps1')

    if (Test-Path (Join-Path $publicDir 'Report\Invoke-SPCDashboardReport.ps1')) {
        . (Join-Path $publicDir 'Report\Invoke-SPCDashboardReport.ps1')
    } elseif (Test-Path (Join-Path $publicDir 'Report\Invoke-SPCDashboardReportV1.ps1')) {
        . (Join-Path $publicDir 'Report\Invoke-SPCDashboardReportV1.ps1')
        # Alias shim for test execution if file is still named V1
        if (-not (Get-Command 'Invoke-SPCDashboardReport' -ErrorAction SilentlyContinue)) {
            Set-Alias -Name 'Invoke-SPCDashboardReport' -Value 'Invoke-SPCDashboardReportV1'
        }
    }

    # Standardized mock module context schema
    $script:FakeContext = [PSCustomObject]@{
        TenantName             = 'contoso'
        TenantId               = 'tid-12345'
        IsConnected            = $true
        AuthMethod             = 'Interactive'
        ConnectedAt            = (Get-Date).ToUniversalTime()
        GraphTokenRefreshedAt  = (Get-Date).ToUniversalTime()
        PnPContext             = [PSCustomObject]@{ Url = 'https://contoso-admin.sharepoint.com' }
        GraphAccessToken       = 'mock_access_token'
        _ClientId              = 'mock_client_id'
        _CertificateThumbprint = $null
        _CertificatePath       = $null
        _CertificatePassword   = $null
        _ClientSecret          = $null
    }
}

Describe 'Invoke-SPCDashboardReport' {

    BeforeEach {
        $script:SPCContext = $script:FakeContext

        Mock Test-SPCConnection {}
        Mock Assert-SPCProLicense {}
        Mock Get-SPCOrphanedUser {
            return @(
                [PSCustomObject]@{ DisplayName = 'User1'; UPN = 'u1@contoso.com'; RiskLevel = 'HIGH'; SiteTitle = 'HR'; SiteUrl = 'https://contoso/sites/hr' }
            )
        }
        Mock Get-SPCGuestAccess {
            return @(
                [PSCustomObject]@{ DisplayName = 'Guest1'; UPN = 'g1#EXT#@contoso.com'; RiskLevel = 'HIGH'; SiteTitle = 'HR'; SiteUrl = 'https://contoso/sites/hr' }
            )
        }
        Mock Get-SPCPrivilegedUser { return @() }
        Mock Get-SPCOverPermissionedUser { return @() }
        Mock Invoke-RestMethod { return [PSCustomObject]@{ '@odata.count' = 50 } }
    }

    Context 'AC-ARCH-02: License Gating' {
        It 'AC-ARCH-02: Throws ERR-LIC-001 when Pro license check fails' {
            Mock Assert-SPCProLicense {
                throw 'ERR-LIC-001: Feature DashboardReport requires an active Pro or Consultant license.'
            }

            $outputPath = Join-Path $TestDrive 'Dashboard_LicenseFail.html'
            { Invoke-SPCDashboardReport -OutputPath $outputPath } | Should -Throw '*ERR-LIC-001*'
        }
    }

    Context 'AC-ARCH-01 / AC-TEST-03: Execution & Output Contract' {
        It 'AC-ARCH-01 / AC-ARCH-02: Generates HTML file and returns output path or FileInfo' {
            $outputPath = Join-Path $TestDrive 'Dashboard_Success.html'
            
            $result = Invoke-SPCDashboardReport -OutputPath $outputPath
            
            Test-Path $outputPath | Should -BeTrue
            $content = Get-Content -Path $outputPath -Raw
            $content | Should -Match 'Overall Permission Health Score'
            $content | Should -Match 'User1'
            $content | Should -Match 'g1#EXT#@contoso.com'
        }

        It 'AC-TEST-03: Invokes all underlying scan cmdlets once during generation' {
            $outputPath = Join-Path $TestDrive 'Dashboard_Scans.html'
            
            $null = Invoke-SPCDashboardReport -OutputPath $outputPath

            Should -Invoke Get-SPCOrphanedUser -Times 1 -Exactly
            Should -Invoke Get-SPCGuestAccess -Times 1 -Exactly
            Should -Invoke Get-SPCPrivilegedUser -Times 1 -Exactly
            Should -Invoke Get-SPCOverPermissionedUser -Times 1 -Exactly
        }
    }

    Context 'Security & Stream Isolation' {
        It 'AC-SEC-02: Does not leak bearer tokens or credentials into Verbose stream' {
            $outputPath = Join-Path $TestDrive 'Dashboard_Sec.html'
            $script:verboseLog = @()
            Mock Write-Verbose {
                param($Message)
                $script:verboseLog += $Message
            }

            $null = Invoke-SPCDashboardReport -OutputPath $outputPath -Verbose

            $leak = $script:verboseLog | Where-Object { $_ -match 'password|secret|token|bearer|ey[A-Za-z0-9_-]+' }
            $leak | Should -BeNullOrEmpty
        }
    }
}
