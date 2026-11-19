#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a persistent SQL Server Management Object (SMO) connection for database operations.
/// </summary>
/// <para>
/// This command creates a reusable SQL Server Management Object (SMO) that serves as the foundation for most dbatools operations. Think of it as your entry point for connecting to SQL Server instances, whether on-premises, in Azure, or anywhere else.
/// </para>
/// <para>
/// The returned SMO server object handles authentication automatically, detecting whether to use Windows integrated security, SQL authentication, or Azure Active Directory based on your credentials. It supports connection pooling by default for better performance and can handle complex scenarios like failover partners, dedicated admin connections, and multi-subnet environments.
/// </para>
/// <para>
/// This is the connection object you'll pass to other dbatools commands like Get-DbaDatabase, Invoke-DbaQuery, or Backup-DbaDatabase. Rather than each command establishing its own connection, you create one persistent connection here and reuse it, which is both faster and more reliable.
/// </para>
/// <para>
/// The connection includes helpful properties for scripting like ComputerName, IsAzure, and ConnectedAs, plus it automatically sets an identifiable ApplicationName in your connection string so you can track dbatools sessions in profiler or extended events.
/// </para>
/// <para>
/// For Azure connections, it handles the various authentication methods including service principals, managed identities, and access tokens. For on-premises instances, it supports Windows authentication (including alternative credentials), SQL logins, and dedicated administrator connections for emergency access.
/// </para>
/// <para>
/// Reference documentation:
/// https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.connectionstring.aspx
/// https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnectionstringbuilder.aspx
/// https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.aspx
/// </para>
/// <para>
/// To execute SQL commands directly: $server.ConnectionContext.ExecuteReader($sql) or $server.ConnectionContext.ExecuteNonQuery($sql)
/// </para>
/// <para>
/// For statements that do not depend on a particular database, use the connection context rather than a database object. A database object executes on the same connection and leaves it in that database, which changes the database of every later command that reuses the connection. A statement that does need a database still has to say so, because the connection context runs it in whatever database the session currently happens to be in.
/// </para>
/// <para>
/// SQL Server 2008 or later is required. Since 2.8.3, dbatools uses SMO 181, which no longer supports SQL Server 2005 and earlier, so a connection to such an instance is refused with an error that names the last release supporting it: dbatools 2.8.2 with dbatools.library 2025.12.28 (for SQL Server 2000, run from Windows PowerShell 5.1).
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Connect-DbaInstance -SqlInstance sql2014
/// </code>
/// <para>
/// Creates an SMO Server object that connects using Windows Authentication
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $wincred = Get-Credential ad\sqladmin
/// PS C:\&gt; Connect-DbaInstance -SqlInstance sql2014 -SqlCredential $wincred
/// </code>
/// <para>
/// Creates an SMO Server object that connects using alternative Windows credentials
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $sqlcred = Get-Credential sqladmin
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance sql2014 -SqlCredential $sqlcred
/// </code>
/// <para>
/// Login to sql2014 as SQL login sqladmin.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance sql2014 -ClientName "my connection"
/// </code>
/// <para>
/// Creates an SMO Server object that connects using Windows Authentication and uses the client name "my connection".
/// So when you open up profiler or use extended events, you can search for "my connection".
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance sql2014 -AppendConnectionString "Packet Size=4096;AttachDbFilename=C:\MyFolder\MyDataFile.mdf;User Instance=true;"
/// </code>
/// <para>
/// Creates an SMO Server object that connects to sql2014 using Windows Authentication, then it sets the packet size (this can also be done via -PacketSize) and other connection attributes.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance sql2014 -NetworkProtocol TcpIp -MultiSubnetFailover
/// </code>
/// <para>
/// Creates an SMO Server object that connects using Windows Authentication that uses TCP/IP and has MultiSubnetFailover enabled.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $splatConnection = @{
///     SqlInstance          = "myserver.database.windows.net"
///     Database             = "MyDb"
///     ConnectRetryCount    = 5
///     ConnectRetryInterval = 10
///     ConnectTimeout       = 120
/// }
/// PS C:\&gt; $server = Connect-DbaInstance @splatConnection
/// PS C:\&gt; Invoke-DbaQuery -SqlInstance $server -Query "SELECT 1"
/// </code>
/// <para>
/// Connects with connection resiliency settings suitable for an Azure SQL Database that might be resuming from auto-pause, then reuses that connection for a query.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $server = Connect-DbaInstance sql2016 -ApplicationIntent ReadOnly
/// </code>
/// <para>
/// Connects with ReadOnly ApplicationIntent.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance myserver.database.windows.net -Database mydb -SqlCredential me@mydomain.onmicrosoft.com -DisableException
/// PS C:\&gt; Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"
/// </code>
/// <para>
/// Logs into Azure SQL DB using AAD / Azure Active Directory, then performs a sample query.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Database dbatools -DisableException
/// PS C:\&gt; Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"
/// </code>
/// <para>
/// Logs into Azure SQL DB using AAD Integrated Auth, then performs a sample query.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance "myserver.public.cust123.database.windows.net,3342" -Database mydb -SqlCredential me@mydomain.onmicrosoft.com -DisableException
/// PS C:\&gt; Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"
/// </code>
/// <para>
/// Logs into Azure SQL Managed instance using AAD / Azure Active Directory, then performs a sample query.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance db.mycustomazure.com -Database mydb -AzureDomain mycustomazure.com -DisableException
/// PS C:\&gt; Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"
/// </code>
/// <para>
/// In the event your AzureSqlDb is not on a database.windows.net domain, you can set a custom domain using the AzureDomain parameter.
/// This tells Connect-DbaInstance to login to the database using the method that works best with Azure.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $connstring = "Data Source=TCP:mydb.database.windows.net,1433;User ID=sqladmin;Password=adfasdf;Connect Timeout=30;"
/// PS C:\&gt; $server = Connect-DbaInstance -ConnectionString $connstring
/// PS C:\&gt; Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"
/// </code>
/// <para>
/// Logs into Azure using a preconstructed connstring, then performs a sample query.
/// ConnectionString is an alias of SqlInstance, so you can use -SqlInstance $connstring as well.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential guid-app-id-here # appid for username, clientsecret for password
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -Database abc -SqlCredential $cred -Tenant guidheremaybename
/// PS C:\&gt; Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"
/// </code>
/// <para>
/// When connecting from a non-Azure workstation, logs into Azure using Universal with MFA Support with a username and password, then performs a sample query.
/// </para>
/// <para>
/// Note that generating access tokens is not supported on Core, so when using Tenant on Core, we rewrite the connection string with Active Directory Service Principal authentication instead.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential guid-app-id-here # appid for username, clientsecret for password
/// PS C:\&gt; Set-DbatoolsConfig -FullName azure.tenantid -Value 'guidheremaybename' -Passthru | Register-DbatoolsConfig
/// PS C:\&gt; Set-DbatoolsConfig -FullName azure.appid -Value $cred.Username -Passthru | Register-DbatoolsConfig
/// PS C:\&gt; Set-DbatoolsConfig -FullName azure.clientsecret -Value $cred.Password -Passthru | Register-DbatoolsConfig # requires securestring
/// PS C:\&gt; Set-DbatoolsConfig -FullName sql.connection.database -Value abc -Passthru | Register-DbatoolsConfig
/// PS C:\&gt; Connect-DbaInstance -SqlInstance psdbatools.database.windows.net
/// </code>
/// <para>
/// Permanently sets some app id config values. To set them temporarily (just for a session), remove -Passthru | Register-DbatoolsConfig
/// When connecting from a non-Azure workstation or an Azure VM without .NET 4.7.2 and higher, logs into Azure using Universal with MFA Support, then performs a sample query.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $azureCredential = Get-Credential -Message 'Azure Credential'
/// PS C:\&gt; $azureAccount = Connect-AzAccount -Credential $azureCredential
/// PS C:\&gt; $azureToken = Get-AzAccessToken -ResourceUrl https://database.windows.net
/// PS C:\&gt; $azureInstance = "YOURSERVER.database.windows.net"
/// PS C:\&gt; $azureDatabase = "MYDATABASE"
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance $azureInstance -Database $azureDatabase -AccessToken $azureToken
/// PS C:\&gt; Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"
/// </code>
/// <para>
/// Connect to an Azure SQL Database or an Azure SQL Managed Instance with an AccessToken.
/// Works with both Azure PowerShell v13 (string tokens) and v14+ (SecureString tokens).
/// Note that the token is valid for only one hour and cannot be renewed automatically.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; # Azure PowerShell v14+ with SecureString token support
/// PS C:\&gt; Connect-AzAccount
/// PS C:\&gt; $azureToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token
/// PS C:\&gt; $azureInstance = "YOUR-AZURE-SQL-MANAGED-INSTANCE.database.windows.net"
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance $azureInstance -Database "YOURDATABASE" -AccessToken $azureToken
/// PS C:\&gt; Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"
/// </code>
/// <para>
/// Connect to an Azure SQL Managed Instance using Azure PowerShell v14+ where Get-AzAccessToken returns a SecureString.
/// The function automatically detects and converts the SecureString token to the required format.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $token = New-DbaAzAccessToken -Type RenewableServicePrincipal -Subtype AzureSqlDb -Tenant $tenantid -Credential $cred
/// PS C:\&gt; Connect-DbaInstance -SqlInstance sample.database.windows.net -Accesstoken $token
/// </code>
/// <para>
/// Uses dbatools to generate the access token for an Azure SQL Database, then logs in using that AccessToken.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance srv1 -DedicatedAdminConnection
/// PS C:\&gt; $dbaProcess = Get-DbaProcess -SqlInstance $server -ExcludeSystemSpids
/// PS C:\&gt; $killedProcess = $dbaProcess | Out-GridView -OutputMode Multiple | Stop-DbaProcess
/// PS C:\&gt; $server | Disconnect-DbaInstance
/// </code>
/// <para>
/// Creates a dedicated admin connection (DAC) to the default instance on server srv1.
/// Receives all non-system processes from the instance using the DAC.
/// Opens a grid view to let the user select processes to be stopped.
/// Closes the connection.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $servers = "sql1", "sql2", "sql3"
/// PS C:\&gt; $servers | Connect-DbaInstance -AllowTrustServerCertificate
/// </code>
/// <para>
/// Connects to multiple servers where some may have valid TLS certificates and others may not.
/// For each server, attempts connection with proper TLS validation first.
/// If a server fails due to certificate validation, automatically retries with TrustServerCertificate enabled.
/// This provides a secure-by-default approach for mixed environments without requiring separate connection logic.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance sql01 -AuthenticationType ActiveDirectoryInteractive
/// </code>
/// <para>
/// Connects to a SQL Server instance (Azure SQL VM, Azure SQL Database, Azure SQL Managed Instance, or Fabric SQL Database)
/// using Entra ID (Azure AD) interactive authentication with MFA. A browser dialog will appear prompting you to select
/// your Entra ID account and complete any required MFA steps.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance myserver.database.windows.net -Database mydb -AuthenticationType ActiveDirectoryInteractive
/// </code>
/// <para>
/// Connects to an Azure SQL Database using Entra ID interactive authentication with MFA.
/// A browser dialog will appear to complete authentication.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $server = Connect-DbaInstance -SqlInstance sql01 -AuthenticationType ActiveDirectoryIntegrated
/// </code>
/// <para>
/// Connects to a SQL Server instance using Entra ID integrated authentication.
/// Uses the currently signed-in Entra ID identity without prompting for credentials.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Connection
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Connect-DbaInstance" />
/// <remarks>
/// Port of public/Connect-DbaInstance.ps1 at the pin, written new from the pinned function. This class holds the
/// pinned surface; ConnectDbaInstanceCommand.Processing.cs holds the begin and process blocks. Input analysis,
/// the connection build, the connect retries and the version checks run in ConnectionService, which every native
/// command shares. The description's last paragraph and the last sentence of MinimumVersion are dbatools PR 10813's,
/// word for word (harness-edits.md, "SQL Server 2005 refusal ported from PR 10813 (operator, 2026-10-29)").
/// </remarks>
[Cmdlet(VerbsCommunications.Connect, "DbaInstance")]
[OutputType(typeof(Server), typeof(Microsoft.Data.SqlClient.SqlConnection))]
public sealed partial class ConnectDbaInstanceCommand : DbaInstanceCmdlet
{
    // The pinned function declares no EnableException: -DisableException decides it in the begin block. The native
    // build has always accepted it (inherited from DbaBaseCmdlet, honored when bound) and the fleet's native tests of
    // other commands pass it, so it stays under the lifted contract (harness-edits.md, "Connect-DbaInstance: contract
    // lifted (operator, 2026-11-11)"); the pinned parameter-list test goes to the operator. The override only gives the
    // parameter this command's help; StopFunction reads it through virtual dispatch.
    /// <summary>
    /// This command already throws terminating exceptions by default. Use -EnableException:$false to get friendly
    /// warnings instead, as -DisableException does. When -DisableException is used, it decides and -EnableException is
    /// ignored.
    /// </summary>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [Alias("Connstring", "ConnectionString")]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.
    /// </para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies the initial database context for the connection instead of connecting to the default database.
    /// Useful when you need to connect directly to a specific database or when the login's default database is unavailable.
    /// </para>
    [Parameter(Position = 2)]
    public string? Database { get; set; }

    /// <para>
    /// Declares the application workload type when connecting to an Always On Availability Group.
    /// Use "ReadOnly" to route connections to readable secondary replicas for reporting workloads, reducing load on the primary replica.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringCast]
    [ValidateSet("ReadOnly", "ReadWrite")]
    public string? ApplicationIntent { get; set; }

    /// <para>
    /// Causes the connection to fail if the target is detected as Azure SQL Database.
    /// Use this to prevent operations that are incompatible with Azure SQL Database from attempting to connect to cloud instances.
    /// </para>
    [Parameter]
    public SwitchParameter AzureUnsupported { get; set; }

    /// <para>
    /// Sets the batch separator for multi-statement SQL execution, defaulting to "GO".
    /// Change this when working with scripts that use different batch separators or when "GO" conflicts with your SQL content.
    /// </para>
    [Parameter(Position = 4)]
    public string? BatchSeparator { get; set; }

    /// <para>
    /// Sets a custom application name in the connection string for identification in SQL Server monitoring tools.
    /// Use this to distinguish dbatools sessions from other applications when analyzing connections in Profiler, Extended Events, or sys.dm_exec_sessions.
    /// </para>
    [Parameter(Position = 5)]
    public string? ClientName { get; set; }

    /// <para>
    /// Sets the number of retries after SqlClient classifies a connection failure as retryable or detects a broken idle connection. Valid values are 0 to 255; 0 disables connection retries.
    /// When this parameter is omitted, SqlClient uses its endpoint default. Microsoft.Data.SqlClient 5.x and later default to 1 for non-Azure endpoints, 2 for Azure SQL, and 5 for Azure SQL serverless or on-demand endpoints.
    /// SQL Server 2014 and later and Azure SQL support restoring broken idle connections. Older SQL Server versions accept this client-side setting but cannot restore an idle session, so the driver disables that part of connection resiliency after login negotiation.
    /// This does not retry failed queries, deadlocks, command timeouts, or other errors that occur while a query is running.
    /// </para>
    [Parameter(Position = 6)]
    [ValidateRange(0, 255)]
    public int ConnectRetryCount { get; set; }

    /// <para>
    /// Sets the number of seconds between connection retry attempts. Valid values are 1 to 60 seconds, and the setting is ignored when ConnectRetryCount is 0.
    /// SqlClient defaults to 10 seconds when this parameter is omitted.
    /// Set ConnectTimeout high enough to allow the requested retry attempts and intervals to complete.
    /// </para>
    [Parameter(Position = 7)]
    [ValidateRange(1, 60)]
    public int ConnectRetryInterval { get; set; }

    /// <para>
    /// Sets the connection timeout in seconds before the connection attempt fails.
    /// Increase this for slow networks or busy servers, or decrease it for faster failure detection in automated scripts. Azure SQL Database connections typically need 30 seconds.
    /// An explicit value of 0 is preserved and waits indefinitely.
    /// This controls opening the connection, including connection retry attempts. It does not control query execution; use Invoke-DbaQuery -QueryTimeout or this command's StatementTimeout for that.
    /// </para>
    [Parameter(Position = 8)]
    [ValidateRange(0, int.MaxValue)]
    public int ConnectTimeout { get; set; }

    /// <para>
    /// Forces SSL encryption for all data transmitted between client and server.
    /// Required for many compliance scenarios and recommended for connections over untrusted networks. Ensure server certificates are properly configured to avoid connection failures.
    /// </para>
    [Parameter]
    public SwitchParameter EncryptConnection { get; set; }

    /// <para>
    /// Specifies the failover partner server name for database mirroring configurations.
    /// Use this when connecting to databases configured for database mirroring to enable automatic failover if the primary server becomes unavailable.
    /// </para>
    [Parameter(Position = 9)]
    public string? FailoverPartner { get; set; }

    /// <para>
    /// Sets the lock timeout in seconds for transactions on this connection.
    /// Use this to control how long statements wait for locks before timing out, which helps prevent long-running blocking scenarios.
    /// </para>
    [Parameter(Position = 10)]
    public int LockTimeout { get; set; }

    /// <para>
    /// Sets the maximum number of connections allowed in the connection pool for this connection string.
    /// Increase this for applications with high concurrency requirements, but be mindful of server resource limits and licensing constraints.
    /// </para>
    [Parameter(Position = 11)]
    public int MaxPoolSize { get; set; }

    /// <para>
    /// Sets the minimum number of connections maintained in the connection pool for this connection string.
    /// Use this to pre-warm the connection pool for better performance when you know connections will be used frequently.
    /// </para>
    [Parameter(Position = 12)]
    public int MinPoolSize { get; set; }

    /// <para>
    /// Specifies the minimum SQL Server version required for the connection to succeed.
    /// Use this to ensure scripts only run against SQL Server versions that support the required features, preventing compatibility issues.
    /// The version is read from SMO, falling back to the version reported by the connection and then to the version reported by T-SQL on instances too old for SMO to describe. If none of these is available the connection is allowed through.
    /// Instances older than SQL Server 2008 (version 10) are refused whether or not this parameter is used.
    /// </para>
    [Parameter(Position = 13)]
    public int MinimumVersion { get; set; }

    /// <para>
    /// Enables Multiple Active Result Sets (MARS) allowing multiple commands to be executed simultaneously on a single connection.
    /// Use this when you need to execute multiple queries concurrently without opening additional connections, though it can impact performance.
    /// </para>
    [Parameter]
    public SwitchParameter MultipleActiveResultSets { get; set; }

    /// <para>
    /// Enables faster detection and connection to the active server in Always On Availability Groups across multiple subnets.
    /// Essential for AG configurations where replicas are in different subnets, reducing connection time during failover scenarios.
    /// </para>
    [Parameter]
    public SwitchParameter MultiSubnetFailover { get; set; }

    /// <para>
    /// Specifies the network protocol for connecting to SQL Server.
    /// Use "TcpIp" for remote connections, "NamedPipes" for local connections with better security, or "SharedMemory" for fastest local connections. Most modern environments use TcpIp.
    /// </para>
    [Parameter(Position = 14)]
    [PsStringCast]
    [ValidateSet("TcpIp", "NamedPipes", "Multiprotocol", "AppleTalk", "BanyanVines", "Via", "SharedMemory", "NWLinkIpxSpx")]
    public string? NetworkProtocol { get; set; }

    /// <para>
    /// Creates a dedicated connection that bypasses connection pooling.
    /// Use this for long-running operations, dedicated admin connections, or when you need to ensure the connection isn't shared with other processes.
    /// </para>
    [Parameter]
    public SwitchParameter NonPooledConnection { get; set; }

    /// <para>
    /// Sets the network packet size in bytes for communication with SQL Server.
    /// Increase from the default 4096 bytes to improve performance for large data transfers, but ensure the server is configured to support the same packet size.
    /// </para>
    [Parameter(Position = 15)]
    public int PacketSize { get; set; }

    /// <para>
    /// Sets the maximum lifetime in seconds for pooled connections before they're discarded and recreated.
    /// Use this in clustered environments to force load balancing or to refresh connections periodically. Zero means unlimited lifetime.
    /// </para>
    [Parameter(Position = 16)]
    public int PooledConnectionLifetime { get; set; }

    /// <para>
    /// Controls how SQL commands are processed by the connection.
    /// Use "CaptureSql" to generate scripts without execution, "ExecuteAndCaptureSql" to both execute and log commands, or "ExecuteSql" for normal execution.
    /// </para>
    [Parameter(Position = 17)]
    [PsStringCast]
    [ValidateSet("CaptureSql", "ExecuteAndCaptureSql", "ExecuteSql")]
    public string? SqlExecutionModes { get; set; }

    /// <para>
    /// Sets the timeout in seconds for SQL statement execution before canceling the command.
    /// Use this to prevent runaway queries from blocking operations indefinitely. Zero means unlimited, but set reasonable limits for production environments.
    /// </para>
    [Parameter(Position = 18)]
    public int StatementTimeout { get; set; }

    /// <para>
    /// Bypasses certificate validation when using encrypted connections.
    /// Use this for development environments or when connecting to servers with self-signed certificates, but avoid in production for security reasons.
    /// </para>
    [Parameter]
    public SwitchParameter TrustServerCertificate { get; set; }

    /// <para>
    /// Attempts connection with proper TLS validation first, then retries with TrustServerCertificate if the initial connection fails due to certificate validation.
    /// Provides a secure-by-default approach for mixed environments where some servers have valid certificates and others do not.
    /// Only retries on certificate validation failures, not on other connection errors like authentication or network issues.
    /// </para>
    [Parameter]
    public SwitchParameter AllowTrustServerCertificate { get; set; }

    /// <para>
    /// Sets the workstation name visible in SQL Server monitoring and session information.
    /// Use this to identify the source of connections in sys.dm_exec_sessions or when troubleshooting connection issues.
    /// </para>
    [Parameter(Position = 19)]
    public string? WorkstationId { get; set; }

    /// <para>
    /// Enables Always Encrypted support for accessing encrypted columns in databases with column-level encryption.
    /// Required when working with sensitive data protected by Always Encrypted, allowing proper decryption of encrypted column values.
    /// </para>
    [Parameter]
    public SwitchParameter AlwaysEncrypted { get; set; }

    /// <para>
    /// Adds custom connection string parameters to the generated connection string.
    /// Use this for advanced connection properties like custom timeout values, SSL settings, or application-specific parameters that aren't covered by other parameters.
    /// When ConnectRetryCount, ConnectRetryInterval, or ConnectTimeout is also passed explicitly, the explicit parameter takes precedence.
    /// </para>
    [Parameter(Position = 20)]
    public string? AppendConnectionString { get; set; }

    /// <para>
    /// Returns only a SqlConnection object instead of the full SMO server object.
    /// Use this when you only need basic connection functionality and want to reduce memory overhead or avoid SMO initialization.
    /// </para>
    [Parameter]
    public SwitchParameter SqlConnectionOnly { get; set; }

    /// <para>
    /// Specifies the domain for Azure SQL Database connections, defaulting to database.windows.net.
    /// Use this when connecting to Azure SQL instances in sovereign clouds or custom domains that require different authentication methods.
    /// </para>
    [Parameter(Position = 21)]
    public string AzureDomain { get; set; } = "database.windows.net";

    /// <para>
    /// Specifies the Azure Active Directory tenant ID for Azure SQL Database authentication.
    /// Required when using service principal authentication or when your account exists in multiple Azure AD tenants.
    /// </para>
    [Parameter(Position = 22)]
    public string? Tenant { get; set; }

    /// <para>
    /// Authenticates to Azure SQL Database using an access token generated by Get-AzAccessToken or New-DbaAzAccessToken.
    /// Use this for service principal authentication or when integrating with Azure automation that provides pre-generated tokens. Tokens expire after one hour and cannot be renewed.
    /// </para>
    [Parameter(Position = 23)]
    public PSObject? AccessToken { get; set; }

    /// <para>
    /// Specifies the authentication method for connecting to Azure SQL or Entra ID-protected SQL Server instances.
    /// Use "ActiveDirectoryInteractive" for Entra ID (Azure AD) authentication with MFA — a browser dialog will prompt you to select your Entra ID account.
    /// Use "ActiveDirectoryIntegrated" for Entra ID integrated authentication using your current Windows session.
    /// Use "ActiveDirectoryPassword" for Entra ID authentication with a username and password via SqlCredential.
    /// Use "ActiveDirectoryServicePrincipal" for service principal authentication (client ID and secret via SqlCredential).
    /// Use "ActiveDirectoryManagedIdentity" for managed identity authentication in Azure-hosted environments.
    /// Use "ActiveDirectoryDeviceCodeFlow" for device code flow authentication.
    /// </para>
    [Parameter(Position = 24)]
    [PsStringCast]
    [ValidateSet(
        ConnectionService.EntraAuthentication.Integrated,
        ConnectionService.EntraAuthentication.Interactive,
        ConnectionService.EntraAuthentication.Password,
        ConnectionService.EntraAuthentication.ServicePrincipal,
        ConnectionService.EntraAuthentication.ManagedIdentity,
        ConnectionService.EntraAuthentication.DeviceCodeFlow)]
    public string? AuthenticationType { get; set; }

    /// <para>
    /// Creates a dedicated administrator connection (DAC) for emergency access to SQL Server.
    /// Use this when SQL Server is unresponsive to regular connections, allowing you to diagnose and resolve critical issues. Remember to manually disconnect the connection when finished.
    /// </para>
    [Parameter]
    public SwitchParameter DedicatedAdminConnection { get; set; }

    /// <para>
    /// Reports whether a new connection was opened, by writing $true or $false into the referenced variable: pass a variable that already exists as [ref]$variable.
    /// Use this when your command has to clean up after itself: only close a connection when this is $true, because a connection that was passed in belongs to the caller and closing it takes their session, their temp tables and their database context with it. When several instances are connected in one call, the value reflects the last connection that was returned.
    /// </para>
    // [ref] in the pinned param block is PSReference; ProcessRecord writes .Value when a reference was given.
    [Parameter(Position = 25)]
    public PSReference? IsNewConnectionReference { get; set; }

    /// <para>
    /// Changes exception handling from throwing errors to displaying warnings.
    /// Use this in interactive sessions where you want graceful error handling instead of script-stopping exceptions, which is the default behavior for this command.
    /// </para>
    [Parameter]
    public SwitchParameter DisableException { get; set; }
}
