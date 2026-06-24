#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/Get-SPCRiskLevel.ps1')
}

Describe 'Get-SPCRiskLevel' {

    Context 'HIGH risk' {
        It 'AC-03: Deleted + direct permissions = HIGH' {
            Get-SPCRiskLevel -OrphanType Deleted -HasDirectPermissions $true -GroupMembershipCount 0 |
                Should -Be 'HIGH'
        }

        It 'AC-03: Deleted + group memberships = HIGH' {
            Get-SPCRiskLevel -OrphanType Deleted -HasDirectPermissions $false -GroupMembershipCount 3 |
                Should -Be 'HIGH'
        }

        It 'AC-03: Deleted + both permissions and groups = HIGH' {
            Get-SPCRiskLevel -OrphanType Deleted -HasDirectPermissions $true -GroupMembershipCount 2 |
                Should -Be 'HIGH'
        }

        It 'AC-03: GuestOrphaned + direct permissions = HIGH' {
            Get-SPCRiskLevel -OrphanType GuestOrphaned -HasDirectPermissions $true -GroupMembershipCount 0 |
                Should -Be 'HIGH'
        }
    }

    Context 'MEDIUM risk' {
        It 'AC-03: SoftDeleted (no permissions) = MEDIUM' {
            Get-SPCRiskLevel -OrphanType SoftDeleted -HasDirectPermissions $false -GroupMembershipCount 0 |
                Should -Be 'MEDIUM'
        }

        It 'AC-03: SoftDeleted (with permissions) = MEDIUM — SoftDeleted always MEDIUM regardless of permissions' {
            Get-SPCRiskLevel -OrphanType SoftDeleted -HasDirectPermissions $true -GroupMembershipCount 5 |
                Should -Be 'MEDIUM'
        }

        It 'AC-03: Disabled + direct permissions = MEDIUM' {
            Get-SPCRiskLevel -OrphanType Disabled -HasDirectPermissions $true -GroupMembershipCount 0 |
                Should -Be 'MEDIUM'
        }
    }

    Context 'LOW risk' {
        It 'AC-03: Deleted + no permissions + no groups = LOW' {
            Get-SPCRiskLevel -OrphanType Deleted -HasDirectPermissions $false -GroupMembershipCount 0 |
                Should -Be 'LOW'
        }

        It 'AC-03: GuestOrphaned + no direct permissions = LOW' {
            Get-SPCRiskLevel -OrphanType GuestOrphaned -HasDirectPermissions $false -GroupMembershipCount 0 |
                Should -Be 'LOW'
        }

        It 'AC-03: Disabled + no direct permissions = LOW' {
            Get-SPCRiskLevel -OrphanType Disabled -HasDirectPermissions $false -GroupMembershipCount 5 |
                Should -Be 'LOW'
        }

        It 'AC-03: Unknown type = LOW' {
            Get-SPCRiskLevel -OrphanType Unknown -HasDirectPermissions $false -GroupMembershipCount 0 |
                Should -Be 'LOW'
        }
    }

    Context 'First-match order' {
        It 'AC-03: SoftDeleted takes MEDIUM before the Deleted+permissions HIGH rule' {
            # SoftDeleted is evaluated before Disabled+perms; must still return MEDIUM
            Get-SPCRiskLevel -OrphanType SoftDeleted -HasDirectPermissions $true -GroupMembershipCount 10 |
                Should -Be 'MEDIUM'
        }

        It 'AC-03: GuestOrphaned without permissions falls through to LOW, not caught by Deleted rule' {
            Get-SPCRiskLevel -OrphanType GuestOrphaned -HasDirectPermissions $false -GroupMembershipCount 0 |
                Should -Not -Be 'HIGH'
        }
    }

    Context 'AC-12: no credentials in output stream' {
        It 'AC-12: Get-SPCRiskLevel does not emit credentials' {
            $out = Get-SPCRiskLevel -OrphanType Deleted -HasDirectPermissions $true -GroupMembershipCount 0 4>&1 5>&1
            $out | ForEach-Object { [string]$_ } | Should -Not -Match 'password|secret|token|pfx|credential'
        }
    }
}
