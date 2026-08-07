function Invoke-SPCGraphBatch {
    <#
    .SYNOPSIS
        Sends Microsoft Graph JSON batch requests per SRS 5.1 (max 20/batch, 429 retry).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[hashtable]] $Requests,

        # If omitted, retrieved from the active PnP connection via Get-PnPGraphAccessToken.
        [Parameter()]
        [string] $AccessToken
    )

    begin {
        $batchUri    = 'https://graph.microsoft.com/v1.0/$batch'
        $allResponses = [System.Collections.Generic.List[object]]::new()
        
        $useMgGraph = $false
        if ([string]::IsNullOrWhiteSpace($AccessToken)) {
            $useMgGraph = $true
        } else {
            $headers = @{
                Authorization  = "Bearer $AccessToken"
                'Content-Type' = 'application/json'
            }
        }
    }

    process {
        if ($Requests.Count -eq 0) { return }

        # SRS 5.1: max 20 requests per batch call
        $batchSize = 20
        for ($offset = 0; $offset -lt $Requests.Count; $offset += $batchSize) {
            $chunk = [System.Linq.Enumerable]::Skip($Requests, $offset) |
                     Select-Object -First $batchSize

            $idx = 1
            $currentRequests = [System.Collections.Generic.List[hashtable]]::new()
            foreach ($req in $chunk) {
                # Use caller-supplied id (for correlation) or fall back to sequential
                $reqId = if ($req.ContainsKey('id')) { $req['id'] } else { "$idx" }
                $currentRequests.Add(@{ id = $reqId; method = $req.method; url = $req.url })
                $idx++
            }

            # Inner sub-request retry loop (up to 5 attempts per batch chunk)
            $subAttempt = 0
            $maxAttempts = 5

            while ($currentRequests.Count -gt 0 -and $subAttempt -lt $maxAttempts) {
                $body = @{ requests = @($currentRequests) } | ConvertTo-Json -Depth 5

                # Envelope HTTP retry loop (for outer 429 envelope throttling)
                $envelopeAttempt = 0
                $result = $null

                do {
                    try {
                        if ($useMgGraph) {
                            $result = Invoke-MgGraphRequest -Method POST -Uri $batchUri -Body $body -ContentType "application/json" -ErrorAction Stop
                        } else {
                            $result = Invoke-RestMethod -Uri $batchUri -Method Post -Headers $headers -Body $body -ErrorAction Stop
                        }
                        break # Envelope request succeeded
                    } catch {
                        $statusCode = 0
                        if ($useMgGraph -and $_.Exception.ResponseStatusCode) {
                            $statusCode = [int]$_.Exception.ResponseStatusCode
                        } elseif (-not $useMgGraph -and $_.Exception.Response) {
                            $statusCode = [int]$_.Exception.Response.StatusCode
                        }

                        if ($statusCode -eq 429) {
                            $envelopeAttempt++
                            if ($envelopeAttempt -ge $maxAttempts) {
                                throw "ERR-429: Graph API envelope batch request throttled after $maxAttempts retry attempts: $($_.Exception.Message)"
                            }

                            $retryAfterSec = 0
                            if ($_.Exception.Response -and $_.Exception.Response.Headers) {
                                try {
                                    $retryHeader = $_.Exception.Response.Headers['Retry-After']
                                    if ($retryHeader) { $retryAfterSec = [int]$retryHeader }
                                } catch {}
                            }

                            $wait = if ($retryAfterSec -gt 0) { $retryAfterSec * 1000 } else { [Math]::Min([Math]::Pow(2, $envelopeAttempt) * 1000, 60000) }
                            Write-Verbose "Graph $batchUri envelope throttled (429) — waiting ${wait}ms (attempt $envelopeAttempt)"
                            Start-Sleep -Milliseconds $wait
                        } else {
                            throw
                        }
                    }
                } while ($envelopeAttempt -lt $maxAttempts)

                # Process sub-request responses
                $nextRequests = [System.Collections.Generic.List[hashtable]]::new()
                $maxSubRetryAfterMs = 0

                if ($result -and $result.responses) {
                    foreach ($r in $result.responses) {
                        # Handle inner sub-request 429 status codes
                        $rStatus = if ($r.status) { [int]$r.status } else { 0 }
                        if ($rStatus -eq 429) {
                            # Extract Retry-After header if present in sub-response headers
                            $retryAfterSec = 0
                            if ($r.headers) {
                                if ($r.headers -is [hashtable] -or $r.headers -is [System.Collections.IDictionary]) {
                                    if ($r.headers.ContainsKey('Retry-After')) { [int]::TryParse([string]$r.headers['Retry-After'], [ref]$retryAfterSec) | Out-Null }
                                    elseif ($r.headers.ContainsKey('retry-after')) { [int]::TryParse([string]$r.headers['retry-after'], [ref]$retryAfterSec) | Out-Null }
                                } else {
                                    $p = $r.headers.PSObject.Properties['Retry-After']
                                    if (-not $p) { $p = $r.headers.PSObject.Properties['retry-after'] }
                                    if ($p) { [int]::TryParse([string]$p.Value, [ref]$retryAfterSec) | Out-Null }
                                }
                            }

                            $subWaitMs = if ($retryAfterSec -gt 0) { $retryAfterSec * 1000 } else { [Math]::Min([Math]::Pow(2, $subAttempt + 1) * 1000, 60000) }
                            if ($subWaitMs -gt $maxSubRetryAfterMs) { $maxSubRetryAfterMs = $subWaitMs }

                            # Find matching original request object to retry
                            $matchingReq = $currentRequests | Where-Object { $_.id -eq [string]$r.id } | Select-Object -First 1
                            if ($matchingReq) {
                                $nextRequests.Add($matchingReq)
                            }
                        } else {
                            # Non-429 response — store in final responses
                            $allResponses.Add($r)
                        }
                    }
                }

                if ($nextRequests.Count -eq 0) {
                    # All sub-requests completed
                    break
                }

                $subAttempt++
                if ($subAttempt -ge $maxAttempts) {
                    Write-Verbose "Graph batch sub-requests throttled — max attempts ($maxAttempts) reached for $($nextRequests.Count) requests."
                    # Append remaining 429 responses to output so downstream can process/log status
                    if ($result -and $result.responses) {
                        foreach ($r in $result.responses) {
                            if ([int]$r.status -eq 429) {
                                $allResponses.Add($r)
                            }
                        }
                    }
                    break
                }

                $currentRequests = $nextRequests
                $waitMs = if ($maxSubRetryAfterMs -gt 0) { $maxSubRetryAfterMs } else { [Math]::Min([Math]::Pow(2, $subAttempt) * 1000, 60000) }
                Write-Verbose "Graph batch sub-requests throttled (429) — retrying $($currentRequests.Count) sub-requests in ${waitMs}ms (attempt $subAttempt of $maxAttempts)"
                Start-Sleep -Milliseconds $waitMs
            }
        }
    }

    end {
        $allResponses
    }
}
