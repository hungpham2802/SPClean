#Requires -Version 5.1

# Module-scoped connection state — set by Connect-SPCTenant, cleared by Disconnect-SPCTenant
$script:SPCContext = $null

$privateFiles = Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue
$publicFiles  = Get-ChildItem -Path "$PSScriptRoot\Public\**\*.ps1" -Recurse -ErrorAction SilentlyContinue

foreach ($file in $privateFiles) {
    . $file.FullName
}

foreach ($file in $publicFiles) {
    . $file.FullName
}

Export-ModuleMember -Function (
    'Connect-SPCTenant',
    'Disconnect-SPCTenant',
    'Get-SPCOrphanedUser',
    'Export-SPCReport',
    'Remove-SPCOrphanedUser',
    'Restore-SPCOrphanedUser',
    'New-SPCScanSchedule',
    'Register-SPCLicense',
    'Get-SPCLicenseInfo'
)
