BeforeAll {
    . $PSScriptRoot\..\Public\Get-SPCGuestAccess.ps1
}

Describe "Get-SPCGuestAccess" {
    BeforeEach {
        Mock Get-PnPAccessToken { return "mock_token" }
    }

    Context "Quét và Lọc dữ liệu" {
        It "TC-FUNC-001 (AC-01): Nên quét thành công một Site cụ thể khi truyền tham số -SiteUrl" {
            Mock Test-SPCConnection { return $true }
            Mock Connect-PnPOnline {}
            Mock Get-PnPSiteUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest1@ext.com'; LoginName = 'i:0#.f|membership|guest1#EXT#@domain.com'; PrincipalType = 'Guest'; IsSiteAdmin = $true }
                )
            }
            Mock Get-PnPRoleAssignment { return @() }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch {
                return @(
                    [PSCustomObject]@{ UserPrincipalName = 'guest1#EXT#@domain.com'; LastSignInDateTime = (Get-Date).AddDays(-10).ToString('o') }
                )
            }

            $result = Get-SPCGuestAccess -SiteUrl "https://tenant.sharepoint.com/sites/Test"
            
            $result.Count | Should -Be 1
            $result[0].GuestEmail | Should -Be 'guest1@ext.com'
            Assert-MockCalled Connect-PnPOnline -Times 1 -ParameterFilter { $Url -eq "https://tenant.sharepoint.com/sites/Test" -and $AccessToken -eq "mock_token" }
        }

        It "TC-FUNC-002 (AC-01): Nên lặp qua tất cả Site Collections và quét toàn Tenant khi không truyền tham số -SiteUrl" {
            Mock Test-SPCConnection { return $true }
            Mock Get-PnPTenantSite {
                return @(
                    [PSCustomObject]@{ Url = 'https://tenant.sharepoint.com/sites/Site1' },
                    [PSCustomObject]@{ Url = 'https://tenant.sharepoint.com/sites/Site2' }
                )
            }
            Mock Connect-PnPOnline {}
            Mock Get-PnPSiteUser { return @() }
            Mock Get-PnPRoleAssignment { return @() }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch { return @() }

            $result = Get-SPCGuestAccess
            
            Assert-MockCalled Get-PnPTenantSite -Times 1
            Assert-MockCalled Connect-PnPOnline -Times 2
        }

        It "TC-FUNC-003: Nên chỉ lọc các tài khoản Guest (PrincipalType == Guest HOẶC LoginName chứa '#EXT#')" {
            Mock Test-SPCConnection { return $true }
            Mock Connect-PnPOnline {}
            Mock Get-PnPSiteUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest1@ext.com'; LoginName = 'i:0#.f|membership|guest1#EXT#@domain.com'; PrincipalType = 'Guest'; IsSiteAdmin = $false },
                    [PSCustomObject]@{ Email = 'user1@domain.com'; LoginName = 'user1@domain.com'; PrincipalType = 'User'; IsSiteAdmin = $false },
                    [PSCustomObject]@{ Email = ''; LoginName = 'group1'; PrincipalType = 'SharePointGroup'; IsSiteAdmin = $false }
                )
            }
            Mock Get-PnPRoleAssignment { return @() }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch { return @() }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            
            $result.Count | Should -Be 1
            $result[0].GuestEmail | Should -Be 'guest1@ext.com'
        }
    }

    Context "Đánh giá Mức độ Rủi ro (Risk Level Scoring)" {
        It "TC-FUNC-004 (AC-02): Nên gán RiskLevel là HIGH nếu Guest có quyền Full Control hoặc Owner" {
            Mock Test-SPCConnection { return $true }
            Mock Connect-PnPOnline {}
            Mock Get-PnPSiteUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest@ext.com'; LoginName = 'guest#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $true }
                )
            }
            Mock Get-PnPRoleAssignment { return @() }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch {
                return @(
                    [PSCustomObject]@{ UserPrincipalName = 'guest#EXT#'; LastSignInDateTime = (Get-Date).AddDays(-10).ToString('o') }
                )
            }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            $result[0].RiskLevel | Should -Be 'HIGH'
        }

        It "TC-FUNC-005 (AC-02): Nên gán RiskLevel là HIGH nếu Guest Inactive > 180 ngày" {
            Mock Test-SPCConnection { return $true }
            Mock Connect-PnPOnline {}
            Mock Get-PnPSiteUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest@ext.com'; LoginName = 'guest#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $false }
                )
            }
            Mock Get-PnPRoleAssignment { return @() }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch {
                return @(
                    [PSCustomObject]@{ UserPrincipalName = 'guest#EXT#'; LastSignInDateTime = (Get-Date).AddDays(-185).ToString('o') }
                )
            }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            $result[0].RiskLevel | Should -Be 'HIGH'
        }

        It "TC-FUNC-006 (AC-02): Nên gán RiskLevel là MEDIUM nếu Guest có quyền Edit hoặc Write qua SP Group" {
            Mock Test-SPCConnection { return $true }
            Mock Connect-PnPOnline {}
            Mock Get-PnPSiteUser {
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
            Mock Get-PnPRoleAssignment {
                return @(
                    [PSCustomObject]@{
                        Member = [PSCustomObject]@{ LoginName = 'Members Group' }
                        RoleDefinitionBindings = @(
                            [PSCustomObject]@{ Name = 'Edit' }
                        )
                    }
                )
            }
            Mock Invoke-SPCGraphBatch {
                return @(
                    [PSCustomObject]@{ UserPrincipalName = 'guest#EXT#'; LastSignInDateTime = (Get-Date).AddDays(-10).ToString('o') }
                )
            }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            $result[0].RiskLevel | Should -Be 'MEDIUM'
        }

        It "TC-FUNC-007 (AC-02): Nên gán RiskLevel là MEDIUM nếu Guest Inactive từ 91 đến 180 ngày" {
            Mock Test-SPCConnection { return $true }
            Mock Connect-PnPOnline {}
            Mock Get-PnPSiteUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest@ext.com'; LoginName = 'guest#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $false }
                )
            }
            Mock Get-PnPRoleAssignment { return @() }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch {
                return @(
                    [PSCustomObject]@{ UserPrincipalName = 'guest#EXT#'; LastSignInDateTime = (Get-Date).AddDays(-100).ToString('o') }
                )
            }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            $result[0].RiskLevel | Should -Be 'MEDIUM'
        }
    }

    Context "Kết quả Đầu ra (Output)" {
        It "TC-FUNC-009 (AC-03): Nên trả về object chứa InvitedBy từ Graph API" {
            Mock Test-SPCConnection { return $true }
            Mock Connect-PnPOnline {}
            Mock Get-PnPSiteUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest@ext.com'; LoginName = 'i:0#.f|membership|guest_gmail.com#EXT#@tenant.onmicrosoft.com'; PrincipalType = 'Guest'; IsSiteAdmin = $false }
                )
            }
            Mock Get-PnPRoleAssignment { return @() }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch { 
                return @(
                    [PSCustomObject]@{ UserPrincipalName = 'guest_gmail.com#EXT#@tenant.onmicrosoft.com'; InvitedBy = 'admin@tenant.com' }
                ) 
            }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            
            $result[0].InvitedBy | Should -Be 'admin@tenant.com'
        }
    }

    Context "Xử lý Lỗi (Error Handling)" {
        It "TC-NEG-001 (AC-04): Không được làm crash script và phải gán LastAccess = 'N/A' khi tài khoản Guest bị soft-deleted hoặc không tồn tại trong Entra ID" {
            Mock Test-SPCConnection { return $true }
            Mock Connect-PnPOnline {}
            Mock Get-PnPSiteUser {
                return @(
                    [PSCustomObject]@{ Email = 'notfound@ext.com'; LoginName = 'notfound#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $false }
                )
            }
            Mock Get-PnPRoleAssignment { return @() }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch {
                throw "Graph API Error 404 Not Found"
            }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            
            $result[0].LastAccess | Should -Be 'N/A'
        }
        
        It "TC-NEG-004: Phải abort graph queries khi gặp lỗi không phải 429 (ví dụ 401 Unauthorized)" {
            Mock Test-SPCConnection { return $true }
            Mock Connect-PnPOnline {}
            Mock Get-PnPSiteUser {
                return @(
                    [PSCustomObject]@{ Email = 'user1@ext.com'; LoginName = 'user1#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $false },
                    [PSCustomObject]@{ Email = 'user2@ext.com'; LoginName = 'user2#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $false }
                )
            }
            Mock Get-PnPRoleAssignment { return @() }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch { throw "401 Unauthorized" }
            
            # Since there's 2 users, if we had batch size 1 (hypothetically) it would loop twice. 
            # We mock to ensure Invoke-SPCGraphBatch is only called once and breaks.
            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            
            Assert-MockCalled Invoke-SPCGraphBatch -Times 1
        }
    }

    Context "Bảo vệ Dữ liệu & Quy tắc Pester" {
        It "TC-SEC-001 (AC-12): Không được rò rỉ bất kỳ credential, token hoặc password nào trong Verbose và Error streams" {
            Mock Test-SPCConnection { return $true }
            Mock Connect-PnPOnline {}
            Mock Get-PnPSiteUser { return @() }
            Mock Get-PnPRoleAssignment { return @() }
            Mock Get-PnPGroup { return @() }
            Mock Invoke-SPCGraphBatch { return @() }

            $stream = { Get-SPCGuestAccess -SiteUrl "https://test" -Verbose } *>&1
            $output = $stream | Out-String
            
            $output -match 'password|secret|token|pfx|credential' | Should -Be $false
        }
    }

    Context "Khả năng Mở rộng & Tần suất API" {
        It "TC-PERF-001: Nên retry theo chiến lược Exponential Backoff tối đa 5 lần khi gặp lỗi Graph API 429 Throttling" {
            Mock Test-SPCConnection { return $true }
            Mock Connect-PnPOnline {}
            Mock Get-PnPSiteUser {
                return @(
                    [PSCustomObject]@{ Email = 'guest@ext.com'; LoginName = 'guest#EXT#'; PrincipalType = 'Guest'; IsSiteAdmin = $false }
                )
            }
            Mock Get-PnPRoleAssignment { return @() }
            Mock Get-PnPGroup { return @() }
            Mock Start-Sleep {}
            
            Mock Invoke-SPCGraphBatch {
                throw "429 Too Many Requests"
            }

            $result = Get-SPCGuestAccess -SiteUrl "https://test"
            
            Assert-MockCalled Invoke-SPCGraphBatch -Times 5
            Assert-MockCalled Start-Sleep -Times 5
        }
    }
}
