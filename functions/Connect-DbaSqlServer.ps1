Function Connect-DbaSqlServer
{
<#
.SYNOPSIS
Creates an efficient SMO SQL Server object.

.DESCRIPTION
This command is efficient because it initializes properties that do not cause enumeration by default. It also supports both Windows and SQL Server credentials and detects which alternative credentials. 

By default, this command also sets the client to "dbatools PowerShell module - dbatools.io - custom connection" if you're doing anything that requires profiling, you can look for this client name.

Alternatively, you can pass in whichever client name you'd like using the -ClientName parameter. There are a ton of other parameters for you to explore as well.
	
See https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.connectionstring.aspx
and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnectionstringbuilder.aspx
and https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.aspx

To execute SQL commands, you can use $server.ConnectionContext.ExecuteReader($sql) or $server.Databases['master'].ExecuteNonQuery($sql)

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user be it Windows or SQL Server. Windows users are determiend by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

.PARAMETER AccessToken	
Gets or sets the access token for the connection.
	
.PARAMETER AppendConnectionString	
Appends to the current connection string. Note that you cannot pass authenitcation information using this method. Use -SqlServer and, optionaly, -SqlCredential to set authentication information.

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
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Connect-DbaSqlServer

.EXAMPLE
Connect-DbaSqlServer -SqlServer sql2014

Creates an SMO Server object that connects using Windows Authentication

.EXAMPLE
$wincred = Get-Credential ad\sqladmin
Connect-DbaSqlServer -SqlServer sql2014 -Credential $wincred

Creates an SMO Server object that connects using alternative Windows credentials

.EXAMPLE
$sqlcred = Get-Credential sqladmin
$server = Connect-DbaSqlServer -SqlServer sql2014 -Credential $sqlcred

Login to sql2014 as SQL login sqladmin.

.EXAMPLE
$server = Connect-DbaSqlServer -SqlServer sql2014 -ClientName "mah connection"

Creates an SMO Server object that connects using Windows Authentication and uses the client name "mah connection". So when you open up profiler or use extended events, you can search for "mah connection".

.EXAMPLE
$server = Connect-DbaSqlServer -SqlServer sql2014 -AppendConnectionString "Packet Size=4096;AttachDbFilename=C:\MyFolder\MyDataFile.mdf;User Instance=true;"

Creates an SMO Server object that connects to sql2014 using Windows Authentication, then it sets the packet size (this can also be done via -PacketSize) and other connection attributes.

.EXAMPLE
$server = Connect-DbaSqlServer -SqlServer sql2014 -NetworkProtocol TcpIp -MultiSubnetFailover

Creates an SMO Server object that connects using Windows Authentication that uses TCPIP and has MultiSubnetFailover enabled.

.EXAMPLE
$server = Connect-DbaSqlServer sql2016 -ApplicationIntent ReadOnly

Connects with ReadOnly ApplicantionIntent.
	
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[Alias("SqlCredential")]
		[System.Management.Automation.PSCredential]$Credential,
		[string]$AccessToken,
		[ValidateSet('ReadOnly', 'ReadWrite')]
		[string]$ApplicationIntent,
		[string]$BatchSeparator,
		[string]$ClientName = "dbatools PowerShell module - dbatools.io - custom connection",
		[int]$ConnectTimeout,
		[switch]$EncryptConnection,
		[string]$FailoverPartner,
		[switch]$IsActiveDirectoryUniversalAuth,
		[int]$LockTimeout,
		[int]$MaxPoolSize,
		[int]$MinPoolSize,
		[switch]$MultipleActiveResultSets,
		[switch]$MultiSubnetFailover,
		[ValidateSet('TcpIp','NamedPipes','Multiprotocol','AppleTalk','BanyanVines','Via','SharedMemory','NWLinkIpxSpx')]
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
	
	DynamicParam { if ($sqlserver) { return Get-ParamSqlDatabase -SqlServer $SqlServer -SqlCredential $Credential } }
	
	PROCESS
	{
		if ($SqlServer.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server])
		{
			
			if ($SqlServer.ConnectionContext.IsOpen -eq $false)
			{
				$SqlServer.ConnectionContext.Connect()
			}
			return $SqlServer
		}
		
		$server = New-Object Microsoft.SqlServer.Management.Smo.Server $SqlServer
		
		if ($AppendConnectionString)
		{
			$connstring = $server.ConnectionContext.ConnectionString
			$server.ConnectionContext.ConnectionString = "$connstring;$appendconnectionstring"
			$server.ConnectionContext.Connect()
		}
		else
		{
			
			$server.ConnectionContext.ApplicationName = $clientname
			$database = $psboundparameters.Database
			
			if ($AccessToken) { $server.ConnectionContext.AccessToken = $AccessToken }
			if ($ApplicationIntent) { $server.ConnectionContext.ApplicationIntent = $ApplicationIntent }
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
			
			if ($connstring -ne $server.ConnectionContext.ConnectionString)
			{
				$server.ConnectionContext.ConnectionString = $connstring
			}
			
			try
			{
				if ($Credential.username -ne $null)
				{
					$username = ($Credential.username).TrimStart("\")
					
					if ($username -like "*\*")
					{
						$username = $username.Split("\")[1]
						$authtype = "Windows Authentication with Credential"
						$server.ConnectionContext.LoginSecure = $true
						$server.ConnectionContext.ConnectAsUser = $true
						$server.ConnectionContext.ConnectAsUserName = $username
						$server.ConnectionContext.ConnectAsUserPassword = ($Credential).GetNetworkCredential().Password
					}
					else
					{
						$authtype = "SQL Authentication"
						$server.ConnectionContext.LoginSecure = $false
						$server.ConnectionContext.set_Login($username)
						$server.ConnectionContext.set_SecurePassword($Credential.Password)
					}
				}
				
				$server.ConnectionContext.Connect()
			}
			catch
			{
				$message = $_.Exception.InnerException.InnerException
				$message = $message.ToString()
				$message = ($message -Split '-->')[0]
				$message = ($message -Split 'at System.Data.SqlClient')[0]
				$message = ($message -Split 'at System.Data.ProviderBase')[0]
				throw "Can't connect to $sqlserver`: $message "
			}
			
		}
		
		if ($server.VersionMajor -eq 8)
		{
			# 2000
			$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], 'ReplicationOptions', 'Collation', 'CompatibilityLevel', 'CreateDate', 'ID', 'IsAccessible', 'IsFullTextEnabled', 'IsUpdateable', 'LastBackupDate', 'LastDifferentialBackupDate', 'LastLogBackupDate', 'Name', 'Owner', 'PrimaryFilePath', 'ReadOnly', 'RecoveryModel', 'Status', 'Version')
			$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], 'CreateDate', 'DateLastModified', 'DefaultDatabase', 'DenyWindowsLogin', 'IsSystemObject', 'Language', 'LanguageAlias', 'LoginType', 'Name', 'Sid', 'WindowsLoginAccessType')
		}
		
		elseif ($server.VersionMajor -eq 9 -or $server.VersionMajor -eq 10)
		{
			# 2005 and 2008
			$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], 'ReplicationOptions', 'BrokerEnabled', 'Collation', 'CompatibilityLevel', 'CreateDate', 'ID', 'IsAccessible', 'IsFullTextEnabled', 'IsMirroringEnabled', 'IsUpdateable', 'LastBackupDate', 'LastDifferentialBackupDate', 'LastLogBackupDate', 'Name', 'Owner', 'PrimaryFilePath', 'ReadOnly', 'RecoveryModel', 'Status', 'Trustworthy', 'Version')
			$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], 'AsymmetricKey', 'Certificate', 'CreateDate', 'Credential', 'DateLastModified', 'DefaultDatabase', 'DenyWindowsLogin', 'ID', 'IsDisabled', 'IsLocked', 'IsPasswordExpired', 'IsSystemObject', 'Language', 'LanguageAlias', 'LoginType', 'MustChangePassword', 'Name', 'PasswordExpirationEnabled', 'PasswordPolicyEnforced', 'Sid', 'WindowsLoginAccessType')
		}
		
		else
		{
			# 2012 and above
			$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], 'ReplicationOptions', 'ActiveConnections', 'AvailabilityDatabaseSynchronizationState', 'AvailabilityGroupName', 'BrokerEnabled', 'Collation', 'CompatibilityLevel', 'ContainmentType', 'CreateDate', 'ID', 'IsAccessible', 'IsFullTextEnabled', 'IsMirroringEnabled', 'IsUpdateable', 'LastBackupDate', 'LastDifferentialBackupDate', 'LastLogBackupDate', 'Name', 'Owner', 'PrimaryFilePath', 'ReadOnly', 'RecoveryModel', 'Status', 'Trustworthy', 'Version')
			$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], 'AsymmetricKey', 'Certificate', 'CreateDate', 'Credential', 'DateLastModified', 'DefaultDatabase', 'DenyWindowsLogin', 'ID', 'IsDisabled', 'IsLocked', 'IsPasswordExpired', 'IsSystemObject', 'Language', 'LanguageAlias', 'LoginType', 'MustChangePassword', 'Name', 'PasswordExpirationEnabled', 'PasswordHashAlgorithm', 'PasswordPolicyEnforced', 'Sid', 'WindowsLoginAccessType')
		}
		return $server
	}
}
