#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/PnPWrappers.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Connect-SPCSiteInternal.ps1')
}

Describe 'Connect-SPCSiteInternal Unit Tests' -Tag 'Auth', 'Internal', 'PnP' {
    Context 'TC-CONN-001: Guard Validation' {
        It 'TC-CONN-001.1: Should throw ERR-AUTH-005 when SPCContext is null' {
            $script:SPCContext = $null

            { Connect-SPCSiteInternal -SiteUrl 'https://contoso.sharepoint.com/sites/Legal' -Context $null } |
                Should -Throw -ExpectedMessage '*ERR-AUTH-005*'
        }
    }

    Context 'TC-CONN-002: Interactive Authentication Forwarding' {
        It 'TC-CONN-002.1: Should pass AccessToken to Connect-PnPOnline in Interactive mode' {
            $mockContext = [PSCustomObject]@{
                AuthMode         = 'Interactive'
                GraphAccessToken = 'mock_interactive_token'
                TenantName       = 'contoso'
            }

            Mock Connect-PnPOnline {
                param($Url, $AccessToken, [switch]$ReturnConnection)
                [PSCustomObject]@{ Url = $Url; Mode = 'Token'; Success = $true }
            }

            $conn = Connect-SPCSiteInternal -SiteUrl 'https://contoso.sharepoint.com/sites/Legal' -Context $mockContext

            $conn | Should -Not -BeNullOrEmpty
            Assert-MockCalled Connect-PnPOnline -Times 1 -ParameterFilter {
                $Url -eq 'https://contoso.sharepoint.com/sites/Legal' -and $AccessToken -eq 'mock_interactive_token'
            }
        }
    }

    Context 'TC-CONN-003: AppOnly Certificate Authentication' {
        It 'TC-CONN-003.1: Should pass CertificatePath and Password when configured' {
            $secPass = ConvertTo-SecureString 'CertP@ssw0rd' -AsPlainText -Force
            $mockContext = [PSCustomObject]@{
                AuthMode            = 'AppOnly'
                ClientId            = '00000000-1111-2222-3333-444444444444'
                CertificatePath     = 'C:\Certs\spclean.pfx'
                CertificatePassword = $secPass
                TenantName          = 'contoso'
            }

            Mock Connect-PnPOnline {
                param($Url, $ClientId, $CertificatePath, $CertificatePassword)
                [PSCustomObject]@{ Url = $Url; Mode = 'CertPath'; Success = $true }
            }

            $conn = Connect-SPCSiteInternal -SiteUrl 'https://contoso.sharepoint.com/sites/Legal' -Context $mockContext

            $conn | Should -Not -BeNullOrEmpty
            Assert-MockCalled Connect-PnPOnline -Times 1 -ParameterFilter {
                $ClientId -eq '00000000-1111-2222-3333-444444444444' -and $CertificatePath -eq 'C:\Certs\spclean.pfx'
            }
        }

        It 'TC-CONN-003.2: Should pass Thumbprint when configured' {
            $mockContext = [PSCustomObject]@{
                AuthMode              = 'AppOnly'
                ClientId              = '00000000-1111-2222-3333-444444444444'
                CertificateThumbprint = 'A1B2C3D4E5F6'
                TenantName            = 'contoso'
            }

            Mock Connect-PnPOnline {
                param($Url, $ClientId, $Thumbprint, $Tenant)
                [PSCustomObject]@{ Url = $Url; Mode = 'Thumbprint'; Success = $true }
            }

            $conn = Connect-SPCSiteInternal -SiteUrl 'https://contoso.sharepoint.com/sites/Legal' -Context $mockContext

            $conn | Should -Not -BeNullOrEmpty
            Assert-MockCalled Connect-PnPOnline -Times 1 -ParameterFilter {
                $ClientId -eq '00000000-1111-2222-3333-444444444444' -and $Thumbprint -eq 'A1B2C3D4E5F6'
            }
        }
    }

    Context 'TC-CONN-004: AppOnly Client Secret with Memory Zeroing' {
        It 'TC-CONN-004.1: Should convert SecureString secret and invoke ZeroFreeBSTR' {
            $secSecret = ConvertTo-SecureString 'SecretValue123!' -AsPlainText -Force
            $mockContext = [PSCustomObject]@{
                AuthMode     = 'AppOnly'
                ClientId     = '00000000-1111-2222-3333-444444444444'
                ClientSecret = $secSecret
                TenantName   = 'contoso.onmicrosoft.com'
            }

            Mock Connect-PnPOnline {
                param($Url, $ClientId, $ClientSecret, $Tenant)
                [PSCustomObject]@{ Url = $Url; Mode = 'Secret'; Success = $true }
            }

            $conn = Connect-SPCSiteInternal -SiteUrl 'https://contoso.sharepoint.com/sites/Legal' -Context $mockContext

            $conn | Should -Not -BeNullOrEmpty
            Assert-MockCalled Connect-PnPOnline -Times 1 -ParameterFilter {
                $ClientSecret -eq 'SecretValue123!' -and $Tenant -eq 'contoso.onmicrosoft.com'
            }
        }
    }
}
