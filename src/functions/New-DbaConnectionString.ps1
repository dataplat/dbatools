function New-DbaConnectionString {
    <#
    .SYNOPSIS
        Builds or extracts a SQL Server Connection String

    .DESCRIPTION
        Builds or extracts a SQL Server Connection String. Note that dbatools-style syntax is used.

        So you do not need to specify "Data Source", you can just specify -SqlInstance and -SqlCredential and we'll handle it for you.

        This is the simplified PowerShell approach to connection string building. See examples for more info.

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
        Basically tells the connection string to ignore authentication. Does not include the AccessToken in the resulting connecstring.

    .PARAMETER AppendConnectionString
        Appends to the current connection string. Note that you cannot pass authentication information using this method. Use -SqlInstance and, optionally, -SqlCredential to set authentication information.

    .PARAMETER ApplicationIntent
        Declares the application workload type when connecting to a server. Possible values are ReadOnly and ReadWrite.

    .PARAMETER BatchSeparator
        By default, this is "GO"

    .PARAMETER ClientName
        By default, this command sets the client's ApplicationName property to "dbatools PowerShell module - dbatools.io". If you're doing anything that requires profiling, you can look for this client name. Using -ClientName allows you to set your own custom client application name.

    .PARAMETER Database
        Database name

    .PARAMETER ConnectTimeout
        The length of time (in seconds) to wait for a connection to the server before terminating the attempt and generating an error.

        Valid values are greater than or equal to 0 and less than or equal to 2147483647.

        When opening a connection to a Azure SQL Database, set the connection timeout to 30 seconds.

    .PARAMETER EncryptConnection
        When true, SQL Server uses SSL encryption for all data sent between the client and server if the server has a certificate installed. Recognized values are true, false, yes, and no. For more information, see Connection String Syntax.

        Beginning in .NET Framework 4.5, when TrustServerCertificate is false and Encrypt is true, the server name (or IP address) in a SQL Server SSL certificate must exactly match the server name (or IP address) specified in the connection string. Otherwise, the connection attempt will fail. For information about support for certificates whose subject starts with a wildcard character (*), see Accepted wildcards used by server certificates for server authentication.

    .PARAMETER FailoverPartner
        The name of the failover partner server where database mirroring is configured.

        If the value of this key is "", then Initial Catalog must be present, and its value must not be "".

        The server name can be 128 characters or less.

        If you specify a failover partner but the failover partner server is not configured for database mirroring and the primary server (specified with the Server keyword) is not available, then the connection will fail.

        If you specify a failover partner and the primary server is not configured for database mirroring, the connection to the primary server (specified with the Server keyword) will succeed if the primary server is available.

    .PARAMETER IsActiveDirectoryUniversalAuth
        Azure related

    .PARAMETER LockTimeout
        Sets the time in seconds required for the connection to time out when the current transaction is locked.

    .PARAMETER MaxPoolSize
        Sets the maximum number of connections allowed in the connection pool for this specific connection string.

    .PARAMETER MinPoolSize
        Sets the minimum number of connections allowed in the connection pool for this specific connection string.

    .PARAMETER MultipleActiveResultSets
        When used, an application can maintain multiple active result sets (MARS). When false, an application must process or cancel all result sets from one batch before it can execute any other batch on that connection.

    .PARAMETER MultiSubnetFailover
        If your application is connecting to an AlwaysOn availability group (AG) on different subnets, setting MultiSubnetFailover provides faster detection of and connection to the (currently) active server. For more information about SqlClient support for Always On Availability Groups

    .PARAMETER NetworkProtocol
        Connect explicitly using 'TcpIp','NamedPipes','Multiprotocol','AppleTalk','BanyanVines','Via','SharedMemory' and 'NWLinkIpxSpx'

    .PARAMETER NonPooledConnection
        Request a non-pooled connection

    .PARAMETER PacketSize
        Sets the size in bytes of the network packets used to communicate with an instance of SQL Server. Must match at server.

    .PARAMETER PooledConnectionLifetime
        When a connection is returned to the pool, its creation time is compared with the current time, and the connection is destroyed if that time span (in seconds) exceeds the value specified by Connection Lifetime. This is useful in clustered configurations to force load balancing between a running server and a server just brought online.

        A value of zero (0) causes pooled connections to have the maximum connection timeout.

    .PARAMETER SqlExecutionModes
        The SqlExecutionModes enumeration contains values that are used to specify whether the commands sent to the referenced connection to the server are executed immediately or saved in a buffer.

        Valid values include CaptureSql, ExecuteAndCaptureSql and ExecuteSql.

    .PARAMETER StatementTimeout
        Sets the number of seconds a statement is given to run before failing with a time-out error.

    .PARAMETER TrustServerCertificate
        Sets a value that indicates whether the channel will be encrypted while bypassing walking the certificate chain to validate trust.

    .PARAMETER WorkstationId
        Sets the name of the workstation connecting to SQL Server.

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
        [switch]$EncryptConnection,
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
        [switch]$TrustServerCertificate,
        [string]$WorkstationId,
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
            In order to be able to test new functions in various environments, the switch "experimental" is introduced.
            This switch can be set with "Set-DbatoolsConfig -FullName sql.connection.experimental -Value $true" for the active session
            and within this function leads to the following code path being used.
            All the sub paths inside the following if clause will end with a continue, so the normal code path is not used.
            #>
            if (Get-DbatoolsConfigValue -FullName sql.connection.experimental) {
                <#
                Maybe more docs...
                #>
                Write-Message -Level Debug -Message "sql.connection.experimental is used"

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
                    $ConnectTimeout = ([Sqlcollaborative.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout)
                }
                if (Test-Bound -Not -ParameterName 'EncryptConnection') {
                    $EncryptConnection = (Get-DbatoolsConfigValue -FullName 'sql.connection.encrypt')
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
                        $connStringBuilder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $instance.InputObject.ConnectionContext.ConnectionString
                        # In Azure, check for a database change
                        if ((Test-Azure -SqlInstance $instance) -and $Database) {
                            $connStringBuilder['Initial Catalog'] = $Database
                        }
                        $connstring = $connStringBuilder.ConnectionString
                        # TODO: Should we check the other parameters and change the connection string accordingly?
                    } else {
                        $connStringBuilder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder
                        $connStringBuilder['Data Source'] = $instance.FullSmoName
                        if ($ApplicationIntent) { $connStringBuilder['ApplicationIntent'] = $ApplicationIntent }
                        if ($ClientName) { $connStringBuilder['Application Name'] = $ClientName }
                        if ($ConnectTimeout) { $connStringBuilder['Connect Timeout'] = $ConnectTimeout }
                        if ($Database) { $connStringBuilder['Initial Catalog'] = $Database }
                        if ($EncryptConnection) { $connStringBuilder['Encrypt'] = $true } else { $connStringBuilder['Encrypt'] = $false }
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

                        $connstring = $connStringBuilder.ConnectionString
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
            This is the end of the experimental code path.
            All session without the configuration "sql.connection.experimental" set to $true will run through the following code.
            #>

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