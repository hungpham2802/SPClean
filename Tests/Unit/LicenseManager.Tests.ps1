#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    # Dot-source in dependency order — Private first, then Public
    . (Join-Path $PSScriptRoot '../../Private/LicenseManager.ps1')
    . (Join-Path $PSScriptRoot '../../Public/License/Get-SPCLicenseInfo.ps1')
    . (Join-Path $PSScriptRoot '../../Public/License/Register-SPCLicense.ps1')

    # Fixed test secret — 32 bytes [1..32]
    $script:TestSecret = [byte[]]@(1..32)

    # Helper: build a valid signed license key using the test secret
    function New-TestLicenseKey {
        param(
            [string] $Tier          = 'PRO',
            [string] $Email         = 'test@contoso.com',
            [int]    $ExpiryOffset  = 365,
            [string] $LicenseId     = 'test1234',
            [byte[]] $SecretBytes   = ([byte[]]@(1..32))
        )
        $expiry   = [datetime]::UtcNow.AddDays($ExpiryOffset).ToString('o')
        $issuedAt = [datetime]::UtcNow.ToString('o')
        $payload  = [ordered]@{
            tier      = $Tier
            expiry    = $expiry
            licenseId = $LicenseId
            email     = $Email
            issuedAt  = $issuedAt
        } | ConvertTo-Json -Compress

        $payloadB64 = [System.Convert]::ToBase64String(
            [System.Text.Encoding]::UTF8.GetBytes($payload)
        ).Replace('+', '-').Replace('/', '_').TrimEnd('=')

        $hmac   = [System.Security.Cryptography.HMACSHA256]::new($SecretBytes)
        $sigRaw = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payloadB64))
        $hmac.Dispose()
        $sigB64 = [System.Convert]::ToBase64String($sigRaw).Replace('+', '-').Replace('/', '_').TrimEnd('=')

        "SPCLEAN-$Tier-$payloadB64-$sigB64"
    }
}

# ════════════════════════════════════════════════════════════════════════════
Describe 'Test-SPCLicenseKey' {

    Context 'Valid PRO key' {
        It 'AC-LIC-01: returns IsValid=true for a valid PRO key' {
            $key    = New-TestLicenseKey -Tier 'PRO'
            $result = Test-SPCLicenseKey -LicenseKey $key -SecretKeyBytes $script:TestSecret
            $result.IsValid | Should -BeTrue
        }
        It 'AC-LIC-01: Tier field is PRO' {
            $key    = New-TestLicenseKey -Tier 'PRO'
            $result = Test-SPCLicenseKey -LicenseKey $key -SecretKeyBytes $script:TestSecret
            $result.Tier | Should -Be 'PRO'
        }
        It 'AC-LIC-01: Email field is populated' {
            $key    = New-TestLicenseKey -Tier 'PRO' -Email 'alice@contoso.com'
            $result = Test-SPCLicenseKey -LicenseKey $key -SecretKeyBytes $script:TestSecret
            $result.Email | Should -Be 'alice@contoso.com'
        }
        It 'AC-LIC-01: LicenseId field is populated' {
            $key    = New-TestLicenseKey -Tier 'PRO' -LicenseId 'abc12345'
            $result = Test-SPCLicenseKey -LicenseKey $key -SecretKeyBytes $script:TestSecret
            $result.LicenseId | Should -Be 'abc12345'
        }
        It 'AC-LIC-01: ExpiresAt is in the future' {
            $key    = New-TestLicenseKey -Tier 'PRO' -ExpiryOffset 365
            $result = Test-SPCLicenseKey -LicenseKey $key -SecretKeyBytes $script:TestSecret
            $result.ExpiresAt | Should -BeGreaterThan ([datetime]::UtcNow)
        }
        It 'returns TypeName SPC.LicenseValidation' {
            $key    = New-TestLicenseKey
            $result = Test-SPCLicenseKey -LicenseKey $key -SecretKeyBytes $script:TestSecret
            $result.PSObject.TypeNames | Should -Contain 'SPC.LicenseValidation'
        }
        It 'tolerates leading/trailing whitespace in key' {
            $key    = "  $(New-TestLicenseKey -Tier 'PRO')  "
            $result = Test-SPCLicenseKey -LicenseKey $key -SecretKeyBytes $script:TestSecret
            $result.IsValid | Should -BeTrue
        }
    }

    Context 'Valid CONSULTANT key' {
        It 'returns IsValid=true for CONSULTANT tier' {
            $key    = New-TestLicenseKey -Tier 'CONSULTANT'
            $result = Test-SPCLicenseKey -LicenseKey $key -SecretKeyBytes $script:TestSecret
            $result.IsValid | Should -BeTrue
            $result.Tier | Should -Be 'CONSULTANT'
        }
    }

    Context 'AC-LIC-04: Tampered signature' {
        It 'AC-LIC-04: returns SignatureMismatch when last chars are changed' {
            $key      = New-TestLicenseKey -Tier 'PRO'
            $tampered = $key.Substring(0, $key.Length - 3) + 'AAA'
            $result   = Test-SPCLicenseKey -LicenseKey $tampered -SecretKeyBytes $script:TestSecret
            $result.IsValid       | Should -BeFalse
            $result.FailureReason | Should -Be 'SignatureMismatch'
        }
        It 'AC-LIC-04: returns SignatureMismatch when payload is changed' {
            $key   = New-TestLicenseKey -Tier 'PRO'
            $parts = $key -split '-', 3
            # Flip a char in the middle of the payload
            $payload = $parts[2].Substring(0, 10) + 'X' + $parts[2].Substring(11)
            $tampered = "SPCLEAN-PRO-$payload"
            $result   = Test-SPCLicenseKey -LicenseKey $tampered -SecretKeyBytes $script:TestSecret
            $result.IsValid       | Should -BeFalse
            $result.FailureReason | Should -BeIn @('SignatureMismatch', 'MalformedFormat', 'Base64DecodeFailure')
        }
    }

    Context 'AC-LIC-05: Expired key' {
        It 'AC-LIC-05: returns Expired for a key expiring yesterday' {
            $key    = New-TestLicenseKey -ExpiryOffset -1
            $result = Test-SPCLicenseKey -LicenseKey $key -SecretKeyBytes $script:TestSecret
            $result.IsValid       | Should -BeFalse
            $result.FailureReason | Should -Be 'Expired'
        }
    }

    Context 'AC-LIC-06: Malformed format' {
        It 'AC-LIC-06: returns MalformedFormat for plain string' {
            $result = Test-SPCLicenseKey -LicenseKey 'NOTAKEY' -SecretKeyBytes $script:TestSecret
            $result.IsValid       | Should -BeFalse
            $result.FailureReason | Should -Be 'MalformedFormat'
        }
        It 'returns MalformedFormat for wrong prefix' {
            $result = Test-SPCLicenseKey -LicenseKey 'WRONGPFX-PRO-payload-sig' -SecretKeyBytes $script:TestSecret
            $result.IsValid       | Should -BeFalse
            $result.FailureReason | Should -Be 'MalformedFormat'
        }
        It 'returns MalformedFormat for two-part key' {
            $result = Test-SPCLicenseKey -LicenseKey 'SPCLEAN-PRO' -SecretKeyBytes $script:TestSecret
            $result.IsValid       | Should -BeFalse
            $result.FailureReason | Should -Be 'MalformedFormat'
        }
    }

    Context 'Invalid tier' {
        It 'returns InvalidTier for FREE tier' {
            $result = Test-SPCLicenseKey -LicenseKey 'SPCLEAN-FREE-payload-sig' -SecretKeyBytes $script:TestSecret
            $result.IsValid       | Should -BeFalse
            $result.FailureReason | Should -Be 'InvalidTier'
        }
        It 'returns InvalidTier for unknown tier' {
            $result = Test-SPCLicenseKey -LicenseKey 'SPCLEAN-ENTERPRISE-payload-sig' -SecretKeyBytes $script:TestSecret
            $result.IsValid       | Should -BeFalse
            $result.FailureReason | Should -Be 'InvalidTier'
        }
    }

    Context 'Base64URL edge cases' {
        It 'handles key with no padding (length mod 4 = 0)' {
            # Any valid key from New-TestLicenseKey exercises this path
            $key    = New-TestLicenseKey
            $result = Test-SPCLicenseKey -LicenseKey $key -SecretKeyBytes $script:TestSecret
            $result.IsValid | Should -BeTrue
        }
    }

    Context 'Constant-time compare helper' {
        It 'returns true for identical arrays' {
            Compare-ByteArrayConstantTimeInternal -A @(1, 2, 3) -B @(1, 2, 3) | Should -BeTrue
        }
        It 'returns false for different arrays of same length' {
            Compare-ByteArrayConstantTimeInternal -A @(1, 2, 3) -B @(1, 2, 4) | Should -BeFalse
        }
        It 'returns false for arrays of different lengths' {
            Compare-ByteArrayConstantTimeInternal -A @(1, 2) -B @(1, 2, 3) | Should -BeFalse
        }
    }
}

# ════════════════════════════════════════════════════════════════════════════
Describe 'Get-SPCLicenseInfo' {

    BeforeEach {
        # Ensure fresh state for each test
        $script:SPCLicenseCache = $null
    }

    Context 'No license file' {
        It 'AC-LIC-02 pre: returns Unlicensed when no file exists' {
            Mock Test-Path -ParameterFilter { $Path -like '*SPClean*license.lic' } { $false }
            $result = Get-SPCLicenseInfo
            $result.Status | Should -Be 'Unlicensed'
        }
        It 'returns Tier=FREE when unlicensed' {
            Mock Test-Path -ParameterFilter { $Path -like '*SPClean*license.lic' } { $false }
            $result = Get-SPCLicenseInfo
            $result.Tier | Should -Be 'FREE'
        }
        It 'never throws when no file exists' {
            Mock Test-Path -ParameterFilter { $Path -like '*SPClean*license.lic' } { $false }
            { Get-SPCLicenseInfo } | Should -Not -Throw
        }
    }

    Context 'Valid license on disk' {
        It 'returns Active when license.lic contains a valid key' {
            $key     = New-TestLicenseKey -Tier 'PRO'
            $licJson = [ordered]@{
                licenseKey   = $key
                tier         = 'PRO'
                email        = 'test@contoso.com'
                licenseId    = 'test1234'
                expiresAt    = [datetime]::UtcNow.AddDays(365).ToString('o')
                issuedAt     = [datetime]::UtcNow.ToString('o')
                registeredAt = [datetime]::UtcNow.ToString('o')
            } | ConvertTo-Json -Compress

            Mock Test-Path    -ParameterFilter { $Path -like '*SPClean*license.lic' } { $true }
            Mock Get-Content  -ParameterFilter { $Path -like '*SPClean*license.lic' } { $licJson }
            Mock Get-SPCSecretKeyBytesInternal { return [byte[]]@(1..32) }

            $result = Get-SPCLicenseInfo
            $result.Status | Should -Be 'Active'
            $result.Tier   | Should -Be 'PRO'
        }
    }

    Context 'AC-LIC-03: Cache behavior' {
        It 'AC-LIC-03: returns from cache on second call without disk read' {
            $key     = New-TestLicenseKey -Tier 'PRO'
            $licJson = [ordered]@{
                licenseKey   = $key
                tier         = 'PRO'
                email        = 'test@contoso.com'
                licenseId    = 'test1234'
                expiresAt    = [datetime]::UtcNow.AddDays(365).ToString('o')
                issuedAt     = [datetime]::UtcNow.ToString('o')
                registeredAt = [datetime]::UtcNow.ToString('o')
            } | ConvertTo-Json -Compress

            Mock Test-Path    -ParameterFilter { $Path -like '*SPClean*license.lic' } { $true }
            Mock Get-Content  -ParameterFilter { $Path -like '*SPClean*license.lic' } { $licJson }
            Mock Get-SPCSecretKeyBytesInternal { return [byte[]]@(1..32) }

            $null = Get-SPCLicenseInfo  # prime cache
            $null = Get-SPCLicenseInfo  # should use cache

            # Get-Content should have been called exactly once (disk read happened once)
            Should -Invoke Get-Content -Exactly 1 -ParameterFilter { $Path -like '*SPClean*license.lic' }
        }
        It 'cache is cleared when SPCLicenseCache is set to null' {
            $script:SPCLicenseCache = $null
            Mock Test-Path   -ParameterFilter { $Path -like '*SPClean*license.lic' } { $false }
            $result = Get-SPCLicenseInfo
            $result.Status | Should -Be 'Unlicensed'
        }
    }

    Context 'AC-LIC-13: Corrupted license.lic' {
        It 'AC-LIC-13: returns Invalid status — does not throw' {
            Mock Test-Path   -ParameterFilter { $Path -like '*SPClean*license.lic' } { $true }
            Mock Get-Content -ParameterFilter { $Path -like '*SPClean*license.lic' } { 'not valid json {{' }
            $result = Get-SPCLicenseInfo
            $result.Status | Should -Be 'Invalid'
        }
        It 'AC-LIC-13: returns Invalid when licenseKey field is missing' {
            Mock Test-Path   -ParameterFilter { $Path -like '*SPClean*license.lic' } { $true }
            Mock Get-Content -ParameterFilter { $Path -like '*SPClean*license.lic' } { '{"tier":"PRO"}' }
            $result = Get-SPCLicenseInfo
            $result.Status | Should -Be 'Invalid'
        }
    }

    Context 'Expired license on disk' {
        It 'returns Expired when key is past expiry' {
            $key     = New-TestLicenseKey -Tier 'PRO' -ExpiryOffset -1
            $licJson = [ordered]@{
                licenseKey   = $key
                tier         = 'PRO'
                email        = 'test@contoso.com'
                licenseId    = 'test1234'
                expiresAt    = [datetime]::UtcNow.AddDays(-1).ToString('o')
                issuedAt     = [datetime]::UtcNow.AddDays(-366).ToString('o')
                registeredAt = [datetime]::UtcNow.AddDays(-366).ToString('o')
            } | ConvertTo-Json -Compress

            Mock Test-Path    -ParameterFilter { $Path -like '*SPClean*license.lic' } { $true }
            Mock Get-Content  -ParameterFilter { $Path -like '*SPClean*license.lic' } { $licJson }
            Mock Get-SPCSecretKeyBytesInternal { return [byte[]]@(1..32) }

            $result = Get-SPCLicenseInfo
            $result.Status | Should -Be 'Expired'
        }
    }

    Context 'TypeName' {
        It 'returns SPC.LicenseInfo TypeName' {
            Mock Test-Path -ParameterFilter { $Path -like '*SPClean*license.lic' } { $false }
            $result = Get-SPCLicenseInfo
            $result.PSObject.TypeNames | Should -Contain 'SPC.LicenseInfo'
        }
    }
}

# ════════════════════════════════════════════════════════════════════════════
Describe 'Assert-SPCProLicense' {

    BeforeEach { $script:SPCLicenseCache = $null }

    Context 'Active PRO license' {
        It 'does not throw with Status=Active Tier=PRO' {
            Mock Get-SPCLicenseInfo {
                $r = [PSCustomObject]@{ Status = 'Active'; Tier = 'PRO' }
                $r
            }
            { Assert-SPCProLicense -Feature 'TestFeature' } | Should -Not -Throw
        }
    }

    Context 'Active CONSULTANT license' {
        It 'does not throw with Status=Active Tier=CONSULTANT' {
            Mock Get-SPCLicenseInfo {
                $r = [PSCustomObject]@{ Status = 'Active'; Tier = 'CONSULTANT' }
                $r
            }
            { Assert-SPCProLicense -Feature 'TestFeature' } | Should -Not -Throw
        }
    }

    Context 'No license' {
        It 'AC-LIC-07: throws ERR-LIC-003 when unlicensed' {
            Mock Get-SPCLicenseInfo {
                $r = [PSCustomObject]@{ Status = 'Unlicensed'; Tier = 'FREE' }
                $r
            }
            { Assert-SPCProLicense -Feature 'HTMLReport' } | Should -Throw '*ERR-LIC-003*'
        }
    }

    Context 'Expired license' {
        It 'throws ERR-LIC-003 when expired' {
            Mock Get-SPCLicenseInfo {
                $r = [PSCustomObject]@{ Status = 'Expired'; Tier = 'PRO' }
                $r
            }
            { Assert-SPCProLicense -Feature 'ScheduledScan' } | Should -Throw '*ERR-LIC-003*'
        }
    }
}

# ════════════════════════════════════════════════════════════════════════════
Describe 'Assert-SPCConsultantLicense' {

    BeforeEach { $script:SPCLicenseCache = $null }

    Context 'Active CONSULTANT license' {
        It 'does not throw with Status=Active Tier=CONSULTANT' {
            Mock Get-SPCLicenseInfo {
                [PSCustomObject]@{ Status = 'Active'; Tier = 'CONSULTANT' }
            }
            { Assert-SPCConsultantLicense -Feature 'WhiteLabelReport' } | Should -Not -Throw
        }
    }

    Context 'PRO license is insufficient' {
        It 'throws ERR-LIC-004 when Tier=PRO (not Consultant)' {
            Mock Get-SPCLicenseInfo {
                [PSCustomObject]@{ Status = 'Active'; Tier = 'PRO' }
            }
            { Assert-SPCConsultantLicense -Feature 'WhiteLabelReport' } | Should -Throw '*ERR-LIC-004*'
        }
    }

    Context 'No license' {
        It 'throws ERR-LIC-004 when unlicensed' {
            Mock Get-SPCLicenseInfo {
                [PSCustomObject]@{ Status = 'Unlicensed'; Tier = 'FREE' }
            }
            { Assert-SPCConsultantLicense -Feature 'WhiteLabelReport' } | Should -Throw '*ERR-LIC-004*'
        }
    }
}

# ════════════════════════════════════════════════════════════════════════════
Describe 'Register-SPCLicense' {

    BeforeEach { $script:SPCLicenseCache = $null }

    Context 'Valid key registration' {
        It 'AC-LIC-02: returns SPC.LicenseInfo with Status=Active' {
            $key = New-TestLicenseKey -Tier 'PRO'

            Mock Get-SPCSecretKeyBytesInternal { return [byte[]]@(1..32) }
            Mock Get-SPCLicensePathInternal    { return (Join-Path $TestDrive 'license.lic') }
            Mock Test-Path    -ParameterFilter { $Path -like (Join-Path $TestDrive '*') } { $false }

            $result = Register-SPCLicense -LicenseKey $key -Force
            $result.Status | Should -Be 'Active'
            $result.Tier   | Should -Be 'PRO'
        }
        It 'AC-LIC-02: writes license.lic to disk' {
            $key     = New-TestLicenseKey -Tier 'PRO'
            $licPath = Join-Path $TestDrive 'license.lic'

            Mock Get-SPCSecretKeyBytesInternal { return [byte[]]@(1..32) }
            Mock Get-SPCLicensePathInternal    { return $licPath }

            Register-SPCLicense -LicenseKey $key -Force | Out-Null
            Test-Path $licPath | Should -BeTrue
        }
        It 'AC-LIC-02: license.lic contains valid JSON' {
            $key     = New-TestLicenseKey -Tier 'PRO'
            $licPath = Join-Path $TestDrive 'license.lic'

            Mock Get-SPCSecretKeyBytesInternal { return [byte[]]@(1..32) }
            Mock Get-SPCLicensePathInternal    { return $licPath }

            Register-SPCLicense -LicenseKey $key -Force | Out-Null
            $json = Get-Content $licPath -Raw
            { $json | ConvertFrom-Json } | Should -Not -Throw
        }
        It 'clears SPCLicenseCache after registration' {
            $key = New-TestLicenseKey -Tier 'PRO'
            $script:SPCLicenseCache = [PSCustomObject]@{ Status = 'Active' }

            Mock Get-SPCSecretKeyBytesInternal { return [byte[]]@(1..32) }
            Mock Get-SPCLicensePathInternal    { return (Join-Path $TestDrive 'lic2.lic') }

            Register-SPCLicense -LicenseKey $key -Force | Out-Null
            $script:SPCLicenseCache | Should -BeNullOrEmpty
        }
    }

    Context 'AC-LIC-04: Invalid key' {
        It 'AC-LIC-04: throws ERR-LIC-001 for tampered key' {
            $key      = New-TestLicenseKey -Tier 'PRO'
            $tampered = $key.Substring(0, $key.Length - 3) + 'AAA'
            Mock Get-SPCSecretKeyBytesInternal { return [byte[]]@(1..32) }
            { Register-SPCLicense -LicenseKey $tampered -Force } | Should -Throw '*ERR-LIC-001*'
        }
        It 'AC-LIC-06: throws ERR-LIC-001 for malformed string' {
            Mock Get-SPCSecretKeyBytesInternal { return [byte[]]@(1..32) }
            { Register-SPCLicense -LicenseKey 'NOTAKEY' -Force } | Should -Throw '*ERR-LIC-001*'
        }
        It 'AC-LIC-05: throws ERR-LIC-001 for expired key' {
            $key = New-TestLicenseKey -ExpiryOffset -1
            Mock Get-SPCSecretKeyBytesInternal { return [byte[]]@(1..32) }
            { Register-SPCLicense -LicenseKey $key -Force } | Should -Throw '*ERR-LIC-001*'
        }
    }

    Context 'AC-LIC-14: License key not in output streams' {
        It 'AC-LIC-14: license key string does not appear in verbose stream' {
            $key     = New-TestLicenseKey -Tier 'PRO'
            $licPath = Join-Path $TestDrive 'lic_stream_test.lic'

            Mock Get-SPCSecretKeyBytesInternal { return [byte[]]@(1..32) }
            Mock Get-SPCLicensePathInternal    { return $licPath }

            $verboseOut = & {
                Register-SPCLicense -LicenseKey $key -Force -Verbose 4>&1
            } 2>&1

            $verboseOut | ForEach-Object { [string]$_ } | Should -Not -Match 'SPCLEAN-(PRO|CONSULTANT)-'
        }
    }
}

# ════════════════════════════════════════════════════════════════════════════
Describe 'Feature Gate Integration' {

    BeforeEach { $script:SPCLicenseCache = $null }

    Context 'AC-LIC-07: Export-SPCReport HTML gate' {
        BeforeAll {
            . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
            . (Join-Path $PSScriptRoot '../../Public/Report/Export-SPCReport.ps1')
            $script:SPCContext = [PSCustomObject]@{
                TenantName = 'test'; AuthMethod = 'Interactive'
                ConnectedAt = [datetime]::UtcNow; PnPContext = $null
                GraphAccessToken = 'fake'; _ClientId = $null
                _CertificatePath = $null; _CertificatePassword = $null; _ClientSecret = $null
            }
            $script:FakeLicOrphan = [PSCustomObject][ordered]@{
                SiteUrl = 'https://test.sharepoint.com'; SiteTitle = 'Test'; UserId = 1
                LoginName = 'i:0#.f|membership|test@test.com'; DisplayName = 'Test'; Email = 'test@test.com'
                UPN = 'test@test.com'; OrphanType = 'Deleted'; RiskLevel = 'HIGH'
                HasDirectPermissions = $false; GroupMemberships = @(); LastActivityDate = $null
                DetectedAt = [datetime]::UtcNow
            }
            $script:FakeLicOrphan.PSObject.TypeNames.Insert(0, 'SPC.OrphanedUser')
        }

        It 'AC-LIC-07: throws ERR-LIC-003 for HTML without license' {
            Mock Get-SPCLicenseInfo { [PSCustomObject]@{ Status = 'Unlicensed'; Tier = 'FREE' } }
            {
                @($script:FakeLicOrphan) | Export-SPCReport -Format HTML -OutputPath (Join-Path $TestDrive 'test.html')
            } | Should -Throw '*ERR-LIC-003*'
        }

        It 'AC-LIC-09: CSV export works without license' {
            Mock Get-SPCLicenseInfo { [PSCustomObject]@{ Status = 'Unlicensed'; Tier = 'FREE' } }
            $path = Join-Path $TestDrive 'test.csv'
            { @($script:FakeLicOrphan) | Export-SPCReport -Format CSV -OutputPath $path } | Should -Not -Throw
            Test-Path $path | Should -BeTrue
        }
    }

    Context 'AC-LIC-10 / AC-LIC-11: Remove-SPCOrphanedUser snapshot gate' {
        BeforeAll {
            . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
            . (Join-Path $PSScriptRoot '../../Private/Save-SPCPermissionSnapshot.ps1')
            . (Join-Path $PSScriptRoot '../../Public/Remediate/Remove-SPCOrphanedUser.ps1')
            $script:SPCContext = [PSCustomObject]@{
                TenantName = 'test'; AuthMethod = 'Interactive'
                ConnectedAt = [datetime]::UtcNow; PnPContext = $null
                GraphAccessToken = 'fake'; _ClientId = $null
                _CertificatePath = $null; _CertificatePassword = $null; _ClientSecret = $null
            }
            $script:FakeRemoveOrphan = [PSCustomObject][ordered]@{
                SiteUrl = 'https://test.sharepoint.com/sites/HR'; SiteTitle = 'HR'
                UserId = 1; LoginName = 'i:0#.f|membership|jdoe@test.com'
                DisplayName = 'Jane Doe'; Email = 'jdoe@test.com'; UPN = 'jdoe@test.com'
                OrphanType = 'Deleted'; RiskLevel = 'HIGH'; HasDirectPermissions = $false
                GroupMemberships = @(); LastActivityDate = $null; DetectedAt = [datetime]::UtcNow
            }
            $script:FakeRemoveOrphan.PSObject.TypeNames.Insert(0, 'SPC.OrphanedUser')
        }

        It 'AC-LIC-10: WhatIf + CreateSnapshot does NOT throw without license' {
            Mock Get-SPCLicenseInfo { [PSCustomObject]@{ Status = 'Unlicensed'; Tier = 'FREE' } }
            {
                @($script:FakeRemoveOrphan) | Remove-SPCOrphanedUser -CreateSnapshot -WhatIf
            } | Should -Not -Throw
        }

        It 'AC-LIC-11: CreateSnapshot without WhatIf throws ERR-LIC-003 without license' {
            Mock Get-SPCLicenseInfo { [PSCustomObject]@{ Status = 'Unlicensed'; Tier = 'FREE' } }
            {
                @($script:FakeRemoveOrphan) | Remove-SPCOrphanedUser -CreateSnapshot -Force
            } | Should -Throw '*ERR-LIC-003*'
        }
    }
}
