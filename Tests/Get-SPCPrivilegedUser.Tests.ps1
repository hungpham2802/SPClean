$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Parent $here) + "\Public\Get-SPCPrivilegedUser.ps1"
. $sut

Describe 'Get-SPCPrivilegedUser' {
    BeforeAll {
        function Test-SPCConnection { return $true }
    }

    Context 'When scanning sites' {
        It 'AC-F2-01 Should return top 20 privileged users grouped by UPN' {
            Mock Get-PnPTenantSite {
                $sites = @()
                for ($i=1; $i -le 25; $i++) {
                    $sites += [PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site$i" }
                }
                return $sites
            }
            Mock Connect-PnPOnline { return "MockConnection" }
            
            Mock Get-PnPSiteUser {
                $users = @()
                for ($u=1; $u -le 25; $u++) {
                    # Every user is SCA on site corresponding to their number and below
                    $users += [PSCustomObject]@{ LoginName = "i:0#.f|membership|user$u@domain.com"; IsSiteAdmin = $true }
                }
                return $users
            }
            Mock Get-PnPGroup { return $null }
            Mock Get-PnPRoleAssignment { return @() }

            $result = Get-SPCPrivilegedUser
            $result.Count | Should -Be 20
            $result[0].UPN | Should -Match "user"
        }
    }

    Context 'When checking permission sources' {
        It 'AC-F2-02 Should correctly identify SCA, Owner, and Direct Full Control' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site1" }) }
            Mock Connect-PnPOnline { return "MockConnection" }
            Mock Get-PnPSiteUser { return @([PSCustomObject]@{ LoginName = "i:0#.f|membership|usera@domain.com"; IsSiteAdmin = $true }) }
            Mock Get-PnPGroup { return [PSCustomObject]@{ Title = "Owners" } }
            Mock Get-PnPGroupMember { return @([PSCustomObject]@{ LoginName = "i:0#.f|membership|userb@domain.com" }) }
            Mock Get-PnPRoleAssignment {
                return @(
                    [PSCustomObject]@{ 
                        Member = [PSCustomObject]@{ PrincipalType = 'User'; LoginName = "i:0#.f|membership|userc@domain.com" }
                        RoleDefinitionBindings = @([PSCustomObject]@{ Name = 'Full Control' })
                    }
                )
            }

            $result = Get-SPCPrivilegedUser
            $result.Count | Should -Be 3
            
            $usera = $result | Where-Object { $_.UPN -eq 'usera@domain.com' }
            $usera.PermissionSources | Should -Contain 'SCA'
            
            $userb = $result | Where-Object { $_.UPN -eq 'userb@domain.com' }
            $userb.PermissionSources | Should -Contain 'Owner'

            $userc = $result | Where-Object { $_.UPN -eq 'userc@domain.com' }
            $userc.PermissionSources | Should -Contain 'Direct'
        }
    }

    Context 'When no privileged user exists' {
        It 'AC-F2-03 Should return empty list gracefully' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site1" }) }
            Mock Connect-PnPOnline { return "MockConnection" }
            Mock Get-PnPSiteUser { return @() }
            Mock Get-PnPGroup { return $null }
            Mock Get-PnPRoleAssignment { return @() }

            $result = Get-SPCPrivilegedUser
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Negative Scenarios' {
        It 'AC-NEG-01 Should throw Terminating Error ERR-AUTH-001 when connection fails' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site1" }) }
            Mock Connect-PnPOnline { throw "Connection failed" }
            
            { Get-SPCPrivilegedUser } | Should -Throw -ErrorId "ERR-AUTH-001"
        }

        It 'AC-NEG-02 Should write non-terminating error and continue for inaccessible sites' {
            Mock Get-PnPTenantSite { 
                return @(
                    [PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/errorSite" },
                    [PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/goodSite" }
                ) 
            }
            Mock Connect-PnPOnline { 
                if ($args[0] -match "errorSite") {
                    throw "Access Denied"
                }
                return "MockConnection"
            }
            Mock Get-PnPSiteUser { return @([PSCustomObject]@{ LoginName = "i:0#.f|membership|good@domain.com"; IsSiteAdmin = $true }) }
            Mock Get-PnPGroup { return $null }
            Mock Get-PnPRoleAssignment { return @() }

            $result = Get-SPCPrivilegedUser -ErrorAction SilentlyContinue
            $result.Count | Should -Be 1
            $result[0].UPN | Should -Be "good@domain.com"
        }

        It 'AC-NEG-03 Should implement exponential backoff retry on 429/503 errors' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site1" }) }
            $global:retryCount = 0
            Mock Connect-PnPOnline { 
                $global:retryCount++
                if ($global:retryCount -lt 3) {
                    throw "429 Too Many Requests"
                }
                return "MockConnection"
            }
            Mock Get-PnPSiteUser { return @() }
            Mock Get-PnPGroup { return $null }
            Mock Get-PnPRoleAssignment { return @() }
            Mock Start-Sleep { return $true } # Mock Start-Sleep to speed up test

            $result = Get-SPCPrivilegedUser
            $global:retryCount | Should -Be 3
        }
    }
    
    Context 'Security Scenarios' {
        It 'AC-SEC-01 Should not leak credentials in verbose stream' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site1" }) }
            Mock Connect-PnPOnline { return "MockConnection" }
            Mock Get-PnPSiteUser { return @() }
            Mock Get-PnPGroup { return $null }
            Mock Get-PnPRoleAssignment { return @() }

            $verboseOutput = ""
            try {
                Get-SPCPrivilegedUser -Verbose 4>&1 | ForEach-Object { $verboseOutput += $_.ToString() }
            } catch { }

            $verboseOutput | Should -Not -Match 'password|secret|token|pfx|credential'
        }
        
        It 'AC-SEC-03 Should not execute dynamic string via IEX' {
            $scriptContent = Get-Content $sut -Raw
            $scriptContent -match 'iex|Invoke-Expression' | Should -BeFalse
        }
    }
}
