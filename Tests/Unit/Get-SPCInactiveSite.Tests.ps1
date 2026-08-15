#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Get-SPCGraphSiteUsageInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Scan/Get-SPCInactiveSite.ps1')

    $script:SPCContext = [PSCustomObject]@{
        TenantName       = 'contoso'
        GraphAccessToken = 'mock_token'
    }
}

Describe 'Get-SPCInactiveSite Unit Tests' -Tag 'Scan', 'Inactive' {
    Context 'AC-03: Inactive Days Threshold Verification' {
        It 'AC-03: Should return only sites with activity older than InactiveDays or null activity' {
            $now = (Get-Date).ToUniversalTime()
            Mock Get-SPCGraphSiteUsageInternal {
                @(
                    [PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/ActiveSite'; StorageUsedMB = 500.0; LastActivityDate = $now.AddDays(-30); IsTeamSite = $false; LockState = 'Unlock'; OwnerUPN = 'user1@contoso.com'; FileCount = 10; GroupId = ''; Template = 'STS#3'; SiteTitle = 'Active' },
                    [PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/DormantSite'; StorageUsedMB = 2048.0; LastActivityDate = $now.AddDays(-120); IsTeamSite = $false; LockState = 'Unlock'; OwnerUPN = 'user2@contoso.com'; FileCount = 50; GroupId = ''; Template = 'STS#3'; SiteTitle = 'Dormant' },
                    [PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/NeverUsed'; StorageUsedMB = 100.0; LastActivityDate = $null; IsTeamSite = $true; LockState = 'Unlock'; OwnerUPN = 'user3@contoso.com'; FileCount = 0; GroupId = 'grp-123'; Template = 'GROUP#0'; SiteTitle = 'NeverUsed' }
                )
            }

            $result = Get-SPCInactiveSite -InactiveDays 90

            $result.Count | Should -Be 2
            $result.SiteUrl | Should -Contain 'https://contoso.sharepoint.com/sites/DormantSite'
            $result.SiteUrl | Should -Contain 'https://contoso.sharepoint.com/sites/NeverUsed'
            $result.SiteUrl | Should -Not -Contain 'https://contoso.sharepoint.com/sites/ActiveSite'
        }
    }

    Context 'AC-04: Filtering by MinStorageMB and IncludeTeamSitesOnly' {
        It 'AC-04: Should filter sites based on MinStorageMB and Team site status' {
            $now = (Get-Date).ToUniversalTime()
            Mock Get-SPCGraphSiteUsageInternal {
                @(
                    [PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/Team1'; StorageUsedMB = 2048.0; LastActivityDate = $now.AddDays(-200); IsTeamSite = $true; LockState = 'Unlock'; OwnerUPN = 'user1@contoso.com'; FileCount = 100; GroupId = 'g1'; Template = 'GROUP#0'; SiteTitle = 'Team1' },
                    [PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/Team2'; StorageUsedMB = 500.0; LastActivityDate = $now.AddDays(-200); IsTeamSite = $true; LockState = 'Unlock'; OwnerUPN = 'user2@contoso.com'; FileCount = 20; GroupId = 'g2'; Template = 'GROUP#0'; SiteTitle = 'Team2' },
                    [PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/NonTeam'; StorageUsedMB = 4096.0; LastActivityDate = $now.AddDays(-200); IsTeamSite = $false; LockState = 'Unlock'; OwnerUPN = 'user3@contoso.com'; FileCount = 300; GroupId = ''; Template = 'STS#3'; SiteTitle = 'NonTeam' }
                )
            }

            $result = Get-SPCInactiveSite -InactiveDays 180 -MinStorageMB 1024 -IncludeTeamSitesOnly

            $result.Count | Should -Be 1
            $result[0].SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/Team1'
        }
    }

    Context 'AC-03: Recommendation Matrix' {
        It 'AC-03: Should produce correct recommendation depending on days inactive' {
            $now = (Get-Date).ToUniversalTime()
            Mock Get-SPCGraphSiteUsageInternal {
                @(
                    [PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/OldSite'; StorageUsedMB = 1000.0; LastActivityDate = $now.AddDays(-400); IsTeamSite = $false; LockState = 'Unlock'; OwnerUPN = 'u1'; FileCount = 10; GroupId = ''; Template = 'STS#3'; SiteTitle = 'Old' },
                    [PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/MidSite'; StorageUsedMB = 1000.0; LastActivityDate = $now.AddDays(-200); IsTeamSite = $false; LockState = 'Unlock'; OwnerUPN = 'u2'; FileCount = 10; GroupId = ''; Template = 'STS#3'; SiteTitle = 'Mid' },
                    [PSCustomObject]@{ SiteUrl = 'https://contoso.sharepoint.com/sites/RecentSite'; StorageUsedMB = 1000.0; LastActivityDate = $now.AddDays(-100); IsTeamSite = $false; LockState = 'Unlock'; OwnerUPN = 'u3'; FileCount = 10; GroupId = ''; Template = 'STS#3'; SiteTitle = 'Recent' }
                )
            }

            $result = Get-SPCInactiveSite -InactiveDays 90

            $old = $result | Where-Object { $_.SiteUrl -match 'OldSite' }
            $mid = $result | Where-Object { $_.SiteUrl -match 'MidSite' }
            $recent = $result | Where-Object { $_.SiteUrl -match 'RecentSite' }

            $old.Recommendation | Should -Be 'Archive or Delete'
            $mid.Recommendation | Should -Be 'Set ReadOnly'
            $recent.Recommendation | Should -Be 'Review with Owner'
        }
    }
}
