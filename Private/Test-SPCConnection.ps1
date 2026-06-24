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
