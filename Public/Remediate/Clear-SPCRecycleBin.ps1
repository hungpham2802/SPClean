function Clear-SPCRecycleBin {
    <#
    .SYNOPSIS
        Safely clears 1st and 2nd stage recycle bins with audit logging and Microsoft Purview hold protection.

    .DESCRIPTION
        Clear-SPCRecycleBin purges deleted items older than OlderThanDays from the first-stage (End-User) and/or
        second-stage (Site Collection Administrator) recycle bins across one or more SharePoint Online site collections.

        Safety & Compliance Guarantees:
        - Purview Hold Immunity: Automatically checks for active Microsoft Purview Retention Policies, Retention Labels,
          or Litigation Holds using Test-SPCPurviewHoldInternal. Protected sites are skipped to prevent compliance violations.
        - Non-Destructive Simulation: Fully supports -DryRun and -WhatIf to preview items and storage that would be freed
          without deleting anything.
        - Immutable Audit Logging: Every purge action (simulated or real) is recorded in an append-only CSV audit file.
        - License Enforcement: Requires a Pro or Consultant license for live execution (simulations are unrestricted).

    .PARAMETER SiteUrl
        One or more SharePoint Online site collection URLs to process.
        Supports pipeline input by value and property name.

    .PARAMETER OlderThanDays
        The minimum age threshold (in days) since item deletion for items to be purged. Default is 30 days.
        Items deleted more recently than this value are preserved. Range: 0 to 180 days.

    .PARAMETER SecondStageOnly
        Purges items only from the second-stage (Site Collection Administrator) recycle bin.

    .PARAMETER FirstStageOnly
        Purges items only from the first-stage (End-User) recycle bin.

    .PARAMETER DryRun
        Executes a non-destructive simulation. No items are deleted from SharePoint, but potential storage savings
        and item counts are calculated and written to the audit log.

    .PARAMETER AuditLogPath
        Custom file path for the append-only CSV audit log. If omitted, an auto-named timestamped CSV file is
        generated in the current working directory.

    .PARAMETER Force
        Suppresses interactive confirmation prompts during execution.

    .INPUTS
        System.String[]
            Accepts site collection URLs from the pipeline.

    .OUTPUTS
        SPC.RecycleBinClearResult
            Returns custom objects containing site URL, stage processed, items deleted count, storage freed in MB,
            monthly cost savings in USD, simulation flag, audit log file path, execution timestamp, and status.

    .EXAMPLE
        Clear-SPCRecycleBin -SiteUrl 'https://contoso.sharepoint.com/sites/Marketing' -OlderThanDays 30 -DryRun

        Simulates purging items older than 30 days from both recycle bin stages on the Marketing site without making changes.

    .EXAMPLE
        Get-SPCStorageWaste -Top 5 | ForEach-Object {
            Clear-SPCRecycleBin -SiteUrl $_.SiteUrl -SecondStageOnly -OlderThanDays 14 -Force
        }

        Discovers top 5 sites with highest storage waste and permanently empties second-stage recycle bin items older than 14 days.

    .EXAMPLE
        Clear-SPCRecycleBin -SiteUrl 'https://contoso.sharepoint.com/sites/Legal' -OlderThanDays 60 -AuditLogPath 'C:\Audit\RecycleBin_Log.csv'

        Purges recycle bin items on the Legal site, automatically validating Purview hold immunity and logging results to a custom audit file.

    .NOTES
        Requires an active SPClean connection initialized via Connect-SPCTenant.
        Live execution requires a Pro or Consultant tier license.

    .LINK
        Get-SPCStorageWaste
        Optimize-SPCFileVersion
        Export-SPCStorageReport
    #>
    [CmdletBinding(DefaultParameterSetName = 'AllStages', SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType('SPC.RecycleBinClearResult')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$SiteUrl,

        [Parameter()]
        [ValidateRange(0, 180)]
        [int]$OlderThanDays = 30,

        [Parameter(ParameterSetName = 'SecondStage')]
        [switch]$SecondStageOnly,

        [Parameter(ParameterSetName = 'FirstStage')]
        [switch]$FirstStageOnly,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [string]$AuditLogPath,

        [Parameter()]
        [switch]$Force
    )

    begin {
        Test-SPCConnection
        $isSimulation = $DryRun.IsPresent -or $WhatIfPreference

        if (-not $isSimulation) {
            # Enforce Pro/Consultant License Gate
            Assert-SPCProLicense -Feature 'Clear-SPCRecycleBin'
        }

        if ([string]::IsNullOrWhiteSpace($AuditLogPath)) {
            $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
            $AuditLogPath = Join-Path (Get-Location) "SPClean_RecycleBin_Audit_$timestamp.csv"
        }
    }

    process {
        foreach ($url in $SiteUrl) {
            $stage = if ($SecondStageOnly) { '2ndStage' } elseif ($FirstStageOnly) { '1stStage' } else { 'Both' }
            
            # Check Purview Hold status
            $holdCheck = Test-SPCPurviewHoldInternal -SiteUrl $url
            if ($holdCheck.IsHoldActive) {
                Write-Warning "Clear-SPCRecycleBin: Site '$url' is protected by Purview Hold ($($holdCheck.HoldType)). Skipping purge."
                $opName = if ($script:SPCContext -and $script:SPCContext.TenantName) { $script:SPCContext.TenantName } else { 'System' }
                Write-SPCAuditLogInternal -LogPath $AuditLogPath -SiteUrl $url -TargetType 'RecycleBin' -ItemId 'N/A' -ItemTitle 'Site-Level Hold' -FileRelativeUrl 'N/A' -SizeBytes 0 -DeletedDate (Get-Date) -DeletedByUPN 'System' -OperatorUPN $opName -ExecutionStatus 'SKIPPED_COMPLIANCE_HOLD' -ErrorMessage "Site has active Purview Hold: $($holdCheck.HoldType)"
                continue
            }

            if (-not $Force -and -not $isSimulation) {
                if (-not $PSCmdlet.ShouldProcess("Site: $url [Stage: $stage, OlderThan: $OlderThanDays days]", "Clear Recycle Bin")) {
                    continue
                }
            }

            $purgeResult = Invoke-SPCSafeRecycleBinPurgeInternal `
                -SiteUrl $url `
                -OlderThanDays $OlderThanDays `
                -Stage $stage `
                -DryRun $isSimulation `
                -AuditLogPath $AuditLogPath

                $status = if ($isSimulation) { 'Simulated' } elseif ($purgeResult.ErrorCount -gt 0) { 'PartialSuccess' } else { 'Success' }
                $monthlySaved = [Math]::Round((($purgeResult.StorageFreedMB / 1024) * 0.20), 2)

                [PSCustomObject][ordered]@{
                    PSTypeName          = 'SPC.RecycleBinClearResult'
                    SiteUrl             = $url
                    StageProcessed      = $stage
                    ItemsDeletedCount   = $purgeResult.DeletedCount
                    StorageFreedMB      = $purgeResult.StorageFreedMB
                    MonthlyCostSavedUSD = $monthlySaved
                    IsDryRun            = $isSimulation
                    AuditLogFilePath    = $AuditLogPath
                    ExecutedAt          = (Get-Date).ToUniversalTime()
                    Status              = $status
                }
        }
    }
}
