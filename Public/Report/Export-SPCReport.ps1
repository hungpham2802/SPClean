function Export-SPCReport {
    <#
    .SYNOPSIS
        Generates a formatted report from [SPC.OrphanedUser] pipeline input per SRS 3.3.1.
    .DESCRIPTION
        Accepts orphaned user objects and writes a CSV, HTML, or JSON file.
        HTML output is self-contained with inline CSS/JS, color-coded risk badges,
        sortable columns, and an optional summary card.
    .PARAMETER InputObject
        One or more [SPC.OrphanedUser] objects. Accepts pipeline input.
    .PARAMETER Format
        Output format: 'CSV' (default), 'HTML', or 'JSON'. Case-insensitive.
    .PARAMETER OutputPath
        Destination file path. Defaults to .\SPClean_OrphanedUsers_{TenantName}_{yyyyMMddHHmm}.{ext}.
    .PARAMETER GroupBy
        Group results by 'Site' (default), 'RiskLevel', or 'OrphanType'.
    .PARAMETER IncludeSummary
        Prepend a summary: total orphans, breakdown by RiskLevel and OrphanType, sites scanned.
    .PARAMETER PassThru
        Pass input objects through to the pipeline after writing the file.
    .EXAMPLE
        Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR' | Export-SPCReport -Format HTML -IncludeSummary
    .EXAMPLE
        $orphans | Export-SPCReport -Format CSV -GroupBy RiskLevel -OutputPath C:\reports\orphans.csv
    .OUTPUTS
        SPC.ReportResult
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]] $InputObject,

        [Parameter()]
        [ValidateSet('CSV', 'HTML', 'JSON')]
        [string] $Format = 'CSV',

        [Parameter()]
        [Alias('Path')]
        [string] $OutputPath,

        [Parameter()]
        [ValidateSet('Site', 'RiskLevel', 'OrphanType')]
        [string] $GroupBy = 'Site',

        [Parameter()]
        [switch] $IncludeSummary,

        [Parameter()]
        [switch] $PassThru
    )

    begin {
        Test-SPCConnection
        if ($Format -ieq 'HTML') {
            Assert-SPCProLicense -Feature 'HTMLReport'
        }
        $collected = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        foreach ($item in $InputObject) { $collected.Add($item) }
    }

    end {
        if ($collected.Count -eq 0) {
            Write-Warning 'Export-SPCReport: No input objects received.'
            return
        }

        $Format      = $Format.ToUpper()
        $ext         = switch ($Format) { 'CSV' { 'csv' } 'HTML' { 'html' } 'JSON' { 'json' } }
        $tenantName  = if ($script:SPCContext) { $script:SPCContext.TenantName } else { 'unknown' }
        $generatedAt = (Get-Date).ToUniversalTime()
        $moduleVer   = (Get-Module SPClean -ErrorAction SilentlyContinue).Version
        $moduleVer   = if ($moduleVer) { $moduleVer.ToString() } else { '1.0.0' }

        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $ts         = $generatedAt.ToString('yyyyMMddHHmm')
            $OutputPath = ".\SPClean_OrphanedUsers_${tenantName}_${ts}.${ext}"
        }
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

        $groupField = switch ($GroupBy) {
            'Site'       { 'SiteUrl'    }
            'RiskLevel'  { 'RiskLevel'  }
            'OrphanType' { 'OrphanType' }
        }
        $sorted = @($collected | Sort-Object -Property $groupField)

        $csvEsc = {
            param($v)
            $s = if ($null -ne $v) { [string]$v } else { '' }
            if ($s -match '[,"\r\n]') { '"' + $s.Replace('"', '""') + '"' } else { $s }
        }

        switch ($Format) {
            'CSV' {
                $enc = [System.Text.UTF8Encoding]::new($true)   # BOM required for Excel compatibility
                $sb  = [System.Text.StringBuilder]::new()
                [void]$sb.AppendLine('SiteUrl,SiteTitle,DisplayName,Email,UPN,OrphanType,RiskLevel,HasDirectPermissions,GroupMemberships,LastActivityDate,DetectedAt')
                foreach ($item in $sorted) {
                    $grp  = if ($item.GroupMemberships) { $item.GroupMemberships -join ';' } else { '' }
                    $last = if ($item.LastActivityDate) { ([datetime]$item.LastActivityDate).ToUniversalTime().ToString('o') } else { '' }
                    $det  = if ($item.DetectedAt)       { ([datetime]$item.DetectedAt).ToUniversalTime().ToString('o') }       else { '' }
                    $row  = @(
                        (& $csvEsc $item.SiteUrl),
                        (& $csvEsc $item.SiteTitle),
                        (& $csvEsc $item.DisplayName),
                        (& $csvEsc $item.Email),
                        (& $csvEsc $item.UPN),
                        $item.OrphanType,
                        $item.RiskLevel,
                        ([string]$item.HasDirectPermissions).ToLower(),
                        (& $csvEsc $grp),
                        $last,
                        $det
                    )
                    [void]$sb.AppendLine($row -join ',')
                }
                [System.IO.File]::WriteAllText($resolvedPath, $sb.ToString(), $enc)
            }

            'HTML' {
                $he = {
                    param($v)
                    $s = if ($null -ne $v) { [string]$v } else { '' }
                    $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
                }

                $summHtml = ''
                if ($IncludeSummary) {
                    $byRisk = @($collected | Group-Object RiskLevel  | Sort-Object Name)
                    $byType = @($collected | Group-Object OrphanType | Sort-Object Name)
                    $sites  = ($collected | Select-Object -ExpandProperty SiteUrl -Unique).Count

                    $rCards = ($byRisk | ForEach-Object {
                        $col = switch ($_.Name) {
                            'HIGH'   { '#dc3545' }
                            'MEDIUM' { '#ffc107' }
                            'LOW'    { '#28a745' }
                            default  { '#6c757d' }
                        }
                        "<div class=`"sc`"><div class=`"sv`" style=`"color:$col`">$($_.Count)</div><div class=`"sl`">$($_.Name)</div></div>"
                    }) -join ''
                    $tCards = ($byType | ForEach-Object {
                        "<div class=`"sc`"><div class=`"sv`">$($_.Count)</div><div class=`"sl`">$(& $he $_.Name)</div></div>"
                    }) -join ''

                    $summHtml = @"
<div class="sum">
  <div class="sc main"><div class="sv">$($collected.Count)</div><div class="sl">Total Orphans</div></div>
  <div class="sc main"><div class="sv">$sites</div><div class="sl">Sites Scanned</div></div>
  $rCards
  $tCards
</div>
"@
                }

                $tbSb    = [System.Text.StringBuilder]::new()
                $prevGrp = $null
                foreach ($item in $sorted) {
                    $curGrp = $item.$groupField
                    if ($curGrp -ne $prevGrp) {
                        [void]$tbSb.Append("<tr class=`"gh`"><td colspan=`"11`">$(& $he $curGrp)</td></tr>`n")
                        $prevGrp = $curGrp
                    }
                    $badge = "<span class=`"b b-$($item.RiskLevel)`">$(& $he $item.RiskLevel)</span>"
                    $grp   = if ($item.GroupMemberships) { & $he ($item.GroupMemberships -join '; ') } else { '' }
                    $last  = if ($item.LastActivityDate) { & $he (([datetime]$item.LastActivityDate).ToUniversalTime().ToString('yyyy-MM-dd')) } else { '' }
                    $det   = if ($item.DetectedAt)       { & $he (([datetime]$item.DetectedAt).ToUniversalTime().ToString('yyyy-MM-dd')) }       else { '' }
                    [void]$tbSb.Append("<tr><td>$(& $he $item.SiteUrl)</td><td>$(& $he $item.SiteTitle)</td><td>$(& $he $item.DisplayName)</td><td>$(& $he $item.Email)</td><td>$(& $he $item.UPN)</td><td>$(& $he $item.OrphanType)</td><td>$badge</td><td>$($item.HasDirectPermissions)</td><td>$grp</td><td>$last</td><td>$det</td></tr>`n")
                }

                $tsStr = $generatedAt.ToString('yyyy-MM-dd HH:mm')
                $html  = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SPClean Report - $tenantName</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#f0f2f5;padding:16px;color:#212529}
h1{font-size:1.35em;margin-bottom:14px}
.sum{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:14px}
.sc{background:#fff;border-radius:8px;padding:10px 16px;box-shadow:0 1px 3px rgba(0,0,0,.1);min-width:90px;text-align:center}
.sc.main .sv{color:#343a40}
.sv{font-size:1.7em;font-weight:700}.sl{font-size:.75em;color:#6c757d;margin-top:2px}
.wrap{overflow-x:auto;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,.1)}
table{width:100%;border-collapse:collapse;background:#fff}
th{background:#343a40;color:#fff;padding:9px 12px;text-align:left;cursor:pointer;white-space:nowrap;user-select:none;font-size:.84em}
th:hover{background:#495057}
td{padding:7px 12px;border-bottom:1px solid #dee2e6;font-size:.84em;word-break:break-word}
tr:last-child td{border-bottom:none}tr:not(.gh):hover td{background:#f8f9fa}
.gh td{background:#e9ecef;font-weight:600;color:#495057;padding:5px 12px;font-size:.80em}
.b{display:inline-block;padding:2px 8px;border-radius:10px;font-size:.76em;font-weight:700;letter-spacing:.3px}
.b-HIGH{background:#dc3545;color:#fff}.b-MEDIUM{background:#ffc107;color:#212529}.b-LOW{background:#28a745;color:#fff}
footer{margin-top:14px;text-align:center;font-size:.76em;color:#6c757d}
@media(max-width:600px){th,td{padding:6px 8px;font-size:.8em}}
</style>
</head>
<body>
<h1>SPClean - Orphaned User Report</h1>
$summHtml
<div class="wrap">
<table id="t">
<thead><tr>
<th>SiteUrl</th><th>SiteTitle</th><th>DisplayName</th><th>Email</th><th>UPN</th>
<th>OrphanType</th><th>RiskLevel</th><th>DirectPerms</th><th>Groups</th>
<th>LastActivity</th><th>DetectedAt</th>
</tr></thead>
<tbody>
$($tbSb.ToString())</tbody>
</table>
</div>
<footer>Generated by SPClean v$moduleVer &bull; Tenant: $tenantName &bull; $tsStr UTC</footer>
<script>
(function(){
var tb=document.querySelector('#t tbody'),ths=document.querySelectorAll('#t th'),dir={};
ths.forEach(function(th,i){
  th.addEventListener('click',function(){
    var asc=dir[i]!==true;dir={};dir[i]=asc;
    ths.forEach(function(h){h.className='';});
    th.className=asc?'asc':'desc';
    Array.from(tb.rows).filter(function(r){return r.classList.contains('gh');}).forEach(function(r){r.parentNode.removeChild(r);});
    var rows=Array.from(tb.rows);
    rows.sort(function(a,b){
      var av=a.cells[i]?a.cells[i].textContent.trim():'';
      var bv=b.cells[i]?b.cells[i].textContent.trim():'';
      return asc?av.localeCompare(bv,undefined,{numeric:true}):bv.localeCompare(av,undefined,{numeric:true});
    });
    rows.forEach(function(r){tb.appendChild(r);});
  });
});
})();
</script>
</body>
</html>
"@
                [System.IO.File]::WriteAllText($resolvedPath, $html, [System.Text.UTF8Encoding]::new($false))
            }

            'JSON' {
                $byGroup  = $sorted | Group-Object -Property $groupField
                $jsonData = @($byGroup | ForEach-Object {
                    [ordered]@{
                        Group = $_.Name
                        Count = $_.Count
                        Items = @($_.Group | Select-Object SiteUrl, SiteTitle, DisplayName, Email, UPN,
                            OrphanType, RiskLevel, HasDirectPermissions, GroupMemberships,
                            LastActivityDate, DetectedAt)
                    }
                })

                $output = if ($IncludeSummary) {
                    [ordered]@{
                        Summary = [ordered]@{
                            TotalOrphans = $collected.Count
                            SitesScanned = ($collected | Select-Object -ExpandProperty SiteUrl -Unique).Count
                            ByRiskLevel  = @($collected | Group-Object RiskLevel  | ForEach-Object { [ordered]@{ RiskLevel  = $_.Name; Count = $_.Count } })
                            ByOrphanType = @($collected | Group-Object OrphanType | ForEach-Object { [ordered]@{ OrphanType = $_.Name; Count = $_.Count } })
                            GeneratedAt  = $generatedAt.ToString('o')
                        }
                        Groups = $jsonData
                    }
                } else {
                    $jsonData
                }
                $jsonText = $output | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($resolvedPath, $jsonText, [System.Text.UTF8Encoding]::new($false))
            }
        }

        Write-Verbose "Export-SPCReport: Wrote $($collected.Count) records to '$resolvedPath'"

        $result = [PSCustomObject][ordered]@{
            FilePath             = $resolvedPath
            Format               = $Format
            TotalOrphansReported = $collected.Count
            GeneratedAt          = $generatedAt
        }
        $result.PSObject.TypeNames.Insert(0, 'SPC.ReportResult')
        $result

        if ($PassThru) { foreach ($item in $collected) { $item } }
    }
}
