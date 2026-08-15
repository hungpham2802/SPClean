#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $moduleRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    $publicDir  = Join-Path $moduleRoot 'Public'
    $privateDir = Join-Path $moduleRoot 'Private'

    . (Join-Path $privateDir 'Test-SPCConnection.ps1')
    . (Join-Path $privateDir 'LicenseManager.ps1')
    if (Test-Path (Join-Path $privateDir 'Connect-SPCSiteInternal.ps1')) {
        . (Join-Path $privateDir 'Connect-SPCSiteInternal.ps1')
    }
    . (Join-Path $publicDir 'Remediate\Restore-SPCOrphanedUser.ps1')

    # Standardized mock module context schema
    $script:FakeContext = [PSCustomObject]@{
        TenantName             = 'contoso'
        TenantId               = 'tid-12345'
        IsConnected            = $true
        AuthMethod             = 'Interactive'
        ConnectedAt            = (Get-Date).ToUniversalTime()
        GraphTokenRefreshedAt  = (Get-Date).ToUniversalTime()
        PnPContext             = [PSCustomObject]@{ Url = 'https://contoso-admin.sharepoint.com' }
        GraphAccessToken       = 'mock_access_token'
        _ClientId              = 'mock_client_id'
        _CertificateThumbprint = $null
        _CertificatePath       = $null
        _CertificatePassword   = $null
        _ClientSecret          = $null
    }
}

Describe 'Restore-SPCOrphanedUser' {

    BeforeEach {
        $script:SPCContext = $script:FakeContext

        Mock Test-SPCConnection {}
        Mock Assert-SPCProLicense {}
        Mock Get-PnPAccessToken { return 'mock_token' }
        Mock Connect-PnPOnline  { return [PSCustomObject]@{ Url = 'https://contoso.sharepoint.com/sites/HR' } }
        Mock Get-PnPWeb         { return [PSCustomObject]@{ Title = 'Human Resources' } }
        Mock Add-PnPRoleAssignment {}
        Mock Add-PnPGroupMember    {}
        Mock Set-PnPTenantSite     {}
        Mock Remove-PnPSiteCollectionAdmin {}
    }

    Context 'Input Validation & Guard Scenarios' {
        It 'Throws when target snapshot file does not exist' {
            $nonExistentPath = Join-Path $TestDrive 'non_existent_snapshot.json'
            { Restore-SPCOrphanedUser -SnapshotPath $nonExistentPath } | Should -Throw "*Snapshot file not found*"
        }

        It 'Throws when snapshot is missing required top-level schema fields' {
            $invalidJson = @{ invalidField = "test" } | ConvertTo-Json
            $invalidSnapPath = Join-Path $TestDrive 'invalid_schema.json'
            Set-Content -Path $invalidSnapPath -Value $invalidJson -Encoding UTF8

            { Restore-SPCOrphanedUser -SnapshotPath $invalidSnapPath } | Should -Throw "*missing required fields*"
        }

        It 'AC-ARCH-02: Blocks execution when Pro license check fails' {
            Mock Assert-SPCProLicense { throw 'ERR-LIC-001: Feature RestoreSnapshot requires an active Pro license.' }
            $snapPath = Join-Path $TestDrive 'valid_snap.json'
            @{ siteUrl = 'https://contoso.sharepoint.com/sites/HR'; user = @{ loginName = 'i:0#.f|membership|user@contoso.com'; upn = 'user@contoso.com'; displayName = 'User' }; permissions = @() } | ConvertTo-Json | Set-Content -Path $snapPath -Encoding UTF8

            { Restore-SPCOrphanedUser -SnapshotPath $snapPath } | Should -Throw '*ERR-LIC-001*'
        }
    }

    Context 'AC-ARCH-05 / AC-TEST-01: Snapshot Schema Compatibility (v1.0 & v1.1)' {
        It 'AC-ARCH-05: Restores permissions and group memberships from v1.0 snapshot format' {
            $snapV10 = [ordered]@{
                snapshotVersion = '1.0'
                siteUrl         = 'https://contoso.sharepoint.com/sites/HR'
                user            = @{
                    loginName   = 'i:0#.f|membership|alice@contoso.com'
                    displayName = 'Alice Smith'
                    upn         = 'alice@contoso.com'
                }
                permissions     = @(
                    @{ scope = 'https://contoso.sharepoint.com/sites/HR'; permissionLevel = 'Edit'; inheritanceStatus = 'Direct' }
                )
                groupMemberships = @(
                    @{ groupId = 10; groupName = 'HR Members' }
                )
            } | ConvertTo-Json -Depth 5

            $snapPath = Join-Path $TestDrive 'snap_v10.json'
            Set-Content -Path $snapPath -Value $snapV10 -Encoding UTF8

            $result = Restore-SPCOrphanedUser -SnapshotPath $snapPath -Confirm:$false
            $result.Status              | Should -Be 'Success'
            $result.PermissionsRestored | Should -Be 2
            $result.PermissionsFailed   | Should -Be 0
            $result.UPN                 | Should -Be 'alice@contoso.com'
            $result.SiteUrl             | Should -Be 'https://contoso.sharepoint.com/sites/HR'
            $result.PSObject.TypeNames  | Should -Contain 'SPC.RestoreResult'

            Should -Invoke Add-PnPRoleAssignment -Times 1 -Exactly
            Should -Invoke Add-PnPGroupMember -Times 1 -Exactly
        }

        It 'AC-ARCH-05: Restores permissions from v1.1 snapshot format' {
            $snapV11 = [ordered]@{
                '$schema'            = 'https://m365automation.com/schemas/spclean/snapshot-v1.1.json'
                snapshotVersion      = '1.1'
                createdAt            = (Get-Date).ToUniversalTime().ToString('o')
                tenantName           = 'contoso'
                siteUrl              = 'https://contoso.sharepoint.com/sites/Finance'
                user                 = @{
                    loginName        = 'i:0#.f|membership|bob@contoso.com'
                    displayName      = 'Bob Jones'
                    upn              = 'bob@contoso.com'
                }
                isEmptyPermissionSet = $false
                permissions          = @(
                    @{ scope = 'https://contoso.sharepoint.com/sites/Finance'; permissionLevel = 'Read'; inheritanceStatus = 'Direct' },
                    @{ scope = 'https://contoso.sharepoint.com/sites/Finance'; permissionLevel = 'Contribute'; inheritanceStatus = 'Direct' }
                )
                groupMemberships     = @()
            } | ConvertTo-Json -Depth 5

            $snapPath = Join-Path $TestDrive 'snap_v11.json'
            Set-Content -Path $snapPath -Value $snapV11 -Encoding UTF8

            $result = Restore-SPCOrphanedUser -SnapshotPath $snapPath -Confirm:$false
            $result.Status              | Should -Be 'Success'
            $result.PermissionsRestored | Should -Be 2
            $result.PermissionsFailed   | Should -Be 0
            Should -Invoke Add-PnPRoleAssignment -Times 2 -Exactly
        }

        It 'AC-ARCH-05: Handles empty permission snapshots with sentinel __empty or empty array gracefully' {
            $snapEmpty = [ordered]@{
                snapshotVersion      = '1.1'
                siteUrl              = 'https://contoso.sharepoint.com/sites/HR'
                user                 = @{
                    loginName        = 'i:0#.f|membership|carol@contoso.com'
                    displayName      = 'Carol Danvers'
                    upn              = 'carol@contoso.com'
                }
                isEmptyPermissionSet = $true
                permissions          = @()
                groupMemberships     = @()
            } | ConvertTo-Json -Depth 5

            $snapPath = Join-Path $TestDrive 'snap_empty.json'
            Set-Content -Path $snapPath -Value $snapEmpty -Encoding UTF8

            $result = Restore-SPCOrphanedUser -SnapshotPath $snapPath -Confirm:$false
            $result.Status              | Should -Be 'Success'
            $result.PermissionsRestored | Should -Be 0
            $result.PermissionsFailed   | Should -Be 0
            Should -Invoke Add-PnPRoleAssignment -Times 0 -Exactly
            Should -Invoke Add-PnPGroupMember -Times 0 -Exactly
        }
    }

    Context 'AC-TEST-01 / NFR-REL-03: Partial Success & Error Recovery' {
        It 'NFR-REL-03: Returns PartialSuccess when one role assignment fails while others succeed' {
            $snap = [ordered]@{
                snapshotVersion  = '1.1'
                siteUrl          = 'https://contoso.sharepoint.com/sites/HR'
                user             = @{
                    loginName    = 'i:0#.f|membership|david@contoso.com'
                    displayName  = 'David Miller'
                    upn          = 'david@contoso.com'
                }
                permissions      = @(
                    @{ scope = 'https://contoso.sharepoint.com/sites/HR'; permissionLevel = 'CustomRole1'; inheritanceStatus = 'Direct' },
                    @{ scope = 'https://contoso.sharepoint.com/sites/HR'; permissionLevel = 'Read'; inheritanceStatus = 'Direct' }
                )
                groupMemberships = @()
            } | ConvertTo-Json -Depth 5

            $snapPath = Join-Path $TestDrive 'snap_partial.json'
            Set-Content -Path $snapPath -Value $snap -Encoding UTF8

            $script:partialCallIndex = 0
            Mock Add-PnPRoleAssignment {
                $script:partialCallIndex++
                if ($script:partialCallIndex -eq 1) {
                    throw 'Role definition CustomRole1 not found'
                }
            }

            $result = Restore-SPCOrphanedUser -SnapshotPath $snapPath -Confirm:$false
            $result.Status              | Should -Be 'PartialSuccess'
            $result.PermissionsRestored | Should -Be 1
            $result.PermissionsFailed   | Should -Be 1
            $result.ErrorMessage        | Should -Match 'CustomRole1'
        }
    }

    Context 'ShouldProcess & WhatIf Execution' {
        It 'AC-TEST-01: WhatIf mode previews restoration without invoking mutation cmdlets' {
            $snap = [ordered]@{
                snapshotVersion  = '1.1'
                siteUrl          = 'https://contoso.sharepoint.com/sites/HR'
                user             = @{
                    loginName    = 'i:0#.f|membership|eve@contoso.com'
                    displayName  = 'Eve Adams'
                    upn          = 'eve@contoso.com'
                }
                permissions      = @(
                    @{ scope = 'https://contoso.sharepoint.com/sites/HR'; permissionLevel = 'Edit'; inheritanceStatus = 'Direct' }
                )
                groupMemberships = @(
                    @{ groupId = 5; groupName = 'HR Editors' }
                )
            } | ConvertTo-Json -Depth 5

            $snapPath = Join-Path $TestDrive 'snap_whatif.json'
            Set-Content -Path $snapPath -Value $snap -Encoding UTF8

            $result = Restore-SPCOrphanedUser -SnapshotPath $snapPath -WhatIf
            $result.Status | Should -Be 'WhatIf'

            Should -Invoke Add-PnPRoleAssignment -Times 0 -Exactly
            Should -Invoke Add-PnPGroupMember -Times 0 -Exactly
        }
    }

    Context 'Security & Stream Isolation' {
        It 'AC-SEC-02: Does not leak tokens or sensitive credentials into Verbose stream' {
            $snap = [ordered]@{
                snapshotVersion  = '1.1'
                siteUrl          = 'https://contoso.sharepoint.com/sites/HR'
                user             = @{
                    loginName    = 'i:0#.f|membership|frank@contoso.com'
                    displayName  = 'Frank Castle'
                    upn          = 'frank@contoso.com'
                }
                permissions      = @(
                    @{ scope = 'https://contoso.sharepoint.com/sites/HR'; permissionLevel = 'Read'; inheritanceStatus = 'Direct' }
                )
                groupMemberships = @()
            } | ConvertTo-Json -Depth 5

            $snapPath = Join-Path $TestDrive 'snap_sec.json'
            Set-Content -Path $snapPath -Value $snap -Encoding UTF8

            $script:verboseLog = @()
            Mock Write-Verbose {
                param($Message)
                $script:verboseLog += $Message
            }

            Restore-SPCOrphanedUser -SnapshotPath $snapPath -Confirm:$false -Verbose

            $leak = $script:verboseLog | Where-Object { $_ -match 'password|secret|token|bearer|ey[A-Za-z0-9_-]+' }
            $leak | Should -BeNullOrEmpty
        }
    }
}
