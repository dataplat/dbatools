function Connect-DbaInstance {
    <#
    .SYNOPSIS
        Creates a robust, reusable SQL Server object.

    .DESCRIPTION
        This command creates a robust, reusable sql server object.

        It is robust because it initializes properties that do not cause enumeration by default. It also supports both Windows and SQL Server authentication methods, and detects which to use based upon the provided credentials.

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

    .PARAMETER AppendConnectionString
        Appends to the current connection string. Note that you cannot pass authentication information using this method. Use -SqlInstance and optionally -SqlCredential to set authentication information.

    .PARAMETER ApplicationIntent
        Declares the application workload type when connecting to a server.

        Valid values are "ReadOnly" and "ReadWrite".

    .PARAMETER BatchSeparator
        A string to separate groups of SQL statements being executed. By default, this is "GO".

    .PARAMETER ClientName
        By default, this command sets the client's ApplicationName property to "dbatools PowerShell module - dbatools.io". If you're doing anything that requires profiling, you can look for this client name. Using -ClientName allows you to set your own custom client application name.

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

    .PARAMETER AzureUnsupported
        Terminate if Azure is detected but not supported

    .PARAMETER AzureDomain

        By default, this is set to database.windows.net

        In the event your AzureSqlDb is not on a database.windows.net domain, you can set a custom domain using the AzureDomain parameter.
        This tells Connect-DbaInstance to login to the database using the method that works best with Azure.

    .PARAMETER MinimumVersion
        Terminate if the target SQL Server instance version does not meet version requirements

    .PARAMETER AuthenticationType
        Basically used to force AD Universal with MFA Support when other types have been detected

    .PARAMETER Tenant
        The TenantId for an Azure Instance

    .PARAMETER Thumbprint
        Thumbprint for connections to Azure MSI

    .PARAMETER Store
        Store where the Azure MSI certificate is stored

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

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance myserver.database.windows.net -Database mydb -SqlCredential me@mydomain.onmicrosoft.com -DisableException
        PS C:\> Invoke-Query -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL DB using AAD / Azure Active Directory, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Database dbatools -DisableException
        PS C:\> Invoke-Query -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL DB using AAD Integrated Auth, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance "myserver.public.cust123.database.windows.net,3342" -Database mydb -SqlCredential me@mydomain.onmicrosoft.com -DisableException
        PS C:\> Invoke-Query -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL Managed instance using AAD / Azure Active Directory, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance db.mycustomazure.com -Database mydb -AzureDomain mycustomazure.com -DisableException
        PS C:\> Invoke-Query -SqlInstance $server -Query "select 1 as test"

        In the event your AzureSqlDb is not on a database.windows.net domain, you can set a custom domain using the AzureDomain parameter.
        This tells Connect-DbaInstance to login to the database using the method that works best with Azure.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -ConnectionString "Data Source=TCP:mydb.database.windows.net,1433;User ID=sqladmin;Password=adfasdf;MultipleActiveResultSets=False;Connect Timeout=30;Encrypt=True;TrustServerCertificate=False;"
        PS C:\> Invoke-Query -SqlInstance $server -Query "select 1 as test"

        Logs into Azure using a preconstructed connstring, then performs a sample query.
        ConnectionString is an alias of SqlInstance, so you can use -SqlInstance $connstring as well.

    .EXAMPLE
        PS C:\> $cred = Get-Credential guid-app-id-here # appid for username, clientsecret for password
        PS C:\> $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Database abc -SqCredential $cred -Tenant guidheremaybename
        PS C:\> Invoke-Query -SqlInstance $server -Query "select 1 as test"

        When connecting from a non-Azure workstation, logs into Azure using Universal with MFA Support with a username and password, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Database abc -AuthenticationType 'AD Universal with MFA Support'
        PS C:\> Invoke-Query -SqlInstance $server -Query "select 1 as test"

        When connecting from an Azure VM with .NET 4.7.2 and higher, logs into Azure using Universal with MFA Support, then performs a sample query.

    .EXAMPLE
        PS C:\> $cred = Get-Credential guid-app-id-here # appid for username, clientsecret for password
        PS C:\> Set-DbatoolsConfig -FullName azure.tenantid -Value 'guidheremaybename' -Passthru | Register-DbatoolsConfig
        PS C:\> Set-DbatoolsConfig -FullName azure.appid -Value $cred.Username -Passthru | Register-DbatoolsConfig
        PS C:\> Set-DbatoolsConfig -FullName azure.clientsecret -Value $cred.Password -Passthru | Register-DbatoolsConfig # requires securestring
        PS C:\> Set-DbatoolsConfig -FullName sql.connection.database -Value abc -Passthru | Register-DbatoolsConfig
        PS C:\> Connect-DbaInstance -SqlInstance psdbatools.database.windows.net

        Permanently sets some app id config values. To set them temporarily (just for a session), remove -Passthru | Register-DbatoolsConfig
        When connecting from a non-Azure workstation or an Azure VM without .NET 4.7.2 and higher, logs into Azure using Universal with MFA Support, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Thumbprint FF6361E82F21664F64A2576BB49EAC429BD5ABB6 -Store CurrentUser -Tenant tenant-guid -SqlCredential app-id-guid-here -Database abc
        PS C:\> Invoke-Query -SqlInstance $server -Query "select 1 as test"

        Logs into Azure using Universal with MFA Support with a certificate, then performs a sample query. Note that you will be prompted for a password but the password can be left blank and the certificate will be used instead.

    .EXAMPLE
        PS C:\> Set-DbatoolsConfig -FullName sql.connection.experimental -Value $true
        PS C:\> $sqlcred = Get-Credential sqladmin
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql2014 -SqlCredential $sqlcred
        PS C:\> Invoke-Query -SqlInstance $server -Query "select 1 as test"

        Use the new code path for handling connections. Especially when you have problems with connection pooling, try this.
        We also have added additional -Verbose and -Debug output to help us understand your problem if you open an issue related to connections.
        For additional information about how the new code path works, please have a look at the code: https://github.com/sqlcollaborative/dbatools/blob/development/functions/Connect-DbaInstance.ps1

        If you like to use the new code path permanently, register this config:
        PS C:\> Set-DbatoolsConfig -FullName sql.connection.experimental -Value $true -Passthru | Register-DbatoolsConfig

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("Connstring", "ConnectionString")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database = (Get-DbatoolsConfigValue -FullName 'sql.connection.database'),
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$ApplicationIntent,
        [switch]$AzureUnsupported,
        [string]$BatchSeparator,
        [string]$ClientName = (Get-DbatoolsConfigValue -FullName 'sql.connection.clientname'),
        [int]$ConnectTimeout = ([Sqlcollaborative.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout),
        [switch]$EncryptConnection = (Get-DbatoolsConfigValue -FullName 'sql.connection.encrypt'),
        [string]$FailoverPartner,
        [int]$LockTimeout,
        [int]$MaxPoolSize,
        [int]$MinPoolSize,
        [int]$MinimumVersion,
        [switch]$MultipleActiveResultSets,
        [switch]$MultiSubnetFailover,
        [ValidateSet('TcpIp', 'NamedPipes', 'Multiprotocol', 'AppleTalk', 'BanyanVines', 'Via', 'SharedMemory', 'NWLinkIpxSpx')]
        [string]$NetworkProtocol = (Get-DbatoolsConfigValue -FullName 'sql.connection.protocol'),
        [switch]$NonPooledConnection,
        [int]$PacketSize = (Get-DbatoolsConfigValue -FullName 'sql.connection.packetsize'),
        [int]$PooledConnectionLifetime,
        [ValidateSet('CaptureSql', 'ExecuteAndCaptureSql', 'ExecuteSql')]
        [string]$SqlExecutionModes,
        [int]$StatementTimeout = (Get-DbatoolsConfigValue -FullName 'sql.execution.timeout'),
        [switch]$TrustServerCertificate = (Get-DbatoolsConfigValue -FullName 'sql.connection.trustcert'),
        [string]$WorkstationId,
        [string]$AppendConnectionString,
        [switch]$SqlConnectionOnly,
        [string]$AzureDomain = "database.windows.net",
        #[ValidateSet('Auto', 'Windows Authentication', 'SQL Server Authentication', 'AD Universal with MFA Support', 'AD - Password', 'AD - Integrated')]
        [ValidateSet('Auto', 'AD Universal with MFA Support')]
        [string]$AuthenticationType = "Auto",
        [string]$Tenant = (Get-DbatoolsConfigValue -FullName 'azure.tenantid'),
        [string]$Thumbprint = (Get-DbatoolsConfigValue -FullName 'azure.certificate.thumbprint'),
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Store = (Get-DbatoolsConfigValue -FullName 'azure.certificate.store'),
        [switch]$DisableException
    )
    begin {
        $azurevm = Get-DbatoolsConfigValue -FullName azure.vm
        #region Utility functions
        if ($Tenant -or $AuthenticationType -in 'AD Universal with MFA Support', 'AD - Password', 'AD - Integrated' -and ($null -eq $azurevm)) {
            Write-Message -Level Verbose -Message "Determining if current workstation is an Azure VM"
            # Do an Azure check - this will occur just once
            try {
                $azurevmcheck = Invoke-RestMethod -Headers @{"Metadata" = "true" } -Uri http://169.254.169.254/metadata/instance?api-version=2018-10-01 -Method GET -TimeoutSec 2 -ErrorAction Stop
                if ($azurevmcheck.compute.azEnvironment) {
                    $azurevm = $true
                    $null = Set-DbatoolsConfig -FullName azure.vm -Value $true -PassThru | Register-DbatoolsConfig
                } else {
                    $null = Set-DbatoolsConfig -FullName azure.vm -Value $false -PassThru | Register-DbatoolsConfig
                }
            } catch {
                $null = Set-DbatoolsConfig -FullName azure.vm -Value $false -PassThru | Register-DbatoolsConfig
            }
        }
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
        function Invoke-TEPPCacheUpdate {
            [CmdletBinding()]
            param (
                [System.Management.Automation.ScriptBlock]$ScriptBlock
            )

            try {
                [ScriptBlock]::Create($scriptBlock).Invoke()
            } catch {
                # If the SQL Server version doesn't support the feature, we ignore it and silently continue
                if ($_.Exception.InnerException.InnerException.GetType().FullName -eq "Microsoft.SqlServer.Management.Sdk.Sfc.InvalidVersionEnumeratorException") {
                    return
                }

                if ($ENV:APPVEYOR_BUILD_FOLDER -or ([Sqlcollaborative.Dbatools.Message.MEssageHost]::DeveloperMode)) { Stop-Function -Message }
                else {
                    Write-Message -Level Warning -Message "Failed TEPP Caching: $($scriptBlock.ToString() | Select-String '"(.*?)"' | ForEach-Object { $_.Matches[0].Groups[1].Value })" -ErrorRecord $_ 3>$null
                }
            }
        }
        function Hide-ConnectionString {
            Param (
                [string]$ConnectionString
            )
            try {
                $connStringBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $ConnectionString
                if ($connStringBuilder.Password) {
                    $connStringBuilder.Password = ''.Padleft(8, '*')
                }
                return $connStringBuilder.ConnectionString
            } catch {
                return "Failed to mask the connection string`: $($_.Exception.Message)"
            }
        }
        #endregion Utility functions

        #region Ensure Credential integrity
        <#
        Usually, the parameter type should have been not object but off the PSCredential type.
        When binding null to a PSCredential type parameter on PS3-4, it'd then show a prompt, asking for username and password.

        In order to avoid that and having to refactor lots of functions (and to avoid making regular scripts harder to read), we created this workaround.
        #>
        if ($SqlCredential) {
            if ($SqlCredential.GetType() -ne [System.Management.Automation.PSCredential]) {
                Stop-Function -Message "The credential parameter was of a non-supported type. Only specify PSCredentials such as generated from Get-Credential. Input was of type $($SqlCredential.GetType().FullName)"
                return
            }
        }
        #endregion Ensure Credential integrity

        # In an unusual move, Connect-DbaInstance goes the exact opposite way of all commands when it comes to exceptions
        # this means that by default it Stop-Function -Messages, but do not be tempted to Stop-Function -Message
        if ($DisableException) {
            $EnableException = $false
        } else {
            $EnableException = $true
        }

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
        if ($AzureDomain) { $AzureDomain = [regex]::escape($AzureDomain) }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        Write-Message -Level Debug -Message "Starting process block"
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Debug -Message "Starting loop for '$instance': ComputerName = '$($instance.ComputerName)', InstanceName = '$($instance.InstanceName)', IsLocalHost = '$($instance.IsLocalHost)', Type = '$($instance.Type)'"

            <#
            In order to be able to test new functions in various environments, the switch "experimental" is introduced.
            This switch can be set with "Set-DbatoolsConfig -FullName sql.connection.experimental -Value $true" for the active session
            and within this function leads to the following code path being used.
            All the sub paths inside the following if clause will end with a continue, so the normal code path is not used.
            #>
            if (Get-DbatoolsConfigValue -FullName sql.connection.experimental) {
                <#
                Best practice:
                * Create a smo server object by submitting the name of the instance as a string to SqlInstance and additional parameters to configure the connection
                * Reuse the smo server object in all following calls as SqlInstance
                * When reusing the smo server object, only the following additional parameters are allowed with Connect-DbaInstance:
                  - Database (command clones ConnectionContext and returns new smo server object)
                  - AzureUnsupported (command fails if target is Azure)
                  - MinimumVersion (command fails if target version is too old)
                  - SqlConnectionOnly (command returns only the ConnectionContext.SqlConnectionObject)
                TODO: Try to identify all commands that use additional parameters and rewrite the command or add support for that parameter to Connect-DbaInstance
                Commands found:
                - Get-DbaDbExtentDiff (NonPooled)
                - Import-DbaCsv (StatementTimeout)
                - Install-DbaMaintenanceSolution (NonPooled)
                - Invoke-DbaQuery (ApplicationIntent)

                Additional possibilities as input to SqlInstance:
                * A smo connection object [System.Data.SqlClient.SqlConnection] (InputObject is used to build smo server object)
                * A smo registered server object [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer] (FullSmoName und InputObject.ConnectionString are used to build smo server object)
                * A connections string [String] (FullSmoName und InputObject are used to build smo server object)
                Limitations of these additional possibilities:
                * All additional parameters are ignored
                  TODO: Should we test and throw a warning? Or should we try to merge some or all additional parameters into the connections string?
                * Currently, connection pooling does not work with connections that are build from connection strings
                  TODO: Test with original smo libraries and open an issue

                * All parameters that configure the connection and where they can be set (here just for documentation and future development):
                  - AppendConnectionString      SqlConnectionInfo.AdditionalParameters
                  - ApplicationIntent           SqlConnectionInfo.ApplicationIntent          SqlConnectionStringBuilder['ApplicationIntent']
                  - AuthenticationType          SqlConnectionInfo.Authentication (TODO)      SqlConnectionStringBuilder['Authentication']
                  - BatchSeparator                                                                                                                     ConnectionContext.BatchSeparator
                  - ClientName                  SqlConnectionInfo.ApplicationName            SqlConnectionStringBuilder['Application Name']
                  - ConnectTimeout              SqlConnectionInfo.ConnectionTimeout          SqlConnectionStringBuilder['Connect Timeout']
                  - Database                    SqlConnectionInfo.DatabaseName               SqlConnectionStringBuilder['Initial Catalog']
                  - EncryptConnection           SqlConnectionInfo.EncryptConnection          SqlConnectionStringBuilder['Encrypt']
                  - FailoverPartner             SqlConnectionInfo.AdditionalParameters       SqlConnectionStringBuilder['Failover Partner']
                  - LockTimeout                                                                                                                        ConnectionContext.LockTimeout
                  - MaxPoolSize                 SqlConnectionInfo.MaxPoolSize                SqlConnectionStringBuilder['Max Pool Size']
                  - MinPoolSize                 SqlConnectionInfo.MinPoolSize                SqlConnectionStringBuilder['Min Pool Size']
                  - MultipleActiveResultSets                                                 SqlConnectionStringBuilder['MultipleActiveResultSets']    ConnectionContext.MultipleActiveResultSets
                  - MultiSubnetFailover         SqlConnectionInfo.AdditionalParameters       SqlConnectionStringBuilder['MultiSubnetFailover']
                  - NetworkProtocol             SqlConnectionInfo.ConnectionProtocol
                  - NonPooledConnection         SqlConnectionInfo.Pooled                     SqlConnectionStringBuilder['Pooling']
                  - PacketSize                  SqlConnectionInfo.PacketSize                 SqlConnectionStringBuilder['Packet Size']
                  - PooledConnectionLifetime    SqlConnectionInfo.PoolConnectionLifeTime     SqlConnectionStringBuilder['Load Balance Timeout']
                  - SqlInstance                 SqlConnectionInfo.ServerName                 SqlConnectionStringBuilder['Data Source']
                  - SqlCredential               SqlConnectionInfo.SecurePassword             SqlConnectionStringBuilder['Password']
                                                SqlConnectionInfo.UserName                   SqlConnectionStringBuilder['User ID']
                                                SqlConnectionInfo.UseIntegratedSecurity      SqlConnectionStringBuilder['Integrated Security']
                  - SqlExecutionModes                                                                                                                  ConnectionContext.SqlExecutionModes
                  - StatementTimeout            (SqlConnectionInfo.QueryTimeout - TODO: different?)                                                    ConnectionContext.StatementTimeout
                  - TrustServerCertificate      SqlConnectionInfo.TrustServerCertificate     SqlConnectionStringBuilder['TrustServerCertificate']
                  - WorkstationId               SqlConnectionInfo.WorkstationId              SqlConnectionStringBuilder['Workstation Id']

                Some additional tests:
                * Is $AzureUnsupported set? Test for Azure.
                * Is $MinimumVersion set? Test for that.
                * Is $SqlConnectionOnly set? Then return $server.ConnectionContext.SqlConnectionObject.
                * Does the server object have the additional properties? Add them when necessary.

                Some general decisions:
                * We try to treat connections to Azure as normal connections.
                * Not every edge case will be covered at the beginning.
                * We copy as less code from the existing code paths as possible.
                #>
                Write-Message -Level Debug -Message "sql.connection.experimental is used"

                # Analyse input object and extract necessary parts
                if ($instance.Type -like 'Server') {
                    Write-Message -Level Verbose -Message "Server object passed in, will do some checks and then return the original object"
                    $inputObjectType = 'Server'
                    $inputObject = $instance.InputObject
                } elseif ($instance.Type -like 'SqlConnection') {
                    Write-Message -Level Verbose -Message "SqlConnection object passed in, will build server object from instance.InputObject, do some checks and then return the server object"
                    $inputObjectType = 'SqlConnection'
                    $inputObject = $instance.InputObject
                } elseif ($instance.Type -like 'RegisteredServer') {
                    Write-Message -Level Verbose -Message "RegisteredServer object passed in, will build empty server object, set connection string from instance.InputObject.ConnectionString, do some checks and then return the server object"
                    $inputObjectType = 'RegisteredServer'
                    $inputObject = $instance.InputObject
                    $serverName = $instance.FullSmoName
                    $connectionString = $instance.InputObject.ConnectionString
                } elseif ($instance.IsConnectionString) {
                    Write-Message -Level Verbose -Message "Connection string is passed in, will build empty server object, set connection string from instance.InputObject, do some checks and then return the server object"
                    $inputObjectType = 'ConnectionString'
                    $serverName = $instance.FullSmoName
                    $connectionString = $instance.InputObject
                } else {
                    Write-Message -Level Verbose -Message "String is passed in, will build server object from instance object and other parameters, do some checks and then return the server object"
                    $inputObjectType = 'String'
                    $serverName = $instance.FullSmoName
                }

                # Check for ignored parameters
                $ignoredParameters = 'ApplicationIntent', 'BatchSeparator', 'ClientName', 'ConnectTimeout', 'EncryptConnection', 'LockTimeout', 'MaxPoolSize', 'MinPoolSize', 'NetworkProtocol', 'NonPooledConnection', 'PacketSize', 'PooledConnectionLifetime', 'SqlExecutionModes', 'StatementTimeout', 'TrustServerCertificate', 'WorkstationId', 'AuthenticationType', 'FailoverPartner', 'MultipleActiveResultSets', 'MultiSubnetFailover', 'AppendConnectionString'
                if ($inputObjectType -eq 'Server') {
                    if (Test-Bound -ParameterName $ignoredParameters) {
                        Write-Message -Level Warning -Message "Additional parameters are passed in, but they will be ignored"
                    }
                } elseif ($inputObjectType -in 'SqlConnection', 'RegisteredServer', 'ConnectionString' ) {
                    if (Test-Bound -ParameterName $ignoredParameters, 'Database') {
                        Write-Message -Level Warning -Message "Additional parameters are passed in, but they will be ignored"
                    }
                }
                # TODO: Test for SqlCredential as well?

                # Create smo server object
                if ($inputObjectType -eq 'Server') {
                    if ($Database) {
                        Write-Message -Level Verbose -Message "Parameter Database passed in, so we clone the connection context"
                        # TODO: Do we have to check if its the same database?
                        $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $inputObject.ConnectionContext.Copy().GetDatabaseConnection($Database)
                    } else {
                        $server = $inputObject
                    }
                } elseif ($inputObjectType -eq 'SqlConnection') {
                    $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $inputObject
                } elseif ($inputObjectType -in 'RegisteredServer', 'ConnectionString') {
                    $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $serverName
                    $server.ConnectionContext.ConnectionString = $connectionString
                } elseif ($inputObjectType -eq 'String') {
                    # Identify authentication method
                    if ($AuthenticationType -ne 'Auto') {
                        # Only possibility at the moment: 'AD Universal with MFA Support'
                        # $username will not be set
                        # Will probably not work at all
                        # TODO: We need a setup to test that
                        $authType = $AuthenticationType
                    } else {
                        if (Test-Azure -SqlInstance $instance) {
                            $authType = 'azure '
                        } else {
                            $authType = 'local '
                        }
                        if ($SqlCredential) {
                            # support both ad\username and username@ad
                            $username = ($SqlCredential.UserName).TrimStart("\")
                            if ($username -like "*\*") {
                                $domain, $login = $username.Split("\")
                                $username = "$login@$domain"
                            }
                            if ($username -like '*@*') {
                                $authType += 'ad'
                            } else {
                                $authType += 'sql'
                            }
                        } else {
                            $authType += 'integrated'
                        }
                    }
                    Write-Message -Level Verbose -Message "authentication method is '$authType'"

                    # Best way to get connection pooling to work is to use SqlConnectionInfo -> ServerConnection -> Server
                    $connInfo = New-Object -TypeName Microsoft.SqlServer.Management.Common.SqlConnectionInfo -ArgumentList $serverName

                    # I will list all properties of SqlConnectionInfo and set them if value is provided

                    #AccessToken            Property   Microsoft.SqlServer.Management.Common.IRenewableToken AccessToken {get;set;}
                    # TODO: Can we use this with Azure?

                    #AdditionalParameters   Property   string AdditionalParameters {get;set;}
                    if ($AppendConnectionString) {
                        Write-Message -Level Debug -Message "AdditionalParameters will be appended by '$AppendConnectionString'"
                        $connInfo.AdditionalParameters += ";$AppendConnectionString"
                    }
                    if ($FailoverPartner) {
                        Write-Message -Level Debug -Message "AdditionalParameters will be appended by '$AppendConnectionString'"
                        $connInfo.AdditionalParameters += ";FailoverPartner=$FailoverPartner"
                    }
                    if ($MultiSubnetFailover) {
                        Write-Message -Level Debug -Message "AdditionalParameters will be appended by '$AppendConnectionString'"
                        $connInfo.AdditionalParameters += ';MultiSubnetFailover=True'
                    }

                    #ApplicationIntent      Property   string ApplicationIntent {get;set;}
                    if ($ApplicationIntent) {
                        Write-Message -Level Debug -Message "ApplicationIntent will be set to '$ApplicationIntent'"
                        $connInfo.ApplicationIntent = $ApplicationIntent
                    }

                    #ApplicationName        Property   string ApplicationName {get;set;}
                    if ($ClientName) {
                        Write-Message -Level Debug -Message "ApplicationName will be set to '$ClientName'"
                        $connInfo.ApplicationName = $ClientName
                    }

                    #Authentication         Property   Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod Authentication {get;set;}
                    #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryIntegrated
                    #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryInteractive
                    #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryPassword
                    #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::NotSpecified
                    #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::SqlPassword
                    if ($authType -eq 'AD Universal with MFA Support') {
                        # Azure AD with Multi-Factor Authentication
                        # TODO: This is not tested
                        Write-Message -Level Debug -Message "Authentication will be set to 'ActiveDirectoryInteractive'"
                        $connInfo.Authentication = [Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryInteractive
                    } elseif ($authType -eq 'azure integrated') {
                        # Azure AD integrated security
                        # TODO: This is not tested
                        Write-Message -Level Debug -Message "Authentication will be set to 'ActiveDirectoryIntegrated'"
                        $connInfo.Authentication = [Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryIntegrated
                    } elseif ($authType -eq 'azure ad') {
                        # Azure AD account with password
                        Write-Message -Level Debug -Message "Authentication will be set to 'ActiveDirectoryPassword'"
                        $connInfo.Authentication = [Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryPassword
                    }

                    #ConnectionProtocol     Property   Microsoft.SqlServer.Management.Common.NetworkProtocol ConnectionProtocol {get;set;}
                    if ($NetworkProtocol) {
                        Write-Message -Level Debug -Message "ConnectionProtocol will be set to '$NetworkProtocol'"
                        $connInfo.ConnectionProtocol = $NetworkProtocol
                    }

                    #ConnectionString       Property   string ConnectionString {get;}
                    # Only a getter, not a setter - so don't touch

                    #ConnectionTimeout      Property   int ConnectionTimeout {get;set;}
                    if ($ConnectTimeout) {
                        Write-Message -Level Debug -Message "ConnectionTimeout will be set to '$ConnectTimeout'"
                        $connInfo.ConnectionTimeout = $ConnectTimeout
                    }

                    #DatabaseName           Property   string DatabaseName {get;set;}
                    if ($Database) {
                        Write-Message -Level Debug -Message "Database will be set to '$Database'"
                        $connInfo.DatabaseName = $Database
                    }

                    #EncryptConnection      Property   bool EncryptConnection {get;set;}
                    if ($EncryptConnection) {
                        Write-Message -Level Debug -Message "EncryptConnection will be set to '$EncryptConnection'"
                        $connInfo.EncryptConnection = $EncryptConnection
                    }

                    #MaxPoolSize            Property   int MaxPoolSize {get;set;}
                    if ($MaxPoolSize) {
                        Write-Message -Level Debug -Message "MaxPoolSize will be set to '$MaxPoolSize'"
                        $connInfo.MaxPoolSize = $MaxPoolSize
                    }

                    #MinPoolSize            Property   int MinPoolSize {get;set;}
                    if ($MinPoolSize) {
                        Write-Message -Level Debug -Message "MinPoolSize will be set to '$MinPoolSize'"
                        $connInfo.MinPoolSize = $MinPoolSize
                    }

                    #PacketSize             Property   int PacketSize {get;set;}
                    if ($PacketSize) {
                        Write-Message -Level Debug -Message "PacketSize will be set to '$PacketSize'"
                        $connInfo.PacketSize = $PacketSize
                    }

                    #Password               Property   string Password {get;set;}
                    # We will use SecurePassword

                    #PoolConnectionLifeTime Property   int PoolConnectionLifeTime {get;set;}
                    if ($PooledConnectionLifetime) {
                        Write-Message -Level Debug -Message "PoolConnectionLifeTime will be set to '$PooledConnectionLifetime'"
                        $connInfo.PoolConnectionLifeTime = $PooledConnectionLifetime
                    }

                    #Pooled                 Property   System.Data.SqlTypes.SqlBoolean Pooled {get;set;}
                    # TODO: Do we need or want the else path or is it the default and we better don't touch it?
                    if ($NonPooledConnection) {
                        Write-Message -Level Debug -Message "Pooled will be set to '$false'"
                        $connInfo.Pooled = $false
                    } else {
                        Write-Message -Level Debug -Message "Pooled will be set to '$true'"
                        $connInfo.Pooled = $true
                    }

                    #QueryTimeout           Property   int QueryTimeout {get;set;}
                    <# TODO: What is the difference between QueryTimeout and StatementTimeout?
                    if ($StatementTimeout) {
                        Write-Message -Level Debug -Message "QueryTimeout will be set to '$StatementTimeout'"
                        $connInfo.QueryTimeout = $StatementTimeout
                    }
                    #>

                    #SecurePassword         Property   securestring SecurePassword {get;set;}
                    if ($authType -in 'azure ad', 'azure sql', 'local sql') {
                        Write-Message -Level Debug -Message "SecurePassword will be set"
                        $connInfo.SecurePassword = $SqlCredential.Password
                    }

                    #ServerCaseSensitivity  Property   Microsoft.SqlServer.Management.Common.ServerCaseSensitivity ServerCaseSensitivity {get;set;}

                    #ServerName             Property   string ServerName {get;set;}
                    # Was already set by the constructor.
                    # TODO: Or do we want to set it here?

                    #ServerType             Property   Microsoft.SqlServer.Management.Common.ConnectionType ServerType {get;}
                    # Only a getter, not a setter - so don't touch

                    #ServerVersion          Property   Microsoft.SqlServer.Management.Common.ServerVersion ServerVersion {get;set;}
                    # We can set that? No, we don't want to...

                    #TrustServerCertificate Property   bool TrustServerCertificate {get;set;}
                    if ($TrustServerCertificate) {
                        Write-Message -Level Debug -Message "TrustServerCertificate will be set to '$TrustServerCertificate'"
                        $connInfo.TrustServerCertificate = $TrustServerCertificate
                    }

                    #UseIntegratedSecurity  Property   bool UseIntegratedSecurity {get;set;}
                    # TODO: Do we have to set this?

                    #UserName               Property   string UserName {get;set;}
                    if ($authType -in 'azure ad', 'azure sql', 'local sql') {
                        Write-Message -Level Debug -Message "UserName will be set to '$username'"
                        $connInfo.UserName = $username
                    }

                    #WorkstationId          Property   string WorkstationId {get;set;}
                    if ($WorkstationId) {
                        Write-Message -Level Debug -Message "WorkstationId will be set to '$WorkstationId'"
                        $connInfo.WorkstationId = $WorkstationId
                    }

                    $srvConn = New-Object -TypeName Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $connInfo

                    if ($authType -eq 'local ad') {
                        Write-Message -Level Debug -Message "ConnectAsUser will be set to '$true'"
                        $srvConn.ConnectAsUser = $true

                        Write-Message -Level Debug -Message "ConnectAsUserName will be set to '$username'"
                        $srvConn.ConnectAsUserName = $username

                        Write-Message -Level Debug -Message "ConnectAsUserPassword will be set"
                        $srvConn.ConnectAsUserPassword = $SqlCredential.GetNetworkCredential().Password
                    }
                    Write-Message -Level Debug -Message "TrueLogin is '$($srvConn.TrueLogin)'"

                    $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $srvConn

                    # Set properties of ConnectionContext that are not part of SqlConnectionInfo
                    if (Test-Bound -ParameterName 'BatchSeparator') {
                        $server.ConnectionContext.BatchSeparator = $BatchSeparator
                    }
                    if (Test-Bound -ParameterName 'LockTimeout') {
                        $server.ConnectionContext.LockTimeout = $LockTimeout
                    }
                    if (Test-Bound -ParameterName 'MultipleActiveResultSets') {
                        $server.ConnectionContext.MultipleActiveResultSets = $true
                    }
                    if (Test-Bound -ParameterName 'SqlExecutionModes') {
                        $server.ConnectionContext.SqlExecutionModes = $SqlExecutionModes
                    }
                    if (Test-Bound -ParameterName 'StatementTimeout') {
                        $server.ConnectionContext.StatementTimeout = $StatementTimeout
                    }
                }

                $maskedConnString = Hide-ConnectionString $server.ConnectionContext.ConnectionString
                Write-Message -Level Debug -Message "The masked server.ConnectionContext.ConnectionString is $maskedConnString"

                if ($server.ConnectionContext.IsOpen -eq $false) {
                    # TODO: IsOpen is always $false - why? Is there a better way to test and avoid unnessasary Open() calls?
                    Write-Message -Level Debug -Message "We connect to the instance with server.ConnectionContext.SqlConnectionObject.Open()"
                    try {
                        # Don't use $server.ConnectionContext.Connect() - this would create a non pooled connection
                        $server.ConnectionContext.SqlConnectionObject.Open()
                    } catch {
                        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                    }
                    Write-Message -Level Debug -Message "IsOpen is: $($server.ConnectionContext.IsOpen)"
                }
                Write-Message -Level Debug -Message "We have a connected server object"

                if ($AzureUnsupported -and $server.DatabaseEngineType -eq "SqlAzureDatabase") {
                    Stop-Function -Message "Azure SQL Database not supported" -Continue
                }

                if ($MinimumVersion -and $server.VersionMajor) {
                    if ($server.VersionMajor -lt $MinimumVersion) {
                        Stop-Function -Message "SQL Server version $MinimumVersion required - $server not supported." -Continue
                    }
                }

                if ($SqlConnectionOnly) {
                    Write-Message -Level Debug -Message "We return only SqlConnection in server.ConnectionContext.SqlConnectionObject"
                    $server.ConnectionContext.SqlConnectionObject
                    continue
                }

                if (-not $server.ComputerName) {
                    Add-Member -InputObject $server -NotePropertyName IsAzure -NotePropertyValue (Test-Azure -SqlInstance $instance) -Force
                    Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $instance.ComputerName -Force
                    Add-Member -InputObject $server -NotePropertyName DbaInstanceName -NotePropertyValue $instance.InstanceName -Force
                    Add-Member -InputObject $server -NotePropertyName NetPort -NotePropertyValue $instance.Port -Force
                    Add-Member -InputObject $server -NotePropertyName ConnectedAs -NotePropertyValue $server.ConnectionContext.TrueLogin -Force
                    Write-Message -Level Debug -Message "We added IsAzure = '$($server.IsAzure)', ComputerName = instance.ComputerName = '$($server.ComputerName)', DbaInstanceName = instance.InstanceName = '$($server.DbaInstanceName)', NetPort = instance.Port = '$($server.NetPort)', ConnectedAs = server.ConnectionContext.TrueLogin = '$($server.ConnectedAs)'"
                }

                Write-Message -Level Debug -Message "We return the server object"
                $server

                # TODO: Do we need this every time? How does it work exactly?
                # Register the connected instance, so that the TEPP updater knows it's been connected to and starts building the cache
                [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::SetInstance($instance.FullSmoName.ToLowerInvariant(), $server.ConnectionContext.Copy(), ($server.ConnectionContext.FixedServerRoles -match "SysAdmin"))

                # Update cache for instance names
                if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $instance.FullSmoName.ToLowerInvariant()) {
                    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $instance.FullSmoName.ToLowerInvariant()
                }

                Write-Message -Level Debug -Message "We are finished with this instance"
                continue
            }
            <#
            This is the end of the experimental code path.
            All session without the configuration "sql.connection.experimental" set to $true will run through the following code.
            #>

            $connstring = ''
            $isConnectionString = $false
            if ($instance.IsConnectionString) {
                $connstring = $instance.InputObject
                $isConnectionString = $true
            }
            if ($instance.Type -eq 'RegisteredServer' -and $instance.InputObject.ConnectionString) {
                $connstring = $instance.InputObject.ConnectionString
                $isConnectionString = $true
            }

            if ($isConnectionString) {
                try {
                    # ensure it's in the proper format
                    $sb = New-Object System.Data.Common.DbConnectionStringBuilder
                    $sb.ConnectionString = $connstring
                } catch {
                    $isConnectionString = $false
                }
            }

            # Gracefully handle Azure connections
            if ($connstring -match $AzureDomain -or $instance.ComputerName -match $AzureDomain -or $instance.InputObject.ComputerName -match $AzureDomain) {
                Write-Message -Level Debug -Message "We are about to connect to Azure"
                # so far, this is not evaluating
                if ($instance.InputObject.ConnectionContext.IsOpen) {
                    Write-Message -Level Debug -Message "Connection is already open, test if database has to be changed"
                    if ('' -eq $Database) {
                        Write-Message -Level Debug -Message "No database specified, so return instance.InputObject"
                        $instance.InputObject
                        continue
                    }
                    $currentdb = $instance.InputObject.ConnectionContext.ExecuteScalar("select db_name()")
                    if ($currentdb -eq $Database) {
                        Write-Message -Level Debug -Message "Same database specified, so return instance.InputObject"
                        $instance.InputObject
                        continue
                    } else {
                        Write-Message -Level Debug -Message "Different databases: Database = '$Database', currentdb = '$currentdb', so we build a new connection"
                    }
                }
                $isAzure = $true
                # Use available command to build the proper connection string
                # but first, clean up passed params so that they match
                $boundparams = $PSBoundParameters
                [object[]]$connstringcmd = (Get-Command New-DbaConnectionString).Parameters.Keys
                [object[]]$connectcmd = (Get-Command Connect-DbaInstance).Parameters.Keys

                foreach ($key in $connectcmd) {
                    if ($key -notin $connstringcmd -and $key -ne "SqlCredential") {
                        $null = $boundparams.Remove($key)
                    }
                }
                # Build connection string
                if ($connstring) {
                    Write-Message -Level Debug -Message "We have a connect string so we use it"
                    $azureconnstring = $connstring
                } else {
                    if ($Tenant) {
                        Write-Message -Level Debug -Message "We have a Tenant and build the connect string"
                        $azureconnstring = New-DbaConnectionString -SqlInstance $instance -AccessToken None -Database $Database
                    } else {
                        Write-Message -Level Debug -Message "We have to build a connect string, using these parameters: $($boundparams.Keys)"
                        $azureconnstring = New-DbaConnectionString @boundparams
                    }
                }

                if ($Tenant -or $AuthenticationType -eq "AD Universal with MFA Support") {
                    if ($Thumbprint) {
                        Stop-Function -Message "Thumbprint is unsupported at this time. Sorry, some DLLs were all messed up."
                        return
                    }

                    $appid = Get-DbatoolsConfigValue -FullName 'azure.appid'
                    $clientsecret = Get-DbatoolsConfigValue -FullName 'azure.clientsecret'

                    if (($appid -and $clientsecret) -and -not $SqlCredential) {
                        $SqlCredential = New-Object System.Management.Automation.PSCredential ($appid, $clientsecret)
                    }

                    if (-not $azurevm -and (-not $SqlCredential -and $Tenant)) {
                        Stop-Function -Message "When using Tenant, SqlCredential must be specified."
                        return
                    }

                    if (-not $Database) {
                        Stop-Function -Message "When using AD Universal with MFA Support, database must be specified."
                        return
                    }

                    if (-not $SqlCredential) {
                        Stop-Function -Message "When using Tenant, SqlCredential must be specified."
                        return
                    }
                    Write-Message -Level Verbose -Message "Creating renewable token"
                    $accesstoken = (New-DbaAzAccessToken -Type RenewableServicePrincipal -Subtype AzureSqlDb -Tenant $Tenant -Credential $SqlCredential)
                }

                try {
                    # this is the way, as recommended by Microsoft
                    # https://docs.microsoft.com/en-us/sql/relational-databases/security/encryption/configure-always-encrypted-using-powershell?view=sql-server-2017
                    $maskedConnString = Hide-ConnectionString $azureconnstring
                    Write-Message -Level Verbose -Message "Connecting to $maskedConnString"
                    try {
                        $sqlconn = New-Object System.Data.SqlClient.SqlConnection $azureconnstring
                    } catch {
                        Write-Message -Level Warning "Connection to $instance not supported yet. Please use MFA instead."
                        continue
                    }
                    # assign this twice, not sure why but hey it works better
                    if ($accesstoken) {
                        $sqlconn.AccessToken = $accesstoken
                    }
                    $serverconn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $sqlconn
                    Write-Message -Level Verbose -Message "Connecting to Azure: $instance"
                    # assign it twice, not sure why but hey it works better
                    if ($accesstoken) {
                        $serverconn.AccessToken = $accesstoken
                    }
                    $null = $serverconn.Connect()
                    Write-Message -Level Debug -Message "will build server with [Microsoft.SqlServer.Management.Common.ServerConnection]serverconn (serverconn.ServerInstance = '$($serverconn.ServerInstance)')"
                    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $serverconn
                    Write-Message -Level Debug -Message "server was build with server.Name = '$($server.Name)'"
                    # Make ComputerName easily available in the server object
                    Add-Member -InputObject $server -NotePropertyName IsAzure -NotePropertyValue $true -Force
                    Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $instance.ComputerName -Force
                    Add-Member -InputObject $server -NotePropertyName DbaInstanceName -NotePropertyValue $instance.InstanceName -Force
                    Add-Member -InputObject $server -NotePropertyName NetPort -NotePropertyValue $instance.Port -Force
                    Add-Member -InputObject $server -NotePropertyName ConnectedAs -NotePropertyValue $server.ConnectionContext.TrueLogin -Force
                    # Azure has a really hard time with $server.Databases, which we rely on heavily. Fix that.
                    <# Fixing that changed the db context back to master so we're SOL here until we can figure out another way.
                    # $currentdb = $server.Databases[$Database] | Where-Object Name -eq $server.ConnectionContext.CurrentDatabase | Select-Object -First 1
                    if ($currentdb) {
                        Add-Member -InputObject $server -NotePropertyName Databases -NotePropertyValue @{ $currentdb.Name = $currentdb } -Force
                    }#>
                    $server
                    continue
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }

            #region Input Object was a server object
            if ($instance.Type -like "Server" -or ($isAzure -and $instance.InputObject.ConnectionContext.IsOpen)) {
                Write-Message -Level Debug -Message "instance.Type -like Server (or Azure) - so we have already the full smo"
                if ($instance.InputObject.ConnectionContext.IsOpen -eq $false) {
                    Write-Message -Level Debug -Message "We connect to the instance with instance.InputObject.ConnectionContext.Connect()"
                    $instance.InputObject.ConnectionContext.Connect()
                }
                if ($SqlConnectionOnly) {
                    $instance.InputObject.ConnectionContext.SqlConnectionObject
                    continue
                } else {
                    Write-Message -Level Debug -Message "We return the instance object with: ComputerName = '$($instance.InputObject.ComputerName)', NetName = '$($instance.InputObject.NetName)', Name = '$($instance.InputObject.Name)'"
                    $instance.InputObject
                    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::SetInstance($instance.FullSmoName.ToLowerInvariant(), $instance.InputObject.ConnectionContext.Copy(), ($instance.InputObject.ConnectionContext.FixedServerRoles -match "SysAdmin"))

                    # Update cache for instance names
                    if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $instance.FullSmoName.ToLowerInvariant()) {
                        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $instance.FullSmoName.ToLowerInvariant()
                    }
                    continue
                }
            }
            #endregion Input Object was a server object

            #region Input Object was anything else
            Write-Message -Level Debug -Message "Input Object was anything else, so not full smo and we have to go on and build one"
            if ($instance.Type -like "SqlConnection") {
                Write-Message -Level Debug -Message "instance.Type -like SqlConnection"
                Write-Message -Level Debug -Message "will build server with [System.Data.SqlClient.SqlConnection]instance.InputObject (instance.InputObject.DataSource = '$($instance.InputObject.DataSource)')   "
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server($instance.InputObject)
                Write-Message -Level Debug -Message "server was build with server.Name = '$($server.Name)'"

                if ($server.ConnectionContext.IsOpen -eq $false) {
                    Write-Message -Level Debug -Message "We connect to the server with server.ConnectionContext.Connect()"
                    $server.ConnectionContext.Connect()
                }
                if ($SqlConnectionOnly) {
                    Write-Message -Level Debug -Message "We have SqlConnectionOnly"
                    if ($MinimumVersion -and $server.VersionMajor) {
                        Write-Message -Level Debug -Message "We test MinimumVersion"
                        if ($server.versionMajor -lt $MinimumVersion) {
                            Stop-Function -Message "SQL Server version $MinimumVersion required - $server not supported." -Continue
                        }
                    }

                    if ($AzureUnsupported -and $server.DatabaseEngineType -eq "SqlAzureDatabase") {
                        Stop-Function -Message "Azure SQL Database not supported" -Continue
                    }
                    Write-Message -Level Debug -Message "We return server.ConnectionContext.SqlConnectionObject"
                    $server.ConnectionContext.SqlConnectionObject
                    continue
                } else {
                    Write-Message -Level Debug -Message "We don't have SqlConnectionOnly"
                    if (-not $server.ComputerName) {
                        Write-Message -Level Debug -Message "We don't have ComputerName, so adding IsAzure = '$false', ComputerName = instance.ComputerName = '$($instance.ComputerName)', DbaInstanceName = instance.InstanceName = '$($instance.InstanceName)', NetPort = instance.Port = '$($instance.Port)', ConnectedAs = server.ConnectionContext.TrueLogin = '$($server.ConnectionContext.TrueLogin)'"
                        Add-Member -InputObject $server -NotePropertyName IsAzure -NotePropertyValue $false -Force
                        Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $instance.ComputerName -Force
                        Add-Member -InputObject $server -NotePropertyName DbaInstanceName -NotePropertyValue $instance.InstanceName -Force
                        Add-Member -InputObject $server -NotePropertyName NetPort -NotePropertyValue $instance.Port -Force
                        Add-Member -InputObject $server -NotePropertyName ConnectedAs -NotePropertyValue $server.ConnectionContext.TrueLogin -Force
                    }
                    if ($MinimumVersion -and $server.VersionMajor) {
                        Write-Message -Level Debug -Message "We test MinimumVersion"
                        if ($server.versionMajor -lt $MinimumVersion) {
                            Stop-Function -Message "SQL Server version $MinimumVersion required - $server not supported." -Continue
                        }
                    }

                    if ($AzureUnsupported -and $server.DatabaseEngineType -eq "SqlAzureDatabase") {
                        Stop-Function -Message "Azure SQL Database not supported" -Continue
                    }

                    [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::SetInstance($instance.FullSmoName.ToLowerInvariant(), $server.ConnectionContext.Copy(), ($server.ConnectionContext.FixedServerRoles -match "SysAdmin"))
                    # Update cache for instance names
                    if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $instance.FullSmoName.ToLowerInvariant()) {
                        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $instance.FullSmoName.ToLowerInvariant()
                    }
                    Write-Message -Level Debug -Message "We return server with server.Name = '$($server.Name)'"
                    $server
                    continue
                }
            }

            if ($isConnectionString) {
                Write-Message -Level Debug -Message "isConnectionString is true"
                # this is the way, as recommended by Microsoft
                # https://docs.microsoft.com/en-us/sql/relational-databases/security/encryption/configure-always-encrypted-using-powershell?view=sql-server-2017
                $sqlconn = New-Object System.Data.SqlClient.SqlConnection $connstring
                $serverconn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $sqlconn
                $null = $serverconn.Connect()
                Write-Message -Level Debug -Message "will build server with [Microsoft.SqlServer.Management.Common.ServerConnection]serverconn (serverconn.ServerInstance = '$($serverconn.ServerInstance)')"
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server $serverconn
                Write-Message -Level Debug -Message "server was build with server.Name = '$($server.Name)'"
            } elseif (-not $isAzure) {
                Write-Message -Level Debug -Message "isConnectionString is false"
                Write-Message -Level Debug -Message "will build server with instance.FullSmoName = '$($instance.FullSmoName)'"
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server($instance.FullSmoName)
                Write-Message -Level Debug -Message "server was build with server.Name = '$($server.Name)'"
            }

            if ($AppendConnectionString) {
                Write-Message -Level Debug -Message "AppendConnectionString was set"
                $connstring = $server.ConnectionContext.ConnectionString
                $server.ConnectionContext.ConnectionString = "$connstring;$appendconnectionstring"
                $server.ConnectionContext.Connect()
            } elseif (-not $isAzure -and -not $isConnectionString) {
                Write-Message -Level Debug -Message "AppendConnectionString was not set"
                # It's okay to skip Azure because this is addressed above with New-DbaConnectionString
                $server.ConnectionContext.ApplicationName = $ClientName

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
                    $server.ConnectionContext.TrustServerCertificate = $TrustServerCertificate
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

                Write-Message -Level Debug -Message "We try to connect"
                try {
                    # parse out sql credential to figure out if it's Windows or SQL Login
                    if ($null -ne $SqlCredential.UserName -and -not $isAzure) {
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
                        # When the Connect method is called, the connection is not automatically released.
                        # The Disconnect method must be called explicitly to release the connection to the connection pool.
                        # https://docs.microsoft.com/en-us/sql/relational-databases/server-management-objects-smo/create-program/disconnecting-from-an-instance-of-sql-server
                        Write-Message -Level Debug -Message "We try nonpooled connection with server.ConnectionContext.Connect()"
                        $server.ConnectionContext.Connect()
                    } elseif ($authtype -eq "Windows Authentication with Credential") {
                        Write-Message -Level Debug -Message "We have authtype -eq Windows Authentication with Credential"
                        # Make it connect in a natural way, hard to explain.
                        # See https://docs.microsoft.com/en-us/sql/relational-databases/server-management-objects-smo/create-program/connecting-to-an-instance-of-sql-server
                        $null = $server.Information.Version
                        if ($server.ConnectionContext.IsOpen -eq $false) {
                            # Sometimes, however, the above may not connect as promised. Force it.
                            # See https://github.com/sqlcollaborative/dbatools/pull/4426
                            Write-Message -Level Debug -Message "We try connection with server.ConnectionContext.Connect()"
                            $server.ConnectionContext.Connect()
                        }
                    } else {
                        if (-not $isAzure) {
                            # SqlConnectionObject.Open() enables connection pooling does not support
                            # alternative Windows Credentials and passes default credentials
                            # See https://github.com/sqlcollaborative/dbatools/pull/3809
                            Write-Message -Level Debug -Message "We try connection with server.ConnectionContext.SqlConnectionObject.Open()"
                            $server.ConnectionContext.SqlConnectionObject.Open()
                        }
                    }
                    Write-Message -Level Debug -Message "Connect was successful"
                } catch {
                    Write-Message -Level Debug -Message "Connect was not successful"
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

            # Register the connected instance, so that the TEPP updater knows it's been connected to and starts building the cache
            [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::SetInstance($instance.FullSmoName.ToLowerInvariant(), $server.ConnectionContext.Copy(), ($server.ConnectionContext.FixedServerRoles -match "SysAdmin"))

            # Update cache for instance names
            if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $instance.FullSmoName.ToLowerInvariant()) {
                [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $instance.FullSmoName.ToLowerInvariant()
            }

            # Update lots of registered stuff
            if (-not [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled) {
                foreach ($scriptBlock in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsFast)) {
                    Invoke-TEPPCacheUpdate -ScriptBlock $scriptBlock
                }
            }

            # By default, SMO initializes several properties. We push it to the limit and gather a bit more
            # this slows down the connect a smidge but drastically improves overall performance
            # especially when dealing with a multitude of servers
            if ($loadedSmoVersion -ge 11 -and -not $isAzure) {
                try {
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
                } catch {
                    # perhaps a DLL issue, continue going
                }
            }

            if ($SqlConnectionOnly) {
                Write-Message -Level Debug -Message "SqlConnectionOnly, so returning server.ConnectionContext.SqlConnectionObject"
                $server.ConnectionContext.SqlConnectionObject
                continue
            } else {
                Write-Message -Level Debug -Message "no SqlConnectionOnly, so we go on"
                if (-not $server.ComputerName) {
                    Write-Message -Level Debug -Message "we don't have server.ComputerName"
                    Write-Message -Level Debug -Message "but we would have instance.ComputerName = '$($instance.ComputerName)'"
                    # Not every environment supports .NetName
                    if ($server.DatabaseEngineType -ne "SqlAzureDatabase") {
                        try {
                            Write-Message -Level Debug -Message "we try to use server.NetName for computername"
                            $computername = $server.NetName
                        } catch {
                            Write-Message -Level Debug -Message "Ups, failed so we use instance.ComputerName"
                            $computername = $instance.ComputerName
                        }
                        Write-Message -Level Debug -Message "Ok, computername = server.NetName = '$computername'"
                    }
                    # SQL on Linux is often on docker and the internal name is not useful
                    if (-not $computername -or $server.HostPlatform -eq "Linux") {
                        Write-Message -Level Debug -Message "SQL on Linux is often on docker and the internal name is not useful - we use instance.ComputerName as computername"
                        $computername = $instance.ComputerName
                        Write-Message -Level Debug -Message "Ok, computername is now '$computername'"
                    }
                    Write-Message -Level Debug -Message "We add IsAzure = '$false', ComputerName = computername = '$computername', DbaInstanceName = instance.InstanceName = '$($instance.InstanceName)', NetPort = instance.Port = '$($instance.Port)', ConnectedAs = server.ConnectionContext.TrueLogin = '$($server.ConnectionContext.TrueLogin)'"
                    Add-Member -InputObject $server -NotePropertyName IsAzure -NotePropertyValue $false -Force
                    Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $computername -Force
                    Add-Member -InputObject $server -NotePropertyName DbaInstanceName -NotePropertyValue $instance.InstanceName -Force
                    Add-Member -InputObject $server -NotePropertyName NetPort -NotePropertyValue $instance.Port -Force
                    Add-Member -InputObject $server -NotePropertyName ConnectedAs -NotePropertyValue $server.ConnectionContext.TrueLogin -Force
                }
            }

            if ($MinimumVersion -and $server.VersionMajor) {
                if ($server.versionMajor -lt $MinimumVersion) {
                    Stop-Function -Message "SQL Server version $MinimumVersion required - $server not supported." -Continue
                }
            }

            if ($AzureUnsupported -and $server.DatabaseEngineType -eq "SqlAzureDatabase") {
                Stop-Function -Message "Azure SQL Database not supported" -Continue
            }

            Write-Message -Level Debug -Message "We return server with server.Name = '$($server.Name)'"
            $server
            continue
        }
        #endregion Input Object was anything else
    }
}
