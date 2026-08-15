#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/PnPWrappers.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Test-SPCConnection.ps1')
    . (Join-Path $PSScriptRoot '../../Private/Connect-SPCSiteInternal.ps1')
    . (Join-Path $PSScriptRoot '../../Public/Scan/Get-SPCVersionWaste.ps1')

    $script:SPCContext = [PSCustomObject]@{
        TenantName       = 'contoso'
        GraphAccessToken = 'mock_token'
        PnPContext       = [PSCustomObject]@{}
    }
}

Describe 'Get-SPCVersionWaste Unit Tests' -Tag 'Scan', 'Versions' {
    Context 'AC-05: Version Sprawl and Recoverable Storage Analysis' {
        It 'AC-05: Should accurately calculate recoverable version storage per document library' {
            Mock Connect-SPCSiteInternal { [PSCustomObject]@{} }
            Mock Get-PnPList {
                @(
                    [PSCustomObject]@{ Title = 'Documents'; BaseTemplate = 101; Hidden = $false; MajorVersionLimit = 500; ItemCount = 1 }
                )
            }
            Mock Get-PnPListItem {
                @( [PSCustomObject]@{ FileSystemObjectType = 'File'; 'FileRef' = '/sites/Eng/Docs/spec.docx'; 'FileLeafRef' = 'spec.docx' } )
            }
            Mock Get-PnPProperty {
                param($ClientObject, $Property, $Connection)
                if ($Property -eq 'File') {
                    return [PSCustomObject]@{ Length = 1048576 }
                }
                if ($Property -eq 'Versions') {
                    $now = (Get-Date).ToUniversalTime()
                    $vers = [System.Collections.Generic.List[object]]::new()
                    1..100 | ForEach-Object {
                        $created = if ($_ -le 50) { $now.AddDays(-120) } else { $now.AddDays(-10) }
                        $vers.Add([PSCustomObject]@{ VersionLabel = "$_.0"; Length = 1048576; Created = $created })
                    }
                    return $vers
                }
            }

            $result = Get-SPCVersionWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Eng' -KeepVersions 50 -OlderThanDays 90

            $result.LibraryTitle | Should -Be 'Documents'
            $result.RecoverableStorageMB | Should -Be 50.0
            $result.ConfiguredMaxVersions | Should -Be 500
            $result.SimulatedKeepVersions | Should -Be 50
        }

        It 'AC-05: Should exclude system libraries like FormServerTemplates and Site Assets' {
            Mock Connect-SPCSiteInternal { [PSCustomObject]@{} }
            Mock Get-PnPList {
                @(
                    [PSCustomObject]@{ Title = 'FormServerTemplates'; BaseTemplate = 101; Hidden = $false; MajorVersionLimit = 500; ItemCount = 10 },
                    [PSCustomObject]@{ Title = 'Site Assets'; BaseTemplate = 101; Hidden = $false; MajorVersionLimit = 500; ItemCount = 10 },
                    [PSCustomObject]@{ Title = 'Shared Documents'; BaseTemplate = 101; Hidden = $false; MajorVersionLimit = 500; ItemCount = 0 }
                )
            }
            Mock Get-PnPListItem { @() }

            $result = Get-SPCVersionWaste -SiteUrl 'https://contoso.sharepoint.com/sites/Test'

            $result.Count | Should -Be 1
            $result.LibraryTitle | Should -Be 'Shared Documents'
        }
    }
}
