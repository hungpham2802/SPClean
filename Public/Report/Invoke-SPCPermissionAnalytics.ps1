function Invoke-SPCPermissionAnalytics {
    <#
    .SYNOPSIS
        Performs tenant-wide permission analytics and exports structured metrics and health score.
    .DESCRIPTION
        Aggregates orphaned users, external guest risks, privileged/over-permissioned accounts,
        broken inheritance, and unowned sites to calculate a global Permission Health Score.
    .PARAMETER OutputPath
        Target JSON output file path. Defaults to .\Analytics.json.
    .PARAMETER BrokenInheritanceThreshold
        Threshold of unique broken permission scopes to flag a site. Defaults to 1000.
    .OUTPUTS
        [PSCustomObject]
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = ".\Analytics.json",

        [Parameter(Mandatory = $false)]
        [int]$BrokenInheritanceThreshold = 1000,

        [Parameter(Mandatory = $false)]
        [switch]$AddTempSiteCollectionAdmin
    )

    begin {
        Write-Verbose "Starting Invoke-SPCPermissionAnalytics"
        Test-SPCConnection
        $analyticsResult = $null
    }

    process {
        $scanParams = @{}
        if ($AddTempSiteCollectionAdmin) {
            $scanParams['AddTempSiteCollectionAdmin'] = $true
        }

        Write-Verbose "Running scans for Analytics..."
        $orphans = @(Get-SPCOrphanedUser -AllSites -IncludeGuests -IncludeDisabled @scanParams)
        $OrphanedUserCount = $orphans.Count

        $guests = @(Get-SPCGuestAccess -ErrorAction SilentlyContinue)
        $HighRiskGuestCount = @($guests | Where-Object { $_.RiskLevel -eq 'HIGH' }).Count

        $overPermissioned = @(Get-SPCOverPermissionedUser @scanParams -ErrorAction SilentlyContinue)
        $OverPermissionedUserCount = $overPermissioned.Count

        $tenantSites = Get-PnPTenantSite -Connection $script:SPCContext.PnPContext -ErrorAction SilentlyContinue
        
        $BrokenInheritanceSiteCount = 0
        $MissingOwnerSiteCount      = 0

        foreach ($site in $tenantSites) {
            if ($site.Template -like 'REDIRECTSITE#*') { continue }
            
            # Missing Owner check
            if ([string]::IsNullOrWhiteSpace($site.Owner)) {
                $MissingOwnerSiteCount++
            }

            # Broken inheritance check
            try {
                $broken = Get-SPCBrokenInheritance -SiteUrl $site.Url @scanParams -ErrorAction SilentlyContinue
                if ($broken.UniqueScopes -gt $BrokenInheritanceThreshold) {
                    $BrokenInheritanceSiteCount++
                }
            } catch {
                # Ignore errors on individual sites
            }
        }

        # Calculate Score using approved Measure-SPCScoreInternal
        $scoreResult = Measure-SPCScoreInternal `
            -OrphanedUserCount $OrphanedUserCount `
            -HighRiskGuestCount $HighRiskGuestCount `
            -OverPermissionedUserCount $OverPermissionedUserCount `
            -BrokenInheritanceSiteCount $BrokenInheritanceSiteCount `
            -MissingOwnerSiteCount $MissingOwnerSiteCount

        $analyticsResult = [PSCustomObject]@{
            TenantName  = $script:SPCContext.TenantName
            GeneratedAt = (Get-Date -Format 'o')
            Metrics     = [PSCustomObject]@{
                OrphanedUserCount          = $OrphanedUserCount
                HighRiskGuestCount         = $HighRiskGuestCount
                OverPermissionedUserCount  = $OverPermissionedUserCount
                BrokenInheritanceSiteCount = $BrokenInheritanceSiteCount
                MissingOwnerSiteCount      = $MissingOwnerSiteCount
            }
            HealthScore = $scoreResult
        }

        $analyticsResult | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8 -Force
        
        Write-Verbose "Analytics JSON generated at $OutputPath"
    }

    end {
        Write-Information "Analytics generation completed successfully. Output saved to $OutputPath" -InformationAction Continue
        return $analyticsResult
    }
}
