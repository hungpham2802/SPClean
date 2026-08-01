#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Invoke-SPCGraphBatch.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Scan/Get-SPCMismatchUser.ps1')

    $script:FakeContext = [PSCustomObject]@{
        TenantName           = 'contoso'
        AuthMethod           = 'Interactive'
        ConnectedAt          = (Get-Date).ToUniversalTime()
        PnPContext           = $null
        GraphAccessToken     = 'fake-graph-token'
    }

    $script:FakeUILUsers = @(
        [PSCustomObject]@{ Id = 1; LoginName = 'i:0#.f|membership|healthy@contoso.com'; Title = 'Healthy'; Email = 'healthy@contoso.com'; AadObjectId = [guid]'11111111-1111-1111-1111-111111111111' }
        [PSCustomObject]@{ Id = 2; LoginName = 'i:0#.f|membership|stale@contoso.com'; Title = 'Stale'; Email = 'stale@contoso.com'; AadObjectId = [guid]'22222222-2222-2222-2222-222222222222' }
        [PSCustomObject]@{ Id = 3; LoginName = 'i:0#.f|membership|guest#EXT#@contoso.com'; Title = 'Guest'; Email = 'guest@contoso.com'; AadObjectId = [guid]'33333333-3333-3333-3333-333333333333' }
        [PSCustomObject]@{ Id = 4; LoginName = 'i:0#.f|membership|dup@contoso.com'; Title = 'Dup 1'; Email = 'dup@contoso.com'; AadObjectId = [guid]'44444444-4444-4444-4444-444444444444' }
        [PSCustomObject]@{ Id = 5; LoginName = 'i:0#.f|membership|dup@contoso.com'; Title = 'Dup 2'; Email = 'dup@contoso.com'; AadObjectId = [guid]'44444444-4444-4444-4444-444444444445' }
        [PSCustomObject]@{ Id = 6; LoginName = 'i:0#.f|membership|nomap@contoso.com'; Title = 'NoMap'; Email = 'nomap@contoso.com'; AadObjectId = [guid]::Empty }
    )
}

Describe 'Get-SPCMismatchUser' {
    BeforeEach {
        $script:SPCContext = $script:FakeContext

        Mock Get-PnPAccessToken { return 'fake-token' }
        Mock Connect-PnPOnline { return [PSCustomObject]@{ Url = 'https://fake.sharepoint.com/sites/HR' } }
        Mock Get-PnPWeb { return [PSCustomObject]@{ Title = 'Human Resources' } }
        Mock Get-PnPUser { return $script:FakeUILUsers }
    }

    Context 'Mismatch Classification' {
        It 'Correctly classifies Healthy, StaleIdentity, GuestMismatch, DuplicateEntry, and safe default Healthy when UIL ObjectId is empty' {
            Mock Get-PnPSiteUser { return $script:FakeUILUsers }
            Mock Invoke-SPCGraphBatch {
                return @(
                    [PSCustomObject]@{ id = '1'; status = 200; body = [PSCustomObject]@{ id = '11111111-1111-1111-1111-111111111111'; userPrincipalName = 'healthy@contoso.com' } }
                    [PSCustomObject]@{ id = '2'; status = 200; body = [PSCustomObject]@{ id = '22222222-2222-2222-2222-000000000000'; userPrincipalName = 'stale@contoso.com' } }
                    [PSCustomObject]@{ id = '3'; status = 200; body = [PSCustomObject]@{ id = '33333333-3333-3333-3333-000000000000'; userPrincipalName = 'guest#EXT#@contoso.com' } }
                    [PSCustomObject]@{ id = '4'; status = 200; body = [PSCustomObject]@{ id = '44444444-4444-4444-4444-444444444444'; userPrincipalName = 'dup@contoso.com' } }
                    [PSCustomObject]@{ id = '5'; status = 200; body = [PSCustomObject]@{ id = '55555555-5555-5555-5555-555555555555'; userPrincipalName = 'nomap@contoso.com' } }
                )
            }
            $result = @(Get-SPCMismatchUser -SiteUrl 'https://contoso.sharepoint.com/sites/HR')
            $result | Should -HaveCount 6
            
            $healthy = $result | Where-Object UPN -eq 'healthy@contoso.com'
            $healthy.Status | Should -Be 'Healthy'

            $stale = $result | Where-Object UPN -eq 'stale@contoso.com'
            $stale.Status | Should -Be 'StaleIdentity'

            $guest = $result | Where-Object UPN -eq 'guest#EXT#@contoso.com'
            $guest.Status | Should -Be 'GuestMismatch'

            $dup = $result | Where-Object UPN -eq 'dup@contoso.com'
            $dup[0].Status | Should -Be 'DuplicateEntry'
            $dup | Should -HaveCount 2

            $nomap = $result | Where-Object UPN -eq 'nomap@contoso.com'
            $nomap.Status | Should -Be 'Healthy'
        }
    }
}
