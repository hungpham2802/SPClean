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
        [Parameter()] [object]$Identity,
        [Parameter()] [switch]$AssociatedOwnerGroup,
        [Parameter()] [switch]$AssociatedMemberGroup,
        [Parameter()] [switch]$AssociatedVisitorGroup,
        [Parameter()] [string[]]$Includes
    )
    if (Get-Command -Name 'Get-PnPGroup' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPGroup' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPGroupMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, Position=0)] [object]$Group,
        [Parameter()] [object]$Identity,
        [Parameter()] [object]$Connection
    )
    if (Get-Command -Name 'Get-PnPGroupMember' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        $p = @{}
        if ($PSBoundParameters.ContainsKey('Connection')) { $p['Connection'] = $Connection }
        $targetGroup = if ($Group) { $Group } elseif ($Identity) { $Identity } else { $null }
        if ($targetGroup) {
            $groupKey = if ($targetGroup -is [string] -or $targetGroup -is [int]) { $targetGroup } else { [string]$targetGroup.Title }
            $p['Group'] = $groupKey
        }
        & (Get-Command -Name 'Get-PnPGroupMember' -Module PnP.PowerShell) @p
    }
}

function Set-PnPTenantSite {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, ValueFromPipelineByPropertyName=$true)]
        [Alias('Url')]
        [string]$Identity,

        [Parameter()]
        [string[]]$Owners,

        [Parameter()]
        [object]$Connection
    )
    if (Get-Command -Name 'Set-PnPTenantSite' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        $bound = @{}
        if ($Identity) { $bound['Identity'] = $Identity }
        if ($Owners) { $bound['Owners'] = $Owners }
        if ($Connection) { $bound['Connection'] = $Connection }
        & (Get-Command -Name 'Set-PnPTenantSite' -Module PnP.PowerShell) @bound
    }
}

function Remove-PnPSiteCollectionAdmin {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter()] [string[]]$Owners
    )
    if (Get-Command -Name 'Remove-PnPSiteCollectionAdmin' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Remove-PnPSiteCollectionAdmin' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Invoke-PnPSPRestMethod {
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Method = 'Get',
        [Parameter()] [string]$Url,
        [Parameter()] [object]$Content,
        [Parameter()] [object]$Connection
    )
    if (Get-Command -Name 'Invoke-PnPSPRestMethod' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Invoke-PnPSPRestMethod' -Module PnP.PowerShell) @PSBoundParameters
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
    } else {
        Get-PnPUser -Connection $Connection
    }
}

function Get-PnPSiteGroup {
    [CmdletBinding()]
    param([Parameter()] [object]$Connection)
    if (Get-Command -Name 'Get-PnPSiteGroup' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPSiteGroup' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPUser {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Connection,
        [Parameter()] [switch]$WithRightsAssigned,
        [Parameter()] [string]$LoginName,
        [Parameter()] [string[]]$Includes
    )
    if (Get-Command -Name 'Get-PnPUser' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        $params = @{}
        foreach ($k in $PSBoundParameters.Keys) { $params[$k] = $PSBoundParameters[$k] }
        if ($params.ContainsKey('LoginName')) {
            $params['Identity'] = $params['LoginName']
            $params.Remove('LoginName') | Out-Null
        }
        & (Get-Command -Name 'Get-PnPUser' -Module PnP.PowerShell) @params
    }
}

function Add-PnPGroupMember {
    [CmdletBinding()]
    param(
        [Parameter()] [string]$LoginName,
        [Parameter()] [object]$Group,
        [Parameter()] [object]$Connection
    )
    if (Get-Command -Name 'Add-PnPGroupMember' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Add-PnPGroupMember' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Set-PnPWebPermission {
    [CmdletBinding()]
    param(
        [Parameter()] [string]$User,
        [Parameter()] [string]$AddRole,
        [Parameter()] [string]$RemoveRole,
        [Parameter()] [object]$Connection
    )
    if (Get-Command -Name 'Set-PnPWebPermission' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Set-PnPWebPermission' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Get-PnPRoleDefinition {
    [CmdletBinding()]
    param(
        [Parameter()] [object]$Identity,
        [Parameter()] [object]$Connection
    )
    if (Get-Command -Name 'Get-PnPRoleDefinition' -Module PnP.PowerShell -ErrorAction SilentlyContinue) {
        & (Get-Command -Name 'Get-PnPRoleDefinition' -Module PnP.PowerShell) @PSBoundParameters
    }
}

function Add-PnPRoleAssignment {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $LoginName,
        [Parameter()] [string] $RoleDefinitionName,
        [Parameter()] [int]    $RoleDefinitionId,
        [Parameter()] [object] $Connection
    )
    if (-not [string]::IsNullOrWhiteSpace($RoleDefinitionName)) {
        Set-PnPWebPermission -User $LoginName -AddRole $RoleDefinitionName -Connection $Connection -ErrorAction Stop
    } else {
        $rd = Get-PnPRoleDefinition -Identity $RoleDefinitionId -Connection $Connection -ErrorAction Stop
        Set-PnPWebPermission -User $LoginName -AddRole $rd.Name -Connection $Connection -ErrorAction Stop
    }
}
