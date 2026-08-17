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

    Context 'Strategy 2: REST /_api/SPO.Tenant/SetSiteAdmin' {
        It 'Elevates operator to SCA via Tenant REST API when Set-PnPTenantSite fails' {
            Mock Set-PnPTenantSite { throw 'Attempted to perform an unauthorized operation.' }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = $true } }
            Mock Start-Sleep {}

            $res = Invoke-SPCTempElevationInternal -SiteUrl 'https://contoso.sharepoint.com/sites/TestSite'
            $res.Success | Should -BeTrue
            $res.ElevationType | Should -Be 'REST_SCA'
            Should -Invoke -CommandName Invoke-PnPSPRestMethod -Times 1 -Exactly
        }
    }

    Context 'Strategy 3: Graph Group Owner Fallback' {
        It 'Elevates operator to M365 Group Owner via Graph when CSOM and REST throw unauthorized' {
            Mock Set-PnPTenantSite { throw 'Attempted to perform an unauthorized operation.' }
            Mock Invoke-PnPSPRestMethod { throw 'Unauthorized' }
            Mock Start-Sleep {}
            Mock Invoke-RestMethod {
                param($Uri, $Method, $Headers, $Body)
                if ($Uri -match 'groups\?\$filter=') {
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

    Context 'Strategy 4: Graph Site Permissions API Fallback' {
        It 'Elevates operator via Graph /sites/{id}/permissions when other strategies fail' {
            Mock Set-PnPTenantSite { throw 'Unauthorized' }
            Mock Invoke-PnPSPRestMethod { throw 'Unauthorized' }
            Mock Start-Sleep {}
            Mock Invoke-RestMethod {
                param($Uri, $Method, $Headers, $Body)
                if ($Uri -match 'groups\?\$filter=') {
                    return [PSCustomObject]@{ value = @() }
                }
                if ($Uri -match 'sites/contoso.sharepoint.com:/sites/TestSite\?\$select=id') {
                    return [PSCustomObject]@{ id = 'site-id-999' }
                }
                if ($Uri -match 'users/admin@contoso.com') {
                    return [PSCustomObject]@{ id = 'user-oid-789'; displayName = 'Admin User'; userPrincipalName = 'admin@contoso.com' }
                }
                if ($Uri -match 'sites/site-id-999/permissions') {
                    return [PSCustomObject]@{ id = 'perm-id-111' }
                }
                return $null
            }

            $res = Invoke-SPCTempElevationInternal -SiteUrl 'https://contoso.sharepoint.com/sites/TestSite'
            $res.Success | Should -BeTrue
            $res.ElevationType | Should -Be 'GraphSitePerm'
            $res.PermissionId | Should -Be 'perm-id-111'
        }
    }

    Context 'Graceful Failure when all strategies are unauthorized' {
        It 'Returns structured failure object without throwing terminating error' {
            Mock Set-PnPTenantSite { throw 'Attempted to perform an unauthorized operation.' }
            Mock Invoke-PnPSPRestMethod { throw 'Unauthorized' }
            Mock Invoke-RestMethod { throw 'Unauthorized Graph call' }

            $res = Invoke-SPCTempElevationInternal -SiteUrl 'https://contoso.sharepoint.com/sites/StrictSite'
            $res.Success | Should -BeFalse
            $res.ElevationType | Should -Be 'None'
            $res.ErrorMessage | Should -Match 'All elevation strategies failed'
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

        It 'Calls REST SPO.Tenant for REST_SCA elevation rollback' {
            Mock Invoke-PnPSPRestMethod {}
            $rec = [PSCustomObject]@{
                Success       = $true
                ElevationType = 'REST_SCA'
                SiteUrl       = 'https://contoso.sharepoint.com/sites/TestSite'
                OperatorUPN   = 'admin@contoso.com'
            }

            Undo-SPCTempElevationInternal -ElevationRecord $rec -SiteConnection 'conn'
            Should -Invoke -CommandName Invoke-PnPSPRestMethod -Times 1 -Exactly
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

        It 'Removes Graph site permissions for GraphSitePerm elevation' {
            Mock Invoke-RestMethod {}
            $rec = [PSCustomObject]@{
                Success       = $true
                ElevationType = 'GraphSitePerm'
                SiteUrl       = 'https://contoso.sharepoint.com/sites/TestSite'
                OperatorUPN   = 'admin@contoso.com'
                GroupId       = 'site-id-999'
                PermissionId  = 'perm-id-111'
            }

            Undo-SPCTempElevationInternal -ElevationRecord $rec -SiteConnection $null
            Should -Invoke -CommandName Invoke-RestMethod -Times 1 -Exactly
        }
    }
}
