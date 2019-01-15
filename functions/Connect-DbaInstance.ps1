function Connect-DbaInstance {
    <#
    .SYNOPSIS
        Creates a robust SMO SQL Server object.

    .DESCRIPTION
        This command is robust because it initializes properties that do not cause enumeration by default. It also supports both Windows and SQL Server authentication methods, and detects which to use based upon the provided credentials.

        By default, this command also sets the connection's ApplicationName property  to "dbatools PowerShell module - dbatools.io - custom connection". If you're doing anything that requires profiling, you can look for this client name.

        Alternatively, you can pass in whichever client name you'd like using the -ClientName parameter. There are a ton of other parameters for you to explore as well.

        See https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.connectionstring.aspx
        and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnectionstringbuilder.aspx,
        and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.aspx

        To execute SQL commands, you can use $server.ConnectionContext.ExecuteReader($sql) or $server.Databases['master'].ExecuteNonQuery($sql)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server.

    .PARAMETER AccessToken
        Gets or sets the access token for the connection.

    .PARAMETER AppendConnectionString
        Appends to the current connection string. Note that you cannot pass authentication information using this method. Use -SqlInstance and optionally -SqlCredential to set authentication information.

    .PARAMETER ApplicationIntent
        Declares the application workload type when connecting to a server.

        Valid values are "ReadOnly" and "ReadWrite".

    .PARAMETER BatchSeparator
        A string to separate groups of SQL statements being executed. By default, this is "GO".

    .PARAMETER ClientName
        By default, this command sets the client's ApplicationName property to "dbatools PowerShell module - dbatools.io - custom connection" if you're doing anything that requires profiling, you can look for this client name. Using -ClientName allows you to set your own custom client application name.

    .PARAMETER ConnectTimeout
        The length of time (in seconds) to wait for a connection to the server before terminating the attempt and generating an error.

        Valid values are integers between 0 and 2147483647.

        When opening a connection to a Azure SQL Database, set the connection timeout to 30 seconds.

    .PARAMETER EncryptConnection
        If this switch is enabled, SQL Server uses SSL encryption for all data sent between the client and server if the server has a certificate installed.

        For more information, see Connection String Syntax. https://docs.microsoft.com/en-us/dotnet/framework/data/adonet/connection-string-syntax

        Beginning in .NET Framework 4.5, when TrustServerCertificate is false and Encrypt is true, the server name (or IP address) in a SQL Server SSL certificate must exactly match the server name (or IP address) specified in the connection string. Otherwise, the connection attempt will fail. For information about support for certificates whose subject starts with a wildcard character (*), see Accepted wildcards used by server certificates for server authentication. https://support.microsoft.com/en-us/help/258858/accepted-wildcards-used-by-server-certificates-for-server-authenticati

    .PARAMETER FailoverPartner
        The name of the failover partner server where database mirroring is configured.

        If the value of this key is "" (an empty string), then Initial Catalog must be present in the connection string, and its value must not be "".

        The server name can be 128 characters or less.

        If you specify a failover partner but the failover partner server is not configured for database mirroring and the primary server (specified with the Server keyword) is not available, then the connection will fail.

        If you specify a failover partner and the primary server is not configured for database mirroring, the connection to the primary server (specified with the Server keyword) will succeed if the primary server is available.

    .PARAMETER LockTimeout
        Sets the time in seconds required for the connection to time out when the current transaction is locked.

    .PARAMETER MaxPoolSize
        Sets the maximum number of connections allowed in the connection pool for this specific connection string.

    .PARAMETER MinPoolSize
        Sets the minimum number of connections allowed in the connection pool for this specific connection string.

    .PARAMETER MultipleActiveResultSets
        If this switch is enabled, an application can maintain multiple active result sets (MARS).

        If this switch is not enabled, an application must process or cancel all result sets from one batch before it can execute any other batch on that connection.

    .PARAMETER MultiSubnetFailover
        If this switch is enabled, and your application is connecting to an AlwaysOn availability group (AG) on different subnets, detection of and connection to the currently active server will be faster. For more information about SqlClient support for Always On Availability Groups, see https://docs.microsoft.com/en-us/dotnet/framework/data/adonet/sql/sqlclient-support-for-high-availability-disaster-recovery

    .PARAMETER NetworkProtocol
        Explicitly sets the network protocol used to connect to the server.

        Valid values are "TcpIp","NamedPipes","Multiprotocol","AppleTalk","BanyanVines","Via","SharedMemory" and "NWLinkIpxSpx"

    .PARAMETER NonPooledConnection
        If this switch is enabled, a non-pooled connection will be requested.

    .PARAMETER PacketSize
        Sets the size in bytes of the network packets used to communicate with an instance of SQL Server. Must match at server.

    .PARAMETER PooledConnectionLifetime
        When a connection is returned to the pool, its creation time is compared with the current time and the connection is destroyed if that time span (in seconds) exceeds the value specified by Connection Lifetime. This is useful in clustered configurations to force load balancing between a running server and a server just brought online.

        A value of zero (0) causes pooled connections to have the maximum connection timeout.

    .PARAMETER SqlExecutionModes
        The SqlExecutionModes enumeration contains values that are used to specify whether the commands sent to the referenced connection to the server are executed immediately or saved in a buffer.

        Valid values include "CaptureSql", "ExecuteAndCaptureSql" and "ExecuteSql".

    .PARAMETER StatementTimeout
        Sets the number of seconds a statement is given to run before failing with a timeout error.

    .PARAMETER TrustServerCertificate
        When this switch is enabled, the channel will be encrypted while bypassing walking the certificate chain to validate trust.

    .PARAMETER WorkstationId
        Sets the name of the workstation connecting to SQL Server.

    .PARAMETER SqlConnectionOnly
        Instead of returning a rich SMO server object, this command will only return a SqlConnection object when setting this switch.

    .PARAMETER DisableException
        By default in most of our commands, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This command, however, gifts you  with "sea of red" exceptions, by default, because it is useful for advanced scripting.

        Using this switch turns our "nice by default" feature on which makes errors into pretty warnings.

    .NOTES
        Tags: Connect, Connection
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Connect-DbaInstance

    .EXAMPLE
        PS C:\> Connect-DbaInstance -SqlInstance sql2014

        Creates an SMO Server object that connects using Windows Authentication

    .EXAMPLE
        PS C:\> $wincred = Get-Credential ad\sqladmin
        PS C:\> Connect-DbaInstance -SqlInstance sql2014 -SqlCredential $wincred

        Creates an SMO Server object that connects using alternative Windows credentials

    .EXAMPLE
        PS C:\> $sqlcred = Get-Credential sqladmin
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -SqlCredential $sqlcred

        Login to sql2014 as SQL login sqladmin.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -ClientName "my connection"

        Creates an SMO Server object that connects using Windows Authentication and uses the client name "my connection". So when you open up profiler or use extended events, you can search for "my connection".

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -AppendConnectionString "Packet Size=4096;AttachDbFilename=C:\MyFolder\MyDataFile.mdf;User Instance=true;"

        Creates an SMO Server object that connects to sql2014 using Windows Authentication, then it sets the packet size (this can also be done via -PacketSize) and other connection attributes.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -NetworkProtocol TcpIp -MultiSubnetFailover

        Creates an SMO Server object that connects using Windows Authentication that uses TCP/IP and has MultiSubnetFailover enabled.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance sql2016 -ApplicationIntent ReadOnly

        Connects with ReadOnly ApplicationIntent.

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [string]$AccessToken,
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$ApplicationIntent,
        [string]$BatchSeparator,
        [string]$ClientName = "dbatools PowerShell module - dbatools.io - custom connection",
        [int]$ConnectTimeout = ([Sqlcollaborative.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout),
        [switch]$EncryptConnection,
        [string]$FailoverPartner,
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
        [string]$AppendConnectionString,
        [switch]$SqlConnectionOnly,
        [switch]$DisableException
    )
    begin {
        if ($DisableException) {
            $EnableException = $false
        } else {
            $EnableException = $true
        }

        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Connect-DbaServer
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Get-DbaInstance

        $loadedSmoVersion = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
            $_.Fullname -like "Microsoft.SqlServer.SMO,*"
        }

        if ($loadedSmoVersion) {
            $loadedSmoVersion = $loadedSmoVersion | ForEach-Object {
                if ($_.Location -match "__") {
                    ((Split-Path (Split-Path $_.Location) -Leaf) -split "__")[0]
                } else {
                    ((Get-ChildItem -Path $_.Location).VersionInfo.ProductVersion)
                }
            }
        }
        #'PrimaryFilePath' seems the culprit for slow SMO on databases
        $Fields2000_Db = 'Collation', 'CompatibilityLevel', 'CreateDate', 'ID', 'IsAccessible', 'IsFullTextEnabled', 'IsSystemObject', 'IsUpdateable', 'LastBackupDate', 'LastDifferentialBackupDate', 'LastLogBackupDate', 'Name', 'Owner', 'ReadOnly', 'RecoveryModel', 'ReplicationOptions', 'Status', 'Version'
        $Fields200x_Db = $Fields2000_Db + @('BrokerEnabled', 'DatabaseSnapshotBaseName', 'IsMirroringEnabled', 'Trustworthy')
        $Fields201x_Db = $Fields200x_Db + @('ActiveConnections', 'AvailabilityDatabaseSynchronizationState', 'AvailabilityGroupName', 'ContainmentType', 'EncryptionEnabled')

        $Fields2000_Login = 'CreateDate', 'DateLastModified', 'DefaultDatabase', 'DenyWindowsLogin', 'IsSystemObject', 'Language', 'LanguageAlias', 'LoginType', 'Name', 'Sid', 'WindowsLoginAccessType'
        $Fields200x_Login = $Fields2000_Login + @('AsymmetricKey', 'Certificate', 'Credential', 'ID', 'IsDisabled', 'IsLocked', 'IsPasswordExpired', 'MustChangePassword', 'PasswordExpirationEnabled', 'PasswordPolicyEnforced')
        $Fields201x_Login = $Fields200x_Login + @('PasswordHashAlgorithm')
    }
    process {
        foreach ($instance in $SqlInstance) {
            #region Safely convert input into instance parameters
            if ($instance.GetType() -eq [Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter]) {
                [DbaInstanceParameter]$ConvertedSqlInstance = $instance
                if ($ConvertedSqlInstance.Type -like "SqlConnection") {
                    [DbaInstanceParameter]$ConvertedSqlInstance = New-Object Microsoft.SqlServer.Management.Smo.Server($ConvertedSqlInstance.InputObject)
                }
            } else {
                [DbaInstanceParameter]$ConvertedSqlInstance = [DbaInstanceParameter]($instance | Select-Object -First 1)

                if ($instance.Count -gt 1) {
                    Write-Message -Level Warning -EnableException $true -Message "More than on server was specified when calling Connect-SqlInstance from $((Get-PSCallStack)[1].Command)"
                }
            }
            #endregion Safely convert input into instance parameters
            if ($instance.Type -like "Server") {
                if ($instance.InputObject.ConnectionContext.IsOpen -eq $false) {
                    $instance.InputObject.ConnectionContext.Connect()
                }
                if ($SqlConnectionOnly) {
                    return $instance.InputObject.ConnectionContext.SqlConnectionObject
                } else {
                    return $instance.InputObject
                }
            }
            if ($instance.Type -like "SqlConnection") {
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server($instance.InputObject)

                if ($server.ConnectionContext.IsOpen -eq $false) {
                    $server.ConnectionContext.Connect()
                }
                if ($SqlConnectionOnly) {
                    return $server.ConnectionContext.SqlConnectionObject
                } else {
                    if (-not $server.ComputerName) {
                        if (-not $server.NetName -or $SqlInstance -match '\.') {
                            $parsedcomputername = $ConvertedSqlInstance.ComputerName
                        } else {
                            $parsedcomputername = $server.NetName
                        }
                        Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $parsedcomputername -Force
                    }
                    return $server
                }
            }

            if ($instance.IsConnectionString) {
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server($instance.InputObject)
            } else {
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server $instance.FullSmoName
            }

            if ($AppendConnectionString) {
                $connstring = $server.ConnectionContext.ConnectionString
                $server.ConnectionContext.ConnectionString = "$connstring;$appendconnectionstring"
                $server.ConnectionContext.Connect()
            } else {

                $server.ConnectionContext.ApplicationName = $ClientName

                if (Test-Bound -ParameterName 'AccessToken') {
                    $server.ConnectionContext.AccessToken = $AccessToken
                }
                if (Test-Bound -ParameterName 'BatchSeparator') {
                    $server.ConnectionContext.BatchSeparator = $BatchSeparator
                }
                if (Test-Bound -ParameterName 'ConnectTimeout') {
                    $server.ConnectionContext.ConnectTimeout = $ConnectTimeout
                }
                if (Test-Bound -ParameterName 'Database') {
                    $server.ConnectionContext.DatabaseName = $Database
                }
                if (Test-Bound -ParameterName 'EncryptConnection') {
                    $server.ConnectionContext.EncryptConnection = $true
                }
                if (Test-Bound -ParameterName 'LockTimeout') {
                    $server.ConnectionContext.LockTimeout = $LockTimeout
                }
                if (Test-Bound -ParameterName 'MaxPoolSize') {
                    $server.ConnectionContext.MaxPoolSize = $MaxPoolSize
                }
                if (Test-Bound -ParameterName 'MinPoolSize') {
                    $server.ConnectionContext.MinPoolSize = $MinPoolSize
                }
                if (Test-Bound -ParameterName 'MultipleActiveResultSets') {
                    $server.ConnectionContext.MultipleActiveResultSets = $true
                }
                if (Test-Bound -ParameterName 'NetworkProtocol') {
                    $server.ConnectionContext.NetworkProtocol = $NetworkProtocol
                }
                if (Test-Bound -ParameterName 'NonPooledConnection') {
                    $server.ConnectionContext.NonPooledConnection = $true
                }
                if (Test-Bound -ParameterName 'PacketSize') {
                    $server.ConnectionContext.PacketSize = $PacketSize
                }
                if (Test-Bound -ParameterName 'PooledConnectionLifetime') {
                    $server.ConnectionContext.PooledConnectionLifetime = $PooledConnectionLifetime
                }
                if (Test-Bound -ParameterName 'StatementTimeout') {
                    $server.ConnectionContext.StatementTimeout = $StatementTimeout
                }
                if (Test-Bound -ParameterName 'SqlExecutionModes') {
                    $server.ConnectionContext.SqlExecutionModes = $SqlExecutionModes
                }
                if (Test-Bound -ParameterName 'TrustServerCertificate') {
                    $server.ConnectionContext.TrustServerCertificate = $true
                }
                if (Test-Bound -ParameterName 'WorkstationId') {
                    $server.ConnectionContext.WorkstationId = $WorkstationId
                }
                if (Test-Bound -ParameterName 'ApplicationIntent') {
                    $server.ConnectionContext.ApplicationIntent = $ApplicationIntent
                }

                $connstring = $server.ConnectionContext.ConnectionString
                if (Test-Bound -ParameterName 'MultiSubnetFailover') {
                    $connstring = "$connstring;MultiSubnetFailover=True"
                }
                if (Test-Bound -ParameterName 'FailoverPartner') {
                    $connstring = "$connstring;Failover Partner=$FailoverPartner"
                }

                if ($connstring -ne $server.ConnectionContext.ConnectionString) {
                    $server.ConnectionContext.ConnectionString = $connstring
                }

                try {
                    if ($null -ne $SqlCredential.UserName) {
                        $username = ($SqlCredential.UserName).TrimStart("\")

                        # support both ad\username and username@ad
                        if ($username -like "*\*" -or $username -like "*@*") {
                            if ($username -like "*\*") {
                                $domain, $login = $username.Split("\")
                                $authtype = "Windows Authentication with Credential"
                                if ($domain) {
                                    $formatteduser = "$login@$domain"
                                } else {
                                    $formatteduser = $username.Split("\")[1]
                                }
                            } else {
                                $formatteduser = $SqlCredential.UserName
                            }

                            $server.ConnectionContext.LoginSecure = $true
                            $server.ConnectionContext.ConnectAsUser = $true
                            $server.ConnectionContext.ConnectAsUserName = $formatteduser
                            $server.ConnectionContext.ConnectAsUserPassword = ($SqlCredential).GetNetworkCredential().Password
                        } else {
                            $authtype = "SQL Authentication"
                            $server.ConnectionContext.LoginSecure = $false
                            $server.ConnectionContext.set_Login($username)
                            $server.ConnectionContext.set_SecurePassword($SqlCredential.Password)
                        }
                    }

                    if ($NonPooled) {
                        $server.ConnectionContext.Connect()
                    } elseif ($authtype -eq "Windows Authentication with Credential") {
                        # Make it connect in a natural way, hard to explain.
                        $null = $server.Information.Version
                        if ($server.ConnectionContext.IsOpen -eq $false) {
                            $server.ConnectionContext.Connect()
                        }
                    } else {
                        $server.ConnectionContext.SqlConnectionObject.Open()
                    }
                } catch {
                    $originalException = $_.Exception
                    try {
                        $message = $originalException.InnerException.InnerException.ToString()
                    } catch {
                        $message = $originalException.ToString()
                    }
                    $message = ($message -Split '-->')[0]
                    $message = ($message -Split 'at System.Data.SqlClient')[0]
                    $message = ($message -Split 'at System.Data.ProviderBase')[0]

                    Stop-Function -Message "Can't connect to $instance" -ErrorRecord $_ -Continue
                }
            }

            if ($loadedSmoVersion -ge 11) {
                if ($server.VersionMajor -eq 8) {
                    # 2000
                    $initFieldsDb = New-Object System.Collections.Specialized.StringCollection
                    [void]$initFieldsDb.AddRange($Fields2000_Db)
                    $initFieldsLogin = New-Object System.Collections.Specialized.StringCollection
                    [void]$initFieldsLogin.AddRange($Fields2000_Login)
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], $initFieldsDb)
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], $initFieldsLogin)
                } elseif ($server.VersionMajor -eq 9 -or $server.VersionMajor -eq 10) {
                    # 2005 and 2008
                    $initFieldsDb = New-Object System.Collections.Specialized.StringCollection
                    [void]$initFieldsDb.AddRange($Fields200x_Db)
                    $initFieldsLogin = New-Object System.Collections.Specialized.StringCollection
                    [void]$initFieldsLogin.AddRange($Fields200x_Login)
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], $initFieldsDb)
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], $initFieldsLogin)
                } else {
                    # 2012 and above
                    $initFieldsDb = New-Object System.Collections.Specialized.StringCollection
                    [void]$initFieldsDb.AddRange($Fields201x_Db)
                    $initFieldsLogin = New-Object System.Collections.Specialized.StringCollection
                    [void]$initFieldsLogin.AddRange($Fields201x_Login)
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], $initFieldsDb)
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], $initFieldsLogin)
                }
            }

            if ($SqlConnectionOnly) {
                return $server.ConnectionContext.SqlConnectionObject
            } else {
                if (-not $server.ComputerName) {
                    if (-not $server.NetName -or $SqlInstance -match '\.') {
                        $parsedcomputername = $ConvertedSqlInstance.ComputerName
                    } else {
                        $parsedcomputername = $server.NetName
                    }
                    Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $parsedcomputername -Force
                }
            }
            $server
        }
    }
}