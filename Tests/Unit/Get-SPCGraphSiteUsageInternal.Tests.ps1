#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/PnPWrappers.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Get-SPCGraphSiteUsageInternal.ps1')
}

Describe 'Get-SPCGraphSiteUsageInternal Unit Tests' -Tag 'Graph', 'Internal', 'Throttling' {
    BeforeEach {
        $script:SPCContext = [PSCustomObject]@{
            TenantName       = 'contoso'
            GraphAccessToken = 'mock_graph_token'
            PnPContext       = [PSCustomObject]@{ Url = 'https://contoso-admin.sharepoint.com' }
        }
    }

    Context 'TC-USAGE-001: CSV Parsing & OwnerUPN Mapping (RF-08)' {
        It 'TC-USAGE-001.1: Should map Site Owner Principal Name to OwnerUPN accurately' {
            $csvContent = @"
Report Refresh Date,Site URL,Site Title,Root Web Template,Site Owner Principal Name,Owner Display Name,Storage Used (Byte),Storage Allocated (Byte),File Count,Active File Count,Last Activity Date,Lock State,Group ID
2026-08-15,https://contoso.sharepoint.com/sites/ProjectA,Project A,STS#3,megan.bowen@contoso.com,Megan Bowen,104857600,1073741824,500,450,2026-08-10,Unlock,11111111-2222-3333-4444-555555555555
"@
            Mock Invoke-RestMethod { $csvContent }

            $result = Get-SPCGraphSiteUsageInternal

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
            $result[0].SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/ProjectA'
            $result[0].OwnerUPN | Should -Be 'megan.bowen@contoso.com'
            $result[0].StorageUsedMB | Should -Be 100.0
            $result[0].IsTeamSite | Should -BeTrue
        }
    }

    Context 'TC-USAGE-002: Throttling Resilience (HTTP 429 Backoff)' {
        It 'TC-USAGE-002.1: Should retry upon encountering HTTP 429 Throttling response' {
            $script:attemptCount = 0
            $csvContent = @"
Report Refresh Date,Site URL,Site Title,Root Web Template,Site Owner Principal Name,Owner Display Name,Storage Used (Byte),Storage Allocated (Byte),File Count,Active File Count,Last Activity Date,Lock State,Group ID
2026-08-15,https://contoso.sharepoint.com/sites/A,Site A,STS#3,admin@contoso.com,Admin,1024,2048,1,1,2026-08-10,Unlock,
"@
            Mock Invoke-RestMethod {
                $script:attemptCount++
                if ($script:attemptCount -lt 2) {
                    $mockResponse = [PSCustomObject]@{
                        StatusCode = [PSCustomObject]@{ value__ = 429 }
                        Headers = @{ 'Retry-After' = 1 }
                    }
                    $ex = [System.Exception]::new('Too Many Requests')
                    $ex | Add-Member -NotePropertyName Response -NotePropertyValue $mockResponse -Force
                    throw $ex
                }
                return $csvContent
            }
            Mock Start-Sleep { }

            $result = Get-SPCGraphSiteUsageInternal

            $result | Should -Not -BeNullOrEmpty
            $script:attemptCount | Should -Be 2
        }
    }

    Context 'TC-USAGE-003: Fallback Mechanism on Non-Throttling Failure' {
        It 'TC-USAGE-003.1: Should fallback to Get-PnPTenantSite when Graph endpoint fails' {
            Mock Invoke-RestMethod { throw [System.Exception]::new('Graph Endpoint 500 Internal Error') }
            Mock Get-PnPTenantSite {
                @(
                    [PSCustomObject]@{
                        Url                      = 'https://contoso.sharepoint.com/sites/FallbackSite'
                        Title                    = 'Fallback Site'
                        StorageUsageCurrent      = 512.0
                        Template                 = 'GROUP#0'
                        GroupId                  = 'mock-guid'
                        Owner                    = 'fallback.owner@contoso.com'
                        LockState                = 'Unlock'
                        LastContentModifiedDate = (Get-Date)
                    }
                )
            }

            $result = Get-SPCGraphSiteUsageInternal

            $result | Should -Not -BeNullOrEmpty
            $result[0].SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/FallbackSite'
            $result[0].OwnerUPN | Should -Be 'fallback.owner@contoso.com'
        }
    }
}
