function Get-SPCOverPermissionedUser {
    <#
    .SYNOPSIS
        Identifies over-permissioned users based on an Excessive Access Score (EAS) (Focus on Breadth of Access).
    
    .DESCRIPTION
        Scans site collections to determine user access levels.
        Calculates the Excessive Access Score (EAS) using the formula:
        EAS = (Full Control * 3) + (Edit * 2) + (Read * 1)
        Flags users with an EAS greater than 100 with a Red Alert.
        
        Concept: Over-Permissioned Users focus on "Breadth of Access" or "Blast Radius" (Chiều rộng quyền hạn).
        Risk: These users have access to a vast amount of resources across the tenant, increasing the risk of widespread data leakage or ransomware infection (data infection) if compromised.
        
        Note: This cmdlet may miss Site Collection Administrators (SCA) because it relies on standard Role Assignments, which do not always enumerate SCAs explicitly.
    
    .EXAMPLE
        Get-SPCOverPermissionedUser
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
                Write-Progress -Activity "Scanning Sites for Over-Permissioned Users" -Status "Processing site $url ($counter / $totalSites)" -PercentComplete (($counter / $totalSites) * 100)
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
                            
                            $roleAssignments = (Invoke-PnPSPRestMethod -Method Get -Url "/_api/web/roleassignments?`$expand=Member,RoleDefinitionBindings" -Connection $siteConnection -ErrorAction Stop).value
                            if ($roleAssignments) {
                                foreach ($ra in $roleAssignments) {
                                    if ($ra.Member.PrincipalType -in 'User', 1 -and $ra.Member.LoginName -match "\|membership\|") {
                                        $upn = $ra.Member.LoginName.Split("|")[-1]
                                        
                                        $roles = $ra.RoleDefinitionBindings.Name
                                        $accessLevel = "None"
                                        if ($roles -contains "Full Control") {
                                            $accessLevel = "Full Control"
                                        }
                                        elseif ($roles -contains "Edit" -or $roles -contains "Contribute") {
                                            $accessLevel = "Edit"
                                        }
                                        elseif ($roles -contains "Read" -or $roles -contains "View Only") {
                                            $accessLevel = "Read"
                                        }
                                        
                                        if ($accessLevel -ne "None") {
                                            $tempResults.Add([PSCustomObject]@{
                                                    UPN         = $upn
                                                    AccessLevel = $accessLevel
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
                                    Write-Error "[ERR-GOPU-001] $(Get-Date -Format 'o'): Failed to process site collection '$url' after $maxRetries attempts due to throttling. Resource: $url." -ErrorAction Continue
                                }
                            }
                            elseif ($ex.Message -match "401" -or $ex.Message -match "403" -or $ex.Message -match "Access denied" -or $ex.Message -match "Unauthorized") {
                                if ($AddTempSiteCollectionAdmin) {
                                    $authMethod = if ($script:SPCContext.AuthMethod) { $script:SPCContext.AuthMethod } else { $script:SPCContext.AuthMode }
                                    if ($authMethod -ne 'Interactive') {
                                        Write-Error "[ERR-GOPU-004] $(Get-Date -Format 'o'): Access Denied on '$url'. -AddTempSiteCollectionAdmin is only supported for Interactive auth. Resource: $url." -ErrorAction Continue
                                        $success = $true
                                        continue
                                    }
                                    Write-Verbose "Get-SPCOverPermissionedUser: Access Denied on '$url'. Attempting temporary elevation."
                                    $elevationRecord = Invoke-SPCTempElevationInternal -SiteUrl $url -Context $script:SPCContext
                                    if ($elevationRecord.Success) {
                                        $siteConnection = Connect-SPCSiteInternal -SiteUrl $url -Context $script:SPCContext
                                        # Retry query in next iteration
                                    } else {
                                        Write-Warning "[WARN-GOPU-005] $(Get-Date -Format 'o'): Access Denied on site collection '$url'. Skipping restricted site. Details: $($elevationRecord.ErrorMessage)"
                                        $success = $true
                                    }
                                } else {
                                    Write-Error "[ERR-GOPU-002] $(Get-Date -Format 'o'): Error processing site collection '$url'. Resource: $url. Details: $($ex.Message)" -ErrorAction Continue
                                    $success = $true
                                }
                            }
                            else {
                                Write-Error "[ERR-GOPU-002] $(Get-Date -Format 'o'): Error processing site collection '$url'. Resource: $url. Details: $($ex.Message)" -ErrorAction Continue
                                $success = $true
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
                    
                    $obj = [PSCustomObject]@{
                        UPN              = $g.Name
                        FullControlCount = $fullControlCount
                        EditCount        = $editCount
                        ReadCount        = $readCount
                        EAS              = $eas
                        IsRedAlert       = $isRedAlert
                    }
                    $obj.PSObject.TypeNames.Insert(0, 'SPC.OverPermissionedUser')
                    $obj
                }
                
                $sorted = $finalResults | Sort-Object -Property EAS -Descending
                $foundCount = $sorted.Count
                Write-Output $sorted
            }
            else {
                Write-Verbose "No users found."
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
        Write-Information -MessageData "Completed Get-SPCOverPermissionedUser scan. Scanned $counter sites, found $foundCount users." -InformationAction Continue
    }
}
