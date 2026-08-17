#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/PnPWrappers.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Connect-SPCSiteInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Invoke-SPCTempElevationInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Get-SPCLibraryBrokenInheritanceInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Scan/Get-SPCBrokenInheritance.ps1')
}

Describe 'Get-SPCBrokenInheritance Unit Tests' -Tag 'Scan', 'Permissions', 'Governance' {
    BeforeEach {
        $script:SPCContext = [PSCustomObject]@{
            TenantName       = 'contoso'
            OperatorUPN      = 'admin@contoso.onmicrosoft.com'
            AuthMode         = 'Interactive'
            GraphAccessToken = 'mock_token'
            PnPContext       = [PSCustomObject]@{ Url = 'https://contoso-admin.sharepoint.com' }
        }
    }

    Context 'Unique Role Assignments (Broken Inheritance) Discovery' {
        It 'Should detect broken inheritance on Document Libraries and return structured object' {
            Mock Test-SPCConnection { $true }
            Mock Connect-SPCSiteInternal { [PSCustomObject]@{ Url = 'https://contoso.sharepoint.com/sites/Finance' } }
            Mock Get-PnPList {
                @(
                    [PSCustomObject]@{
                        Title                    = 'Restricted Invoices'
                        BaseType                 = 'DocumentLibrary'
                        HasUniqueRoleAssignments = $true
                        Hidden                   = $false
                        RootFolder               = [PSCustomObject]@{ ServerRelativeUrl = '/sites/Finance/Invoices' }
                    }
                )
            }
            Mock Get-PnPListItem {
                @(
                    [PSCustomObject]@{
                        Id                       = 1
                        HasUniqueRoleAssignments = $true
                        FileSystemObjectType     = 'File'
                        FieldValues              = @{ 'FileRef' = '/sites/Finance/Invoices/Inv001.pdf' }
                    }
                )
            }

            $result = Get-SPCBrokenInheritance -SiteUrl 'https://contoso.sharepoint.com/sites/Finance'

            $result | Should -Not -BeNullOrEmpty
            $result.SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/Finance'
            $result.UniqueScopes | Should -Be 2
            $result.BrokenItems.Count | Should -Be 2
            $result.BrokenItems[0].Type | Should -Be 'Library'
            $result.BrokenItems[1].Type | Should -Be 'File/Item'
        }
    }

    Context 'Threshold and Boundary Handling' {
        It 'Should return 0 unique scopes when inheritance is fully intact across libraries' {
            Mock Test-SPCConnection { $true }
            Mock Connect-SPCSiteInternal { [PSCustomObject]@{} }
            Mock Get-PnPList {
                @(
                    [PSCustomObject]@{
                        Title                    = 'Shared Documents'
                        BaseType                 = 'DocumentLibrary'
                        HasUniqueRoleAssignments = $false
                        Hidden                   = $false
                        RootFolder               = [PSCustomObject]@{ ServerRelativeUrl = '/sites/Finance/Shared Documents' }
                    }
                )
            }
            Mock Get-PnPListItem { @() }

            $result = Get-SPCBrokenInheritance -SiteUrl 'https://contoso.sharepoint.com/sites/Finance'

            $result.UniqueScopes | Should -Be 0
            $result.BrokenItems.Count | Should -Be 0
        }
    }

    Context 'Connection Guard and Error Handling' {
        It 'Should throw ERR-001 when not connected' {
            Mock Test-SPCConnection { throw 'Not connected' }

            { Get-SPCBrokenInheritance -SiteUrl 'https://contoso.sharepoint.com/sites/Finance' } |
                Should -Throw -ExpectedMessage '*ERR-001*'
        }

        It 'AC-SCA-01 Should temporarily elevate SCA on Access Denied when -AddTempSiteCollectionAdmin is supplied' {
            Mock Test-SPCConnection { $true }
            $script:accessDenied = $true
            Mock Connect-SPCSiteInternal {
                return [PSCustomObject]@{ Url = 'https://contoso.sharepoint.com/sites/Finance' }
            }
            Mock Get-PnPList {
                if ($script:accessDenied) {
                    throw "403 Unauthorized: Access Denied"
                }
                return @(
                    [PSCustomObject]@{
                        Title                    = 'Restricted Docs'
                        BaseType                 = 'DocumentLibrary'
                        HasUniqueRoleAssignments = $true
                        Hidden                   = $false
                        RootFolder               = [PSCustomObject]@{ ServerRelativeUrl = '/sites/Finance/Restricted' }
                    }
                )
            }
            Mock Get-PnPListItem { @() }
            Mock Set-PnPTenantSite {
                $script:accessDenied = $false
            }
            Mock Remove-PnPSiteCollectionAdmin {}
            Mock Start-Sleep {}

            $result = Get-SPCBrokenInheritance -SiteUrl 'https://contoso.sharepoint.com/sites/Finance' -AddTempSiteCollectionAdmin
            $result.UniqueScopes | Should -Be 1
            Should -Invoke -CommandName Set-PnPTenantSite -Times 1 -Exactly
            Should -Invoke -CommandName Remove-PnPSiteCollectionAdmin -Times 1 -Exactly
        }
    }
}
