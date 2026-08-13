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
            $siteConn = $null
            $tenantId = if ($script:SPCContext.TenantName -match '\.') { $script:SPCContext.TenantName } else { "$($script:SPCContext.TenantName).onmicrosoft.com" }

            if ($script:SPCContext.AuthMethod -eq 'Interactive') {
                $siteConn = Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $script:SPCContext._ClientId -ReturnConnection
            } elseif ($script:SPCContext._CertificateThumbprint) {
                $siteConn = Connect-PnPOnline -Url $SiteUrl -ClientId $script:SPCContext._ClientId -Tenant $tenantId -Thumbprint $script:SPCContext._CertificateThumbprint -ReturnConnection
            } elseif ($script:SPCContext._CertificatePath) {
                if ($null -ne $script:SPCContext._CertificatePassword) {
                    $siteConn = Connect-PnPOnline -Url $SiteUrl -ClientId $script:SPCContext._ClientId -Tenant $tenantId -CertificatePath $script:SPCContext._CertificatePath -CertificatePassword $script:SPCContext._CertificatePassword -ReturnConnection
                } else {
                    $siteConn = Connect-PnPOnline -Url $SiteUrl -ClientId $script:SPCContext._ClientId -Tenant $tenantId -CertificatePath $script:SPCContext._CertificatePath -ReturnConnection
                }
            } else {
                $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($script:SPCContext._ClientSecret)
                try {
                    $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                    $siteConn = Connect-PnPOnline -Url $SiteUrl -ClientId $script:SPCContext._ClientId -ClientSecret $plain -ReturnConnection
                } finally {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                    $plain = $null
                }
            }
            
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
