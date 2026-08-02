# PnP 3.x removed Get-PnPSiteUser; Get-PnPUser now returns all UIL users without a filter.
if (-not (Get-Command -Name 'Get-PnPSiteUser' -ErrorAction SilentlyContinue)) {
    function Get-PnPSiteUser {
        [CmdletBinding()]
        param([Parameter()] [object] $Connection)
        $params = @{}; foreach ($k in $PSBoundParameters.Keys) { $params[$k] = $PSBoundParameters[$k] }
        & Get-PnPUser @params
    }
}

# PS wrappers with [object] Connection so Pester mocks don't enforce PnPConnection type coercion.
if (Get-Command -Name 'Get-PnPWeb' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
    $__pnpGetWeb = Get-Command 'Get-PnPWeb' -Module PnP.PowerShell
    function Get-PnPWeb {
        [CmdletBinding()] param([object]$Connection)
        & $__pnpGetWeb @PSBoundParameters
    }
}
if (Get-Command -Name 'Get-PnPUser' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
    $__pnpGetUser = Get-Command 'Get-PnPUser' -Module PnP.PowerShell
    function Get-PnPUser {
        [CmdletBinding()]
        param([object]$Connection, [switch]$WithRightsAssigned, [string]$LoginName, [string[]]$Includes)
        $params = @{}; foreach ($k in $PSBoundParameters.Keys) { $params[$k] = $PSBoundParameters[$k] }
        if ($params.ContainsKey('LoginName')) {
            $params['Identity'] = $params['LoginName']
            $params.Remove('LoginName') | Out-Null
        }
        & $__pnpGetUser @params
    }
}
if (Get-Command -Name 'Get-PnPSiteGroup' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
    $__pnpGetSiteGroup = Get-Command 'Get-PnPSiteGroup' -Module PnP.PowerShell
    function Get-PnPSiteGroup {
        [CmdletBinding()] param([object]$Connection)
        & $__pnpGetSiteGroup @PSBoundParameters
    }
}
if (Get-Command -Name 'Get-PnPGroupMember' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
    $__pnpGetGroupMember = Get-Command 'Get-PnPGroupMember' -Module PnP.PowerShell
    function Get-PnPGroupMember {
        [CmdletBinding()] param([object]$Group, [object]$Connection)
        $params = @{}; foreach ($k in $PSBoundParameters.Keys) { $params[$k] = $PSBoundParameters[$k] }
        $groupKey = if ($Group -is [string] -or $Group -is [int]) { $Group } else { [string]$Group.Title }
        $params['Group'] = $groupKey
        & $__pnpGetGroupMember @params
    }
}

function Get-SPCOrphanedUser {
    <#
    .SYNOPSIS
        Scans one or more SharePoint Online site collections and returns orphaned user objects.
    .DESCRIPTION
        Detects accounts still in the SharePoint User Information List (UIL) whose Entra ID state
        is Deleted, SoftDeleted, Disabled, or GuestOrphaned. Risk-classifies each result per SRS 3.2.2.
    .PARAMETER SiteUrl
        One or more full site collection URLs. Mutually exclusive with -AllSites.
        Accepts pipeline input.
    .PARAMETER AllSites
        Scan all site collections in the tenant. Requires SharePoint Admin role.
    .PARAMETER IncludeGuests
        Also detect orphaned external (#EXT#) accounts.
    .PARAMETER IncludeDisabled
        Also detect accounts that are disabled in Entra ID (OrphanType = 'Disabled').
    .PARAMETER ExcludeSiteUrl
        Site URLs to skip in an -AllSites scan. Supports wildcards (e.g. '*-my.sharepoint.com/*').
    .PARAMETER ThrottleLimit
        Maximum concurrent site connections. Default 3. Range 1-10; values outside are clamped.
    .EXAMPLE
        Get-SPCOrphanedUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR'
    .EXAMPLE
        Get-SPCOrphanedUser -AllSites -ExcludeSiteUrl '*-my.sharepoint.com/*' | Export-SPCReport -Path C:\report.html
    .OUTPUTS
        SPC.OrphanedUser
    #>
    [CmdletBinding(DefaultParameterSetName = 'SingleSite')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'SingleSite',
                   ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]] $SiteUrl,

        [Parameter(Mandatory, ParameterSetName = 'AllSites')]
        [switch] $AllSites,

        [Parameter()]
        [switch] $IncludeGuests,

        [Parameter()]
        [switch] $IncludeDisabled,

        [Parameter(ParameterSetName = 'AllSites')]
        [string[]] $ExcludeSiteUrl,

        [Parameter()]
        [switch] $AddTempSiteCollectionAdmin,

        [Parameter()]
        [int] $ThrottleLimit = 3
    )

    begin {
        Test-SPCConnection

        # SRS 3.2.1: ThrottleLimit range 1-10, clamp with warning
        $effectiveThrottle = $ThrottleLimit
        if ($ThrottleLimit -lt 1) {
            Write-Warning "ThrottleLimit $ThrottleLimit below minimum — clamped to 1."
            $effectiveThrottle = 1
        } elseif ($ThrottleLimit -gt 10) {
            Write-Warning "ThrottleLimit $ThrottleLimit exceeds maximum 10 — clamped to 10."
            $effectiveThrottle = 10
        }
        Write-Verbose "Get-SPCOrphanedUser: ThrottleLimit = $effectiveThrottle (sequential in PS 5.1)"

        $pendingSites = [System.Collections.Generic.List[string]]::new()

        if ($PSCmdlet.ParameterSetName -eq 'AllSites') {
            Write-Verbose 'Get-SPCOrphanedUser: Enumerating all tenant sites...'
            $tenantSites = Get-PnPTenantSite -Connection $script:SPCContext.PnPContext -ErrorAction Stop
            foreach ($site in $tenantSites) {
                if ($site.Template -like 'REDIRECTSITE#*') {
                    Write-Verbose "Get-SPCOrphanedUser: Skipping redirect site $($site.Url) ($($site.Template))"
                    continue
                }
                
                $excluded = $false
                if ($ExcludeSiteUrl) {
                    foreach ($pattern in $ExcludeSiteUrl) {
                        if ($site.Url -like $pattern) { $excluded = $true; break }
                    }
                }
                if (-not $excluded) { $pendingSites.Add($site.Url) }
            }
            Write-Verbose "Get-SPCOrphanedUser: $($pendingSites.Count) sites to scan."
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'SingleSite' -and $SiteUrl) {
            foreach ($url in $SiteUrl) { $pendingSites.Add($url) }
        }
    }

    end {
        # ScriptBlock used to connect to each site collection, reusing stored auth params
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

        # SRS 3.2.1: system account login name patterns to exclude (step 7)
        $systemPatterns = @(
            'SHAREPOINT\system',
            'NT AUTHORITY\authenticated users',
            'c:0(.s|true)',
            'Everyone except external users',
            'NT AUTHORITY\LOCAL SERVICE'
        )

        $ctx          = $script:SPCContext
        $graphToken   = $ctx.GraphAccessToken
        $total        = $pendingSites.Count
        $siteIdx      = 0
        $showProgress = $AllSites -or $total -gt 1

        foreach ($currentSiteUrl in $pendingSites) {
            $siteIdx++

            # Refresh Graph token if older than 50 minutes to avoid expiration during long scans
            $timeSinceConnect = (Get-Date).ToUniversalTime() - $ctx.ConnectedAt
            if ($timeSinceConnect.TotalMinutes -gt 50) {
                Write-Verbose "Get-SPCOrphanedUser: Graph token is older than 50 minutes. Refreshing..."
                $graphToken = Get-PnPGraphAccessToken -Connection $ctx.PnPContext
                $ctx.GraphAccessToken = $graphToken
                $ctx.ConnectedAt = (Get-Date).ToUniversalTime()
            }
            if ($showProgress) {
                Write-Progress -Activity 'Get-SPCOrphanedUser' `
                    -Status "[$siteIdx/$total] $currentSiteUrl" `
                    -PercentComplete ([int](($siteIdx / $total) * 100))
            }

            $removeSca = $false
            $myUPN = $null
            $siteConn = $null

            try {
                $siteConn = & $connectToSite -SiteUrl $currentSiteUrl -Ctx $ctx
            } catch {
                Write-Error "[ERR-GOU-001] $(Get-Date -Format 'o'): Cannot connect to site collection '$currentSiteUrl'. Resource: $currentSiteUrl. Details: $_" -ErrorAction Continue
                continue
            }

            try {
                $uilUsers = $null
                try {
                    # SRS step 6: retrieve all UIL users
                    Write-Verbose "Get-SPCOrphanedUser: Getting UIL for $currentSiteUrl"
                    $uilUsers  = Get-PnPSiteUser -Connection $siteConn -ErrorAction Stop
                } catch [System.UnauthorizedAccessException], [System.Exception] {
                    if ($_.Exception.Message -match "401" -or $_.Exception.Message -match "403" -or $_.Exception.Message -match "Access denied" -or $_.Exception.Message -match "Unauthorized") {
                        if ($AddTempSiteCollectionAdmin) {
                            if ($ctx.AuthMethod -ne 'Interactive') {
                                Write-Error "[ERR-GOU-002] $(Get-Date -Format 'o'): Access Denied on '$currentSiteUrl'. -AddTempSiteCollectionAdmin is only supported for Interactive auth. Resource: $currentSiteUrl." -ErrorAction Continue
                                continue
                            }
                            Write-Verbose "Get-SPCOrphanedUser: Access Denied. Attempting to add temporary Site Collection Admin rights."
                            try {
                                $me = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/me" -Headers @{ Authorization = "Bearer $($ctx.GraphAccessToken)" } -ErrorAction Stop
                                $myUPN = $me.userPrincipalName
                                
                                Set-PnPTenantSite -Connection $ctx.PnPContext -Url $currentSiteUrl -Owners $myUPN -ErrorAction Stop
                                $removeSca = $true
                                
                                Start-Sleep -Seconds 5
                                $siteConn = & $connectToSite -SiteUrl $currentSiteUrl -Ctx $ctx
                                $uilUsers = Get-PnPSiteUser -Connection $siteConn -ErrorAction Stop
                            } catch {
                                Write-Error "[ERR-GOU-003] $(Get-Date -Format 'o'): Failed to add temporary SCA or retry on '$currentSiteUrl'. Resource: $currentSiteUrl. Details: $_" -ErrorAction Continue
                                continue
                            }
                        } else {
                            Write-Error "[ERR-GOU-004] $(Get-Date -Format 'o'): Access Denied on '$currentSiteUrl'. You must be a Site Collection Administrator or use -AddTempSiteCollectionAdmin to scan. Resource: $currentSiteUrl." -ErrorAction Continue
                            continue
                        }
                    } else {
                        Write-Error "[ERR-GOU-005] $(Get-Date -Format 'o'): Error getting users for site collection '$currentSiteUrl'. Resource: $currentSiteUrl. Details: $_" -ErrorAction Continue
                        continue
                    }
                }
                $siteTitle = (Get-PnPWeb -Connection $siteConn -ErrorAction SilentlyContinue).Title

                # SRS step 7: filter system accounts
                # Note: i:0#.f|membership| is ALWAYS a real Entra user claim — never filter by empty
                # email for this claim type. Entra-deleted users lose their email in the SP UIL.
                $filteredUsers = $uilUsers | Where-Object {
                    $ln = $_.LoginName
                    $isSystem = $false
                    foreach ($p in $systemPatterns) {
                        if ($ln -eq $p) { $isSystem = $true; break }
                    }
                    -not $isSystem
                }

                if (-not $filteredUsers) { continue }

                # Build permission lookups once per site (O(groups × members))
                $directPermSet     = @{}
                $groupMembershipMap = @{}

                $directPermUsers = Get-PnPUser -WithRightsAssigned -Connection $siteConn `
                                       -ErrorAction SilentlyContinue
                foreach ($u in $directPermUsers) { $directPermSet[$u.LoginName] = $true }

                $siteGroups = Get-PnPSiteGroup -Connection $siteConn -ErrorAction SilentlyContinue
                foreach ($group in $siteGroups) {
                    $members = Get-PnPGroupMember -Group $group -Connection $siteConn `
                                   -ErrorAction SilentlyContinue
                    foreach ($m in $members) {
                        if (-not $groupMembershipMap.ContainsKey($m.LoginName)) {
                            $groupMembershipMap[$m.LoginName] = [System.Collections.Generic.List[string]]::new()
                        }
                        $groupMembershipMap[$m.LoginName].Add($group.Title)
                    }
                }

                # SRS step 8: extract UPN per user
                $requestIdMap  = @{}   # reqId → { User, UPN }
                $batchRequests = [System.Collections.Generic.List[hashtable]]::new()
                $reqId         = 1

                foreach ($user in $filteredUsers) {
                    $upn = if ($user.LoginName -like 'i:0#.f|membership|*') {
                        $user.LoginName -replace '^i:0#\.f\|membership\|', ''
                    } elseif ($user.Email) { $user.Email }
                    else { $null }

                    if (-not $upn) { continue }

                    $requestIdMap["$reqId"] = @{ User = $user; UPN = $upn }
                    $batchRequests.Add(@{
                        id     = "$reqId"
                        method = 'GET'
                        url    = "/users/$([uri]::EscapeDataString($upn))?`$select=id,displayName,givenName,surname,accountEnabled,userPrincipalName"
                    })
                    $reqId++
                }

                if ($batchRequests.Count -eq 0) { continue }

                # SRS step 9: first Graph batch — /users/{upn} lookups
                Write-Verbose "Get-SPCOrphanedUser: Graph batch — $($batchRequests.Count) users on $currentSiteUrl"
                $initialResponses = Invoke-SPCGraphBatch -Requests $batchRequests -AccessToken $graphToken

                $foundUsers    = @{}   # reqId → Graph user body (status 200)
                $notFoundItems = [System.Collections.Generic.List[hashtable]]::new()  # 404 entries

                foreach ($resp in $initialResponses) {
                    if (-not $requestIdMap.ContainsKey($resp.id)) { continue }
                    if ($resp.status -eq 200)  { $foundUsers[$resp.id] = $resp.body }
                    elseif ($resp.status -eq 404) { $notFoundItems.Add($requestIdMap[$resp.id]) }
                }

                # SRS step 10: SoftDeleted lookup (requires Directory.Read.All)
                $softDeletedUpns = @{}
                $softDeletedObjects = @{}
                if ($notFoundItems.Count -gt 0) {
                    Write-Verbose "Get-SPCOrphanedUser: Checking deleted items for $($notFoundItems.Count) missing users"
                    $delRequests = [System.Collections.Generic.List[hashtable]]::new()
                    $seenDelUpns = @{}
                    $delId = 1
                    foreach ($item in $notFoundItems) {
                        if (-not $seenDelUpns.ContainsKey($item.UPN)) {
                            $seenDelUpns[$item.UPN] = $true
                            $delRequests.Add(@{
                                id     = "del_$delId"
                                method = 'GET'
                                url    = "/directory/deletedItems/microsoft.graph.user?`$filter=userPrincipalName eq '$($item.UPN)'&`$select=id,userPrincipalName,displayName,givenName,surname"
                            })
                            $delId++
                        }
                    }
                    $delResponses = Invoke-SPCGraphBatch -Requests $delRequests -AccessToken $graphToken
                    foreach ($resp in $delResponses) {
                        if ($resp.status -eq 200 -and $resp.body.value -and $resp.body.value.Count -gt 0) {
                            $delItem = $resp.body.value[0]
                            $foundDelUpn = $delItem.userPrincipalName
                            if ($foundDelUpn) {
                                $softDeletedUpns[$foundDelUpn] = $true
                                $softDeletedObjects[$foundDelUpn] = $delItem
                            }
                        }
                    }
                }

                # Sign-in activity batch for found (200) users — requires AuditLog.Read.All
                $signInMap  = @{}   # reqId → DateTime
                $siRequests = [System.Collections.Generic.List[hashtable]]::new()
                $siReqToId  = @{}
                $siId       = 1
                foreach ($reqIdStr in $foundUsers.Keys) {
                    $userId = $foundUsers[$reqIdStr].id
                    if ($userId) {
                        $siReqToId["$siId"] = $reqIdStr
                        $siRequests.Add(@{
                            id     = "$siId"
                            method = 'GET'
                            url    = "/users/$userId/signInActivity"
                        })
                        $siId++
                    }
                }
                if ($siRequests.Count -gt 0) {
                    Write-Verbose "Get-SPCOrphanedUser: Sign-in activity for $($siRequests.Count) users"
                    $siResponses = Invoke-SPCGraphBatch -Requests $siRequests -AccessToken $graphToken
                    $warnedSignIn = $false
                    foreach ($resp in $siResponses) {
                        $origId = $siReqToId[$resp.id]
                        if ($resp.status -eq 403 -and -not $warnedSignIn) {
                            Write-Warning "SPClean: Unable to retrieve signInActivity. Missing 'AuditLog.Read.All' permission or Entra ID P1/P2 license. LastActivityDate will be empty."
                            $warnedSignIn = $true
                        } elseif ($origId -and $resp.status -eq 200 -and $resp.body.lastSignInDateTime) {
                            $signInMap[$origId] = [datetime]$resp.body.lastSignInDateTime
                        }
                    }
                }

                # SRS step 11: classify and emit SPC.OrphanedUser objects
                $detectedAt = (Get-Date).ToUniversalTime()

                foreach ($reqIdStr in $requestIdMap.Keys) {
                    $entry     = $requestIdMap[$reqIdStr]
                    $user      = $entry.User
                    $upn       = $entry.UPN
                    $isGuest   = $user.LoginName -like '*#EXT#*'
                    $graphUser = $foundUsers[$reqIdStr]   # $null when 404

                    # SRS 3.2.1 step 10: OrphanType classification
                    $orphanType = $null
                    if ($null -ne $graphUser) {
                        if (-not $graphUser.accountEnabled) {
                            if ($isGuest -and $IncludeGuests)          { $orphanType = 'GuestOrphaned' }
                            elseif (-not $isGuest -and $IncludeDisabled) { $orphanType = 'Disabled' }
                        }
                        # accountEnabled = true → active, not orphaned
                    } else {
                        if ($isGuest) {
                            if ($IncludeGuests) { $orphanType = 'GuestOrphaned' }
                        } elseif ($softDeletedUpns.ContainsKey($upn)) {
                            $orphanType = 'SoftDeleted'
                        } else {
                            $orphanType = 'Deleted'
                        }
                    }

                    if ($null -eq $orphanType) { continue }

                    $hasDirectPerms = $directPermSet.ContainsKey($user.LoginName)
                    $userGroups     = if ($groupMembershipMap.ContainsKey($user.LoginName)) {
                                          @($groupMembershipMap[$user.LoginName])
                                      } else { @() }

                    $riskLevel = Get-SPCRiskLevel `
                        -OrphanType           $orphanType `
                        -HasDirectPermissions $hasDirectPerms `
                        -GroupMembershipCount $userGroups.Count

                    $targetGraphUser = if ($null -ne $graphUser) {
                        $graphUser
                    } elseif ($null -ne $softDeletedObjects -and $softDeletedObjects.ContainsKey($upn)) {
                        $softDeletedObjects[$upn]
                    } else {
                        $null
                    }

                    $displayName = $null
                    if ($null -ne $targetGraphUser) {
                        if (-not [string]::IsNullOrWhiteSpace($targetGraphUser.displayName)) {
                            $displayName = $targetGraphUser.displayName
                        } elseif (-not [string]::IsNullOrWhiteSpace($targetGraphUser.givenName) -or -not [string]::IsNullOrWhiteSpace($targetGraphUser.surname)) {
                            $displayName = ("$($targetGraphUser.givenName) $($targetGraphUser.surname)").Trim()
                        }
                    }
                    if ([string]::IsNullOrWhiteSpace($displayName)) {
                        $displayName = $user.Title
                    }

                    $out = [PSCustomObject][ordered]@{
                        SiteUrl              = $currentSiteUrl
                        SiteTitle            = $siteTitle
                        UserId               = $user.Id
                        LoginName            = $user.LoginName
                        DisplayName          = $displayName
                        Email                = $user.Email
                        UPN                  = $upn
                        OrphanType           = $orphanType
                        RiskLevel            = $riskLevel
                        HasDirectPermissions = $hasDirectPerms
                        GroupMemberships     = $userGroups
                        LastActivityDate     = $signInMap[$reqIdStr]
                        DetectedAt           = $detectedAt
                    }
                    $out.PSObject.TypeNames.Insert(0, 'SPC.OrphanedUser')
                    $out   # SRS step 11: write to pipeline
                }
            } finally {
                if ($removeSca -and $myUPN) {
                    Write-Verbose "Get-SPCOrphanedUser: Removing temporary Site Collection Admin rights for $myUPN on $currentSiteUrl"
                    Remove-PnPSiteCollectionAdmin -Connection $siteConn -Owners $myUPN -ErrorAction SilentlyContinue
                }
            }

        }

        if ($showProgress) {
            Write-Progress -Activity 'Get-SPCOrphanedUser' -Completed
        }
    }
}
