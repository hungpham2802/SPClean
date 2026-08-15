#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $moduleRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    $publicDir  = Join-Path $moduleRoot 'Public'
    $privateDir = Join-Path $moduleRoot 'Private'

    # Dot-source required private helpers and public cmdlets
    if (Test-Path (Join-Path $privateDir 'Measure-SPCScoreInternal.ps1')) {
        . (Join-Path $privateDir 'Measure-SPCScoreInternal.ps1')
    } elseif (Test-Path (Join-Path $privateDir 'Calculate-SPCScoreInternal.ps1')) {
        . (Join-Path $privateDir 'Calculate-SPCScoreInternal.ps1')
    }
    
    if (Test-Path (Join-Path $privateDir 'PnPWrappers.ps1')) {
        . (Join-Path $privateDir 'PnPWrappers.ps1')
    }
    if (Test-Path (Join-Path $privateDir 'Connect-SPCSiteInternal.ps1')) {
        . (Join-Path $privateDir 'Connect-SPCSiteInternal.ps1')
    }
    . (Join-Path $privateDir 'Get-SPCLibraryBrokenInheritanceInternal.ps1')
    . (Join-Path $privateDir 'Test-SPCConnection.ps1')

    if (Test-Path (Join-Path $publicDir 'Report\Get-SPCPermissionHealthScore.ps1')) {
        . (Join-Path $publicDir 'Report\Get-SPCPermissionHealthScore.ps1')
    }
    if (Test-Path (Join-Path $publicDir 'Scan\Get-SPCBrokenInheritance.ps1')) {
        . (Join-Path $publicDir 'Scan\Get-SPCBrokenInheritance.ps1')
    }
    if (Test-Path (Join-Path $publicDir 'Report\Compare-SPCPermissionSnapshot.ps1')) {
        . (Join-Path $publicDir 'Report\Compare-SPCPermissionSnapshot.ps1')
    }

    # Define score helper wrapper for backward/forward compatibility during test execution
    function Invoke-ScoreTest {
        param(
            [int]$OrphanedUserCount,
            [int]$HighRiskGuestCount,
            [int]$OverPermissionedUserCount,
            [int]$BrokenInheritanceSiteCount,
            [int]$MissingOwnerSiteCount
        )
        if (Get-Command 'Measure-SPCScoreInternal' -ErrorAction SilentlyContinue) {
            Measure-SPCScoreInternal @PSBoundParameters
        } else {
            Calculate-SPCScoreInternal @PSBoundParameters
        }
    }

    # Standardized mock module context schema conforming to FR-TEST-03 / AC-TEST-04
    $script:SPCContext = [PSCustomObject]@{
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

Describe 'Phase 2 Architecture & Health Analytics Unit Tests' {

    Context 'Measure-SPCScoreInternal (Health Score Engine)' {
        It 'AC-STD-04: Returns score 100 with zero risk counts' {
            $res = Invoke-ScoreTest -OrphanedUserCount 0 -HighRiskGuestCount 0 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0
            $res.OverallScore | Should -Be 100
            $res.Breakdown.OrphanedUserDeduction | Should -Be 0
            $res.Breakdown.HighRiskGuestDeduction | Should -Be 0
            $res.Breakdown.OverPermissionedDeduction | Should -Be 0
            $res.Breakdown.BrokenInheritanceDeduction | Should -Be 0
            $res.Breakdown.MissingOwnerDeduction | Should -Be 0
        }

        It 'AC-STD-04: Deducts Orphaned User points below the 30-point cap' {
            $res = Invoke-ScoreTest -OrphanedUserCount 10 -HighRiskGuestCount 0 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0
            $res.OverallScore | Should -Be 80
            $res.Breakdown.OrphanedUserDeduction | Should -Be 20
        }

        It 'AC-STD-04: Caps Orphaned User deduction at maximum 30 points' {
            $res = Invoke-ScoreTest -OrphanedUserCount 20 -HighRiskGuestCount 0 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0
            $res.OverallScore | Should -Be 70
            $res.Breakdown.OrphanedUserDeduction | Should -Be 30
        }

        It 'AC-STD-04: Deducts High-Risk Guest points below the 25-point cap' {
            $res = Invoke-ScoreTest -OrphanedUserCount 0 -HighRiskGuestCount 10 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0
            $res.OverallScore | Should -Be 85
            $res.Breakdown.HighRiskGuestDeduction | Should -Be 15
        }

        It 'AC-STD-04: Caps High-Risk Guest deduction at maximum 25 points' {
            $res = Invoke-ScoreTest -OrphanedUserCount 0 -HighRiskGuestCount 20 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0
            $res.OverallScore | Should -Be 75
            $res.Breakdown.HighRiskGuestDeduction | Should -Be 25
        }

        It 'AC-STD-04: Caps Over-Permissioned User deduction at maximum 20 points' {
            $res = Invoke-ScoreTest -OrphanedUserCount 0 -HighRiskGuestCount 0 -OverPermissionedUserCount 15 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0
            $res.OverallScore | Should -Be 80
            $res.Breakdown.OverPermissionedDeduction | Should -Be 20
        }

        It 'AC-STD-04: Correctly calculates Broken Inheritance and Missing Owner deductions' {
            $res = Invoke-ScoreTest -OrphanedUserCount 0 -HighRiskGuestCount 0 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 2 -MissingOwnerSiteCount 1
            $res.OverallScore | Should -Be 60
            $res.Breakdown.BrokenInheritanceDeduction | Should -Be 30
            $res.Breakdown.MissingOwnerDeduction | Should -Be 10
        }

        It 'AC-STD-04: Floors overall health score to 0 in worst-case risk combination' {
            $res = Invoke-ScoreTest -OrphanedUserCount 100 -HighRiskGuestCount 100 -OverPermissionedUserCount 100 -BrokenInheritanceSiteCount 10 -MissingOwnerSiteCount 10
            $res.OverallScore | Should -Be 0
        }
    }

    Context 'Get-SPCLibraryBrokenInheritanceInternal' {
        BeforeEach {
            $script:SPCContext = [PSCustomObject]@{
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

            Mock Get-PnPAccessToken { return 'mock_token' }
            Mock Connect-PnPOnline { return [PSCustomObject]@{ Url = 'https://test.sharepoint.com/sites/test' } }
        }

        It 'AC-ARCH-03: Detects folders with broken permission inheritance' {
            Mock Get-PnPList {
                return @(
                    [PSCustomObject]@{
                        Title = 'DocLib1'
                        BaseType = 'DocumentLibrary'
                        Hidden = $false
                        HasUniqueRoleAssignments = $false
                        RootFolder = [PSCustomObject]@{ ServerRelativeUrl = '/sites/test/DocLib1' }
                    }
                )
            }
            Mock Get-PnPListItem {
                return @(
                    [PSCustomObject]@{
                        Id = 1
                        HasUniqueRoleAssignments = $true
                        FileSystemObjectType = 'Folder'
                        FieldValues = @{ FileRef = '/sites/test/DocLib1/Folder1' }
                    }
                )
            }

            $res = @(Get-SPCLibraryBrokenInheritanceInternal -SiteUrl 'https://test.sharepoint.com/sites/test')
            $res.Count | Should -Be 1
            $res[0].Path | Should -Be '/sites/test/DocLib1/Folder1'
            $res[0].Type | Should -Be 'Folder'
        }
    }

    Context 'Compare-SPCPermissionSnapshot' {
        BeforeAll {
            $baseline = @(
                @{ user = @{ upn = 'admin@test.com' }; isSCA = $true; isOwner = $false; permissions = @() },
                @{ user = @{ upn = 'owner@test.com' }; isSCA = $false; isOwner = $true; permissions = @() },
                @{ user = @{ upn = 'user1@test.com' }; isSCA = $false; isOwner = $false; permissions = @('Full Control') },
                @{ user = @{ upn = 'guest#EXT#@external.com' }; isSCA = $false; isOwner = $false; permissions = @() }
            ) | ConvertTo-Json -Depth 5
            
            $current = @(
                @{ user = @{ upn = 'admin@test.com' }; isSCA = $true; isOwner = $false; permissions = @() },
                @{ user = @{ upn = 'newadmin@test.com' }; isSCA = $true; isOwner = $false; permissions = @() },
                @{ user = @{ upn = 'owner@test.com' }; isSCA = $false; isOwner = $true; permissions = @() },
                @{ user = @{ upn = 'newowner@test.com' }; isSCA = $false; isOwner = $true; permissions = @() },
                @{ user = @{ upn = 'user1@test.com' }; isSCA = $false; isOwner = $false; permissions = @('Full Control') },
                @{ user = @{ upn = 'user2@test.com' }; isSCA = $false; isOwner = $false; permissions = @('Full Control') },
                @{ user = @{ upn = 'guest#EXT#@external.com' }; isSCA = $false; isOwner = $false; permissions = @() },
                @{ user = @{ upn = 'newguest#EXT#@external.com' }; isSCA = $false; isOwner = $false; permissions = @() }
            ) | ConvertTo-Json -Depth 5
            
            $script:tempBaseline = Join-Path $TestDrive 'baseline.json'
            $script:tempCurrent  = Join-Path $TestDrive 'current.json'
            Set-Content -Path $script:tempBaseline -Value $baseline -Encoding UTF8
            Set-Content -Path $script:tempCurrent -Value $current -Encoding UTF8
        }
        
        It 'AC-ARCH-05: Accurately detects permission drift across SCAs, Owners, Direct Full Control, and Guests' {
            Mock Test-SPCConnection { return $true }
            
            $res = Compare-SPCPermissionSnapshot -BaselineSnapshotPath $script:tempBaseline -CurrentSnapshotPath $script:tempCurrent
            
            $res.NewSCAOrOwners | Should -Contain 'newadmin@test.com'
            $res.NewSCAOrOwners | Should -Contain 'newowner@test.com'
            $res.NewDirectFullControlAssignments | Should -Contain 'user2@test.com'
            $res.NewGuestAccounts | Should -Contain 'newguest#EXT#@external.com'
        }
    }
    
    Context 'Security & Stream Isolation' {
        It 'AC-SEC-02: Does not leak secrets or bearer tokens into Verbose stream' {
            $script:verboseLog = @()
            Mock Write-Verbose {
                param($Message)
                $script:verboseLog += $Message
            }

            Invoke-ScoreTest -OrphanedUserCount 0 -HighRiskGuestCount 0 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0 -Verbose
            
            $leak = $script:verboseLog | Where-Object { $_ -match 'password|secret|token|bearer' }
            $leak | Should -BeNullOrEmpty
        }
    }
}
