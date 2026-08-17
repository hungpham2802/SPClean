#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Invoke-SPCTempElevationInternal' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../../Private/PnPWrappers.ps1')
        . (Join-Path $PSScriptRoot '../../Private/Invoke-SPCTempElevationInternal.ps1')
    }

    BeforeEach {
        $script:SPCContext = [PSCustomObject]@{
            TenantName       = 'contoso'
            AuthMethod       = 'Interactive'
            OperatorUPN      = 'admin@contoso.com'
            GraphAccessToken = 'mock_graph_token'
            PnPContext       = [PSCustomObject]@{ Url = 'https://contoso-admin.sharepoint.com' }
        }
    }

    Context 'Strategy 1: CSOM Set-PnPTenantSite Success' {
        It 'Elevates operator to SCA via Set-PnPTenantSite when authorized' {
            Mock Set-PnPTenantSite {}
            Mock Start-Sleep {}

            $res = Invoke-SPCTempElevationInternal -SiteUrl 'https://contoso.sharepoint.com/sites/TestSite'
            $res.Success | Should -BeTrue
            $res.ElevationType | Should -Be 'SCA'
            $res.OperatorUPN | Should -Be 'admin@contoso.com'
            Should -Invoke -CommandName Set-PnPTenantSite -Times 1 -Exactly
        }
    }

    Context 'Strategy 2: Graph Group Owner Fallback when CSOM is Unauthorized' {
        It 'Elevates operator to M365 Group Owner via Graph when CSOM throws unauthorized' {
            Mock Set-PnPTenantSite { throw 'Attempted to perform an unauthorized operation.' }
            Mock Start-Sleep {}
            Mock Invoke-RestMethod {
                param($Uri, $Method, $Headers, $Body)
                if ($Uri -match 'sites/contoso.sharepoint.com:/sites/TestGroup') {
                    return [PSCustomObject]@{ id = 'site-123' }
                }
                if ($Uri -match 'groups\?\$filter=mailNickname eq') {
                    return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'group-456' }) }
                }
                if ($Uri -match 'users/admin@contoso.com') {
                    return [PSCustomObject]@{ id = 'user-oid-789' }
                }
                if ($Uri -match 'groups/group-456/owners/\$ref') {
                    return $null
                }
                return $null
            }

            $res = Invoke-SPCTempElevationInternal -SiteUrl 'https://contoso.sharepoint.com/sites/TestGroup'
            $res.Success | Should -BeTrue
            $res.ElevationType | Should -Be 'GroupOwner'
            $res.GroupId | Should -Be 'group-456'
        }
    }

    Context 'Graceful Failure when all strategies are unauthorized' {
        It 'Returns structured failure object without throwing terminating error' {
            Mock Set-PnPTenantSite { throw 'Attempted to perform an unauthorized operation.' }
            Mock Invoke-RestMethod { throw 'Unauthorized Graph call' }

            $res = Invoke-SPCTempElevationInternal -SiteUrl 'https://contoso.sharepoint.com/sites/StrictSite'
            $res.Success | Should -BeFalse
            $res.ElevationType | Should -Be 'None'
            $res.ErrorMessage | Should -Match 'unauthorized'
        }
    }

    Context 'Undo-SPCTempElevationInternal Rollback' {
        It 'Calls Remove-PnPSiteCollectionAdmin for SCA elevation' {
            Mock Remove-PnPSiteCollectionAdmin {}
            $rec = [PSCustomObject]@{
                Success       = $true
                ElevationType = 'SCA'
                SiteUrl       = 'https://contoso.sharepoint.com/sites/TestSite'
                OperatorUPN   = 'admin@contoso.com'
            }

            Undo-SPCTempElevationInternal -ElevationRecord $rec -SiteConnection 'conn'
            Should -Invoke -CommandName Remove-PnPSiteCollectionAdmin -Times 1 -Exactly
        }

        It 'Removes Graph group owner for GroupOwner elevation' {
            Mock Invoke-RestMethod {
                param($Uri, $Method)
                if ($Uri -match 'users/admin@contoso.com') {
                    return [PSCustomObject]@{ id = 'user-oid-789' }
                }
                return $null
            }

            $rec = [PSCustomObject]@{
                Success       = $true
                ElevationType = 'GroupOwner'
                SiteUrl       = 'https://contoso.sharepoint.com/sites/TestGroup'
                OperatorUPN   = 'admin@contoso.com'
                GroupId       = 'group-456'
            }

            Undo-SPCTempElevationInternal -ElevationRecord $rec -SiteConnection $null
            Should -Invoke -CommandName Invoke-RestMethod -Times 2
        }
    }
}
