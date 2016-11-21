Function Connect-DbaSqlServer
{
<#
.SYNOPSIS
Creates an efficient SMO SQL Server object.

.DESCRIPTION
This command is efficient because it initializes properties that do not cause enumeration by default. It also supports both Windows and SQL Server credentials and detects which alternative credentials. 

By default, this command also sets the client to "dbatools PowerShell module - dbatools.io - custom connection" if you're doing anything that requires profiling, you can look for this client name.

Alternatively, you can pass in whichever client name you'd like using the -ClientName parameter.
	
See https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.connectionstring.aspx for more information about ConnectionString properties.

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user be it Windows or SQL Server. Windows users are determiend by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

.PARAMETER AccessToken	

.PARAMETER AppendConnectionString	
	
.PARAMETER ApplicationIntent	

.PARAMETER BatchSeparator	

.PARAMETER ClientName
By default, this command sets the client to "dbatools PowerShell module - dbatools.io - custom connection" if you're doing anything that requires profiling, you can look for this client name. Using -ClientName allows you to set your own custom client.

.PARAMETER ConnectTimeout	

.PARAMETER EncryptConnection	

.PARAMETER FailoverPartner	

.PARAMETER InUse	

.PARAMETER IsActiveDirectoryUniversalAuth	

.PARAMETER LockTimeout	

.PARAMETER MaxPoolSize	

.PARAMETER MinPoolSize	

.PARAMETER MultipleActiveResultSets	

.PARAMETER MultiSubnetFailover	

.PARAMETER NetworkProtocol	

.PARAMETER NonPooledConnection	

.PARAMETER PacketSize	

.PARAMETER PooledConnectionLifetime	

.PARAMETER SqlExecutionModes	

.PARAMETER StatementTimeout	

.PARAMETER TrueName	

.PARAMETER TrustServerCertificate	

.PARAMETER WorkstationId	

	
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
$sqlcred = Get-Credential sa
Connect-DbaSqlServer -SqlServer sql2014 -Credential $sqlcred

Don't use sa, this one is just an obvious SQL login.

.EXAMPLE
$sqlcred = Get-Credential sqladmin
Connect-DbaSqlServer -SqlServer sql2014 -Credential $sqlcred

Login to sql2014 as SQL login sqladmin.

.EXAMPLE
Connect-DbaSqlServer -SqlServer sql2014 -ClientName "mah connection"

Creates an SMO Server object that connects using Windows Authentication and uses the client name "mah connection". So when you open up profiler or use extended events, you can search for "mah connection".

#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
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
		[switch]$InUse,
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
		[string]$TrueName,
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
			if ($InUse) { $server.ConnectionContext.InUse = $true }
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
			if ($TrueName) { $server.ConnectionContext.TrueName = $TrueName }
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