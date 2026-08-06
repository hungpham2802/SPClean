#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/LicenseManager.ps1')
    . (Join-Path $PSScriptRoot '../../Public/License/Get-SPCLicenseInfo.ps1')
    . (Join-Path $PSScriptRoot '../../Public/License/Register-SPCLicense.ps1')

    $script:TestUUID  = '6F0E4C97-B72A-4E69-A11B-F6C4AF6517E7'
    $script:TestEmail = 'test@contoso.com'

    function New-TestLicFile {
        param(
            [string]$Path,
            [string]$Tier    = 'PRO',
            [int]$AgeDays    = 0,
            [bool]$IsTesting = $false
        )
        $lastVerifiedAt = [datetime]::UtcNow.AddDays(-$AgeDays).ToString('o')
        @{
            licenseKey     = $script:TestUUID
            tier           = $Tier
            email          = $script:TestEmail
            isTesting      = $IsTesting
            registeredAt   = [datetime]::UtcNow.AddDays(-30).ToString('o')
            lastVerifiedAt = $lastVerifiedAt
            registeredTenant = 'contoso'
        } | ConvertTo-Json | Set-Content -Path $Path -Encoding UTF8
    }

    function New-ValidApiResponse {
        param(
            [string]$Tier      = 'PRO',
            [bool]$Refunded    = $false,
            [bool]$Testing     = $false
        )
        [PSCustomObject]@{
            success  = $true
            uses     = 1
            purchase = [PSCustomObject]@{
                email        = $script:TestEmail
                product_name = "SPClean $Tier"
                refunded     = $Refunded
                chargebacked = $false
                test         = $Testing
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Invoke-GumroadVerifyInternal
# ---------------------------------------------------------------------------
Describe 'Invoke-GumroadVerifyInternal' {

    It 'returns Success=true with email for a valid PRO key' {
        Mock Invoke-RestMethod { New-ValidApiResponse -Tier 'PRO' } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Invoke-GumroadVerifyInternal -LicenseKey $script:TestUUID -Tier 'PRO'
        $r.Success | Should -BeTrue
        $r.Email   | Should -Be $script:TestEmail
        $r.Tier    | Should -Be 'PRO'
    }

    It 'returns Success=false (not throw) on HTTP 404' {
        Mock Invoke-RestMethod {
            $msg = [System.Net.Http.HttpResponseMessage]::new(
                       [System.Net.HttpStatusCode]::NotFound)
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Not Found', $msg)
        } -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Invoke-GumroadVerifyInternal -LicenseKey $script:TestUUID -Tier 'PRO'
        $r.Success | Should -BeFalse
    }

    It 'throws ERR-LIC-NET-001 on network error' {
        Mock Invoke-RestMethod {
            throw [System.Net.Http.HttpRequestException]::new('Connection refused')
        } -ParameterFilter { $Uri -like '*gumroad*' }
        { Invoke-GumroadVerifyInternal -LicenseKey $script:TestUUID -Tier 'PRO' } |
            Should -Throw '*ERR-LIC-NET-001*'
    }

    It 'returns Refunded=true when purchase.refunded is true' {
        Mock Invoke-RestMethod { New-ValidApiResponse -Refunded $true } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Invoke-GumroadVerifyInternal -LicenseKey $script:TestUUID -Tier 'PRO'
        $r.Refunded | Should -BeTrue
    }

    It 'returns IsTesting=true for test purchases' {
        Mock Invoke-RestMethod { New-ValidApiResponse -Testing $true } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Invoke-GumroadVerifyInternal -LicenseKey $script:TestUUID -Tier 'PRO'
        $r.IsTesting | Should -BeTrue
    }

    It 'passes increment_uses_count=false when IncrementUses is false' {
        $script:capturedBody = $null
        Mock Invoke-RestMethod {
            $script:capturedBody = $Body
            New-ValidApiResponse
        } -ParameterFilter { $Uri -like '*gumroad*' }
        Invoke-GumroadVerifyInternal -LicenseKey $script:TestUUID -Tier 'PRO' -IncrementUses $false
        $script:capturedBody.increment_uses_count | Should -Be 'false'
    }
}

# ---------------------------------------------------------------------------
# Test-SPCLicenseKeyInternal
# ---------------------------------------------------------------------------
Describe 'Test-SPCLicenseKeyInternal' {

    It 'returns IsValid=false / MalformedFormat for non-UUID input' {
        $r = Test-SPCLicenseKeyInternal -LicenseKey 'not-a-uuid'
        $r.IsValid       | Should -BeFalse
        $r.FailureReason | Should -Be 'MalformedFormat'
    }

    It 'trims whitespace before UUID check' {
        Mock Invoke-RestMethod { New-ValidApiResponse } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Test-SPCLicenseKeyInternal -LicenseKey "  $script:TestUUID  "
        $r.IsValid | Should -BeTrue
    }

    It 'returns IsValid=true / Tier=PRO for a valid PRO UUID' {
        Mock Invoke-RestMethod { New-ValidApiResponse -Tier 'PRO' } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Test-SPCLicenseKeyInternal -LicenseKey $script:TestUUID
        $r.IsValid | Should -BeTrue
        $r.Tier    | Should -Be 'PRO'
    }

    It 'falls back to CONSULTANT when PRO returns 404' {
        $script:gumroadCallN = 0
        Mock Invoke-RestMethod {
            $script:gumroadCallN++
            if ($script:gumroadCallN -eq 1) {
                $msg = [System.Net.Http.HttpResponseMessage]::new(
                           [System.Net.HttpStatusCode]::NotFound)
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Not Found', $msg)
            }
            New-ValidApiResponse -Tier 'CONSULTANT'
        } -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Test-SPCLicenseKeyInternal -LicenseKey $script:TestUUID
        $r.IsValid | Should -BeTrue
        $r.Tier    | Should -Be 'CONSULTANT'
    }

    It 'returns InvalidKey when both tiers return 404' {
        Mock Invoke-RestMethod {
            $msg = [System.Net.Http.HttpResponseMessage]::new(
                       [System.Net.HttpStatusCode]::NotFound)
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Not Found', $msg)
        } -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Test-SPCLicenseKeyInternal -LicenseKey $script:TestUUID
        $r.IsValid       | Should -BeFalse
        $r.FailureReason | Should -Be 'InvalidKey'
    }

    It 'returns NetworkError when PRO call throws non-404' {
        Mock Invoke-RestMethod {
            throw [System.Net.Http.HttpRequestException]::new('timeout')
        } -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Test-SPCLicenseKeyInternal -LicenseKey $script:TestUUID
        $r.IsValid       | Should -BeFalse
        $r.FailureReason | Should -Be 'NetworkError'
    }

    It 'returns Refunded when key is valid but purchase is refunded' {
        Mock Invoke-RestMethod { New-ValidApiResponse -Refunded $true } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Test-SPCLicenseKeyInternal -LicenseKey $script:TestUUID
        $r.IsValid       | Should -BeFalse
        $r.FailureReason | Should -Be 'Refunded'
    }

    It 'propagates IsTesting=true from API response' {
        Mock Invoke-RestMethod { New-ValidApiResponse -Testing $true } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Test-SPCLicenseKeyInternal -LicenseKey $script:TestUUID
        $r.IsTesting | Should -BeTrue
    }
}

# ---------------------------------------------------------------------------
# Get-SPCLicenseInfo
# ---------------------------------------------------------------------------
Describe 'Get-SPCLicenseInfo' {

    BeforeEach {
        $script:SPCLicenseCache = $null
        $script:LicenseFilePath = Join-Path $TestDrive 'license.lic'
        Remove-Item -Path $script:LicenseFilePath -ErrorAction SilentlyContinue
    }

    It 'returns Status=Unlicensed when no license file exists' {
        $r = Get-SPCLicenseInfo
        $r.Status | Should -Be 'Unlicensed'
    }

    It 'returns Status=Active when fresh license file exists' {
        New-TestLicFile -Path $script:LicenseFilePath -AgeDays 0
        $r = Get-SPCLicenseInfo
        $r.Status | Should -Be 'Active'
        $r.Tier   | Should -Be 'PRO'
        $r.Email  | Should -Be $script:TestEmail
    }

    It 'returns SPC.LicenseInfo TypeName' {
        New-TestLicFile -Path $script:LicenseFilePath -AgeDays 0
        $r = Get-SPCLicenseInfo
        $r.PSObject.TypeNames | Should -Contain 'SPC.LicenseInfo'
    }

    It 'returns cached result on second call without re-reading disk' {
        New-TestLicFile -Path $script:LicenseFilePath -AgeDays 0
        $null = Get-SPCLicenseInfo
        Remove-Item $script:LicenseFilePath -Force
        $r = Get-SPCLicenseInfo
        $r.Status | Should -Be 'Active'
    }

    It 'returns Status=Invalid for malformed license file' {
        Set-Content -Path $script:LicenseFilePath -Value 'not-json' -Encoding UTF8
        $r = Get-SPCLicenseInfo
        $r.Status | Should -Be 'Invalid'
    }

    It 'returns Status=Invalid when required fields are missing' {
        '{"licenseKey":"abc"}' | Set-Content -Path $script:LicenseFilePath -Encoding UTF8
        $r = Get-SPCLicenseInfo
        $r.Status | Should -Be 'Invalid'
    }

    It 're-verifies via Gumroad when cache is >= 7 days old and returns Active' {
        New-TestLicFile -Path $script:LicenseFilePath -AgeDays 8
        Mock Invoke-RestMethod { New-ValidApiResponse } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Get-SPCLicenseInfo
        $r.Status | Should -Be 'Active'
    }

    It 'returns Status=Revoked when re-verify returns refunded=true' {
        New-TestLicFile -Path $script:LicenseFilePath -AgeDays 8
        Mock Invoke-RestMethod { New-ValidApiResponse -Refunded $true } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Get-SPCLicenseInfo
        $r.Status | Should -Be 'Revoked'
        (Test-Path $script:LicenseFilePath) | Should -BeFalse
    }

    It 'does not throw when re-verify fails (offline grace)' {
        New-TestLicFile -Path $script:LicenseFilePath -AgeDays 8
        Mock Invoke-RestMethod {
            throw [System.Net.Http.HttpRequestException]::new('offline')
        } -ParameterFilter { $Uri -like '*gumroad*' }
        { Get-SPCLicenseInfo } | Should -Not -Throw
    }

    It 'returns Active with offline grace when re-verify fails' {
        New-TestLicFile -Path $script:LicenseFilePath -AgeDays 8
        Mock Invoke-RestMethod {
            throw [System.Net.Http.HttpRequestException]::new('offline')
        } -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Get-SPCLicenseInfo
        $r.Status | Should -Be 'Active'
    }

    It 'returns IsTesting=true when license file has isTesting=true' {
        New-TestLicFile -Path $script:LicenseFilePath -AgeDays 0 -IsTesting $true
        $r = Get-SPCLicenseInfo
        $r.IsTesting | Should -BeTrue
    }

    It 'never throws — returns non-Active for nonexistent directory' {
        $script:LicenseFilePath = Join-Path $TestDrive 'nonexistent\license.lic'
        { Get-SPCLicenseInfo } | Should -Not -Throw
    }
}

# ---------------------------------------------------------------------------
# Register-SPCLicense
# ---------------------------------------------------------------------------
Describe 'Register-SPCLicense' {

    BeforeEach {
        $script:SPCLicenseCache = $null
        $script:LicenseFilePath = Join-Path $TestDrive 'license.lic'
        Remove-Item -Path $script:LicenseFilePath -ErrorAction SilentlyContinue
        $script:SPCContext = [PSCustomObject]@{ TenantName = 'contoso' }
    }

    It 'writes license.lic and returns SPC.LicenseInfo on success' {
        Mock Invoke-RestMethod { New-ValidApiResponse -Tier 'PRO' } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Register-SPCLicense -LicenseKey $script:TestUUID -Confirm:$false
        $r.Status              | Should -Be 'Active'
        $r.Tier                | Should -Be 'PRO'
        $r.PSObject.TypeNames  | Should -Contain 'SPC.LicenseInfo'
        (Test-Path $script:LicenseFilePath) | Should -BeTrue
    }

    It 'license.lic contains expected fields' {
        Mock Invoke-RestMethod { New-ValidApiResponse -Tier 'PRO' } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        Register-SPCLicense -LicenseKey $script:TestUUID -Confirm:$false
        $data = Get-Content $script:LicenseFilePath -Raw | ConvertFrom-Json
        $data.licenseKey     | Should -Be $script:TestUUID
        $data.tier           | Should -Be 'PRO'
        $data.email          | Should -Be $script:TestEmail
        $data.lastVerifiedAt | Should -Not -BeNullOrEmpty
        $data.registeredAt   | Should -Not -BeNullOrEmpty
    }

    It 'throws ERR-LIC-001 for an invalid key (404 from API)' {
        Mock Invoke-RestMethod {
            $msg = [System.Net.Http.HttpResponseMessage]::new(
                       [System.Net.HttpStatusCode]::NotFound)
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Not Found', $msg)
        } -ParameterFilter { $Uri -like '*gumroad*' }
        { Register-SPCLicense -LicenseKey $script:TestUUID -Confirm:$false } |
            Should -Throw '*ERR-LIC-001*'
    }

    It 'throws ERR-LIC-001 for a malformed (non-UUID) key' {
        { Register-SPCLicense -LicenseKey 'bad-key' -Confirm:$false } |
            Should -Throw '*ERR-LIC-001*'
    }

    It 'throws ERR-LIC-NET-001 on network error' {
        Mock Invoke-RestMethod {
            throw [System.Net.Http.HttpRequestException]::new('no network')
        } -ParameterFilter { $Uri -like '*gumroad*' }
        { Register-SPCLicense -LicenseKey $script:TestUUID -Confirm:$false } |
            Should -Throw '*ERR-LIC-NET-001*'
    }

    It 'overwrites existing license when -Force is specified' {
        New-TestLicFile -Path $script:LicenseFilePath -Tier 'PRO' -AgeDays 0
        Mock Invoke-RestMethod { New-ValidApiResponse -Tier 'PRO' } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        $r = Register-SPCLicense -LicenseKey $script:TestUUID -Force -Confirm:$false
        $r.Status | Should -Be 'Active'
        (Test-Path $script:LicenseFilePath) | Should -BeTrue
    }

    It 'clears SPCLicenseCache after registration' {
        $script:SPCLicenseCache = [PSCustomObject]@{ Status = 'Active' }
        Mock Invoke-RestMethod { New-ValidApiResponse } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        Register-SPCLicense -LicenseKey $script:TestUUID -Confirm:$false
        $script:SPCLicenseCache | Should -BeNullOrEmpty
    }

    It 'emits warning for test purchase' {
        Mock Invoke-RestMethod { New-ValidApiResponse -Testing $true } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        Register-SPCLicense -LicenseKey $script:TestUUID -Confirm:$false `
            -WarningVariable warnVar -WarningAction SilentlyContinue
        $warnVar            | Should -Not -BeNullOrEmpty
        $warnVar[0].Message | Should -BeLike '*Test purchase*'
    }

    It 'AC-12: license key does not appear in any output stream' {
        Mock Invoke-RestMethod { New-ValidApiResponse } `
            -ParameterFilter { $Uri -like '*gumroad*' }
        $allOutput = Register-SPCLicense -LicenseKey $script:TestUUID -Confirm:$false `
            -Verbose -WarningVariable w -InformationVariable i 4>&1 5>&1 6>&1
        $allOutput | ForEach-Object { "$_" | Should -Not -BeLike "*$script:TestUUID*" }
        $w         | ForEach-Object { "$_" | Should -Not -BeLike "*$script:TestUUID*" }
        $i         | ForEach-Object { "$_" | Should -Not -BeLike "*$script:TestUUID*" }
    }
}

# ---------------------------------------------------------------------------
# Assert-SPCProLicense
# ---------------------------------------------------------------------------
Describe 'Assert-SPCProLicense' {

    BeforeEach {
        $script:SPCLicenseCache = $null
        $script:LicenseFilePath = Join-Path $TestDrive 'license.lic'
        Remove-Item -Path $script:LicenseFilePath -ErrorAction SilentlyContinue
        $script:SPCContext = [PSCustomObject]@{ TenantName = 'contoso' }
    }

    It 'does not throw when Status=Active Tier=PRO' {
        New-TestLicFile -Path $script:LicenseFilePath -Tier 'PRO' -AgeDays 0
        { Assert-SPCProLicense -Feature 'TestFeature' } | Should -Not -Throw
    }

    It 'does not throw when Status=Active Tier=CONSULTANT' {
        New-TestLicFile -Path $script:LicenseFilePath -Tier 'CONSULTANT' -AgeDays 0
        { Assert-SPCProLicense -Feature 'TestFeature' } | Should -Not -Throw
    }

    It 'throws ERR-LIC-003 when unlicensed' {
        { Assert-SPCProLicense -Feature 'TestFeature' } |
            Should -Throw '*ERR-LIC-003*'
    }

    It 'throws ERR-LIC-003 when Status=Invalid' {
        Set-Content -Path $script:LicenseFilePath -Value 'bad' -Encoding UTF8
        { Assert-SPCProLicense -Feature 'TestFeature' } |
            Should -Throw '*ERR-LIC-003*'
    }
}

# ---------------------------------------------------------------------------
# Assert-SPCConsultantLicense
# ---------------------------------------------------------------------------
Describe 'Assert-SPCConsultantLicense' {

    BeforeEach {
        $script:SPCLicenseCache = $null
        $script:LicenseFilePath = Join-Path $TestDrive 'license.lic'
        Remove-Item -Path $script:LicenseFilePath -ErrorAction SilentlyContinue
        $script:SPCContext = [PSCustomObject]@{ TenantName = 'contoso' }
    }

    It 'does not throw when Status=Active Tier=CONSULTANT' {
        New-TestLicFile -Path $script:LicenseFilePath -Tier 'CONSULTANT' -AgeDays 0
        { Assert-SPCConsultantLicense -Feature 'TestFeature' } | Should -Not -Throw
    }

    It 'throws ERR-LIC-004 when Tier=PRO' {
        New-TestLicFile -Path $script:LicenseFilePath -Tier 'PRO' -AgeDays 0
        { Assert-SPCConsultantLicense -Feature 'TestFeature' } |
            Should -Throw '*ERR-LIC-004*'
    }

    It 'throws ERR-LIC-004 when unlicensed' {
        { Assert-SPCConsultantLicense -Feature 'TestFeature' } |
            Should -Throw '*ERR-LIC-004*'
    }
}

# ---------------------------------------------------------------------------
# Feature Gate Integration
# ---------------------------------------------------------------------------
Describe 'Feature Gate Integration' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
        . (Join-Path $PSScriptRoot '../../Public/Report/Export-SPCReport.ps1')
        . (Join-Path $PSScriptRoot '../../Public/Schedule/New-SPCScanSchedule.ps1')
        . (Join-Path $PSScriptRoot '../../Public/Remediate/Remove-SPCOrphanedUser.ps1')
        . (Join-Path $PSScriptRoot '../../Public/Remediate/Restore-SPCOrphanedUser.ps1')
    }

    BeforeEach {
        $script:SPCLicenseCache = $null
        $script:LicenseFilePath = Join-Path $TestDrive 'license.lic'
        Remove-Item -Path $script:LicenseFilePath -ErrorAction SilentlyContinue
        Mock Test-SPCConnection {}
        Mock Get-PnPAccessToken { return 'fake' }
        Mock Connect-PnPOnline {}
        Mock Disconnect-PnPOnline {}
    }

    It 'Export-SPCReport HTML requires Pro — throws ERR-LIC-003 when unlicensed' {
        $fakeItem = [PSCustomObject]@{ LoginName = 'user@contoso.com'; SiteUrl = 'https://x.sharepoint.com' }
        {
            Export-SPCReport -InputObject $fakeItem -Format HTML `
                -OutputPath (Join-Path $TestDrive 'report.html')
        } | Should -Throw '*ERR-LIC-003*'
    }

    It 'New-SPCScanSchedule requires Pro — throws ERR-LIC-003 when unlicensed' {
        $secPwd = ConvertTo-SecureString 'x' -AsPlainText -Force
        {
            New-SPCScanSchedule -TenantName 'contoso' -ClientId 'abc' `
                -CertificatePath 'C:\fake.pfx' `
                -CertificatePassword $secPwd `
                -Schedule Daily `
                -ReportOutputPath (Join-Path $TestDrive 'reports') `
                -Confirm:$false
        } | Should -Throw '*ERR-LIC-003*'
    }

    It 'Remove-SPCOrphanedUser -CreateSnapshot requires Pro — throws ERR-LIC-003 when unlicensed' {
        $fakeUser = [PSCustomObject]@{
            LoginName   = 'i:0#.f|membership|user@contoso.com'
            SiteUrl     = 'https://contoso.sharepoint.com/sites/test'
            DisplayName = 'Test User'
        }
        $fakeUser.PSObject.TypeNames.Insert(0, 'SPC.OrphanedUser')
        {
            Remove-SPCOrphanedUser -InputObject $fakeUser -CreateSnapshot -Confirm:$false
        } | Should -Throw '*ERR-LIC-003*'
    }

    It 'Restore-SPCOrphanedUser requires Pro — throws ERR-LIC-003 when unlicensed' {
        {
            Restore-SPCOrphanedUser -SnapshotPath (Join-Path $TestDrive 'snap.json') -Confirm:$false
        } | Should -Throw '*ERR-LIC-003*'
    }
}
