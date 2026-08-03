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
    
    if ($orphans) {
        $csvPath = "D:\Project\SPClean\ReportTests\OrphanedUsersReport_v2.csv"
        $exportData = $orphans | ForEach-Object {
            $row = $_ | Select-Object *
            if ($row.GroupMemberships -is [array]) {
                $row.GroupMemberships = $row.GroupMemberships -join ', '
            }
            $row
        }
        $exportData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Exported orphaned users to $csvPath"
    }

    Write-Host "Running Get-SPCGuestAccess scan..."
    "Scanning guest access..." | Out-File -FilePath $logFile -Append
    $guests = @(Get-SPCGuestAccess -ErrorAction SilentlyContinue)
    "Guests found: $($guests.Count)" | Out-File -FilePath $logFile -Append

    Write-Host "Running Get-SPCPrivilegedUser scan..."
    "Scanning privileged users..." | Out-File -FilePath $logFile -Append
    $privileged = @(Get-SPCPrivilegedUser -ClientId $ClientId -Thumbprint $Thumbprint -Tenant $TenantName -ErrorAction SilentlyContinue)
    "Privileged users found: $($privileged.Count)" | Out-File -FilePath $logFile -Append

    Write-Host "Running Get-SPCOverPermissionedUser scan..."
    "Scanning over-permissioned users..." | Out-File -FilePath $logFile -Append
    $overPermissioned = @(Get-SPCOverPermissionedUser -ClientId $ClientId -Thumbprint $Thumbprint -Tenant $TenantName -ErrorAction SilentlyContinue)
    "Over-permissioned users found: $($overPermissioned.Count)" | Out-File -FilePath $logFile -Append

    Write-Host "Running Get-SPCMismatchUser scan..."
    "Scanning mismatch users..." | Out-File -FilePath $logFile -Append
    $mismatches = @(Get-SPCMismatchUser -AllSites -ErrorAction SilentlyContinue)
    "Mismatches found: $($mismatches.Count)" | Out-File -FilePath $logFile -Append

    # Calculate summary metrics
    $totalOrphaned = $orphans.Count
    $totalGuests = $guests.Count
    $highRiskOrphans = ($orphans | Where-Object { $_.RiskLevel -eq 'HIGH' }).Count
    $highRiskGuests = ($guests | Where-Object { $_.RiskLevel -eq 'HIGH' }).Count
    $highRiskUsers = $highRiskOrphans + $highRiskGuests
    $topHighRiskGuestsList = @($guests | Where-Object { $_.RiskLevel -eq 'HIGH' })

    $allUpns = @()
    if ($orphans) { $allUpns += $orphans.UPN }
    if ($guests) { $allUpns += $guests.GuestEmail }
    if ($privileged) { $allUpns += $privileged.UPN }
    if ($overPermissioned) { $allUpns += $overPermissioned.UPN }
    if ($mismatches) { $allUpns += $mismatches.UPN }

    $totalUsers = ($allUpns | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -Unique).Count

    Write-Host "Generating HTML Dashboard at $OutputPath via New-SPCDashboardHtmlInternal..."
    "Generating HTML dashboard via New-SPCDashboardHtmlInternal..." | Out-File -FilePath $logFile -Append

    if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

    . "D:\Project\SPClean\Private\New-SPCDashboardHtmlInternal.ps1"
    New-SPCDashboardHtmlInternal `
        -OutputPath $OutputPath `
        -TotalUsers $totalUsers `
        -TotalGuests $totalGuests `
        -TotalOrphaned $totalOrphaned `
        -HighRiskUsers $highRiskUsers `
        -OrphanedUsersList $orphans `
        -TopHighRiskGuestsList $topHighRiskGuestsList `
        -PrivilegedUsers $privileged `
        -OverPermissionedUsers $overPermissioned

    "Dashboard HTML generated successfully at $OutputPath" | Out-File -FilePath $logFile -Append
    Write-Host "Scan and Dashboard generation completed successfully!"
} catch {
    "ERROR during live scan: $_" | Out-File -FilePath $logFile -Append
    throw $_
}
