#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/PnPWrappers.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Connect-SPCSiteInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Get-SPCGraphSiteUsageInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Scan/Get-SPCPreservationHoldWaste.ps1')

    $script:SPCContext = [PSCustomObject]@{
        TenantName       = 'contoso'
        GraphAccessToken = 'mock_token'
        PnPContext       = [PSCustomObject]@{}
    }
}

Describe 'Get-SPCPreservationHoldWaste Unit Tests' -Tag 'Scan', 'PHL' {
    Context 'AC-06: Non-Destructive Inspection of Preservation Hold Library' {
        It 'AC-06: Should measure PHL storage accurately without modifying any data' {
            Mock Connect-SPCSiteInternal { [PSCustomObject]@{} }
            Mock Get-PnPWeb { [PSCustomObject]@{ Title = 'Legal Department' } }
            Mock Get-PnPSite { [PSCustomObject]@{ Usage = [PSCustomObject]@{ Storage = 53687091200 } } }
            Mock Get-PnPList {
                [PSCustomObject]@{ Title = 'PreservationHoldLibrary'; ItemCount = 500 }
            }
            Mock Get-PnPListItem {
                @( [PSCustomObject]@{ 'File_x0020_Size' = 10737418240 } )
            }

            $result = Get-SPCPreservationHoldWaste -SiteUrl 'https://contoso.sharepoint.com/sites/LegalSite'

            $result.HasPreservationHold | Should -BeTrue
            $result.PHLSizeMB | Should -Be 10240.0
            $result.PHLFileCount | Should -Be 500
            $result.ComplianceHoldActive | Should -BeTrue
            $result.ComplianceNote | Should -Match 'Immutable'
        }

        It 'AC-06: Should report HasPreservationHold = $false when no PHL list exists' {
            Mock Connect-SPCSiteInternal { [PSCustomObject]@{} }
            Mock Get-PnPWeb { [PSCustomObject]@{ Title = 'Normal Site' } }
            Mock Get-PnPSite { [PSCustomObject]@{ Usage = [PSCustomObject]@{ Storage = 10737418240 } } }
            Mock Get-PnPList { $null }

            $result = Get-SPCPreservationHoldWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Normal'

            $result.HasPreservationHold | Should -BeFalse
            $result.PHLSizeMB | Should -Be 0.0
            $result.ComplianceHoldActive | Should -BeFalse
        }
    }

    Context 'AC-07: AlertLevel Threshold Evaluation' {
        It 'AC-07: Should set AlertLevel to Critical when PHL exceeds 2x WarningThresholdMB' {
            Mock Connect-SPCSiteInternal { [PSCustomObject]@{} }
            Mock Get-PnPWeb { [PSCustomObject]@{ Title = 'Big Legal' } }
            Mock Get-PnPSite { [PSCustomObject]@{ Usage = [PSCustomObject]@{ Storage = 107374182400 } } }
            Mock Get-PnPList {
                [PSCustomObject]@{ Title = 'PreservationHoldLibrary'; ItemCount = 1000 }
            }
            Mock Get-PnPListItem {
                @( [PSCustomObject]@{ 'File_x0020_Size' = 12884901888 } )
            }

            $result = Get-SPCPreservationHoldWaste -SiteUrl 'https://contoso.sharepoint.com/sites/BigLegal' -WarningThresholdMB 5120

            $result.AlertLevel | Should -Be 'Critical'
        }
    }
}
