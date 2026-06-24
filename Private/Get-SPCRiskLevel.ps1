function Get-SPCRiskLevel {
    <#
    .SYNOPSIS
        Classifies an orphaned user's risk level per SRS 3.2.2 (first-match rule table).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Deleted', 'GuestOrphaned', 'SoftDeleted', 'Disabled', 'Unknown')]
        [string] $OrphanType,

        [Parameter(Mandatory)]
        [bool] $HasDirectPermissions,

        [Parameter(Mandatory)]
        [int] $GroupMembershipCount
    )

    process {
        # SRS 3.2.2 — evaluated top-to-bottom, first match wins
        if ($OrphanType -eq 'Deleted' -and ($HasDirectPermissions -or $GroupMembershipCount -gt 0)) {
            return 'HIGH'
        }
        if ($OrphanType -eq 'GuestOrphaned' -and $HasDirectPermissions) {
            return 'HIGH'
        }
        if ($OrphanType -eq 'SoftDeleted') {
            return 'MEDIUM'
        }
        if ($OrphanType -eq 'Disabled' -and $HasDirectPermissions) {
            return 'MEDIUM'
        }
        return 'LOW'
    }
}
