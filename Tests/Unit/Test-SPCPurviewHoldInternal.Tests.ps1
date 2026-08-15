#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/PnPWrappers.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Connect-SPCSiteInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCPurviewHoldInternal.ps1')
}

Describe 'Test-SPCPurviewHoldInternal Unit Tests' -Tag 'Compliance', 'Internal', 'Hold' {
    BeforeEach {
        $script:SPCContext = [PSCustomObject]@{
            TenantName  = 'contoso'
            OperatorUPN = 'admin@contoso.onmicrosoft.com'
        }
    }

    Context 'TC-HOLD-001: Detection of Preservation Hold Library (PHL)' {
        It 'TC-HOLD-001.1: Should return IsHoldActive = $true when PHL list exists' {
            Mock Connect-SPCSiteInternal { [PSCustomObject]@{} }
            Mock Get-PnPSite { [PSCustomObject]@{ RootWeb = $null } }
            Mock Get-PnPList {
                param($Identity)
                if ($Identity -eq 'PreservationHoldLibrary' -or $Identity -eq 'Preservation Hold Library') {
                    [PSCustomObject]@{ Title = 'Preservation Hold Library' }
                }
            }

            $result = Test-SPCPurviewHoldInternal -SiteUrl 'https://contoso.sharepoint.com/sites/Legal'

            $result.IsHoldActive | Should -BeTrue
            $result.HoldType | Should -Be 'PurviewRetentionPolicy'
        }
    }

    Context 'TC-HOLD-002: Detection of eDiscovery Legal Hold via Web Properties' {
        It 'TC-HOLD-002.1: Should detect _ComplianceFlags in web property bag' {
            Mock Connect-SPCSiteInternal { [PSCustomObject]@{} }
            Mock Get-PnPList { $null }
            Mock Get-PnPProperty {}
            Mock Get-PnPSite {
                [PSCustomObject]@{
                    RootWeb = [PSCustomObject]@{
                        AllProperties = [PSCustomObject]@{
                            FieldValues = @{
                                '_ComplianceFlags' = '1'
                            }
                        }
                    }
                }
            }

            $result = Test-SPCPurviewHoldInternal -SiteUrl 'https://contoso.sharepoint.com/sites/Investigation'

            $result.IsHoldActive | Should -BeTrue
            $result.HoldType | Should -Be 'eDiscoveryHold'
        }
    }

    Context 'TC-HOLD-003: Unconstrained Site Verification' {
        It 'TC-HOLD-003.1: Should return IsHoldActive = $false for clean unheld sites' {
            Mock Connect-SPCSiteInternal { [PSCustomObject]@{} }
            Mock Get-PnPList { $null }
            Mock Get-PnPProperty {}
            Mock Get-PnPSite {
                [PSCustomObject]@{
                    RootWeb = [PSCustomObject]@{
                        AllProperties = [PSCustomObject]@{
                            FieldValues = @{}
                        }
                    }
                }
            }

            $result = Test-SPCPurviewHoldInternal -SiteUrl 'https://contoso.sharepoint.com/sites/Standard'

            $result.IsHoldActive | Should -BeFalse
            $result.HoldType | Should -Be 'None'
        }
    }

    Context 'TC-HOLD-004: Safe Error Handling on Access Denied' {
        It 'TC-HOLD-004.1: Should return safe object with error flag when access is restricted' {
            Mock Connect-SPCSiteInternal { throw [System.UnauthorizedAccessException]::new('Unauthorized access') }

            $result = Test-SPCPurviewHoldInternal -SiteUrl 'https://contoso.sharepoint.com/sites/Restricted'

            $result.IsHoldActive | Should -BeFalse
            $result.HoldType | Should -Be 'Unknown'
            $result.Details | Should -Match 'Unauthorized access'
        }
    }
}
