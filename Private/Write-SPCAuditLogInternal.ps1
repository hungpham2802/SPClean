function Write-SPCAuditLogInternal {
    <#
    .SYNOPSIS
        Appends an audit log record into an immutable CSV log file.
    .DESCRIPTION
        Thread-safe append-only CSV logger with directory auto-creation and schema compliance.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$LogPath,
        [Parameter(Mandatory)] [string]$SiteUrl,
        [Parameter(Mandatory)] [string]$TargetType,
        [Parameter(Mandatory)] [string]$ItemId,
        [Parameter(Mandatory)] [string]$ItemTitle,
        [Parameter(Mandatory)] [string]$FileRelativeUrl,
        [Parameter(Mandatory)] [int64]$SizeBytes,
        [Parameter(Mandatory)] [datetime]$DeletedDate,
        [Parameter(Mandatory)] [string]$DeletedByUPN,
        [Parameter(Mandatory)] [string]$OperatorUPN,
        [Parameter(Mandatory)] [string]$ExecutionStatus,
        [Parameter()] [string]$ErrorMessage = ''
    )

    $logEntry = [PSCustomObject][ordered]@{
        TimestampUtc    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        SiteUrl         = $SiteUrl
        TargetType      = $TargetType
        ItemId          = $ItemId
        ItemTitle       = $ItemTitle
        FileRelativeUrl = $FileRelativeUrl
        SizeBytes       = $SizeBytes
        SizeMB          = [Math]::Round(($SizeBytes / 1MB), 4)
        DeletedDateUtc  = $DeletedDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        DeletedByUPN    = $DeletedByUPN
        OperatorUPN     = $OperatorUPN
        ExecutionStatus = $ExecutionStatus
        ErrorMessage    = $ErrorMessage
    }

    try {
        $parentDir = Split-Path $LogPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }

        $isNewFile = -not (Test-Path $LogPath)
        $csvLine = $logEntry | ConvertTo-Csv -NoTypeInformation
        if ($isNewFile) {
            $csvLine | Out-File -FilePath $LogPath -Encoding UTF8 -Force
        } else {
            $csvLine | Select-Object -Skip 1 | Out-File -FilePath $LogPath -Encoding UTF8 -Append
        }
    }
    catch {
        Write-Warning "ERR-STO-106: Failed to write audit log to '$LogPath': $($_.Exception.Message)"
    }
}
