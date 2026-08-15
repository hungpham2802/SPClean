#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/New-SPCStorageDashboardHtmlInternal.ps1')
}

Describe 'New-SPCStorageDashboardHtmlInternal Unit Tests' -Tag 'Reporting', 'Internal', 'HTML' {
    BeforeAll {
        $TestHtmlDir = Join-Path -Path $TestDrive -ChildPath 'HtmlReports'
    }

    BeforeEach {
        $script:SPCContext = [PSCustomObject]@{
            TenantName  = 'contoso'
            OperatorUPN = 'admin@contoso.onmicrosoft.com'
        }
    }

    Context 'TC-HTML-001: Self-Contained HTML Generation (0 External CDN)' {
        It 'TC-HTML-001.1: Should generate complete HTML file with embedded CSS and zero CDN links' {
            $outputPath = Join-Path -Path $TestHtmlDir -ChildPath 'storage_dashboard.html'
            $mockData = @(
                [PSCustomObject]@{
                    SiteUrl                   = 'https://contoso.sharepoint.com/sites/Sales'
                    SiteTitle                 = 'Sales Hub'
                    StorageUsedMB             = 102400.0
                    StorageAllocatedMB        = 204800.0
                    RecycleBin1stStageMB      = 5120.0
                    RecycleBin2ndStageMB      = 2048.0
                    TotalRecycleBinMB         = 7168.0
                    VersionWasteMB            = 15360.0
                    PreservationHoldMB        = 8192.0
                    TotalWasteMB              = 22528.0
                    PotentialMonthlySavingUSD = 4.40
                    PotentialAnnualSavingUSD  = 52.80
                }
            )

            New-SPCStorageDashboardHtmlInternal -StorageWasteData $mockData -OutputPath $outputPath -UnitPricePerGB 0.20

            Test-Path $outputPath | Should -BeTrue
            $content = Get-Content -Path $outputPath -Raw
            $content | Should -Match '<!DOCTYPE html>'
            $content | Should -Match '<style>'
            $content | Should -Not -Match 'https://cdn\.'
            $content | Should -Not -Match 'https://cdnjs\.'
            $content | Should -Not -Match 'https://fonts\.googleapis\.com'
        }
    }

    Context 'TC-HTML-002: Consultant White-Label Branding' {
        It 'TC-HTML-002.1: Should render custom Client Name and Company Logo when provided' {
            $outputPath = Join-Path -Path $TestHtmlDir -ChildPath 'whitelabel_dashboard.html'
            $mockData = @([PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/1'; TotalWasteMB = 100.0; StorageUsedMB = 200.0; TotalRecycleBinMB = 50.0; VersionWasteMB = 50.0; PotentialMonthlySavingUSD = 0.02 })

            New-SPCStorageDashboardHtmlInternal `
                -StorageWasteData $mockData `
                -OutputPath $outputPath `
                -UnitPricePerGB 0.20 `
                -ClientName 'Fabrikam Global Corp' `
                -CompanyLogoUrl 'https://fabrikam.com/logo.png'

            $content = Get-Content -Path $outputPath -Raw
            $content | Should -Match 'Fabrikam Global Corp'
            $content | Should -Match 'https://fabrikam.com/logo.png'
        }
    }

    Context 'TC-HTML-003: KPI Cards and Financial ROI Calculations' {
        It 'TC-HTML-003.1: Should render calculated Annual Cost Savings and metrics' {
            $outputPath = Join-Path -Path $TestHtmlDir -ChildPath 'kpi_dashboard.html'
            $mockData = @(
                [PSCustomObject]@{
                    SiteUrl                   = 'https://contoso.sharepoint.com/sites/Eng'
                    StorageUsedMB             = 1000000.0
                    TotalRecycleBinMB         = 200000.0
                    VersionWasteMB            = 200000.0
                    TotalWasteMB              = 400000.0
                    PotentialMonthlySavingUSD = 80.00
                }
            )

            New-SPCStorageDashboardHtmlInternal -StorageWasteData $mockData -OutputPath $outputPath -UnitPricePerGB 0.20

            $content = Get-Content -Path $outputPath -Raw
            $content | Should -Match 'SPClean — Storage ROI Executive Dashboard'
            $content | Should -Match 'Digital Waste Identified'
        }
    }
}
