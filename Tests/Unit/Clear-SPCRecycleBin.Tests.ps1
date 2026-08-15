#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Private/LicenseManager.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Connect-SPCSiteInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCPurviewHoldInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Write-SPCAuditLogInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Invoke-SPCSafeRecycleBinPurgeInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Remediate/Clear-SPCRecycleBin.ps1')

    $script:SPCContext = [PSCustomObject]@{
        TenantName       = 'contoso'
        AuthMethod       = 'Interactive'
        PnPContext       = [PSCustomObject]@{}
        GraphAccessToken = 'mock_token'
    }
}

Describe 'Clear-SPCRecycleBin Unit Tests' -Tag 'Remediate', 'Storage' {
    Context 'AC-08: DryRun and WhatIf Simulation' {
        It 'AC-08: Should calculate potential freed storage without deleting items when -DryRun is used' {
            Mock Test-SPCPurviewHoldInternal { [PSCustomObject]@{ IsHoldActive = $false; HoldType = 'None' } }
            Mock Invoke-SPCSafeRecycleBinPurgeInternal {
                [PSCustomObject]@{ DeletedCount = 25; StorageFreedMB = 1024.0; ErrorCount = 0 }
            }

            $result = Clear-SPCRecycleBin -SiteUrl 'https://contoso.sharepoint.com/sites/hr' -DryRun

            $result.IsDryRun | Should -BeTrue
            $result.Status | Should -Be 'Simulated'
            $result.StorageFreedMB | Should -Be 1024.0
            $result.MonthlyCostSavedUSD | Should -Be 0.20
        }
    }

    Context 'AC-10: Actual Purge with Pro License' {
        It 'AC-10: Should perform actual purge and call Invoke-SPCSafeRecycleBinPurgeInternal when licensed' {
            Mock Assert-SPCProLicense {}
            Mock Test-SPCPurviewHoldInternal { [PSCustomObject]@{ IsHoldActive = $false; HoldType = 'None' } }
            Mock Invoke-SPCSafeRecycleBinPurgeInternal {
                param($SiteUrl, $OlderThanDays, $Stage, $DryRun, $AuditLogPath)
                $Stage | Should -Be '2ndStage'
                $DryRun | Should -BeFalse
                [PSCustomObject]@{ DeletedCount = 50; StorageFreedMB = 2048.0; ErrorCount = 0 }
            }

            $result = Clear-SPCRecycleBin -SiteUrl 'https://contoso.sharepoint.com/sites/ops' -SecondStageOnly -OlderThanDays 30 -Force

            $result.IsDryRun | Should -BeFalse
            $result.Status | Should -Be 'Success'
            $result.StorageFreedMB | Should -Be 2048.0
        }
    }

    Context 'AC-11: Purview Hold Immunity' {
        It 'AC-11: Should skip purge and log SKIPPED_COMPLIANCE_HOLD when Purview Hold is active' {
            Mock Assert-SPCProLicense {}
            Mock Test-SPCPurviewHoldInternal {
                [PSCustomObject]@{ IsHoldActive = $true; HoldType = 'PurviewRetentionPolicy' }
            }
            Mock Write-SPCAuditLogInternal {
                param($ExecutionStatus)
                $ExecutionStatus | Should -Be 'SKIPPED_COMPLIANCE_HOLD'
            }
            Mock Invoke-SPCSafeRecycleBinPurgeInternal {
                throw "Should not be called"
            }

            $result = Clear-SPCRecycleBin -SiteUrl 'https://contoso.sharepoint.com/sites/heldsite' -Force

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'ERR-LIC-003: License Gate Protection' {
        It 'Throws license error when executed in Free Tier without -DryRun' {
            Mock Assert-SPCProLicense {
                throw "ERR-LIC-003: Clear-SPCRecycleBin requires a Pro or Consultant license."
            }

            { Clear-SPCRecycleBin -SiteUrl 'https://contoso.sharepoint.com/sites/unlic' -Force } |
                Should -Throw -ExpectedMessage "*ERR-LIC-*"
        }
    }
}
