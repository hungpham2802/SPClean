

function Get-SPCLibraryBrokenInheritanceInternal {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteUrl
    )

    begin {
        Write-Verbose "Entering Get-SPCLibraryBrokenInheritanceInternal for Site: $SiteUrl"
    }

    process {
        try {
            Write-Verbose "Connecting to PnP Online for Site: $SiteUrl"
            $siteConn = Connect-SPCSiteInternal -SiteUrl $SiteUrl -Context $script:SPCContext
            
            $lists = Get-PnPList -Connection $siteConn -Includes HasUniqueRoleAssignments, RootFolder -ErrorAction Stop | Where-Object { $_.BaseType -eq 'DocumentLibrary' -and $_.Hidden -eq $false }
            
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
        } catch {
            Write-Error "ERR-201: Failed to fetch lists for site $SiteUrl. Details: $_"
        }
    }

    end {
        Write-Verbose "Completed Get-SPCLibraryBrokenInheritanceInternal for Site: $SiteUrl"
    }
}
