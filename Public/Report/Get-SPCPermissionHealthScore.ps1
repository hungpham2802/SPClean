function Get-SPCPermissionHealthScore {
    <#
    .SYNOPSIS
        Calculates the Permission Health Score for the tenant.

    .DESCRIPTION
        This cmdlet calculates a permission health score from 0 to 100 based on quantified risks.
        It deducts points for orphaned users, high-risk guests, over-permissioned users,
        broken inheritance, and missing site owners.

    .PARAMETER OrphanedUserCount
        The number of orphaned users detected.
    
    .PARAMETER HighRiskGuestCount
        The number of high-risk guests detected.

    .PARAMETER OverPermissionedUserCount
        The number of over-permissioned users (EAS > 100).

    .PARAMETER BrokenInheritanceSiteCount
        The number of sites with more than 1000 broken inheritance scopes.

    .PARAMETER MissingOwnerSiteCount
        The number of sites missing an owner or with an inactive owner.

    .EXAMPLE
        Get-SPCPermissionHealthScore -OrphanedUserCount 10 -HighRiskGuestCount 5 -OverPermissionedUserCount 2 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory=$true)]
        [int]$OrphanedUserCount,

        [Parameter(Mandatory=$true)]
        [int]$HighRiskGuestCount,

        [Parameter(Mandatory=$true)]
        [int]$OverPermissionedUserCount,

        [Parameter(Mandatory=$true)]
        [int]$BrokenInheritanceSiteCount,

        [Parameter(Mandatory=$true)]
        [int]$MissingOwnerSiteCount
    )

    begin {
        Write-Verbose "Entering Get-SPCPermissionHealthScore"
        try {
            Test-SPCConnection -ErrorAction Stop
        } catch {
            throw "ERR-001: Connection not found. Please connect using Connect-SPCTenant first."
        }
    }

    process {
        Write-Verbose "Calculating score with inputs: Orphans=$OrphanedUserCount, Guests=$HighRiskGuestCount, OverPerm=$OverPermissionedUserCount, BrokenSites=$BrokenInheritanceSiteCount, MissingOwner=$MissingOwnerSiteCount"
        
        $scoreResult = Calculate-SPCScoreInternal -OrphanedUserCount $OrphanedUserCount -HighRiskGuestCount $HighRiskGuestCount -OverPermissionedUserCount $OverPermissionedUserCount -BrokenInheritanceSiteCount $BrokenInheritanceSiteCount -MissingOwnerSiteCount $MissingOwnerSiteCount
        
        Write-Information "Health score calculation completed successfully. Overall Score: $($scoreResult.OverallScore)"
        return $scoreResult
    }

    end {
        Write-Verbose "Health score calculation completed."
    }
}
