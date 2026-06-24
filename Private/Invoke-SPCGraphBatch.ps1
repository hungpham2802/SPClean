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
        if ([string]::IsNullOrWhiteSpace($AccessToken)) {
            $AccessToken = Get-PnPGraphAccessToken
        }
        $batchUri    = 'https://graph.microsoft.com/v1.0/$batch'
        $headers     = @{
            Authorization  = "Bearer $AccessToken"
            'Content-Type' = 'application/json'
        }
        $allResponses = [System.Collections.Generic.List[object]]::new()
    }

    process {
        if ($Requests.Count -eq 0) { return }

        # SRS 5.1: max 20 requests per batch call
        $batchSize = 20
        for ($offset = 0; $offset -lt $Requests.Count; $offset += $batchSize) {
            $chunk = [System.Linq.Enumerable]::Skip($Requests, $offset) |
                     Select-Object -First $batchSize

            $idx = 1
            $batchRequests = foreach ($req in $chunk) {
                # Use caller-supplied id (for correlation) or fall back to sequential
                $reqId = if ($req.ContainsKey('id')) { $req['id'] } else { "$idx" }
                @{ id = $reqId; method = $req.method; url = $req.url }
                $idx++
            }

            $body = @{ requests = @($batchRequests) } | ConvertTo-Json -Depth 5

            # Throttling pattern — SRS 5.1 / powershell-standards.md
            $attempt = 0
            do {
                try {
                    $result = Invoke-RestMethod -Uri $batchUri -Method Post `
                        -Headers $headers -Body $body -ErrorAction Stop
                    foreach ($r in $result.responses) { $allResponses.Add($r) }
                    break
                } catch {
                    if ($_.Exception.Response.StatusCode -eq 429) {
                        $wait = [Math]::Min([Math]::Pow(2, $attempt) * 1000, 60000)
                        Write-Verbose "Graph $batchUri throttled — waiting ${wait}ms (attempt $($attempt + 1))"
                        Start-Sleep -Milliseconds $wait
                        $attempt++
                    } else { throw }
                }
            } while ($attempt -lt 5)
        }
    }

    end {
        $allResponses
    }
}
