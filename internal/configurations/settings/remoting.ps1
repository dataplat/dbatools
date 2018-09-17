# Handles PowerShell Session scrapping timeout
Set-DbaConfig -FullName 'PSRemoting.Sessions.ExpirationTimeout' -Value (New-TimeSpan -Minutes 5) -Initialize -Validation timespan -Handler { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionTimeout = $args[0] } -Description 'The timeout interval for PowerShell remote sessions. Dbatools will kill sessions that have been idle for this amount of time.'

# Disables session caching
Set-DbaConfig -FullName 'PSRemoting.Sessions.Enable' -Value $true -Initialize -Validation bool -Handler { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionCacheEnabled = $args[0] } -Description 'Globally enables session caching for PowerShell remoting'