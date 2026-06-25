function Disconnect-SPCTenant {
    <#
    .SYNOPSIS
        Clears the SPClean connection context and disconnects PnP and Graph sessions.
    .DESCRIPTION
        Always succeeds — never throws. Idempotent: safe to call when not connected.
    .EXAMPLE
        Disconnect-SPCTenant
    .EXAMPLE
        Disconnect-SPCTenant -WhatIf
    .OUTPUTS
        None.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()

    process {
        if ($PSCmdlet.ShouldProcess('SPClean tenant connection', 'Disconnect')) {
            # SRS 3.1.2: always succeeds — wrap every call individually
            try { Disconnect-PnPOnline -ErrorAction SilentlyContinue } catch {}
            try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
            $script:SPCContext      = $null
            $script:SPCLicenseCache = $null
            Write-Verbose 'SPClean: Disconnected from tenant.'
        }
    }
}
