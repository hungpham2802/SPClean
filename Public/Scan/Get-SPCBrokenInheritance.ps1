function Get-SPCBrokenInheritance {
    <#
    .SYNOPSIS
        Scans for unique permission scopes (broken inheritance) in a SharePoint Site Collection.

    .DESCRIPTION
        This cmdlet scans Document Libraries, Folders, and Files within a specified Site Collection
        to find objects where permission inheritance is broken (HasUniqueRoleAssignments == true).
        It returns the list of objects and warns if the total exceeds 3,000 scopes.

    .PARAMETER SiteUrl
        The URL of the SharePoint Site Collection to scan.

    .EXAMPLE
        Get-SPCBrokenInheritance -SiteUrl "https://contoso.sharepoint.com/sites/hr"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteUrl
    )

    begin {
        Write-Verbose "Entering Get-SPCBrokenInheritance"
        try {
            Test-SPCConnection -ErrorAction Stop
        } catch {
            throw "ERR-001: Connection not found. Please connect using Connect-SPCTenant first."
        }
    }

    process {
        Write-Verbose "Scanning Site: $SiteUrl for broken inheritance"
        
        $brokenItems = @(Get-SPCLibraryBrokenInheritanceInternal -SiteUrl $SiteUrl)
        $uniqueScopesCount = $brokenItems.Count

        if ($uniqueScopesCount -gt 3000) {
            Write-Warning "Alert: Site $SiteUrl has $uniqueScopesCount unique permission scopes, exceeding the recommended limit of 3,000 scopes. This may cause severe performance issues."
        }

        $result = [PSCustomObject]@{
            SiteUrl      = $SiteUrl
            UniqueScopes = $uniqueScopesCount
            BrokenItems  = $brokenItems
        }

        return $result
    }

    end {
        Write-Information "Broken inheritance scan completed. Total unique scopes: $uniqueScopesCount"
    }
}
