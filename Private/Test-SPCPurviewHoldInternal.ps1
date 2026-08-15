function Test-SPCPurviewHoldInternal {
    <#
    .SYNOPSIS
        Inspects whether a SharePoint site collection or library is under Microsoft Purview retention or legal hold.
    .DESCRIPTION
        Checks Preservation Hold Library existence and site compliance flags to ensure zero unintended data loss.
    .OUTPUTS
        [PSCustomObject] with SiteUrl, IsHoldActive, HoldType, Details
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] [string]$SiteUrl,
        [Parameter()] [string]$LibraryTitle
    )

    try {
        $siteConn = Connect-SPCSiteInternal -SiteUrl $SiteUrl -Context $script:SPCContext
        $site = Get-PnPSite -Connection $siteConn

        # 1. Inspect Preservation Hold Library presence
        $phl = Get-PnPList -Identity "PreservationHoldLibrary" -Connection $siteConn -ErrorAction SilentlyContinue
        if ($null -eq $phl) {
            $phl = Get-PnPList -Identity "Preservation Hold Library" -Connection $siteConn -ErrorAction SilentlyContinue
        }

        # 2. Check Site Compliance Tag / Hold policies via Web properties
        $web = $site.RootWeb
        $hasHoldProp = $false
        if ($null -ne $web) {
            Get-PnPProperty -ClientObject $web -Property AllProperties -Connection $siteConn | Out-Null
            if ($null -ne $web.AllProperties -and $null -ne $web.AllProperties.FieldValues) {
                $hasHoldProp = $web.AllProperties.FieldValues.ContainsKey('_ComplianceFlags') -or
                               $web.AllProperties.FieldValues.ContainsKey('HoldSearchQueries')
            }
        }

        $isHoldActive = ($null -ne $phl) -or $hasHoldProp
        $holdType = if ($null -ne $phl) { 'PurviewRetentionPolicy' } elseif ($hasHoldProp) { 'eDiscoveryHold' } else { 'None' }

        return [PSCustomObject]@{
            SiteUrl      = $SiteUrl
            IsHoldActive = $isHoldActive
            HoldType     = $holdType
            Details      = if ($isHoldActive) { "Site locked by $holdType" } else { "No active holds detected" }
        }
    }
    catch {
        Write-Warning "Test-SPCPurviewHoldInternal: Error checking holds on '$SiteUrl': $($_.Exception.Message)"
        return [PSCustomObject]@{
            SiteUrl      = $SiteUrl
            IsHoldActive = $false
            HoldType     = 'Unknown'
            Details      = "Error evaluating holds: $($_.Exception.Message)"
        }
    }
}
