# When unit tests dot-source only this file (without LicenseManager.ps1), the license
# gate functions are undefined. These stubs prevent CommandNotFoundException.
# In a full module load, LicenseManager.ps1 loads alphabetically first and defines the
# real implementations; the guard below ensures the stubs do NOT override them.
if (-not (Get-Command 'Assert-SPCProLicense' -ErrorAction SilentlyContinue)) {
    function Assert-SPCProLicense       { param([Parameter(Mandatory)][string]$Feature) }
    function Assert-SPCConsultantLicense { param([Parameter(Mandatory)][string]$Feature) }
}

function Test-SPCConnection {
    <#
    .SYNOPSIS
        Guards public cmdlets — throws if no active SPClean connection exists.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    process {
        if ($null -eq $script:SPCContext) {
            $timestamp = (Get-Date).ToUniversalTime().ToString('o')
            throw "No active SPClean connection. Run Connect-SPCTenant first. [$timestamp]"
        }
    }
}
