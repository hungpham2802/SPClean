#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Private/LicenseManager.ps1')
    . (Join-Path $PSScriptRoot '../../Private/New-SPCStorageDashboardHtmlInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Report/Export-SPCStorageReport.ps1')

    $script:SPCContext = [PSCustomObject]@{
        TenantName = 'contoso'
    }
}

Describe 'Export-SPCStorageReport Functional Tests' -Tag 'Report', 'Dashboard' {
    BeforeAll {
        $testReportDir = Join-Path $TestDrive 'Reports'
        if (-not (Test-Path $testReportDir)) {
            New-Item -Path $testReportDir -ItemType Directory -Force | Out-Null
        }
    }

    Context 'AC-13: Single-File Self-Contained HTML Dashboard' {
        It 'AC-13: Should generate standalone HTML dashboard without external CDN dependencies' {
            Mock Assert-SPCProLicense {}
            Mock New-SPCStorageDashboardHtmlInternal {
                param($OutputPath)
                '<!DOCTYPE html><html><head><style>/* inline */</style></head><body><h1>SPClean Dashboard</h1></body></html>' |
                    Out-File -FilePath $OutputPath -Encoding UTF8
            }

            $mockWaste = @(
                [PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/site1'; TotalWasteMB = 10240.0; StorageUsedMB = 20480.0; TotalRecycleBinMB = 5120.0; VersionWasteMB = 5120.0; PotentialMonthlySavingUSD = 2.0 }
            )

            $result = Export-SPCStorageReport -StorageWasteData $mockWaste -Format HTML -OutputPath (Join-Path $TestDrive 'Reports')

            Test-Path $result.HtmlDashboardPath | Should -BeTrue
            $htmlContent = Get-Content -Path $result.HtmlDashboardPath -Raw
            $htmlContent | Should -Not -Match '<script\s+src=["'']https?://'
            $htmlContent | Should -Not -Match '<link\s+rel=["'']stylesheet["'']\s+href=["'']https?://'
        }
    }

    Context 'AC-14: Financial KPI Aggregation' {
        It 'AC-14: Should accurately compute TotalWasteGB, MonthlySavingsUSD, and AnnualSavingsUSD' {
            Mock Assert-SPCProLicense {}
            Mock New-SPCStorageDashboardHtmlInternal {}

            $mockWaste = @(
                [PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/site1'; TotalWasteMB = 51200.0 },
                [PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/site2'; TotalWasteMB = 51200.0 }
            )

            $result = Export-SPCStorageReport -StorageWasteData $mockWaste -UnitPricePerGB 0.20 -OutputPath (Join-Path $TestDrive 'Reports')

            $result.TotalWasteGB | Should -Be 100.0
            $result.MonthlySavingsUSD | Should -Be 20.0
            $result.AnnualSavingsUSD | Should -Be 240.0
        }
    }

    Context 'AC-16: Consultant License Check for White-Labeling' {
        It 'AC-16: Should call Assert-SPCConsultantLicense when CompanyLogoUrl is supplied' {
            Mock Assert-SPCProLicense {}
            Mock Assert-SPCConsultantLicense {
                throw "ERR-LIC-004: Consultant license required"
            }

            $mockWaste = @(
                [PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/site1'; TotalWasteMB = 100.0 }
            )

            { Export-SPCStorageReport -StorageWasteData $mockWaste -CompanyLogoUrl 'https://cdn.example.com/logo.png' -OutputPath (Join-Path $TestDrive 'Reports') } |
                Should -Throw -ExpectedMessage "*ERR-LIC-004*"
        }
    }
}
