#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/Write-SPCAuditLogInternal.ps1')
}

Describe 'Write-SPCAuditLogInternal Unit Tests' -Tag 'Logging', 'Internal', 'Audit' {
    BeforeAll {
        $TestLogDir = Join-Path -Path $TestDrive -ChildPath 'AuditLogs'
    }

    Context 'TC-AUDIT-001: Automatic Directory Provisioning' {
        It 'TC-AUDIT-001.1: Should create log directory if it does not exist' {
            $targetLog = Join-Path -Path $TestLogDir -ChildPath 'NewSubFolder\audit.csv'

            Write-SPCAuditLogInternal `
                -LogPath $targetLog `
                -SiteUrl 'https://contoso.sharepoint.com/sites/HR' `
                -TargetType 'RecycleBinItem' `
                -ItemId 'item-101' `
                -ItemTitle 'old_report.docx' `
                -FileRelativeUrl '/sites/HR/docs/old_report.docx' `
                -SizeBytes 1048576 `
                -DeletedDate (Get-Date) `
                -DeletedByUPN 'user1@contoso.com' `
                -OperatorUPN 'admin@contoso.onmicrosoft.com' `
                -ExecutionStatus 'SUCCESS' `
                -ErrorMessage ''

            Test-Path $targetLog | Should -BeTrue
        }
    }

    Context 'TC-AUDIT-002: Header Generation on New File' {
        It 'TC-AUDIT-002.1: Should write standard 13-column UTF-8 CSV Header on fresh creation' {
            $freshLog = Join-Path -Path $TestLogDir -ChildPath 'fresh_audit.csv'

            Write-SPCAuditLogInternal `
                -LogPath $freshLog `
                -SiteUrl 'https://contoso.sharepoint.com/sites/HR' `
                -TargetType 'RecycleBinItem' `
                -ItemId 'item-102' `
                -ItemTitle 'data.xlsx' `
                -FileRelativeUrl '/sites/HR/docs/data.xlsx' `
                -SizeBytes 2097152 `
                -DeletedDate (Get-Date) `
                -DeletedByUPN 'user2@contoso.com' `
                -OperatorUPN 'admin@contoso.onmicrosoft.com' `
                -ExecutionStatus 'SIMULATED' `
                -ErrorMessage ''

            $lines = Get-Content -Path $freshLog
            $lines.Count | Should -Be 2
            $header = $lines[0]
            $header | Should -Match 'TimestampUtc'
            $header | Should -Match 'SiteUrl'
            $header | Should -Match 'TargetType'
            $header | Should -Match 'ItemId'
            $header | Should -Match 'ItemTitle'
            $header | Should -Match 'FileRelativeUrl'
            $header | Should -Match 'SizeBytes'
            $header | Should -Match 'SizeMB'
            $header | Should -Match 'DeletedDateUtc'
            $header | Should -Match 'DeletedByUPN'
            $header | Should -Match 'OperatorUPN'
            $header | Should -Match 'ExecutionStatus'
            $header | Should -Match 'ErrorMessage'
        }
    }

    Context 'TC-AUDIT-003: Append-Only Integrity' {
        It 'TC-AUDIT-003.1: Should append records without rewriting CSV header when file exists' {
            $appendLog = Join-Path -Path $TestLogDir -ChildPath 'append_audit.csv'

            # First Write
            Write-SPCAuditLogInternal -LogPath $appendLog -SiteUrl 'https://contoso.sharepoint.com/sites/1' -TargetType 'RecycleBinItem' -ItemId '1' -ItemTitle 'f1' -FileRelativeUrl '/1' -SizeBytes 1024 -DeletedDate (Get-Date) -DeletedByUPN 'u1' -OperatorUPN 'admin@contoso.com' -ExecutionStatus 'SUCCESS' -ErrorMessage ''
            
            # Second Write
            Write-SPCAuditLogInternal -LogPath $appendLog -SiteUrl 'https://contoso.sharepoint.com/sites/2' -TargetType 'FileVersion' -ItemId '2' -ItemTitle 'f2' -FileRelativeUrl '/2' -SizeBytes 2048 -DeletedDate (Get-Date) -DeletedByUPN 'u2' -OperatorUPN 'admin@contoso.com' -ExecutionStatus 'SUCCESS' -ErrorMessage ''

            $lines = Get-Content -Path $appendLog
            $lines.Count | Should -Be 3  # 1 header + 2 data rows
        }
    }

    Context 'TC-AUDIT-004: Schema Validation & Accurate Value Mapping' {
        It 'TC-AUDIT-004.1: Should correctly record SizeMB and ErrorMessage for FAILED status' {
            $errorLog = Join-Path -Path $TestLogDir -ChildPath 'error_audit.csv'

            Write-SPCAuditLogInternal `
                -LogPath $errorLog `
                -SiteUrl 'https://contoso.sharepoint.com/sites/Secure' `
                -TargetType 'FileVersion' `
                -ItemId 'ver-999' `
                -ItemTitle 'secure.docx' `
                -FileRelativeUrl '/sites/Secure/secure.docx' `
                -SizeBytes 10485760 `
                -DeletedDate (Get-Date) `
                -DeletedByUPN 'exec@contoso.com' `
                -OperatorUPN 'admin@contoso.onmicrosoft.com' `
                -ExecutionStatus 'FAILED' `
                -ErrorMessage 'Access Denied (403 Forbidden)'

            $csvData = Import-Csv -Path $errorLog
            $csvData.SizeMB | Should -Be '10'
            $csvData.ExecutionStatus | Should -Be 'FAILED'
            $csvData.ErrorMessage | Should -Be 'Access Denied (403 Forbidden)'
            $csvData.OperatorUPN | Should -Be 'admin@contoso.onmicrosoft.com'
        }
    }
}
