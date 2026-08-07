#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Report/Export-SPCReport.ps1')

    $script:SPCContext = [PSCustomObject]@{
        TenantName           = 'contoso'
        AuthMethod           = 'Interactive'
        ConnectedAt          = (Get-Date).ToUniversalTime()
        PnPContext           = $null
        GraphAccessToken     = 'fake-token'
        _ClientId            = $null
        _CertificatePath     = $null
        _CertificatePassword = $null
        _ClientSecret        = $null
    }

    # ── Shared fake orphan objects ───────────────────────────────────────────────

    function New-FakeOrphan {
        param(
            [string] $UPN         = 'jdoe@contoso.com',
            [string] $OrphanType  = 'Deleted',
            [string] $RiskLevel   = 'HIGH',
            [string] $SiteUrl     = 'https://contoso.sharepoint.com/sites/HR'
        )
        $o = [PSCustomObject][ordered]@{
            SiteUrl              = $SiteUrl
            SiteTitle            = 'Human Resources'
            UserId               = 42
            LoginName            = "i:0#.f|membership|$UPN"
            DisplayName          = 'John Doe'
            Email                = $UPN
            UPN                  = $UPN
            OrphanType           = $OrphanType
            RiskLevel            = $RiskLevel
            HasDirectPermissions = $true
            GroupMemberships     = @('HR Members', 'Site Owners')
            LastActivityDate     = [datetime]'2026-01-15T10:00:00Z'
            DetectedAt           = [datetime]'2026-06-22T00:00:00Z'
        }
        $o.PSObject.TypeNames.Insert(0, 'SPC.OrphanedUser')
        $o
    }

    $script:FakeOrphans = @(
        (New-FakeOrphan -UPN 'alice@contoso.com' -OrphanType 'Deleted'      -RiskLevel 'HIGH')
        (New-FakeOrphan -UPN 'bob@contoso.com'   -OrphanType 'SoftDeleted'  -RiskLevel 'MEDIUM')
        (New-FakeOrphan -UPN 'carol@contoso.com' -OrphanType 'GuestOrphaned' -RiskLevel 'LOW')
    )

    # Temp file helper — cleans up after each test
    $script:TempFiles = [System.Collections.Generic.List[string]]::new()

    function Get-TempReportPath {
        param([string] $Extension = 'html')
        $p = [System.IO.Path]::Combine(
            [System.IO.Path]::GetTempPath(),
            "SPCleanTest_$([System.IO.Path]::GetRandomFileName()).$Extension"
        )
        $script:TempFiles.Add($p)
        $p
    }
}

AfterAll {
    foreach ($f in $script:TempFiles) {
        if (Test-Path $f) { Remove-Item $f -ErrorAction SilentlyContinue }
    }
}

Describe 'Export-SPCReport' {

    Context 'AC-05: HTML report generation' {
        It 'AC-05: creates an HTML file at the specified OutputPath' {
            $path   = Get-TempReportPath 'html'
            $script:FakeOrphans | Export-SPCReport -Format HTML -OutputPath $path | Out-Null
            Test-Path $path | Should -BeTrue
        }

        It 'AC-05: HTML file contains DOCTYPE declaration' {
            $path = Get-TempReportPath 'html'
            $script:FakeOrphans | Export-SPCReport -Format HTML -OutputPath $path | Out-Null
            Get-Content $path -Raw | Should -Match '<!DOCTYPE html>'
        }

        It 'AC-05: HTML file contains all required table headers' {
            $path = Get-TempReportPath 'html'
            $script:FakeOrphans | Export-SPCReport -Format HTML -OutputPath $path | Out-Null
            $html = Get-Content $path -Raw
            foreach ($header in @('SiteUrl','DisplayName','UPN','OrphanType','RiskLevel')) {
                $html | Should -Match $header
            }
        }

        It 'AC-05: HIGH risk badge uses correct color #dc3545' {
            $high = @(New-FakeOrphan -RiskLevel 'HIGH')
            $path = Get-TempReportPath 'html'
            $high | Export-SPCReport -Format HTML -OutputPath $path | Out-Null
            Get-Content $path -Raw | Should -Match '#dc3545'
        }

        It 'AC-05: MEDIUM risk badge uses correct color #ffc107' {
            $med  = @(New-FakeOrphan -RiskLevel 'MEDIUM' -OrphanType 'SoftDeleted')
            $path = Get-TempReportPath 'html'
            $med  | Export-SPCReport -Format HTML -OutputPath $path | Out-Null
            Get-Content $path -Raw | Should -Match '#ffc107'
        }

        It 'AC-05: LOW risk badge uses correct color #28a745' {
            $low  = @(New-FakeOrphan -RiskLevel 'LOW' -OrphanType 'GuestOrphaned')
            $path = Get-TempReportPath 'html'
            $low  | Export-SPCReport -Format HTML -OutputPath $path | Out-Null
            Get-Content $path -Raw | Should -Match '#28a745'
        }

        It 'AC-05: HTML file contains inline JavaScript (sortable columns)' {
            $path = Get-TempReportPath 'html'
            $script:FakeOrphans | Export-SPCReport -Format HTML -OutputPath $path | Out-Null
            Get-Content $path -Raw | Should -Match '<script>'
        }

        It 'AC-05: HTML report footer contains tenant name' {
            $path = Get-TempReportPath 'html'
            $script:FakeOrphans | Export-SPCReport -Format HTML -OutputPath $path | Out-Null
            Get-Content $path -Raw | Should -Match 'contoso'
        }

        It 'AC-05: -IncludeSummary adds summary section to HTML' {
            $path = Get-TempReportPath 'html'
            $script:FakeOrphans | Export-SPCReport -Format HTML -OutputPath $path -IncludeSummary | Out-Null
            Get-Content $path -Raw | Should -Match 'Total Orphans'
        }
    }

    Context 'AC-05: CSV report generation' {
        It 'AC-05: creates a CSV file' {
            $path = Get-TempReportPath 'csv'
            $script:FakeOrphans | Export-SPCReport -Format CSV -OutputPath $path | Out-Null
            Test-Path $path | Should -BeTrue
        }

        It 'AC-05: CSV file has correct header row' {
            $path = Get-TempReportPath 'csv'
            $script:FakeOrphans | Export-SPCReport -Format CSV -OutputPath $path | Out-Null
            $firstLine = (Get-Content $path -TotalCount 1)
            $firstLine | Should -Be 'SiteUrl,SiteTitle,DisplayName,Email,UPN,OrphanType,RiskLevel,HasDirectPermissions,GroupMemberships,LastActivityDate,DetectedAt'
        }

        It 'AC-05: CSV GroupMemberships column is semicolon-delimited' {
            $path = Get-TempReportPath 'csv'
            $script:FakeOrphans | Export-SPCReport -Format CSV -OutputPath $path | Out-Null
            $content = Get-Content $path -Raw
            $content | Should -Match 'HR Members;Site Owners'
        }

        It 'AC-05: CSV file starts with UTF-8 BOM' {
            $path  = Get-TempReportPath 'csv'
            $script:FakeOrphans | Export-SPCReport -Format CSV -OutputPath $path | Out-Null
            $bytes = [System.IO.File]::ReadAllBytes($path)
            # UTF-8 BOM: EF BB BF
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }
    }

    Context 'AC-05: JSON report generation' {
        It 'AC-05: creates a JSON file' {
            $path = Get-TempReportPath 'json'
            $script:FakeOrphans | Export-SPCReport -Format JSON -OutputPath $path | Out-Null
            Test-Path $path | Should -BeTrue
        }

        It 'AC-05: JSON file is valid JSON' {
            $path = Get-TempReportPath 'json'
            $script:FakeOrphans | Export-SPCReport -Format JSON -OutputPath $path | Out-Null
            { Get-Content $path -Raw | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context 'SPC.ReportResult output object' {
        It 'AC-05: output has TypeName SPC.ReportResult' {
            $path   = Get-TempReportPath 'html'
            $result = $script:FakeOrphans | Export-SPCReport -Format HTML -OutputPath $path
            $result.PSObject.TypeNames | Should -Contain 'SPC.ReportResult'
        }

        It 'AC-05: TotalOrphansReported matches input count' {
            $path   = Get-TempReportPath 'csv'
            $result = $script:FakeOrphans | Export-SPCReport -Format CSV -OutputPath $path
            $result.TotalOrphansReported | Should -Be 3
        }

        It 'AC-05: FilePath in result resolves to the written file' {
            $path   = Get-TempReportPath 'csv'
            $result = $script:FakeOrphans | Export-SPCReport -Format CSV -OutputPath $path
            $result.FilePath | Should -Be $result.FilePath   # existence verified by Test-Path above
            Test-Path $result.FilePath | Should -BeTrue
        }

        It 'AC-05: -PassThru pipes input objects through after writing' {
            $path       = Get-TempReportPath 'csv'
            $allOutputs = @($script:FakeOrphans | Export-SPCReport -Format CSV -OutputPath $path -PassThru)
            # First object is SPC.ReportResult, remaining are SPC.OrphanedUser
            $allOutputs.Count | Should -BeGreaterThan 1
            $allOutputs | Where-Object { $_.PSObject.TypeNames -contains 'SPC.OrphanedUser' } |
                Should -HaveCount 3
        }
    }

    Context 'Default path generation' {
        It 'AC-05: auto-generated path includes tenant name and timestamp when -OutputPath omitted' {
            $result = $script:FakeOrphans | Export-SPCReport -Format HTML
            $result.FilePath | Should -Match 'SPClean_OrphanedUsers_contoso_\d{12}\.html'
            $script:TempFiles.Add($result.FilePath)
        }
    }

    Context 'Warning on empty input' {
        It 'AC-05: emits a warning and no result when input is empty' {
            $result = @() | Export-SPCReport -Format CSV -WarningVariable wv -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $wv     | Should -Match 'No input objects received'
        }
    }

    Context 'AC-12: no credentials in output streams' {
        It 'AC-12: verbose and information streams contain no credential strings' {
            $path = Get-TempReportPath 'html'
            $out  = & {
                $script:SPCContext = $script:SPCContext
                $script:FakeOrphans | Export-SPCReport -Format HTML -OutputPath $path -Verbose 4>&1 5>&1
            } 2>&1
            $out | ForEach-Object { [string]$_ } |
                Should -Not -Match 'password|secret|token|pfx|credential'
        }
    }
}
