$ErrorActionPreference = 'Stop'
Import-Module .\SPClean.psd1 -Force
Connect-SPCTenant -TenantName 'icclabvn' -AuthMethod Interactive -ClientId '889a17ac-afca-4d54-838c-9bf793407670'
$res = Invoke-SPCGraph -Method GET -Url "/me" -AccessToken $script:SPCContext.GraphAccessToken
$res.body.userPrincipalName
