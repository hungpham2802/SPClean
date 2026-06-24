#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Save-SPCPermissionSnapshot.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Remediate/Remove-SPCOrphanedUser.ps1')

    # ── Shared fake data ────────────────────────────────────────────────────────

    $script:FakeContext = [PSCustomObject]@{
        TenantName           = 'contoso'
        AuthMethod           = 'Interactive'
        ConnectedAt          = (Get-Date).ToUniversalTime()
        PnPContext           = $null
        GraphAccessToken     = 'fake-graph-token'
        _ClientId            = $null
        _CertificatePath     = $null
        _CertificatePassword = $null
        _ClientSecret        = $null
    }

    function New-FakeOrphan {
        param(
            [string] $UPN          = 'jdoe@contoso.com',
            [string] $OrphanType   = 'Deleted',
            [string] $RiskLevel    = 'HIGH',
            [bool]   $DirectPerms  = $true,
            [string] $SiteUrl      = 'https://contoso.sharepoint.com/sites/HR'
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
            HasDirectPermissions = $DirectPerms
            GroupMemberships     = @('HR Members')
            LastActivityDate     = $null
            DetectedAt           = (Get-Date).ToUniversalTime()
        }
        $o.PSObject.TypeNames.Insert(0, 'SPC.OrphanedUser')
        $o
    }
}

Describe 'Remove-SPCOrphanedUser' {

    BeforeEach {
        $script:SPCContext = $script:FakeContext

        Mock Connect-PnPOnline           { return [PSCustomObject]@{ Url = 'fake' } }
        Mock Remove-PnPUser              {}
        Mock Get-PnPRoleAssignment       { return @() }
        Mock Remove-PnPRoleAssignment    {}
        Mock Save-SPCPermissionSnapshot  { return [System.IO.FileInfo]::new('C:\fake\snap.json') }
    }

    Context 'AC-06: WhatIf writes exact SRS message, no changes made' {
        It 'AC-06: WhatIf writes exact SRS message to information stream' {
            $orphan = New-FakeOrphan -UPN 'jdoe@contoso.com' -SiteUrl 'https://contoso.sharepoint.com/sites/HR'
            $info   = $orphan | Remove-SPCOrphanedUser -WhatIf -InformationAction Continue 6>&1
            $info   | Should -Match "WhatIf: Would remove user John Doe \(jdoe@contoso\.com\) from site https://contoso\.sharepoint\.com/sites/HR\. OrphanType: Deleted\. DirectPermissions: True\."
        }

        It 'AC-06: WhatIf does not call Remove-PnPUser' {
            $orphan = New-FakeOrphan
            $orphan | Remove-SPCOrphanedUser -WhatIf -InformationAction SilentlyContinue | Out-Null
            Should -Invoke Remove-PnPUser -Times 0 -Exactly
        }

        It 'AC-06: WhatIf does not call Save-SPCPermissionSnapshot even with -CreateSnapshot' {
            $orphan = New-FakeOrphan
            $orphan | Remove-SPCOrphanedUser -WhatIf -CreateSnapshot -SnapshotPath 'C:\fake' `
                -InformationAction SilentlyContinue | Out-Null
            Should -Invoke Save-SPCPermissionSnapshot -Times 0 -Exactly
        }
    }

    Context 'AC-06: OrphanType filter defaults to Deleted only' {
        It 'AC-06: SoftDeleted orphans are skipped by default' {
            $softDeleted = New-FakeOrphan -OrphanType 'SoftDeleted'
            $softDeleted | Remove-SPCOrphanedUser -Force | Out-Null
            Should -Invoke Remove-PnPUser -Times 0 -Exactly
        }

        It 'AC-06: Disabled orphans are skipped by default' {
            $disabled = New-FakeOrphan -OrphanType 'Disabled'
            $disabled | Remove-SPCOrphanedUser -Force | Out-Null
            Should -Invoke Remove-PnPUser -Times 0 -Exactly
        }

        It 'AC-06: Deleted orphans are processed by default' {
            $deleted = New-FakeOrphan -OrphanType 'Deleted'
            $deleted | Remove-SPCOrphanedUser -Force | Out-Null
            Should -Invoke Remove-PnPUser -Times 1 -Exactly
        }

        It 'AC-06: SoftDeleted is processed when explicitly opted in' {
            $softDeleted = New-FakeOrphan -OrphanType 'SoftDeleted' -RiskLevel 'MEDIUM'
            $softDeleted | Remove-SPCOrphanedUser -OrphanType 'SoftDeleted' -Force | Out-Null
            Should -Invoke Remove-PnPUser -Times 1 -Exactly
        }
    }

    Context 'AC-06: CreateSnapshot calls Save-SPCPermissionSnapshot before removal' {
        It 'AC-06: Save-SPCPermissionSnapshot is called when -CreateSnapshot is set' {
            $orphan = New-FakeOrphan
            $orphan | Remove-SPCOrphanedUser -CreateSnapshot -SnapshotPath 'C:\fake' -Force | Out-Null
            Should -Invoke Save-SPCPermissionSnapshot -Times 1 -Exactly
        }

        It 'AC-06: SnapshotPath is populated in SPC.RemovalResult when -CreateSnapshot used' {
            $orphan = New-FakeOrphan
            $result = $orphan | Remove-SPCOrphanedUser -CreateSnapshot -SnapshotPath 'C:\fake' -Force
            $result.SnapshotPath | Should -Not -BeNullOrEmpty
        }

        It 'AC-06: SnapshotPath is null in SPC.RemovalResult without -CreateSnapshot' {
            $orphan = New-FakeOrphan
            $result = $orphan | Remove-SPCOrphanedUser -Force
            $result.SnapshotPath | Should -BeNullOrEmpty
        }
    }

    Context 'AC-06: SPC.RemovalResult output' {
        It 'AC-06: output has TypeName SPC.RemovalResult' {
            $orphan = New-FakeOrphan
            $result = $orphan | Remove-SPCOrphanedUser -Force
            $result.PSObject.TypeNames | Should -Contain 'SPC.RemovalResult'
        }

        It 'AC-06: Status = Success when UIL removal succeeds' {
            $orphan = New-FakeOrphan
            $result = $orphan | Remove-SPCOrphanedUser -Force
            $result.Status | Should -Be 'Success'
        }

        It 'AC-06: Status = Failed when Remove-PnPUser throws' {
            Mock Remove-PnPUser { throw 'Access denied' }
            $orphan = New-FakeOrphan
            $result = $orphan | Remove-SPCOrphanedUser -Force 2>$null
            $result.Status        | Should -Be 'Failed'
            $result.ErrorMessage  | Should -Match 'Access denied'
        }

        It 'AC-06: RemovedFromUIL = $true on success' {
            $orphan = New-FakeOrphan
            $result = $orphan | Remove-SPCOrphanedUser -Force
            $result.RemovedFromUIL | Should -BeTrue
        }

        It 'AC-06: summary is written to information stream' {
            $orphan = New-FakeOrphan
            $info   = $orphan | Remove-SPCOrphanedUser -Force -InformationAction Continue 6>&1
            $info   | Should -Match 'Removed \d+ orphaned users across \d+ sites'
        }
    }

    Context 'RiskLevel filter' {
        It 'AC-06: LOW orphan is skipped when -RiskLevel HIGH is specified' {
            $low = New-FakeOrphan -RiskLevel 'LOW'
            $low | Remove-SPCOrphanedUser -RiskLevel 'HIGH' -Force | Out-Null
            Should -Invoke Remove-PnPUser -Times 0 -Exactly
        }

        It 'AC-06: HIGH orphan is processed when -RiskLevel HIGH is specified' {
            $high = New-FakeOrphan -RiskLevel 'HIGH'
            $high | Remove-SPCOrphanedUser -RiskLevel 'HIGH' -Force | Out-Null
            Should -Invoke Remove-PnPUser -Times 1 -Exactly
        }
    }

    Context 'AC-12: no credentials in output streams' {
        It 'AC-12: verbose output does not contain credential strings' {
            $orphan = New-FakeOrphan
            $out    = & {
                $script:SPCContext = $script:FakeContext
                $orphan | Remove-SPCOrphanedUser -Force -Verbose 4>&1 5>&1
            } 2>&1
            $out | ForEach-Object { [string]$_ } |
                Should -Not -Match 'password|secret|pfx|credential'
        }
    }
}
