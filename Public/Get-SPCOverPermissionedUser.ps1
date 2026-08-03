function Get-SPCOverPermissionedUser {
    <#
    .SYNOPSIS
        Identifies over-permissioned users based on an Excessive Access Score (EAS).
    
    .DESCRIPTION
        Scans site collections to determine user access levels (Full Control, Edit, Read).
        Calculates the Excessive Access Score (EAS) using the formula:
        EAS = (Full Control * 3) + (Edit * 2) + (Read * 1)
        Flags users with an EAS greater than 100 with a Red Alert.
    
    .EXAMPLE
        Get-SPCOverPermissionedUser -ClientId "app-id" -Thumbprint "cert-thumb" -Tenant "tenant.onmicrosoft.com"
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
        $tempResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        try {
            $sitesToScan = @()
            if ($SiteUrl) {
                $sitesToScan += $SiteUrl
            } else {
                Write-Verbose "Fetching all tenant sites..."
                $sitesToScan = Get-PnPTenantSite -Connection $script:SPCContext.PnPContext | Select-Object -ExpandProperty Url
            }

            $totalSites = $sitesToScan.Count
            $counter = 0

            foreach ($url in $sitesToScan) {
                $counter++
                Write-Progress -Activity "Scanning Sites for Over-Permissioned Users" -Status "Processing site $url ($counter / $totalSites)" -PercentComplete (($counter / $totalSites) * 100)
                Write-Verbose "Scanning site: $url"

                try {
                    $retryCount = 0
                    $maxRetries = 5
                    $success = $false
                    
                    while (-not $success -and $retryCount -lt $maxRetries) {
                        try {
                            $siteConnection = & $connectToSite -SiteUrl $url -Ctx $script:SPCContext
                            
                            $roleAssignments = (Invoke-PnPSPRestMethod -Method Get -Url "/_api/web/roleassignments?`$expand=Member,RoleDefinitionBindings" -Connection $siteConnection -ErrorAction SilentlyContinue).value
                            foreach ($ra in $roleAssignments) {
                                if ($ra.Member.PrincipalType -in 'User', 1 -and $ra.Member.LoginName -match "\|membership\|") {
                                    $upn = $ra.Member.LoginName.Split("|")[-1]
                                    
                                    $roles = $ra.RoleDefinitionBindings.Name
                                    $accessLevel = "None"
                                    if ($roles -contains "Full Control") {
                                        $accessLevel = "Full Control"
                                    } elseif ($roles -contains "Edit" -or $roles -contains "Contribute") {
                                        $accessLevel = "Edit"
                                    } elseif ($roles -contains "Read" -or $roles -contains "View Only") {
                                        $accessLevel = "Read"
                                    }
                                    
                                    if ($accessLevel -ne "None") {
                                        $tempResults.Add([PSCustomObject]@{
                                            UPN = $upn
                                            AccessLevel = $accessLevel
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
                                    Write-Error "[ERR-GOPU-001] $(Get-Date -Format 'o'): Failed to process site collection '$url' after $maxRetries attempts due to throttling. Resource: $url." -ErrorAction Continue
                                }
                            } else {
                                Write-Error "[ERR-GOPU-002] $(Get-Date -Format 'o'): Error processing site collection '$url'. Resource: $url. Details: $($ex.Message)" -ErrorAction Continue
                                $success = $true
                            }
                        }
                    }
                } catch {
                    Write-Error "[ERR-GOPU-003] $(Get-Date -Format 'o'): Error processing site collection '$url'. Resource: $url. Details: $($_.Exception.Message)" -ErrorAction Continue
                }
            }

            Write-Verbose "Calculating EAS..."
            $foundCount = 0
            if ($tempResults.Count -gt 0) {
                $grouped = $tempResults | Group-Object -Property UPN
                $finalResults = foreach ($g in $grouped) {
                    $fullControlCount = ($g.Group | Where-Object { $_.AccessLevel -eq 'Full Control' }).Count
                    $editCount = ($g.Group | Where-Object { $_.AccessLevel -eq 'Edit' }).Count
                    $readCount = ($g.Group | Where-Object { $_.AccessLevel -eq 'Read' }).Count
                    
                    $eas = ($fullControlCount * 3) + ($editCount * 2) + ($readCount * 1)
                    $isRedAlert = $eas -gt 100
                    
                    [PSCustomObject]@{
                        UPN = $g.Name
                        FullControlCount = $fullControlCount
                        EditCount = $editCount
                        ReadCount = $readCount
                        EAS = $eas
                        IsRedAlert = $isRedAlert
                    }
                }
                
                $sorted = $finalResults | Sort-Object -Property EAS -Descending
                $foundCount = $sorted.Count
                Write-Output $sorted
            } else {
                Write-Verbose "No users found."
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
        Write-Information -MessageData "Completed Get-SPCOverPermissionedUser scan. Scanned $counter sites, found $foundCount users." -InformationAction Continue
    }
}
