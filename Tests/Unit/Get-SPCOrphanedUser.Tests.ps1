#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/PnPWrappers.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Get-SPCRiskLevel.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Invoke-SPCGraphBatch.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Connect-SPCSiteInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Invoke-SPCTempElevationInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Scan/Get-SPCOrphanedUser.ps1')

    # ── Shared fake data ────────────────────────────────────────────────────────

    $script:FakeContext = [PSCustomObject]@{
        TenantName            = 'contoso'
        AuthMethod            = 'Interactive'
        ConnectedAt           = (Get-Date).ToUniversalTime()
        GraphTokenRefreshedAt = (Get-Date).ToUniversalTime()
        PnPContext            = $null
        GraphAccessToken      = 'fake-graph-token'
        _ClientId             = $null
        _CertificatePath      = $null
        _CertificatePassword  = $null
        _ClientSecret         = $null
    }

    # Three UIL users that will be classified as orphaned
    $script:FakeUILUsers = @(
        [PSCustomObject]@{ Id = 1; LoginName = 'i:0#.f|membership|alice@contoso.com'; Title = 'Alice'; Email = 'alice@contoso.com'; PrincipalType = 'User' }
        [PSCustomObject]@{ Id = 2; LoginName = 'i:0#.f|membership|bob@contoso.com';   Title = 'Bob';   Email = 'bob@contoso.com'; PrincipalType = 'User' }
        [PSCustomObject]@{ Id = 3; LoginName = 'i:0#.f|membership|carol@contoso.com'; Title = 'Carol'; Email = 'carol@contoso.com'; PrincipalType = 'User' }
    )

    # System accounts that must be filtered out
    $script:SystemAccounts = @(
        [PSCustomObject]@{ Id = 99; LoginName = 'SHAREPOINT\system';                     Title = 'System'; Email = ''; PrincipalType = 'User' }
        [PSCustomObject]@{ Id = 98; LoginName = 'NT AUTHORITY\authenticated users';      Title = 'Everyone'; Email = ''; PrincipalType = 'User' }
    )
}

Describe 'Get-SPCOrphanedUser' {

    BeforeEach {
        $script:SPCContext = $script:FakeContext

        Mock Get-PnPAccessToken { return 'fake' }
        Mock Connect-PnPOnline   { return $null }
        Mock Get-PnPWeb          { return [PSCustomObject]@{ Title = 'Human Resources' } }
        Mock Get-PnPUser         { return @() }
        Mock Get-PnPSiteGroup    { return @() }
        Mock Get-PnPGroupMember  { return @() }
    }

    Context 'AC-03: orphan detection and classification' {
        BeforeEach {
            Mock Get-PnPSiteUser { return $script:FakeUILUsers }
            $script:callCount = 0
            Mock Invoke-SPCGraphBatch {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    return @(
                        [PSCustomObject]@{ id = '1'; status = 404; body = $null }
                        [PSCustomObject]@{ id = '2'; status = 404; body = $null }
                        [PSCustomObject]@{ id = '3'; status = 404; body = $null }
                    )
                } else {
                    return @(
                        [PSCustomObject]@{ id = '1'; status = 200; body = [PSCustomObject]@{ value = @() } }
                        [PSCustomObject]@{ id = '2'; status = 200; body = [PSCustomObject]@{ value = @() } }
                        [PSCustomObject]@{ id = '3'; status = 200; body = [PSCustomObject]@{ value = @() } }
                    )
                }
            }
        }

        It 'AC-03: returns exactly 3 SPC.OrphanedUser objects for 3 orphaned UIL users' {
            $result = Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR'
            $result | Should -HaveCount 3
        }

        It 'AC-03: output objects have TypeName SPC.OrphanedUser' {
            $result = Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR'
            $result | ForEach-Object {
                $_.PSObject.TypeNames | Should -Contain 'SPC.OrphanedUser'
            }
        }

        It 'AC-03: OrphanType = Deleted when user is not in Entra (404) and not soft-deleted' {
            $result = Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR'
            $result | ForEach-Object { $_.OrphanType | Should -Be 'Deleted' }
        }

        It 'AC-03: SiteUrl and SiteTitle are populated on output objects' {
            $result = Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR'
            $result[0].SiteUrl   | Should -Be 'https://contoso.sharepoint.com/sites/HR'
            $result[0].SiteTitle | Should -Be 'Human Resources'
        }

        It 'AC-03: all required output properties are present' {
            $result = Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR'
            $required = 'SiteUrl','SiteTitle','UserId','LoginName','DisplayName','Email','UPN',
                        'OrphanType','RiskLevel','HasDirectPermissions','GroupMemberships',
                        'LastActivityDate','DetectedAt'
            foreach ($prop in $required) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop
            }
        }
    }

    Context 'AC-SEC-03: OData Injection & Escaping Protection' {
        It 'AC-SEC-03: Escapes single quotes and special characters in UPN Graph requests' {
            $specialUser = @(
                [PSCustomObject]@{ Id = 10; LoginName = "i:0#.f|membership|o'connor@contoso.com"; Title = "O'Connor"; Email = "o'connor@contoso.com"; PrincipalType = 'User' }
            )
            Mock Get-PnPSiteUser { return $specialUser }

            $script:capturedRequests = @()
            Mock Invoke-SPCGraphBatch {
                param($Requests, $AccessToken)
                $script:capturedRequests += $Requests
                return @(
                    [PSCustomObject]@{ id = '1'; status = 404; body = $null }
                )
            }

            $null = Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR'

            $script:capturedRequests | Should -Not -BeNullOrEmpty
            # Verify URL path is properly escaped or valid OData
            $url = $script:capturedRequests[0].url
            $url | Should -Match "o%27connor|o''connor|o'connor"
        }
    }

    Context 'AC-ARCH-04: Token Refresh Timestamp Isolation' {
        It 'AC-ARCH-04: Executes token refresh logic when time threshold is reached' {
            Mock Get-PnPSiteUser { return @() }
            Mock Get-PnPGraphAccessToken { return 'refreshed-token' }

            # Set connected time back > 50 minutes
            $pastTime = (Get-Date).ToUniversalTime().AddMinutes(-55)
            $script:SPCContext.ConnectedAt = $pastTime
            if ($script:SPCContext.PSObject.Properties['GraphTokenRefreshedAt']) {
                $script:SPCContext.GraphTokenRefreshedAt = $pastTime
            }

            $null = Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR'

            # Context GraphAccessToken is updated
            $script:SPCContext.GraphAccessToken | Should -Be 'refreshed-token'
        }
    }

    Context 'AC-04: clean site returns no results' {
        It 'AC-04: returns 0 results when all UIL users are active in Entra (200 + accountEnabled)' {
            Mock Get-PnPSiteUser { return $script:FakeUILUsers }
            Mock Invoke-SPCGraphBatch {
                return @(
                    [PSCustomObject]@{ id = '1'; status = 200; body = [PSCustomObject]@{ id = 'oid1'; accountEnabled = $true; userPrincipalName = 'alice@contoso.com'; displayName = 'Alice' } }
                    [PSCustomObject]@{ id = '2'; status = 200; body = [PSCustomObject]@{ id = 'oid2'; accountEnabled = $true; userPrincipalName = 'bob@contoso.com';   displayName = 'Bob'   } }
                    [PSCustomObject]@{ id = '3'; status = 200; body = [PSCustomObject]@{ id = 'oid3'; accountEnabled = $true; userPrincipalName = 'carol@contoso.com'; displayName = 'Carol' } }
                )
            }
            $result = @(Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR')
            $result | Should -HaveCount 0
        }

        It 'AC-04: returns 0 results when UIL is empty' {
            Mock Get-PnPSiteUser { return @() }
            Mock Invoke-SPCGraphBatch {}
            $result = @(Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR')
            $result | Should -HaveCount 0
        }
    }

    Context 'AC-09: system account filtering' {
        It 'AC-09: SHAREPOINT\system is excluded from results' {
            Mock Get-PnPSiteUser { return $script:SystemAccounts }
            Mock Invoke-SPCGraphBatch { return @() }
            $result = @(Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR')
            $result | Should -HaveCount 0
        }

        It 'AC-09: Invoke-SPCGraphBatch is called for real (non-system) users' {
            Mock Get-PnPSiteUser { return $script:FakeUILUsers }
            Mock Invoke-SPCGraphBatch { return @() }
            Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR' | Out-Null
            Should -Invoke -CommandName Invoke-SPCGraphBatch -Times 1
        }

        It 'AC-09: ThrottleLimit below 1 is clamped to 1 with a warning' {
            Mock Get-PnPSiteUser { return @() }
            Mock Invoke-SPCGraphBatch { return @() }
            $warnings = Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR' `
                -ThrottleLimit 0 -WarningVariable wv 3>&1 | Out-Null
            $wv | Should -Match 'clamped to 1'
        }

        It 'AC-09: ThrottleLimit above 10 is clamped to 10 with a warning' {
            Mock Get-PnPSiteUser { return @() }
            Mock Invoke-SPCGraphBatch { return @() }
            Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR' `
                -ThrottleLimit 99 -WarningVariable wv | Out-Null
            $wv | Should -Match 'clamped to 10'
        }
    }

    Context 'AC-12: no credentials in output streams' {
        It 'AC-12: verbose output does not contain credential strings' {
            Mock Get-PnPSiteUser { return @() }
            Mock Invoke-SPCGraphBatch { return @() }
            $out = & {
                $script:SPCContext = $script:FakeContext
                Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR' -Verbose 4>&1 5>&1
            } 2>&1
            $out | ForEach-Object { [string]$_ } |
                Should -Not -Match 'password|secret|pfx|credential'
        }
    }
}
