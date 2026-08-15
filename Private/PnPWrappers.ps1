# PS wrappers with [object] Connection so Pester mocks don't enforce PnPConnection type coercion.
function Get-PnPAccessToken {
    [CmdletBinding()]
    param(
        [Parameter()] [string]$ResourceTypeName,
        [Parameter()] [object]$Connection
    )
    if (Get-Command -Name 'Get-PnPAccessToken' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPAccessToken' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Connect-PnPOnline {
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Url,
        [Parameter()] [string]$AccessToken,
        [Parameter()] [switch]$ReturnConnection,
        [Parameter()] [switch]$Interactive,
        [Parameter()] [string]$ClientId,
        [Parameter()] [string]$Tenant,
        [Parameter()] [string]$Thumbprint,
        [Parameter()] [string]$CertificatePath,
        [Parameter()] [System.Security.SecureString]$CertificatePassword,
        [Parameter()] [string]$ClientSecret
    )
    if (Get-Command -Name 'Connect-PnPOnline' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Connect-PnPOnline' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPWeb {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection
    )
    if (Get-Command -Name 'Get-PnPWeb' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPWeb' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPSite {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection
    )
    if (Get-Command -Name 'Get-PnPSite' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPSite' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPSubWeb {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter()] [switch]$Recurse
    )
    if (Get-Command -Name 'Get-PnPSubWeb' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPSubWeb' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPList {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter(Position=0)] [object]$Identity,
        [Parameter()] [string[]]$Includes
    )
    if (Get-Command -Name 'Get-PnPList' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        $p = @{}
        if ($PSBoundParameters.ContainsKey('Connection')) { $p['Connection'] = $Connection }
        if ($PSBoundParameters.ContainsKey('Identity')) { $p['Identity'] = $Identity }
        if ($PSBoundParameters.ContainsKey('Includes')) { $p['Includes'] = $Includes }
        & (Get-Command -Name 'Get-PnPList' -Module PnP.PowerShell) @p
    }
}

function Get-PnPListItem {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter(Position=0)] [object]$List,
        [Parameter()] [int]$PageSize,
        [Parameter()] [string[]]$Fields,
        [Parameter()] [string[]]$Includes
    )
    if (Get-Command -Name 'Get-PnPListItem' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        $listTarget = if ($null -ne $List -and $List.GetType().Name -match 'List$' -and -not [string]::IsNullOrWhiteSpace($List.Title)) {
            $List.Title
        } else {
            $List
        }
        $p = @{ List = $listTarget; Connection = $Connection }
        if ($PSBoundParameters.ContainsKey('PageSize')) { $p['PageSize'] = $PageSize }
        if ($PSBoundParameters.ContainsKey('Fields')) { $p['Fields'] = $Fields }
        if ($PSBoundParameters.ContainsKey('Includes')) { $p['Includes'] = $Includes }
        & (Get-Command -Name 'Get-PnPListItem' -Module PnP.PowerShell) @p
    }
}

function Get-PnPProperty {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter()] [object]$ClientObject,
        [Parameter()] [string]$Property
    )
    if (Get-Command -Name 'Get-PnPProperty' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPProperty' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPRecycleBinItem {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter()] [int]$RowLimit
    )
    if (Get-Command -Name 'Get-PnPRecycleBinItem' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPRecycleBinItem' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Clear-PnPRecycleBinItem {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter()] [object]$Identity,
        [Parameter()] [switch]$Force
    )
    if (Get-Command -Name 'Clear-PnPRecycleBinItem' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Clear-PnPRecycleBinItem' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Set-PnPList {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter()] [object]$Identity,
        [Parameter()] [int]$MajorVersions
    )
    if (Get-Command -Name 'Set-PnPList' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Set-PnPList' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPRoleAssignment {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter()] [switch]$IncludeRoleDefinitionBindings
    )
    if (Get-Command -Name 'Get-PnPRoleAssignment' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPRoleAssignment' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPRoleDefinition {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter()] [object]$Identity
    )
    if (Get-Command -Name 'Get-PnPRoleDefinition' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPRoleDefinition' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPTenantSite {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter()] [string]$Url,
        [Parameter()] [switch]$Detailed
    )
    if (Get-Command -Name 'Get-PnPTenantSite' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPTenantSite' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPGroup {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter()] [object]$Identity
    )
    if (Get-Command -Name 'Get-PnPGroup' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPGroup' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPSiteCollectionAdmin {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection
    )
    if (Get-Command -Name 'Get-PnPSiteCollectionAdmin' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPSiteCollectionAdmin' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPSiteUser {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter()] [object]$Identity
    )
    if (Get-Command -Name 'Get-PnPSiteUser' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPSiteUser' -Module PnP.PowerShell) @PSBoundParameters
    }
}
