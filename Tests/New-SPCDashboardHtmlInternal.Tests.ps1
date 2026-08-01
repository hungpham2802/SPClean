$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Parent $here) + "\Private\New-SPCDashboardHtmlInternal.ps1"
. $sut

Describe 'New-SPCDashboardHtmlInternal' {
    $tempFile = Join-Path $env:TEMP "dashboard_test_$([guid]::NewGuid()).html"

    AfterAll {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
    }

    Context 'When generating HTML file' {
        It 'AC-F4-01 Should generate a single offline HTML without CDN' {
            New-SPCDashboardHtmlInternal -OutputPath $tempFile -TotalUsers 10
            
            $content = Get-Content $tempFile -Raw
            $content | Should -Match "<style>"
            $content | Should -Not -Match "<link rel=`"stylesheet`""
            $content | Should -Not -Match "<script src="
        }
    }

    Context 'When rendering UI components' {
        It 'AC-F4-02 Should contain 4 KPI Cards, 1 Score Card and 2 Data Tables' {
            $orphaned = @([PSCustomObject]@{ DisplayName="UserA"; UPN="a@a.com"; RiskLevel="HIGH" })
            $guests = @([PSCustomObject]@{ DisplayName="UserB"; UPN="b@b.com"; RiskLevel="LOW" })
            
            New-SPCDashboardHtmlInternal -OutputPath $tempFile -TotalUsers 100 -TotalGuests 10 -TotalOrphaned 5 -HighRiskUsers 2 -OrphanedUsersList $orphaned -TopHighRiskGuestsList $guests

            $content = Get-Content $tempFile -Raw
            
            # Check 4 KPI Cards
            $content | Should -Match "Total Users"
            $content | Should -Match "Total Guests"
            $content | Should -Match "Orphaned Users"
            $content | Should -Match "High Risk Users"

            # Check 1 Score Card
            $content | Should -Match "Overall Permission Health Score"

            # Check 2 Data Tables
            $content | Should -Match "<table"
            $content | Should -Match "UserA"
            $content | Should -Match "UserB"
        }
    }

    Context 'When applying risk colors' {
        It 'AC-F4-03 Should apply correct HTML hex color codes for risk levels' {
            $orphaned = @(
                [PSCustomObject]@{ DisplayName="User1"; UPN="1@a.com"; RiskLevel="HIGH" },
                [PSCustomObject]@{ DisplayName="User2"; UPN="2@a.com"; RiskLevel="MEDIUM" },
                [PSCustomObject]@{ DisplayName="User3"; UPN="3@a.com"; RiskLevel="LOW" }
            )
            
            New-SPCDashboardHtmlInternal -OutputPath $tempFile -OrphanedUsersList $orphaned

            $content = Get-Content $tempFile -Raw
            
            $content | Should -Match "#dc3545" # HIGH
            $content | Should -Match "#ffc107" # MEDIUM
            $content | Should -Match "#28a745" # LOW
        }
    }

    Context 'Negative Scenarios' {
        It 'AC-NEG-04 Should generate dashboard gracefully with empty or null data arrays' {
            New-SPCDashboardHtmlInternal -OutputPath $tempFile -OrphanedUsersList $null -TopHighRiskGuestsList $null
            
            $content = Get-Content $tempFile -Raw
            $content | Should -Match "No orphaned users found."
            $content | Should -Match "No high-risk guests found."
        }
    }

    Context 'Security Scenarios' {
        It 'AC-SEC-02 Should HTML-encode user input to prevent XSS in Dashboard' {
            $maliciousUser = @([PSCustomObject]@{ DisplayName="<script>alert('hack')</script>"; UPN="hack@hack.com"; RiskLevel="HIGH" })
            
            New-SPCDashboardHtmlInternal -OutputPath $tempFile -OrphanedUsersList $maliciousUser

            $content = Get-Content $tempFile -Raw
            
            $content | Should -Not -Match "<script>alert('hack')</script>"
            $content | Should -Match "&lt;script&gt;alert(&#39;hack&#39;)&lt;/script&gt;"
        }
    }
}
