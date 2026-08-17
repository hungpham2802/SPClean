function Invoke-SPCTempElevationInternal {
    <#
    .SYNOPSIS
        Elevates current interactive operator to Site Collection Administrator, Group Owner, or Site Permission Holder temporarily.
    .DESCRIPTION
        Implements multi-strategy elevation with fallback for SharePoint Online.
        Strategy 1: CSOM Set-PnPTenantSite (with both UPN and Claims login formats).
        Strategy 2: Tenant REST API /_api/SPO.Tenant/SetSiteAdmin.
        Strategy 3: Microsoft Graph API M365 Group Owner addition if site is connected to an M365 Group.
        Strategy 4: Microsoft Graph API Site Permission role addition (/sites/{siteId}/permissions).
    .OUTPUTS
        [PSCustomObject] Elevation record containing Success, ElevationType, SiteUrl, OperatorUPN, GroupId, PermissionId.
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
                PermissionId  = $null
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
                PermissionId  = $null
                ErrorMessage  = "Unable to determine current operator UPN for elevation."
            }
        }

        $claimsLogin = if ($myUPN -match "\|membership\|") { $myUPN } else { "i:0#.f|membership|$myUPN" }
        $errors = [System.Collections.Generic.List[string]]::new()

        # Strategy 1A & 1B: CSOM Tenant Site Owner (Set-PnPTenantSite)
        if ($Context.PnPContext) {
            try {
                Write-Verbose "Invoke-SPCTempElevationInternal: Strategy 1A - CSOM Set-PnPTenantSite (UPN)..."
                Set-PnPTenantSite -Connection $Context.PnPContext -Url $SiteUrl -Owners $myUPN -ErrorAction Stop
                Start-Sleep -Seconds 5
                return [PSCustomObject]@{
                    Success       = $true
                    ElevationType = 'SCA'
                    SiteUrl       = $SiteUrl
                    OperatorUPN   = $myUPN
                    GroupId       = $null
                    PermissionId  = $null
                    ErrorMessage  = $null
                }
            }
            catch {
                $errors.Add("Strategy 1A (CSOM UPN): $($_.Exception.Message)")
            }

            try {
                Write-Verbose "Invoke-SPCTempElevationInternal: Strategy 1B - CSOM Set-PnPTenantSite (Claims)..."
                Set-PnPTenantSite -Connection $Context.PnPContext -Url $SiteUrl -Owners $claimsLogin -ErrorAction Stop
                Start-Sleep -Seconds 5
                return [PSCustomObject]@{
                    Success       = $true
                    ElevationType = 'SCA'
                    SiteUrl       = $SiteUrl
                    OperatorUPN   = $myUPN
                    GroupId       = $null
                    PermissionId  = $null
                    ErrorMessage  = $null
                }
            }
            catch {
                $errors.Add("Strategy 1B (CSOM Claims): $($_.Exception.Message)")
            }

            # Strategy 2: Tenant REST API /_api/SPO.Tenant/SetSiteAdmin
            try {
                Write-Verbose "Invoke-SPCTempElevationInternal: Strategy 2 - REST /_api/SPO.Tenant/SetSiteAdmin..."
                $restBody = @{
                    siteUrl     = $SiteUrl
                    loginName   = $claimsLogin
                    isSiteAdmin = $true
                }
                $null = Invoke-PnPSPRestMethod -Method Post -Url "/_api/SPO.Tenant/SetSiteAdmin" -Content $restBody -Connection $Context.PnPContext -ErrorAction Stop
                Start-Sleep -Seconds 5
                return [PSCustomObject]@{
                    Success       = $true
                    ElevationType = 'REST_SCA'
                    SiteUrl       = $SiteUrl
                    OperatorUPN   = $myUPN
                    GroupId       = $null
                    PermissionId  = $null
                    ErrorMessage  = $null
                }
            }
            catch {
                $errors.Add("Strategy 2 (REST SPO.Tenant): $($_.Exception.Message)")
            }
        }

        # Strategy 3: Graph API M365 Group Owner Elevation
        if ($Context.GraphAccessToken) {
            try {
                Write-Verbose "Invoke-SPCTempElevationInternal: Strategy 3 - Microsoft Graph M365 Group Owner..."
                $uri = [System.Uri]$SiteUrl
                $hostName = $uri.Host
                $sitePath = $uri.AbsolutePath.Trim('/')
                $alias = $sitePath.Split('/')[-1]

                $graphHeaders = @{ Authorization = "Bearer $($Context.GraphAccessToken)"; 'Content-Type' = 'application/json' }
                
                # Get Operator Object ID
                $userObj = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$myUPN?`$select=id" -Headers $graphHeaders -ErrorAction Stop
                $userOid = $userObj.id

                # Try finding group by alias or mailNickname
                $groupSearchResult = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=mailNickname eq '$alias' or displayName eq '$alias'&`$select=id" -Headers $graphHeaders -ErrorAction SilentlyContinue
                
                if ($groupSearchResult.value -and $groupSearchResult.value.Count -gt 0) {
                    $targetGroupId = $groupSearchResult.value[0].id
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
                        PermissionId  = $null
                        ErrorMessage  = $null
                    }
                }
            }
            catch {
                $errors.Add("Strategy 3 (Graph Group Owner): $($_.Exception.Message)")
            }

            # Strategy 4: Microsoft Graph Site Permissions API (/sites/{id}/permissions)
            try {
                Write-Verbose "Invoke-SPCTempElevationInternal: Strategy 4 - Microsoft Graph Site Permissions..."
                $uri = [System.Uri]$SiteUrl
                $hostName = $uri.Host
                $sitePath = $uri.AbsolutePath.Trim('/')
                $graphHeaders = @{ Authorization = "Bearer $($Context.GraphAccessToken)"; 'Content-Type' = 'application/json' }

                $siteInfo = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/${hostName}:/${sitePath}?`$select=id" -Headers $graphHeaders -ErrorAction Stop
                if ($siteInfo -and $siteInfo.id) {
                    $siteId = $siteInfo.id
                    $userObj = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$myUPN?`$select=id,displayName,userPrincipalName" -Headers $graphHeaders -ErrorAction Stop
                    
                    $permBody = @{
                        roles = @("write", "owner")
                        grantedToIdentities = @(
                            @{
                                user = @{
                                    id                = $userObj.id
                                    displayName       = $userObj.displayName
                                    userPrincipalName = $userObj.userPrincipalName
                                }
                            }
                        )
                    } | ConvertTo-Json -Depth 5

                    $permRes = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/permissions" -Method Post -Headers $graphHeaders -Body $permBody -ErrorAction Stop
                    Start-Sleep -Seconds 5

                    return [PSCustomObject]@{
                        Success       = $true
                        ElevationType = 'GraphSitePerm'
                        SiteUrl       = $SiteUrl
                        OperatorUPN   = $myUPN
                        GroupId       = $siteId
                        PermissionId  = $permRes.id
                        ErrorMessage  = $null
                    }
                }
            }
            catch {
                $errors.Add("Strategy 4 (Graph Site Perm): $($_.Exception.Message)")
            }
        }

        # If all strategies failed, return structured failure object
        $details = $errors -join " | "
        return [PSCustomObject]@{
            Success       = $false
            ElevationType = 'None'
            SiteUrl       = $SiteUrl
            OperatorUPN   = $myUPN
            GroupId       = $null
            PermissionId  = $null
            ErrorMessage  = "All elevation strategies failed: $details"
        }
    }

    end {
        Write-Verbose "Invoke-SPCTempElevationInternal: Completed elevation attempt for '$SiteUrl'"
    }
}

function Undo-SPCTempElevationInternal {
    <#
    .SYNOPSIS
        Rolls back temporary elevation safely across all strategies.
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
            'REST_SCA' {
                if ($Context.PnPContext -and $ElevationRecord.OperatorUPN) {
                    Write-Verbose "Undo-SPCTempElevationInternal: Removing temporary REST Site Collection Admin for $($ElevationRecord.OperatorUPN) on $($ElevationRecord.SiteUrl)"
                    $claimsLogin = if ($ElevationRecord.OperatorUPN -match "\|membership\|") { $ElevationRecord.OperatorUPN } else { "i:0#.f|membership|$($ElevationRecord.OperatorUPN)" }
                    $restBody = @{
                        siteUrl     = $ElevationRecord.SiteUrl
                        loginName   = $claimsLogin
                        isSiteAdmin = $false
                    }
                    $null = Invoke-PnPSPRestMethod -Method Post -Url "/_api/SPO.Tenant/SetSiteAdmin" -Content $restBody -Connection $Context.PnPContext -ErrorAction SilentlyContinue
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
            'GraphSitePerm' {
                if ($ElevationRecord.GroupId -and $ElevationRecord.PermissionId -and $Context.GraphAccessToken) {
                    Write-Verbose "Undo-SPCTempElevationInternal: Removing temporary Graph Site Permission $($ElevationRecord.PermissionId) on site $($ElevationRecord.GroupId)"
                    $graphHeaders = @{ Authorization = "Bearer $($Context.GraphAccessToken)" }
                    Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/$($ElevationRecord.GroupId)/permissions/$($ElevationRecord.PermissionId)" -Method Delete -Headers $graphHeaders -ErrorAction SilentlyContinue
                }
            }
        }
    }
    catch {
        Write-Verbose "Undo-SPCTempElevationInternal: Cleanup encountered non-fatal error: $($_.Exception.Message)"
    }
}
