function New-SPCStorageDashboardHtmlInternal {
    <#
    .SYNOPSIS
        Generates a 100% self-contained HTML executive ROI dashboard for storage optimization.
    .DESCRIPTION
        Zero external CDN dependencies, embedded CSS and JavaScript, SVG indicators, dynamic ROI slider.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$OutputPath,
        [Parameter(Mandatory)] [PSCustomObject[]]$StorageWasteData,
        [Parameter()] [PSCustomObject[]]$InactiveSiteData,
        [Parameter()] [PSCustomObject[]]$VersionWasteData,
        [Parameter()] [PSCustomObject[]]$PreservationHoldData,
        [Parameter(Mandatory)] [double]$UnitPricePerGB,
        [Parameter()] [string]$CompanyLogoUrl,
        [Parameter()] [string]$ClientName
    )

    $totalTenantUsedMB = ($StorageWasteData | Measure-Object -Property StorageUsedMB -Sum).Sum
    $totalRecycleBinMB = ($StorageWasteData | Measure-Object -Property TotalRecycleBinMB -Sum).Sum
    $totalVersionWasteMB = ($StorageWasteData | Measure-Object -Property VersionWasteMB -Sum).Sum
    $totalInactiveMB = if ($InactiveSiteData) { ($InactiveSiteData | Measure-Object -Property StorageUsedMB -Sum).Sum } else { 0.0 }
    $totalPHLMB = if ($PreservationHoldData) { ($PreservationHoldData | Measure-Object -Property PHLSizeMB -Sum).Sum } else { 0.0 }
    
    $totalWasteMB = $totalRecycleBinMB + $totalVersionWasteMB
    $totalWasteGB = [Math]::Round(($totalWasteMB / 1024), 2)
    $monthlySavings = [Math]::Round(($totalWasteGB * $UnitPricePerGB), 2)
    $annualSavings = [Math]::Round(($monthlySavings * 12), 2)

    $clientDisplay = if ([string]::IsNullOrWhiteSpace($ClientName)) { "M365 Tenant Storage Audit" } else { $ClientName }
    $scanDate = (Get-Date).ToString("MMMM dd, yyyy HH:mm UTC")

    $logoHtml = if (-not [string]::IsNullOrWhiteSpace($CompanyLogoUrl)) {
        "<img src='$CompanyLogoUrl' alt='Company Logo' style='max-height:48px; max-width:200px; object-fit:contain;' />"
    } else {
        ""
    }

    $cleanSites = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($s in $StorageWasteData) {
        $cleanSites.Add([PSCustomObject]@{
            SiteUrl                   = $s.SiteUrl
            SiteTitle                 = $s.SiteTitle
            StorageUsedMB             = $s.StorageUsedMB
            TotalRecycleBinMB         = $s.TotalRecycleBinMB
            VersionWasteMB            = $s.VersionWasteMB
            TotalWasteMB              = $s.TotalWasteMB
            PotentialMonthlySavingUSD = $s.PotentialMonthlySavingUSD
        })
    }

    $jsonData = @{
        totalWasteGB    = $totalWasteGB
        unitPricePerGB  = $UnitPricePerGB
        monthlySavings  = $monthlySavings
        annualSavings   = $annualSavings
        recycleBinMB    = $totalRecycleBinMB
        versionWasteMB  = $totalVersionWasteMB
        inactiveMB      = $totalInactiveMB
        phlMB           = $totalPHLMB
        sites           = $cleanSites
    } | ConvertTo-Json -Depth 5 -Compress

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>SPClean — Storage Optimization & ROI Executive Dashboard</title>
<style>
  :root {
    --bg-dark: #0f172a; --card-bg: #1e293b; --accent: #38bdf8; --accent-green: #22c55e;
    --accent-orange: #f97316; --accent-red: #ef4444; --text-light: #f8fafc; --text-dim: #94a3b8;
    --border-color: #334155;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
  body { background-color: var(--bg-dark); color: var(--text-light); padding: 24px; }
  .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid var(--border-color); padding-bottom: 16px; margin-bottom: 24px; }
  .title-group h1 { font-size: 24px; font-weight: 700; color: var(--text-light); }
  .title-group p { font-size: 14px; color: var(--text-dim); }
  .kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; margin-bottom: 24px; }
  .kpi-card { background: var(--card-bg); padding: 20px; border-radius: 12px; border: 1px solid var(--border-color); }
  .kpi-title { font-size: 13px; color: var(--text-dim); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 8px; }
  .kpi-value { font-size: 28px; font-weight: 700; color: var(--text-light); }
  .kpi-value.green { color: var(--accent-green); }
  .kpi-value.orange { color: var(--accent-orange); }
  .kpi-sub { font-size: 12px; color: var(--text-dim); margin-top: 4px; }
  .dashboard-main { display: grid; grid-template-columns: 2fr 1fr; gap: 24px; margin-bottom: 24px; }
  .card { background: var(--card-bg); padding: 20px; border-radius: 12px; border: 1px solid var(--border-color); }
  .card h2 { font-size: 18px; margin-bottom: 16px; color: var(--accent); }
  .table-wrap { overflow-x: auto; max-height: 400px; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; text-align: left; }
  th, td { padding: 10px 12px; border-bottom: 1px solid var(--border-color); }
  th { background: #0f172a; color: var(--text-dim); font-weight: 600; position: sticky; top: 0; }
  tr:hover { background: #334155; }
  .slider-container { padding: 12px 0; }
  .slider-container input[type=range] { width: 100%; height: 6px; border-radius: 3px; background: var(--border-color); outline: none; }
  .slider-labels { display: flex; justify-content: space-between; font-size: 12px; color: var(--text-dim); margin-top: 8px; }
  .calc-box { background: #0f172a; border-radius: 8px; padding: 16px; margin-top: 16px; text-align: center; }
</style>
</head>
<body>
<div class="header">
  <div class="title-group">
    <h1>SPClean — Storage ROI Executive Dashboard</h1>
    <p>$clientDisplay | Generated: $scanDate</p>
  </div>
  <div>$logoHtml</div>
</div>

<div class="kpi-grid">
  <div class="kpi-card">
    <div class="kpi-title">Total Tenant Storage Used</div>
    <div class="kpi-value">$([Math]::Round($totalTenantUsedMB / 1024, 2)) GB</div>
    <div class="kpi-sub">$($StorageWasteData.Count) Sites Scanned</div>
  </div>
  <div class="kpi-card">
    <div class="kpi-title">Digital Waste Identified</div>
    <div class="kpi-value orange">$totalWasteGB GB</div>
    <div class="kpi-sub">Recycle Bin + Version Sprawl</div>
  </div>
  <div class="kpi-card">
    <div class="kpi-title">Monthly Cost Avoidance</div>
    <div class="kpi-value green">`$$monthlySavings USD</div>
    <div class="kpi-sub">Based on `$$UnitPricePerGB/GB/month</div>
  </div>
  <div class="kpi-card">
    <div class="kpi-title">Annual Projected ROI</div>
    <div class="kpi-value green">`$$annualSavings USD</div>
    <div class="kpi-sub">Net Annualized Savings</div>
  </div>
</div>

<div class="dashboard-main">
  <div class="card">
    <h2>Top Storage Waste Sites</h2>
    <div class="table-wrap">
      <table id="wasteTable">
        <thead>
          <tr>
            <th>Site URL</th>
            <th>Used (MB)</th>
            <th>Recycle Bin (MB)</th>
            <th>Version Waste (MB)</th>
            <th>Total Waste (MB)</th>
            <th>Monthly Saving ($)</th>
          </tr>
        </thead>
        <tbody id="wasteBody">
        </tbody>
      </table>
    </div>
  </div>

  <div class="card">
    <h2>Interactive ROI Calculator</h2>
    <div class="slider-container">
      <label style="font-size:13px; color:var(--text-dim);">Target Remediation Goal: <span id="remediationGoalText" style="color:var(--accent); font-weight:bold;">100%</span></label>
      <input type="range" id="goalSlider" min="10" max="100" value="100" step="5" oninput="updateCalculator(this.value)">
      <div class="slider-labels"><span>10%</span><span>50%</span><span>100%</span></div>
    </div>
    <div class="calc-box">
      <div style="font-size:13px; color:var(--text-dim);">Estimated Annual Savings</div>
      <div id="dynAnnualSavings" style="font-size:32px; font-weight:bold; color:var(--accent-green); margin-top:8px;">`$$annualSavings USD</div>
      <div id="dynStorageFreed" style="font-size:13px; color:var(--accent); margin-top:4px;">$totalWasteGB GB to be freed</div>
    </div>
  </div>
</div>

<script>
  const appData = $jsonData;

  function renderTable() {
    const tbody = document.getElementById('wasteBody');
    tbody.innerHTML = '';
    if (!appData.sites || appData.sites.length === 0) return;
    appData.sites.slice(0, 20).forEach(s => {
      const tr = document.createElement('tr');
      tr.innerHTML = '<td><a href="' + s.SiteUrl + '" target="_blank" style="color:var(--accent);text-decoration:none;">' + s.SiteUrl + '</a></td>' +
        '<td>' + s.StorageUsedMB + '</td>' +
        '<td>' + s.TotalRecycleBinMB + '</td>' +
        '<td>' + s.VersionWasteMB + '</td>' +
        '<td style="font-weight:bold;color:var(--accent-orange);">' + s.TotalWasteMB + '</td>' +
        '<td style="color:var(--accent-green);font-weight:bold;">$' + s.PotentialMonthlySavingUSD + '</td>';
      tbody.appendChild(tr);
    });
  }

  function updateCalculator(val) {
    document.getElementById('remediationGoalText').innerText = val + '%';
    const ratio = val / 100.0;
    const freedGB = (appData.totalWasteGB * ratio).toFixed(2);
    const monthly = (freedGB * appData.unitPricePerGB).toFixed(2);
    const annual = (monthly * 12).toFixed(2);
    document.getElementById('dynAnnualSavings').innerText = '$' + annual + ' USD';
    document.getElementById('dynStorageFreed').innerText = freedGB + ' GB to be freed';
  }

  renderTable();
</script>
</body>
</html>
"@

    $parentDir = Split-Path $OutputPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path $parentDir)) {
        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
    }

    $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
}
