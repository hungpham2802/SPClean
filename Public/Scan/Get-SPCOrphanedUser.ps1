# PnP 3.x removed Get-PnPSiteUser; Get-PnPUser now returns all UIL users without a filter.
if (-not (Get-Command -Name 'Get-PnPSiteUser' -ErrorAction SilentlyContinue)) {
    function Get-PnPSiteUser {
        [CmdletBinding()]
        param([Parameter()] [object] $Connection)
        Get-PnPUser -Connection $Connection -ErrorAction SilentlyContinue
    }
}

# PS wrappers with [object] Connection so Pester mocks don't enforce PnPConnection type coercion.
if (Get-Command -Name 'Get-PnPWeb' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
    $__pnpGetWeb = Get-Command 'Get-PnPWeb' -Module PnP.PowerShell
    function Get-PnPWeb {
        [CmdletBinding()] param([object]$Connection)
        & $__pnpGetWeb -Connection $Connection -ErrorAction SilentlyContinue
    }
}
if (Get-Command -Name 'Get-PnPUser' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
    $__pnpGetUser = Get-Command 'Get-PnPUser' -Module PnP.PowerShell
    function Get-PnPUser {
        [CmdletBinding()]
        param([object]$Connection, [switch]$WithRightsAssigned, [string]$LoginName)
        if ($LoginName) {
            # PnP 3.x uses -Identity (UserPipeBind), not -LoginName
            & $__pnpGetUser -Identity $LoginName -Connection $Connection -ErrorAction SilentlyContinue
        } elseif ($WithRightsAssigned) {
            & $__pnpGetUser -WithRightsAssigned -Connection $Connection -ErrorAction SilentlyContinue
        } else {
            & $__pnpGetUser -Connection $Connection -ErrorAction SilentlyContinue
        }
    }
}
if (Get-Command -Name 'Get-PnPSiteGroup' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
    $__pnpGetSiteGroup = Get-Command 'Get-PnPSiteGroup' -Module PnP.PowerShell
    function Get-PnPSiteGroup {
        [CmdletBinding()] param([object]$Connection)
        & $__pnpGetSiteGroup -Connection $Connection -ErrorAction SilentlyContinue
    }
}
if (Get-Command -Name 'Get-PnPGroupMember' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
    $__pnpGetGroupMember = Get-Command 'Get-PnPGroupMember' -Module PnP.PowerShell
    function Get-PnPGroupMember {
        [CmdletBinding()] param([object]$Group, [object]$Connection)
        # GroupPipeBind accepts string (title) or int (id); $Group.Id is null in PnP 3.x (CSOM lazy load),
        # so use Title (string) for groups, pass through ints/strings unchanged
        $groupKey = if ($Group -is [string] -or $Group -is [int]) { $Group } else { [string]$Group.Title }
        & $__pnpGetGroupMember -Group $groupKey -Connection $Connection -ErrorAction SilentlyContinue
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
                    Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $Ctx._ClientId -ReturnConnection
                }
                'AppOnly' {
                    if ($Ctx._CertificatePath) {
                        Connect-PnPOnline -Url $SiteUrl -ClientId $Ctx._ClientId `
                            -Tenant $tenantId `
                            -CertificatePath $Ctx._CertificatePath `
                            -CertificatePassword $Ctx._CertificatePassword -ReturnConnection
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
            if ($showProgress) {
                Write-Progress -Activity 'Get-SPCOrphanedUser' `
                    -Status "[$siteIdx/$total] $currentSiteUrl" `
                    -PercentComplete ([int](($siteIdx / $total) * 100))
            }

            try {
                $siteConn = & $connectToSite -SiteUrl $currentSiteUrl -Ctx $ctx
            } catch {
                Write-Error "Get-SPCOrphanedUser: Cannot connect to '$currentSiteUrl'. $_"
                continue
            }

            # SRS step 6: retrieve all UIL users
            Write-Verbose "Get-SPCOrphanedUser: Getting UIL for $currentSiteUrl"
            $uilUsers  = Get-PnPSiteUser -Connection $siteConn -ErrorAction Stop
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
                    url    = "/users/$([uri]::EscapeDataString($upn))?`$select=id,displayName,accountEnabled,userPrincipalName"
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

            # SRS step 10: soft-deleted check for all 404 users
            $softDeletedUpns = @{}
            if ($notFoundItems.Count -gt 0) {
                $sdRequests = [System.Collections.Generic.List[hashtable]]::new()
                $sdReqToUpn = @{}
                $sdId       = 1
                foreach ($entry in $notFoundItems) {
                    $sdReqToUpn["$sdId"] = $entry.UPN
                    $sdRequests.Add(@{
                        id     = "$sdId"
                        method = 'GET'
                        url    = "/directory/deletedItems/microsoft.graph.user?`$filter=userPrincipalName eq '$($entry.UPN)'&`$select=id,userPrincipalName"
                    })
                    $sdId++
                }
                Write-Verbose "Get-SPCOrphanedUser: Soft-delete check for $($sdRequests.Count) users"
                $sdResponses = Invoke-SPCGraphBatch -Requests $sdRequests -AccessToken $graphToken
                foreach ($resp in $sdResponses) {
                    if ($resp.status -eq 200 -and $resp.body.value.Count -gt 0) {
                        $softDeletedUpns[$sdReqToUpn[$resp.id]] = $true
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
                foreach ($resp in $siResponses) {
                    $origId = $siReqToId[$resp.id]
                    if ($origId -and $resp.status -eq 200 -and $resp.body.lastSignInDateTime) {
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

                $out = [PSCustomObject][ordered]@{
                    SiteUrl              = $currentSiteUrl
                    SiteTitle            = $siteTitle
                    UserId               = $user.Id
                    LoginName            = $user.LoginName
                    DisplayName          = $user.Title
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
        }

        if ($showProgress) {
            Write-Progress -Activity 'Get-SPCOrphanedUser' -Completed
        }
    }
}
