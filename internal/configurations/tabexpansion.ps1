# Sets the default interval and timeout for TEPP updates
Set-DbaConfig -Name 'TabExpansion.UpdateInterval' -Value (New-TimeSpan -Minutes 3) -Default -DisableHandler -Description 'The frequency in which TEPP tries to update each cache for autocompletion'
Set-DbaConfig -Name 'TabExpansion.UpdateTimeout' -Value (New-TimeSpan -Minutes 30) -Default -DisableHandler -Description 'After this timespan has passed without connections to a server, the TEPP updater will no longer update the cache.'

# Disable the management cache entire
Set-DbaConfig -Name 'TabExpansion.Disable' -Value $false -Default -DisableHandler -Description 'Globally disables all TEPP functionality by dbatools'
Set-DbaConfig -Name 'TabExpansion.Disable.Asynchronous' -Value $true -Default -DisableHandler -Description 'Globally disables asynchronous TEPP updates in the background'
Set-DbaConfig -Name 'TabExpansion.Disable.Synchronous' -Value $false -Default -DisableHandler -Description 'Globally disables synchronous TEPP updates, performed whenever connecting o the server. If this is not disabled, it will only perform updates that are fast to perform, in order to minimize performance impact. This may lead to some TEPP functionality loss if asynchronous updates are disabled.'