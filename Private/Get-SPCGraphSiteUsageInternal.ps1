function Get-SPCGraphSiteUsageInternal {
    <#
    .SYNOPSIS
        Retrieves SharePoint site usage metrics via Microsoft Graph REST API.
    .DESCRIPTION
        Queries /reports/getSharePointSiteUsageDetail with automatic HTTP 429 exponential backoff and jitter.
    .OUTPUTS
        [System.Collections.Generic.List[PSCustomObject]]
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('D7', 'D30', 'D90', 'D180')]
        [string]$Period = 'D180'
    )

    $endpoint = "https://graph.microsoft.com/v1.0/reports/getSharePointSiteUsageDetail(period='$Period')"
    $token = $script:SPCContext.GraphAccessToken
    $headers = @{
        'Authorization'    = "Bearer $token"
        'ConsistencyLevel' = 'eventual'
    }

    $maxRetries = 5
    $retryCount = 0
    $backoffSec = 2

    while ($retryCount -lt $maxRetries) {
        try {
            Write-Verbose "Querying Graph Site Usage Report: $endpoint"
            $csvResponse = Invoke-RestMethod -Uri $endpoint -Headers $headers -Method Get -ErrorAction Stop
            
            # Graph reports endpoint returns CSV content directly
            $rows = $csvResponse | ConvertFrom-Csv
            $result = [System.Collections.Generic.List[PSCustomObject]]::new()

            if ($null -ne $rows) {
                # Check if Site URLs are concealed due to M365 privacy settings
                $isConcealed = $false
                $firstRowWithId = $rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.'Site Id') } | Select-Object -First 1
                if ($firstRowWithId -and [string]::IsNullOrWhiteSpace($firstRowWithId.'Site URL')) {
                    $isConcealed = $true
                }

                $pnpSiteLookup = @{}
                if ($isConcealed -and $script:SPCContext.PnPContext) {
                    try {
                        Write-Verbose "Get-SPCGraphSiteUsageInternal: Detected M365 report privacy concealment. Resolving site URLs via PnP tenant query."
                        $tenantSites = Get-PnPTenantSite -Connection $script:SPCContext.PnPContext -ErrorAction SilentlyContinue
                        if ($tenantSites) {
                            foreach ($ts in $tenantSites) {
                                if ($ts.SiteId) {
                                    $pnpSiteLookup[$ts.SiteId.ToString().ToLower()] = $ts
                                }
                            }
                        }
                    } catch {
                        Write-Verbose "Get-SPCGraphSiteUsageInternal: PnP tenant site lookup for privacy concealment failed: $($_.Exception.Message)"
                    }
                }

                foreach ($r in $rows) {
                    $siteIdKey = if (-not [string]::IsNullOrWhiteSpace($r.'Site Id')) { $r.'Site Id'.ToString().ToLower() } else { $null }
                    $pnpMatch = if ($siteIdKey -and $pnpSiteLookup.ContainsKey($siteIdKey)) { $pnpSiteLookup[$siteIdKey] } else { $null }

                    $resolvedUrl = if (-not [string]::IsNullOrWhiteSpace($r.'Site URL')) {
                        $r.'Site URL'
                    } elseif ($pnpMatch) {
                        $pnpMatch.Url
                    } else {
                        $null
                    }

                    $resolvedTitle = if (-not [string]::IsNullOrWhiteSpace($r.'Site Title')) {
                        $r.'Site Title'
                    } elseif ($pnpMatch -and -not [string]::IsNullOrWhiteSpace($pnpMatch.Title)) {
                        $pnpMatch.Title
                    } elseif (-not [string]::IsNullOrWhiteSpace($r.'Owner Display Name')) {
                        $r.'Owner Display Name'
                    } else {
                        $null
                    }

                    $storageBytes = [int64]0
                    if ($null -ne $r.'Storage Used (Byte)') {
                        [int64]::TryParse($r.'Storage Used (Byte)', [ref]$storageBytes) | Out-Null
                    }
                    $storageMB = [Math]::Round(($storageBytes / 1MB), 2)

                    $fileCount = [int64]0
                    if ($null -ne $r.'File Count') {
                        [int64]::TryParse($r.'File Count', [ref]$fileCount) | Out-Null
                    }

                    $lastActivity = $null
                    if (-not [string]::IsNullOrWhiteSpace($r.'Last Activity Date')) {
                        $parsedDate = [datetime]::MinValue
                        if ([datetime]::TryParse($r.'Last Activity Date', [ref]$parsedDate)) {
                            $lastActivity = $parsedDate
                        }
                    }

                    $ownerUPN = if (-not [string]::IsNullOrWhiteSpace($r.'Site Owner Principal Name')) {
                        $r.'Site Owner Principal Name'
                    } elseif (-not [string]::IsNullOrWhiteSpace($r.'Owner Display Name')) {
                        $r.'Owner Display Name'
                    } elseif ($pnpMatch -and -not [string]::IsNullOrWhiteSpace($pnpMatch.Owner)) {
                        $pnpMatch.Owner
                    } else {
                        'Unknown'
                    }

                    $result.Add([PSCustomObject]@{
                        SiteUrl          = $resolvedUrl
                        SiteTitle        = $resolvedTitle
                        GroupId          = if (-not [string]::IsNullOrWhiteSpace($r.'Group ID')) { $r.'Group ID' } elseif ($pnpMatch) { $pnpMatch.GroupId } else { $null }
                        Template         = if (-not [string]::IsNullOrWhiteSpace($r.'Root Web Template')) { $r.'Root Web Template' } elseif ($pnpMatch) { $pnpMatch.Template } else { $null }
                        StorageUsedMB    = $storageMB
                        FileCount        = $fileCount
                        LastActivityDate = $lastActivity
                        LockState        = if (-not [string]::IsNullOrWhiteSpace($r.'Lock State')) { $r.'Lock State' } elseif ($pnpMatch) { $pnpMatch.LockState } else { $null }
                        OwnerUPN         = $ownerUPN
                        IsTeamSite       = (-not [string]::IsNullOrWhiteSpace($r.'Group ID') -or ($pnpMatch -and -not [string]::IsNullOrWhiteSpace($pnpMatch.GroupId) -and $pnpMatch.GroupId -ne [Guid]::Empty.ToString()))
                    })
                }
            }
            return $result
        }
        catch {
            $statusCode = $null
            if ($_.Exception -and $_.Exception.Response) {
                if ($_.Exception.Response.StatusCode) {
                    if ($_.Exception.Response.StatusCode.value__) {
                        $statusCode = $_.Exception.Response.StatusCode.value__
                    } else {
                        $statusCode = [int]$_.Exception.Response.StatusCode
                    }
                }
            }

            if ($statusCode -in @(429, 503)) {
                $retryCount++
                $retryAfter = $null
                if ($_.Exception.Response.Headers -and $_.Exception.Response.Headers['Retry-After']) {
                    $retryAfter = $_.Exception.Response.Headers['Retry-After']
                }
                $sleepDuration = if ($retryAfter) { [int]$retryAfter } else { $backoffSec }
                
                # Add jitter
                $jitter = (Get-Random -Minimum 100 -Maximum 1000) / 1000.0
                $totalSleep = $sleepDuration + $jitter

                Write-Warning "ERR-STO-104: Microsoft Graph API Throttled (HTTP $statusCode). Retrying in $totalSleep seconds (Attempt $retryCount of $maxRetries)..."
                Start-Sleep -Seconds $totalSleep
                $backoffSec *= 2
            } else {
                Write-Verbose "Get-SPCGraphSiteUsageInternal: Graph report request failed ($($_.Exception.Message)). Falling back to PnP Tenant Sites query."
                try {
                    $tenantSites = if (Get-Command -Name 'Get-PnPTenantSite' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
                        Get-PnPTenantSite -Connection $script:SPCContext.PnPContext -ErrorAction Stop
                    } else { @() }

                    $fallbackResult = [System.Collections.Generic.List[PSCustomObject]]::new()
                    foreach ($ts in $tenantSites) {
                        if ($ts.Template -like 'REDIRECTSITE#*' -or $ts.Template -like 'POINTPUBLISHINGHUB#*') {
                            continue
                        }
                        $mb = [Math]::Round(($ts.StorageUsageCurrent), 2)
                        $fallbackResult.Add([PSCustomObject]@{
                            SiteUrl          = $ts.Url
                            SiteTitle        = $ts.Title
                            GroupId          = $ts.GroupId
                            Template         = $ts.Template
                            StorageUsedMB    = $mb
                            FileCount        = 0
                            LastActivityDate = $ts.LastContentModifiedDate
                            LockState        = $ts.LockState
                            OwnerUPN         = $ts.Owner
                            IsTeamSite       = (-not [string]::IsNullOrWhiteSpace($ts.GroupId) -and $ts.GroupId -ne [Guid]::Empty.ToString())
                        })
                    }
                    return $fallbackResult
                }
                catch {
                    throw "ERR-STO-102: Failed to fetch Graph Site Usage Report and PnP fallback failed: $($_.Exception.Message)"
                }
            }
        }
    }
    throw "ERR-STO-104: Exceeded maximum retry attempts for Microsoft Graph Site Usage Report."
}
