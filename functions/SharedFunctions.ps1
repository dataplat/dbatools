# These are shared, mostly internal functions.

Function Update-dbatools
{
<# 
.SYNOPSIS 
Exported function. Updates dbatools. Deletes current copy and replaces it with freshest copy.

.EXAMPLE
Update-dbatools
#>	
	
	Invoke-Expression (Invoke-WebRequest -UseBasicParsing http://git.io/vn1hQ).Content
}

Function Connect-SqlServer
{
<# 
.SYNOPSIS 
Internal function that creates SMO server object. Input can be text or SMO.Server.
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$ParameterConnection,
		[switch]$RegularUser
	)
	
	
	if ($SqlServer.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server])
	{
		
		if ($ParameterConnection)
		{
			$paramserver = New-Object Microsoft.SqlServer.Management.Smo.Server
			$paramserver.ConnectionContext.ConnectTimeout = 2
			$paramserver.ConnectionContext.ApplicationName = "dbatools PowerShell module - dbatools.io"
			$paramserver.ConnectionContext.ConnectionString = $SqlServer.ConnectionContext.ConnectionString
			
			if ($SqlCredential.username -ne $null)
			{
				$username = ($SqlCredential.username).TrimStart("\")
				
				if ($username -like "*\*")
				{
					$username = $username.Split("\")[1]
					$authtype = "Windows Authentication with Credential"
					$server.ConnectionContext.LoginSecure = $true
					$server.ConnectionContext.ConnectAsUser = $true
					$server.ConnectionContext.ConnectAsUserName = $username
					$server.ConnectionContext.ConnectAsUserPassword = ($SqlCredential).GetNetworkCredential().Password
				}
				else
				{
					$authtype = "SQL Authentication"
					$server.ConnectionContext.LoginSecure = $false
					$server.ConnectionContext.set_Login($username)
					$server.ConnectionContext.set_SecurePassword($SqlCredential.Password)
				}
			}
			
			$paramserver.ConnectionContext.Connect()
			return $paramserver
		}
		
		if ($SqlServer.ConnectionContext.IsOpen -eq $false)
		{
			$SqlServer.ConnectionContext.Connect()
		}
		return $SqlServer
	}
	
	$server = New-Object Microsoft.SqlServer.Management.Smo.Server $SqlServer
	$server.ConnectionContext.ApplicationName = "dbatools PowerShell module - dbatools.io"
	
	try
	{
		if ($SqlCredential.username -ne $null)
		{
			$username = ($SqlCredential.username).TrimStart("\")
			
			if ($username -like "*\*")
			{
				$username = $username.Split("\")[1]
				$authtype = "Windows Authentication with Credential"
				$server.ConnectionContext.LoginSecure = $true
				$server.ConnectionContext.ConnectAsUser = $true
				$server.ConnectionContext.ConnectAsUserName = $username
				$server.ConnectionContext.ConnectAsUserPassword = ($SqlCredential).GetNetworkCredential().Password
			}
			else
			{
				$authtype = "SQL Authentication"
				$server.ConnectionContext.LoginSecure = $false
				$server.ConnectionContext.set_Login($username)
				$server.ConnectionContext.set_SecurePassword($SqlCredential.Password)
			}
		}
	}
	catch { }
	
	try
	{
		if ($ParameterConnection)
		{
			$server.ConnectionContext.ConnectTimeout = 2
		}
		else
		{
			$server.ConnectionContext.ConnectTimeout = 3
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
	
	if ($RegularUser -eq $false)
	{
		if ($server.ConnectionContext.FixedServerRoles -notmatch "SysAdmin")
		{
			throw "Not a sysadmin on $SqlServer. Quitting."
		}
	}
	
	if ($ParameterConnection -eq $false)
	{
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
	}
	
	return $server
}

Function Test-SqlConnection
{
<# 
.SYNOPSIS 
Exported function. Tests a the connection to a single instance and shows the output.

.EXAMPLE
Test-SqlConnection sql01

Sample output:

Local PowerShell Enviornment

Windows    : 10.0.10240.0
PowerShell : 5.0.10240.16384
CLR        : 4.0.30319.42000
SMO        : 13.0.0.0
DomainUser : True
RunAsAdmin : False

SQL Server Connection Information

ServerName         : sql01
BaseName           : sql01
InstanceName       : (Default)
AuthType           : Windows Authentication (Trusted)
ConnectingAsUser   : ad\dba
ConnectSuccess     : True
SqlServerVersion   : 12.0.2370
AddlConnectInfo    : N/A
RemoteServer       : True
IPAddress          : 10.0.1.4
NetBIOSname        : SQLSERVER2014A
RemotingAccessible : True
Pingable           : True
DefaultSQLPortOpen : True
RemotingPortOpen   : True
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	
	# Get local enviornment
	Write-Output "Getting local enivornment information"
	$localinfo = @{ } | Select-Object Windows, PowerShell, CLR, SMO, DomainUser, RunAsAdmin
	$localinfo.Windows = [environment]::OSVersion.Version.ToString()
	$localinfo.PowerShell = $PSVersionTable.PSversion.ToString()
	$localinfo.CLR = $PSVersionTable.CLRVersion.ToString()
	$smo = (([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Fullname -like "Microsoft.SqlServer.SMO,*" }).FullName -Split ", ")[1]
	$localinfo.SMO = $smo.TrimStart("Version=")
	$localinfo.DomainUser = $env:computername -ne $env:USERDOMAIN
	$localinfo.RunAsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
	
	# SQL Server
	if ($SqlServer.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) { $SqlServer = $SqlServer.Name.ToString() }
	
	$serverinfo = @{ } | Select-Object ServerName, BaseName, InstanceName, AuthType, ConnectingAsUser, ConnectSuccess, SqlServerVersion, AddlConnectInfo, RemoteServer, IPAddress, NetBIOSname, RemotingAccessible, Pingable, DefaultSQLPortOpen, RemotingPortOpen
	
	$serverinfo.ServerName = $sqlserver
	
	Write-Output "Determining SQL Server base address"
	$baseaddress = $sqlserver.Split("\")[0]
	try { $instance = $sqlserver.Split("\")[1] }
	catch { $instance = "(Default)" }
	if ($instance -eq $null) { $instance = "(Default)" }
	
	if ($baseaddress -eq "." -or $baseaddress -eq $env:COMPUTERNAME)
	{
		$ipaddr = "."
		$hostname = $env:COMPUTERNAME
		$baseaddress = $env:COMPUTERNAME
	}
	
	$serverinfo.BaseName = $baseaddress
	$remote = $baseaddress -ne $env:COMPUTERNAME
	$serverinfo.InstanceName = $instance
	$serverinfo.RemoteServer = $remote
	
	Write-Output "Resolving IP address"
	try
	{
		$hostentry = [System.Net.Dns]::GetHostEntry($baseaddress)
		$ipaddr = ($hostentry.AddressList | Where-Object { $_ -notlike '169.*' } | Select-Object -First 1).IPAddressToString
	}
	catch { $ipaddr = "Unable to resolve" }
	
	$serverinfo.IPAddress = $ipaddr
	
	Write-Output "Resolving NetBIOS name"
	try
	{
		$hostname = (Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter IPEnabled=TRUE -ComputerName $ipaddr -ErrorAction SilentlyContinue).PSComputerName
		if ($hostname -eq $null) { $hostname = (nbtstat -A $ipaddr | Where-Object { $_ -match '\<00\>  UNIQUE' } | ForEach-Object { $_.SubString(4, 14) }).Trim() }
	}
	catch { $hostname = "Unknown" }
	
	$serverinfo.NetBIOSname = $hostname
	
	
	if ($remote -eq $true)
	{
		# Test for WinRM #Test-WinRM neh
		Write-Output "Checking remote acccess"
		winrm id -r:$hostname 2>$null | Out-Null
		if ($LastExitCode -eq 0) { $remoting = $true }
		else { $remoting = $false }
		
		$serverinfo.RemotingAccessible = $remoting
		
		Write-Output "Testing raw socket connection to PowerShell remoting port"
		$tcp = New-Object System.Net.Sockets.TcpClient
		try
		{
			$tcp.Connect($baseaddress, 135)
			$tcp.Close()
			$tcp.Dispose()
			$remotingport = $true
		}
		catch { $remotingport = $false }
		
		$serverinfo.RemotingPortOpen = $remotingport
	}
	
	# Test Connection first using Test-Connection which requires ICMP access then failback to tcp if pings are blocked
	Write-Output "Testing ping to $baseaddress"
	$testconnect = Test-Connection -ComputerName $baseaddress -Count 1 -Quiet
	
	$serverinfo.Pingable = $testconnect
	
	# SQL Server connection
	
	if ($instance -eq "(Default)")
	{
		Write-Output "Testing raw socket connection to default SQL port"
		$tcp = New-Object System.Net.Sockets.TcpClient
		try
		{
			$tcp.Connect($baseaddress, 1433)
			$tcp.Close()
			$tcp.Dispose()
			$sqlport = $true
		}
		catch { $sqlport = $false }
		$serverinfo.DefaultSQLPortOpen = $sqlport
	}
	else { $serverinfo.DefaultSQLPortOpen = "N/A" }
	
	$server = New-Object Microsoft.SqlServer.Management.Smo.Server $SqlServer
	
	try
	{
		if ($SqlCredential -ne $null)
		{
			$username = ($SqlCredential.username).TrimStart("\")

			if ($username -like "*\*")
			{
				$username = $username.Split("\")[1]
				$authtype = "Windows Authentication with Credential"
				$server.ConnectionContext.LoginSecure = $true
				$server.ConnectionContext.ConnectAsUser = $true
				$server.ConnectionContext.ConnectAsUserName = $username
				$server.ConnectionContext.ConnectAsUserPassword = ($SqlCredential).GetNetworkCredential().Password
			}
			else
			{
				$authtype = "SQL Authentication"
				$server.ConnectionContext.LoginSecure = $false
				$server.ConnectionContext.set_Login($username)
				$server.ConnectionContext.set_SecurePassword($SqlCredential.Password)
			}
		}
		else
		{
			$authtype = "Windows Authentication (Trusted)"
			$username = "$env:USERDOMAIN\$env:username"
		}
	}
	catch
	{
		Write-Exception $_
		$authtype = "Windows Authentication (Trusted)"
		$username = "$env:USERDOMAIN\$env:username"
	}
	
	$serverinfo.ConnectingAsUser = $username
	$serverinfo.AuthType = $authtype
	
	
	Write-Output "Attempting to connect to $SqlServer as $username "
	try
	{
		$server.ConnectionContext.ConnectTimeout = 10
		$server.ConnectionContext.Connect()
		$connectSuccess = $true
		$version = $server.Version.ToString()
		$addlinfo = "N/A"
		$server.ConnectionContext.Disconnect()
	}
	catch
	{
		$connectSuccess = $false
		$version = "N/A"
		$addlinfo = $_.Exception
	}
	
	$serverinfo.ConnectSuccess = $connectSuccess
	$serverinfo.SqlServerVersion = $version
	$serverinfo.AddlConnectInfo = $addlinfo
	
	Write-Output "`nLocal PowerShell Enviornment"
	$localinfo | Select-Object Windows, PowerShell, CLR, SMO, DomainUser, RunAsAdmin
	
	Write-Output "SQL Server Connection Information`n"
	$serverinfo | Select-Object ServerName, BaseName, InstanceName, AuthType, ConnectingAsUser, ConnectSuccess, SqlServerVersion, AddlConnectInfo, RemoteServer, IPAddress, NetBIOSname, RemotingAccessible, Pingable, DefaultSQLPortOpen, RemotingPortOpen
	
}

<#
				
		All functions below are internal to the module and cannot be executed via command line.
				
#>

Function Connect-AsServer
{
<# 
.SYNOPSIS 
Internal function that creates SMO server object. Input can be text or SMO.Server.
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$AsServer,
		[switch]$ParameterConnection
	)
	
	if ($AsServer.GetType() -eq [Microsoft.AnalysisServices.Server])
	{
		
		if ($ParameterConnection)
		{
			$paramserver = New-Object Microsoft.AnalysisServices.Server
			$paramserver.Connect("Data Source=$($AsServer.Name);Connect Timeout=2")
			return $paramserver
		}
		
		if ($AsServer.Connected -eq $false) { $AsServer.Connect("Data Source=$($AsServer.Name);Connect Timeout=3") }
		return $AsServer
	}
	
	$server = New-Object Microsoft.AnalysisServices.Server
	
	try
	{
		if ($ParameterConnection)
		{
			$server.Connect("Data Source=$AsServer;Connect Timeout=2")
		}
		else { $server.Connect("Data Source=$AsServer;Connect Timeout=3") }
	}
	catch
	{
		$message = $_.Exception.InnerException
		$message = $message.ToString()
		$message = ($message -Split '-->')[0]
		$message = ($message -Split 'at System.Data.SqlClient')[0]
		$message = ($message -Split 'at System.Data.ProviderBase')[0]
		throw "Can't connect to $asserver`: $message "
	}
	
	return $server
}

Function Invoke-SmoCheck
{
<# 
.SYNOPSIS 
Checks for PowerShell SMO version vs SQL Server's SMO version.

#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer
	)
	
	if ($script:smocheck -ne $true)
	{
		$script:smocheck = $true
		$smo = (([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Fullname -like "Microsoft.SqlServer.SMO,*" }).FullName -Split ", ")[1]
		$smo = ([version]$smo.TrimStart("Version=")).Major
		$serverversion = $SqlServer.version.major
		
		if ($serverversion - $smo -gt 1)
		{
			Write-Warning "Your version of SMO is $smo, which is significantly older than $($sqlserver.name)'s version $($SqlServer.version.major)."
			Write-Warning "This may present an issue when migrating certain portions of SQL Server."
			Write-Warning "If you encounter issues, consider upgrading SMO."
		}
	}
}


Function Get-OfflineSqlFileStructure
{
<#
.SYNOPSIS
Internal function. Returns dictionary object that contains file structures for SQL databases.

#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateNotNullOrEmpty()]
		[object]$SqlServer,
		[Parameter(Mandatory = $true, Position = 1)]
		[string]$dbname,
		[Parameter(Mandatory = $true, Position = 2)]
		[object]$filelist,
		[Parameter(Mandatory = $false, Position = 3)]
		[bool]$ReuseSourceFolderStructure,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	
	$destinationfiles = @{ };
	$logfiles = $filelist | Where-Object { $_.Type -eq "L" }
	$datafiles = $filelist | Where-Object { $_.Type -ne "L" }
	$filestream = $filelist | Where-Object { $_.Type -eq "S" }
	
	if ($filestream)
	{
		$sql = "select coalesce(SERVERPROPERTY('FilestreamConfiguredLevel'),0) as fs"
		$fscheck = $server.databases['master'].ExecuteWithResults($sql)
		if ($fscheck.tables.fs -eq 0) { return $false }
	}
	
	# Data Files
	foreach ($file in $datafiles)
	{
		# Destination File Structure
		$d = @{ }
		if ($ReuseSourceFolderStructure -eq $true)
		{
			$d.physical = $file.PhysicalName
		}
		else
		{
			$directory = Get-SqlDefaultPaths $server data
			$filename = Split-Path $($file.PhysicalName) -leaf
			$d.physical = "$directory\$filename"
		}
		
		$d.logical = $file.LogicalName
		$destinationfiles.add($file.LogicalName, $d)
	}
	
	# Log Files
	foreach ($file in $logfiles)
	{
		$d = @{ }
		if ($ReuseSourceFolderStructure)
		{
			$d.physical = $file.PhysicalName
		}
		else
		{
			$directory = Get-SqlDefaultPaths $server log
			$filename = Split-Path $($file.PhysicalName) -leaf
			$d.physical = "$directory\$filename"
		}
		
		$d.logical = $file.LogicalName
		$destinationfiles.add($file.LogicalName, $d)
	}
	
	return $destinationfiles
}

Function Get-SqlFileStructure
{
<#
.SYNOPSIS
Internal function. Returns custom object that contains file structures on destination paths (\\sqlserver\m$\mssql\etc\etc\file.mdf) for
source and destination servers.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateNotNullOrEmpty()]
		[object]$source,
		[Parameter(Mandatory = $true, Position = 1)]
		[ValidateNotNullOrEmpty()]
		[object]$destination,
		[Parameter(Mandatory = $false, Position = 2)]
		[bool]$ReuseSourceFolderStructure,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential
	)
	
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$source = $sourceserver.DomainInstanceName
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
	$destination = $destserver.DomainInstanceName
	
	$sourcenetbios = Resolve-NetBiosName $sourceserver
	$destnetbios = Resolve-NetBiosName $destserver
	
	$dbcollection = @{ };
	
	foreach ($db in $sourceserver.databases)
	{
		$dbstatus = $db.status.toString()
		if ($dbstatus.StartsWith("Normal") -eq $false) { continue }
		$destinationfiles = @{ }; $sourcefiles = @{ }
		
		# Data Files
		foreach ($filegroup in $db.filegroups)
		{
			foreach ($file in $filegroup.files)
			{
				# Destination File Structure
				$d = @{ }
				if ($ReuseSourceFolderStructure)
				{
					$d.physical = $file.filename
				}
				else
				{
					$directory = Get-SqlDefaultPaths $destserver data
					$filename = Split-Path $($file.filename) -leaf
					$d.physical = "$directory\$filename"
				}
				$d.logical = $file.name
				$d.remotefilename = Join-AdminUnc $destnetbios $d.physical
				$destinationfiles.add($file.name, $d)
				
				# Source File Structure
				$s = @{ }
				$s.logical = $file.name
				$s.physical = $file.filename
				$s.remotefilename = Join-AdminUnc $sourcenetbios $s.physical
				$sourcefiles.add($file.name, $s)
			}
		}
		
		# Add support for Full Text Catalogs in SQL Server 2005 and below
		if ($sourceserver.VersionMajor -lt 10)
		{
			foreach ($ftc in $db.FullTextCatalogs)
			{
				# Destination File Structure
				$d = @{ }
				$pre = "sysft_"
				$name = $ftc.name
				$physical = $ftc.RootPath
				$logical = "$pre$name"
				if ($ReuseSourceFolderStructure)
				{
					$d.physical = $physical
				}
				else
				{
					$directory = Get-SqlDefaultPaths $destserver data
					if ($destserver.VersionMajor -lt 10) { $directory = "$directory\FTDATA" }
					$filename = Split-Path($physical) -leaf
					$d.physical = "$directory\$filename"
				}
				$d.logical = $logical
				$d.remotefilename = Join-AdminUnc $destnetbios $d.physical
				$destinationfiles.add($logical, $d)
				
				# Source File Structure
				$s = @{ }
				$pre = "sysft_"
				$name = $ftc.name
				$physical = $ftc.RootPath
				$logical = "$pre$name"
				
				$s.logical = $logical
				$s.physical = $physical
				$s.remotefilename = Join-AdminUnc $sourcenetbios $s.physical
				$sourcefiles.add($logical, $s)
			}
		}
		
		# Log Files
		foreach ($file in $db.logfiles)
		{
			$d = @{ }
			if ($ReuseSourceFolderStructure)
			{
				$d.physical = $file.filename
			}
			else
			{
				$directory = Get-SqlDefaultPaths $destserver log
				$filename = Split-Path $($file.filename) -leaf
				$d.physical = "$directory\$filename"
			}
			$d.logical = $file.name
			$d.remotefilename = Join-AdminUnc $destnetbios $d.physical
			$destinationfiles.add($file.name, $d)
			
			$s = @{ }
			$s.logical = $file.name
			$s.physical = $file.filename
			$s.remotefilename = Join-AdminUnc $sourcenetbios $s.physical
			$sourcefiles.add($file.name, $s)
		}
		
		$location = @{ }
		$location.add("Destination", $destinationfiles)
		$location.add("Source", $sourcefiles)
		$dbcollection.Add($($db.name), $location)
	}
	
	$filestructure = [pscustomobject]@{ "databases" = $dbcollection }
	return $filestructure
}

Function Get-SqlDefaultPaths
{
<#
.SYNOPSIS
Internal function. Returns the default data and log paths for SQL Server. Needed because SMO's server.defaultpath is sometimes null.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$filetype,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	
	switch ($filetype) { "mdf" { $filetype = "data" } "ldf" { $filetype = "log" } }
	
	if ($filetype -eq "log")
	{
		# First attempt
		$filepath = $server.DefaultLog
		# Second attempt
		if ($filepath.Length -eq 0) { $filepath = $server.Information.MasterDbLogPath }
		# Third attempt
		if ($filepath.Length -eq 0)
		{
			$sql = "select SERVERPROPERTY('InstanceDefaultLogPath') as physical_name"
			$filepath = $server.ConnectionContext.ExecuteScalar($sql)
		}
	}
	else
	{
		# First attempt
		$filepath = $server.DefaultFile
		# Second attempt
		if ($filepath.Length -eq 0) { $filepath = $server.Information.MasterDbPath }
		# Third attempt
		if ($filepath.Length -eq 0)
		{
			$sql = "select SERVERPROPERTY('InstanceDefaultDataPath') as physical_name"
			$filepath = $server.ConnectionContext.ExecuteScalar($sql)
		}
	}
	
	if ($filepath.Length -eq 0) { throw "Cannot determine the required directory path" }
	$filepath = $filepath.TrimEnd("\")
	return $filepath
}


Function Get-SqlSaLogin
{
<#
.SYNOPSIS
Internal function. Gets the name of the sa login in case someone changed it.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	$sa = $server.Logins | Where-Object { $_.id -eq 1 }
	
	return $sa.name
	
}

Function Join-AdminUnc
{
<#
.SYNOPSIS
Internal function. Parses a path to make it an admin UNC.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$servername,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$filepath
		
	)
	
	if (!$filepath) { return }
	if ($filepath.StartsWith("\\")) { return $filepath }
	
	$servername = $servername.Split("\")[0]
	
	if ($filepath.length -gt 0 -and $filepath -ne [System.DbNull]::Value)
	{
		$newpath = Join-Path "\\$servername\" $filepath.replace(':', '$')
		return $newpath
	}
	else { return }
}

Function Test-SqlLoginAccess
{
<#
.SYNOPSIS
Internal function. Ensures login has access on SQL Server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[string]$Login
		#[switch]$Detailed - can return if its a login or just has access
	)
	
	if ($SqlServer.GetType() -ne [Microsoft.SqlServer.Management.Smo.Server])
	{
		$SqlServer = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	}
	
	if (($SqlServer.Logins.Name) -notcontains $Login)
	{
		try
		{
			$rows = $SqlServer.ConnectionContext.ExecuteScalar("EXEC xp_logininfo '$Login'")
			
			if (($rows | Measure-Object).Count -eq 0)
			{
				return $false
			}
		}
		catch
		{
			return $false
		}
	}
	
	return $true
}

Function Test-SqlSa
{
<#
.SYNOPSIS
Internal function. Ensures sysadmin account access on SQL Server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	try
	{
		
		if ($SqlServer.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server])
		{
			return ($SqlServer.ConnectionContext.FixedServerRoles -match "SysAdmin")
		}
		
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
		return ($server.ConnectionContext.FixedServerRoles -match "SysAdmin")
	}
	catch { return $false }
}

Function Resolve-NetBiosName
{
 <#
.SYNOPSIS
Internal function. Takes a best guess at the NetBIOS name of a server. 		
 #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	$servernetbios = $server.ComputerNamePhysicalNetBIOS
	
	if ($servernetbios -eq $null)
	{
		$servernetbios = ($server.name).Split("\")[0]
		$servernetbios = $servernetbios.Split(",")[0]
	}
	
	return $($servernetbios.ToLower())
}

Function Resolve-SqlIpAddress
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	$servernetbios = $server.ComputerNamePhysicalNetBIOS
	$ipaddr = (Test-Connection $servernetbios -count 1).Ipv4Address
	return $ipaddr
}


Function Restore-Database
{
<# 
	.SYNOPSIS
	Internal function. Restores .bak file to SQL database. Creates db if it doesn't exist. $filestructure is
	a custom object that contains logical and physical file locations.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$dbname,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$backupfile,
		[string]$filetype = "Database",
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$filestructure,
		[switch]$norecovery = $true,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	$servername = $server.name
	$server.ConnectionContext.StatementTimeout = 0
	$restore = New-Object "Microsoft.SqlServer.Management.Smo.Restore"
	$restore.ReplaceDatabase = $true
	
	foreach ($file in $filestructure.values)
	{
		$movefile = New-Object "Microsoft.SqlServer.Management.Smo.RelocateFile"
		$movefile.LogicalFileName = $file.logical
		$movefile.PhysicalFileName = $file.physical
		$null = $restore.RelocateFiles.Add($movefile)
	}
	
	try
	{
		
		$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
			Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
		}
		$restore.add_PercentComplete($percent)
		$restore.PercentCompleteNotification = 1
		$restore.add_Complete($complete)
		$restore.ReplaceDatabase = $true
		$restore.Database = $dbname
		$restore.Action = $filetype
		$restore.NoRecovery = $norecovery
		$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
		$device.name = $backupfile
		$device.devicetype = "File"
		$restore.Devices.Add($device)
		
		Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
		$restore.sqlrestore($server)
		Write-Progress -id 1 -activity "Restoring $dbname to $servername" -status "Complete" -Completed
		
		return $true
	}
	catch
	{
		Write-Error "Restore failed: $($_.Exception)"
		return $false
	}
}

Function Test-SqlAgent
{
<#
.SYNOPSIS
Internal function. Checks to see if SQL Server Agent is running on a server.  
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	if ($SqlServer.GetType() -ne [Microsoft.SqlServer.Management.Smo.Server])
	{
		$SqlServer = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	}
	
	if ($SqlServer.JobServer -eq $null) { return $false }
	try { $null = $SqlServer.JobServer.script(); return $true }
	catch { return $false }
}

Function Update-SqlDbOwner
{
<#
.SYNOPSIS
Internal function. Updates specified database dbowner.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$source,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$destination,
		[string]$dbname,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential
	)
	
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
	
	$source = $sourceserver.DomainInstanceName
	$destination = $destserver.DomainInstanceName
	
	if ($dbname.length -eq 0)
	{
		$databases = ($sourceserver.Databases | Where-Object { $destserver.databases.name -contains $_.name -and $_.IsSystemObject -eq $false }).Name
	}
	else { $databases = $dbname }
	
	foreach ($dbname in $databases)
	{
		$destdb = $destserver.databases[$dbname]
		$dbowner = $sourceserver.databases[$dbname].owner
		
		if ($destdb.owner -ne $dbowner)
		{
			if ($destdb.Status -ne 'Normal') { Write-Output "Database status not normal. Skipping dbowner update."; continue }
			
			if ($dbowner -eq $null -or $destserver.logins[$dbowner] -eq $null)
			{
				try
				{
					$dbowner = ($destserver.logins | Where-Object { $_.id -eq 1 }).Name
				}
				catch
				{
					$dbowner = "sa"
				}
			}
			
			try
			{
				if ($destdb.ReadOnly -eq $true)
				{
					$changeroback = $true
					Update-SqlDbReadOnly $destserver $dbname $false
				}
				
				$destdb.SetOwner($dbowner)
				Write-Output "Changed $dbname owner to $dbowner"
				
				if ($changeroback)
				{
					Update-SqlDbReadOnly $destserver $dbname $true
					$changeroback = $null
				}
			}
			catch
			{
				Write-Error "Failed to update $dbname owner to $dbowner."
			}
		}
		else { Write-Output "Proper owner already set on $dbname" }
	}
}

Function Update-SqlDbReadOnly
{
<#
.SYNOPSIS
Internal function. Updates specified database to read-only or read-write. Necessary because SMO doesn't appear to support NO_WAIT.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$dbname,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[bool]$readonly
	)
	
	if ($readonly)
	{
		$sql = "ALTER DATABASE [$dbname] SET READ_ONLY WITH NO_WAIT"
	}
	else
	{
		$sql = "ALTER DATABASE [$dbname] SET READ_WRITE WITH NO_WAIT"
	}
	
	try
	{
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
		$null = $server.ConnectionContext.ExecuteNonQuery($sql)
		Write-Output "Changed ReadOnly status to $readonly for $dbname on $($server.name)"
		return $true
	}
	catch
	{
		Write-Error "Could not change readonly status for $dbname on $($server.name)"
		return $false
	}
}

Function Remove-SqlDatabase
{
<#
.SYNOPSIS
Internal function. Uses SMO's KillDatabase to drop all user connections then drop a database. $server is
an SMO server object.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[Parameter(Mandatory = $true)]
		[string]$DBName,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	try
	{
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
		$server.KillDatabase($dbname)
		$server.refresh()
		Write-Output "Successfully dropped $dbname on $($server.name)"
	}
	catch
	{
		try
		{
			$server.databases[$dbname].Drop()
			Write-Output "Successfully dropped $dbname on $($server.name)"
		}
		catch
		{
			try
			{
				$null = $server.ConnectionContext.ExecuteNonQuery("DROP DATABASE $dbname")
				Write-Output "Successfully dropped $dbname on $($server.name)"
			}
			catch { return $false }
		}
	}
}


Function Get-SaLoginName
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	
	$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	$saname = ($server.logins | Where-Object { $_.id -eq 1 }).Name
	
	return $saname
}

Function Write-Exception
{
<#
.SYNOPSIS
Internal function. Writes exception to disk (my docs\dbatools-exceptions.txt) for later analysis.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$e
	)
	
	$docs = [Environment]::GetFolderPath("mydocuments")
	$errorlog = "$docs\dbatools-exceptions.txt"
	$message = $e.Exception
	
	if ($e.Exception.InnerException -ne $null) { $messsage = $e.Exception.InnerException }
	
	$message = $message.ToString()
	Add-Content $errorlog $(Get-Date)
	Add-Content $errorlog $message
	Write-Warning "See error log $(Resolve-Path $errorlog) for more details."
}

Function Update-SqlPermissions
{
 <#
 
.SYNOPSIS
 Internal function. Updates permission sets, roles, database mappings on server and databases

 #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$sourceserver,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$sourcelogin,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$destserver,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$destlogin
	)
	
	$destination = $destserver.DomainInstanceName
	$source = $sourceserver.DomainInstanceName
	$username = $sourcelogin.name
	
	# Server Roles: sysadmin, bulklogin, etc
	foreach ($role in $sourceserver.roles)
	{
		$rolename = $role.name
		$destrole = $destserver.roles[$rolename]
		if ($destrole -ne $null)
		{
			try { $destrolemembers = $destrole.EnumMemberNames() }
			catch { $destrolemembers = $destrole.EnumServerRoleMembers() }
		}
		try { $rolemembers = $role.EnumMemberNames() }
		catch { $rolemembers = $role.EnumServerRoleMembers() }
		if ($rolemembers -contains $username)
		{
			if ($destrole -ne $null)
			{
				If ($Pscmdlet.ShouldProcess($destination, "Adding $username to $rolename server role"))
				{
					try
					{
						$destrole.AddMember($username)
						Write-Output "Added $username to $rolename server role."
					}
					catch
					{
						Write-Warning "Failed to add $username to $rolename server role."
						Write-Exception $_
					}
				}
			}
		}
		
		# Remove for Syncs
		if ($rolemembers -notcontains $username -and $destrolemembers -contains $username -and $destrole -ne $null)
		{
			If ($Pscmdlet.ShouldProcess($destination, "Adding $username to $rolename server role"))
			{
				try
				{
					$destrole.DropMember($username)
					Write-Output "Removed $username from $destrolename server role on $($destserver.name)."
				}
				catch
				{
					Write-Warning "Failed to remove $username from $destrolename server role on $($destserver.name)."
					Write-Exception $_
				}
			}
		}
	}
	
	$ownedjobs = $sourceserver.JobServer.Jobs | Where-Object { $_.OwnerLoginName -eq $username }
	foreach ($ownedjob in $ownedjobs)
	{
		if ($destserver.JobServer.Jobs[$ownedjob.name] -ne $null)
		{
			If ($Pscmdlet.ShouldProcess($destination, "Changing job owner to $username for $($ownedjob.name)"))
			{
				try
				{
					Write-Output "Changing job owner to $username for $($ownedjob.name)"
					$destownedjob = $destserver.JobServer.Jobs | Where-Object { $_.name -eq $ownedjobs.name }
					$destownedjob.set_OwnerLoginName($username)
					$destownedjob.Alter()
				}
				catch
				{
					Write-Warning "Could not change job owner for $($ownedjob.name)"
					Write-Exception $_
				}
			}
		}
	}
	
	if ($sourceserver.versionMajor -ge 9 -and $destserver.versionMajor -ge 9)
	{
		# These operations are only supported by SQL Server 2005 and above.
		# Securables: Connect SQL, View any database, Administer Bulk Operations, etc.
		
		$perms = $sourceserver.EnumServerPermissions($username)
		foreach ($perm in $perms)
		{
			$permstate = $perm.permissionstate
			if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" }
			else { $grantwithgrant = $false }
			$permset = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.permissiontype)
			If ($Pscmdlet.ShouldProcess($destination, "Performing $permstate on $($perm.permissiontype) for $username"))
			{
				try
				{
					$destserver.PSObject.Methods[$permstate].Invoke($permset, $username, $grantwithgrant)
					Write-Output "Successfully performed $permstate $($perm.permissiontype) to $username"
				}
				catch
				{
					Write-Warning "Failed to $permstate $($perm.permissiontype) to $username"
					Write-Exception $_
				}
			}
			
			# for Syncs
			$destperms = $destserver.EnumServerPermissions($username)
			foreach ($perm in $destperms)
			{
				$permstate = $perm.permissionstate
				$sourceperm = $perms | Where-Object { $_.PermissionType -eq $perm.Permissiontype -and $_.PermissionState -eq $permstate }
				if ($sourceperm -eq $null)
				{
					If ($Pscmdlet.ShouldProcess($destination, "Performing Revoke on $($perm.permissiontype) for $username"))
					{
						try
						{
							$permset = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.permissiontype)
							if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" }
							else { $grantwithgrant = $false }
							$destserver.PSObject.Methods["Revoke"].Invoke($permset, $username, $false, $grantwithgrant)
							Write-Output "Successfully revoked $($perm.permissiontype) from $username"
						}
						catch
						{
							Write-Warning "Failed to revoke $($perm.permissiontype) from $username"
							Write-Exception $_
						}
					}
				}
			}
		}
		
		# Credential mapping. Credential removal not currently supported for Syncs.
		$logincredentials = $sourceserver.credentials | Where-Object { $_.Identity -eq $sourcelogin.name }
		foreach ($credential in $logincredentials)
		{
			if ($destserver.Credentials[$credential.name] -eq $null)
			{
				If ($Pscmdlet.ShouldProcess($destination, "Adding $($credential.name) to $username"))
				{
					try
					{
						$newcred = New-Object Microsoft.SqlServer.Management.Smo.Credential($destserver, $credential.name)
						$newcred.identity = $sourcelogin.name
						$newcred.Create()
						Write-Output "Successfully created credential for $username"
					}
					catch
					{
						Write-Warning "Failed to create credential for $username"
						Write-Exception $_
					}
				}
			}
		}
	}
	
	if ($destserver.versionMajor -lt 9) { Write-Warning "Database mappings skipped when destination is SQL Server 2000"; continue }
	
	# For Sync, if info doesn't exist in EnumDatabaseMappings, then no big deal.
	foreach ($db in $destlogin.EnumDatabaseMappings())
	{
		$dbname = $db.dbname
		$destdb = $destserver.databases[$dbname]
		$sourcedb = $sourceserver.databases[$dbname]
		$dbusername = $db.username; $dblogin = $db.loginName
		
		if ($sourcedb -ne $null)
		{
			if ($sourcedb.users[$dbusername] -eq $null -and $destdb.users[$dbusername] -ne $null)
			{
				If ($Pscmdlet.ShouldProcess($destination, "Dropping $dbusername from $dbname on destination."))
				{
					try
					{
						$destdb.users[$dbusername].Drop()
						Write-Output "Dropped user $dbusername (login: $dblogin) from $dbname on destination. User may own a schema."
					}
					catch
					{
						Write-Warning "Failed to drop $dbusername ($dblogin) from $dbname on destination."
						Write-Exception $_
					}
				}
			}
			
			# Remove user from role. Role removal not currently supported for Syncs.
			# TODO: reassign if dbo, application roles
			foreach ($destrole in $destdb.roles)
			{
				$destrolename = $destrole.name
				$sourcerole = $sourcedb.roles[$destrolename]
				if ($sourcerole -ne $null)
				{
					if ($sourcerole.EnumMembers() -notcontains $dbusername -and $destrole.EnumMembers() -contains $dbusername)
					{
						if ($dbusername -ne "dbo")
						{
							If ($Pscmdlet.ShouldProcess($destination, "Dropping $username from $destrolename database role on $dbname"))
							{
								try
								{
									$destrole.DropMember($dbusername)
									$destdb.Alter()
									Write-Output "Dropped username $dbusername (login: $dblogin) from $destrolename on $destination"
								}
								catch
								{
									Write-Warning "Failed to remove $dbusername from $destrolename database role on $dbname."
									Write-Exception $_
								}
							}
						}
					}
				}
			}
			
			# Remove Connect, Alter Any Assembly, etc
			$destperms = $destdb.EnumDatabasePermissions($username)
			$perms = $sourcedb.EnumDatabasePermissions($username)
			# for Syncs
			foreach ($perm in $destperms)
			{
				$permstate = $perm.permissionstate
				$sourceperm = $perms | Where-Object { $_.PermissionType -eq $perm.Permissiontype -and $_.PermissionState -eq $permstate }
				if ($sourceperm -eq $null)
				{
					If ($Pscmdlet.ShouldProcess($destination, "Performing Revoke on $($perm.permissiontype) for $username on $dbname on $destination"))
					{
						try
						{
							$permset = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.permissiontype)
							if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" }
							else { $grantwithgrant = $false }
							$destdb.PSObject.Methods["Revoke"].Invoke($permset, $username, $false, $grantwithgrant)
							Write-Output "Successfully revoked $($perm.permissiontype) from $username on $dbname on $destination"
						}
						catch
						{
							Write-Warning "Failed to revoke $($perm.permissiontype) from $username on $dbname on $destination"
							Write-Exception $_
						}
					}
				}
			}
		}
	}
	
	# Adding database mappings and securables
	foreach ($db in $sourcelogin.EnumDatabaseMappings())
	{
		$dbname = $db.dbname
		$destdb = $destserver.databases[$dbname]
		$sourcedb = $sourceserver.databases[$dbname]
		$dbusername = $db.username; $dblogin = $db.loginName
		
		if ($destdb -ne $null)
		{
			if ($destdb.users[$dbusername] -eq $null)
			{
				If ($Pscmdlet.ShouldProcess($destination, "Adding $dbusername to $dbname"))
				{
					$sql = $sourceserver.databases[$dbname].users[$dbusername].script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					try
					{
						$destdb.ExecuteNonQuery($sql)
						Write-Output "Added user $dbusername (login: $dblogin) to $dbname"
					}
					catch
					{
						Write-Warning "Failed to add $dbusername ($dblogin) to $dbname on $destination."
						Write-Exception $_
					}
				}
			}
			
			# Db owner
			If ($sourcedb.owner -eq $username)
			{
				If ($Pscmdlet.ShouldProcess($destination, "Changing $dbname dbowner to $username"))
				{
					try
					{
						$result = Update-SqlDbOwner $sourceserver $destserver -dbname $dbname
						if ($result -eq $true)
						{
							Write-Output "Changed $($destdb.name) owner to $($sourcedb.owner)."
						}
						else { Write-Warning "Failed to update $($destdb.name) owner to $($sourcedb.owner)." }
					}
					catch { Write-Warning "Failed to update $($destdb.name) owner to $($sourcedb.owner)." }
				}
			}
			
			# Database Roles: db_owner, db_datareader, etc
			foreach ($role in $sourcedb.roles)
			{
				if ($role.EnumMembers() -contains $username)
				{
					$rolename = $role.name
					$destdbrole = $destdb.roles[$rolename]
					
					if ($destdbrole -ne $null -and $dbusername -ne "dbo" -and $destdbrole.EnumMembers() -notcontains $username)
					{
						If ($Pscmdlet.ShouldProcess($destination, "Adding $username to $rolename database role on $dbname"))
						{
							try
							{
								$destdbrole.AddMember($username)
								$destdb.Alter()
								Write-Output "Added $username to $rolename database role on $dbname."
								
							}
							catch
							{
								Write-Warning "Failed to add $username to $rolename database role on $dbname."
								Write-Exception $_
							}
						}
					}
				}
			}
			
			# Connect, Alter Any Assembly, etc
			$perms = $sourcedb.EnumDatabasePermissions($username)
			foreach ($perm in $perms)
			{
				$permstate = $perm.permissionstate
				if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" }
				else { $grantwithgrant = $false }
				$permset = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.permissiontype)
				If ($Pscmdlet.ShouldProcess($destination, "Performing $permstate on $($perm.permissiontype) for $username on $dbname"))
				{
					try
					{
						$destdb.PSObject.Methods[$permstate].Invoke($permset, $username, $grantwithgrant)
						Write-Output "Successfully performed $permstate $($perm.permissiontype) to $username on $dbname"
					}
					catch
					{
						Write-Warning "Failed to perform $permstate on $($perm.permissiontype) for $username on $dbname."
						Write-Exception $_
					}
				}
			}
		}
	}
}