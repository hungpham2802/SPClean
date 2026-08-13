function Compare-SPCPermissionSnapshot {
    <#
    .SYNOPSIS
        Detects permission drift by comparing two permission snapshots.

    .DESCRIPTION
        This cmdlet compares a Baseline snapshot and a Current snapshot (in JSON format)
        to identify newly added Site Collection Administrators (SCA), Owners, 
        direct Full Control assignments, and new guest accounts.

    .PARAMETER BaselineSnapshotPath
        Absolute path to the baseline snapshot file.

    .PARAMETER CurrentSnapshotPath
        Absolute path to the current snapshot file.

    .EXAMPLE
        Compare-SPCPermissionSnapshot -BaselineSnapshotPath "C:\snapshots\base.json" -CurrentSnapshotPath "C:\snapshots\current.json"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if (-not (Test-Path $_)) { throw "ERR-501: Baseline snapshot file not found." }
            return $true
        })]
        [string]$BaselineSnapshotPath,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if (-not (Test-Path $_)) { throw "ERR-501: Current snapshot file not found." }
            return $true
        })]
        [string]$CurrentSnapshotPath
    )

    begin {
        Write-Verbose "Entering Compare-SPCPermissionSnapshot"
        try {
            Test-SPCConnection -ErrorAction Stop
        } catch {
            throw "ERR-001: Connection not found. Please connect using Connect-SPCTenant first."
        }
    }

    process {
        Write-Verbose "Loading Baseline Snapshot from $BaselineSnapshotPath"
        try {
            $baselineContent = Get-Content -Path $BaselineSnapshotPath -Raw -ErrorAction Stop
            $baselineData = ConvertFrom-Json -InputObject $baselineContent -ErrorAction Stop
        } catch {
            throw "ERR-502: Failed to parse Baseline snapshot. Ensure it is a valid JSON file."
        }

        Write-Verbose "Loading Current Snapshot from $CurrentSnapshotPath"
        try {
            $currentContent = Get-Content -Path $CurrentSnapshotPath -Raw -ErrorAction Stop
            $currentData = ConvertFrom-Json -InputObject $currentContent -ErrorAction Stop
        } catch {
            throw "ERR-502: Failed to parse Current snapshot. Ensure it is a valid JSON file."
        }

        # Initialize HashSets for quick lookups
        $baselineSCA = [System.Collections.Generic.HashSet[string]]::new()
        $baselineOwners = [System.Collections.Generic.HashSet[string]]::new()
        $baselineDirectFullControl = [System.Collections.Generic.HashSet[string]]::new()
        $baselineGuests = [System.Collections.Generic.HashSet[string]]::new()

        Write-Verbose "Processing Baseline Data..."
        foreach ($item in $baselineData) {
            $upn = $item.user.upn
            if ([string]::IsNullOrEmpty($upn)) { continue }

            if ($item.isSCA) { $baselineSCA.Add($upn) | Out-Null }
            if ($item.isOwner) { $baselineOwners.Add($upn) | Out-Null }
            if ($item.permissions -contains "Full Control") { $baselineDirectFullControl.Add($upn) | Out-Null }
            if ($upn -match "(?i)#EXT#") { $baselineGuests.Add($upn) | Out-Null }
        }

        # Lists for storing new findings
        $newSCA = [System.Collections.Generic.List[string]]::new()
        $newOwners = [System.Collections.Generic.List[string]]::new()
        $newDirectFullControl = [System.Collections.Generic.List[string]]::new()
        $newGuests = [System.Collections.Generic.List[string]]::new()

        Write-Verbose "Processing Current Data and detecting drift..."
        foreach ($item in $currentData) {
            $upn = $item.user.upn
            if ([string]::IsNullOrEmpty($upn)) { continue }

            if ($item.isSCA -and -not $baselineSCA.Contains($upn)) {
                $newSCA.Add($upn)
            }
            if ($item.isOwner -and -not $baselineOwners.Contains($upn)) {
                $newOwners.Add($upn)
            }
            if ($item.permissions -contains "Full Control" -and -not $baselineDirectFullControl.Contains($upn)) {
                $newDirectFullControl.Add($upn)
            }
            if (($upn -match "(?i)#EXT#") -and -not $baselineGuests.Contains($upn)) {
                $newGuests.Add($upn)
            }
        }

        $driftAlert = [PSCustomObject]@{
            NewSCAOrOwners                 = @($newSCA) + @($newOwners) | Select-Object -Unique
            NewDirectFullControlAssignments = $newDirectFullControl.ToArray()
            NewGuestAccounts               = $newGuests.ToArray()
        }

        return $driftAlert
    }

    end {
        Write-Information "Permission snapshot comparison completed successfully."
    }
}
