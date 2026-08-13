BeforeAll {
    $publicDir = "d:\Project\SPClean\Public"
    $privateDir = "d:\Project\SPClean\Private"
    
    . "$privateDir\Calculate-SPCScoreInternal.ps1"
    . "$privateDir\Get-SPCLibraryBrokenInheritanceInternal.ps1"
    . "$privateDir\Test-SPCConnection.ps1"
    
    if (Test-Path "$publicDir\Report\Get-SPCPermissionHealthScore.ps1") {
        . "$publicDir\Report\Get-SPCPermissionHealthScore.ps1"
    }
    if (Test-Path "$publicDir\Scan\Get-SPCBrokenInheritance.ps1") {
        . "$publicDir\Scan\Get-SPCBrokenInheritance.ps1"
    }
    if (Test-Path "$publicDir\Report\Compare-SPCPermissionSnapshot.ps1") {
        . "$publicDir\Report\Compare-SPCPermissionSnapshot.ps1"
    }

    # Dummy module properties
    $script:SPCContext = @{
        TenantId = "tenant"
        IsConnected = $true
    }
}

Describe "Phase 2 Unit Tests" {
    Context "Calculate-SPCScoreInternal" {
        It "F5-01: Tính điểm với rủi ro bằng 0" {
            $res = Calculate-SPCScoreInternal -OrphanedUserCount 0 -HighRiskGuestCount 0 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0
            $res.OverallScore | Should -Be 100
            $res.Breakdown.OrphanedUserDeduction | Should -Be 0
        }
        It "F5-02: Trừ điểm Orphaned User chưa chạm trần" {
            $res = Calculate-SPCScoreInternal -OrphanedUserCount 10 -HighRiskGuestCount 0 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0
            $res.OverallScore | Should -Be 80
            $res.Breakdown.OrphanedUserDeduction | Should -Be 20
        }
        It "F5-03: Trừ điểm Orphaned User vượt trần" {
            $res = Calculate-SPCScoreInternal -OrphanedUserCount 20 -HighRiskGuestCount 0 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0
            $res.OverallScore | Should -Be 70
            $res.Breakdown.OrphanedUserDeduction | Should -Be 30
        }
        It "F5-04: Trừ điểm High-Risk Guest chưa chạm trần" {
            $res = Calculate-SPCScoreInternal -OrphanedUserCount 0 -HighRiskGuestCount 10 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0
            $res.OverallScore | Should -Be 85
            $res.Breakdown.HighRiskGuestDeduction | Should -Be 15
        }
        It "F5-05: Trừ điểm High-Risk Guest vượt trần" {
            $res = Calculate-SPCScoreInternal -OrphanedUserCount 0 -HighRiskGuestCount 20 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0
            $res.OverallScore | Should -Be 75
            $res.Breakdown.HighRiskGuestDeduction | Should -Be 25
        }
        It "F5-06: Trừ điểm Over-Permissioned User vượt trần" {
            $res = Calculate-SPCScoreInternal -OrphanedUserCount 0 -HighRiskGuestCount 0 -OverPermissionedUserCount 15 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0
            $res.OverallScore | Should -Be 80
            $res.Breakdown.OverPermissionedDeduction | Should -Be 20
        }
        It "F5-07: Trừ điểm Broken Inheritance & Missing Owner" {
            $res = Calculate-SPCScoreInternal -OrphanedUserCount 0 -HighRiskGuestCount 0 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 2 -MissingOwnerSiteCount 1
            $res.OverallScore | Should -Be 60
            $res.Breakdown.BrokenInheritanceDeduction | Should -Be 30
            $res.Breakdown.MissingOwnerDeduction | Should -Be 10
        }
        It "F5-08: Tổ hợp tất cả rủi ro vượt trần (Worst case)" {
            $res = Calculate-SPCScoreInternal -OrphanedUserCount 100 -HighRiskGuestCount 100 -OverPermissionedUserCount 100 -BrokenInheritanceSiteCount 10 -MissingOwnerSiteCount 10
            $res.OverallScore | Should -Be 0
        }
    }

    Context "Get-SPCLibraryBrokenInheritanceInternal" {
        It "F6-02: Có Folder bẻ gãy kế thừa" {
            Mock Get-PnPList {
                return @(
                    [PSCustomObject]@{
                        Title = "DocLib1"
                        BaseType = 'DocumentLibrary'
                        Hidden = $false
                        HasUniqueRoleAssignments = $false
                        RootFolder = [PSCustomObject]@{ ServerRelativeUrl = "/sites/test/DocLib1" }
                    }
                )
            }
            Mock Get-PnPListItem {
                return @(
                    [PSCustomObject]@{
                        Id = 1
                        HasUniqueRoleAssignments = $true
                        FileSystemObjectType = 'Folder'
                        FieldValues = @{ FileRef = "/sites/test/DocLib1/Folder1" }
                    }
                )
            }
            $res = Get-SPCLibraryBrokenInheritanceInternal -SiteUrl "https://test.sharepoint.com/sites/test"
            $res.Count | Should -Be 1
            $res[0].Path | Should -Be "/sites/test/DocLib1/Folder1"
            $res[0].Type | Should -Be "Folder"
        }
    }

    Context "Compare-SPCPermissionSnapshot" {
        BeforeAll {
            $baseline = @(
                @{ user = @{ upn = "admin@test.com" }; isSCA = $true; isOwner = $false; permissions = @() },
                @{ user = @{ upn = "owner@test.com" }; isSCA = $false; isOwner = $true; permissions = @() },
                @{ user = @{ upn = "user1@test.com" }; isSCA = $false; isOwner = $false; permissions = @("Full Control") },
                @{ user = @{ upn = "guest#EXT#@external.com" }; isSCA = $false; isOwner = $false; permissions = @() }
            ) | ConvertTo-Json -Depth 5
            
            $current = @(
                @{ user = @{ upn = "admin@test.com" }; isSCA = $true; isOwner = $false; permissions = @() },
                @{ user = @{ upn = "newadmin@test.com" }; isSCA = $true; isOwner = $false; permissions = @() },
                @{ user = @{ upn = "owner@test.com" }; isSCA = $false; isOwner = $true; permissions = @() },
                @{ user = @{ upn = "newowner@test.com" }; isSCA = $false; isOwner = $true; permissions = @() },
                @{ user = @{ upn = "user1@test.com" }; isSCA = $false; isOwner = $false; permissions = @("Full Control") },
                @{ user = @{ upn = "user2@test.com" }; isSCA = $false; isOwner = $false; permissions = @("Full Control") },
                @{ user = @{ upn = "guest#EXT#@external.com" }; isSCA = $false; isOwner = $false; permissions = @() },
                @{ user = @{ upn = "newguest#EXT#@external.com" }; isSCA = $false; isOwner = $false; permissions = @() }
            ) | ConvertTo-Json -Depth 5
            
            $baselinePath = "d:\Project\SPClean\Tests\Unit\baseline.json"
            $currentPath = "d:\Project\SPClean\Tests\Unit\current.json"
            Set-Content -Path $baselinePath -Value $baseline
            Set-Content -Path $currentPath -Value $current
        }
        
        It "F7-01 to F7-04: Phát hiện biến động" {
            $baselinePath = "d:\Project\SPClean\Tests\Unit\baseline.json"
            $currentPath = "d:\Project\SPClean\Tests\Unit\current.json"
            
            Mock Test-SPCConnection { return $true }
            
            $res = Compare-SPCPermissionSnapshot -BaselineSnapshotPath $baselinePath -CurrentSnapshotPath $currentPath
            
            $res.NewSCAOrOwners | Should -Contain "newadmin@test.com"
            $res.NewSCAOrOwners | Should -Contain "newowner@test.com"
            $res.NewDirectFullControlAssignments | Should -Contain "user2@test.com"
            $res.NewGuestAccounts | Should -Contain "newguest#EXT#@external.com"
        }
        
        AfterAll {
            Remove-Item "d:\Project\SPClean\Tests\Unit\baseline.json" -ErrorAction SilentlyContinue
            Remove-Item "d:\Project\SPClean\Tests\Unit\current.json" -ErrorAction SilentlyContinue
        }
    }
    
    Context "Security Test Cases" {
        It "SEC-01: Không rò rỉ Token/Secret trong luồng Verbose" {
            $verboseLog = @()
            # We mock write-verbose to capture it
            Mock Write-Verbose {
                param($Message)
                $script:verboseLog += $Message
            }
            # Run something that generates verbose output
            Calculate-SPCScoreInternal -OrphanedUserCount 0 -HighRiskGuestCount 0 -OverPermissionedUserCount 0 -BrokenInheritanceSiteCount 0 -MissingOwnerSiteCount 0 -Verbose
            
            $leak = $script:verboseLog | Where-Object { $_ -match "password|secret|token|bearer" }
            $leak | Should -BeNullOrEmpty
        }
    }
}
