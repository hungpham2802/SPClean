function Get-SPCPrivilegedUser {
    <#
    .SYNOPSIS
        Gets the top 20 privileged users across the SharePoint tenant.
    
    .DESCRIPTION
        This cmdlet scans all site collections to identify users who are Site Collection Administrators,
        members of the default Owners group, or have direct 'Full Control' assignments. 
        It aggregates this data by UserPrincipalName and returns the top 20 users with the most privileged access.
    
    .EXAMPLE
        Get-SPCPrivilegedUser -ClientId "app-id" -Thumbprint "cert-thumb" -Tenant "tenant.onmicrosoft.com"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteUrl,

        [Parameter(Mandatory = $false)]
        [string]$ClientId,

        [Parameter(Mandatory = $false)]
        [string]$Thumbprint,

        [Parameter(Mandatory = $false)]
        [string]$Tenant
    )

    begin {
        Write-Verbose "Validating connection..."
        if (Get-Command Test-SPCConnection -ErrorAction SilentlyContinue) {
            Test-SPCConnection
        }
        $tempResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        
        # Try to extract current connection details if parameters are not provided
        $currentConn = Get-PnPConnection -ErrorAction SilentlyContinue
        if ($currentConn) {
            if (-not $ClientId -and $currentConn.ClientId) { $ClientId = $currentConn.ClientId }
            if (-not $Tenant -and $currentConn.Tenant) { $Tenant = $currentConn.Tenant }
            if (-not $Thumbprint -and $currentConn.Certificate) { $Thumbprint = $currentConn.Certificate.Thumbprint }
        }
    }

    process {
        try {
            $sitesToScan = @()
            if ($SiteUrl) {
                $sitesToScan += $SiteUrl
            } else {
                Write-Verbose "Fetching all tenant sites..."
                # Use Select-Object to only load URLs into memory to avoid OOM for large tenants
                $sitesToScan = Get-PnPTenantSite | Select-Object -ExpandProperty Url
            }

            $totalSites = $sitesToScan.Count
            $counter = 0

            foreach ($url in $sitesToScan) {
                $counter++
                Write-Progress -Activity "Scanning Sites for Privileged Users" -Status "Processing site $url ($counter / $totalSites)" -PercentComplete (($counter / $totalSites) * 100)
                Write-Verbose "Scanning site: $url"

                try {
                    $retryCount = 0
                    $maxRetries = 5
                    $success = $false
                    
                    while (-not $success -and $retryCount -lt $maxRetries) {
                        try {
                            if ($ClientId -and $Thumbprint -and $Tenant) {
                                $siteConnection = Connect-PnPOnline -Url $url -ClientId $ClientId -Thumbprint $Thumbprint -Tenant $Tenant -ReturnConnection -ErrorAction Stop
                            } else {
                                # Fallback to clone current context or interactive if context allows
                                $siteConnection = Connect-PnPOnline -Url $url -Interactive:$false -ReturnConnection -ErrorAction Stop
                            }
                            
                            # 1. SCAs - Use Get-PnPSiteCollectionAdmin to avoid large list thresholds
                            $scas = Get-PnPSiteCollectionAdmin -Connection $siteConnection -ErrorAction SilentlyContinue
                            foreach ($sca in $scas) {
                                if (-not [string]::IsNullOrEmpty($sca.LoginName) -and $sca.LoginName -match "\|membership\|") {
                                    $upn = $sca.LoginName.Split("|")[-1]
                                    $tempResults.Add([PSCustomObject]@{
                                        UPN = $upn
                                        SiteUrl = $url
                                        PermissionSource = "SCA"
                                    })
                                }
                            }

                            # 2. Owners Group
                            $ownersGroup = Get-PnPGroup -AssociatedOwnerGroup -Connection $siteConnection -ErrorAction SilentlyContinue
                            if ($ownersGroup) {
                                $ownerMembers = Get-PnPGroupMember -Identity $ownersGroup.Title -Connection $siteConnection -ErrorAction SilentlyContinue
                                foreach ($member in $ownerMembers) {
                                    if (-not [string]::IsNullOrEmpty($member.LoginName) -and $member.LoginName -match "\|membership\|") {
                                        $upn = $member.LoginName.Split("|")[-1]
                                        $tempResults.Add([PSCustomObject]@{
                                            UPN = $upn
                                            SiteUrl = $url
                                            PermissionSource = "Owner"
                                        })
                                    }
                                }
                            }

                            # 3. Direct Assignments (Full Control)
                            # Use REST API to bypass missing Get-PnPRoleAssignment in PnP 3.x
                            $roleAssignments = (Invoke-PnPSPRestMethod -Method Get -Url "/_api/web/roleassignments?`$expand=Member,RoleDefinitionBindings" -Connection $siteConnection -ErrorAction SilentlyContinue).value
                            foreach ($ra in $roleAssignments) {
                                $isFullControl = $ra.RoleDefinitionBindings | Where-Object { $_.Name -eq 'Full Control' }
                                if ($isFullControl) {
                                    if ($ra.Member.PrincipalType -in 'User', 1 -and $ra.Member.LoginName -match "\|membership\|") {
                                        $upn = $ra.Member.LoginName.Split("|")[-1]
                                        $tempResults.Add([PSCustomObject]@{
                                            UPN = $upn
                                            SiteUrl = $url
                                            PermissionSource = "Direct"
                                        })
                                    }
                                }
                            }
                            
                            $success = $true
                        } catch {
                            $ex = $_.Exception
                            if ($ex.Message -match '429|503' -or $_.FullyQualifiedErrorId -match '429|503') {
                                $retryCount++
                                $retryAfter = $null
                                if ($ex.Response -and $ex.Response.Headers -and $ex.Response.Headers["Retry-After"]) {
                                    $retryAfter = $ex.Response.Headers["Retry-After"]
                                }
                                
                                if ($retryAfter) {
                                    $waitTime = [int]$retryAfter
                                } else {
                                    $waitTime = [Math]::Pow(2, $retryCount)
                                }
                                
                                Write-Verbose "Throttled (429/503). Retrying in $waitTime seconds (Attempt $retryCount of $maxRetries)..."
                                Start-Sleep -Seconds $waitTime
                                if ($retryCount -eq $maxRetries) {
                                    Write-Error "[ERR-GPU-001] $(Get-Date -Format 'o'): Failed to process site collection '$url' after $maxRetries attempts due to throttling. Resource: $url." -ErrorAction Continue
                                }
                            } else {
                                Write-Error "[ERR-GPU-002] $(Get-Date -Format 'o'): Error processing site collection '$url'. Resource: $url. Details: $($ex.Message)" -ErrorAction Continue
                                $success = $true # break out of retry loop for non-throttling errors
                            }
                        }
                    }
                } catch {
                    Write-Error "[ERR-GPU-003] $(Get-Date -Format 'o'): Error processing site collection '$url'. Resource: $url. Details: $($_.Exception.Message)" -ErrorAction Continue
                }
            }

            Write-Verbose "Aggregating results..."
            $foundCount = 0
            if ($tempResults.Count -gt 0) {
                $grouped = $tempResults | Group-Object -Property UPN
                $finalResults = foreach ($g in $grouped) {
                    [PSCustomObject]@{
                        UPN = $g.Name
                        SiteCount = $g.Count
                        Sites = $g.Group.SiteUrl | Select-Object -Unique
                        PermissionSources = $g.Group.PermissionSource | Select-Object -Unique
                    }
                }

                $top20 = $finalResults | Sort-Object -Property SiteCount -Descending | Select-Object -First 20
                $foundCount = $top20.Count
                Write-Output $top20
            } else {
                Write-Verbose "No privileged users found."
                Write-Output @()
            }
        } catch {
            $errCode = "ERR-AUTH-001"
            $exMsg = "[$errCode] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ssZ'): Terminating error occurred. $($_.Exception.Message)"
            Write-Error -Message $exMsg -Exception $_.Exception -ErrorAction Stop
        }
    }

    end {
        if ($null -eq $counter) { $counter = 0 }
        if ($null -eq $foundCount) { $foundCount = 0 }
        Write-Information -MessageData "Completed Get-SPCPrivilegedUser scan. Scanned $counter sites, found $foundCount privileged users." -InformationAction Continue
    }
}
