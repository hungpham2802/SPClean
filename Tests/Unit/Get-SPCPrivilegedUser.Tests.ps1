#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Get-SPCPrivilegedUser' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../../Private/PnPWrappers.ps1')
        . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
        . (Join-Path $PSScriptRoot '../../Private/Connect-SPCSiteInternal.ps1')
        . (Join-Path $PSScriptRoot '../../Private/Invoke-SPCTempElevationInternal.ps1')
        . (Join-Path $PSScriptRoot '../../Public/Scan/Get-SPCPrivilegedUser.ps1')
        $script:sut = (Join-Path $PSScriptRoot '../../Public/Scan/Get-SPCPrivilegedUser.ps1')
    }

    BeforeEach {
        $script:SPCContext = [PSCustomObject]@{
            TenantName       = 'tenant'
            OperatorUPN      = 'admin@tenant.onmicrosoft.com'
            AuthMethod       = 'Interactive'
            GraphAccessToken = 'mock_token'
            PnPContext       = [PSCustomObject]@{ Url = 'https://tenant-admin.sharepoint.com' }
        }
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
            Mock Get-PnPAccessToken { return "MockToken" }
            Mock Connect-PnPOnline { return "MockConnection" }
            
            Mock Get-PnPSiteCollectionAdmin {
                $users = @()
                for ($u=1; $u -le 25; $u++) {
                    # Every user is SCA on site corresponding to their number and below
                    $users += [PSCustomObject]@{ LoginName = "i:0#.f|membership|user$u@domain.com" }
                }
                return $users
            }
            Mock Get-PnPGroup { return $null }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }

            $result = Get-SPCPrivilegedUser
            $result.Count | Should -Be 20
            $result[0].UPN | Should -Match "user"
        }
    }

    Context 'When checking permission sources' {
        It 'AC-F2-02 Should correctly identify SCA, Owner, and Direct Full Control' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site1" }) }
            Mock Get-PnPAccessToken { return "MockToken" }
            Mock Connect-PnPOnline { return "MockConnection" }
            Mock Get-PnPSiteCollectionAdmin { return @([PSCustomObject]@{ LoginName = "i:0#.f|membership|usera@domain.com" }) }
            Mock Get-PnPGroup { return [PSCustomObject]@{ Title = "Owners" } }
            Mock Get-PnPGroupMember { return @([PSCustomObject]@{ LoginName = "i:0#.f|membership|userb@domain.com" }) }
            Mock Invoke-PnPSPRestMethod {
                return [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{ 
                            Member = [PSCustomObject]@{ PrincipalType = 'User'; LoginName = "i:0#.f|membership|userc@domain.com" }
                            RoleDefinitionBindings = @([PSCustomObject]@{ Name = 'Full Control' })
                        }
                    )
                }
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
            Mock Get-PnPAccessToken { return "MockToken" }
            Mock Connect-PnPOnline { return "MockConnection" }
            Mock Get-PnPSiteCollectionAdmin { return @() }
            Mock Get-PnPGroup { return $null }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }

            $result = Get-SPCPrivilegedUser
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Negative Scenarios' {
        It 'AC-NEG-01 Should throw Terminating Error ERR-AUTH-001 when connection fails' {
            Mock Get-PnPTenantSite { throw "Connection failed" }
            
            { Get-SPCPrivilegedUser } | Should -Throw -ErrorId "ERR-AUTH-001*"
        }

        It 'AC-NEG-02 Should write non-terminating error and continue for inaccessible sites' {
            Mock Get-PnPTenantSite { 
                return @(
                    [PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/errorSite" },
                    [PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/goodSite" }
                ) 
            }
            Mock Get-PnPAccessToken { return "MockToken" }
            Mock Connect-PnPOnline { 
                if ($args[0] -match "errorSite") {
                    throw "Access Denied"
                }
                return "MockConnection"
            }
            Mock Get-PnPSiteCollectionAdmin { return @([PSCustomObject]@{ LoginName = "i:0#.f|membership|good@domain.com" }) }
            Mock Get-PnPGroup { return $null }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }

            $result = Get-SPCPrivilegedUser -ErrorAction SilentlyContinue
            $result.Count | Should -Be 1
            $result[0].UPN | Should -Be "good@domain.com"
        }

        It 'AC-NEG-03 Should implement exponential backoff retry on 429/503 errors' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site1" }) }
            $global:retryCount = 0
            Mock Get-PnPAccessToken { return "MockToken" }
            Mock Connect-PnPOnline { 
                $global:retryCount++
                if ($global:retryCount -lt 3) {
                    throw "429 Too Many Requests"
                }
                return "MockConnection"
            }
            Mock Get-PnPSiteCollectionAdmin { return @() }
            Mock Get-PnPGroup { return $null }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }
            Mock Start-Sleep { return $true } # Mock Start-Sleep to speed up test

            $result = Get-SPCPrivilegedUser
            $global:retryCount | Should -Be 3
        }

        It 'AC-SCA-01 Should temporarily elevate SCA on Access Denied when -AddTempSiteCollectionAdmin is supplied' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/restrictedSite" }) }
            $script:accessDenied = $true
            Mock Connect-SPCSiteInternal {
                return [PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/restrictedSite" }
            }
            Mock Get-PnPSiteCollectionAdmin {
                if ($script:accessDenied) {
                    throw "403 Unauthorized: Access Denied"
                }
                return @([PSCustomObject]@{ LoginName = "i:0#.f|membership|elevateduser@domain.com" })
            }
            Mock Set-PnPTenantSite {
                $script:accessDenied = $false
            }
            Mock Remove-PnPSiteCollectionAdmin {}
            Mock Start-Sleep {}
            Mock Get-PnPGroup { return $null }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }

            $result = Get-SPCPrivilegedUser -AddTempSiteCollectionAdmin
            $result.Count | Should -Be 1
            $result[0].UPN | Should -Be "elevateduser@domain.com"
            Should -Invoke -CommandName Set-PnPTenantSite -Times 1 -Exactly
            Should -Invoke -CommandName Remove-PnPSiteCollectionAdmin -Times 1 -Exactly
        }
    }
    
    Context 'Security Scenarios' {
        It 'AC-SEC-01 Should not leak credentials in verbose stream' {
            Mock Get-PnPTenantSite { return @([PSCustomObject]@{ Url = "https://tenant.sharepoint.com/sites/site1" }) }
            Mock Get-PnPAccessToken { return "MockToken" }
            Mock Connect-PnPOnline { return "MockConnection" }
            Mock Get-PnPSiteCollectionAdmin { return @() }
            Mock Get-PnPGroup { return $null }
            Mock Invoke-PnPSPRestMethod { return [PSCustomObject]@{ value = @() } }

            $verboseOutput = ""
            try {
                Get-SPCPrivilegedUser -Verbose 4>&1 | ForEach-Object { $verboseOutput += $_.ToString() }
            } catch { }

            $verboseOutput | Should -Not -Match 'password|secret|token|pfx|credential'
        }
        
        It 'AC-SEC-03 Should not execute dynamic string via IEX' {
            $scriptContent = Get-Content $script:sut -Raw
            $scriptContent -match 'iex|Invoke-Expression' | Should -BeFalse
        }
    }
}
