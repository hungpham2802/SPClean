function Invoke-SPCTempElevationInternal {
    <#
    .SYNOPSIS
        Elevates current interactive operator to Site Collection Administrator or Group Owner temporarily.
    .DESCRIPTION
        Implements multi-strategy elevation with fallback for SharePoint Online.
        Strategy 1: CSOM Set-PnPTenantSite (requires Tenant Admin / SharePoint Admin role).
        Strategy 2: Graph API M365 Group Owner addition if site is connected to a Microsoft 365 Group.
    .OUTPUTS
        [PSCustomObject] Elevation record containing Success, ElevationType, SiteUrl, OperatorUPN, GroupId, SiteConnection.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteUrl,

        [Parameter()]
        [PSCustomObject]$Context = $script:SPCContext
    )

    begin {
        Write-Verbose "Invoke-SPCTempElevationInternal: Entering elevation process for site '$SiteUrl'"
        if ($null -eq $Context) {
            throw "ERR-ELEV-001: No active SPClean context provided for elevation."
        }
    }

    process {
        $authMode = if ($Context.AuthMode) { $Context.AuthMode } else { $Context.AuthMethod }
        if ($authMode -ne 'Interactive') {
            Write-Verbose "Invoke-SPCTempElevationInternal: Skipping elevation because auth mode is '$authMode' (AppOnly or non-Interactive)."
            return [PSCustomObject]@{
                Success       = $false
                ElevationType = 'None'
                SiteUrl       = $SiteUrl
                OperatorUPN   = $null
                GroupId       = $null
                ErrorMessage  = "Elevation only applicable in Interactive mode."
            }
        }

        # Resolve Operator UPN
        $myUPN = if ($Context.OperatorUPN -and $Context.OperatorUPN -notlike 'AppOnly:*') {
            $Context.OperatorUPN
        } else {
            try {
                (Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/me" -Headers @{ Authorization = "Bearer $($Context.GraphAccessToken)" } -ErrorAction Stop).userPrincipalName
            } catch {
                try {
                    (Get-MgContext).Account
                } catch {
                    if ($Context.TenantName) {
                        "admin@$($Context.TenantName).onmicrosoft.com"
                    } else {
                        $null
                    }
                }
            }
        }

        if (-not $myUPN) {
            Write-Verbose "Invoke-SPCTempElevationInternal: Could not determine operator UPN."
            return [PSCustomObject]@{
                Success       = $false
                ElevationType = 'None'
                SiteUrl       = $SiteUrl
                OperatorUPN   = $null
                GroupId       = $null
                ErrorMessage  = "Unable to determine current operator UPN for elevation."
            }
        }

        # Strategy 1: CSOM Tenant Site Owner / SCA
        $csomError = $null
        try {
            Write-Verbose "Invoke-SPCTempElevationInternal: Attempting Strategy 1 (CSOM Set-PnPTenantSite)..."
            if ($Context.PnPContext) {
                Set-PnPTenantSite -Connection $Context.PnPContext -Url $SiteUrl -Owners $myUPN -ErrorAction Stop
                Start-Sleep -Seconds 5
                return [PSCustomObject]@{
                    Success       = $true
                    ElevationType = 'SCA'
                    SiteUrl       = $SiteUrl
                    OperatorUPN   = $myUPN
                    GroupId       = $null
                    ErrorMessage  = $null
                }
            }
        }
        catch {
            $csomError = $_.Exception.Message
            Write-Verbose "Invoke-SPCTempElevationInternal: Strategy 1 failed: $csomError"
        }

        # Strategy 2: Graph API M365 Group Owner Elevation (for Unified Group Sites)
        try {
            Write-Verbose "Invoke-SPCTempElevationInternal: Attempting Strategy 2 (Microsoft Graph M365 Group Owner)..."
            $uri = [System.Uri]$SiteUrl
            $hostName = $uri.Host
            $sitePath = $uri.AbsolutePath.Trim('/')
            
            # Resolve site and group from Graph
            $graphHeaders = @{ Authorization = "Bearer $($Context.GraphAccessToken)"; 'Content-Type' = 'application/json' }
            $siteInfo = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/${hostName}:/${sitePath}?`$select=id" -Headers $graphHeaders -ErrorAction Stop
            
            if ($siteInfo -and $siteInfo.id) {
                $siteId = $siteInfo.id
                # Try finding group by alias
                $alias = $sitePath.Split('/')[-1]
                $groupSearchResult = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=mailNickname eq '$alias'&`$select=id" -Headers $graphHeaders -ErrorAction SilentlyContinue
                
                if ($groupSearchResult.value -and $groupSearchResult.value.Count -gt 0) {
                    $targetGroupId = $groupSearchResult.value[0].id
                    
                    # Get Operator Object ID
                    $userObj = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$myUPN?`$select=id" -Headers $graphHeaders -ErrorAction Stop
                    $userOid = $userObj.id

                    $body = @{
                        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$userOid"
                    } | ConvertTo-Json

                    Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups/$targetGroupId/owners/`$ref" -Method Post -Headers $graphHeaders -Body $body -ErrorAction Stop
                    Start-Sleep -Seconds 5

                    return [PSCustomObject]@{
                        Success       = $true
                        ElevationType = 'GroupOwner'
                        SiteUrl       = $SiteUrl
                        OperatorUPN   = $myUPN
                        GroupId       = $targetGroupId
                        ErrorMessage  = $null
                    }
                }
            }
        }
        catch {
            Write-Verbose "Invoke-SPCTempElevationInternal: Strategy 2 failed: $($_.Exception.Message)"
        }

        # If all strategies failed, return structured failure object
        return [PSCustomObject]@{
            Success       = $false
            ElevationType = 'None'
            SiteUrl       = $SiteUrl
            OperatorUPN   = $myUPN
            GroupId       = $null
            ErrorMessage  = if ($csomError) { $csomError } else { "Access denied. Operator requires SharePoint Administrator or Site Collection Admin permissions." }
        }
    }

    end {
        Write-Verbose "Invoke-SPCTempElevationInternal: Completed elevation attempt for '$SiteUrl'"
    }
}

function Undo-SPCTempElevationInternal {
    <#
    .SYNOPSIS
        Rolls back temporary elevation safely.
    .PARAMETER ElevationRecord
        The PSCustomObject returned by Invoke-SPCTempElevationInternal.
    .PARAMETER SiteConnection
        The PnP Connection object for the site.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ElevationRecord,

        [Parameter()]
        [object]$SiteConnection,

        [Parameter()]
        [PSCustomObject]$Context = $script:SPCContext
    )

    if ($null -eq $ElevationRecord -or -not $ElevationRecord.Success) {
        return
    }

    try {
        switch ($ElevationRecord.ElevationType) {
            'SCA' {
                if ($ElevationRecord.OperatorUPN) {
                    Write-Verbose "Undo-SPCTempElevationInternal: Removing temporary Site Collection Admin for $($ElevationRecord.OperatorUPN) on $($ElevationRecord.SiteUrl)"
                    Remove-PnPSiteCollectionAdmin -Connection $SiteConnection -Owners $ElevationRecord.OperatorUPN -ErrorAction SilentlyContinue
                }
            }
            'GroupOwner' {
                if ($ElevationRecord.GroupId -and $ElevationRecord.OperatorUPN -and $Context.GraphAccessToken) {
                    Write-Verbose "Undo-SPCTempElevationInternal: Removing temporary Group Owner from group $($ElevationRecord.GroupId)"
                    $graphHeaders = @{ Authorization = "Bearer $($Context.GraphAccessToken)" }
                    $userObj = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$($ElevationRecord.OperatorUPN)?`$select=id" -Headers $graphHeaders -ErrorAction SilentlyContinue
                    if ($userObj -and $userObj.id) {
                        Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups/$($ElevationRecord.GroupId)/owners/$($userObj.id)/`$ref" -Method Delete -Headers $graphHeaders -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
    catch {
        Write-Verbose "Undo-SPCTempElevationInternal: Cleanup encountered non-fatal error: $($_.Exception.Message)"
    }
}
