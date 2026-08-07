Import-Module .\SPClean.psd1 -Force
$tenantName = 'icclabvn.onmicrosoft.com'
$clientId = 'eecf892a-44c3-48fe-aa2f-b9e332dda328'
$thumbprint = 'FCC7E9F8AB71338B51E2DF77F17B903C2342C53A'

$conn = Connect-SPCTenant -TenantName $tenantName -AuthMethod AppOnly -ClientId $clientId -CertificateThumbprint $thumbprint -ErrorAction Stop

$guests = @(Get-SPCGuestAccess -ErrorAction Stop)
$privileged = @(Get-SPCPrivilegedUser -ClientId $clientId -Thumbprint $thumbprint -Tenant $tenantName -ErrorAction Stop)
$overPermissioned = @(Get-SPCOverPermissionedUser -ClientId $clientId -Thumbprint $thumbprint -Tenant $tenantName -ErrorAction Stop)

. .\Private\New-SPCDashboardHtmlInternal.ps1

$htmlPath = ".\ReportTests\Sample_Phase1_Dashboard.html"
$highRiskGuests = @($guests | Where-Object { $_.RiskLevel -eq 'HIGH' })

$graphToken = $conn.GraphAccessToken
$headers = @{ "Authorization" = "Bearer $graphToken"; "ConsistencyLevel" = "eventual" }
$response = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users?`$count=true" -Headers $headers -ErrorAction SilentlyContinue
$totalUsers = $response.'@odata.count'
if ($null -eq $totalUsers) { $totalUsers = 0 }

$orphans = @(Get-SPCOrphanedUser -AllSites -IncludeGuests -IncludeDisabled -ErrorAction Stop)
$highRiskOrphans = @($orphans | Where-Object { $_.RiskLevel -eq 'HIGH' })

New-SPCDashboardHtmlInternal -OutputPath $htmlPath -TotalUsers $totalUsers -TotalGuests $guests.Count -TotalOrphaned $orphans.Count -HighRiskUsers ($highRiskGuests.Count + $highRiskOrphans.Count) -OrphanedUsersList $orphans -TopHighRiskGuestsList $highRiskGuests -PrivilegedUsers $privileged -OverPermissionedUsers $overPermissioned

Disconnect-SPCTenant
