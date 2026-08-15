#Requires -Version 7.0
<#
.MODULE
    SPClean
.VERSION
    2.0.0
.RELEASENOTES
    2.0.0 - 2026-08-15:
    - Major Feature: SharePoint Online Storage Optimization & Digital Waste Management.
    - New Scan Cmdlets: Get-SPCStorageWaste, Get-SPCInactiveSite, Get-SPCVersionWaste, Get-SPCPreservationHoldWaste.
    - New Remediation Cmdlets: Clear-SPCRecycleBin, Optimize-SPCFileVersion.
    - New Reporting Cmdlet: Export-SPCStorageReport (Interactive HTML ROI Dashboard + CSV Audit).
    - Architecture: Decoupled PnPWrappers layer, PnP 3.2.0 compatibility, BSTR unmanaged memory zeroing.
#>

# Module-scoped connection state — set by Connect-SPCTenant, cleared by Disconnect-SPCTenant
$script:SPCContext = $null

$wrapperFile  = Join-Path -Path $PSScriptRoot -ChildPath 'Private\PnPWrappers.ps1'
if (Test-Path -Path $wrapperFile) {
    . $wrapperFile
}

$privateFiles = Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -Exclude 'PnPWrappers.ps1' -ErrorAction SilentlyContinue
$publicFiles  = Get-ChildItem -Path "$PSScriptRoot\Public\**\*.ps1" -Recurse -ErrorAction SilentlyContinue

foreach ($file in $privateFiles) {
    . $file.FullName
}

foreach ($file in $publicFiles) {
    . $file.FullName
}

# Register aliases for backward compatibility
Set-Alias -Name 'Invoke-SPCDashboardReportV1' -Value 'Invoke-SPCDashboardReport' -Description 'Deprecated: Use Invoke-SPCDashboardReport instead.'
Set-Alias -Name 'Invoke-SPCPermissionAnalyticsV2' -Value 'Invoke-SPCPermissionAnalytics' -Description 'Deprecated: Use Invoke-SPCPermissionAnalytics instead.'

Export-ModuleMember -Function (
    'Connect-SPCTenant',
    'Disconnect-SPCTenant',
    'Get-SPCOrphanedUser',
    'Export-SPCReport',
    'Remove-SPCOrphanedUser',
    'Restore-SPCOrphanedUser',
    'New-SPCScanSchedule',
    'Register-SPCLicense',
    'Get-SPCLicenseInfo',
    'Get-SPCMismatchUser',
    'Repair-SPCMismatchUser',
    'Get-SPCGuestAccess',
    'Get-SPCPrivilegedUser',
    'Get-SPCOverPermissionedUser',
    'Get-SPCPermissionHealthScore',
    'Get-SPCBrokenInheritance',
    'Compare-SPCPermissionSnapshot',
    'Invoke-SPCDashboardReport',
    'Invoke-SPCPermissionAnalytics',
    'Get-SPCStorageWaste',
    'Get-SPCInactiveSite',
    'Get-SPCVersionWaste',
    'Get-SPCPreservationHoldWaste',
    'Clear-SPCRecycleBin',
    'Optimize-SPCFileVersion',
    'Export-SPCStorageReport'
) -Alias (
    'Invoke-SPCDashboardReportV1',
    'Invoke-SPCPermissionAnalyticsV2'
)
