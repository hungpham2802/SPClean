function Measure-SPCScoreInternal {
    <#
    .SYNOPSIS
        Calculates the 0-100 Permission Health Score and deduction breakdown per SRS.
    .DESCRIPTION
        Quantified health score deduction engine evaluating orphaned users, high-risk guests,
        over-permissioned users, broken inheritance sites, and missing site owners.
    .OUTPUTS
        [PSCustomObject]
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
        Write-Verbose "Calculating permission health score..."
    }

    process {
        $orphanedDeduction        = [Math]::Min(30, $OrphanedUserCount * 2)
        $guestDeduction           = [Math]::Min(25, $HighRiskGuestCount * 1.5)
        $overPermissionedDeduction= [Math]::Min(20, $OverPermissionedUserCount * 2)
        $brokenInheritanceDeduction = $BrokenInheritanceSiteCount * 15
        $missingOwnerDeduction    = $MissingOwnerSiteCount * 10

        $totalDeduction = $orphanedDeduction + $guestDeduction + $overPermissionedDeduction + $brokenInheritanceDeduction + $missingOwnerDeduction
        $overallScore   = [Math]::Max(0, 100 - $totalDeduction)

        $breakdown = [PSCustomObject]@{
            OrphanedUserDeduction      = $orphanedDeduction
            HighRiskGuestDeduction     = $guestDeduction
            OverPermissionedDeduction  = $overPermissionedDeduction
            BrokenInheritanceDeduction = $brokenInheritanceDeduction
            MissingOwnerDeduction      = $missingOwnerDeduction
        }

        $result = [PSCustomObject]@{
            OverallScore = $overallScore
            Breakdown    = $breakdown
        }

        return $result
    }

    end {
        Write-Verbose "Score calculation completed."
    }
}
