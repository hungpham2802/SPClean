function Invoke-SPCDashboardReportV1 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [string]$OutputPath = ".\Dashboard.html"
    )

    begin {
        Write-Verbose "Starting Invoke-SPCDashboardReportV1"
        Test-SPCConnection
    }

    process {
        Write-Verbose "Running Get-SPCOrphanedUser scan across all sites..."
        $orphans = @(Get-SPCOrphanedUser -AllSites -IncludeGuests -IncludeDisabled)

        Write-Verbose "Running Get-SPCGuestAccess scan..."
        $guests = @(Get-SPCGuestAccess -ErrorAction SilentlyContinue)

        Write-Verbose "Running Get-SPCPrivilegedUser scan..."
        $privileged = @(Get-SPCPrivilegedUser -ErrorAction SilentlyContinue)

        Write-Verbose "Running Get-SPCOverPermissionedUser scan..."
        $overPermissioned = @(Get-SPCOverPermissionedUser -ErrorAction SilentlyContinue)

        # Calculate summary metrics
        $totalOrphaned = $orphans.Count
        $totalGuests = $guests.Count
        $highRiskOrphans = ($orphans | Where-Object { $_.RiskLevel -eq 'HIGH' }).Count
        $highRiskGuests = ($guests | Where-Object { $_.RiskLevel -eq 'HIGH' }).Count
        $highRiskUsers = $highRiskOrphans + $highRiskGuests
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

        Write-Verbose "Dashboard HTML generated successfully at $OutputPath"
        return $OutputPath
    }

    end {
        Write-Verbose "Completed Invoke-SPCDashboardReportV1"
    }
}
