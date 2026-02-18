function New-DbaConnectionString {
    <#
    .SYNOPSIS
        Creates connection strings for SQL Server instances using PowerShell-friendly parameters

    .DESCRIPTION
        Creates properly formatted SQL Server connection strings without having to manually construct complex connection string syntax. Instead of remembering obscure keywords like "Data Source" or "Initial Catalog", you can use familiar PowerShell parameters like -SqlInstance and -Database.

        This function handles the complexity of connection string building for you, including authentication methods (Windows, SQL Server, Azure AD), encryption settings, timeout values, and Azure SQL Database specifics. It supports both legacy System.Data.SqlClient and modern Microsoft.Data.SqlClient providers.

        Particularly useful when building custom applications, automation scripts, or when you need to generate connection strings for other tools that require them. The function can also extract connection strings from existing SMO server objects for reuse or modification.

        See https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.connectionstring.aspx
        and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnectionstringbuilder.aspx
        and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.aspx

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance. be it Windows or SQL Server. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER AccessToken
        Specifies that Azure Active Directory access token authentication should be used. When specified, the connection string is configured for token-based authentication.
        Use this when connecting to Azure SQL with an access token you've obtained separately from Azure AD authentication flows.

    .PARAMETER AppendConnectionString
        Adds custom connection string parameters to the generated connection string. Authentication parameters cannot be passed this way.
        Use this when you need to add specialized connection parameters like AttachDbFilename, User Instance, or custom driver-specific settings that aren't available through other parameters.

    .PARAMETER ApplicationIntent
        Specifies whether the application workload is read-only or read-write when connecting to an Always On availability group. Valid values are ReadOnly and ReadWrite.
        Use ReadOnly to connect to secondary replicas for reporting queries, which helps offload read traffic from the primary replica.

    .PARAMETER BatchSeparator
        Sets the batch separator for SQL commands. Defaults to "GO" if not specified.
        Change this when working with tools or scripts that use different batch separators, or when "GO" conflicts with your SQL code.

    .PARAMETER ClientName
        Sets the application name that appears in SQL Server monitoring tools like Activity Monitor, Extended Events, and Profiler. Defaults to "dbatools PowerShell module - dbatools.io".
        Use a descriptive name when you need to identify specific scripts or applications in SQL Server logs and monitoring for troubleshooting or performance analysis.

    .PARAMETER Database
        Specifies the initial database to connect to when the connection is established. Sets the Initial Catalog property in the connection string.
        Required for Azure SQL Database connections, and useful for ensuring connections start in the correct database context for your operations.

    .PARAMETER ConnectTimeout
        Sets the number of seconds to wait while attempting to establish a connection before timing out. Valid range is 0 to 2147483647.
        Increase this value for slow networks or when connecting to busy servers. Azure SQL Database connections automatically default to 30 seconds due to network latency considerations.

    .PARAMETER EncryptConnection
        Forces SSL/TLS encryption for the connection to protect data in transit. Automatically enabled for Azure SQL Database connections.
        Enable this for connections over untrusted networks or when your security policy requires encrypted database connections. Requires proper SSL certificates when TrustServerCertificate is false.

    .PARAMETER FailoverPartner
        Specifies the failover partner server name for database mirroring configurations. Limited to 128 characters or less.
        Use this when connecting to databases configured with database mirroring to enable automatic failover if the primary server becomes unavailable. Requires the Database parameter to be specified.

    .PARAMETER IsActiveDirectoryUniversalAuth
        Enables Azure Active Directory Universal Authentication with Multi-Factor Authentication (MFA) support for Azure SQL connections.
        Use this when connecting to Azure SQL Database or Managed Instance with accounts that require MFA or when using Azure AD guest accounts.

    .PARAMETER LockTimeout
        Sets the number of seconds to wait for locks to be released before timing out. Not supported in connection strings - this parameter generates a warning.
        This parameter is included for legacy compatibility but has no effect on the generated connection string.

    .PARAMETER MaxPoolSize
        Sets the maximum number of connections allowed in the connection pool for this connection string. Defaults to 100 if not specified.
        Increase this value for applications with high concurrency requirements, or decrease it to limit resource usage on the SQL Server.

    .PARAMETER MinPoolSize
        Sets the minimum number of connections maintained in the connection pool for this connection string. Defaults to 0 if not specified.
        Set this to a higher value when you want to maintain warm connections for faster subsequent connection requests, especially for frequently accessed databases.

    .PARAMETER MultipleActiveResultSets
        Enables Multiple Active Result Sets (MARS) allowing multiple commands to be executed simultaneously on a single connection.
        Enable this when your application needs to execute multiple queries concurrently on the same connection, such as reading from one result set while executing another query.

    .PARAMETER MultiSubnetFailover
        Enables faster failover detection when connecting to Always On availability groups across different subnets.
        Use this when your availability group replicas are distributed across multiple subnets to reduce connection timeout during failover scenarios.

    .PARAMETER NetworkProtocol
        Forces a specific network protocol for the connection. Valid values include TcpIp, NamedPipes, SharedMemory, and others.
        Use TcpIp for remote connections or NamedPipes for local connections when you need to override default protocol selection or troubleshoot connectivity issues.

    .PARAMETER NonPooledConnection
        Disables connection pooling for this connection, creating a dedicated connection that isn't shared.
        Use this for long-running operations, debugging scenarios, or when you need to ensure complete isolation of the database connection.

    .PARAMETER PacketSize
        Sets the network packet size in bytes for communication with SQL Server. Must be between 512 and 32767 bytes.
        Increase this value for bulk operations or large result sets to improve performance, but ensure the server's network packet size setting can accommodate the specified value.

    .PARAMETER PooledConnectionLifetime
        Sets the maximum lifetime in seconds for pooled connections. Connections older than this value are destroyed when returned to the pool.
        Use this in clustered environments to force load balancing across cluster nodes or to ensure connections don't remain open indefinitely. Zero means no lifetime limit.

    .PARAMETER SqlExecutionModes
        Controls how SQL commands are processed - immediately executed, captured for review, or both. Not supported in connection strings - this parameter generates a warning.
        This parameter is included for legacy compatibility but has no effect on the generated connection string.

    .PARAMETER StatementTimeout
        Sets the number of seconds before SQL commands timeout. Not supported in connection strings - this parameter generates a warning.
        This parameter is included for legacy compatibility but has no effect on the generated connection string. Use the CommandTimeout property on SqlCommand objects instead.

    .PARAMETER TrustServerCertificate
        Bypasses SSL certificate validation when EncryptConnection is enabled. The connection will be encrypted but the server certificate won't be verified.
        Use this for development environments or when connecting to servers with self-signed certificates, but avoid in production due to security risks.

    .PARAMETER WorkstationId
        Sets the workstation identifier that appears in SQL Server system views and logs. Defaults to the local computer name if not specified.
        Use this to identify connections from specific machines or applications when monitoring SQL Server activity or troubleshooting connection issues.

    .PARAMETER Legacy
        Forces the use of the older System.Data.SqlClient provider instead of the modern Microsoft.Data.SqlClient provider.
        Use this only when connecting to applications or tools that specifically require the legacy provider for compatibility reasons.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Connection, Connect, ConnectionString
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaConnectionString

    .OUTPUTS
        System.String

        Returns one or more SQL Server connection strings as plain text strings. Each connection string contains all the connection parameters in standard SQL Server connection string format.

        The output format varies by usage path:
        - When an SMO Server object is passed via pipeline, the existing connection string is extracted and optionally modified with new parameters
        - When SQL instance names are specified, new connection strings are built with the specified parameters
        - When using the legacy code path, connection strings are constructed using SMO ServerConnection objects

        Connection string examples:
        - Windows Authentication: "Data Source=sql2016;Connection Timeout=15;Integrated Security=true;Application Name="custom connection""
        - SQL Authentication: "Data Source=sql2016;User ID=sqladmin;Password=P@ssw0rd;Connection Timeout=15;Application Name="custom connection""
        - Azure SQL with AD: "Data Source=tcp:mydb.database.windows.net,1433;Initial Catalog=db;User ID=user@domain.onmicrosoft.com;Password=pwd;MultipleActiveResultSets=False;Connect Timeout=30;Encrypt=Mandatory;TrustServerCertificate=False;Authentication=Active Directory Password;Application Name="custom connection""

        The returned string can be used directly with SqlClient, ADO.NET applications, or any tool that accepts SQL Server connection strings. Use `Write-Host` to display in a terminal or pipe to other commands that accept connection strings.

    .EXAMPLE
        PS C:\> New-DbaConnectionString -SqlInstance sql2014

        Creates a connection string that connects using Windows Authentication

    .EXAMPLE
        PS C:\> Connect-DbaInstance -SqlInstance sql2016 | New-DbaConnectionString

        Builds a connected SMO object using Connect-DbaInstance then extracts and displays the connection string

    .EXAMPLE
        PS C:\> $wincred = Get-Credential ad\sqladmin
        PS C:\> New-DbaConnectionString -SqlInstance sql2014 -Credential $wincred

        Creates a connection string that connects using alternative Windows credentials

    .EXAMPLE
        PS C:\> $sqlcred = Get-Credential sqladmin
        PS C:\> $server = New-DbaConnectionString -SqlInstance sql2014 -Credential $sqlcred

        Login to sql2014 as SQL login sqladmin.

    .EXAMPLE
        PS C:\> $connstring = New-DbaConnectionString -SqlInstance mydb.database.windows.net -SqlCredential me@myad.onmicrosoft.com -Database db

        Creates a connection string for an Azure Active Directory login to Azure SQL db. Output looks like this:
        Data Source=TCP:mydb.database.windows.net,1433;Initial Catalog=db;User ID=me@myad.onmicrosoft.com;Password=fakepass;MultipleActiveResultSets=False;Connect Timeout=30;Encrypt=True;TrustServerCertificate=False;Application Name="dbatools PowerShell module - dbatools.io";Authentication="Active Directory Password"

    .EXAMPLE
        PS C:\> $server = New-DbaConnectionString -SqlInstance sql2014 -ClientName "mah connection"

        Creates a connection string that connects using Windows Authentication and uses the client name "mah connection". So when you open up profiler or use extended events, you can search for "mah connection".

    .EXAMPLE
        PS C:\> $server = New-DbaConnectionString -SqlInstance sql2014 -AppendConnectionString "Packet Size=4096;AttachDbFilename=C:\MyFolder\MyDataFile.mdf;User Instance=true;"

        Creates a connection string that connects to sql2014 using Windows Authentication, then it sets the packet size (this can also be done via -PacketSize) and other connection attributes.

    .EXAMPLE
        PS C:\> $server = New-DbaConnectionString -SqlInstance sql2014 -NetworkProtocol TcpIp -MultiSubnetFailover

        Creates a connection string with Windows Authentication that uses TCPIP and has MultiSubnetFailover enabled.

    .EXAMPLE
        PS C:\> $connstring = New-DbaConnectionString sql2016 -ApplicationIntent ReadOnly

        Creates a connection string with ReadOnly ApplicationIntent.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer", "Server", "DataSource")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("SqlCredential")]
        [PSCredential]$Credential,
        [string]$AccessToken,
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$ApplicationIntent,
        [string]$BatchSeparator,
        [string]$ClientName = "custom connection",
        [int]$ConnectTimeout,
        [string]$Database,
        [switch]$EncryptConnection = (Get-DbatoolsConfigValue -FullName 'sql.connection.encrypt'),
        [string]$FailoverPartner,
        [switch]$IsActiveDirectoryUniversalAuth,
        [int]$LockTimeout,
        [int]$MaxPoolSize,
        [int]$MinPoolSize,
        [switch]$MultipleActiveResultSets,
        [switch]$MultiSubnetFailover,
        [ValidateSet('TcpIp', 'NamedPipes', 'Multiprotocol', 'AppleTalk', 'BanyanVines', 'Via', 'SharedMemory', 'NWLinkIpxSpx')]
        [string]$NetworkProtocol,
        [switch]$NonPooledConnection,
        [int]$PacketSize,
        [int]$PooledConnectionLifetime,
        [ValidateSet('CaptureSql', 'ExecuteAndCaptureSql', 'ExecuteSql')]
        [string]$SqlExecutionModes,
        [int]$StatementTimeout,
        [switch]$TrustServerCertificate = (Get-DbatoolsConfigValue -FullName 'sql.connection.trustcert'),
        [string]$WorkstationId,
        [switch]$Legacy,
        [string]$AppendConnectionString
    )
    begin {
        function Test-Azure {
            Param (
                [DbaInstanceParameter[]]$SqlInstance
            )
            if ($SqlInstance.ComputerName -match $AzureDomain) {
                Write-Message -Level Debug -Message "Test for Azure is positive"
                return $true
            } else {
                Write-Message -Level Debug -Message "Test for Azure is negative"
                return $false
            }
        }
    }
    process {
        foreach ($instance in $SqlInstance) {

            <#
            The new code path (formerly known as experimental) is now the default.
            To have a quick way to switch back in case any problems occur, the switch "legacy" is introduced: Set-DbatoolsConfig -FullName sql.connection.legacy -Value $true
            All the sub paths inside the following if clause will end with a continue, so the normal code path is not used.
            #>
            if (-not (Get-DbatoolsConfigValue -FullName sql.connection.legacy)) {
                <#
                Maybe more docs...
                #>
                Write-Message -Level Debug -Message "We have to build a connect string, using these parameters: $($PSBoundParameters.Keys)"

                # Test for unsupported parameters
                if (Test-Bound -ParameterName 'LockTimeout') {
                    Write-Message -Level Warning -Message "Parameter LockTimeout not supported, because it is not part of a connection string."
                }
                # TODO: That can be added to the Data Source - but why?
                #if (Test-Bound -ParameterName 'NetworkProtocol') {
                #    Write-Message -Level Warning -Message "Parameter NetworkProtocol not supported, because it is not part of a connection string."
                #}
                if (Test-Bound -ParameterName 'StatementTimeout') {
                    Write-Message -Level Warning -Message "Parameter StatementTimeout not supported, because it is not part of a connection string."
                }
                if (Test-Bound -ParameterName 'SqlExecutionModes') {
                    Write-Message -Level Warning -Message "Parameter SqlExecutionModes not supported, because it is not part of a connection string."
                }

                # Set defaults like in Connect-DbaInstance
                if (Test-Bound -Not -ParameterName 'Database') {
                    $Database = (Get-DbatoolsConfigValue -FullName 'sql.connection.database')
                }
                if (Test-Bound -Not -ParameterName 'ClientName') {
                    $ClientName = (Get-DbatoolsConfigValue -FullName 'sql.connection.clientname')
                }
                if (Test-Bound -Not -ParameterName 'ConnectTimeout') {
                    $ConnectTimeout = ([Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout)
                }
                if (Test-Bound -Not -ParameterName 'NetworkProtocol') {
                    $np = (Get-DbatoolsConfigValue -FullName 'sql.connection.protocol')
                    if ($np) {
                        $NetworkProtocol = $np
                    }
                }
                if (Test-Bound -Not -ParameterName 'PacketSize') {
                    $PacketSize = (Get-DbatoolsConfigValue -FullName 'sql.connection.packetsize')
                }
                if (Test-Bound -Not -ParameterName 'TrustServerCertificate') {
                    $TrustServerCertificate = (Get-DbatoolsConfigValue -FullName 'sql.connection.trustcert')
                }
                # TODO: Maybe put this in a config item:
                $AzureDomain = "database.windows.net"

                # Rename credential parameter to align with other commands, later rename parameter
                $SqlCredential = $Credential

                if ($Pscmdlet.ShouldProcess($instance, "Making a new Connection String")) {
                    if ($instance.Type -like "Server") {
                        Write-Message -Level Debug -Message "server object passed in, connection string is: $($instance.InputObject.ConnectionContext.ConnectionString)"
                        if ($Legacy) {
                            $converted = $instance.InputObject.ConnectionContext.ConnectionString | Convert-ConnectionString
                            $connStringBuilder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $converted
                        } else {
                            $connStringBuilder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $instance.InputObject.ConnectionContext.ConnectionString
                        }
                        # In Azure, check for a database change
                        if ((Test-Azure -SqlInstance $instance) -and $Database) {
                            $connStringBuilder['Initial Catalog'] = $Database
                        }
                        $connstring = $connStringBuilder.ConnectionString
                        # TODO: Should we check the other parameters and change the connection string accordingly?
                    } else {
                        if ($Legacy) {
                            $connStringBuilder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder
                        } else {
                            $connStringBuilder = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder
                        }
                        $connStringBuilder['Data Source'] = $instance.FullSmoName
                        if ($ApplicationIntent) { $connStringBuilder['ApplicationIntent'] = $ApplicationIntent }
                        if ($ClientName) { $connStringBuilder['Application Name'] = $ClientName }
                        if ($ConnectTimeout) { $connStringBuilder['Connect Timeout'] = $ConnectTimeout }
                        if ($Database) { $connStringBuilder['Initial Catalog'] = $Database }
                        # https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqlconnectionstringbuilder.encrypt?view=sqlclient-dotnet-standard-5.0
                        if ($instance -notmatch "localdb") {
                            if ($EncryptConnection) { $connStringBuilder['Encrypt'] = 'Mandatory' }
                            if (-not $EncryptConnection -and (Test-Bound -ParameterName 'EncryptConnection')) { $connStringBuilder['Encrypt'] = 'False' }
                        } else {
                            Write-Message -Level Verbose -Message "localdb detected, skipping unsupported keyword 'Encryption'"
                        }
                        if ($FailoverPartner) { $connStringBuilder['Failover Partner'] = $FailoverPartner }
                        if ($MaxPoolSize) { $connStringBuilder['Max Pool Size'] = $MaxPoolSize }
                        if ($MinPoolSize) { $connStringBuilder['Min Pool Size'] = $MinPoolSize }
                        if ($MultipleActiveResultSets) { $connStringBuilder['MultipleActiveResultSets'] = $true } else { $connStringBuilder['MultipleActiveResultSets'] = $false }
                        if ($MultiSubnetFailover) { $connStringBuilder['MultiSubnetFailover'] = $true }
                        if ($NonPooledConnection) { $connStringBuilder['Pooling'] = $false }
                        if ($PacketSize) { $connStringBuilder['Packet Size'] = $PacketSize }
                        if ($PooledConnectionLifetime) { $connStringBuilder['Load Balance Timeout'] = $PooledConnectionLifetime }
                        if ($TrustServerCertificate) { $connStringBuilder['TrustServerCertificate'] = $true } else { $connStringBuilder['TrustServerCertificate'] = $false }
                        if ($WorkstationId) { $connStringBuilder['Workstation Id'] = $WorkstationId }
                        if ($SqlCredential) {
                            Write-Message -Level Debug -Message "We have a SqlCredential"
                            $username = ($SqlCredential.UserName).TrimStart("\")
                            # support both ad\username and username@ad
                            if ($username -like "*\*") {
                                $domain, $login = $username.Split("\")
                                $username = "$login@$domain"
                            }
                            $connStringBuilder['User ID'] = $username
                            $connStringBuilder['Password'] = $SqlCredential.GetNetworkCredential().Password
                            if ((Test-Azure -SqlInstance $instance) -and ($username -like "*@*")) {
                                Write-Message -Level Debug -Message "We connect to Azure with Azure AD account, so adding Authentication=Active Directory Password"
                                $connStringBuilder['Authentication'] = 'Active Directory Password'
                            }
                        } else {
                            Write-Message -Level Debug -Message "We don't have a SqlCredential"
                            if (Test-Azure -SqlInstance $instance) {
                                Write-Message -Level Debug -Message "We connect to Azure, so adding Authentication=Active Directory Integrated"
                                $connStringBuilder['Authentication'] = 'Active Directory Integrated'
                            } else {
                                Write-Message -Level Debug -Message "We don't connect to Azure, so setting Integrated Security=True"
                                $connStringBuilder['Integrated Security'] = $true
                            }
                        }

                        # special config for Azure
                        if (Test-Azure -SqlInstance $instance) {
                            if (Test-Bound -Not -ParameterName ConnectTimeout) {
                                $connStringBuilder['Connect Timeout'] = 30
                            }
                            $connStringBuilder['Encrypt'] = $true
                            # Why adding tcp:?
                            #$connStringBuilder['Data Source'] = "tcp:$($instance.ComputerName),$($instance.Port)"
                        }
                        if ($Legacy) {
                            $connstring = $connStringBuilder.ConnectionString
                        } else {
                            $connstring = $connStringBuilder.ToString()
                        }
                        if ($AppendConnectionString) {
                            # TODO: Check if new connection string is still valid
                            $connstring = "$connstring;$AppendConnectionString"
                        }
                    }
                    $connstring
                    continue
                }
            }
            <#
            This is the end of the new default code path.
            All session with the configuration "sql.connection.legacy" set to $true will run through the following code.
            To use the legacy code path: Set-DbatoolsConfig -FullName sql.connection.legacy -Value $true
            #>

            Write-Message -Level Debug -Message "sql.connection.legacy is used"

            if ($Pscmdlet.ShouldProcess($instance, "Making a new Connection String")) {
                if ($instance.ComputerName -match "database\.windows\.net" -or $instance.InputObject.ComputerName -match "database\.windows\.net") {
                    if ($instance.InputObject.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) {
                        $connstring = $instance.InputObject.ConnectionContext.ConnectionString
                        if ($Database) {
                            $olddb = $connstring -split ';' | Where-Object { $_.StartsWith("Initial Catalog") }
                            $newdb = "Initial Catalog=$Database"
                            if ($olddb) {
                                $connstring = $connstring.Replace("$olddb", "$newdb")
                            } else {
                                $connstring = "$connstring;$newdb;"
                            }
                        }
                        $connstring
                        continue
                    } else {
                        $isAzure = $true

                        if (-not (Test-Bound -ParameterName ConnectTimeout)) {
                            $ConnectTimeout = 30
                        }

                        if (-not (Test-Bound -ParameterName ClientName)) {
                            $ClientName = "dbatools PowerShell module - dbatools.io"

                        }
                        $EncryptConnection = $true
                        $instance = [DbaInstanceParameter]"tcp:$($instance.ComputerName),$($instance.Port)"
                    }
                }

                if ($instance.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) {
                    return $instance.ConnectionContext.ConnectionString
                } else {
                    $guid = [System.Guid]::NewGuid()
                    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $guid

                    if ($AppendConnectionString) {
                        $connstring = $server.ConnectionContext.ConnectionString
                        $server.ConnectionContext.ConnectionString = "$connstring;$appendconnectionstring"
                        $server.ConnectionContext.ConnectionString
                    } else {

                        $server.ConnectionContext.ApplicationName = $ClientName
                        if ($BatchSeparator) { $server.ConnectionContext.BatchSeparator = $BatchSeparator }
                        if ($ConnectTimeout) { $server.ConnectionContext.ConnectTimeout = $ConnectTimeout }
                        if ($Database) { $server.ConnectionContext.DatabaseName = $Database }
                        if ($EncryptConnection) { $server.ConnectionContext.EncryptConnection = $true }
                        if ($IsActiveDirectoryUniversalAuth) { $server.ConnectionContext.IsActiveDirectoryUniversalAuth = $true }
                        if ($LockTimeout) { $server.ConnectionContext.LockTimeout = $LockTimeout }
                        if ($MaxPoolSize) { $server.ConnectionContext.MaxPoolSize = $MaxPoolSize }
                        if ($MinPoolSize) { $server.ConnectionContext.MinPoolSize = $MinPoolSize }
                        if ($MultipleActiveResultSets) { $server.ConnectionContext.MultipleActiveResultSets = $true }
                        if ($NetworkProtocol) { $server.ConnectionContext.NetworkProtocol = $NetworkProtocol }
                        if ($NonPooledConnection) { $server.ConnectionContext.NonPooledConnection = $true }
                        if ($PacketSize) { $server.ConnectionContext.PacketSize = $PacketSize }
                        if ($PooledConnectionLifetime) { $server.ConnectionContext.PooledConnectionLifetime = $PooledConnectionLifetime }
                        if ($StatementTimeout) { $server.ConnectionContext.StatementTimeout = $StatementTimeout }
                        if ($SqlExecutionModes) { $server.ConnectionContext.SqlExecutionModes = $SqlExecutionModes }
                        if ($TrustServerCertificate) { $server.ConnectionContext.TrustServerCertificate = $true }
                        if ($WorkstationId) { $server.ConnectionContext.WorkstationId = $WorkstationId }

                        if ($null -ne $Credential.username) {
                            $username = ($Credential.username).TrimStart("\")

                            if ($username -like "*\*") {
                                $username = $username.Split("\")[1]
                                $server.ConnectionContext.LoginSecure = $true
                                $server.ConnectionContext.ConnectAsUser = $true
                                $server.ConnectionContext.ConnectAsUserName = $username
                                $server.ConnectionContext.ConnectAsUserPassword = ($Credential).GetNetworkCredential().Password
                            } else {
                                $server.ConnectionContext.LoginSecure = $false
                                $server.ConnectionContext.set_Login($username)
                                $server.ConnectionContext.set_SecurePassword($Credential.Password)
                            }
                        }

                        $connstring = $server.ConnectionContext.ConnectionString
                        if ($MultiSubnetFailover) { $connstring = "$connstring;MultiSubnetFailover=True" }
                        if ($FailoverPartner) { $connstring = "$connstring;Failover Partner=$FailoverPartner" }
                        if ($ApplicationIntent) { $connstring = "$connstring;ApplicationIntent=$ApplicationIntent;" }

                        if ($isAzure) {
                            if ($Credential) {
                                if ($Credential.UserName -like "*\*" -or $Credential.UserName -like "*@*") {
                                    $connstring = "$connstring;Authentication=`"Active Directory Password`""
                                } else {
                                    $username = ($Credential.username).TrimStart("\")
                                    $server.ConnectionContext.LoginSecure = $false
                                    $server.ConnectionContext.set_Login($username)
                                    $server.ConnectionContext.set_SecurePassword($Credential.Password)
                                }
                            } else {
                                $connstring = $connstring.Replace("Integrated Security=True;", "Persist Security Info=True;")
                                if (-not $AccessToken) {
                                    $connstring = "$connstring;Authentication=`"Active Directory Integrated`""
                                }
                            }
                        }

                        if ($connstring -ne $server.ConnectionContext.ConnectionString) {
                            $server.ConnectionContext.ConnectionString = $connstring
                        }

                        ($server.ConnectionContext.ConnectionString).Replace($guid, $instance)
                    }
                }
            }
        }
    }
}