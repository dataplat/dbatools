Function Connect-SqlServer {
<# 
.SYNOPSIS 
Internal function that creates SMO server object. Input can be text or SMO.Server.
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$ParameterConnection,
		[switch]$RegularUser,
		[string]$ApplicationName = "dbatools PowerShell module - dbatools.io"
	)
	
	$SqlServer = $SqlServer[0]
	
	if ($SqlServer.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) {
		
		if ($ParameterConnection) {
			$paramserver = New-Object Microsoft.SqlServer.Management.Smo.Server
			$paramserver.ConnectionContext.ApplicationName = $ApplicationName
			$paramserver.ConnectionContext.ConnectionString = $SqlServer.ConnectionContext.ConnectionString
			
			if ($SqlCredential.username -ne $null) {
				$username = ($SqlCredential.username).TrimStart("\")
				
				if ($username -like "*\*") {
					$username = $username.Split("\")[1]
					$authtype = "Windows Authentication with Credential"
					$paramserver.ConnectionContext.LoginSecure = $true
					$paramserver.ConnectionContext.ConnectAsUser = $true
					$paramserver.ConnectionContext.ConnectAsUserName = $username
					$paramserver.ConnectionContext.ConnectAsUserPassword = ($SqlCredential).GetNetworkCredential().Password
				}
				else {
					$authtype = "SQL Authentication"
					$paramserver.ConnectionContext.LoginSecure = $false
					$paramserver.ConnectionContext.set_Login($username)
					$paramserver.ConnectionContext.set_SecurePassword($SqlCredential.Password)
				}
			}
			
			$paramserver.ConnectionContext.Connect()
			return $paramserver
		}
		
		if ($SqlServer.ConnectionContext.IsOpen -eq $false) {
			$SqlServer.ConnectionContext.Connect()
		}
		return $SqlServer
	}
	
	# This seems a little complex but is required because some connections do TCP,sqlserver
	[regex]$portdetection = ":\d{1,5}$"
	if ($sqlserver.ToString().LastIndexOf(":") -ne -1) {
		$portnumber = $sqlserver.ToString().substring($sqlserver.ToString().LastIndexOf(":"))
		if ($portnumber -match $portdetection) {
			$replacedportseparator = $portnumber -replace ":", ","
			$sqlserver = $sqlserver -replace $portnumber, $replacedportseparator
		}
	}
	
	if ($null -ne $SqlServer.Name) { $SqlServer = $SqlServer.Name }
	$server = New-Object Microsoft.SqlServer.Management.Smo.Server $SqlServer
	$server.ConnectionContext.ApplicationName = $ApplicationName
	
	<#
	 Just realized this will not work because it's SMO ;) We will return to if this is still needed and how to handle it in 1.0.
	
	if ($server.Configuration.SmoAndDmoXPsEnabled.RunValue -eq 0)
    {
        Write-Error "Accessing this server via SQL Management Objects (SMO) or Distributed Management Objects (DMO) is currently not permitted.
                     Enable the option 'SMO and DMO XPs' on your instance using sp_configure to continue.
                     Note that this will require 'Show Advanced Options' to be enabled using sp_configure as well."
        break
    }
	#>
	
	try {
		if ($SqlCredential.username -ne $null) {
			$username = ($SqlCredential.username).TrimStart("\")
			
			if ($username -like "*\*") {
				$username = $username.Split("\")[1]
				$authtype = "Windows Authentication with Credential"
				$server.ConnectionContext.LoginSecure = $true
				$server.ConnectionContext.ConnectAsUser = $true
				$server.ConnectionContext.ConnectAsUserName = $username
				$server.ConnectionContext.ConnectAsUserPassword = ($SqlCredential).GetNetworkCredential().Password
			}
			else {
				$authtype = "SQL Authentication"
				$server.ConnectionContext.LoginSecure = $false
				$server.ConnectionContext.set_Login($username)
				$server.ConnectionContext.set_SecurePassword($SqlCredential.Password)
			}
		}
	}
	catch { }
	
	try {
		if ($ParameterConnection) {
			$server.ConnectionContext.ConnectTimeout = 7
		}
		
		$server.ConnectionContext.Connect()
	}
	catch {
		$message = $_.Exception.InnerException.InnerException
		$message = $message.ToString()
		$message = ($message -Split '-->')[0]
		$message = ($message -Split 'at System.Data.SqlClient')[0]
		$message = ($message -Split 'at System.Data.ProviderBase')[0]
		throw "Can't connect to $sqlserver`: $message "
	}
	
	if ($RegularUser -eq $false) {
		if ($server.ConnectionContext.FixedServerRoles -notmatch "SysAdmin") {
			throw "Not a sysadmin on $SqlServer. Quitting."
		}
	}
	
	if ($ParameterConnection -eq $false) {
		$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Trigger], 'IsSystemObject')
		$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Rule], 'IsSystemObject')
		$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Schema], 'IsSystemObject')
		$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.SqlAssembly], 'IsSystemObject')
		$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Table], 'IsSystemObject')
		$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.View], 'IsSystemObject')
		$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.StoredProcedure], 'IsSystemObject')
		$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.UserDefinedFunction], 'IsSystemObject')
		
		if ($server.VersionMajor -eq 8) {
			# 2000
			$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], 'ReplicationOptions', 'Collation', 'CompatibilityLevel', 'CreateDate', 'ID', 'IsAccessible', 'IsFullTextEnabled', 'IsUpdateable', 'LastBackupDate', 'LastDifferentialBackupDate', 'LastLogBackupDate', 'Name', 'Owner', 'PrimaryFilePath', 'ReadOnly', 'RecoveryModel', 'Status', 'Version')
			$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], 'CreateDate', 'DateLastModified', 'DefaultDatabase', 'DenyWindowsLogin', 'IsSystemObject', 'Language', 'LanguageAlias', 'LoginType', 'Name', 'Sid', 'WindowsLoginAccessType')
		}
		
		
		elseif ($server.VersionMajor -eq 9 -or $server.VersionMajor -eq 10) {
			# 2005 and 2008
			$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], 'ReplicationOptions', 'BrokerEnabled', 'Collation', 'CompatibilityLevel', 'CreateDate', 'ID', 'IsAccessible', 'IsFullTextEnabled', 'IsMirroringEnabled', 'IsUpdateable', 'LastBackupDate', 'LastDifferentialBackupDate', 'LastLogBackupDate', 'Name', 'Owner', 'PrimaryFilePath', 'ReadOnly', 'RecoveryModel', 'Status', 'Trustworthy', 'Version')
			$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], 'AsymmetricKey', 'Certificate', 'CreateDate', 'Credential', 'DateLastModified', 'DefaultDatabase', 'DenyWindowsLogin', 'ID', 'IsDisabled', 'IsLocked', 'IsPasswordExpired', 'IsSystemObject', 'Language', 'LanguageAlias', 'LoginType', 'MustChangePassword', 'Name', 'PasswordExpirationEnabled', 'PasswordPolicyEnforced', 'Sid', 'WindowsLoginAccessType')
		}
		
		else {
			# 2012 and above
			$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Database], 'ReplicationOptions', 'ActiveConnections', 'AvailabilityDatabaseSynchronizationState', 'AvailabilityGroupName', 'BrokerEnabled', 'Collation', 'CompatibilityLevel', 'ContainmentType', 'CreateDate', 'ID', 'IsAccessible', 'IsFullTextEnabled', 'IsMirroringEnabled', 'IsUpdateable', 'LastBackupDate', 'LastDifferentialBackupDate', 'LastLogBackupDate', 'Name', 'Owner', 'PrimaryFilePath', 'ReadOnly', 'RecoveryModel', 'Status', 'Trustworthy', 'Version')
			$server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.Login], 'AsymmetricKey', 'Certificate', 'CreateDate', 'Credential', 'DateLastModified', 'DefaultDatabase', 'DenyWindowsLogin', 'ID', 'IsDisabled', 'IsLocked', 'IsPasswordExpired', 'IsSystemObject', 'Language', 'LanguageAlias', 'LoginType', 'MustChangePassword', 'Name', 'PasswordExpirationEnabled', 'PasswordHashAlgorithm', 'PasswordPolicyEnforced', 'Sid', 'WindowsLoginAccessType')
		}
	}
	
	return $server
}