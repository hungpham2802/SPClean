#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
BeforeAll {
        $script:sut = "$PSScriptRoot\..\..\Public\Scan\Get-SPCGuestAccess.ps1"
    . $PSScriptRoot\..\..\Public\Scan\Get-SPCGuestAccess.ps1
    function Test-SPCConnection {}
    function Connect-PnPOnline {}
    function Get-PnPUser {}
    function Invoke-PnPSPRestMethod {}
    function Get-PnPGroup {}
    function Invoke-SPCGraphBatch {}
    function Get-PnPAccessToken {}
    function Get-PnPTenantSite {}
    function Start-Sleep {}
}

Describe "Get-SPCGuestAccess" {
    BeforeEach {
        $script:SPCContext = [PSCustomObject]@{
            TenantName = 'tenant'
            AuthMethod = 'Interactive'
            PnPContext = $null
            GraphAccessToken = 'mock_token'
        }
        Mock Get-PnPAccessToken { return "mock_token" }
    }

    Context "Scanning and Filtering" {
        It "TC-FUNC-001 (AC-01): Should successfully scan a specific Site when -SiteUrl is provided" {
            Mock Test-SPCConnection {}
            Mock Get-PnPAccessToken { return "mock_token" }
                       Mock Connect-PnPOnline {}
            Mock Get-PnPUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest1@ext.com'; LoginName = 'i:0#.f|membership|guest1#EXT#@domain.com'; PrincipalType = 'Guest'; IsSiteAdmin = $true }
                )
            }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch {
                  return @(
                      [PSCustomObject]@{
                          id = 'guest1#EXT#@domain.com'
                          status = 200
                          body = [PSCustomObject]@{
                              value = @(
                                  [PSCustomObject]@{
                                      userPrincipalName = 'guest1#EXT#@domain.com'
                                      signInActivity = [PSCustomObject]@{ lastSignInDateTime = (Get-Date).AddDays(-10).ToString('o') }
                                  }
                              )
                          }
                      }
                  )
              }

            $result = Get-SPCGuestAccess -SiteUrl "https://tenant.sharepoint.com/sites/Test"
            
            $result.Count | Should -Be 1
            $result[0].GuestEmail | Should -Be 'guest1@ext.com'
            Assert-MockCalled Connect-PnPOnline -Times 1
        }

        It "TC-FUNC-002 (AC-01): Should iterate through all Site Collections and scan entire Tenant when -SiteUrl is not provided" {
            Mock Test-SPCConnection {}
            Mock Get-PnPTenantSite {
                return @(
                    [PSCustomObject]@{ Url = 'https://tenant.sharepoint.com/sites/Site1' },
                    [PSCustomObject]@{ Url = 'https://tenant.sharepoint.com/sites/Site2' }
                )
            }
            Mock Get-PnPAccessToken { return "mock_token" }
                       Mock Connect-PnPOnline {}
            Mock Get-PnPUser { return @() }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch { return @() }

            $result = Get-SPCGuestAccess
            
            Assert-MockCalled Get-PnPTenantSite -Times 1
            Assert-MockCalled Connect-PnPOnline -Times 2
        }

        It "TC-FUNC-003: Should only filter Guest accounts (PrincipalType == Guest OR LoginName contains '#EXT#')" {
            Mock Test-SPCConnection {}
            Mock Get-PnPAccessToken { return "mock_token" }
                       Mock Connect-PnPOnline {}
            Mock Get-PnPUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest1@ext.com'; LoginName = 'i:0#.f|membership|guest1#EXT#@domain.com'; PrincipalType = 'Guest'; IsSiteAdmin = $false },
                    [PSCustomObject]@{ Email = 'user1@domain.com'; LoginName = 'user1@domain.com'; PrincipalType = 'User'; IsSiteAdmin = $false },
                    [PSCustomObject]@{ Email = ''; LoginName = 'group1'; PrincipalType = 'SharePointGroup'; IsSiteAdmin = $false }
                )
            }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch { return @() }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            
            $result.Count | Should -Be 1
            $result[0].GuestEmail | Should -Be 'guest1@ext.com'
        }
    }

    Context "Risk Level Scoring" {
        It "TC-FUNC-004 (AC-02): Should assign RiskLevel HIGH if Guest has Full Control or Owner permissions" {
            Mock Test-SPCConnection {}
            Mock Get-PnPAccessToken { return "mock_token" }
                       Mock Connect-PnPOnline {}
            Mock Get-PnPUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest@ext.com'; LoginName = 'guest#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $true }
                )
            }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch {
                  return @(
                      [PSCustomObject]@{
                          id = 'guest#EXT#'
                          status = 200
                          body = [PSCustomObject]@{
                              value = @(
                                  [PSCustomObject]@{
                                      userPrincipalName = 'guest#EXT#'
                                      signInActivity = [PSCustomObject]@{ lastSignInDateTime = (Get-Date).AddDays(-10).ToString('o') }
                                  }
                              )
                          }
                      }
                  )
              }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            $result[0].RiskLevel | Should -Be 'HIGH'
        }

        It "TC-FUNC-005 (AC-02): Should assign RiskLevel HIGH if Guest is Inactive > 180 days" {
            Mock Test-SPCConnection {}
            Mock Get-PnPAccessToken { return "mock_token" }
                       Mock Connect-PnPOnline {}
            Mock Get-PnPUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest@ext.com'; LoginName = 'guest#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $false }
                )
            }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch {
                  return @(
                      [PSCustomObject]@{
                          id = 'guest#EXT#'
                          status = 200
                          body = [PSCustomObject]@{
                              value = @(
                                  [PSCustomObject]@{
                                      userPrincipalName = 'guest#EXT#'
                                      signInActivity = [PSCustomObject]@{ lastSignInDateTime = (Get-Date).AddDays(-185).ToString('o') }
                                  }
                              )
                          }
                      }
                  )
              }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            $result[0].RiskLevel | Should -Be 'HIGH'
        }

        It "TC-FUNC-006 (AC-02): Should assign RiskLevel MEDIUM if Guest has Edit or Write permissions via SP Group" {
            Mock Test-SPCConnection {}
            Mock Get-PnPAccessToken { return "mock_token" }
                       Mock Connect-PnPOnline {}
            Mock Get-PnPUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest@ext.com'; LoginName = 'guest#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $false }
                )
            }
            Mock Get-PnPGroup {
                return @(
                    [PSCustomObject]@{
                        LoginName = 'Members Group'
                        Users = @( [PSCustomObject]@{ LoginName = 'guest#EXT#' } )
                    }
                )
            }
            Mock Invoke-PnPSPRestMethod {
                  return [PSCustomObject]@{
                      value = @(
                          [PSCustomObject]@{
                              Member = [PSCustomObject]@{ LoginName = 'Members Group' }
                              RoleDefinitionBindings = @(
                                  [PSCustomObject]@{ Name = 'Edit' }
                              )
                          }
                      )
                  }
              }
            Mock Invoke-SPCGraphBatch {
                  return @(
                      [PSCustomObject]@{
                          id = 'guest#EXT#'
                          status = 200
                          body = [PSCustomObject]@{
                              value = @(
                                  [PSCustomObject]@{
                                      userPrincipalName = 'guest#EXT#'
                                      signInActivity = [PSCustomObject]@{ lastSignInDateTime = (Get-Date).AddDays(-10).ToString('o') }
                                  }
                              )
                          }
                      }
                  )
              }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            $result[0].RiskLevel | Should -Be 'MEDIUM'
        }

        It "TC-FUNC-007 (AC-02): Should assign RiskLevel MEDIUM if Guest is Inactive between 91 and 180 days" {
            Mock Test-SPCConnection {}
                        Mock Get-PnPAccessToken { return "mock_token" }
            Mock Connect-PnPOnline {}
            Mock Get-PnPUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest@ext.com'; LoginName = 'guest#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $false }
                )
            }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch {
                  return @(
                      [PSCustomObject]@{
                          id = 'guest#EXT#'
                          status = 200
                          body = [PSCustomObject]@{
                              value = @(
                                  [PSCustomObject]@{
                                      userPrincipalName = 'guest#EXT#'
                                      signInActivity = [PSCustomObject]@{ lastSignInDateTime = (Get-Date).AddDays(-100).ToString('o') }
                                  }
                              )
                          }
                      }
                  )
              }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            $result[0].RiskLevel | Should -Be 'MEDIUM'
        }
    }

    Context "Output Results" {
        It "TC-FUNC-009 (AC-03): Should return object containing InvitedBy from Graph API" {
            Mock Test-SPCConnection {}
                        Mock Get-PnPAccessToken { return "mock_token" }
            Mock Connect-PnPOnline {}
            Mock Get-PnPUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest@ext.com'; LoginName = 'i:0#.f|membership|guest_gmail.com#EXT#@tenant.onmicrosoft.com'; PrincipalType = 'Guest'; IsSiteAdmin = $false }
                )
            }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch {
                  return @(
                      [PSCustomObject]@{
                          id = 'guest_gmail.com#EXT#@tenant.onmicrosoft.com'
                          status = 200
                          body = [PSCustomObject]@{
                              value = @(
                                  [PSCustomObject]@{
                                      userPrincipalName = 'guest_gmail.com#EXT#@tenant.onmicrosoft.com'
                                      signInActivity = [PSCustomObject]@{ lastSignInDateTime = (Get-Date).AddDays(-10).ToString('o') }
                                      invitedBy = [PSCustomObject]@{ user = [PSCustomObject]@{ email = 'admin@tenant.com' } }
                                  }
                              )
                          }
                      }
                  )
              }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            
            $result[0].InvitedBy | Should -Be 'admin@tenant.com'
        }
    }

    Context "Error Handling" {
        It "TC-NEG-001 (AC-04): Should not crash script and must assign LastAccess = 'N/A' when Guest account is soft-deleted or does not exist in Entra ID" {
            Mock Test-SPCConnection {}
                        Mock Get-PnPAccessToken { return "mock_token" }
            Mock Connect-PnPOnline {}
            Mock Get-PnPUser {
                return @(
                    [PSCustomObject]@{ Email = 'notfound@ext.com'; LoginName = 'notfound#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $false }
                )
            }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch {
                throw "Graph API Error 404 Not Found"
            }

            $result = Get-SPCGuestAccess -SiteUrl "https://test" 2>$null
            
            $result[0].LastAccess | Should -Be 'N/A'
        }
        
        It "TC-NEG-004: Should abort graph queries on non-429 errors (e.g., 401 Unauthorized)" {
            Mock Test-SPCConnection {}
                        Mock Get-PnPAccessToken { return "MockToken" }
            Mock Connect-PnPOnline {}
            Mock Get-PnPUser {
                return @(
                    [PSCustomObject]@{ Email = 'user1@ext.com'; LoginName = 'user1#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $false },
                    [PSCustomObject]@{ Email = 'user2@ext.com'; LoginName = 'user2#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $false }
                )
            }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch { throw "401 Unauthorized" }
            
            # Since there's 2 users, if we had batch size 1 (hypothetically) it would loop twice. 
            # We mock to ensure Invoke-SPCGraphBatch is only called once and breaks.
            $result = Get-SPCGuestAccess -SiteUrl "https://test" 2>$null
            
            Assert-MockCalled Invoke-SPCGraphBatch -Times 1
        }
    }

    Context "Data Protection and Pester Rules" {
        It "TC-SEC-001 (AC-12): Should not leak any credential, token or password in Verbose and Error streams" {
            Mock Test-SPCConnection {}
                        Mock Get-PnPAccessToken { return "MockToken" }
            Mock Connect-PnPOnline {}
            Mock Get-PnPUser { return @() }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch { return @() }

            $stream = { Get-SPCGuestAccess -SiteUrl "https://test" -Verbose } *>&1
            $output = $stream | Out-String
            
            $output -match 'password|secret|token|pfx|credential' | Should -Be $false
        }
    }

    Context "Scalability and API Throttling" {
        It "TC-PERF-001: Should retry using Exponential Backoff up to 5 times when encountering Graph API 429 Throttling error" {
            Mock Test-SPCConnection {}
                        Mock Get-PnPAccessToken { return "MockToken" }
            Mock Connect-PnPOnline {}
            Mock Get-PnPUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest@ext.com'; LoginName = 'guest#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $false }
                )
            }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }
            Mock Get-PnPGroup { return @() }
            Mock Start-Sleep {}
            
            Mock Invoke-SPCGraphBatch {
                throw "429 Too Many Requests"
            }

            $result = Get-SPCGuestAccess -SiteUrl "https://test" 2>$null
            
            Assert-MockCalled Invoke-SPCGraphBatch -Times 5
            Assert-MockCalled Start-Sleep -Times 5
        }
    }
}
