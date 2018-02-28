function New-DbaSqlConnectionString {
    <#
.SYNOPSIS
Builds or extracts a SQL Server Connection String

.DESCRIPTION
Builds or extracts a SQL Server Connection String

See https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.connectionstring.aspx
and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnectionstringbuilder.aspx
and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.aspx

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user be it Windows or SQL Server. Windows users are determiend by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

.PARAMETER AccessToken
Gets or sets the access token for the connection.

.PARAMETER AppendConnectionString
Appends to the current connection string. Note that you cannot pass authenitcation information using this method. Use -SqlInstance and, optionaly, -SqlCredential to set authentication information.

.PARAMETER ApplicationIntent
Declares the application workload type when connecting to a server. Possible values are ReadOnly and ReadWrite.

.PARAMETER BatchSeparator
By default, this is "GO"

.PARAMETER ClientName
By default, this command sets the client to "dbatools PowerShell module - dbatools.io - custom connection" if you're doing anything that requires profiling, you can look for this client name. Using -ClientName allows you to set your own custom client.

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

Valid values incldue CaptureSql, ExecuteAndCaptureSql and ExecuteSql.

.PARAMETER StatementTimeout
Sets the number of seconds a statement is given to run before failing with a time-out error.

.PARAMETER TrustServerCertificate
ets or sets a value that indicates whether the channel will be encrypted while bypassing walking the certificate chain to validate trust.

.PARAMETER WorkstationId
Sets the name of the workstation connecting to SQL Server.

.NOTES
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.LINK
 https://dbatools.io/New-DbaSqlConnectionString

.EXAMPLE
New-DbaSqlConnectionString -SqlInstance sql2014

Creates a connection string that connects using Windows Authentication

.EXAMPLE
Connect-DbaInstance -SqlInstance sql2016 | New-DbaSqlConnectionString

Builds a connected SMO object using Connect-DbaInstance then extracts and displays the connection string

.EXAMPLE
$wincred = Get-Credential ad\sqladmin
New-DbaSqlConnectionString -SqlInstance sql2014 -Credential $wincred

Creates a connection string that connects using alternative Windows credentials

.EXAMPLE
$sqlcred = Get-Credential sqladmin
$server = New-DbaSqlConnectionString -SqlInstance sql2014 -Credential $sqlcred

Login to sql2014 as SQL login sqladmin.

.EXAMPLE
$server = New-DbaSqlConnectionString -SqlInstance sql2014 -ClientName "mah connection"

Creates a connection string that connects using Windows Authentication and uses the client name "mah connection". So when you open up profiler or use extended events, you can search for "mah connection".

.EXAMPLE
$server = New-DbaSqlConnectionString -SqlInstance sql2014 -AppendConnectionString "Packet Size=4096;AttachDbFilename=C:\MyFolder\MyDataFile.mdf;User Instance=true;"

Creates a connection string that connects to sql2014 using Windows Authentication, then it sets the packet size (this can also be done via -PacketSize) and other connection attributes.

.EXAMPLE
$server = New-DbaSqlConnectionString -SqlInstance sql2014 -NetworkProtocol TcpIp -MultiSubnetFailover

Creates a connection string with Windows Authentication that uses TCPIP and has MultiSubnetFailover enabled.

.EXAMPLE
$connstring = New-DbaSqlConnectionString sql2016 -ApplicationIntent ReadOnly

Creates a connection string with ReadOnly ApplicantionIntent.

#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("SqlCredential")]
        [PSCredential]$Credential,
        [string]$AccessToken,
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$ApplicationIntent,
        [string]$BatchSeparator,
        [string]$ClientName = "custom connection",
        [int]$ConnectTimeout,
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

    process {
        foreach ($instance in $sqlinstance) {

            if ($instance.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) {
                return $instance.ConnectionContext.ConnectionString
            }
            else {
                $guid = [System.Guid]::NewGuid()
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server $guid

                if ($AppendConnectionString) {
                    $connstring = $server.ConnectionContext.ConnectionString
                    $server.ConnectionContext.ConnectionString = "$connstring;$appendconnectionstring"
                    $server.ConnectionContext.ConnectionString
                }
                else {

                    $server.ConnectionContext.ApplicationName = $clientname

                    if ($AccessToken) { $server.ConnectionContext.AccessToken = $AccessToken }
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

                    $connstring = $server.ConnectionContext.ConnectionString
                    if ($MultiSubnetFailover) { $connstring = "$connstring;MultiSubnetFailover=True" }
                    if ($FailoverPartner) { $connstring = "$connstring;Failover Partner=$FailoverPartner" }
                    if ($ApplicationIntent) { $connstring = "$connstring;ApplicationIntent=$ApplicationIntent;" }

                    if ($connstring -ne $server.ConnectionContext.ConnectionString) {
                        $server.ConnectionContext.ConnectionString = $connstring
                    }
                    if ($null -ne $Credential.username) {
                        $username = ($Credential.username).TrimStart("\")

                        if ($username -like "*\*") {
                            $username = $username.Split("\")[1]
                            $authtype = "Windows Authentication with Credential"
                            $server.ConnectionContext.LoginSecure = $true
                            $server.ConnectionContext.ConnectAsUser = $true
                            $server.ConnectionContext.ConnectAsUserName = $username
                            $server.ConnectionContext.ConnectAsUserPassword = ($Credential).GetNetworkCredential().Password
                        }
                        else {
                            $authtype = "SQL Authentication"
                            $server.ConnectionContext.LoginSecure = $false
                            $server.ConnectionContext.set_Login($username)
                            $server.ConnectionContext.set_SecurePassword($Credential.Password)
                        }
                    }

                    ($server.ConnectionContext.ConnectionString).Replace($guid, $SqlInstance)
                }
            }
        }
    }
}