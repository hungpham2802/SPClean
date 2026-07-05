$ErrorActionPreference = 'Stop'
Import-Module .\SPClean.psd1 -Force
Connect-SPCTenant -TenantName 'icclabvn' -AuthMethod AppOnly -ClientId '02e72fed-fb03-486e-a54c-d6193d1e3edd' -CertificateThumbprint '0B6157F727C5542B33152276633E9E55C682F30A'
Get-MgContext | Select-Object ClientId, Account
