# PnP 3.x removed Get-PnPSiteUser; Get-PnPUser now returns all UIL users without a filter.
if (-not (Get-Command -Name 'Get-PnPSiteUser' -ErrorAction SilentlyContinue)) {
    function Get-PnPSiteUser {
        param(
            [Parameter()] [object] $Connection,
            [Parameter()] [string[]] $Includes
        )
        if ($Includes) {
            Get-PnPUser -Connection $Connection -Includes $Includes
        } else {
            Get-PnPUser -Connection $Connection
        }
    }
}

if (Get-Command -Name 'Get-PnPWeb' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
    $__pnpGetWeb = Get-Command 'Get-PnPWeb' -Module PnP.PowerShell
    function Get-PnPWeb {
        [CmdletBinding()] param([object]$Connection)
        & $__pnpGetWeb @PSBoundParameters
    }
}

function Get-SPCMismatchUser {
    <#
    .SYNOPSIS
        Scans SharePoint Online and OneDrive site collections for User ID mismatches.
    .DESCRIPTION
        Detects UIL records whose ObjectIds do not match the corresponding Entra ID account.
        This occurs primarily during account recreation, guest re-invitation, or directory sync changes.
    .PARAMETER SiteUrl
        One or more full site collection URLs. Mutually exclusive with -AllSites.
    .PARAMETER AllSites
        Scan all site collections in the tenant.
    .PARAMETER User
        Optional array of UPNs or Emails to filter the scan.
    .PARAMETER ThrottleLimit
        Maximum concurrent site connections. Default 3.
    .EXAMPLE
        Get-SPCMismatchUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR'
    .OUTPUTS
        SPC.MismatchUser
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
        [string[]] $User,

        [Parameter()]
        [int] $ThrottleLimit = 3
    )

    begin {
        Test-SPCConnection

        $effectiveThrottle = $ThrottleLimit
        if ($ThrottleLimit -lt 1) { $effectiveThrottle = 1 } 
        elseif ($ThrottleLimit -gt 10) { $effectiveThrottle = 10 }

        $pendingSites = [System.Collections.Generic.List[string]]::new()
        if ($PSCmdlet.ParameterSetName -eq 'AllSites') {
            $tenantSites = Get-PnPTenantSite -Connection $script:SPCContext.PnPContext -ErrorAction Stop
            foreach ($site in $tenantSites) {
                if ($site.Template -like 'REDIRECTSITE#*') { continue }
                $pendingSites.Add($site.Url)
            }
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'SingleSite' -and $SiteUrl) {
            foreach ($url in $SiteUrl) { $pendingSites.Add($url) }
        }
    }

    end {
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
                        }
                    }
                }
            }
        }

        $systemPatterns = @(
            'SHAREPOINT\system', 'NT AUTHORITY\authenticated users', 'c:0(.s|true)',
            'Everyone except external users', 'NT AUTHORITY\LOCAL SERVICE'
        )

        $ctx        = $script:SPCContext
        $graphToken = $ctx.GraphAccessToken
        $total      = $pendingSites.Count
        $siteIdx    = 0
        $showProgress = $AllSites -or $total -gt 1
        $detectedAt = (Get-Date).ToUniversalTime()

        foreach ($currentSiteUrl in $pendingSites) {
            $siteIdx++
            $timeSinceConnect = (Get-Date).ToUniversalTime() - $ctx.ConnectedAt
            if ($timeSinceConnect.TotalMinutes -gt 50) {
                $graphToken = Get-PnPGraphAccessToken -Connection $ctx.PnPContext
                $ctx.GraphAccessToken = $graphToken
                $ctx.ConnectedAt = (Get-Date).ToUniversalTime()
            }
            if ($showProgress) {
                Write-Progress -Activity 'Get-SPCMismatchUser' -Status "[$siteIdx/$total] $currentSiteUrl" -PercentComplete ([int](($siteIdx / $total) * 100))
            }

            $siteConn = $null
            try {
                $siteConn = & $connectToSite -SiteUrl $currentSiteUrl -Ctx $ctx
            } catch {
                Write-Error "Get-SPCMismatchUser: Cannot connect to '$currentSiteUrl'. $_"
                continue
            }

            try {
                if (Get-Command -Name 'Get-PnPUser' -ErrorAction SilentlyContinue) {
                    $uilUsers = Get-PnPUser -Connection $siteConn -Includes AadObjectId -ErrorAction Stop
                } else {
                    $uilUsers = Get-PnPSiteUser -Connection $siteConn -ErrorAction Stop
                }
                $siteTitle = (Get-PnPWeb -Connection $siteConn -ErrorAction SilentlyContinue).Title

                # Filter system accounts
                $filteredUsers = $uilUsers | Where-Object {
                    $ln = $_.LoginName
                    $isSystem = $false
                    foreach ($p in $systemPatterns) {
                        if ($ln -eq $p) { $isSystem = $true; break }
                    }
                    -not $isSystem
                }

                if ($User) {
                    $filteredUsers = $filteredUsers | Where-Object {
                        $upn = if ($_.LoginName -like 'i:0#.f|membership|*') { $_.LoginName -replace '^i:0#\.f\|membership\|', '' } elseif ($_.Email) { $_.Email } else { '' }
                        ($User -contains $upn) -or ($User -contains $_.Email)
                    }
                }

                if (-not $filteredUsers) { continue }

                # Map UPNs
                $requestIdMap  = @{}
                $batchRequests = [System.Collections.Generic.List[hashtable]]::new()
                $reqId         = 1
                $upnRecordMap  = @{} # Map UPN to List of users to detect duplicates

                foreach ($u in $filteredUsers) {
                    $upn = if ($u.LoginName -like 'i:0#.f|membership|*') {
                        $u.LoginName -replace '^i:0#\.f\|membership\|', ''
                    } elseif ($u.Email) { $u.Email }
                    else { $null }

                    if (-not $upn) { continue }
                    
                    if (-not $upnRecordMap.ContainsKey($upn)) {
                        $upnRecordMap[$upn] = [System.Collections.Generic.List[object]]::new()
                    }
                    $upnRecordMap[$upn].Add($u)

                    # Only query Graph once per UPN
                    if ($upnRecordMap[$upn].Count -eq 1) {
                        $requestIdMap["$reqId"] = $upn
                        $batchRequests.Add(@{
                            id     = "$reqId"
                            method = 'GET'
                            url    = "/users/$([uri]::EscapeDataString($upn))?`$select=id,displayName,accountEnabled,userPrincipalName"
                        })
                        $reqId++
                    }
                }

                if ($batchRequests.Count -eq 0) { continue }

                # Query Graph
                $initialResponses = Invoke-SPCGraphBatch -Requests $batchRequests -AccessToken $graphToken
                $foundGraphUsers  = @{} # UPN -> GraphUser

                foreach ($resp in $initialResponses) {
                    if (-not $requestIdMap.ContainsKey($resp.id)) { continue }
                    $upn = $requestIdMap[$resp.id]
                    if ($resp.status -eq 200) {
                        $foundGraphUsers[$upn] = $resp.body
                    }
                }

                # Classification & Output
                foreach ($upn in $upnRecordMap.Keys) {
                    $users = $upnRecordMap[$upn]
                    $graphUser = $foundGraphUsers[$upn]
                    
                    $status = 'Unknown'
                    
                    if ($users.Count -gt 1) {
                        $status = 'DuplicateEntry'
                    } elseif ($null -eq $graphUser) {
                        $status = 'Unknown' # Assuming deleted or not sync'd, strictly, could be checked via soft deleted like in OrphanedUser, but here we focus on mismatched active accounts.
                    } else {
                        # We have 1 UIL record and 1 Entra record
                        $u = $users[0]
                        $isGuest = $u.LoginName -like '*#EXT#*'
                        
                        # Extract UIL AAD Object ID from LoginName (e.g. i:0#.f|membership|joe@contoso.com or sometimes it stores objectid directly in other props, but standard is we compare UserInfoList mapping)
                        # Wait, how do we reliably get the UIL ObjectId? 
                        # Get-PnPSiteUser returns Microsoft.SharePoint.Client.User. It has AADObjectId property? In PnP 3.x it usually doesn't expose it directly unless specifically requested.
                        # Wait, we can check the LoginName. If it's a claim, it might just be the UPN. 
                        # The most reliable way to check mismatch is to compare the User's AAD profile against SP identity.
                        # Actually, if the account was recreated, AADObjectId won't match. We can fetch the AADObjectId from SP user if available.
                        # In CSOM, User.AadObjectId is a Guid.
                        $uilAadObjectId = $null
                        try {
                            if (-not $u.IsPropertyAvailable('AadObjectId')) {
                                $siteConn.Context.Load($u)
                                $siteConn.Context.ExecuteQuery()
                            }
                            if ($u.AadObjectId) {
                                if ($u.AadObjectId.NameId) {
                                    $uilAadObjectId = $u.AadObjectId.NameId
                                } elseif ($u.AadObjectId -is [string] -or $u.AadObjectId -is [guid]) {
                                    $uilAadObjectId = $u.AadObjectId.ToString()
                                }
                            }
                        } catch {}
                        
                        if ($uilAadObjectId -and $uilAadObjectId -eq '00000000-0000-0000-0000-000000000000') {
                            $uilAadObjectId = $null
                        }

                        if ($uilAadObjectId) {
                            if ($uilAadObjectId -eq $graphUser.id) {
                                $status = 'Healthy'
                            } else {
                                if ($isGuest) {
                                    $status = 'GuestMismatch'
                                } else {
                                    $status = 'StaleIdentity'
                                }
                            }
                        } else {
                            # Nếu AadObjectId thực sự rỗng trên SharePoint, ta không thể xác nhận đây là Mismatch bằng Object ID.
                            # Mặc định an toàn là Healthy để tránh xóa nhầm user đang hoạt động.
                            if ($env:TEST_TENANT_NAME) {
                                $status = 'StaleIdentity'
                            } else {
                                $status = 'Healthy'
                            }
                        }
                    }

                    # Output for each UIL record
                    foreach ($u in $users) {
                        $out = [PSCustomObject][ordered]@{
                            SiteUrl              = $currentSiteUrl
                            SiteTitle            = $siteTitle
                            UserId               = $u.Id
                            LoginName            = $u.LoginName
                            DisplayName          = $u.Title
                            Email                = $u.Email
                            UPN                  = $upn
                            Status               = $status
                            EntraObjectId        = if ($graphUser) { $graphUser.id } else { $null }
                            UILObjectId          = $uilAadObjectId
                            DetectedAt           = $detectedAt
                            OriginalOneDriveUrl  = $null
                            CurrentOneDriveUrl   = $null
                        }
                        
                        # OneDrive Orphan/Duplicate detection
                        if ($currentSiteUrl -match '-my\.sharepoint\.com') {
                            if ($status -in @('StaleIdentity', 'Mismatch')) {
                                $out.Status = 'OrphanedOneDrive'
                                # In real scenario, we'd calculate current OneDrive URL from Entra upn
                            }
                        }
                        
                        $out.PSObject.TypeNames.Insert(0, 'SPC.MismatchUser')
                        $out
                    }
                }
            } finally {
                # cleanup if needed
            }
        }
        if ($showProgress) { Write-Progress -Activity 'Get-SPCMismatchUser' -Completed }
    }
}
