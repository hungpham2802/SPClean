<#
.SYNOPSIS
    Scans, detects, and classifies the Risk Level of Guest accounts in SharePoint Online.
.DESCRIPTION
    Gets Guest accounts from SharePoint Online and evaluates their risk level based on permission levels and inactivity.
    Risk Levels:
    - HIGH: Guest has Full Control / Owner OR inactive > 180 days.
    - MEDIUM: Guest has Edit / Write OR inactive > 90 days.
    - LOW: Guest has Read AND active within 90 days.
#>
function Get-SPCGuestAccess {
    [CmdletBinding(SupportsShouldProcess=$false)]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteUrl,

        [Parameter(Mandatory=$false)]
        [ValidateRange(0, 3650)]
        [int]$DaysInactive = 90
    )

    begin {
        if (-not (Get-Command -Name 'Test-SPCConnection' -ErrorAction SilentlyContinue)) {
            throw "ERR-GUA-002: Test-SPCConnection cmdlet not found. Resource: Environment. Time: $(Get-Date -Format 'o')"
        }
        
        Test-SPCConnection

        $connectToSite = {
            param([string] $SiteUrl, [PSCustomObject] $Ctx)
            $tenantId = if ($Ctx.TenantName -match '\.') { $Ctx.TenantName } else { "$($Ctx.TenantName).onmicrosoft.com" }
            switch ($Ctx.AuthMethod) {
                'Interactive' {
                    $token = Get-PnPAccessToken -ResourceTypeName SharePoint -Connection $Ctx.PnPContext
                    Connect-PnPOnline -Url $SiteUrl -AccessToken $token -ReturnConnection
                }
                'AppOnly' {
                    if ($Ctx._CertificatePath) {
                        Connect-PnPOnline -Url $SiteUrl -ClientId $Ctx._ClientId `
                            -Tenant $tenantId `
                            -CertificatePath $Ctx._CertificatePath `
                            -CertificatePassword $Ctx._CertificatePassword -ReturnConnection
                    } elseif ($Ctx._CertificateThumbprint) {
                        Connect-PnPOnline -Url $SiteUrl -ClientId $Ctx._ClientId `
                            -Tenant $tenantId `
                            -Thumbprint $Ctx._CertificateThumbprint -ReturnConnection
                    } else {
                        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Ctx._ClientSecret)
                        try {
                            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                            Connect-PnPOnline -Url $SiteUrl -ClientId $Ctx._ClientId `
                                -ClientSecret $plain -ReturnConnection
                        } finally {
                            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                            $plain = $null
                        }
                    }
                }
            }
        }

        $highCount = 0
        $mediumCount = 0
        $lowCount = 0
    }

    process {
        try {
            $sites = @()
            if ([string]::IsNullOrEmpty($SiteUrl)) {
                Write-Verbose "No SiteUrl provided. Fetching all sites in the tenant..."
                $sites = Get-PnPTenantSite -Connection $script:SPCContext.PnPContext | Select-Object -ExpandProperty Url
            } else {
                $sites = @($SiteUrl)
            }

            $totalSites = $sites.Count
            $siteIndex = 0
            $guestDict = @{}

            foreach ($site in $sites) {
                $siteIndex++
                Write-Progress -Activity "Scanning Sites" -Status "Processing site $siteIndex of $totalSites" -PercentComplete (($siteIndex / $totalSites) * 100)
                
                try {
                    Write-Verbose "Connecting to $site"
                    $siteConnection = & $connectToSite -SiteUrl $site -Ctx $script:SPCContext
                    
                    Write-Verbose "Retrieving users for $site"
                    $users = Get-PnPUser -Connection $siteConnection -ErrorAction Stop | Where-Object {
                        $_.PrincipalType -eq 'Guest' -or $_.LoginName -match '#EXT#'
                    }

                    if ($users.Count -gt 0) {
                        $roleAssignments = (Invoke-PnPSPRestMethod -Connection $siteConnection -Method Get -Url "/_api/web/roleassignments?`$expand=Member,RoleDefinitionBindings" -ErrorAction SilentlyContinue).value
                        $allGroups = Get-PnPGroup -Connection $siteConnection -Includes Users -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    $errCode = "ERR-GUA-003"
                    $timestamp = (Get-Date -Format 'o')
                    Write-Error "[$errCode] ${timestamp}: Failed to process site collection '$site'. Resource: $site. Details: $($_.Exception.Message)" -ErrorAction Continue
                    continue
                }

                foreach ($user in $users) {
                    $upn = $user.LoginName
                    if ($user.LoginName -match '\|([^\|]+#ext#[^\|]+)' -or $user.LoginName -match '\|([^\|]+#EXT#[^\|]+)') {
                        $upn = $matches[1]
                    }

                    if (-not $guestDict.ContainsKey($upn)) {
                        $guestDict[$upn] = @{
                            DisplayName = if (-not [string]::IsNullOrEmpty($user.Title)) { $user.Title } else { "Guest User" }
                            Email = if ([string]::IsNullOrEmpty($user.Email)) { $upn } else { $user.Email }
                            UPN = $upn
                            InvitedBy = "Unknown"
                            SiteCount = 0
                            MaxPermission = 0
                            PermissionLevel = "Read"
                            LastAccess = "N/A"
                        }
                    }

                    $guestDict[$upn].SiteCount++
                    
                    $permLevel = 1
                    if ($user.IsSiteAdmin) {
                        $permLevel = 3
                    } else {
                        $roles = ""
                        
                        $userGroups = @()
                        if ($null -ne $allGroups) {
                            $userGroups = $allGroups | Where-Object { 
                                $_.Users.LoginName -contains $user.LoginName 
                            }
                        }

                        $userGroupLogins = @($userGroups.LoginName)
                        
                        $userRoles = $roleAssignments | Where-Object { 
                            $_.Member.LoginName -eq $user.LoginName -or 
                            $userGroupLogins -contains $_.Member.LoginName 
                        }

                        if ($userRoles) {
                            $roles = ($userRoles.RoleDefinitionBindings.Name | Select-Object -Unique) -join ','
                        }
                        
                        if ($roles -match "Full Control|Owner") {
                            $permLevel = 3
                        } elseif ($roles -match "Edit|Write|Contribute|Design") {
                            $permLevel = 2
                        } else {
                            $permLevel = 1
                        }
                    }

                    if ($permLevel -gt $guestDict[$upn].MaxPermission) {
                        $guestDict[$upn].MaxPermission = $permLevel
                        if ($permLevel -eq 3) { $guestDict[$upn].PermissionLevel = "Full Control" }
                        elseif ($permLevel -eq 2) { $guestDict[$upn].PermissionLevel = "Edit" }
                        else { $guestDict[$upn].PermissionLevel = "Read" }
                    }
                }
            }

            $guestUPNs = @($guestDict.Keys)
            $totalGuests = $guestUPNs.Count
            
            if ($totalGuests -gt 0) {
                Write-Verbose "Found $totalGuests unique guests. Querying Microsoft Graph for sign-in activity..."
                
                $graphToken = if ($script:SPCContext) { $script:SPCContext.GraphAccessToken } else { Get-PnPAccessToken -ResourceTypeName "Graph" -ErrorAction SilentlyContinue }
                $batchSize = 20
                $abortGraphQueries = $false

                for ($i = 0; $i -lt $totalGuests; $i += $batchSize) {
                    if ($abortGraphQueries) { break }

                    $batchUPNs = $guestUPNs[$i..([math]::Min($i + $batchSize - 1, $totalGuests - 1))]
                    
                    Write-Progress -Activity "Querying Graph API" -Status "Processing batch $([math]::Floor($i/$batchSize) + 1)" -PercentComplete (($i / $totalGuests) * 100)
                    
                    $retryCount = 0
                    $maxRetries = 5
                    $success = $false

                    while (-not $success -and $retryCount -lt $maxRetries) {
                        try {
                            $batchRequests = [System.Collections.Generic.List[hashtable]]::new()
                            foreach ($upn in $batchUPNs) {
                                # Escape single quotes in UPN if any, though rare
                                $safeUpn = $upn -replace "'", "''"
                                # We have to URL encode the # character for the query string
                                $encodedUpn = $safeUpn.Replace('#', '%23')
                                $batchRequests.Add(@{
                                    id = $upn
                                    method = "GET"
                                    url = "/users?`$filter=userPrincipalName eq '$encodedUpn'&`$select=displayName,givenName,surname,userPrincipalName,signInActivity,createdDateTime"
                                })
                            }

                            $batchResult = Invoke-SPCGraphBatch -Requests $batchRequests -AccessToken $graphToken -ErrorAction Stop
                            $success = $true
                            
                            if ($batchResult) {
                                foreach ($res in $batchResult) {
                                    $upn = $res.id
                                    if ($res.status -eq 200 -and $null -ne $res.body -and $null -ne $res.body.value -and $res.body.value.Count -gt 0) {
                                        $userObj = $res.body.value[0]
                                        if ($guestDict.ContainsKey($upn)) {
                                            if (-not [string]::IsNullOrWhiteSpace($userObj.displayName)) {
                                                $guestDict[$upn].DisplayName = $userObj.displayName
                                            } elseif (-not [string]::IsNullOrWhiteSpace($userObj.givenName) -or -not [string]::IsNullOrWhiteSpace($userObj.surname)) {
                                                $guestDict[$upn].DisplayName = ("$($userObj.givenName) $($userObj.surname)").Trim()
                                            }
                                            if ($null -ne $userObj.signInActivity -and -not [string]::IsNullOrEmpty($userObj.signInActivity.lastSignInDateTime)) {
                                                $guestDict[$upn].LastAccess = $userObj.signInActivity.lastSignInDateTime
                                            }
                                            if ($null -ne $userObj.invitedBy -and $null -ne $userObj.invitedBy.user -and -not [string]::IsNullOrEmpty($userObj.invitedBy.user.email)) {
                                                $guestDict[$upn].InvitedBy = $userObj.invitedBy.user.email
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        catch {
                            if ($_.Exception.Message -match "429") {
                                $retryCount++
                                $waitTime = [math]::Pow(2, $retryCount)
                                Write-Verbose "Throttled (429). Retrying in $waitTime seconds (Attempt $retryCount of $maxRetries)..."
                                Start-Sleep -Seconds $waitTime
                                 if ($retryCount -eq $maxRetries) {
                                    Write-Error "[ERR-GUA-004] $(Get-Date -Format 'o'): Failed to query Graph API for batch after $maxRetries retries. Resource: Tenant. Details: $($_.Exception.Message)" -ErrorAction Continue
                                }
                            } else {
                                Write-Error "[ERR-GUA-005] $(Get-Date -Format 'o'): Failed to query Graph API for batch. Resource: Tenant. Details: $($_.Exception.Message)" -ErrorAction Continue
                                $abortGraphQueries = $true
                                break
                            }
                        }
                    }
                }
            }

            foreach ($upn in $guestDict.Keys) {
                $guestInfo = $guestDict[$upn]

                $inactiveDays = 0
                $isInactiveOver180Days = $false
                $isInactiveOverThreshold = $false

                if ($guestInfo.LastAccess -ne "N/A") {
                    try {
                        $lastAccessDate = ([datetime]$guestInfo.LastAccess).ToUniversalTime()
                        $inactiveDays = ([DateTime]::UtcNow - $lastAccessDate).Days
                        if ($inactiveDays -gt 180) {
                            $isInactiveOver180Days = $true
                            $isInactiveOverThreshold = $true
                        } elseif ($inactiveDays -gt $DaysInactive) {
                            $isInactiveOverThreshold = $true
                        }
                    } catch {
                        Write-Verbose "Could not parse LastAccess date: $($guestInfo.LastAccess)"
                    }
                } else {
                    $isInactiveOver180Days = $true # Treat missing as highly risky/inactive
                }

                $riskLevel = "LOW"
                if ($guestInfo.PermissionLevel -match "Full Control|Owner" -or $isInactiveOver180Days) {
                    $riskLevel = "HIGH"
                    $highCount++
                } elseif ($guestInfo.PermissionLevel -match "Edit|Write|Contribute|Design" -or $isInactiveOverThreshold) {
                    $riskLevel = "MEDIUM"
                    $mediumCount++
                } else {
                    $riskLevel = "LOW"
                    $lowCount++
                }

                $outputObj = [PSCustomObject]@{
                    DisplayName     = if (-not [string]::IsNullOrWhiteSpace($guestInfo.DisplayName)) { $guestInfo.DisplayName } else { "Guest User" }
                    UPN             = if (-not [string]::IsNullOrWhiteSpace($guestInfo.UPN)) { $guestInfo.UPN } else { $upn }
                    GuestEmail      = $guestInfo.Email
                    InvitedBy       = $guestInfo.InvitedBy
                    LastAccess      = $guestInfo.LastAccess
                    SiteCount       = $guestInfo.SiteCount
                    PermissionLevel = $guestInfo.PermissionLevel
                    RiskLevel       = $riskLevel
                }

                $outputObj.PSObject.TypeNames.Insert(0, 'SPC.GuestUser')
                Write-Output $outputObj
            }
        }
        catch {
            $errCode = "ERR-GUA-500"
            throw "${errCode}: An unexpected error occurred while processing guests. Resource: Tenant. Time: $(Get-Date -Format 'o'). Details: $($_.Exception.Message)"
        }
    }

    end {
        $total = $highCount + $mediumCount + $lowCount
        Write-Information "Total: $total Guests - HIGH: $highCount, MEDIUM: $mediumCount, LOW: $lowCount"
    }
}
