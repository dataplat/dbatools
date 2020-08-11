# Handles PowerShell Session scrapping timeout
Set-DbatoolsConfig -FullName 'PSRemoting.Sessions.ExpirationTimeout' -Value (New-TimeSpan -Minutes 5) -Initialize -Validation timespan -Handler { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionTimeout = $args[0] } -Description 'The timeout interval for PowerShell remote sessions. Dbatools will kill sessions that have been idle for this amount of time.'

# Disables session caching
Set-DbatoolsConfig -FullName 'PSRemoting.Sessions.Enable' -Value $true -Initialize -Validation bool -Handler { [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionCacheEnabled = $args[0] } -Description 'Globally enables session caching for PowerShell remoting'

# New-PSSessionOption
Set-DbatoolsConfig -FullName 'PSRemoting.PsSessionOption.IncludePortInSPN' -Value $false -Initialize -Validation bool -Description 'Changes the value of -IncludePortInSPN parameter used by New-PsSessionOption which is used for dbatools internally when working with PSRemoting.'

# New-PSSession
Set-DbatoolsConfig -FullName 'PSRemoting.PsSession.UseSSL' -Value $false -Initialize -Validation bool -Description 'Changes the value of -UseSSL parameter used by New-PsSession which is used for dbatools internally when working with PSRemoting.'