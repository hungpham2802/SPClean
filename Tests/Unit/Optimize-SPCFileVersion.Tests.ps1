#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Private/LicenseManager.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Connect-SPCSiteInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Write-SPCAuditLogInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Invoke-SPCVersionTrimmingInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Remediate/Optimize-SPCFileVersion.ps1')

    $script:SPCContext = [PSCustomObject]@{
        TenantName       = 'contoso'
        PnPContext       = [PSCustomObject]@{}
        GraphAccessToken = 'mock_token'
    }
}

Describe 'Optimize-SPCFileVersion Functional Tests' -Tag 'Remediate', 'Versions' {
    Context 'AC-11: Version Trimming Remediation' {
        It 'AC-11: Should trim versions and calculate freed storage' {
            Mock Assert-SPCProLicense {}
            Mock Invoke-SPCVersionTrimmingInternal {
                [PSCustomObject]@{
                    LibrariesProcessed   = 2
                    FilesOptimizedCount  = 15
                    VersionsRemovedCount = 120
                    StorageFreedMB       = 1024.0
                }
            }

            $result = Optimize-SPCFileVersion -SiteUrl 'https://contoso.sharepoint.com/sites/rnd' -KeepVersions 20 -OlderThanDays 60 -Force

            $result.LibrariesProcessed | Should -Be 2
            $result.FilesOptimizedCount | Should -Be 15
            $result.VersionsRemovedCount | Should -Be 120
            $result.StorageFreedMB | Should -Be 1024.0
            $result.MonthlyCostSavedUSD | Should -Be 0.20
            $result.AnnualCostSavedUSD | Should -Be 2.40
            $result.IsDryRun | Should -BeFalse
        }
    }

    Context 'AC-12: Library MajorVersionLimit Policy Update' {
        It 'AC-12: Should pass ApplyPolicy $true to internal helper when -ApplyPolicyToLibrary switch is specified' {
            Mock Assert-SPCProLicense {}
            Mock Invoke-SPCVersionTrimmingInternal {
                param($ApplyPolicy, $KeepVersions)
                $ApplyPolicy | Should -BeTrue
                $KeepVersions | Should -Be 25
                [PSCustomObject]@{
                    LibrariesProcessed   = 2
                    FilesOptimizedCount  = 10
                    VersionsRemovedCount = 100
                    StorageFreedMB       = 512.0
                }
            }

            $result = Optimize-SPCFileVersion -SiteUrl 'https://contoso.sharepoint.com/sites/rnd' -KeepVersions 25 -ApplyPolicyToLibrary -Force

            $result.PolicyUpdated | Should -BeTrue
            $result.StorageFreedMB | Should -Be 512.0
        }
    }
}
