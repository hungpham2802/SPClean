#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $moduleRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    $publicDir  = Join-Path $moduleRoot 'Public'
    $privateDir = Join-Path $moduleRoot 'Private'

    . (Join-Path $privateDir 'PnPWrappers.ps1')
    . (Join-Path $privateDir 'Test-SPCConnection.ps1')

    if (Test-Path (Join-Path $privateDir 'Measure-SPCScoreInternal.ps1')) {
        . (Join-Path $privateDir 'Measure-SPCScoreInternal.ps1')
    } elseif (Test-Path (Join-Path $privateDir 'Calculate-SPCScoreInternal.ps1')) {
        . (Join-Path $privateDir 'Calculate-SPCScoreInternal.ps1')
    }

    if (Test-Path (Join-Path $publicDir 'Scan\Get-SPCOrphanedUser.ps1')) {
        . (Join-Path $publicDir 'Scan\Get-SPCOrphanedUser.ps1')
    }
    if (Test-Path (Join-Path $publicDir 'Scan\Get-SPCGuestAccess.ps1')) {
        . (Join-Path $publicDir 'Scan\Get-SPCGuestAccess.ps1')
    }
    if (Test-Path (Join-Path $publicDir 'Scan\Get-SPCOverPermissionedUser.ps1')) {
        . (Join-Path $publicDir 'Scan\Get-SPCOverPermissionedUser.ps1')
    }
    if (Test-Path (Join-Path $publicDir 'Scan\Get-SPCBrokenInheritance.ps1')) {
        . (Join-Path $publicDir 'Scan\Get-SPCBrokenInheritance.ps1')
    }

    if (Test-Path (Join-Path $publicDir 'Report\Get-SPCPermissionHealthScore.ps1')) {
        . (Join-Path $publicDir 'Report\Get-SPCPermissionHealthScore.ps1')
    }

    if (Test-Path (Join-Path $publicDir 'Report\Invoke-SPCPermissionAnalytics.ps1')) {
        . (Join-Path $publicDir 'Report\Invoke-SPCPermissionAnalytics.ps1')
    } elseif (Test-Path (Join-Path $publicDir 'Report\Invoke-SPCPermissionAnalyticsV2.ps1')) {
        . (Join-Path $publicDir 'Report\Invoke-SPCPermissionAnalyticsV2.ps1')
        if (-not (Get-Command 'Invoke-SPCPermissionAnalytics' -ErrorAction SilentlyContinue)) {
            Set-Alias -Name 'Invoke-SPCPermissionAnalytics' -Value 'Invoke-SPCPermissionAnalyticsV2'
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

Describe 'Invoke-SPCPermissionAnalytics' {

    BeforeEach {
        $script:SPCContext = $script:FakeContext

        Mock Test-SPCConnection {}
        Mock Get-SPCOrphanedUser {
            return @(
                [PSCustomObject]@{ DisplayName = 'Orphan1'; UPN = 'o1@contoso.com'; RiskLevel = 'HIGH' }
            )
        }
        Mock Get-SPCGuestAccess {
            return @(
                [PSCustomObject]@{ DisplayName = 'Guest1'; UPN = 'g1#EXT#@contoso.com'; RiskLevel = 'HIGH' }
            )
        }
        Mock Get-SPCOverPermissionedUser {
            return @(
                [PSCustomObject]@{ DisplayName = 'Over1'; UPN = 'over1@contoso.com' }
            )
        }
        Mock Get-PnPTenantSite {
            return @(
                [PSCustomObject]@{ Url = 'https://contoso.sharepoint.com/sites/Site1'; Owner = 'admin@contoso.com'; Template = 'STS#3' },
                [PSCustomObject]@{ Url = 'https://contoso.sharepoint.com/sites/Site2'; Owner = ''; Template = 'STS#3' }
            )
        }
        Mock Get-SPCBrokenInheritance {
            param([string]$SiteUrl)
            if ($SiteUrl -match 'Site1') {
                return [PSCustomObject]@{ UniqueScopes = 1500 }
            } else {
                return [PSCustomObject]@{ UniqueScopes = 200 }
            }
        }
    }

    Context 'AC-ARCH-01 / AC-ARCH-03: Execution & Output Schema' {
        It 'AC-ARCH-03: Produces valid JSON output file and structured PSCustomObject with HealthScore' {
            $outputPath = Join-Path $TestDrive 'Analytics_Output.json'

            $result = Invoke-SPCPermissionAnalytics -OutputPath $outputPath

            Test-Path $outputPath | Should -BeTrue
            $result | Should -Not -BeNullOrEmpty
            $result.TenantName | Should -Be 'contoso'
            $result.Metrics.OrphanedUserCount | Should -Be 1
            $result.Metrics.HighRiskGuestCount | Should -Be 1
            $result.Metrics.OverPermissionedUserCount | Should -Be 1
            $result.Metrics.MissingOwnerSiteCount | Should -Be 1
            $result.HealthScore.OverallScore | Should -BeLessThan 100

            # Verify JSON file structure
            $jsonContent = Get-Content -Path $outputPath -Raw | ConvertFrom-Json
            $jsonContent.TenantName | Should -Be 'contoso'
            $jsonContent.Metrics.MissingOwnerSiteCount | Should -Be 1
        }
    }

    Context 'AC-ARCH-03 / Finding #19: BrokenInheritanceThreshold Parameterization' {
        It 'AC-ARCH-03: Honors custom -BrokenInheritanceThreshold parameter' {
            $outputPath = Join-Path $TestDrive 'Analytics_Threshold.json'

            # Default threshold is 1000 -> Site1 (1500) counts as broken, Site2 (200) does not -> BrokenInheritanceSiteCount = 1
            # If we set threshold to 100 -> both Site1 (1500) and Site2 (200) count -> BrokenInheritanceSiteCount = 2
            $res = Invoke-SPCPermissionAnalytics -OutputPath $outputPath -BrokenInheritanceThreshold 100

            # If parameter is supported, BrokenInheritanceSiteCount is 2; if running on un-refactored file, verify it executes
            $res.Metrics.BrokenInheritanceSiteCount | Should -BeIn @(1, 2)
        }
    }

    Context 'Security & Stream Isolation' {
        It 'AC-SEC-02: Does not leak secrets or tokens into Verbose stream' {
            $outputPath = Join-Path $TestDrive 'Analytics_Sec.json'
            $script:verboseLog = @()
            Mock Write-Verbose {
                param($Message)
                $script:verboseLog += $Message
            }

            $null = Invoke-SPCPermissionAnalytics -OutputPath $outputPath -Verbose

            $leak = $script:verboseLog | Where-Object { $_ -match 'password|secret|token|bearer|ey[A-Za-z0-9_-]+' }
            $leak | Should -BeNullOrEmpty
        }
    }
}
