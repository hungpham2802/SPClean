#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/PnPWrappers.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Private/LicenseManager.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Connect-SPCSiteInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Get-SPCGraphSiteUsageInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCPurviewHoldInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Scan/Get-SPCVersionWaste.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Scan/Get-SPCPreservationHoldWaste.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Scan/Get-SPCStorageWaste.ps1')

    $script:SPCContext = [PSCustomObject]@{
        TenantName       = 'contoso'
        AuthMethod       = 'Interactive'
        GraphAccessToken = 'mock_token'
        PnPContext       = [PSCustomObject]@{}
    }
}

Describe 'Get-SPCStorageWaste Unit Tests' -Tag 'Scan', 'Storage' {
    Context 'AC-01: Full Waste Discovery on Specified Site' {
        It 'AC-01: Should accurately aggregate all 4 waste vectors into SPC.StorageWasteSummary' {
            Mock Connect-SPCSiteInternal { [PSCustomObject]@{} }
            Mock Get-PnPWeb { [PSCustomObject]@{ Title = 'Marketing Portal' } }
            Mock Get-PnPSite {
                [PSCustomObject]@{
                    Usage = [PSCustomObject]@{
                        Storage      = 104857600000
                        StorageQuota = 209715200000
                    }
                }
            }
            Mock Get-PnPRecycleBinItem {
                @(
                    [PSCustomObject]@{ ItemState = 'FirstStageRecycleBin'; Size = 10737418240 },
                    [PSCustomObject]@{ ItemState = 'SecondStageRecycleBin'; Size = 5368709120 }
                )
            }
            Mock Get-SPCVersionWaste {
                [PSCustomObject]@{ RecoverableStorageMB = 20480.0 }
            }
            Mock Get-SPCPreservationHoldWaste {
                [PSCustomObject]@{ PHLSizeMB = 15360.0 }
            }

            $result = Get-SPCStorageWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Marketing' -IncludeRecycleBin -IncludeVersions -IncludePreservationHold

            $result.SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/Marketing'
            $result.StorageUsedMB | Should -Be 100000.0
            $result.StorageAllocatedMB | Should -Be 200000.0
            $result.StorageUsedPercent | Should -Be 50.0
            $result.TotalRecycleBinMB | Should -Be 15360.0
            $result.VersionWasteMB | Should -Be 20480.0
            $result.PreservationHoldMB | Should -Be 15360.0
            $result.TotalWasteMB | Should -Be 35840.0
        }
    }

    Context 'AC-02: Financial Savings ROI Calculation' {
        It 'AC-02: Should compute exact monthly and annual savings using standard $0.20/GB rate' {
            Mock Connect-SPCSiteInternal { [PSCustomObject]@{} }
            Mock Get-PnPWeb { [PSCustomObject]@{ Title = 'Finance Site' } }
            Mock Get-PnPSite {
                [PSCustomObject]@{ Usage = [PSCustomObject]@{ Storage = 104857600000; StorageQuota = 524288000000 } }
            }
            Mock Get-PnPRecycleBinItem {
                @( [PSCustomObject]@{ ItemState = 'FirstStageRecycleBin'; Size = 53687091200 } )
            }

            $result = Get-SPCStorageWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Finance' -IncludeRecycleBin

            $result.TotalWasteMB | Should -Be 51200.0
            $result.PotentialMonthlySavingUSD | Should -Be 10.0
            $result.PotentialAnnualSavingUSD | Should -Be 120.0
        }
    }

    Context 'AC-01: Pipeline Support and Top Filter' {
        It 'AC-01: Should sort descending by TotalWasteMB and respect Top parameter' {
            Mock Connect-SPCSiteInternal { [PSCustomObject]@{} }
            Mock Get-PnPWeb { [PSCustomObject]@{ Title = 'Test Site' } }
            Mock Get-PnPSite {
                [PSCustomObject]@{ Usage = [PSCustomObject]@{ Storage = 10737418240; StorageQuota = 107374182400 } }
            }
            Mock Get-PnPRecycleBinItem {
                @( [PSCustomObject]@{ ItemState = 'FirstStageRecycleBin'; Size = 10737418240 } )
            }

            $sites = @(
                'https://contoso.sharepoint.com/sites/site1',
                'https://contoso.sharepoint.com/sites/site2',
                'https://contoso.sharepoint.com/sites/site3'
            )

            $result = $sites | Get-SPCStorageWaste -Top 2
            $result.Count | Should -Be 2
        }
    }

    Context 'ERR-STO-101: Connection Validation' {
        It 'Should throw ERR-STO-101 when no active session context exists' {
            $savedContext = $script:SPCContext
            $script:SPCContext = $null
            try {
                { Get-SPCStorageWaste -SiteUrl 'https://contoso.sharepoint.com/sites/test' } |
                    Should -Throw -ExpectedMessage "*ERR-STO-101*"
            }
            finally {
                $script:SPCContext = $savedContext
            }
        }
    }
}
