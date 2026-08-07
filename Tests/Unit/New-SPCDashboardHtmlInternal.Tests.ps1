#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
$sut = "$PSScriptRoot\..\..\Private\New-SPCDashboardHtmlInternal.ps1"

Describe 'New-SPCDashboardHtmlInternal' {
    BeforeAll {
        . $PSScriptRoot\..\..\Private\New-SPCDashboardHtmlInternal.ps1
        $script:tempFile = Join-Path $env:TEMP "dashboard_test_$([guid]::NewGuid()).html"
    }

    AfterAll {
        if (Test-Path $script:tempFile) {
            Remove-Item $script:tempFile -Force
        }
    }

    Context 'When generating HTML file' {
        It 'AC-F4-01 Should generate a single offline HTML without CDN' {
            New-SPCDashboardHtmlInternal -OutputPath $script:tempFile -TotalUsers 10
            
            $content = Get-Content $script:tempFile -Raw
            $content | Should -Match "<style>"
            $content | Should -Not -Match "<link rel=`"stylesheet`""
            $content | Should -Not -Match "<script src="
        }
    }

    Context 'When rendering UI components' {
        It 'AC-F4-02 Should contain 4 KPI Cards, 1 Score Card and 4 Data Tables' {
            $orphaned = @([PSCustomObject]@{ DisplayName="UserA"; UPN="a@a.com"; RiskLevel="HIGH"; SiteTitle="HR Site"; SiteUrl="https://test/hr" })
            $guests = @([PSCustomObject]@{ DisplayName="UserB"; UPN="b@b.com"; RiskLevel="LOW"; SiteTitle="HR Site"; SiteUrl="https://test/hr" })
            $privileged = @([PSCustomObject]@{ UPN="admin@a.com"; SiteCount=3; Sites=@("https://site1","https://site2"); PermissionSources=@("SCA","Owner") })
            $overPermissioned = @([PSCustomObject]@{ UPN="op@a.com"; FullControlCount=5; EditCount=2; ReadCount=10; EAS=21; IsRedAlert=$false })
            
            New-SPCDashboardHtmlInternal -OutputPath $script:tempFile `
                -TotalUsers 100 `
                -TotalGuests 10 `
                -TotalOrphaned 5 `
                -HighRiskUsers 2 `
                -OrphanedUsersList $orphaned `
                -TopHighRiskGuestsList $guests `
                -PrivilegedUsers $privileged `
                -OverPermissionedUsers $overPermissioned

            $content = Get-Content $script:tempFile -Raw
            
            # Check 4 KPI Cards
            $content | Should -Match "Total Users"
            $content | Should -Match "Total Guests"
            $content | Should -Match "Orphaned Users"
            $content | Should -Match "High Risk Users"

            # Check 1 Score Card
            $content | Should -Match "Overall Permission Health Score"

            # Check 4 Data Tables
            $content | Should -Match "Orphaned Users"
            $content | Should -Match "Top High-Risk Guests"
            $content | Should -Match "Top Privileged Users"
            $content | Should -Match "Over-Permissioned Users \(EAS\)"

            # Check contents
            $content | Should -Match "UserA"
            $content | Should -Match "UserB"
            $content | Should -Match "admin@a.com"
            $content | Should -Match "op@a.com"
            $content | Should -Match "Permission Sources"
            $content | Should -Match "Red Alert Badge"
        }
    }

    Context 'When applying risk colors' {
        It 'AC-F4-03 Should apply correct HTML hex color codes for risk levels' {
            $orphaned = @(
                [PSCustomObject]@{ DisplayName="User1"; UPN="1@a.com"; RiskLevel="HIGH"; SiteTitle="HR Site"; SiteUrl="https://test/hr" },
                [PSCustomObject]@{ DisplayName="User2"; UPN="2@a.com"; RiskLevel="MEDIUM"; SiteTitle="HR Site"; SiteUrl="https://test/hr" },
                [PSCustomObject]@{ DisplayName="User3"; UPN="3@a.com"; RiskLevel="LOW"; SiteTitle="HR Site"; SiteUrl="https://test/hr" }
            )
            
            New-SPCDashboardHtmlInternal -OutputPath $script:tempFile -OrphanedUsersList $orphaned

            $content = Get-Content $script:tempFile -Raw
            
            $content | Should -Match "#dc3545" # HIGH
            $content | Should -Match "#ffc107" # MEDIUM
            $content | Should -Match "#28a745" # LOW
        }
    }

    Context 'Negative Scenarios' {
        It 'AC-NEG-04 Should generate dashboard gracefully with empty or null data arrays' {
            New-SPCDashboardHtmlInternal -OutputPath $script:tempFile `
                -OrphanedUsersList $null `
                -TopHighRiskGuestsList $null `
                -PrivilegedUsers $null `
                -OverPermissionedUsers $null
            
            $content = Get-Content $script:tempFile -Raw
            $content | Should -Match "No orphaned users found."
            $content | Should -Match "No high-risk guests found."
            $content | Should -Match "No privileged users found."
            $content | Should -Match "No over-permissioned users found."
        }
    }

    Context 'Security Scenarios' {
        It 'AC-SEC-02 Should HTML-encode user input to prevent XSS in Dashboard' {
            $maliciousUser = @([PSCustomObject]@{ DisplayName="<script>alert('hack')</script>"; UPN="hack@hack.com"; RiskLevel="HIGH"; SiteTitle="HR Site"; SiteUrl="https://test/hr" })
            $maliciousPriv = @([PSCustomObject]@{ UPN="<script>alert('priv')</script>"; SiteCount=1; Sites=@("<script>site</script>"); PermissionSources=@("SCA") })
            $maliciousOver = @([PSCustomObject]@{ UPN="<script>alert('over')</script>"; FullControlCount=1; EditCount=1; ReadCount=1; EAS=6; IsRedAlert=$false })
            
            New-SPCDashboardHtmlInternal -OutputPath $script:tempFile `
                -OrphanedUsersList $maliciousUser `
                -PrivilegedUsers $maliciousPriv `
                -OverPermissionedUsers $maliciousOver

            $content = Get-Content $script:tempFile -Raw
            
            $content | Should -Not -Match "<script>alert\('hack'\)</script>"
            $content | Should -Not -Match "<script>alert\('priv'\)</script>"
            $content | Should -Not -Match "<script>alert\('over'\)</script>"
            $content | Should -Match "&lt;script&gt;alert\(&#39;hack&#39;\)&lt;/script&gt;"
            $content | Should -Match "&lt;script&gt;alert\(&#39;priv&#39;\)&lt;/script&gt;"
            $content | Should -Match "&lt;script&gt;alert\(&#39;over&#39;\)&lt;/script&gt;"
        }
    }
}
