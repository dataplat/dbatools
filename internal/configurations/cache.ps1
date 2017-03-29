<#
This is designed for all things that control how anything that caches acts
#>

# Disable the management cache entire
Set-DbaConfig -Name 'Cache.Management.Disable.All' -Value $false -Default -DisableHandler -Description "Globally disables all caching done by the Windows Management functions"

# Disables the caching of bad credentials, which is kept in order to avoid reusing them
Set-DbaConfig -Name 'Cache.Management.Disable.BadCredentialList' -Value $false -Default -DisableHandler -Description "Disables the caching of bad credentials. dbatools caches bad logon credentials for wmi/cim and will not reuse them."