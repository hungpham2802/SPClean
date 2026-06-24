#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Auth/Connect-SPCTenant.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Auth/Disconnect-SPCTenant.ps1')

    # Reset connection context before each file run
    $script:SPCContext = $null
}

Describe 'Connect-SPCTenant' {

    BeforeEach {
        $script:SPCContext = $null
        Mock Connect-PnPOnline  { return [PSCustomObject]@{ Url = 'https://fake-admin.sharepoint.com' } }
        Mock Connect-MgGraph    {}
        Mock Get-PnPGraphAccessToken { return 'fake-graph-token' }
    }

    Context 'ERR-AUTH-001 — invalid TenantName' {
        It 'AC-11: throws ERR-AUTH-001 for empty string' {
            { Connect-SPCTenant -TenantName '' } | Should -Throw '*ERR-AUTH-001*'
        }

        It 'AC-11: throws ERR-AUTH-001 for name with spaces' {
            { Connect-SPCTenant -TenantName 'my tenant' } | Should -Throw '*ERR-AUTH-001*'
        }

        It 'AC-11: throws ERR-AUTH-001 for name starting with hyphen' {
            { Connect-SPCTenant -TenantName '-badname' } | Should -Throw '*ERR-AUTH-001*'
        }
    }

    Context 'ERR-AUTH-003 — AppOnly missing parameters' {
        It 'AC-11: throws ERR-AUTH-003 for AppOnly with no ClientId' {
            { Connect-SPCTenant -TenantName 'contoso' -AuthMethod AppOnly } |
                Should -Throw '*ERR-AUTH-003*'
        }

        It 'AC-11: throws ERR-AUTH-003 for AppOnly with ClientId but no cert or secret' {
            { Connect-SPCTenant -TenantName 'contoso' -AuthMethod AppOnly -ClientId 'abc' } |
                Should -Throw '*ERR-AUTH-003*'
        }
    }

    Context 'Successful Interactive connection' {
        It 'AC-11: returns SPC.ConnectionInfo object' {
            $result = Connect-SPCTenant -TenantName 'contoso'
            $result.PSObject.TypeNames | Should -Contain 'SPC.ConnectionInfo'
        }

        It 'AC-11: output contains TenantName and AuthMethod' {
            $result = Connect-SPCTenant -TenantName 'contoso'
            $result.TenantName  | Should -Be 'contoso'
            $result.AuthMethod  | Should -Be 'Interactive'
        }

        It 'AC-11: populates $script:SPCContext after connection' {
            Connect-SPCTenant -TenantName 'contoso' | Out-Null
            $script:SPCContext            | Should -Not -BeNullOrEmpty
            $script:SPCContext.TenantName | Should -Be 'contoso'
        }

        It 'AC-11: calls Connect-PnPOnline once for Interactive auth' {
            Connect-SPCTenant -TenantName 'contoso' | Out-Null
            Should -Invoke Connect-PnPOnline -Times 1 -Exactly
        }
    }

    Context 'Successful AppOnly (certificate) connection' {
        It 'AC-11: connects without throwing when cert params provided' {
            $fakePwd = ConvertTo-SecureString 'fake' -AsPlainText -Force
            { Connect-SPCTenant -TenantName 'contoso' -AuthMethod AppOnly `
                  -ClientId 'abc' -CertificatePath 'C:\fake.pfx' `
                  -CertificatePassword $fakePwd } | Should -Not -Throw
        }

        It 'AC-11: stores _CertificatePath in context' {
            $fakePwd = ConvertTo-SecureString 'fake' -AsPlainText -Force
            Connect-SPCTenant -TenantName 'contoso' -AuthMethod AppOnly `
                -ClientId 'abc' -CertificatePath 'C:\fake.pfx' `
                -CertificatePassword $fakePwd | Out-Null
            $script:SPCContext._CertificatePath | Should -Be 'C:\fake.pfx'
        }
    }

    Context 'Test-SPCConnection guard' {
        It 'AC-11: Test-SPCConnection throws when context is null' {
            $script:SPCContext = $null
            { Test-SPCConnection } | Should -Throw '*No active SPClean connection*'
        }

        It 'AC-11: Test-SPCConnection does not throw when context is set' {
            $script:SPCContext = [PSCustomObject]@{ TenantName = 'contoso' }
            { Test-SPCConnection } | Should -Not -Throw
        }
    }

    Context 'AC-12: no credentials in output stream' {
        It 'AC-12: verbose output does not contain credential strings' {
            $out = Connect-SPCTenant -TenantName 'contoso' -Verbose 4>&1 5>&1
            $out | ForEach-Object { [string]$_ } |
                Should -Not -Match 'password|secret|token|pfx|credential'
        }
    }
}
