function Connect-DbaInstance {
    <#
    .SYNOPSIS
        Creates a persistent SQL Server Management Object (SMO) connection for database operations.

    .DESCRIPTION
        This command creates a reusable SQL Server Management Object (SMO) that serves as the foundation for most dbatools operations. Think of it as your entry point for connecting to SQL Server instances, whether on-premises, in Azure, or anywhere else.

        The returned SMO server object handles authentication automatically, detecting whether to use Windows integrated security, SQL authentication, or Azure Active Directory based on your credentials. It supports connection pooling by default for better performance and can handle complex scenarios like failover partners, dedicated admin connections, and multi-subnet environments.

        This is the connection object you'll pass to other dbatools commands like Get-DbaDatabase, Invoke-DbaQuery, or Backup-DbaDatabase. Rather than each command establishing its own connection, you create one persistent connection here and reuse it, which is both faster and more reliable.

        The connection includes helpful properties for scripting like ComputerName, IsAzure, and ConnectedAs, plus it automatically sets an identifiable ApplicationName in your connection string so you can track dbatools sessions in profiler or extended events.

        For Azure connections, it handles the various authentication methods including service principals, managed identities, and access tokens. For on-premises instances, it supports Windows authentication (including alternative credentials), SQL logins, and dedicated administrator connections for emergency access.

        Reference documentation:
        https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.connectionstring.aspx
        https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnectionstringbuilder.aspx
        https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.aspx

        To execute SQL commands directly: $server.ConnectionContext.ExecuteReader($sql) or $server.Databases['master'].ExecuteNonQuery($sql)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Database
        Specifies the initial database context for the connection instead of connecting to the default database.
        Useful when you need to connect directly to a specific database or when the login's default database is unavailable.

    .PARAMETER AppendConnectionString
        Adds custom connection string parameters to the generated connection string.
        Use this for advanced connection properties like custom timeout values, SSL settings, or application-specific parameters that aren't covered by other parameters.

    .PARAMETER ApplicationIntent
        Declares the application workload type when connecting to an Always On Availability Group.
        Use "ReadOnly" to route connections to readable secondary replicas for reporting workloads, reducing load on the primary replica.

    .PARAMETER BatchSeparator
        Sets the batch separator for multi-statement SQL execution, defaulting to "GO".
        Change this when working with scripts that use different batch separators or when "GO" conflicts with your SQL content.

    .PARAMETER ClientName
        Sets a custom application name in the connection string for identification in SQL Server monitoring tools.
        Use this to distinguish dbatools sessions from other applications when analyzing connections in Profiler, Extended Events, or sys.dm_exec_sessions.

    .PARAMETER ConnectTimeout
        Sets the connection timeout in seconds before the connection attempt fails.
        Increase this for slow networks or busy servers, or decrease it for faster failure detection in automated scripts. Azure SQL Database connections typically need 30 seconds.

    .PARAMETER EncryptConnection
        Forces SSL encryption for all data transmitted between client and server.
        Required for many compliance scenarios and recommended for connections over untrusted networks. Ensure server certificates are properly configured to avoid connection failures.

    .PARAMETER FailoverPartner
        Specifies the failover partner server name for database mirroring configurations.
        Use this when connecting to databases configured for database mirroring to enable automatic failover if the primary server becomes unavailable.

    .PARAMETER LockTimeout
        Sets the lock timeout in seconds for transactions on this connection.
        Use this to control how long statements wait for locks before timing out, which helps prevent long-running blocking scenarios.

    .PARAMETER MaxPoolSize
        Sets the maximum number of connections allowed in the connection pool for this connection string.
        Increase this for applications with high concurrency requirements, but be mindful of server resource limits and licensing constraints.

    .PARAMETER MinPoolSize
        Sets the minimum number of connections maintained in the connection pool for this connection string.
        Use this to pre-warm the connection pool for better performance when you know connections will be used frequently.

    .PARAMETER MultipleActiveResultSets
        Enables Multiple Active Result Sets (MARS) allowing multiple commands to be executed simultaneously on a single connection.
        Use this when you need to execute multiple queries concurrently without opening additional connections, though it can impact performance.

    .PARAMETER MultiSubnetFailover
        Enables faster detection and connection to the active server in Always On Availability Groups across multiple subnets.
        Essential for AG configurations where replicas are in different subnets, reducing connection time during failover scenarios.

    .PARAMETER NetworkProtocol
        Specifies the network protocol for connecting to SQL Server.
        Use "TcpIp" for remote connections, "NamedPipes" for local connections with better security, or "SharedMemory" for fastest local connections. Most modern environments use TcpIp.

    .PARAMETER NonPooledConnection
        Creates a dedicated connection that bypasses connection pooling.
        Use this for long-running operations, dedicated admin connections, or when you need to ensure the connection isn't shared with other processes.

    .PARAMETER PacketSize
        Sets the network packet size in bytes for communication with SQL Server.
        Increase from the default 4096 bytes to improve performance for large data transfers, but ensure the server is configured to support the same packet size.

    .PARAMETER PooledConnectionLifetime
        Sets the maximum lifetime in seconds for pooled connections before they're discarded and recreated.
        Use this in clustered environments to force load balancing or to refresh connections periodically. Zero means unlimited lifetime.

    .PARAMETER SqlExecutionModes
        Controls how SQL commands are processed by the connection.
        Use "CaptureSql" to generate scripts without execution, "ExecuteAndCaptureSql" to both execute and log commands, or "ExecuteSql" for normal execution.

    .PARAMETER StatementTimeout
        Sets the timeout in seconds for SQL statement execution before canceling the command.
        Use this to prevent runaway queries from blocking operations indefinitely. Zero means unlimited, but set reasonable limits for production environments.

    .PARAMETER TrustServerCertificate
        Bypasses certificate validation when using encrypted connections.
        Use this for development environments or when connecting to servers with self-signed certificates, but avoid in production for security reasons.

    .PARAMETER AllowTrustServerCertificate
        Attempts connection with proper TLS validation first, then retries with TrustServerCertificate if the initial connection fails due to certificate validation.
        Provides a secure-by-default approach for mixed environments where some servers have valid certificates and others do not.
        Only retries on certificate validation failures, not on other connection errors like authentication or network issues.

    .PARAMETER WorkstationId
        Sets the workstation name visible in SQL Server monitoring and session information.
        Use this to identify the source of connections in sys.dm_exec_sessions or when troubleshooting connection issues.

    .PARAMETER AlwaysEncrypted
        Enables Always Encrypted support for accessing encrypted columns in databases with column-level encryption.
        Required when working with sensitive data protected by Always Encrypted, allowing proper decryption of encrypted column values.

    .PARAMETER SqlConnectionOnly
        Returns only a SqlConnection object instead of the full SMO server object.
        Use this when you only need basic connection functionality and want to reduce memory overhead or avoid SMO initialization.

    .PARAMETER AzureUnsupported
        Causes the connection to fail if the target is detected as Azure SQL Database.
        Use this to prevent operations that are incompatible with Azure SQL Database from attempting to connect to cloud instances.

    .PARAMETER AzureDomain
        Specifies the domain for Azure SQL Database connections, defaulting to database.windows.net.
        Use this when connecting to Azure SQL instances in sovereign clouds or custom domains that require different authentication methods.

    .PARAMETER MinimumVersion
        Specifies the minimum SQL Server version required for the connection to succeed.
        Use this to ensure scripts only run against SQL Server versions that support the required features, preventing compatibility issues.

    .PARAMETER Tenant
        Specifies the Azure Active Directory tenant ID for Azure SQL Database authentication.
        Required when using service principal authentication or when your account exists in multiple Azure AD tenants.

    .PARAMETER AccessToken
        Authenticates to Azure SQL Database using an access token generated by Get-AzAccessToken or New-DbaAzAccessToken.
        Use this for service principal authentication or when integrating with Azure automation that provides pre-generated tokens. Tokens expire after one hour and cannot be renewed.

    .PARAMETER DedicatedAdminConnection
        Creates a dedicated administrator connection (DAC) for emergency access to SQL Server.
        Use this when SQL Server is unresponsive to regular connections, allowing you to diagnose and resolve critical issues. Remember to manually disconnect the connection when finished.

    .PARAMETER DisableException
        Changes exception handling from throwing errors to displaying warnings.
        Use this in interactive sessions where you want graceful error handling instead of script-stopping exceptions, which is the default behavior for this command.

    .NOTES
        Tags: Connection
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

        Creates an SMO Server object that connects using Windows Authentication and uses the client name "my connection".
        So when you open up profiler or use extended events, you can search for "my connection".

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
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL DB using AAD / Azure Active Directory, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Database dbatools -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL DB using AAD Integrated Auth, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance "myserver.public.cust123.database.windows.net,3342" -Database mydb -SqlCredential me@mydomain.onmicrosoft.com -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure SQL Managed instance using AAD / Azure Active Directory, then performs a sample query.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance db.mycustomazure.com -Database mydb -AzureDomain mycustomazure.com -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        In the event your AzureSqlDb is not on a database.windows.net domain, you can set a custom domain using the AzureDomain parameter.
        This tells Connect-DbaInstance to login to the database using the method that works best with Azure.

    .EXAMPLE
        PS C:\> $connstring = "Data Source=TCP:mydb.database.windows.net,1433;User ID=sqladmin;Password=adfasdf;Connect Timeout=30;"
        PS C:\> $server = Connect-DbaInstance -ConnectionString $connstring
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Logs into Azure using a preconstructed connstring, then performs a sample query.
        ConnectionString is an alias of SqlInstance, so you can use -SqlInstance $connstring as well.

    .EXAMPLE
        PS C:\> $cred = Get-Credential guid-app-id-here # appid for username, clientsecret for password
        PS C:\> $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Database abc -SqlCredential $cred -Tenant guidheremaybename
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        When connecting from a non-Azure workstation, logs into Azure using Universal with MFA Support with a username and password, then performs a sample query.

        Note that generating access tokens is not supported on Core, so when using Tenant on Core, we rewrite the connection string with Active Directory Service Principal authentication instead.

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
        PS C:\> $azureCredential = Get-Credential -Message 'Azure Credential'
        PS C:\> $azureAccount = Connect-AzAccount -Credential $azureCredential
        PS C:\> $azureToken = Get-AzAccessToken -ResourceUrl https://database.windows.net
        PS C:\> $azureInstance = "YOURSERVER.database.windows.net"
        PS C:\> $azureDatabase = "MYDATABASE"
        PS C:\> $server = Connect-DbaInstance -SqlInstance $azureInstance -Database $azureDatabase -AccessToken $azureToken
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Connect to an Azure SQL Database or an Azure SQL Managed Instance with an AccessToken.
        Works with both Azure PowerShell v13 (string tokens) and v14+ (SecureString tokens).
        Note that the token is valid for only one hour and cannot be renewed automatically.

    .EXAMPLE
        PS C:\> # Azure PowerShell v14+ with SecureString token support
        PS C:\> Connect-AzAccount
        PS C:\> $azureToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token
        PS C:\> $azureInstance = "YOUR-AZURE-SQL-MANAGED-INSTANCE.database.windows.net"
        PS C:\> $server = Connect-DbaInstance -SqlInstance $azureInstance -Database "YOURDATABASE" -AccessToken $azureToken
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Connect to an Azure SQL Managed Instance using Azure PowerShell v14+ where Get-AzAccessToken returns a SecureString.
        The function automatically detects and converts the SecureString token to the required format.

    .EXAMPLE
        PS C:\> $token = New-DbaAzAccessToken -Type RenewableServicePrincipal -Subtype AzureSqlDb -Tenant $tenantid -Credential $cred
        PS C:\> Connect-DbaInstance -SqlInstance sample.database.windows.net -Accesstoken $token

        Uses dbatools to generate the access token for an Azure SQL Database, then logs in using that AccessToken.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance srv1 -DedicatedAdminConnection
        PS C:\> $dbaProcess = Get-DbaProcess -SqlInstance $server -ExcludeSystemSpids
        PS C:\> $killedProcess = $dbaProcess | Out-GridView -OutputMode Multiple | Stop-DbaProcess
        PS C:\> $server | Disconnect-DbaInstance

        Creates a dedicated admin connection (DAC) to the default instance on server srv1.
        Receives all non-system processes from the instance using the DAC.
        Opens a grid view to let the user select processes to be stopped.
        Closes the connection.

    .EXAMPLE
        PS C:\> $servers = "sql1", "sql2", "sql3"
        PS C:\> $servers | Connect-DbaInstance -AllowTrustServerCertificate

        Connects to multiple servers where some may have valid TLS certificates and others may not.
        For each server, attempts connection with proper TLS validation first.
        If a server fails due to certificate validation, automatically retries with TrustServerCertificate enabled.
        This provides a secure-by-default approach for mixed environments without requiring separate connection logic.

    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
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
        [int]$ConnectTimeout = ([Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout),
        [switch]$EncryptConnection = (Get-DbatoolsConfigValue -FullName 'sql.connection.encrypt'),
        [string]$FailoverPartner,
        [int]$LockTimeout,
        [int]$MaxPoolSize,
        [int]$MinPoolSize,
        [int]$MinimumVersion,
        [switch]$MultipleActiveResultSets,
        [switch]$MultiSubnetFailover = (Get-DbatoolsConfigValue -FullName 'sql.connection.multisubnetfailover'),
        [ValidateSet('TcpIp', 'NamedPipes', 'Multiprotocol', 'AppleTalk', 'BanyanVines', 'Via', 'SharedMemory', 'NWLinkIpxSpx')]
        [string]$NetworkProtocol = (Get-DbatoolsConfigValue -FullName 'sql.connection.protocol'),
        [switch]$NonPooledConnection,
        [int]$PacketSize = (Get-DbatoolsConfigValue -FullName 'sql.connection.packetsize'),
        [int]$PooledConnectionLifetime,
        [ValidateSet('CaptureSql', 'ExecuteAndCaptureSql', 'ExecuteSql')]
        [string]$SqlExecutionModes,
        [int]$StatementTimeout = (Get-DbatoolsConfigValue -FullName 'sql.execution.timeout'),
        [switch]$TrustServerCertificate = (Get-DbatoolsConfigValue -FullName 'sql.connection.trustcert'),
        [switch]$AllowTrustServerCertificate = (Get-DbatoolsConfigValue -FullName 'sql.connection.allowtrustcert'),
        [string]$WorkstationId,
        [switch]$AlwaysEncrypted,
        [string]$AppendConnectionString,
        [switch]$SqlConnectionOnly,
        [string]$AzureDomain = "database.windows.net",
        [string]$Tenant = (Get-DbatoolsConfigValue -FullName 'azure.tenantid'),
        [psobject]$AccessToken,
        [switch]$DedicatedAdminConnection,
        [switch]$DisableException
    )
    begin {
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

                if ($ENV:APPVEYOR_BUILD_FOLDER -or ([Dataplat.Dbatools.Message.MEssageHost]::DeveloperMode)) { Stop-Function -Message }
                else {
                    Write-Message -Level Warning -Message "Failed TEPP Caching: $($scriptBlock.ToString() | Select-String '"(.*?)"' | ForEach-Object { $_.Matches[0].Groups[1].Value })" -ErrorRecord $_ 3>$null
                }
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

        #see #7753
        $Fields_Job = 'LastRunOutcome', 'CurrentRunStatus', 'CurrentRunStep', 'CurrentRunRetryAttempt', 'NextRunScheduleID', 'NextRunDate', 'LastRunDate', 'JobType', 'HasStep', 'HasServer', 'CurrentRunRetryAttempt', 'HasSchedule', 'Category', 'CategoryID', 'CategoryType', 'OperatorToEmail', 'OperatorToNetSend', 'OperatorToPage'
        if ($AzureDomain) { $AzureDomain = [regex]::escape($AzureDomain) }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        # if tenant is specified with a GUID username such as 21f5633f-6776-4bab-b878-bbd5e3e5ed72 (for clientid)
        if ($Tenant -and -not $AccessToken -and $SqlCredential.UserName -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {

            try {
                if ($PSVersionTable.PSEdition -eq "Core") {
                    Write-Message -Level Verbose "Generating access tokens is not supported on Core. Will try connection string with Active Directory Service Principal instead. See https://github.com/dataplat/dbatools/pull/7610 for more information."
                    $tryconnstring = $true
                } else {
                    Write-Message -Level Verbose "Tenant detected, getting access token"
                    $AccessToken = (New-DbaAzAccessToken -Type RenewableServicePrincipal -Subtype AzureSqlDb -Tenant $Tenant -Credential $SqlCredential -ErrorAction Stop).GetAccessToken()
                    $PSBoundParameters.Tenant = $Tenant = $null
                    $PSBoundParameters.SqlCredential = $SqlCredential = $null
                    $PSBoundParameters.AccessToken = $AccessToken
                }

            } catch {
                $errormessage = Get-ErrorMessage -Record $_
                Stop-Function -Message "Failed to get access token for Azure SQL DB ($errormessage)"
                return
            }
        }

        Write-Message -Level Debug -Message "Starting process block"
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Starting loop for '$instance': ComputerName = '$($instance.ComputerName)', InstanceName = '$($instance.InstanceName)', IsLocalHost = '$($instance.IsLocalHost)', Type = '$($instance.Type)'"

            if ($tryconnstring) {
                $azureserver = $instance.InputObject
                if ($Database) {
                    $instance = [DbaInstanceParameter]"Server=$azureserver; Authentication=Active Directory Service Principal; Database=$Database; User Id=$($SqlCredential.UserName); Password=$($SqlCredential.GetNetworkCredential().Password)"
                } else {
                    $instance = [DbaInstanceParameter]"Server=$azureserver; Authentication=Active Directory Service Principal; User Id=$($SqlCredential.UserName); Password=$($SqlCredential.GetNetworkCredential().Password)"
                }
            }

            Write-Message -Level Debug -Message "Immediately checking for Azure"
            if ($instance.ComputerName -match $AzureDomain -or $instance.InputObject.ComputerName -match $AzureDomain) {
                Write-Message -Level Verbose -Message "Azure detected"
                $isAzure = $true
            } else {
                $isAzure = $false
            }

            <#
            Best practice:
            * Create a smo server object by submitting the name of the instance as a string to SqlInstance and additional parameters to configure the connection
            * Reuse the smo server object in all following calls as SqlInstance
            * When reusing the smo server object, only the following additional parameters are allowed with Connect-DbaInstance:
                - Database, ApplicationIntent, NonPooledConnection, StatementTimeout (command clones ConnectionContext and returns new smo server object)
                - AzureUnsupported (command fails if target is Azure)
                - MinimumVersion (command fails if target version is too old)
                - SqlConnectionOnly (command returns only the ConnectionContext.SqlConnectionObject)
            Commands that use these parameters:
            * ApplicationIntent
                - Invoke-DbaQuery
            * NonPooledConnection
                - Install-DbaFirstResponderKit
            * StatementTimeout (sometimes not as a parameter, they should changed to do so)
                - Backup-DbaDatabase
                - Restore-DbaDatabase
                - Get-DbaTopResourceUsage
                - Import-DbaCsv
                - Invoke-DbaDbLogShipping
                - Invoke-DbaDbShrink
                - Invoke-DbaDbUpgrade
                - Set-DbaDbCompression
                - Test-DbaDbCompression
                - Start-DbccCheck
            * AzureUnsupported
                - Backup-DbaDatabase
                - Copy-DbaLogin
                - Get-DbaLogin
                - Set-DbaLogin
                - Get-DbaDefaultPath
                - Get-DbaUserPermission
                - Get-DbaXESession
                - New-DbaCustomError
                - Remove-DbaCustomError
            Additional possibilities as input to SqlInstance:
            * A smo connection object [Microsoft.Data.SqlClient.SqlConnection] (InputObject is used to build smo server object)
            * A smo registered server object [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer] (FullSmoName und InputObject.ConnectionString are used to build smo server object)
            * A connections string [String] (FullSmoName und InputObject are used to build smo server object)
            Limitations of these additional possibilities:
            * All additional parameters are ignored, a warning is displayed if they are used
            * Currently, connection pooling does not work with connections that are build from connection strings
            * All parameters that configure the connection and where they can be set (here just for documentation and future development):
                - AppendConnectionString      SqlConnectionInfo.AdditionalParameters
                - ApplicationIntent           SqlConnectionInfo.ApplicationIntent          SqlConnectionStringBuilder['ApplicationIntent']
                - AuthenticationType          SqlConnectionInfo.Authentication             SqlConnectionStringBuilder['Authentication']
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
                - StatementTimeout            (SqlConnectionInfo.QueryTimeout?)                                                                      ConnectionContext.StatementTimeout
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

            # Analyse input object and extract necessary parts
            if ($instance.Type -like 'Server') {
                Write-Message -Level Verbose -Message "Server object passed in, will do some checks and then return the original object"
                $inputObjectType = 'Server'
                $isNewConnection = $false
                $inputObject = $instance.InputObject
            } elseif ($instance.Type -like 'SqlConnection') {
                Write-Message -Level Verbose -Message "SqlConnection object passed in, will build server object from instance.InputObject, do some checks and then return the server object"
                $inputObjectType = 'SqlConnection'
                $isNewConnection = $false
                $inputObject = $instance.InputObject
            } elseif ($instance.Type -like 'RegisteredServer') {
                Write-Message -Level Verbose -Message "RegisteredServer object passed in, will build empty server object, set connection string from instance.InputObject.ConnectionString, do some checks and then return the server object"
                $inputObjectType = 'RegisteredServer'
                $isNewConnection = $true
                $inputObject = $instance.InputObject
                $serverName = $instance.FullSmoName
                $connectionString = $instance.InputObject.ConnectionString
            } elseif ($instance.IsConnectionString) {
                Write-Message -Level Verbose -Message "Connection string is passed in, will build empty server object, set connection string from instance.InputObject, do some checks and then return the server object"
                $inputObjectType = 'ConnectionString'
                $isNewConnection = $true
                $serverName = $instance.FullSmoName
                $connectionString = $instance.InputObject | Convert-ConnectionString
            } else {
                Write-Message -Level Verbose -Message "String is passed in, will build server object from instance object and other parameters, do some checks and then return the server object"
                $inputObjectType = 'String'
                $isNewConnection = $true
                $serverName = $instance.FullSmoName
            }

            # Check for ignored parameters
            # We do not check for SqlCredential as this parameter is widely used even if a server SMO is passed in and we don't want to output a message for that
            $ignoredParameters = 'BatchSeparator', 'ClientName', 'ConnectTimeout', 'EncryptConnection', 'LockTimeout', 'MaxPoolSize', 'MinPoolSize', 'NetworkProtocol', 'PacketSize', 'PooledConnectionLifetime', 'SqlExecutionModes', 'TrustServerCertificate', 'AllowTrustServerCertificate', 'WorkstationId', 'FailoverPartner', 'MultipleActiveResultSets', 'MultiSubnetFailover', 'AppendConnectionString', 'AccessToken'
            if ($inputObjectType -eq 'Server') {
                if (Test-Bound -ParameterName $ignoredParameters) {
                    Write-Message -Level Warning -Message "Additional parameters are passed in, but they will be ignored"
                }
            } elseif ($inputObjectType -in 'RegisteredServer', 'ConnectionString' ) {
                # Parameter TrustServerCertificate changes the connection string be allow connections to instances with the default self-signed certificate
                if (Test-Bound -ParameterName 'TrustServerCertificate') {
                    Write-Message -Level Verbose -Message "Additional parameter TrustServerCertificate is passed in and will override other settings"
                } elseif (Test-Bound -ParameterName $ignoredParameters, 'ApplicationIntent', 'StatementTimeout') {
                    Write-Message -Level Warning -Message "Additional parameters are passed in, but they will be ignored"
                }
            } elseif ($inputObjectType -in 'SqlConnection' ) {
                if (Test-Bound -ParameterName $ignoredParameters, 'ApplicationIntent', 'StatementTimeout', 'DedicatedAdminConnection') {
                    Write-Message -Level Warning -Message "Additional parameters are passed in, but they will be ignored"
                }
            }

            if ($DedicatedAdminConnection -and $serverName) {
                Write-Message -Level Debug -Message "Parameter DedicatedAdminConnection is used, so serverName will be changed and NonPooledConnection will be set."
                $serverName = 'ADMIN:' + $serverName
                $NonPooledConnection = $true
            }

            # Create smo server object
            if ($inputObjectType -eq 'Server') {
                # Test if we have to copy the connection context
                # Currently only if we have a different Database or have to switch to a NonPooledConnection or using a specific StatementTimeout or using ApplicationIntent
                # We do not test for SqlCredential as this would change the behavior compared to the legacy code path
                $copyContext = $false
                $createNewConnection = $false
                if ($Database) {
                    Write-Message -Level Debug -Message "Database [$Database] provided."
                    if (-not $inputObject.ConnectionContext.CurrentDatabase) {
                        Write-Message -Level Debug -Message "ConnectionContext.CurrentDatabase is empty, so connection will be opened to get the value"
                        $inputObject.ConnectionContext.Connect()
                        Write-Message -Level Debug -Message "ConnectionContext.CurrentDatabase is now [$($inputObject.ConnectionContext.CurrentDatabase)]"
                    }
                    if ($inputObject.ConnectionContext.CurrentDatabase -ne $Database) {
                        Write-Message -Level Verbose -Message "Database [$Database] provided. Does not match ConnectionContext.CurrentDatabase [$($inputObject.ConnectionContext.CurrentDatabase)], copying ConnectionContext and setting the CurrentDatabase"
                        $copyContext = $true
                        if ($inputObject.ConnectionContext.ConnectAsUserName -ne '') {
                            Write-Message -Level Debug -Message "Using ConnectAsUserName [$($inputObject.ConnectionContext.ConnectAsUserName)], so changing database context is not possible without loosing this information. We will create a new connection targeting database [$Database]"
                            $createNewConnection = $true
                        }
                    }
                }
                if ($ApplicationIntent -and $inputObject.ConnectionContext.ApplicationIntent -ne $ApplicationIntent) {
                    Write-Message -Level Verbose -Message "ApplicationIntent provided. Does not match ConnectionContext.ApplicationIntent, copying ConnectionContext and setting the ApplicationIntent"
                    $copyContext = $true
                }
                if ($NonPooledConnection -and -not $inputObject.ConnectionContext.NonPooledConnection) {
                    Write-Message -Level Verbose -Message "NonPooledConnection provided. Does not match ConnectionContext.NonPooledConnection, copying ConnectionContext and setting NonPooledConnection"
                    $copyContext = $true
                }
                if (Test-Bound -Parameter StatementTimeout -and $inputObject.ConnectionContext.StatementTimeout -ne $StatementTimeout) {
                    Write-Message -Level Verbose -Message "StatementTimeout provided. Does not match ConnectionContext.StatementTimeout, copying ConnectionContext and setting the StatementTimeout"
                    $copyContext = $true
                }
                if ($DedicatedAdminConnection -and $inputObject.ConnectionContext.ServerInstance -notmatch '^ADMIN:') {
                    Write-Message -Level Verbose -Message "DedicatedAdminConnection provided. Does not match ConnectionContext.ServerInstance, copying ConnectionContext and setting the ServerInstance"
                    $copyContext = $true
                }
                if ($createNewConnection) {
                    $isNewConnection = $true
                    $secStringPassword = ConvertTo-SecureString -String $inputObject.ConnectionContext.ConnectAsUserPassword -AsPlainText -Force
                    $serverCredentialFromSMO = New-Object System.Management.Automation.PSCredential($inputObject.ConnectionContext.ConnectAsUserName, $secStringPassword)
                    $connectParams = $PSBoundParameters
                    $connectParams.SqlInstance = $inputObject.Name
                    $connectParams.SqlCredential = $serverCredentialFromSMO
                    $server = Connect-DbaInstance @connectParams
                } elseif ($copyContext) {
                    $isNewConnection = $true
                    $connContext = $inputObject.ConnectionContext.Copy()
                    if ($ApplicationIntent) {
                        $connContext.ApplicationIntent = $ApplicationIntent
                    }
                    if ($NonPooledConnection) {
                        $connContext.NonPooledConnection = $true
                    }
                    if (Test-Bound -Parameter StatementTimeout) {
                        $connContext.StatementTimeout = $StatementTimeout
                    }
                    if ($DedicatedAdminConnection -and $inputObject.ConnectionContext.ServerInstance -notmatch '^ADMIN:') {
                        $connContext.ServerInstance = 'ADMIN:' + $connContext.ServerInstance
                        $connContext.NonPooledConnection = $true
                    }
                    if ($Database) {
                        # Save StatementTimeout because it might be reset on GetDatabaseConnection
                        $savedStatementTimeout = $connContext.StatementTimeout
                        $connContext = $connContext.GetDatabaseConnection($Database, $false)
                        $connContext.StatementTimeout = $savedStatementTimeout
                    }
                    $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $connContext
                    if ($Database -and $server.ConnectionContext.CurrentDatabase -ne $Database) {
                        Write-Message -Level Warning -Message "Changing connection context to database $Database was not successful. Current database is $($server.ConnectionContext.CurrentDatabase). Please open an issue on https://github.com/dataplat/dbatools/issues."
                    }
                } else {
                    $server = $inputObject
                }
            } elseif ($inputObjectType -eq 'SqlConnection') {
                $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $inputObject
            } elseif ($inputObjectType -in 'RegisteredServer', 'ConnectionString') {
                # Create the server SMO in the same way as when passing a string (see #8962 for details).
                # Best way to get connection pooling to work is to use SqlConnectionInfo -> ServerConnection -> Server
                $sqlConnectionInfo = New-Object -TypeName Microsoft.SqlServer.Management.Common.SqlConnectionInfo

                # Set properties of SqlConnectionInfo based on the used properties of the connection string.
                $csb = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $connectionString
                if ($csb.ShouldSerialize('Data Source')) {
                    Write-Message -Level Debug -Message "ServerName will be set to '$($csb.DataSource)'"
                    $sqlConnectionInfo.ServerName = $csb.DataSource
                    $null = $csb.Remove('Data Source')
                }
                if ($csb.ShouldSerialize('User ID')) {
                    Write-Message -Level Debug -Message "UserName will be set to '$($csb.UserID)'"
                    $sqlConnectionInfo.UserName = $csb.UserID
                    $null = $csb.Remove('User ID')
                }
                if ($csb.ShouldSerialize('Password')) {
                    Write-Message -Level Debug -Message "Password will be set"
                    $sqlConnectionInfo.Password = $csb.Password
                    $null = $csb.Remove('Password')
                }
                # look for 'Initial Catalog' and 'Database' in the connection string
                $specifiedDatabase = $csb['Database']
                if ($specifiedDatabase -eq '') {
                    $specifiedDatabase = $csb['Initial Catalog']
                }
                if ($Database -and $Database -ne $specifiedDatabase) {
                    Write-Message -Level Debug -Message "Database specified in connection string '$specifiedDatabase' does not match Database parameter '$Database'. Database parameter will be used."
                    # clear both, in order to not be overridden later by setting all AddtionalParameters
                    if ($csb.ShouldSerialize('Database')) {
                        $csb.Remove('Database')
                    }
                    if ($csb.ShouldSerialize('Initial Catalog')) {
                        $csb.Remove('Initial Catalog')
                    }
                    $sqlConnectionInfo.DatabaseName = $Database
                }

                # Add all remaining parts of the connection string as additional parameters.
                $sqlConnectionInfo.AdditionalParameters = $csb.ConnectionString

                # Set properties based on used parameters.
                if ($TrustServerCertificate) {
                    Write-Message -Level Debug -Message "TrustServerCertificate will be set to '$TrustServerCertificate'"
                    $sqlConnectionInfo.TrustServerCertificate = $TrustServerCertificate
                }

                $serverConnection = New-Object -TypeName Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $sqlConnectionInfo
                $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $serverConnection
            } elseif ($inputObjectType -eq 'String') {
                # Identify authentication method
                if ($isAzure) {
                    $authType = 'azure '
                } else {
                    $authType = 'local '
                }
                if ($SqlCredential) {
                    $username = ($SqlCredential.UserName).TrimStart("\")
                    # support both ad\username and username@ad
                    # username@ad works only for domain joined and workgroup
                    # nobody remembers why, but username@ad is preferred
                    # so we switch ad\username to username@ad only doing a raw guess
                    # when USERDOMAIN -ne COMPUTERNAME, we're probably joined to ad
                    if ($env:USERDOMAIN -ne $env:COMPUTERNAME) {
                        if ($username -like "*\*") {
                            $domain, $login = $username.Split("\")
                            $username = "$login@$domain"
                        }
                    }
                    if ($username -like '*@*' -or $username -like '*\*') {
                        $authType += 'ad'
                    } else {
                        $authType += 'sql'
                    }
                } elseif ($AccessToken) {
                    $authType += 'token'
                } else {
                    $authType += 'integrated'
                }
                Write-Message -Level Verbose -Message "authentication method is '$authType'"

                # Best way to get connection pooling to work is to use SqlConnectionInfo -> ServerConnection -> Server
                $sqlConnectionInfo = New-Object -TypeName Microsoft.SqlServer.Management.Common.SqlConnectionInfo -ArgumentList $serverName

                # But if we have an AccessToken, we need ConnectionString -> SqlConnection -> ServerConnection -> Server
                # We will get the ConnectionString from the SqlConnectionInfo, so let's move on

                # I will list all properties of SqlConnectionInfo and set them if value is provided

                #AccessToken            Property   Microsoft.SqlServer.Management.Common.IRenewableToken AccessToken {get;set;}
                # This parameter needs an IRenewableToken and we currently support only a non renewable token

                #AdditionalParameters   Property   string AdditionalParameters {get;set;}
                if ($AppendConnectionString) {
                    Write-Message -Level Debug -Message "AdditionalParameters will be appended by '$AppendConnectionString;'"
                    $sqlConnectionInfo.AdditionalParameters += "$AppendConnectionString;"
                }
                if ($FailoverPartner) {
                    Write-Message -Level Debug -Message "AdditionalParameters will be appended by 'FailoverPartner=$FailoverPartner;'"
                    $sqlConnectionInfo.AdditionalParameters += "FailoverPartner=$FailoverPartner;"
                }
                if ($MultiSubnetFailover) {
                    Write-Message -Level Debug -Message "AdditionalParameters will be appended by 'MultiSubnetFailover=True;'"
                    $sqlConnectionInfo.AdditionalParameters += 'MultiSubnetFailover=True;'
                }
                if ($AlwaysEncrypted) {
                    Write-Message -Level Debug -Message "AdditionalParameters will be appended by 'Column Encryption Setting=enabled;'"
                    $sqlConnectionInfo.AdditionalParameters += 'Column Encryption Setting=enabled;'
                }

                #ApplicationIntent      Property   string ApplicationIntent {get;set;}
                if ($ApplicationIntent) {
                    Write-Message -Level Debug -Message "ApplicationIntent will be set to '$ApplicationIntent'"
                    $sqlConnectionInfo.ApplicationIntent = $ApplicationIntent
                }

                #ApplicationName        Property   string ApplicationName {get;set;}
                if ($ClientName) {
                    Write-Message -Level Debug -Message "ApplicationName will be set to '$ClientName'"
                    $sqlConnectionInfo.ApplicationName = $ClientName
                }

                #Authentication         Property   Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod Authentication {get;set;}
                #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryIntegrated
                #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryInteractive
                #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryPassword
                #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::NotSpecified
                #[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::SqlPassword
                if ($authType -eq 'azure integrated') {
                    # Azure AD integrated security
                    # TODO: This is not tested / How can we test that?
                    Write-Message -Level Debug -Message "Authentication will be set to 'ActiveDirectoryIntegrated'"
                    $sqlConnectionInfo.Authentication = [Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryIntegrated
                } elseif ($authType -eq 'azure ad') {
                    # Azure AD account with password
                    Write-Message -Level Debug -Message "Authentication will be set to 'ActiveDirectoryPassword'"
                    $sqlConnectionInfo.Authentication = [Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryPassword
                }

                #ConnectionProtocol     Property   Microsoft.SqlServer.Management.Common.NetworkProtocol ConnectionProtocol {get;set;}
                if ($NetworkProtocol) {
                    Write-Message -Level Debug -Message "ConnectionProtocol will be set to '$NetworkProtocol'"
                    $sqlConnectionInfo.ConnectionProtocol = $NetworkProtocol
                }

                #ConnectionString       Property   string ConnectionString {get;}
                # Only a getter, not a setter - so don't touch

                #ConnectionTimeout      Property   int ConnectionTimeout {get;set;}
                if ($ConnectTimeout) {
                    Write-Message -Level Debug -Message "ConnectionTimeout will be set to '$ConnectTimeout'"
                    $sqlConnectionInfo.ConnectionTimeout = $ConnectTimeout
                }

                #DatabaseName           Property   string DatabaseName {get;set;}
                if ($Database) {
                    Write-Message -Level Debug -Message "Database will be set to '$Database'"
                    $sqlConnectionInfo.DatabaseName = $Database
                }

                if ($instance -notmatch "localdb") {
                    #EncryptConnection      Property   bool EncryptConnection {get;set;}
                    Write-Message -Level Debug -Message "EncryptConnection will be set to '$EncryptConnection'"
                    $sqlConnectionInfo.EncryptConnection = $EncryptConnection
                } else {
                    Write-Message -Level Verbose -Message "localdb detected, skipping unsupported keyword 'Encryption'"
                }

                #MaxPoolSize            Property   int MaxPoolSize {get;set;}
                if ($MaxPoolSize) {
                    Write-Message -Level Debug -Message "MaxPoolSize will be set to '$MaxPoolSize'"
                    $sqlConnectionInfo.MaxPoolSize = $MaxPoolSize
                }

                #MinPoolSize            Property   int MinPoolSize {get;set;}
                if ($MinPoolSize) {
                    Write-Message -Level Debug -Message "MinPoolSize will be set to '$MinPoolSize'"
                    $sqlConnectionInfo.MinPoolSize = $MinPoolSize
                }

                #PacketSize             Property   int PacketSize {get;set;}
                if ($PacketSize) {
                    Write-Message -Level Debug -Message "PacketSize will be set to '$PacketSize'"
                    $sqlConnectionInfo.PacketSize = $PacketSize
                }

                #Password               Property   string Password {get;set;}
                # We will use SecurePassword

                #PoolConnectionLifeTime Property   int PoolConnectionLifeTime {get;set;}
                if ($PooledConnectionLifetime) {
                    Write-Message -Level Debug -Message "PoolConnectionLifeTime will be set to '$PooledConnectionLifetime'"
                    $sqlConnectionInfo.PoolConnectionLifeTime = $PooledConnectionLifetime
                }

                #Pooled                 Property   System.Data.SqlTypes.SqlBoolean Pooled {get;set;}
                # TODO: Do we need or want the else path or is it the default and we better don't touch it?
                if ($NonPooledConnection) {
                    Write-Message -Level Debug -Message "Pooled will be set to '$false'"
                    $sqlConnectionInfo.Pooled = $false
                } else {
                    Write-Message -Level Debug -Message "Pooled will be set to '$true'"
                    $sqlConnectionInfo.Pooled = $true
                }

                #QueryTimeout           Property   int QueryTimeout {get;set;}
                # We use ConnectionContext.StatementTimeout instead

                #SecurePassword         Property   securestring SecurePassword {get;set;}
                if ($authType -in 'azure ad', 'azure sql', 'local sql') {
                    Write-Message -Level Debug -Message "SecurePassword will be set"
                    $sqlConnectionInfo.SecurePassword = $SqlCredential.Password
                }

                #ServerCaseSensitivity  Property   Microsoft.SqlServer.Management.Common.ServerCaseSensitivity ServerCaseSensitivity {get;set;}

                #ServerName             Property   string ServerName {get;set;}
                # Was already set by the constructor.

                #ServerType             Property   Microsoft.SqlServer.Management.Common.ConnectionType ServerType {get;}
                # Only a getter, not a setter - so don't touch

                #ServerVersion          Property   Microsoft.SqlServer.Management.Common.ServerVersion ServerVersion {get;set;}
                # We can set that? No, we don't want to...

                #TrustServerCertificate Property   bool TrustServerCertificate {get;set;}
                Write-Message -Level Debug -Message "TrustServerCertificate will be set to '$TrustServerCertificate'"
                $sqlConnectionInfo.TrustServerCertificate = $TrustServerCertificate

                #UseIntegratedSecurity  Property   bool UseIntegratedSecurity {get;set;}
                # $true is the default and it is automatically set to $false if we set a UserName, so we don't touch

                #UserName               Property   string UserName {get;set;}
                if ($authType -in 'azure ad', 'azure sql', 'local sql') {
                    Write-Message -Level Debug -Message "UserName will be set to '$username'"
                    $sqlConnectionInfo.UserName = $username
                }

                #WorkstationId          Property   string WorkstationId {get;set;}
                if ($WorkstationId) {
                    Write-Message -Level Debug -Message "WorkstationId will be set to '$WorkstationId'"
                    $sqlConnectionInfo.WorkstationId = $WorkstationId
                }

                # If we have an AccessToken, we will build a SqlConnection
                if ($AccessToken) {
                    # Check if token was created by New-DbaAzAccessToken or Get-AzAccessToken
                    Write-Message -Level Debug -Message "AccessToken detected, checking for string, SecureString, or PsObjectIRenewableToken"
                    if ($AccessToken | Get-Member | Where-Object Name -eq GetAccessToken) {
                        Write-Message -Level Debug -Message "Token was generated using New-DbaAzAccessToken, executing GetAccessToken()"
                        $AccessToken = $AccessToken.GetAccessToken()
                    }
                    if ($AccessToken | Get-Member | Where-Object Name -eq Token) {
                        Write-Message -Level Debug -Message "Token was generated using Get-AzAccessToken, getting .Token"
                        $tokenValue = $AccessToken.Token
                        # Check if the Token property is a SecureString (Azure PowerShell v14+)
                        if ($tokenValue -is [System.Security.SecureString]) {
                            Write-Message -Level Debug -Message "Token is SecureString (Azure PowerShell v14+), converting to plain text"
                            try {
                                $AccessToken = ConvertFrom-SecurePass -InputObject $tokenValue
                                Write-Message -Level Debug -Message "Successfully converted SecureString token to plain text"
                            } catch {
                                Stop-Function -Target $instance -Message "Failed to convert SecureString AccessToken to plain text: $($_.Exception.Message)" -Continue
                            }
                        } else {
                            Write-Message -Level Debug -Message "Token is plain text string (Azure PowerShell v13 and earlier)"
                            $AccessToken = $tokenValue
                        }
                    } elseif ($AccessToken -is [System.Security.SecureString]) {
                        # Handle direct SecureString AccessToken input
                        Write-Message -Level Debug -Message "AccessToken is directly provided as SecureString, converting to plain text"
                        try {
                            $AccessToken = ConvertFrom-SecurePass -InputObject $AccessToken
                            Write-Message -Level Debug -Message "Successfully converted direct SecureString AccessToken to plain text"
                        } catch {
                            Stop-Function -Target $instance -Message "Failed to convert SecureString AccessToken to plain text: $($_.Exception.Message)" -Continue
                        }
                    }
                    Write-Message -Level Debug -Message "We have an AccessToken and build a SqlConnection with that token"
                    Write-Message -Level Debug -Message "But we remove 'Integrated Security=True;'"
                    # TODO: How do we get a ConnectionString without this?
                    Write-Message -Level Debug -Message "Building SqlConnection from SqlConnectionInfo.ConnectionString"
                    $connectionString = $sqlConnectionInfo.ConnectionString -replace 'Integrated Security=True;', ''
                    $sqlConnection = New-Object -TypeName Microsoft.Data.SqlClient.SqlConnection -ArgumentList $connectionString
                    Write-Message -Level Debug -Message "SqlConnection was built"
                    $sqlConnection.AccessToken = $AccessToken
                    Write-Message -Level Debug -Message "Building ServerConnection from SqlConnection"
                    $serverConnection = New-Object -TypeName Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $sqlConnection
                    Write-Message -Level Debug -Message "ServerConnection was built"
                } else {
                    Write-Message -Level Debug -Message "Building ServerConnection from SqlConnectionInfo"
                    $serverConnection = New-Object -TypeName Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $sqlConnectionInfo
                    Write-Message -Level Debug -Message "ServerConnection was built"
                }

                if ($authType -eq 'local ad') {
                    if ($IsLinux -or $IsMacOS) {
                        Stop-Function -Target $instance -Message "Cannot use Windows credentials to connect when host is Linux or OS X. Use kinit instead. See https://github.com/dataplat/dbatools/issues/7602 for more info."
                        return
                    }
                    Write-Message -Level Debug -Message "ConnectAsUser will be set to '$true'"
                    $serverConnection.ConnectAsUser = $true

                    Write-Message -Level Debug -Message "ConnectAsUserName will be set to '$username'"
                    $serverConnection.ConnectAsUserName = $username

                    Write-Message -Level Debug -Message "ConnectAsUserPassword will be set"
                    $serverConnection.ConnectAsUserPassword = $SqlCredential.GetNetworkCredential().Password
                }

                Write-Message -Level Debug -Message "Building Server from ServerConnection"
                $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $serverConnection
                Write-Message -Level Debug -Message "Server was built"

                # Set properties of ConnectionContext that are not part of SqlConnectionInfo
                if (Test-Bound -ParameterName 'BatchSeparator') {
                    Write-Message -Level Debug -Message "Setting ConnectionContext.BatchSeparator to '$BatchSeparator'"
                    $server.ConnectionContext.BatchSeparator = $BatchSeparator
                }
                if (Test-Bound -ParameterName 'LockTimeout') {
                    Write-Message -Level Debug -Message "Setting ConnectionContext.LockTimeout to '$LockTimeout'"
                    $server.ConnectionContext.LockTimeout = $LockTimeout
                }
                if ($MultipleActiveResultSets) {
                    Write-Message -Level Debug -Message "Setting ConnectionContext.MultipleActiveResultSets to 'True'"
                    $server.ConnectionContext.MultipleActiveResultSets = $true
                }
                if (Test-Bound -ParameterName 'SqlExecutionModes') {
                    Write-Message -Level Debug -Message "Setting ConnectionContext.SqlExecutionModes to '$SqlExecutionModes'"
                    $server.ConnectionContext.SqlExecutionModes = $SqlExecutionModes
                }
                Write-Message -Level Debug -Message "Setting ConnectionContext.StatementTimeout to '$StatementTimeout'"
                $server.ConnectionContext.StatementTimeout = $StatementTimeout
            }

            $maskedConnString = Hide-ConnectionString $server.ConnectionContext.ConnectionString
            Write-Message -Level Debug -Message "The masked server.ConnectionContext.ConnectionString is $maskedConnString"

            # It doesn't matter which input we have, we pass this line and have a server SMO in $server to work with
            # It might be a brand new one or an already used one.
            # "Pooled connections are always closed directly after an operation" (so .IsOpen does not tell us anything):
            # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.common.connectionmanager.isopen?view=sql-smo-160#Microsoft_SqlServer_Management_Common_ConnectionManager_IsOpen
            # We could use .ConnectionContext.SqlConnectionObject.Open(), but we would have to check ConnectionContext.IsOpen first because it is not allowed on open connections
            # But ConnectionContext.IsOpen does not tell the truth if the instance was just shut down
            # And we don't use $server.ConnectionContext.Connect() as this would create a non pooled connection
            # Instead we run a real T-SQL command and just SELECT something to be sure we have a valid connection and let the SMO handle the connection
            $connectionSucceeded = $false
            $connectionError = $null
            try {
                Write-Message -Level Debug -Message "We connect to the instance by running SELECT 'dbatools is opening a new connection'"
                $null = $server.ConnectionContext.ExecuteWithResults("SELECT 'dbatools is opening a new connection'")
                Write-Message -Level Debug -Message "We have a connected server object"
                $connectionSucceeded = $true
            } catch {
                $connectionError = $_
                $errorMessage = $_.Exception.Message

                # Check if AllowTrustServerCertificate is enabled and this is a new connection attempt and not already using TrustServerCertificate
                # Also verify this is a certificate validation error
                $isCertError = $errorMessage -match "certificate" -or $errorMessage -match "SSL" -or $errorMessage -match "TLS" -or $errorMessage -match "trust"
                if ($AllowTrustServerCertificate -and $isNewConnection -and -not $TrustServerCertificate -and $isCertError -and $inputObjectType -eq 'String') {
                    Write-Message -Level Verbose -Message "Initial connection failed due to certificate validation. Retrying with TrustServerCertificate enabled."
                    Write-Message -Level Debug -Message "Original error: $errorMessage"

                    # Recreate the connection with TrustServerCertificate enabled
                    try {
                        # Update the SqlConnectionInfo to trust the server certificate
                        $server.ConnectionContext.SqlConnectionObject.ConnectionString = $server.ConnectionContext.SqlConnectionObject.ConnectionString -replace "Trust Server Certificate=False", "Trust Server Certificate=True"
                        if ($server.ConnectionContext.SqlConnectionObject.ConnectionString -notmatch "Trust Server Certificate") {
                            if ($server.ConnectionContext.SqlConnectionObject.ConnectionString -match ";$") {
                                $server.ConnectionContext.SqlConnectionObject.ConnectionString += "Trust Server Certificate=True;"
                            } else {
                                $server.ConnectionContext.SqlConnectionObject.ConnectionString += ";Trust Server Certificate=True;"
                            }
                        }

                        # Retry the connection
                        Write-Message -Level Debug -Message "Retrying connection with TrustServerCertificate enabled"
                        $null = $server.ConnectionContext.ExecuteWithResults("SELECT 'dbatools is opening a new connection with TrustServerCertificate'")
                        Write-Message -Level Verbose -Message "Connection succeeded with TrustServerCertificate enabled"
                        $connectionSucceeded = $true
                    } catch {
                        Write-Message -Level Debug -Message "Retry with TrustServerCertificate also failed: $($_.Exception.Message)"
                        # Use the original error for reporting since the retry also failed
                        $connectionError = $_
                    }
                }

                if (-not $connectionSucceeded) {
                    Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
                }
            }

            if ($AzureUnsupported -and $server.DatabaseEngineType -eq "SqlAzureDatabase") {
                if ($isNewConnection) {
                    $server.ConnectionContext.Disconnect()
                }
                Stop-Function -Target $instance -Message "Azure SQL Database not supported" -Continue
            }

            if ($MinimumVersion -and $server.VersionMajor) {
                if ($server.VersionMajor -lt $MinimumVersion) {
                    if ($isNewConnection) {
                        $server.ConnectionContext.Disconnect()
                    }
                    Stop-Function -Target $instance -Message "SQL Server version $MinimumVersion required - $server not supported." -Continue
                }
            }

            if ($SqlConnectionOnly) {
                $null = Add-ConnectionHashValue -Key $server.ConnectionContext.ConnectionString -Value $server.ConnectionContext.SqlConnectionObject
                Write-Message -Level Debug -Message "We return only SqlConnection in server.ConnectionContext.SqlConnectionObject"
                $server.ConnectionContext.SqlConnectionObject
                continue
            }

            if (-not $server.ComputerName) {
                # To set the source of ComputerName to something else than the default use this config parameter:
                # Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'server.ComputerNamePhysicalNetBIOS'
                # Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'instance.ComputerName'
                # If the config parameter is not used, then there a different ways to handle the new property ComputerName
                # Rules in legacy code: Use $server.NetName, but if $server.NetName is empty or we are on Azure or Linux, use $instance.ComputerName
                $computerName = $null
                $computerNameSource = Get-DbatoolsConfigValue -FullName commands.connect-dbainstance.smo.computername.source
                if ($computerNameSource) {
                    Write-Message -Level Debug -Message "Setting ComputerName based on $computerNameSource"
                    $object, $property = $computerNameSource -split '\.'
                    $value = (Get-Variable -Name $object).Value.$property
                    if ($value) {
                        $computerName = $value
                        Write-Message -Level Debug -Message "ComputerName will be set to $computerName"
                    } else {
                        Write-Message -Level Debug -Message "No value found for ComputerName, so will use the default"
                    }
                }
                if (-not $computerName) {
                    if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                        Write-Message -Level Debug -Message "We are on Azure, so server.ComputerName will be set to instance.ComputerName"
                        $computerName = $instance.ComputerName
                    } elseif ($server.HostPlatform -eq 'Linux') {
                        Write-Message -Level Debug -Message "We are on Linux what is often on docker and the internal name is not useful, so server.ComputerName will be set to instance.ComputerName"
                        $computerName = $instance.ComputerName
                    } elseif ($server.NetName) {
                        Write-Message -Level Debug -Message "We will set server.ComputerName to server.NetName"
                        $computerName = $server.NetName
                    } else {
                        Write-Message -Level Debug -Message "We will set server.ComputerName to instance.ComputerName as server.NetName is empty"
                        $computerName = $instance.ComputerName
                    }
                    Write-Message -Level Debug -Message "ComputerName will be set to $computerName"
                }
                Add-Member -InputObject $server -NotePropertyName ComputerName -NotePropertyValue $computerName -Force
            }

            if (-not $server.IsAzure) {
                Add-Member -InputObject $server -NotePropertyName IsAzure -NotePropertyValue $isAzure -Force
                Add-Member -InputObject $server -NotePropertyName DbaInstanceName -NotePropertyValue $instance.InstanceName -Force
                Add-Member -InputObject $server -NotePropertyName SqlInstance -NotePropertyValue $server.DomainInstanceName -Force
                Add-Member -InputObject $server -NotePropertyName NetPort -NotePropertyValue $instance.Port -Force
                Add-Member -InputObject $server -NotePropertyName ConnectedAs -NotePropertyValue $server.ConnectionContext.TrueLogin -Force
                Write-Message -Level Debug -Message "We added IsAzure = '$($server.IsAzure)', DbaInstanceName = instance.InstanceName = '$($server.DbaInstanceName)', SqlInstance = server.DomainInstanceName = '$($server.SqlInstance)', NetPort = instance.Port = '$($server.NetPort)', ConnectedAs = server.ConnectionContext.TrueLogin = '$($server.ConnectedAs)'"
            }

            Write-Message -Level Debug -Message "We return the server object"
            $server

            if ($isNewConnection -and -not $DedicatedAdminConnection) {
                # Register the connected instance, so that the TEPP updater knows it's been connected to and starts building the cache
                [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::SetInstance($instance.FullSmoName.ToLowerInvariant(), $server.ConnectionContext.Copy(), ($server.ConnectionContext.FixedServerRoles -match "SysAdmin"))

                # Update cache for instance names
                if ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $instance.FullSmoName.ToLowerInvariant()) {
                    [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $instance.FullSmoName.ToLowerInvariant()
                }

                # Update lots of registered stuff
                # Default for [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled is $true, so will not run by default
                # Must be explicitly activated with [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled = $false to run
                if (-not [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled) {
                    # Variable $FullSmoName is used inside the script blocks, so we have to set
                    $FullSmoName = $instance.FullSmoName.ToLowerInvariant()
                    Write-Message -Level Debug -Message "Will run Invoke-TEPPCacheUpdate for FullSmoName = $FullSmoName"
                    foreach ($scriptBlock in ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsFast)) {
                        Invoke-TEPPCacheUpdate -ScriptBlock $scriptBlock
                    }
                }

                # By default, SMO initializes several properties. We push it to the limit and gather a bit more
                # this slows down the connect a smidge but drastically improves overall performance
                # especially when dealing with a multitude of servers
                if ($loadedSmoVersion -ge 11 -and -not $isAzure) {
                    try {
                        Write-Message -Level Debug -Message "SetDefaultInitFields will be used"
                        $initFieldsDb = New-Object System.Collections.Specialized.StringCollection
                        $initFieldsLogin = New-Object System.Collections.Specialized.StringCollection
                        $initFieldsJob = New-Object System.Collections.Specialized.StringCollection
                        if ($server.VersionMajor -eq 8) {
                            # 2000
                            [void]$initFieldsDb.AddRange($Fields2000_Db)
                            [void]$initFieldsLogin.AddRange($Fields2000_Login)
                        } elseif ($server.VersionMajor -eq 9 -or $server.VersionMajor -eq 10) {
                            # 2005 and 2008
                            [void]$initFieldsDb.AddRange($Fields200x_Db)
                            [void]$initFieldsLogin.AddRange($Fields200x_Login)
                        } elseif ($server.VersionMajor -ge 16) {
                            # 2022 and above - exclude ActiveConnections due to performance issue #9282
                            $fields = New-Object System.Collections.Specialized.StringCollection
                            foreach ($field in $Fields201x_Db) {
                                if ($field -ne "ActiveConnections") {
                                    [void]$fields.Add($field)
                                }
                            }
                            [void]$initFieldsDb.AddRange($fields)
                            [void]$initFieldsLogin.AddRange($Fields201x_Login)
                        } else {
                            # 2012 to 2019
                            [void]$initFieldsDb.AddRange($Fields201x_Db)
                            [void]$initFieldsLogin.AddRange($Fields201x_Login)
                        }
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], $initFieldsDb)
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], $initFieldsLogin)
                        #see 7753
                        [void]$initFieldsJob.AddRange($Fields_Job)
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Agent.Job], $initFieldsJob)
                    } catch {
                        Write-Message -Level Debug -Message "SetDefaultInitFields failed with $_"
                        # perhaps a DLL issue, continue going
                    }
                }
            }

            $null = Add-ConnectionHashValue -Key $server.ConnectionContext.ConnectionString -Value $server
            Write-Message -Level Debug -Message "We are finished with this instance"
        }
    }
}