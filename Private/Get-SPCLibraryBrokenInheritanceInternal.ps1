

function Get-SPCLibraryBrokenInheritanceInternal {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteUrl,

        [Parameter()]
        [switch]$AddTempSiteCollectionAdmin
    )

    begin {
        Write-Verbose "Entering Get-SPCLibraryBrokenInheritanceInternal for Site: $SiteUrl"
    }

    process {
        $removeSca = $false
        $myUPN = $null
        $siteConn = $null

        try {
            Write-Verbose "Connecting to PnP Online for Site: $SiteUrl"
            $retryConnection = $true
            $attemptedSca = $false

            while ($retryConnection) {
                $retryConnection = $false
                try {
                    $siteConn = Connect-SPCSiteInternal -SiteUrl $SiteUrl -Context $script:SPCContext
                    $lists = Get-PnPList -Connection $siteConn -Includes HasUniqueRoleAssignments, RootFolder -ErrorAction Stop | Where-Object { $_.BaseType -eq 'DocumentLibrary' -and $_.Hidden -eq $false }
                }
                catch {
                    $ex = $_.Exception
                    if (($ex.Message -match "401|403|Access.*denied|Unauthorized|E_ACCESSDENIED|forbidden" -or $_.FullyQualifiedErrorId -match "401|403|Unauthorized|Access.*Denied") -and -not $attemptedSca) {
                        $attemptedSca = $true
                        if ($AddTempSiteCollectionAdmin) {
                            $authMethod = if ($script:SPCContext.AuthMethod) { $script:SPCContext.AuthMethod } else { $script:SPCContext.AuthMode }
                            if ($authMethod -ne 'Interactive') {
                                Write-Error "[ERR-GBI-004] $(Get-Date -Format 'o'): Access Denied on '$SiteUrl'. -AddTempSiteCollectionAdmin is only supported for Interactive auth. Resource: $SiteUrl." -ErrorAction Continue
                                return
                            }
                            Write-Verbose "Get-SPCLibraryBrokenInheritanceInternal: Access Denied on '$SiteUrl'. Attempting temporary elevation."
                            $elevationRecord = Invoke-SPCTempElevationInternal -SiteUrl $SiteUrl -Context $script:SPCContext
                            if ($elevationRecord.Success) {
                                $retryConnection = $true
                                continue
                            } else {
                                Write-Warning "[WARN-GBI-005] $(Get-Date -Format 'o'): Access Denied on '$SiteUrl'. Skipping restricted site. Details: $($elevationRecord.ErrorMessage)"
                                return
                            }
                        } else {
                            Write-Error "ERR-201: Access Denied fetching lists for site $SiteUrl. Details: $($ex.Message)"
                            return
                        }
                    } else {
                        Write-Error "ERR-201: Failed to fetch lists for site $SiteUrl. Details: $($_.Exception.Message)"
                        return
                    }
                }
            }
            
            if ($null -ne $lists) {
                foreach ($list in $lists) {
                    try {
                        if ($list.HasUniqueRoleAssignments) {
                            [PSCustomObject]@{
                                Path = $list.RootFolder.ServerRelativeUrl
                                Type = "Library"
                            }
                        }

                        Write-Verbose "Fetching items for list: $($list.Title) using pagination"
                        
                        $retryCount = 0
                        $maxRetries = 5
                        $success = $false
                        $items = $null

                        while (-not $success -and $retryCount -lt $maxRetries) {
                            try {
                                $items = Get-PnPListItem -Connection $siteConn -List $list.Title -PageSize 500 -Includes HasUniqueRoleAssignments, FileSystemObjectType -ErrorAction Stop
                                $success = $true
                            } catch {
                                if ($_.Exception.Message -match "429" -or $_.Exception.Message -match "Too Many Requests") {
                                    $retryCount++
                                    $waitTime = [math]::Pow(2, $retryCount)
                                    Write-Verbose "Throttling... retrying in $waitTime seconds (Attempt $retryCount of $maxRetries)"
                                    Start-Sleep -Seconds $waitTime
                                    if ($retryCount -ge $maxRetries) {
                                        throw "Exceeded maximum retries for list $($list.Title) due to throttling."
                                    }
                                } else {
                                    throw $_
                                }
                            }
                        }

                        if ($items) {
                            foreach ($item in $items) {
                                if ($item.HasUniqueRoleAssignments) {
                                    $itemUrl = ""
                                    if ($item.FieldValues.ContainsKey('FileRef')) {
                                        $itemUrl = $item.FieldValues['FileRef']
                                    } else {
                                        $itemUrl = "$($list.RootFolder.ServerRelativeUrl)/Item_$($item.Id)"
                                    }

                                    [PSCustomObject]@{
                                        Path = $itemUrl
                                        Type = if ($item.FileSystemObjectType -eq 'Folder') { "Folder" } else { "File/Item" }
                                    }
                                }
                            }
                        }
                    } catch {
                        Write-Error "ERR-202: Failed to process list $($list.Title) on site $SiteUrl. Details: $_"
                    }
                }
            }
        } finally {
            if ($elevationRecord -and $elevationRecord.Success) {
                Undo-SPCTempElevationInternal -ElevationRecord $elevationRecord -SiteConnection $siteConn -Context $script:SPCContext
            }
        }
    }

    end {
        Write-Verbose "Completed Get-SPCLibraryBrokenInheritanceInternal for Site: $SiteUrl"
    }
}
