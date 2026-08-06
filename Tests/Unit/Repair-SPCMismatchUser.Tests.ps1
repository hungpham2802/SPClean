#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Get-SPCRiskLevel.ps1')
    . (Join-Path $PSScriptRoot '../../Private/LicenseManager.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Remediate/Repair-SPCMismatchUser.ps1')

    $script:FakeContext = [PSCustomObject]@{
        TenantName           = 'contoso'
        AuthMethod           = 'Interactive'
        ConnectedAt          = (Get-Date).ToUniversalTime()
        PnPContext           = $null
        GraphAccessToken     = 'fake-graph-token'
        License              = [PSCustomObject]@{ Tier = 'Pro'; Features = @('MismatchRemediation') }
    }
}

Describe 'Repair-SPCMismatchUser' {
    BeforeEach {
        $script:SPCContext = $script:FakeContext

        Mock Get-PnPAccessToken { return 'fake-token' }
        Mock Get-PnPAccessToken { return 'fake' }
        Mock Connect-PnPOnline { return $null }
        Mock Remove-PnPUser {}
        Mock Get-PnPRoleAssignment { return @() }
        Mock Add-PnPRoleAssignment {}
        Mock Add-PnPGroupMember {}
        Mock Assert-SPCProLicense {}
    }

    Context 'Mode and Filtering' {
        It 'Skips GuestMismatch items' {
            $guest = [PSCustomObject]@{ SiteUrl = 'https://contoso/sites/hr'; UPN = 'guest#EXT#@contoso.com'; Status = 'GuestMismatch'; EntraObjectId = '123' }
            $guest | Add-Member -MemberType NoteProperty -Name 'PSObject.TypeNames' -Value 'SPC.MismatchUser' -Force
            
            Repair-SPCMismatchUser -InputObject $guest -Mode Clean -WarningVariable wv -Force | Out-Null
            $wv | Should -Match 'Skipping Guest user'
            Should -Not -Invoke Remove-PnPUser
        }

        It 'Removes UIL entry in Clean mode' {
            $stale = [PSCustomObject]@{ SiteUrl = 'https://contoso/sites/hr'; UPN = 'stale@contoso.com'; Status = 'StaleIdentity'; EntraObjectId = '123'; LoginName = 'i:0#.f|membership|stale@contoso.com' }
            
            $res = Repair-SPCMismatchUser -InputObject $stale -Mode Clean -Force
            Should -Invoke Remove-PnPUser -Times 1
            $res.RemovedFromUIL | Should -Be $true
            $res.PermissionsRestored | Should -Be 0
        }

        It 'Restores permissions in CleanAndRestore mode' {
            $stale = [PSCustomObject]@{ SiteUrl = 'https://contoso/sites/hr'; UPN = 'stale@contoso.com'; Status = 'StaleIdentity'; EntraObjectId = '123'; LoginName = 'i:0#.f|membership|stale@contoso.com'; GroupMemberships = @('HR Members') }
            Mock Get-PnPRoleAssignment { return @([PSCustomObject]@{ RoleDefinitionId = 'Full Control' }) }
            
            $res = Repair-SPCMismatchUser -InputObject $stale -Mode CleanAndRestore -Force
            
            Should -Invoke Remove-PnPUser -Times 1
            Should -Invoke Add-PnPRoleAssignment -Times 1 -ParameterFilter { $LoginName -eq 'i:0#.f|membership|stale@contoso.com' -and $RoleDefinitionName -eq 'Full Control' }
            Should -Invoke Add-PnPGroupMember -Times 1 -ParameterFilter { $LoginName -eq 'i:0#.f|membership|stale@contoso.com' -and $Group -eq 'HR Members' }
            $res.PermissionsRestored | Should -Be 2
        }
    }
}
