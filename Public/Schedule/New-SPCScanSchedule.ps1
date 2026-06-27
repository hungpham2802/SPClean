function New-SPCScanSchedule {
    <#
    .SYNOPSIS
        Creates a Windows Scheduled Task that runs Get-SPCOrphanedUser and Export-SPCReport per SRS 3.5.1.
    .DESCRIPTION
        Generates a self-contained PowerShell scan script and registers it with Windows Task Scheduler.
        Always uses App-only authentication (Interactive cannot be scheduled).
        Certificate password is encrypted with DPAPI — decryptable only on the same machine and user account.
        On non-Windows platforms, writes the script file and advises configuring a cron job manually.
    .PARAMETER TenantName
        SharePoint tenant name (e.g. 'contoso').
    .PARAMETER ClientId
        Azure AD app registration client ID.
    .PARAMETER CertificatePath
        Path to the .pfx certificate file used for App-only auth.
    .PARAMETER CertificatePassword
        SecureString password for the .pfx file. Encrypted with DPAPI for storage.
    .PARAMETER Schedule
        Recurring schedule shorthand: 'Daily', 'Weekly', or 'Monthly'. Mutually exclusive with -ScheduleAt.
    .PARAMETER ScheduleAt
        One-time execution date/time. Mutually exclusive with -Schedule.
    .PARAMETER ReportFormat
        Report file format: 'HTML' (default), 'CSV', or 'JSON'.
    .PARAMETER ReportOutputPath
        Directory where report files are saved by the scheduled task.
    .PARAMETER TaskName
        Windows Task Scheduler task name. Default: 'SPClean_OrphanedUserScan'.
    .EXAMPLE
        New-SPCScanSchedule -TenantName contoso -ClientId '...' -CertificatePath C:\cert.pfx -CertificatePassword $pwd -Schedule Weekly -ReportOutputPath C:\Reports
    .EXAMPLE
        New-SPCScanSchedule -TenantName contoso -ClientId '...' -CertificatePath C:\cert.pfx -CertificatePassword $pwd -Schedule Daily -ReportOutputPath C:\Reports -WhatIf
    .OUTPUTS
        SPC.ScheduleResult
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Recurring')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $TenantName,

        [Parameter(Mandatory)]
        [string] $ClientId,

        [Parameter(Mandatory)]
        [string] $CertificatePath,

        [Parameter(Mandatory)]
        [System.Security.SecureString] $CertificatePassword,

        [Parameter(Mandatory, ParameterSetName = 'Recurring')]
        [ValidateSet('Daily', 'Weekly', 'Monthly')]
        [string] $Schedule,

        [Parameter(Mandatory, ParameterSetName = 'OneTime')]
        [datetime] $ScheduleAt,

        [Parameter()]
        [ValidateSet('CSV', 'HTML', 'JSON')]
        [string] $ReportFormat = 'HTML',

        [Parameter(Mandatory)]
        [Alias('OutputPath')]
        [string] $ReportOutputPath,

        [Parameter()]
        [string] $TaskName = 'SPClean_OrphanedUserScan'
    )

    process {
        Assert-SPCProLicense -Feature 'ScheduledScan'

        # Resolve and validate paths
        $resolvedCert = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CertificatePath)
        if (-not (Test-Path -Path $resolvedCert -PathType Leaf)) {
            throw "New-SPCScanSchedule: Certificate not found: '$resolvedCert'"
        }
        $resolvedOutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportOutputPath)

        # Encrypt CertificatePassword with DPAPI — machine+user scoped, never plain text
        $encryptedPwd = $CertificatePassword | ConvertFrom-SecureString

        $ext = switch ($ReportFormat.ToUpper()) { 'CSV' { 'csv' } 'HTML' { 'html' } 'JSON' { 'json' } }

        # Script file lives in the parent of the report directory (or alongside it)
        $scriptDir = Split-Path -Path $resolvedOutputDir -Parent
        if ([string]::IsNullOrWhiteSpace($scriptDir) -or -not (Test-Path -Path $scriptDir -PathType Container)) {
            $scriptDir = $resolvedOutputDir
        }
        $scriptPath = Join-Path $scriptDir "${TaskName}.ps1"

        $scheduleLabel = if ($PSCmdlet.ParameterSetName -eq 'OneTime') {
            "Once at $($ScheduleAt.ToString('yyyy-MM-dd HH:mm'))"
        } else {
            $Schedule
        }

        # WhatIf — report intent only
        if ($WhatIfPreference) {
            Write-Information "WhatIf: Would write scan script to '$scriptPath' and register task '$TaskName' ($scheduleLabel)." -InformationAction Continue
            $preview = [PSCustomObject][ordered]@{
                TaskName   = $TaskName
                ScriptPath = $scriptPath
                Schedule   = $scheduleLabel
                NextRun    = $null
                Status     = 'WhatIf'
                Message    = 'Dry-run: no files or tasks were created.'
            }
            $preview.PSObject.TypeNames.Insert(0, 'SPC.ScheduleResult')
            $preview
            return
        }

        if (-not $PSCmdlet.ShouldProcess($TaskName, 'New-SPCScanSchedule')) { return }

        # Generate the scan script — backtick-dollar escapes inner PS variables;
        # double-backtick produces a single backtick (line continuation) in the output file
        $scriptContent = @"
#Requires -Version 5.1
# SPClean scheduled scan script
# Generated by New-SPCScanSchedule on $(( Get-Date ).ToString('yyyy-MM-dd'))
# SECURITY: CertificatePassword is DPAPI-encrypted — only decryptable on this machine
#           by the user account that registered this task.

param()

`$ErrorActionPreference = 'Stop'

`$CertificatePassword = '$encryptedPwd' | ConvertTo-SecureString

Import-Module SPClean -ErrorAction Stop

try {
    Connect-SPCTenant ``
        -TenantName        '$TenantName' ``
        -AuthMethod        AppOnly ``
        -ClientId          '$ClientId' ``
        -CertificatePath   '$resolvedCert' ``
        -CertificatePassword `$CertificatePassword

    if (-not (Test-Path -Path '$resolvedOutputDir')) {
        New-Item -ItemType Directory -Path '$resolvedOutputDir' -Force | Out-Null
    }

    `$timestamp  = Get-Date -Format 'yyyyMMddHHmm'
    `$reportFile = Join-Path '$resolvedOutputDir' "SPClean_`$timestamp.$ext"

    Get-SPCOrphanedUser -AllSites | ``
        Export-SPCReport -Format '$ReportFormat' -OutputPath `$reportFile -IncludeSummary

    Write-Output "SPClean scan complete: `$reportFile"
} finally {
    Disconnect-SPCTenant -Confirm:`$false -ErrorAction SilentlyContinue
}
"@

        # Ensure script directory exists and write script
        if (-not (Test-Path -Path $scriptDir -PathType Container)) {
            [void](New-Item -Path $scriptDir -ItemType Directory -Force)
        }
        [System.IO.File]::WriteAllText($scriptPath, $scriptContent, [System.Text.UTF8Encoding]::new($false))
        Write-Verbose "New-SPCScanSchedule: Scan script written to '$scriptPath'"

        # Detect Windows via .NET — reliable across PS 5.1, PS 7+, and module scopes.
        # Get-Variable/automatic-variable lookup is not trustworthy inside module functions.
        $isWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

        $taskRegistered = $false
        $nextRun        = $null
        $statusMsg      = $null

        if ($isWindows) {
            try {
                $pwshPath = if ($PSVersionTable.PSVersion.Major -ge 6) {
                    $p = Get-Command pwsh -ErrorAction SilentlyContinue
                    if ($p) { $p.Source } else { (Get-Command powershell -ErrorAction Stop).Source }
                } else {
                    (Get-Command powershell -ErrorAction Stop).Source
                }

                $action  = New-ScheduledTaskAction `
                    -Execute  $pwshPath `
                    -Argument "-NonInteractive -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""

                $trigger = if ($PSCmdlet.ParameterSetName -eq 'OneTime') {
                    New-ScheduledTaskTrigger -Once -At $ScheduleAt
                } else {
                    switch ($Schedule) {
                        'Daily'   { New-ScheduledTaskTrigger -Daily   -At '02:00' }
                        'Weekly'  { New-ScheduledTaskTrigger -Weekly  -At '02:00' -DaysOfWeek Sunday }
                        'Monthly' { New-ScheduledTaskTrigger -Monthly -At '02:00' -DaysOfMonth 1 }
                    }
                }

                $settings = New-ScheduledTaskSettingsSet `
                    -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
                    -MultipleInstances  IgnoreNew

                $task = Register-ScheduledTask `
                    -TaskName $TaskName `
                    -Action   $action `
                    -Trigger  $trigger `
                    -Settings $settings `
                    -Force    `
                    -ErrorAction Stop

                $taskRegistered = $true
                $nextRun        = if ($task.Triggers.Count -gt 0) { $task.Triggers[0].StartBoundary } else { $null }
                $statusMsg      = "Task '$TaskName' registered in Windows Task Scheduler. Script: '$scriptPath'"
                Write-Verbose "New-SPCScanSchedule: $statusMsg"
            } catch {
                Write-Warning "New-SPCScanSchedule: Task Scheduler registration failed — $($_.Exception.Message). Script saved to '$scriptPath'."
                $statusMsg = "Script created but task registration failed: $($_.Exception.Message)"
            }
        } else {
            $cronExpr = switch ($PSCmdlet.ParameterSetName) {
                'OneTime'   { "# One-time: $(if ($ScheduleAt) { $ScheduleAt.ToString('mm HH d M') } else { '...' }) *" }
                'Recurring' {
                    switch ($Schedule) {
                        'Daily'   { '0 2 * * *' }
                        'Weekly'  { '0 2 * * 0' }
                        'Monthly' { '0 2 1 * *' }
                    }
                }
            }
            $statusMsg = "Non-Windows platform: Task Scheduler unavailable. Script written to '$scriptPath'. Add this cron entry: $cronExpr pwsh -NonInteractive -File `"$scriptPath`""
            Write-Warning "New-SPCScanSchedule: $statusMsg"
        }

        $result = [PSCustomObject][ordered]@{
            TaskName   = $TaskName
            ScriptPath = $scriptPath
            Schedule   = $scheduleLabel
            NextRun    = $nextRun
            Status     = if ($taskRegistered) { 'Registered' } else { 'ScriptOnly' }
            Message    = $statusMsg
        }
        $result.PSObject.TypeNames.Insert(0, 'SPC.ScheduleResult')
        $result
    }
}
