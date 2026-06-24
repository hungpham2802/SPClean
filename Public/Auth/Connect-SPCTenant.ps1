# PnP 3.x removed Get-PnPGraphAccessToken; provide compat wrapper so existing mocks and call sites work.
if (-not (Get-Command -Name 'Get-PnPGraphAccessToken' -ErrorAction SilentlyContinue)) {
    function Get-PnPGraphAccessToken {
        [CmdletBinding()]
        param([Parameter()] [object] $Connection)
        if ($Connection) { Get-PnPAccessToken -Connection $Connection } else { Get-PnPAccessToken }
    }
}

function Connect-SPCTenant {
    <#
    .SYNOPSIS
        Establishes an authenticated session to a Microsoft 365 tenant for all SPClean cmdlets.
    .DESCRIPTION
        Supports Interactive (device code flow) and AppOnly (certificate or client secret) auth.
        Stores connection state in $script:SPCContext. Also connects Microsoft Graph for user lookups.
    .PARAMETER TenantName
        Tenant hostname: 'contoso', 'contoso.onmicrosoft.com', or 'contoso.sharepoint.com'.
    .PARAMETER AuthMethod
        'Interactive' (default, device code flow) or 'AppOnly' (requires -ClientId + cert or secret).
    .PARAMETER ClientId
        Azure AD app registration client ID. Required for AppOnly.
    .PARAMETER CertificatePath
        Path to .pfx certificate file. Used with AppOnly cert-based auth.
    .PARAMETER CertificatePassword
        SecureString password for the .pfx file. Never plain text.
    .PARAMETER ClientSecret
        SecureString client secret. AppOnly alternative to certificate. Mutually exclusive with -CertificatePath.
    .EXAMPLE
        Connect-SPCTenant -TenantName contoso
    .EXAMPLE
        Connect-SPCTenant -TenantName contoso -AuthMethod AppOnly -ClientId '...' -CertificatePath C:\cert.pfx -CertificatePassword $pwd
    .OUTPUTS
        SPC.ConnectionInfo
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $TenantName,

        [Parameter()]
        [ValidateSet('Interactive', 'AppOnly')]
        [string] $AuthMethod = 'Interactive',

        [Parameter()]
        [string] $ClientId,

        [Parameter()]
        [string] $CertificatePath,

        [Parameter()]
        [System.Security.SecureString] $CertificatePassword,

        [Parameter()]
        [System.Security.SecureString] $ClientSecret
    )

    begin {
        # ERR-AUTH-001: derive and validate the admin URL from TenantName
        $shortName = $TenantName `
            -replace '^https?://',              '' `
            -replace '\.onmicrosoft\.com.*$',   '' `
            -replace '(-admin)?\.sharepoint\.com.*$', '' `
            -replace '/$',                      ''

        if ($shortName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]*$') {
            throw "ERR-AUTH-001: Cannot resolve tenant URL from TenantName: '$TenantName'. Verify the tenant hostname."
        }
        $adminUrl = "https://${shortName}-admin.sharepoint.com"

        # ERR-AUTH-003: validate AppOnly parameter combination
        if ($AuthMethod -eq 'AppOnly') {
            if ([string]::IsNullOrWhiteSpace($ClientId) -or
                ([string]::IsNullOrWhiteSpace($CertificatePath) -and $null -eq $ClientSecret)) {
                throw 'ERR-AUTH-003: AppOnly auth requires -ClientId and either -CertificatePath or -ClientSecret.'
            }
        }

        # ERR-AUTH-004: PnP 3.x removed the implicit default app — ClientId is required for Interactive auth
        if ($AuthMethod -eq 'Interactive' -and [string]::IsNullOrWhiteSpace($ClientId)) {
            throw 'ERR-AUTH-004: Interactive auth requires -ClientId in PnP.PowerShell 3.x. Register an Entra app with delegated permissions (Sites.FullControl.All, User.Read.All, Directory.Read.All) and "Allow public client flows" enabled, then pass its client ID here.'
        }
    }

    process {
        $connectedAt = (Get-Date).ToUniversalTime()
        $pnpContext  = $null

        try {
            if ($AuthMethod -eq 'Interactive') {
                Write-Verbose "Connecting interactively to $adminUrl"
                $pnpContext = Connect-PnPOnline -Url $adminUrl -Interactive -ClientId $ClientId -ReturnConnection
                # Connect-MgGraph for Graph cmdlets (SRS 3.1.1 step 2)
                Connect-MgGraph -Scopes 'User.Read.All', 'Directory.Read.All' -NoWelcome |
                    Out-Null

            } elseif (-not [string]::IsNullOrWhiteSpace($CertificatePath)) {
                Write-Verbose "Connecting AppOnly (certificate) to $adminUrl"
                # Azure AD requires a valid DNS name; append .onmicrosoft.com when only short name given
                $tenantId   = if ($shortName -match '\.') { $shortName } else { "$shortName.onmicrosoft.com" }
                $pnpContext = Connect-PnPOnline -Url $adminUrl -ClientId $ClientId `
                    -Tenant $tenantId `
                    -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword `
                    -ReturnConnection

            } else {
                Write-Verbose "Connecting AppOnly (client secret) to $adminUrl"
                # SecureString → plain only in-memory, cleared immediately after (SRS 4.3 / E001)
                $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
                try {
                    $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                    $pnpContext = Connect-PnPOnline -Url $adminUrl -ClientId $ClientId `
                        -ClientSecret $plain -ReturnConnection
                } finally {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                    $plain = $null
                }
            }
        } catch {
            # ERR-AUTH-002: propagate underlying auth error with context prefix
            throw "SPClean: Authentication failed. $($_.Exception.Message)"
        }

        $graphToken = Get-PnPGraphAccessToken -Connection $pnpContext

        # SRS 3.1.1 step 4 — store module-scoped context
        # _-prefixed fields are internal: used by Get-SPCOrphanedUser for per-site reconnects
        $script:SPCContext = [PSCustomObject]@{
            TenantName           = $shortName
            AuthMethod           = $AuthMethod
            ConnectedAt          = $connectedAt
            PnPContext           = $pnpContext
            GraphAccessToken     = $graphToken
            _ClientId            = $ClientId
            _CertificatePath     = $CertificatePath
            _CertificatePassword = $CertificatePassword   # SecureString — never plain text
            _ClientSecret        = $ClientSecret          # SecureString — never plain text
        }

        # SRS 3.1.1 step 5 — pipeline output
        $out = [PSCustomObject][ordered]@{
            TenantName     = $shortName
            AuthMethod     = $AuthMethod
            ConnectedAt    = $connectedAt
            ExpiresAt      = $connectedAt.AddHours(1)
        }
        $out.PSObject.TypeNames.Insert(0, 'SPC.ConnectionInfo')
        $out
    }
}
