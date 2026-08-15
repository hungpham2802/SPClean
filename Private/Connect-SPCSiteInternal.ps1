function Connect-SPCSiteInternal {
    <#
    .SYNOPSIS
        Private helper establishing a site-specific PnP connection reusing active session credentials.
    .DESCRIPTION
        Consolidates per-site authentication across SPClean cmdlets. Supports Interactive
        token reuse and AppOnly authentication via certificate file, certificate thumbprint,
        or client secret (with secure in-memory BSTR memory clearing).
    .PARAMETER SiteUrl
        The full URL of the SharePoint Online site collection to connect to.
    .PARAMETER Context
        The session context object. Defaults to $script:SPCContext.
    .OUTPUTS
        [PnP.PowerShell.Commands.Base.PnPConnection] or connection object
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteUrl,

        [Parameter()]
        [PSCustomObject]$Context = $script:SPCContext
    )

    begin {
        Write-Verbose "Connect-SPCSiteInternal: Connecting to site collection '$SiteUrl'"
        if ($null -eq $Context) {
            throw 'ERR-AUTH-005: Connect-SPCSiteInternal: No active SPClean session context provided.'
        }
    }

    process {
        $tenantId = if ($Context.TenantName -match '\.') { $Context.TenantName } else { "$($Context.TenantName).onmicrosoft.com" }

        $authMode = if ($Context.AuthMode) { $Context.AuthMode } else { $Context.AuthMethod }

        switch ($authMode) {
            'Interactive' {
                $token = if ($Context.GraphAccessToken) {
                    $Context.GraphAccessToken
                } elseif ($Context.PnPContext) {
                    Get-PnPAccessToken -ResourceTypeName SharePoint -Connection $Context.PnPContext
                } else {
                    Get-PnPAccessToken -ResourceTypeName SharePoint
                }
                Connect-PnPOnline -Url $SiteUrl -AccessToken $token -ReturnConnection
            }
            'AppOnly' {
                $clientId = if ($Context.ClientId) { $Context.ClientId } else { $Context._ClientId }
                $certPath = if ($Context.CertificatePath) { $Context.CertificatePath } else { $Context._CertificatePath }
                $certPass = if ($Context.CertificatePassword) { $Context.CertificatePassword } else { $Context._CertificatePassword }
                $thumbprint = if ($Context.CertificateThumbprint) { $Context.CertificateThumbprint } elseif ($Context.Thumbprint) { $Context.Thumbprint } else { $Context._CertificateThumbprint }
                $clientSecret = if ($Context.ClientSecret) { $Context.ClientSecret } else { $Context._ClientSecret }

                if ($certPath) {
                    $pnpParams = @{
                        Url              = $SiteUrl
                        ClientId         = $clientId
                        Tenant           = $tenantId
                        CertificatePath  = $certPath
                        ReturnConnection = $true
                    }
                    if ($null -ne $certPass) {
                        $pnpParams['CertificatePassword'] = $certPass
                    }
                    Connect-PnPOnline @pnpParams
                } elseif ($thumbprint) {
                    Connect-PnPOnline -Url $SiteUrl -ClientId $clientId `
                        -Tenant $tenantId `
                        -Thumbprint $thumbprint -ReturnConnection
                } elseif ($null -ne $clientSecret) {
                    $secSecret = if ($clientSecret -is [System.Security.SecureString]) {
                        $clientSecret
                    } else {
                        ConvertTo-SecureString $clientSecret -AsPlainText -Force
                    }
                    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secSecret)
                    try {
                        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                        Connect-PnPOnline -Url $SiteUrl -ClientId $clientId `
                            -ClientSecret $plain -Tenant $tenantId -ReturnConnection
                    } finally {
                        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                        $plain = $null
                    }
                } else {
                    throw 'ERR-AUTH-003: Connect-SPCSiteInternal: Incomplete AppOnly credentials in context.'
                }
            }
            Default {
                throw "ERR-AUTH-001: Connect-SPCSiteInternal: Unsupported AuthMethod '$authMode'."
            }
        }
    }

    end {
        Write-Verbose "Connect-SPCSiteInternal: Completed connection for '$SiteUrl'"
    }
}
