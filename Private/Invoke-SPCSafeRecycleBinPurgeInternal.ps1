function Invoke-SPCSafeRecycleBinPurgeInternal {
    <#
    .SYNOPSIS
        Purges items in the 1st and 2nd stage recycle bins in batches with audit logging.
    .DESCRIPTION
        Processes items in chunks of 100 to prevent memory spikes and maintains detailed audit trails.
    .OUTPUTS
        [PSCustomObject] with DeletedCount, StorageFreedMB, ErrorCount
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$SiteUrl,
        [Parameter(Mandatory)] [int]$OlderThanDays,
        [Parameter(Mandatory)] [string]$Stage,
        [Parameter(Mandatory)] [bool]$DryRun,
        [Parameter(Mandatory)] [string]$AuditLogPath
    )

    begin {
        $siteConn = Connect-SPCSiteInternal -SiteUrl $SiteUrl -Context $script:SPCContext
        $cutoffDate = (Get-Date).ToUniversalTime().AddDays(-$OlderThanDays)

        $deletedCount = 0
        $freedBytes = [int64]0
        $errorCount = 0

        $operatorUPN = if ($script:SPCContext -and -not [string]::IsNullOrWhiteSpace($script:SPCContext.OperatorUPN)) {
            $script:SPCContext.OperatorUPN
        } elseif ($script:SPCContext -and $script:SPCContext.TenantName) {
            "admin@$($script:SPCContext.TenantName).onmicrosoft.com"
        } else {
            'System'
        }
    }

    process {
        $itemsQuery = Get-PnPRecycleBinItem -Connection $siteConn -RowLimit 5000
        
        $filteredItems = @()
        if ($null -ne $itemsQuery) {
            $filteredItems = @($itemsQuery | Where-Object {
                $itemDeletedDate = $_.DeletedDate.ToUniversalTime()
                $isOlder = $itemDeletedDate -le $cutoffDate
                $stageMatch = switch ($Stage) {
                    '1stStage' { $_.ItemState -eq 'FirstStageRecycleBin' }
                    '2ndStage' { $_.ItemState -eq 'SecondStageRecycleBin' }
                    'Both'     { $true }
                }
                $isOlder -and $stageMatch
            })
        }

        $batches = [System.Collections.Generic.List[object[]]]::new()
        $batchSize = 100
        for ($i = 0; $i -lt $filteredItems.Count; $i += $batchSize) {
            $count = [Math]::Min($batchSize, ($filteredItems.Count - $i))
            $batches.Add($filteredItems[$i..($i + $count - 1)])
        }

        foreach ($batch in $batches) {
            foreach ($item in $batch) {
                $itemSize = [int64]$item.Size
                $itemIdStr = if ($null -ne $item.Id) { $item.Id.ToString() } else { '' }
                $itemTitle = if ($null -ne $item.Title) { $item.Title } else { '' }
                $dirName = if ($null -ne $item.DirName) { $item.DirName } else { '' }
                $deletedBy = if ($null -ne $item.DeletedByName) { $item.DeletedByName } else { 'Unknown' }
                $itemDate = if ($null -ne $item.DeletedDate) { $item.DeletedDate } else { (Get-Date) }

                if ($DryRun) {
                    Write-SPCAuditLogInternal `
                        -LogPath $AuditLogPath `
                        -SiteUrl $SiteUrl `
                        -TargetType 'RecycleBinItem' `
                        -ItemId $itemIdStr `
                        -ItemTitle $itemTitle `
                        -FileRelativeUrl $dirName `
                        -SizeBytes $itemSize `
                        -DeletedDate $itemDate `
                        -DeletedByUPN $deletedBy `
                        -OperatorUPN $operatorUPN `
                        -ExecutionStatus 'SIMULATED' `
                        -ErrorMessage ''

                    $freedBytes += $itemSize
                    $deletedCount++
                } else {
                    try {
                        Clear-PnPRecycleBinItem -Identity $item.Id -Force -Connection $siteConn -ErrorAction Stop
                        Write-SPCAuditLogInternal `
                            -LogPath $AuditLogPath `
                            -SiteUrl $SiteUrl `
                            -TargetType 'RecycleBinItem' `
                            -ItemId $itemIdStr `
                            -ItemTitle $itemTitle `
                            -FileRelativeUrl $dirName `
                            -SizeBytes $itemSize `
                            -DeletedDate $itemDate `
                            -DeletedByUPN $deletedBy `
                            -OperatorUPN $operatorUPN `
                            -ExecutionStatus 'SUCCESS' `
                            -ErrorMessage ''

                        $freedBytes += $itemSize
                        $deletedCount++
                    }
                    catch {
                        $errorCount++
                        Write-SPCAuditLogInternal `
                            -LogPath $AuditLogPath `
                            -SiteUrl $SiteUrl `
                            -TargetType 'RecycleBinItem' `
                            -ItemId $itemIdStr `
                            -ItemTitle $itemTitle `
                            -FileRelativeUrl $dirName `
                            -SizeBytes $itemSize `
                            -DeletedDate $itemDate `
                            -DeletedByUPN $deletedBy `
                            -OperatorUPN $operatorUPN `
                            -ExecutionStatus 'FAILED' `
                            -ErrorMessage $_.Exception.Message
                    }
                }
            }
        }
    }

    end {
        return [PSCustomObject]@{
            DeletedCount   = $deletedCount
            StorageFreedMB = [Math]::Round(($freedBytes / 1MB), 2)
            ErrorCount     = $errorCount
        }
    }
}
