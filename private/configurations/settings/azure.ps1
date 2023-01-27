# Azure default tenant - can be guid or name
Set-DbatoolsConfig -FullName 'azure.tenantid' -Value $null -Initialize -Validation string -Handler { } -Description "Default Azure tenantid - can be guid or name"

# Azure default AppID for MFA
Set-DbatoolsConfig -FullName 'azure.appid' -Value $null -Initialize -Validation string -Handler { } -Description "Default Azure AppID for MFA"

# Azure default client secret
Set-DbatoolsConfig -FullName 'azure.clientsecret' -Value $null -Initialize -Validation securestring -Handler { } -Description "Client secret as secureString"

# Azure default certificate
Set-DbatoolsConfig -FullName 'azure.certificate.thumbprint' -Value $null -Initialize -Validation string -Handler { } -Description "Certificate thumbprint"

# Azure default certificate store
Set-DbatoolsConfig -FullName 'azure.certificate.store' -Value $null -Initialize -Validation string -Handler { } -Description "Store where certificate resides"

# Azure default certificate store
Set-DbatoolsConfig -FullName 'azure.vm' -Value $null -Initialize -Validation bool -Handler { } -Description "Is this machine in Azure?"