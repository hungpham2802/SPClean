$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Parent $here) + "\Public\Get-SPCOverPermissionedUser.ps1"
. $sut

Describe 'Get-SPCOverPermissionedUser' {
    BeforeAll {
        function Test-SPCConnection { return $true }
    }

    Context 'When calculating EAS' {
        It 'AC-F3-01 Should correctly calculate EAS based on formula' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site1" }) }
            Mock Connect-PnPOnline { return "MockConnection" }
            Mock Get-PnPRoleAssignment {
                $assignments = @()
                for ($i=0; $i -lt 5; $i++) {
                    $assignments += [PSCustomObject]@{ Member = [PSCustomObject]@{ PrincipalType = 'User'; LoginName = "i:0#.f|membership|usera@domain.com" }; RoleDefinitionBindings = @([PSCustomObject]@{ Name = 'Full Control' }) }
                }
                for ($i=0; $i -lt 10; $i++) {
                    $assignments += [PSCustomObject]@{ Member = [PSCustomObject]@{ PrincipalType = 'User'; LoginName = "i:0#.f|membership|usera@domain.com" }; RoleDefinitionBindings = @([PSCustomObject]@{ Name = 'Edit' }) }
                }
                for ($i=0; $i -lt 15; $i++) {
                    $assignments += [PSCustomObject]@{ Member = [PSCustomObject]@{ PrincipalType = 'User'; LoginName = "i:0#.f|membership|usera@domain.com" }; RoleDefinitionBindings = @([PSCustomObject]@{ Name = 'Read' }) }
                }
                return $assignments
            }

            $result = Get-SPCOverPermissionedUser
            $result.Count | Should -Be 1
            $result[0].EAS | Should -Be 50 # 5*3 + 10*2 + 15*1 = 50
        }
    }

    Context 'When EAS is greater than 100' {
        It 'AC-F3-02 Should flag user with Red Alert if EAS > 100' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site1" }) }
            Mock Connect-PnPOnline { return "MockConnection" }
            Mock Get-PnPRoleAssignment {
                $assignments = @()
                for ($i=0; $i -lt 40; $i++) {
                    $assignments += [PSCustomObject]@{ Member = [PSCustomObject]@{ PrincipalType = 'User'; LoginName = "i:0#.f|membership|userb@domain.com" }; RoleDefinitionBindings = @([PSCustomObject]@{ Name = 'Full Control' }) }
                }
                return $assignments
            }

            $result = Get-SPCOverPermissionedUser
            $result.Count | Should -Be 1
            $result[0].EAS | Should -Be 120
            $result[0].IsRedAlert | Should -Be $true
        }
    }

    Context 'When EAS is exactly 100 or less' {
        It 'AC-F3-03 Should not flag user with Red Alert if EAS <= 100' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site1" }) }
            Mock Connect-PnPOnline { return "MockConnection" }
            Mock Get-PnPRoleAssignment {
                $assignments = @()
                for ($i=0; $i -lt 30; $i++) {
                    $assignments += [PSCustomObject]@{ Member = [PSCustomObject]@{ PrincipalType = 'User'; LoginName = "i:0#.f|membership|userc@domain.com" }; RoleDefinitionBindings = @([PSCustomObject]@{ Name = 'Full Control' }) }
                }
                for ($i=0; $i -lt 5; $i++) {
                    $assignments += [PSCustomObject]@{ Member = [PSCustomObject]@{ PrincipalType = 'User'; LoginName = "i:0#.f|membership|userc@domain.com" }; RoleDefinitionBindings = @([PSCustomObject]@{ Name = 'Edit' }) }
                }
                return $assignments
            }

            $result = Get-SPCOverPermissionedUser
            $result.Count | Should -Be 1
            $result[0].EAS | Should -Be 100
            $result[0].IsRedAlert | Should -Be $false
        }
    }
    
    Context 'Negative Scenarios' {
        It 'AC-NEG-01 Should throw Terminating Error ERR-AUTH-001 when connection fails' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site1" }) }
            Mock Connect-PnPOnline { throw "Connection failed" }
            
            { Get-SPCOverPermissionedUser } | Should -Throw -ErrorId "ERR-AUTH-001"
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
            Mock Get-PnPRoleAssignment { 
                return @([PSCustomObject]@{ Member = [PSCustomObject]@{ PrincipalType = 'User'; LoginName = "i:0#.f|membership|good@domain.com" }; RoleDefinitionBindings = @([PSCustomObject]@{ Name = 'Full Control' }) })
            }

            $result = Get-SPCOverPermissionedUser -ErrorAction SilentlyContinue
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
            Mock Get-PnPRoleAssignment { return @() }
            Mock Start-Sleep { return $true } # Mock Start-Sleep to speed up test

            $result = Get-SPCOverPermissionedUser
            $global:retryCount | Should -Be 3
        }
    }

    Context 'Security Scenarios' {
        It 'AC-SEC-01 Should not leak credentials in verbose stream' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site1" }) }
            Mock Connect-PnPOnline { return "MockConnection" }
            Mock Get-PnPRoleAssignment { return @() }

            $verboseOutput = ""
            try {
                Get-SPCOverPermissionedUser -Verbose 4>&1 | ForEach-Object { $verboseOutput += $_.ToString() }
            } catch { }

            $verboseOutput | Should -Not -Match 'password|secret|token|pfx|credential'
        }
        
        It 'AC-SEC-03 Should not execute dynamic string via IEX' {
            $scriptContent = Get-Content $sut -Raw
            $scriptContent -match 'iex|Invoke-Expression' | Should -BeFalse
        }
    }
}
