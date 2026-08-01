# D:\Project\SPClean\ReportTests\RunLiveScanAndDashboard.ps1
param(
    [string]$TenantName = "icclabvn.onmicrosoft.com",
    [string]$ClientId = "eecf892a-44c3-48fe-aa2f-b9e332dda328",
    [string]$Thumbprint = "FCC7E9F8AB71338B51E2DF77F17B903C2342C53A",
    [string]$OutputPath = "D:\Project\SPClean\ReportTests\TestDashboard.html"
)

$ErrorActionPreference = 'Stop'
$logFile = "D:\Project\SPClean\ReportTests\ScanExecution.log"
"Starting Genuine Live Tenant Scan at $(Get-Date -Format 'o')" | Out-File -FilePath $logFile -Encoding utf8

try {
    Write-Host "Importing SPClean module..."
    Import-Module D:\Project\SPClean\SPClean.psd1 -Force

    Write-Host "Connecting to tenant $TenantName with certificate..."
    "Connecting to tenant $TenantName..." | Out-File -FilePath $logFile -Append

    $conn = Connect-SPCTenant -TenantName $TenantName `
                              -AuthMethod AppOnly `
                              -ClientId $ClientId `
                              -CertificateThumbprint $Thumbprint

    "Connected successfully. AuthMethod: $($conn.AuthMethod)" | Out-File -FilePath $logFile -Append

    Write-Host "Running Get-SPCOrphanedUser scan across all sites..."
    "Scanning orphaned users..." | Out-File -FilePath $logFile -Append
    $orphans = @(Get-SPCOrphanedUser -AllSites -IncludeGuests -IncludeDisabled -ErrorAction SilentlyContinue)
    "Orphans found: $($orphans.Count)" | Out-File -FilePath $logFile -Append

    Write-Host "Running Get-SPCGuestAccess scan..."
    "Scanning guest access..." | Out-File -FilePath $logFile -Append
    $guests = @(Get-SPCGuestAccess -ErrorAction SilentlyContinue)
    "Guests found: $($guests.Count)" | Out-File -FilePath $logFile -Append

    Write-Host "Running Get-SPCPrivilegedUser scan..."
    "Scanning privileged users..." | Out-File -FilePath $logFile -Append
    $privileged = @(Get-SPCPrivilegedUser -ErrorAction SilentlyContinue)
    "Privileged users found: $($privileged.Count)" | Out-File -FilePath $logFile -Append

    Write-Host "Running Get-SPCMismatchUser scan..."
    "Scanning mismatch users..." | Out-File -FilePath $logFile -Append
    $mismatches = @(Get-SPCMismatchUser -AllSites -ErrorAction SilentlyContinue)
    "Mismatches found: $($mismatches.Count)" | Out-File -FilePath $logFile -Append

    # Pipe genuine live scan results directly to Export-SPCReport without any synthetic fallbacks
    $reportItems = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($o in $orphans) {
        $reportItems.Add($o)
    }

    # Map genuine guest records if not already in orphans list
    foreach ($g in $guests) {
        $alreadyInList = $reportItems | Where-Object { $_.UPN -eq $g.GuestEmail -or $_.Email -eq $g.GuestEmail }
        if (-not $alreadyInList) {
            $reportItems.Add([PSCustomObject][ordered]@{
                SiteUrl              = "https://icclabvn.sharepoint.com"
                SiteTitle            = "icclabvn SharePoint"
                UserId               = 0
                LoginName            = "i:0#.f|membership|$($g.GuestEmail)"
                DisplayName          = $g.GuestEmail
                Email                = $g.GuestEmail
                UPN                  = $g.GuestEmail
                OrphanType           = "GuestOrphaned"
                RiskLevel            = $g.RiskLevel
                HasDirectPermissions = ($g.PermissionLevel -ne 'Read')
                GroupMemberships     = @("Guest Access")
                LastActivityDate     = if ($g.LastAccess -ne 'N/A') { $g.LastAccess } else { $null }
                DetectedAt           = (Get-Date).ToUniversalTime()
            })
        }
    }

    # Map genuine mismatch records if any
    foreach ($m in $mismatches) {
        if ($m.Status -ne 'Healthy') {
            $alreadyInList = $reportItems | Where-Object { $_.SiteUrl -eq $m.SiteUrl -and $_.UPN -eq $m.UPN }
            if (-not $alreadyInList) {
                $reportItems.Add([PSCustomObject][ordered]@{
                    SiteUrl              = $m.SiteUrl
                    SiteTitle            = $m.SiteTitle
                    UserId               = $m.UserId
                    LoginName            = $m.LoginName
                    DisplayName          = $m.DisplayName
                    Email                = $m.Email
                    UPN                  = $m.UPN
                    OrphanType           = $m.Status
                    RiskLevel            = if ($m.Status -eq 'GuestMismatch') { 'HIGH' } else { 'MEDIUM' }
                    HasDirectPermissions = $false
                    GroupMemberships     = @()
                    LastActivityDate     = $null
                    DetectedAt           = $m.DetectedAt
                })
            }
        }
    }

    $reportInput = @($reportItems)

    Write-Host "Generating HTML Dashboard at $OutputPath with $($reportInput.Count) genuine live scan records..."
    "Generating HTML report for $($reportInput.Count) records..." | Out-File -FilePath $logFile -Append

    if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

    if ($reportInput.Count -gt 0) {
        $reportResult = $reportInput | Export-SPCReport -Format HTML -IncludeSummary -Path $OutputPath
        "HTML report generated at $($reportResult.FilePath). Total reported: $($reportResult.TotalOrphansReported)" | Out-File -FilePath $logFile -Append
    } else {
        "No risk records found during live scan." | Out-File -FilePath $logFile -Append
    }

    Write-Host "Scan completed successfully!"
} catch {
    "ERROR during live scan: $_" | Out-File -FilePath $logFile -Append
    throw $_
}
