#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    SPClean Phase 1 — Integration Tests (real tenant required).

.DESCRIPTION
    Tests run against a dev tenant to verify Guest Access, Privileged Users, Over-Permissioned Users and Dashboard.

    Setup requirements:
        - Must provide valid TenantName, ClientId, and CertificateThumbprint as Environment variables or defaults.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../SPClean.psd1') -Force -ErrorAction Stop

    $script:tenantName = 'icclabvn.onmicrosoft.com'
    $script:clientId = 'eecf892a-44c3-48fe-aa2f-b9e332dda328'
    $script:thumbprint = 'FCC7E9F8AB71338B51E2DF77F17B903C2342C53A'

    $script:conn = Connect-SPCTenant `
        -TenantName $script:tenantName `
        -AuthMethod AppOnly `
        -ClientId $script:clientId `
        -CertificateThumbprint $script:thumbprint `
        -ErrorAction Stop

    # Define temporary output path for HTML Dashboard
    $ts = (Get-Date).ToString('yyyyMMddHHmmss')
    $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "SPClean_Phase1_IT_$ts"
    [void](New-Item -Path $script:tempDir -ItemType Directory -Force)
    $script:htmlPath = Join-Path $script:tempDir "TestDashboard.html"
}

AfterAll {
    Disconnect-SPCTenant -ErrorAction SilentlyContinue
    if ($script:tempDir -and (Test-Path $script:tempDir)) {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Phase 1 Features - Real Tenant Scan' {
    
    Context 'Get-SPCGuestAccess' {
        It 'Returns an array of guest users or empty, without throwing errors' {
            $script:guests = @(Get-SPCGuestAccess -ErrorAction Stop)
            $script:guests.Count | Should -BeGreaterOrEqual 0
        }
        It 'Outputs objects of type SPC.GuestUser' {
            if ($script:guests.Count -gt 0) {
                $script:guests[0].PSObject.TypeNames | Should -Contain 'SPC.GuestUser'
            }
        }
    }

    Context 'Get-SPCOrphanedUser' {
        It 'Returns orphaned users without throwing errors' {
            $script:orphans = @(Get-SPCOrphanedUser -AllSites -IncludeGuests -IncludeDisabled -ErrorAction Stop)
            $script:orphans.Count | Should -BeGreaterOrEqual 0
        }
        It 'Outputs objects of type SPC.OrphanedUser' {
            if ($script:orphans.Count -gt 0) {
                $script:orphans[0].PSObject.TypeNames | Should -Contain 'SPC.OrphanedUser'
            }
        }
    }

    Context 'Get-SPCPrivilegedUser' {
        It 'Returns privileged users without throwing errors' {
            $script:privileged = @(Get-SPCPrivilegedUser -ClientId $script:clientId -Thumbprint $script:thumbprint -Tenant $script:tenantName -ErrorAction Stop)
            $script:privileged.Count | Should -BeGreaterOrEqual 0
        }
        It 'Outputs objects of type SPC.PrivilegedUser' {
            if ($script:privileged.Count -gt 0) {
                $script:privileged[0].PSObject.TypeNames | Should -Contain 'SPC.PrivilegedUser'
            }
        }
    }

    Context 'Get-SPCOverPermissionedUser' {
        It 'Returns over-permissioned users without throwing errors' {
            $script:overPermissioned = @(Get-SPCOverPermissionedUser -ClientId $script:clientId -Thumbprint $script:thumbprint -Tenant $script:tenantName -ErrorAction Stop)
            $script:overPermissioned.Count | Should -BeGreaterOrEqual 0
        }
        It 'Outputs objects of type SPC.OverPermissionedUser' {
            if ($script:overPermissioned.Count -gt 0) {
                $script:overPermissioned[0].PSObject.TypeNames | Should -Contain 'SPC.OverPermissionedUser'
            }
        }
    }

    Context 'New-SPCDashboardHtmlInternal' {
        It 'Generates HTML dashboard correctly' {
            # Load private function
            . (Join-Path $PSScriptRoot '../../Private/New-SPCDashboardHtmlInternal.ps1')
            
            $highRiskGuests = @($script:guests | Where-Object { $_.RiskLevel -eq 'HIGH' })
            $highRiskOrphans = @($script:orphans | Where-Object { $_.RiskLevel -eq 'HIGH' })
            
            $graphToken = $script:conn.GraphAccessToken
            $headers = @{ "Authorization" = "Bearer $graphToken"; "ConsistencyLevel" = "eventual" }
            $response = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users?`$count=true" -Headers $headers -ErrorAction SilentlyContinue
            $totalUsers = $response.'@odata.count'
            if ($null -eq $totalUsers) { $totalUsers = 0 }

            New-SPCDashboardHtmlInternal `
                -OutputPath $script:htmlPath `
                -TotalUsers $totalUsers `
                -TotalGuests $script:guests.Count `
                -TotalOrphaned $script:orphans.Count `
                -HighRiskUsers ($highRiskGuests.Count + $highRiskOrphans.Count) `
                -OrphanedUsersList $script:orphans `
                -TopHighRiskGuestsList $highRiskGuests `
                -PrivilegedUsers $script:privileged `
                -OverPermissionedUsers $script:overPermissioned
            
            Test-Path $script:htmlPath | Should -Be $true
        }
        It 'Generated HTML file contains expected content' {
            $htmlContent = Get-Content $script:htmlPath -Raw
            $htmlContent | Should -Match '<html'
            $htmlContent | Should -Match '</html>'
            $htmlContent.Length | Should -BeGreaterThan 1000
        }
    }
}
