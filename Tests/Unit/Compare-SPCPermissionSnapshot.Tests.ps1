#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Report/Compare-SPCPermissionSnapshot.ps1')
}

Describe 'Compare-SPCPermissionSnapshot Unit Tests' -Tag 'Governance', 'Security', 'Drift' {
    BeforeEach {
        $script:SPCContext = [PSCustomObject]@{
            TenantName = 'contoso'
        }
    }

    Context 'TC-SNAP-001: Added Permissions & Roles Detection' {
        It 'TC-SNAP-001.1: Should detect newly added SCA, Owner, Direct Full Control, and Guest accounts' {
            Mock Test-SPCConnection { $true }

            $baselineData = @(
                @{
                    user = @{ upn = 'admin@contoso.com' }
                    isSCA = $true
                    isOwner = $true
                    permissions = @('Full Control')
                }
            )

            $currentData = @(
                @{
                    user = @{ upn = 'admin@contoso.com' }
                    isSCA = $true
                    isOwner = $true
                    permissions = @('Full Control')
                },
                @{
                    user = @{ upn = 'new_owner@contoso.com' }
                    isSCA = $false
                    isOwner = $true
                    permissions = @('Edit')
                },
                @{
                    user = @{ upn = 'direct_fc@contoso.com' }
                    isSCA = $false
                    isOwner = $false
                    permissions = @('Full Control')
                },
                @{
                    user = @{ upn = 'guest_user#EXT#@fabrikam.com' }
                    isSCA = $false
                    isOwner = $false
                    permissions = @('Read')
                }
            )

            $basePath = Join-Path -Path $TestDrive -ChildPath 'baseline.json'
            $currPath = Join-Path -Path $TestDrive -ChildPath 'current.json'

            $baselineData | ConvertTo-Json -Depth 5 | Set-Content -Path $basePath -Encoding UTF8
            $currentData | ConvertTo-Json -Depth 5 | Set-Content -Path $currPath -Encoding UTF8

            $drift = Compare-SPCPermissionSnapshot -BaselineSnapshotPath $basePath -CurrentSnapshotPath $currPath

            $drift | Should -Not -BeNullOrEmpty
            $drift.NewSCAOrOwners | Should -Contain 'new_owner@contoso.com'
            $drift.NewDirectFullControlAssignments | Should -Contain 'direct_fc@contoso.com'
            $drift.NewGuestAccounts | Should -Contain 'guest_user#EXT#@fabrikam.com'
        }
    }

    Context 'TC-SNAP-004: Identical Snapshots (No Drift)' {
        It 'TC-SNAP-004.1: Should return empty drift collections when snapshots are identical' {
            Mock Test-SPCConnection { $true }

            $data = @(
                @{
                    user = @{ upn = 'user1@contoso.com' }
                    isSCA = $true
                    isOwner = $false
                    permissions = @('Full Control')
                }
            )

            $basePath = Join-Path -Path $TestDrive -ChildPath 'same_base.json'
            $currPath = Join-Path -Path $TestDrive -ChildPath 'same_curr.json'

            $data | ConvertTo-Json -Depth 5 | Set-Content -Path $basePath -Encoding UTF8
            $data | ConvertTo-Json -Depth 5 | Set-Content -Path $currPath -Encoding UTF8

            $drift = Compare-SPCPermissionSnapshot -BaselineSnapshotPath $basePath -CurrentSnapshotPath $currPath

            $drift.NewSCAOrOwners.Count | Should -Be 0
            $drift.NewDirectFullControlAssignments.Count | Should -Be 0
            $drift.NewGuestAccounts.Count | Should -Be 0
        }
    }

    Context 'Error and Guard Validation' {
        It 'Should throw ERR-001 when connection is missing' {
            Mock Test-SPCConnection { throw 'Not connected' }

            $fakeFile = Join-Path -Path $TestDrive -ChildPath 'fake.json'
            '{}' | Set-Content -Path $fakeFile

            { Compare-SPCPermissionSnapshot -BaselineSnapshotPath $fakeFile -CurrentSnapshotPath $fakeFile } |
                Should -Throw -ExpectedMessage '*ERR-001*'
        }
    }
}
