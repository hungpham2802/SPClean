function Invoke-SPCPermissionAnalyticsV2 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [string]$OutputPath = ".\AnalyticsV2.json"
    )

    begin {
        Write-Verbose "Starting Invoke-SPCPermissionAnalyticsV2"
        Test-SPCConnection
    }

    process {

        Write-Verbose "Running scans for Analytics V2..."
        $orphans = @(Get-SPCOrphanedUser -AllSites -IncludeGuests -IncludeDisabled)
        $OrphanedUserCount = $orphans.Count

        $guests = @(Get-SPCGuestAccess -ErrorAction SilentlyContinue)
        $HighRiskGuestCount = @($guests | Where-Object { $_.RiskLevel -eq 'HIGH' }).Count

        $overPermissioned = @(Get-SPCOverPermissionedUser -ErrorAction SilentlyContinue)
        $OverPermissionedUserCount = $overPermissioned.Count

        # For Analytics V2, we also need to check Broken Inheritance and Missing Owners.
        # Enumerate sites
        $tenantSites = Get-PnPTenantSite -Connection $script:SPCContext.PnPContext -ErrorAction SilentlyContinue
        
        $BrokenInheritanceSiteCount = 0
        $MissingOwnerSiteCount = 0

        foreach ($site in $tenantSites) {
            if ($site.Template -like 'REDIRECTSITE#*') { continue }
            
            # Missing Owner check
            if ([string]::IsNullOrWhiteSpace($site.Owner)) {
                $MissingOwnerSiteCount++
            }

            # Broken inheritance check
            try {
                $broken = Get-SPCBrokenInheritance -SiteUrl $site.Url -ErrorAction SilentlyContinue
                if ($broken.UniqueScopes -gt 1000) {
                    $BrokenInheritanceSiteCount++
                }
            } catch {
                # Ignore errors on individual sites
            }
        }

        # Calculate Score
        $scoreResult = Get-SPCPermissionHealthScore `
            -OrphanedUserCount $OrphanedUserCount `
            -HighRiskGuestCount $HighRiskGuestCount `
            -OverPermissionedUserCount $OverPermissionedUserCount `
            -BrokenInheritanceSiteCount $BrokenInheritanceSiteCount `
            -MissingOwnerSiteCount $MissingOwnerSiteCount

        $exportData = [PSCustomObject]@{
            TenantName = $script:SPCContext.TenantName
            GeneratedAt = (Get-Date -Format 'o')
            Metrics = [PSCustomObject]@{
                OrphanedUserCount = $OrphanedUserCount
                HighRiskGuestCount = $HighRiskGuestCount
                OverPermissionedUserCount = $OverPermissionedUserCount
                BrokenInheritanceSiteCount = $BrokenInheritanceSiteCount
                MissingOwnerSiteCount = $MissingOwnerSiteCount
            }
            HealthScore = $scoreResult
        }

        $exportData | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8 -Force
        
        Write-Verbose "Analytics V2 JSON generated at $OutputPath"
        return $exportData
    }
}
