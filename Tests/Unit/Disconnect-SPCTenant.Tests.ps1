#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $moduleRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    $publicDir  = Join-Path $moduleRoot 'Public'
    $privateDir = Join-Path $moduleRoot 'Private'

    . (Join-Path $privateDir 'Test-SPCConnection.ps1')
    . (Join-Path $publicDir 'Auth\Disconnect-SPCTenant.ps1')

    # Standardized mock module context schema
    $script:FakeConnectedContext = [PSCustomObject]@{
        TenantName             = 'contoso'
        AuthMethod             = 'Interactive'
        ConnectedAt            = (Get-Date).ToUniversalTime()
        GraphTokenRefreshedAt  = (Get-Date).ToUniversalTime()
        PnPContext             = [PSCustomObject]@{ Url = 'https://contoso-admin.sharepoint.com' }
        GraphAccessToken       = 'fake-token'
        _ClientId              = 'fake-client-id'
        _CertificateThumbprint = $null
        _CertificatePath       = $null
        _CertificatePassword   = $null
        _ClientSecret          = $null
    }
}

Describe 'Disconnect-SPCTenant' {

    BeforeEach {
        $script:SPCContext = $script:FakeConnectedContext
        $script:SPCLicenseCache = @{ Key = 'test-key'; Tier = 'PRO' }

        Mock Disconnect-PnPOnline {}
        Mock Disconnect-MgGraph   {}
    }

    Context 'AC-TEST-02 / AC-STD-05: Session Context Cleanup' {
        It 'AC-TEST-02: Clears $script:SPCContext and license cache on disconnect' {
            $script:SPCContext | Should -Not -BeNullOrEmpty
            Disconnect-SPCTenant
            $script:SPCContext | Should -BeNullOrEmpty
            $script:SPCLicenseCache | Should -BeNullOrEmpty
        }

        It 'AC-TEST-02: Calls Disconnect-PnPOnline and Disconnect-MgGraph' {
            Disconnect-SPCTenant
            Should -Invoke Disconnect-PnPOnline -Times 1 -Exactly
            Should -Invoke Disconnect-MgGraph -Times 1 -Exactly
        }
    }

    Context 'NFR-REL-02: Idempotency & Error Handling' {
        It 'NFR-REL-02: Safely executes when already disconnected ($script:SPCContext is null) without throwing' {
            $script:SPCContext = $null
            { Disconnect-SPCTenant } | Should -Not -Throw
            $script:SPCContext | Should -BeNullOrEmpty
        }

        It 'NFR-REL-02: Silently suppresses underlying Disconnect-PnPOnline exceptions' {
            Mock Disconnect-PnPOnline { throw 'PnP session fault' }
            { Disconnect-SPCTenant } | Should -Not -Throw
            $script:SPCContext | Should -BeNullOrEmpty
        }

        It 'NFR-REL-02: Silently suppresses underlying Disconnect-MgGraph exceptions' {
            Mock Disconnect-MgGraph { throw 'Graph disconnect fault' }
            { Disconnect-SPCTenant } | Should -Not -Throw
            $script:SPCContext | Should -BeNullOrEmpty
        }
    }

    Context 'ShouldProcess & WhatIf Support' {
        It 'AC-TEST-02: Respects -WhatIf by leaving session context intact and skipping disconnect calls' {
            Disconnect-SPCTenant -WhatIf
            $script:SPCContext | Should -Not -BeNullOrEmpty
            Should -Invoke Disconnect-PnPOnline -Times 0 -Exactly
            Should -Invoke Disconnect-MgGraph -Times 0 -Exactly
        }
    }

    Context 'Security & Stream Isolation' {
        It 'AC-SEC-02: Does not leak tokens or credentials into Verbose stream' {
            $script:verboseLog = @()
            Mock Write-Verbose {
                param($Message)
                $script:verboseLog += $Message
            }

            Disconnect-SPCTenant -Verbose

            $leak = $script:verboseLog | Where-Object { $_ -match 'password|secret|token|bearer|ey[A-Za-z0-9_-]+' }
            $leak | Should -BeNullOrEmpty
        }
    }
}
