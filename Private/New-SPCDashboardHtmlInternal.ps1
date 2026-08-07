function New-SPCDashboardHtmlInternal {
    <#
    .SYNOPSIS
        Generates an offline HTML Dashboard for SPClean (Permission Health Dashboard v1.5).
    
    .DESCRIPTION
        Takes analyzed data regarding Privileged Users, Over-Permissioned Users, 
        and Orphaned Users, and generates a single HTML file with CSS/JS embedded.
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

            # Deduplicate Orphaned Users (Group by UPN)
            $uniqueOrphans = @()
            if ($null -ne $OrphanedUsersList -and $OrphanedUsersList.Count -gt 0) {
                $grouped = $OrphanedUsersList | Group-Object UPN
                foreach ($g in $grouped) {
                    $first = $g.Group[0]
                    $sites = ($g.Group | Select-Object -ExpandProperty SiteTitle | Select-Object -Unique) -join ', '
                    if ([string]::IsNullOrWhiteSpace($sites)) {
                        $sites = ($g.Group | Select-Object -ExpandProperty SiteUrl | Select-Object -Unique) -join ', '
                    }
                    $uniqueOrphans += [PSCustomObject]@{
                        DisplayName = $first.DisplayName
                        UPN = $first.UPN
                        RiskLevel = $first.RiskLevel
                        OrphanType = $first.OrphanType
                        Sites = $sites
                    }
                }
            }

            # Generate Orphaned Users Table Rows
            $orphanedRows = ""
            if ($uniqueOrphans.Count -gt 0) {
                foreach ($u in $uniqueOrphans) {
                    $dName = if (-not [string]::IsNullOrWhiteSpace($u.DisplayName)) { $u.DisplayName } else { $u.UPN }
                    $uName = if (-not [string]::IsNullOrWhiteSpace($u.UPN)) { $u.UPN } else { "" }
                    $displayName = ConvertTo-HtmlEncodedString $dName
                    $upn = ConvertTo-HtmlEncodedString $uName
                    $status = ConvertTo-HtmlEncodedString $u.OrphanType
                    $sites = ConvertTo-HtmlEncodedString $u.Sites
                    $sites = "<div class='scrollable-cell'>$sites</div>"
                    $risk = ConvertTo-HtmlEncodedString $u.RiskLevel
                    $color = Get-RiskColor $risk
                    $orphanedRows += "<tr><td>$displayName</td><td>$upn</td><td>$status</td><td>$sites</td><td style='color:$color; font-weight:bold;'>$risk</td></tr>"
                }
            } else {
                $orphanedRows = "<tr><td colspan='5'>No orphaned users found.</td></tr>"
            }

            # Generate High Risk Guests Table Rows
            $guestRows = ""
            if ($null -ne $TopHighRiskGuestsList -and $TopHighRiskGuestsList.Count -gt 0) {
                foreach ($g in $TopHighRiskGuestsList) {
                    $dName = if (-not [string]::IsNullOrWhiteSpace($g.DisplayName)) { $g.DisplayName } else { "Guest User" }
                    $uName = if (-not [string]::IsNullOrWhiteSpace($g.UPN)) { $g.UPN } elseif (-not [string]::IsNullOrWhiteSpace($g.GuestEmail)) { $g.GuestEmail } else { "" }
                    $displayName = ConvertTo-HtmlEncodedString $dName
                    $upn = ConvertTo-HtmlEncodedString $uName
                    $risk = ConvertTo-HtmlEncodedString $g.RiskLevel
                    $color = Get-RiskColor $risk
                    # Since Guests don't have OrphanType, we just show 'Guest' or 'Invited' as their status.
                    $guestRows += "<tr><td>$displayName</td><td>$upn</td><td>Guest</td><td style='color:$color; font-weight:bold;'>$risk</td></tr>"
                }
            } else {
                $guestRows = "<tr><td colspan='4'>No high-risk guests found.</td></tr>"
            }

            # Generate Privileged Users Table Rows
            $privilegedRows = ""
            if ($null -ne $PrivilegedUsers -and $PrivilegedUsers.Count -gt 0) {
                foreach ($p in $PrivilegedUsers) {
                    $upn = ConvertTo-HtmlEncodedString $p.UPN
                    $siteCount = [int]$p.SiteCount
                    $sitesStr = if ($p.Sites -is [array] -or $p.Sites -is [System.Collections.ICollection]) { $p.Sites -join ", " } else { [string]$p.Sites }
                    $sites = ConvertTo-HtmlEncodedString $sitesStr
                    $sites = "<div class='scrollable-cell'>$sites</div>"
                    $sourcesStr = if ($p.PermissionSources -is [array] -or $p.PermissionSources -is [System.Collections.ICollection]) { $p.PermissionSources -join ", " } else { [string]$p.PermissionSources }
                    $sources = ConvertTo-HtmlEncodedString $sourcesStr
                    $sources = "<div class='scrollable-cell'>$sources</div>"
                    $privilegedRows += "<tr><td>$upn</td><td>$siteCount</td><td>$sites</td><td>$sources</td></tr>"
                }
            } else {
                $privilegedRows = "<tr><td colspan='4'>No privileged users found.</td></tr>"
            }

            # Generate Over-Permissioned Users Table Rows
            $overPermissionedRows = ""
            if ($null -ne $OverPermissionedUsers -and $OverPermissionedUsers.Count -gt 0) {
                foreach ($op in $OverPermissionedUsers) {
                    $upn = ConvertTo-HtmlEncodedString $op.UPN
                    $fc = [int]$op.FullControlCount
                    $edit = [int]$op.EditCount
                    $read = [int]$op.ReadCount
                    $eas = [int]$op.EAS
                    $badge = if ($op.IsRedAlert) { "<span style='color:#dc3545; font-weight:bold;'>RED ALERT</span>" } else { "<span style='color:#28a745;'>Normal</span>" }
                    $overPermissionedRows += "<tr><td>$upn</td><td>$fc</td><td>$edit</td><td>$read</td><td>$eas</td><td>$badge</td></tr>"
                }
            } else {
                $overPermissionedRows = "<tr><td colspan='6'>No over-permissioned users found.</td></tr>"
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
    <meta http-equiv="Content-Security-Policy" content="default-src 'self' 'unsafe-inline';">
    <title>SPClean - Permission Health Dashboard v1.5</title>
    <style>
        * { box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f4f7f6; margin: 0; padding: 20px; color: #333; }
        .container { max-width: 1200px; margin: auto; }
        h1 { text-align: center; color: #2c3e50; margin-bottom: 30px; }
        
        .kpi-container { display: flex; justify-content: space-between; margin-bottom: 20px; flex-wrap: wrap; }
        .kpi-card { background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); width: 22%; text-align: center; margin-bottom: 10px; box-sizing: border-box; }
        .kpi-card h3 { margin: 0 0 10px 0; font-size: 1.2em; color: #7f8c8d; }
        .kpi-card .value { font-size: 2em; font-weight: bold; color: #2980b9; }

        .score-card { background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); text-align: center; margin-bottom: 20px; box-sizing: border-box; position: relative; }
        .score-circle { 
            width: 150px; height: 150px; border-radius: 50%; 
            background: conic-gradient($scoreColor $($score)%, #e0e0e0 0); 
            display: flex; align-items: center; justify-content: center; 
            margin: auto; font-size: 2em; font-weight: bold; color: #333;
        }
        .score-inner { width: 120px; height: 120px; border-radius: 50%; background: #fff; display: flex; align-items: center; justify-content: center; }

        .score-btn {
            margin-top: 15px; padding: 8px 16px; background-color: #0078d4; color: #fff; border: none; border-radius: 4px; cursor: pointer; font-size: 0.9em;
        }
        .score-btn:hover { background-color: #005a9e; }

        /* Modal CSS */
        .modal {
            display: none; position: fixed; z-index: 1000; left: 0; top: 0; width: 100%; height: 100%; overflow: auto; background-color: rgba(0,0,0,0.5);
        }
        .modal-content {
            background-color: #fefefe; margin: 15% auto; padding: 20px; border: 1px solid #888; width: 80%; max-width: 500px; border-radius: 8px;
        }
        .close { color: #aaa; float: right; font-size: 28px; font-weight: bold; cursor: pointer; }
        .close:hover, .close:focus { color: black; text-decoration: none; cursor: pointer; }

        .tables-container { display: flex; flex-direction: column; }
        .data-table-wrap { width: 100%; background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); margin-bottom: 20px; box-sizing: border-box; overflow-x: auto; }
        .data-table-wrap h3 { margin-top: 0; color: #34495e; border-bottom: 2px solid #ecf0f1; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; table-layout: fixed; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; word-wrap: break-word; word-break: break-word; overflow-wrap: break-word; vertical-align: top; }
        th { background-color: #f8f9fa; color: #495057; position: relative; }

        /* Custom Table Column Widths */
        .orphan-table th:nth-child(1) { width: 20%; }
        .orphan-table th:nth-child(2) { width: 25%; }
        .orphan-table th:nth-child(3) { width: 15%; }
        .orphan-table th:nth-child(4) { width: 30%; }
        .orphan-table th:nth-child(5) { width: 10%; }
        
        .guest-table th:nth-child(1) { width: 30%; }
        .guest-table th:nth-child(2) { width: 40%; }
        .guest-table th:nth-child(3) { width: 15%; }
        .guest-table th:nth-child(4) { width: 15%; }

        .priv-table th:nth-child(1) { width: 25%; }
        .priv-table th:nth-child(2) { width: 10%; }
        .priv-table th:nth-child(3) { width: 50%; }
        .priv-table th:nth-child(4) { width: 15%; }

        .scrollable-cell { max-height: 120px; overflow-y: auto; display: block; padding-right: 5px; }

        /* Tooltip CSS */
        .tooltip-icon {
            display: inline-block; width: 18px; height: 18px; line-height: 18px; text-align: center; border-radius: 50%; background-color: #0078d4; color: white; font-size: 12px; font-weight: bold; cursor: help; margin-left: 5px; position: relative;
        }
        .tooltip-text {
            visibility: hidden; width: 250px; background-color: #333; color: #fff; text-align: left; border-radius: 6px; padding: 10px; position: absolute; z-index: 1; bottom: 125%; left: 50%; margin-left: -125px; opacity: 0; transition: opacity 0.3s; font-size: 0.9em; font-weight: normal; box-shadow: 0 4px 8px rgba(0,0,0,0.2);
        }
        .tooltip-text::after { content: ""; position: absolute; top: 100%; left: 50%; margin-left: -5px; border-width: 5px; border-style: solid; border-color: #333 transparent transparent transparent; }
        .tooltip-icon:hover .tooltip-text { visibility: visible; opacity: 1; }

        @media (max-width: 768px) {
            .kpi-card { width: 48%; }
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
            <button id="scoreBtn" class="score-btn">How is this calculated?</button>
        </div>

        <!-- Score Modal -->
        <div id="scoreModal" class="modal">
            <div class="modal-content">
                <span class="close">&times;</span>
                <h2>Permission Health Score Logic</h2>
                <p>The Permission Health Score begins at <strong>100</strong> and deducts points based on identified risks:</p>
                <ul>
                    <li><strong>-2 points</strong> for each High Risk User.</li>
                    <li><strong>-1 point</strong> for each Orphaned User.</li>
                </ul>
                <p><strong>Formula:</strong></p>
                <code style="background: #f4f4f4; padding: 5px; border-radius: 3px; display: block;">Score = 100 - (HighRiskUsers * 2) - (TotalOrphaned * 1)</code>
                <p><em>Note: The minimum score is 0.</em></p>
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
                <table class="orphan-table">
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>UPN</th>
                            <th>Status</th>
                            <th>Sites Found</th>
                            <th>Risk Level 
                                <span class="tooltip-icon">?<span class="tooltip-text"><strong>HIGH:</strong> Deleted/Disabled with direct permissions.<br><strong>MEDIUM:</strong> SoftDeleted or Disabled without perms.<br><strong>LOW:</strong> Deleted with no permissions.</span></span>
                            </th>
                        </tr>
                    </thead>
                    <tbody>
                        $orphanedRows
                    </tbody>
                </table>
            </div>

            <div class="data-table-wrap">
                <h3>Top High-Risk Guests</h3>
                <table class="guest-table">
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>UPN</th>
                            <th>Status</th>
                            <th>Risk Level
                                <span class="tooltip-icon">?<span class="tooltip-text"><strong>HIGH:</strong> Full Control/Owner OR inactive > 180 days.<br><strong>MEDIUM:</strong> Edit/Write OR inactive > 90 days.<br><strong>LOW:</strong> Read and recently active.</span></span>
                            </th>
                        </tr>
                    </thead>
                    <tbody>
                        $guestRows
                    </tbody>
                </table>
            </div>

            <div class="data-table-wrap">
                <h3>Top Privileged Users</h3>
                <table class="priv-table">
                    <thead>
                        <tr><th>UPN</th><th>Site Count</th><th>Sites</th><th>Permission Sources</th></tr>
                    </thead>
                    <tbody>
                        $privilegedRows
                    </tbody>
                </table>
            </div>

            <div class="data-table-wrap">
                <h3>Over-Permissioned Users (EAS)</h3>
                <table class="overperm-table">
                    <thead>
                        <tr><th>UPN</th><th>Full Control Count</th><th>Edit Count</th><th>Read Count</th><th>EAS Score</th><th>Red Alert Badge</th></tr>
                    </thead>
                    <tbody>
                        $overPermissionedRows
                    </tbody>
                </table>
            </div>
        </div>
    </div>
    
    <script>
        // Modal Script
        var modal = document.getElementById("scoreModal");
        var btn = document.getElementById("scoreBtn");
        var span = document.getElementsByClassName("close")[0];

        btn.onclick = function() {
            modal.style.display = "block";
        }
        span.onclick = function() {
            modal.style.display = "none";
        }
        window.onclick = function(event) {
            if (event.target == modal) {
                modal.style.display = "none";
            }
        }
    </script>
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
