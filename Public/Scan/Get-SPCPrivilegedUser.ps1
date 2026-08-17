function Get-SPCPrivilegedUser {
    <#
    .SYNOPSIS
        Gets the top 20 privileged users across the SharePoint tenant (Focus on Depth of Access).
    
    .DESCRIPTION
        This cmdlet scans all site collections to identify users who are Site Collection Administrators,
        members of the default Owners group, or have direct 'Full Control' assignments. 
        It aggregates this data by UserPrincipalName and returns the top 20 users with the most privileged access.
        
        Concept: Privileged Users focus on "Depth of Access".
        Risk: These users have the highest level of control over specific resources, posing a severe risk of system compromise, configuration changes, or "admin theft" if their accounts are compromised.
    
    .EXAMPLE
        Get-SPCPrivilegedUser
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteUrl,

        [Parameter()]
        [switch]$AddTempSiteCollectionAdmin
    )

    begin {
        Write-Verbose "Validating connection..."
        if (Get-Command Test-SPCConnection -ErrorAction SilentlyContinue) {
            Test-SPCConnection
        }
        $tempResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        try {
            $sitesToScan = @()
            if ($SiteUrl) {
                $sitesToScan += $SiteUrl
            }
            else {
                Write-Verbose "Fetching all tenant sites..."
                $sitesToScan = Get-PnPTenantSite -Connection $script:SPCContext.PnPContext | Select-Object -ExpandProperty Url
            }

            $totalSites = $sitesToScan.Count
            $counter = 0

            foreach ($url in $sitesToScan) {
                $counter++
                Write-Progress -Activity "Scanning Sites for Privileged Users" -Status "Processing site $url ($counter / $totalSites)" -PercentComplete (($counter / $totalSites) * 100)
                Write-Verbose "Scanning site: $url"

                $removeSca = $false
                $myUPN = $null
                $siteConnection = $null

                try {
                    $retryCount = 0
                    $maxRetries = 5
                    $success = $false
                    
                    while (-not $success -and $retryCount -lt $maxRetries) {
                        try {
                            $siteConnection = Connect-SPCSiteInternal -SiteUrl $url -Context $script:SPCContext
                            
                            # 1. SCAs - Use Get-PnPSiteCollectionAdmin
                            $scas = Get-PnPSiteCollectionAdmin -Connection $siteConnection -ErrorAction Stop
                            if ($scas) {
                                foreach ($sca in $scas) {
                                    if (-not [string]::IsNullOrEmpty($sca.LoginName) -and $sca.LoginName -match "\|membership\|") {
                                        $upn = $sca.LoginName.Split("|")[-1]
                                        $tempResults.Add([PSCustomObject]@{
                                                UPN              = $upn
                                                SiteUrl          = $url
                                                PermissionSource = "SCA"
                                            })
                                    }
                                }
                            }

                            # 2. Owners Group
                            $ownersGroup = $null
                            try {
                                $ownersGroup = Get-PnPGroup -AssociatedOwnerGroup -Connection $siteConnection -ErrorAction SilentlyContinue
                            } catch {}
                            if (-not $ownersGroup) {
                                try {
                                    $web = Get-PnPWeb -Connection $siteConnection -ErrorAction SilentlyContinue
                                    if ($web -and $web.AssociatedOwnerGroup) {
                                        $ownersGroup = $web.AssociatedOwnerGroup
                                    }
                                } catch {}
                            }
                            if ($ownersGroup) {
                                $ownerMembers = Get-PnPGroupMember -Group $ownersGroup -Connection $siteConnection -ErrorAction SilentlyContinue
                                if ($ownerMembers) {
                                    foreach ($member in $ownerMembers) {
                                        if (-not [string]::IsNullOrEmpty($member.LoginName) -and $member.LoginName -match "\|membership\|") {
                                            $upn = $member.LoginName.Split("|")[-1]
                                            $tempResults.Add([PSCustomObject]@{
                                                    UPN              = $upn
                                                    SiteUrl          = $url
                                                    PermissionSource = "Owner"
                                                })
                                        }
                                    }
                                }
                            }

                            # 3. Direct Assignments (Full Control)
                            $roleAssignments = (Invoke-PnPSPRestMethod -Method Get -Url "/_api/web/roleassignments?`$expand=Member,RoleDefinitionBindings" -Connection $siteConnection -ErrorAction SilentlyContinue).value
                            if ($roleAssignments) {
                                foreach ($ra in $roleAssignments) {
                                    $isFullControl = $ra.RoleDefinitionBindings | Where-Object { $_.Name -eq 'Full Control' }
                                    if ($isFullControl) {
                                        if ($ra.Member.PrincipalType -in 'User', 1 -and $ra.Member.LoginName -match "\|membership\|") {
                                            $upn = $ra.Member.LoginName.Split("|")[-1]
                                            $tempResults.Add([PSCustomObject]@{
                                                    UPN              = $upn
                                                    SiteUrl          = $url
                                                    PermissionSource = "Direct"
                                                })
                                        }
                                    }
                                }
                            }
                            
                            $success = $true
                        }
                        catch {
                            $ex = $_.Exception
                            if ($ex.Message -match '429|503' -or $_.FullyQualifiedErrorId -match '429|503') {
                                $retryCount++
                                $retryAfter = $null
                                if ($ex.Response -and $ex.Response.Headers -and $ex.Response.Headers["Retry-After"]) {
                                    $retryAfter = $ex.Response.Headers["Retry-After"]
                                }
                                
                                $waitTime = if ($retryAfter) { [int]$retryAfter } else { [Math]::Pow(2, $retryCount) }
                                
                                Write-Verbose "Throttled (429/503). Retrying in $waitTime seconds (Attempt $retryCount of $maxRetries)..."
                                Start-Sleep -Seconds $waitTime
                                if ($retryCount -eq $maxRetries) {
                                    Write-Error "[ERR-GPU-001] $(Get-Date -Format 'o'): Failed to process site collection '$url' after $maxRetries attempts due to throttling. Resource: $url." -ErrorAction Continue
                                }
                            }
                            elseif ($ex.Message -match "401" -or $ex.Message -match "403" -or $ex.Message -match "Access denied" -or $ex.Message -match "Unauthorized") {
                                if ($AddTempSiteCollectionAdmin) {
                                    $authMethod = if ($script:SPCContext.AuthMethod) { $script:SPCContext.AuthMethod } else { $script:SPCContext.AuthMode }
                                    if ($authMethod -ne 'Interactive') {
                                        Write-Error "[ERR-GPU-004] $(Get-Date -Format 'o'): Access Denied on '$url'. -AddTempSiteCollectionAdmin is only supported for Interactive auth. Resource: $url." -ErrorAction Continue
                                        $success = $true
                                        continue
                                    }
                                    Write-Verbose "Get-SPCPrivilegedUser: Access Denied on '$url'. Attempting temporary elevation."
                                    $elevationRecord = Invoke-SPCTempElevationInternal -SiteUrl $url -Context $script:SPCContext
                                    if ($elevationRecord.Success) {
                                        $siteConnection = Connect-SPCSiteInternal -SiteUrl $url -Context $script:SPCContext
                                        # Retry the scan in next while iteration
                                    } else {
                                        Write-Warning "[WARN-GPU-005] $(Get-Date -Format 'o'): Access Denied on site collection '$url'. Skipping restricted site. Details: $($elevationRecord.ErrorMessage)"
                                        $success = $true
                                    }
                                } else {
                                    Write-Error "[ERR-GPU-002] $(Get-Date -Format 'o'): Error processing site collection '$url'. Resource: $url. Details: $($ex.Message)" -ErrorAction Continue
                                    $success = $true
                                }
                            }
                            else {
                                Write-Error "[ERR-GPU-002] $(Get-Date -Format 'o'): Error processing site collection '$url'. Resource: $url. Details: $($ex.Message)" -ErrorAction Continue
                                $success = $true # break out of retry loop for non-throttling errors
                            }
                        }
                    }
                }
                finally {
                    if ($elevationRecord -and $elevationRecord.Success) {
                        Undo-SPCTempElevationInternal -ElevationRecord $elevationRecord -SiteConnection $siteConnection -Context $script:SPCContext
                    }
                }
            }

            Write-Verbose "Aggregating results..."
            $foundCount = 0
            if ($tempResults.Count -gt 0) {
                $grouped = $tempResults | Group-Object -Property UPN
                $finalResults = foreach ($g in $grouped) {
                    $obj = [PSCustomObject]@{
                        UPN               = $g.Name
                        SiteCount         = $g.Count
                        Sites             = $g.Group.SiteUrl | Select-Object -Unique
                        PermissionSources = $g.Group.PermissionSource | Select-Object -Unique
                    }
                    $obj.PSObject.TypeNames.Insert(0, 'SPC.PrivilegedUser')
                    $obj
                }

                $top20 = @($finalResults | Sort-Object -Property SiteCount -Descending)
                if ($top20.Count -gt 20) { $top20 = $top20[0..19] }
                $foundCount = $top20.Count
                Write-Output $top20
            }
            else {
                Write-Verbose "No privileged users found."
                Write-Output @()
            }
        }
        catch {
            $errCode = "ERR-AUTH-001"
            $exMsg = "[$errCode] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ssZ'): Terminating error occurred. $($_.Exception.Message)"
            Write-Error -Message $exMsg -Exception $_.Exception -ErrorId $errCode -ErrorAction Stop
        }
    }

    end {
        if ($null -eq $counter) { $counter = 0 }
        if ($null -eq $foundCount) { $foundCount = 0 }
        Write-Information -MessageData "Completed Get-SPCPrivilegedUser scan. Scanned $counter sites, found $foundCount privileged users." -InformationAction Continue
    }
}
