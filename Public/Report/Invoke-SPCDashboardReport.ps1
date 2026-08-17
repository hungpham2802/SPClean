function Invoke-SPCDashboardReport {
    <#
    .SYNOPSIS
        Generates the executive HTML Permission Health Dashboard report (Pro Feature).
    .DESCRIPTION
        Aggregates orphaned users, external guest risks, privileged accounts, and over-permissioned
        users across the tenant and builds an HTML visual dashboard report.
    .PARAMETER OutputPath
        Target file path for the HTML report. Defaults to .\Dashboard.html.
    .OUTPUTS
        [System.IO.FileInfo]
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = ".\Dashboard.html",

        [Parameter(Mandatory = $false)]
        [switch]$AddTempSiteCollectionAdmin
    )

    begin {
        Write-Verbose "Starting Invoke-SPCDashboardReport"
        Test-SPCConnection
        Assert-SPCProLicense -Feature 'DashboardReport'
    }

    process {
        $scanParams = @{}
        if ($AddTempSiteCollectionAdmin) {
            $scanParams['AddTempSiteCollectionAdmin'] = $true
        }

        Write-Verbose "Running Get-SPCOrphanedUser scan across all sites..."
        $orphans = @(Get-SPCOrphanedUser -AllSites -IncludeGuests -IncludeDisabled @scanParams)

        Write-Verbose "Running Get-SPCGuestAccess scan..."
        $guests = @(Get-SPCGuestAccess -ErrorAction SilentlyContinue)

        Write-Verbose "Running Get-SPCPrivilegedUser scan..."
        $privileged = @(Get-SPCPrivilegedUser @scanParams -ErrorAction SilentlyContinue)

        Write-Verbose "Running Get-SPCOverPermissionedUser scan..."
        $overPermissioned = @(Get-SPCOverPermissionedUser @scanParams -ErrorAction SilentlyContinue)

        # Calculate summary metrics
        $totalOrphaned = $orphans.Count
        $totalGuests   = $guests.Count
        $highRiskOrphans = ($orphans | Where-Object { $_.RiskLevel -eq 'HIGH' }).Count
        $highRiskGuests  = ($guests | Where-Object { $_.RiskLevel -eq 'HIGH' }).Count
        $highRiskUsers   = $highRiskOrphans + $highRiskGuests
        $topHighRiskGuestsList = @($guests | Where-Object { $_.RiskLevel -eq 'HIGH' })

        $graphToken = $script:SPCContext.GraphAccessToken
        $headers = @{ "Authorization" = "Bearer $graphToken"; "ConsistencyLevel" = "eventual" }
        $response = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users?`$count=true" -Headers $headers -ErrorAction SilentlyContinue
        $totalUsers = $response.'@odata.count'
        if ($null -eq $totalUsers) { $totalUsers = 0 }

        Write-Verbose "Generating HTML Dashboard at $OutputPath via New-SPCDashboardHtmlInternal..."

        if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

        $null = New-SPCDashboardHtmlInternal `
            -OutputPath $OutputPath `
            -TotalUsers $totalUsers `
            -TotalGuests $totalGuests `
            -TotalOrphaned $totalOrphaned `
            -HighRiskUsers $highRiskUsers `
            -OrphanedUsersList $orphans `
            -TopHighRiskGuestsList $topHighRiskGuestsList `
            -PrivilegedUsers $privileged `
            -OverPermissionedUsers $overPermissioned

        $resolved = Get-Item -Path $OutputPath
        Write-Verbose "Dashboard HTML generated successfully at $($resolved.FullName)"
        return $resolved
    }

    end {
        Write-Verbose "Completed Invoke-SPCDashboardReport"
    }
}
