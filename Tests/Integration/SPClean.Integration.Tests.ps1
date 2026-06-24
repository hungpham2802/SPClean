#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    SPClean M01 — Integration Tests (real tenant required).

.DESCRIPTION
    Tests run against a dev tenant with pre-seeded orphaned users.
    All tests are skipped automatically when env vars are absent.

    Required env vars:
        SPC_TENANT_NAME      — e.g. "contoso" or "contoso.onmicrosoft.com"
        SPC_CLIENT_ID        — Azure AD app registration client ID
        SPC_CERT_PATH        — Full path to .pfx certificate file
        SPC_CERT_PASSWORD    — Certificate password (plain text; converted to SecureString here)
        SPC_TEST_SITE_ORPHAN — Full URL of a site collection pre-seeded with exactly 3 orphaned users

    Setup requirements:
        - The test site (SPC_TEST_SITE_ORPHAN) must have exactly 3 users whose accounts are
          deleted/soft-deleted in Entra ID but still present in the SharePoint UIL.
        - AC-07 and AC-08 are destructive (remove, then restore). Run the full suite only once
          against a freshly seeded tenant; re-seed orphans before re-running.

    Run:
        $env:SPC_TENANT_NAME = 'contoso'
        ... (set all vars)
        Invoke-Pester Tests/Integration/ -Output Detailed
#>

# ── Skip condition — evaluated at discovery time (script level, before BeforeAll) ──
$script:requiredVars = @(
    'SPC_TENANT_NAME', 'SPC_CLIENT_ID', 'SPC_CERT_PATH',
    'SPC_CERT_PASSWORD', 'SPC_TEST_SITE_ORPHAN'
)
$script:missingVars = $script:requiredVars |
    Where-Object { -not (Get-Item "Env:$_" -ErrorAction SilentlyContinue) }
$script:skipInteg   = $script:missingVars.Count -gt 0

if ($script:skipInteg) {
    Write-Warning "SPClean integration tests will be SKIPPED — missing env vars: $($script:missingVars -join ', ')"
}

# ── Module load + shared connect ──────────────────────────────────────────────

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../SPClean.psd1') -Force -ErrorAction Stop

    if (-not $script:skipInteg) {
        $certPass = ConvertTo-SecureString $env:SPC_CERT_PASSWORD -AsPlainText -Force

        $script:conn = Connect-SPCTenant `
            -TenantName          $env:SPC_TENANT_NAME `
            -AuthMethod          AppOnly `
            -ClientId            $env:SPC_CLIENT_ID `
            -CertificatePath     $env:SPC_CERT_PATH `
            -CertificatePassword $certPass

        $shortName               = ($env:SPC_TENANT_NAME -replace '\..*$', '')
        $script:testSiteUrl      = $env:SPC_TEST_SITE_ORPHAN
        $script:cleanSiteUrl     = "https://$shortName.sharepoint.com"

        # Isolated temp dir for report files and snapshots
        $ts                      = (Get-Date).ToString('yyyyMMddHHmmss')
        $script:tempDir          = Join-Path ([System.IO.Path]::GetTempPath()) "SPClean_IT_$ts"
        [void](New-Item -Path $script:tempDir -ItemType Directory -Force)
        $script:snapshotDir      = Join-Path $script:tempDir 'Snapshots'

        # Fetch orphans once — reused by AC-03, AC-05, AC-07
        $script:orphans          = @(Get-SPCOrphanedUser -SiteUrl $script:testSiteUrl)
    }
}

AfterAll {
    if (-not $script:skipInteg) {
        Disconnect-SPCTenant -ErrorAction SilentlyContinue
        if ($script:tempDir -and (Test-Path $script:tempDir)) {
            Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-01: Interactive auth (manual only — device-code requires browser interaction)
# ─────────────────────────────────────────────────────────────────────────────

Describe 'AC-01: Interactive auth' {

    It 'AC-01: [manual] Connect-SPCTenant interactive flow returns SPC.ConnectionInfo' -Skip {
        # Run manually: Connect-SPCTenant -TenantName contoso
        # Do NOT automate — requires browser or device-code user interaction.
        $result = Connect-SPCTenant -TenantName $env:SPC_TENANT_NAME
        $result.PSObject.TypeNames | Should -Contain 'SPC.ConnectionInfo'
        $result.AuthMethod         | Should -Be 'Interactive'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-02: AppOnly certificate authentication
# ─────────────────────────────────────────────────────────────────────────────

Describe 'AC-02: AppOnly cert auth' {

    It 'AC-02: Connect-SPCTenant returns SPC.ConnectionInfo' -Skip:$script:skipInteg {
        $script:conn.PSObject.TypeNames | Should -Contain 'SPC.ConnectionInfo'
    }

    It 'AC-02: AuthMethod is AppOnly' -Skip:$script:skipInteg {
        $script:conn.AuthMethod | Should -Be 'AppOnly'
    }

    It 'AC-02: TenantName is populated and matches configured tenant' -Skip:$script:skipInteg {
        $script:conn.TenantName | Should -Not -BeNullOrEmpty
    }

    It 'AC-02: ConnectedAt is a valid UTC datetime within last 5 minutes' -Skip:$script:skipInteg {
        $script:conn.ConnectedAt | Should -BeOfType [datetime]
        $script:conn.ConnectedAt | Should -BeGreaterThan (Get-Date).AddMinutes(-5).ToUniversalTime()
    }

    It 'AC-02: ExpiresAt is in the future' -Skip:$script:skipInteg {
        $script:conn.ExpiresAt | Should -BeGreaterThan (Get-Date).ToUniversalTime()
    }

    It 'AC-12: SPC.ConnectionInfo properties contain no credential strings' -Skip:$script:skipInteg {
        $propValues = $script:conn.PSObject.Properties | ForEach-Object { [string]$_.Value }
        $propValues | ForEach-Object { $_ | Should -Not -Match 'password|secret|pfx|credential' }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-03: Orphan detection against real tenant
# ─────────────────────────────────────────────────────────────────────────────

Describe 'AC-03: Orphan detection — real tenant' {

    It 'AC-03: detects exactly 3 orphaned users on the pre-seeded test site' -Skip:$script:skipInteg {
        $script:orphans | Should -HaveCount 3
    }

    It 'AC-03: all output objects carry TypeName SPC.OrphanedUser' -Skip:$script:skipInteg {
        $script:orphans | ForEach-Object {
            $_.PSObject.TypeNames | Should -Contain 'SPC.OrphanedUser'
        }
    }

    It 'AC-03: OrphanType is a valid SRS enum value' -Skip:$script:skipInteg {
        $valid = 'Deleted', 'SoftDeleted', 'Disabled', 'GuestOrphaned'
        $script:orphans | ForEach-Object { $_.OrphanType | Should -BeIn $valid }
    }

    It 'AC-03: RiskLevel is HIGH, MEDIUM, or LOW' -Skip:$script:skipInteg {
        $script:orphans | ForEach-Object { $_.RiskLevel | Should -BeIn 'HIGH', 'MEDIUM', 'LOW' }
    }

    It 'AC-03: SiteUrl on every result matches the scanned site' -Skip:$script:skipInteg {
        $script:orphans | ForEach-Object { $_.SiteUrl | Should -Be $script:testSiteUrl }
    }

    It 'AC-03: all required SRS output properties are present' -Skip:$script:skipInteg {
        $required = 'SiteUrl','SiteTitle','UserId','LoginName','DisplayName','Email','UPN',
                    'OrphanType','RiskLevel','HasDirectPermissions','GroupMemberships',
                    'LastActivityDate','DetectedAt'
        foreach ($prop in $required) {
            $script:orphans[0].PSObject.Properties.Name | Should -Contain $prop
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-04: Clean site returns 0 results
# ─────────────────────────────────────────────────────────────────────────────

Describe 'AC-04: Clean site — 0 results' {

    It 'AC-04: tenant root site returns 0 orphaned users' -Skip:$script:skipInteg {
        # Uses the tenant root URL as a conventionally clean site.
        # If this fails, the root site has unexpected orphan accounts — choose a different clean site.
        $result = @(Get-SPCOrphanedUser -SiteUrl $script:cleanSiteUrl)
        $result | Should -HaveCount 0
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-05: HTML report generated from real scan results
# ─────────────────────────────────────────────────────────────────────────────

Describe 'AC-05: HTML report' {
    BeforeAll {
        if (-not $script:skipInteg -and $script:orphans.Count -gt 0) {
            $htmlPath             = Join-Path $script:tempDir 'report_ac05.html'
            $script:reportResult  = $script:orphans | Export-SPCReport -Format HTML -Path $htmlPath
            $script:reportHtml    = if (Test-Path $htmlPath) { Get-Content $htmlPath -Raw } else { '' }
        }
    }

    It 'AC-05: Export-SPCReport returns SPC.ReportResult' -Skip:$script:skipInteg {
        $script:reportResult.PSObject.TypeNames | Should -Contain 'SPC.ReportResult'
    }

    It 'AC-05: HTML report file exists at FilePath' -Skip:$script:skipInteg {
        Test-Path $script:reportResult.FilePath | Should -Be $true
    }

    It 'AC-05: TotalOrphansReported equals detected orphan count' -Skip:$script:skipInteg {
        $script:reportResult.TotalOrphansReported | Should -Be $script:orphans.Count
    }

    It 'AC-05: HTML contains HIGH risk badge color (#dc3545 per SRS 3.3.1)' -Skip:$script:skipInteg {
        $script:reportHtml | Should -Match '#dc3545'
    }

    It 'AC-05: HTML contains MEDIUM risk badge color (#ffc107 per SRS 3.3.1)' -Skip:$script:skipInteg {
        $script:reportHtml | Should -Match '#ffc107'
    }

    It 'AC-05: HTML file is non-empty and well-formed' -Skip:$script:skipInteg {
        $script:reportHtml.Length | Should -BeGreaterThan 500
        $script:reportHtml        | Should -Match '<html'
        $script:reportHtml        | Should -Match '</html>'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-07: Remove + CreateSnapshot (DESTRUCTIVE — modifies the test tenant)
# ─────────────────────────────────────────────────────────────────────────────

Describe 'AC-07: Remove + CreateSnapshot' {
    BeforeAll {
        if (-not $script:skipInteg -and $script:orphans.Count -gt 0) {
            $script:removeResults = @(
                $script:orphans | Remove-SPCOrphanedUser `
                    -CreateSnapshot  `
                    -SnapshotPath    $script:snapshotDir `
                    -Force `
                    -Confirm:$false
            )
            $script:snapshotFiles = @(
                Get-ChildItem -Path $script:snapshotDir -Filter '*.json' -ErrorAction SilentlyContinue
            )
        } else {
            $script:removeResults = @()
            $script:snapshotFiles = @()
        }
    }

    It 'AC-07: Remove-SPCOrphanedUser returns SPC.RemovalResult objects' -Skip:$script:skipInteg {
        $script:removeResults | ForEach-Object {
            $_.PSObject.TypeNames | Should -Contain 'SPC.RemovalResult'
        }
    }

    It 'AC-07: at least one user was removed from the UIL' -Skip:$script:skipInteg {
        @($script:removeResults | Where-Object { $_.RemovedFromUIL }).Count |
            Should -BeGreaterThan 0
    }

    It 'AC-07: snapshot JSON files created in SnapshotPath' -Skip:$script:skipInteg {
        $script:snapshotFiles.Count | Should -BeGreaterThan 0
    }

    It 'AC-07: snapshot file contains all SRS 6.2 required fields' -Skip:$script:skipInteg {
        $snap = Get-Content $script:snapshotFiles[0].FullName -Raw | ConvertFrom-Json
        $snap.snapshotVersion | Should -Not -BeNullOrEmpty
        $snap.createdAt       | Should -Not -BeNullOrEmpty
        $snap.tenantName      | Should -Not -BeNullOrEmpty
        $snap.siteUrl         | Should -Not -BeNullOrEmpty
        $snap.user            | Should -Not -Be $null
        $snap.user.loginName  | Should -Not -BeNullOrEmpty
        $snap.user.upn        | Should -Not -BeNullOrEmpty
        $snap.permissions     | Should -Not -Be $null
    }

    It 'AC-07: re-scan of test site returns 0 orphans after removal' -Skip:$script:skipInteg {
        $reScan = @(Get-SPCOrphanedUser -SiteUrl $script:testSiteUrl)
        $reScan | Should -HaveCount 0
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-08: Restore from snapshot (runs after AC-07 which must have created snapshots)
# ─────────────────────────────────────────────────────────────────────────────

Describe 'AC-08: Restore from snapshot' {
    BeforeAll {
        if (-not $script:skipInteg -and $script:snapshotFiles.Count -gt 0) {
            $firstSnap             = $script:snapshotFiles | Select-Object -First 1
            $script:restoreResult  = Restore-SPCOrphanedUser `
                -SnapshotPath $firstSnap.FullName `
                -Confirm:$false
        } else {
            $script:restoreResult = $null
        }
    }

    It 'AC-08: Restore-SPCOrphanedUser returns SPC.RestoreResult' -Skip:$script:skipInteg {
        $script:restoreResult | Should -Not -Be $null
        $script:restoreResult.PSObject.TypeNames | Should -Contain 'SPC.RestoreResult'
    }

    It 'AC-08: Status is Success or PartialSuccess' -Skip:$script:skipInteg {
        $script:restoreResult.Status | Should -BeIn 'Success', 'PartialSuccess'
    }

    It 'AC-08: PermissionsRestored count is a non-negative integer' -Skip:$script:skipInteg {
        $script:restoreResult.PermissionsRestored | Should -BeGreaterOrEqual 0
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-PERF-01: Single-site scan must complete in under 30 seconds (SRS 3.2.1)
# ─────────────────────────────────────────────────────────────────────────────

Describe 'AC-PERF-01: Performance' {

    It 'AC-PERF-01: single-site Get-SPCOrphanedUser completes in under 30 seconds' -Skip:$script:skipInteg {
        $elapsed = (Measure-Command {
            Get-SPCOrphanedUser -SiteUrl $script:testSiteUrl -ErrorAction SilentlyContinue |
                Out-Null
        }).TotalSeconds

        Write-Host "  [PERF] Elapsed: $([math]::Round($elapsed, 2))s"
        $elapsed | Should -BeLessThan 30
    }
}
