# Controls the timeout on sql connects
Set-DbatoolsConfig -FullName 'sql.connection.timeout' -Value 15 -Initialize -Validation integerpositive -Handler { [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $args[0] } -Description "The number of seconds before sql server connection attempts are aborted"

# Controls the default database on sql connects
Set-DbatoolsConfig -FullName 'sql.connection.database' -Value $null -Initialize -Validation string -Handler { } -Description "The default database for all connections unless otherwise specified"

# Controls the timeout on sql connects "The network packet size"
Set-DbatoolsConfig -FullName 'sql.connection.packetsize' -Value 4096 -Initialize -Validation integerpositive -Handler { } -Description "Packet size"

# The default network protocol for all connections unless otherwise specified
Set-DbatoolsConfig -FullName 'sql.connection.protocol' -Value $null -Initialize -Validation string -Handler { } -Description "Network protocol"

# Sets connect to use MultiSubnetFailover each time
Set-DbatoolsConfig -FullName 'sql.connection.multisubnetfailover' -Value $false -Initialize -Validation bool -Handler { } -Description "Use MultiSubnetFailover by default"

# How long to wait for results
Set-DbatoolsConfig -FullName 'sql.execution.timeout' -Value 0 -Initialize -Validation integer -Handler { } -Description "Statement timeout"

# Force encryption on the client
# Mandatory per Microsoft's defaults https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqlconnectionstringbuilder.encrypt
Set-DbatoolsConfig -FullName 'sql.connection.encrypt' -Value $true -Initialize -Validation bool -Handler { } -Description "Encrypt connection to server"

# Trust server certificate
Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $false -Initialize -Validation bool -Handler { } -Description "Trust SQL Server certificate"

# Allow trust server certificate fallback
Set-DbatoolsConfig -FullName 'sql.connection.allowtrustcert' -Value $false -Initialize -Validation bool -Handler { } -Description "Attempt connection with TrustServerCertificate if TLS validation fails"

# Enables Always Encryption
Set-DbatoolsConfig -FullName 'sql.alwaysencrypted.enable' -Value $false -Initialize -Validation bool -Handler { } -Description "Not yet implemented"

# Enclave Attesettation URL for the server-side enclave, for use with Always Encrypted with secure enclaves
Set-DbatoolsConfig -FullName 'sql.alwaysencrypted.enclave' -Value $null -Initialize -Validation string -Handler { } -Description "Not yet implemented"

# The default client name
Set-DbatoolsConfig -FullName 'sql.connection.clientname' -Value "dbatools PowerShell module - dbatools.io" -Initialize -Validation string -Handler { } -Description "The client name - defaults to 'dbatools PowerShell module - dbatools.io'"