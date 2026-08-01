function New-SPCDashboardHtmlInternal {
    <#
    .SYNOPSIS
        Generates an offline HTML Dashboard for SPClean (Permission Health Dashboard v1.5).
    
    .DESCRIPTION
        Takes analyzed data regarding Privileged Users, Over-Permissioned Users, 
        and Orphaned Users, and generates a single HTML file with CSS/JS embedded.
    
    .EXAMPLE
        New-SPCDashboardHtmlInternal -OutputPath "C:\temp\report.html" -TotalUsers 500 -TotalGuests 50 -OrphanedUsers $orphaned -HighRiskUsers 5 -TopHighRiskGuests $highRiskGuests
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [int]$TotalUsers = 0,

        [Parameter(Mandatory = $false)]
        [int]$TotalGuests = 0,

        [Parameter(Mandatory = $false)]
        [int]$TotalOrphaned = 0,

        [Parameter(Mandatory = $false)]
        [int]$HighRiskUsers = 0,

        [Parameter(Mandatory = $false)]
        [array]$OrphanedUsersList = @(),

        [Parameter(Mandatory = $false)]
        [array]$TopHighRiskGuestsList = @(),
        
        [Parameter(Mandatory = $false)]
        [array]$PrivilegedUsers = @(),

        [Parameter(Mandatory = $false)]
        [array]$OverPermissionedUsers = @()
    )

    begin {
        Write-Verbose "Starting Dashboard HTML Generation..."
    }

    process {
        try {
            # HTML Encode function
            function ConvertTo-HtmlEncodedString {
                param([string]$inputStr)
                if ([string]::IsNullOrEmpty($inputStr)) { return "" }
                return [System.Net.WebUtility]::HtmlEncode($inputStr)
            }

            # Helper to color code risks
            function Get-RiskColor {
                param([string]$riskLevel)
                switch ($riskLevel.ToUpper()) {
                    "HIGH" { return "#dc3545" }
                    "MEDIUM" { return "#ffc107" }
                    "LOW" { return "#28a745" }
                    default { return "#6c757d" }
                }
            }

            # Generate Orphaned Users Table Rows
            $orphanedRows = ""
            if ($null -ne $OrphanedUsersList -and $OrphanedUsersList.Count -gt 0) {
                foreach ($u in $OrphanedUsersList) {
                    $displayName = ConvertTo-HtmlEncodedString $u.DisplayName
                    $upn = ConvertTo-HtmlEncodedString $u.UPN
                    $risk = ConvertTo-HtmlEncodedString $u.RiskLevel
                    $color = Get-RiskColor $risk
                    $orphanedRows += "<tr><td>$displayName</td><td>$upn</td><td style='color:$color; font-weight:bold;'>$risk</td></tr>"
                }
            } else {
                $orphanedRows = "<tr><td colspan='3'>No orphaned users found.</td></tr>"
            }

            # Generate High Risk Guests Table Rows
            $guestRows = ""
            if ($null -ne $TopHighRiskGuestsList -and $TopHighRiskGuestsList.Count -gt 0) {
                foreach ($g in $TopHighRiskGuestsList) {
                    $dName = if ($null -ne $g.DisplayName) { $g.DisplayName } else { "Guest User" }
                    $uName = if ($null -ne $g.UPN) { $g.UPN } elseif ($null -ne $g.GuestEmail) { $g.GuestEmail } else { "" }
                    $displayName = ConvertTo-HtmlEncodedString $dName
                    $upn = ConvertTo-HtmlEncodedString $uName
                    $risk = ConvertTo-HtmlEncodedString $g.RiskLevel
                    $color = Get-RiskColor $risk
                    $guestRows += "<tr><td>$displayName</td><td>$upn</td><td style='color:$color; font-weight:bold;'>$risk</td></tr>"
                }
            } else {
                $guestRows = "<tr><td colspan='3'>No high-risk guests found.</td></tr>"
            }
            
            # Health Score Logic
            $score = 100
            if ($HighRiskUsers -gt 0) {
                $score = $score - ($HighRiskUsers * 2)
            }
            if ($TotalOrphaned -gt 0) {
                $score = $score - ($TotalOrphaned * 1)
            }
            if ($score -lt 0) { $score = 0 }
            
            $scoreColor = "#28a745"
            if ($score -lt 70) { $scoreColor = "#ffc107" }
            if ($score -lt 40) { $scoreColor = "#dc3545" }

            $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Content-Security-Policy" content="default-src 'self'; style-src 'unsafe-inline';">
    <title>SPClean - Permission Health Dashboard v1.5</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f4f7f6; margin: 0; padding: 20px; color: #333; }
        .container { max-width: 1200px; margin: auto; }
        h1 { text-align: center; color: #2c3e50; }
        
        .kpi-container { display: flex; justify-content: space-between; margin-bottom: 20px; flex-wrap: wrap; }
        .kpi-card { background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); width: 22%; text-align: center; margin-bottom: 10px; }
        .kpi-card h3 { margin: 0 0 10px 0; font-size: 1.2em; color: #7f8c8d; }
        .kpi-card .value { font-size: 2em; font-weight: bold; color: #2980b9; }

        .score-card { background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); text-align: center; margin-bottom: 20px; }
        .score-circle { 
            width: 150px; height: 150px; border-radius: 50%; 
            background: conic-gradient($scoreColor $($score)%, #e0e0e0 0); 
            display: flex; align-items: center; justify-content: center; 
            margin: auto; font-size: 2em; font-weight: bold; color: #333;
        }
        .score-inner { width: 120px; height: 120px; border-radius: 50%; background: #fff; display: flex; align-items: center; justify-content: center; }

        .tables-container { display: flex; justify-content: space-between; flex-wrap: wrap; }
        .data-table-wrap { width: 48%; background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); margin-bottom: 20px; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; color: #495057; }
        
        @media (max-width: 768px) {
            .kpi-card { width: 48%; }
            .data-table-wrap { width: 100%; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>SPClean Permission Health Dashboard</h1>
        
        <!-- Score Card -->
        <div class="score-card">
            <h3>Overall Permission Health Score</h3>
            <div class="score-circle">
                <div class="score-inner">$score/100</div>
            </div>
        </div>

        <!-- 4 KPI Cards -->
        <div class="kpi-container">
            <div class="kpi-card">
                <h3>Total Users</h3>
                <div class="value">$TotalUsers</div>
            </div>
            <div class="kpi-card">
                <h3>Total Guests</h3>
                <div class="value">$TotalGuests</div>
            </div>
            <div class="kpi-card">
                <h3>Orphaned Users</h3>
                <div class="value">$TotalOrphaned</div>
            </div>
            <div class="kpi-card">
                <h3>High Risk Users</h3>
                <div class="value">$HighRiskUsers</div>
            </div>
        </div>

        <!-- Data Tables -->
        <div class="tables-container">
            <div class="data-table-wrap">
                <h3>Orphaned Users</h3>
                <table>
                    <thead>
                        <tr><th>Name</th><th>UPN</th><th>Risk Level</th></tr>
                    </thead>
                    <tbody>
                        $orphanedRows
                    </tbody>
                </table>
            </div>

            <div class="data-table-wrap">
                <h3>Top High-Risk Guests</h3>
                <table>
                    <thead>
                        <tr><th>Name</th><th>UPN</th><th>Risk Level</th></tr>
                    </thead>
                    <tbody>
                        $guestRows
                    </tbody>
                </table>
            </div>
        </div>
    </div>
</body>
</html>
"@

            Set-Content -Path $OutputPath -Value $html -Encoding UTF8 -Force
            Write-Output "Dashboard generated successfully at: $OutputPath"
            
        } catch {
            $errCode = "ERR-HTML-001"
            $exMsg = "[$errCode] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ssZ'): Terminating error occurred generating dashboard. $($_.Exception.Message)"
            Write-Error -Message $exMsg -Exception $_.Exception -ErrorAction Stop
        }
    }

    end {
        Write-Information -MessageData "Completed New-SPCDashboardHtmlInternal." -InformationAction Continue
    }
}
