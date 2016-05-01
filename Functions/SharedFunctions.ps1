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
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	$username = $SqlCredential.username
	if ($username -ne $null)
	{
		$username = $username.TrimStart("\")
		if ($username -like "*\*") { throw "Only SQL Logins can be specified when using the Credential parameter. To connect as to SQL Server a different Windows user, you must start PowerShell as that user." }
	}
	
	# Get local enviornment
	Write-Output "Getting local enivornment information"
	$localinfo = @{ } | Select Windows, PowerShell, CLR, SMO, DomainUser, RunAsAdmin
	$localinfo.Windows = [environment]::OSVersion.Version.ToString()
	$localinfo.PowerShell = $PSVersionTable.PSversion.ToString()
	$localinfo.CLR = $PSVersionTable.CLRVersion.ToString()
	$smo = (([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Fullname -like "Microsoft.SqlServer.SMO,*" }).FullName -Split ", ")[1]
	$localinfo.SMO = $smo.TrimStart("Version=")
	$localinfo.DomainUser = $env:computername -ne $env:USERDOMAIN
	$localinfo.RunAsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
	
	# SQL Server
	if ($SqlServer.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server]) { $SqlServer = $SqlServer.Name.ToString() }
	
	$serverinfo = @{ } | Select ServerName, BaseName, InstanceName, AuthType, ConnectingAsUser, ConnectSuccess, SqlServerVersion, AddlConnectInfo, RemoteServer, IPAddress, NetBIOSname, RemotingAccessible, Pingable, DefaultSQLPortOpen, RemotingPortOpen
	
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
		$ipaddr = ($hostentry.AddressList | Where-Object { $_ -notlike '169.*' } | Select -First 1).IPAddressToString
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
			$authtype = "SQL Authentication"
			$username = ($SqlCredential.username).TrimStart("\")
			$server.ConnectionContext.LoginSecure = $false
			$server.ConnectionContext.set_Login($username)
			$server.ConnectionContext.set_SecurePassword($SqlCredential.Password)
		}
		else
		{
			$authtype = "Windows Authentication (Trusted)"
			$username = "$env:USERDOMAIN\$env:username"
		}
	}
	catch
	{
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
	$localinfo | Select Windows, PowerShell, CLR, SMO, DomainUser, RunAsAdmin
	
	Write-Output "SQL Server Connection Information`n"
	$serverinfo | Select ServerName, BaseName, InstanceName, AuthType, ConnectingAsUser, ConnectSuccess, SqlServerVersion, AddlConnectInfo, RemoteServer, IPAddress, NetBIOSname, RemotingAccessible, Pingable, DefaultSQLPortOpen, RemotingPortOpen
	
}

<#
				
		All functions below are internal to the module and cannot be executed via command line.
				
#>

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
		[switch]$ParameterConnection
	)
	
	$username = $SqlCredential.username
	if ($username -ne $null)
	{
		$username = $username.TrimStart("\")
		if ($username -like "*\*") { throw "Only SQL Logins can be specified when using the Credential parameter. To connect as to SQL Server a different Windows user, you must start PowerShell as that user." }
	}
	
	if ($SqlServer.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server])
	{
		
		if ($ParameterConnection)
		{
			$paramserver = New-Object Microsoft.SqlServer.Management.Smo.Server
			$paramserver.ConnectionContext.ConnectTimeout = 2
			$paramserver.ConnectionContext.ConnectionString = $SqlServer.ConnectionContext.ConnectionString
			$paramserver.ConnectionContext.Connect()
			return $paramserver
		}
		
		if ($SqlServer.ConnectionContext.IsOpen -eq $false) { $SqlServer.ConnectionContext.Connect() }
		return $SqlServer
	}
	
	$server = New-Object Microsoft.SqlServer.Management.Smo.Server $SqlServer
	
	try
	{
		if ($SqlCredential.username -ne $null)
		{
			$server.ConnectionContext.LoginSecure = $false
			$server.ConnectionContext.set_Login($username)
			$server.ConnectionContext.set_SecurePassword($SqlCredential.Password)
		}
	}
	catch { }
	
	try
	{
		if ($ParameterConnection) { $server.ConnectionContext.ConnectTimeout = 2 }
		else { $server.ConnectionContext.ConnectTimeout = 3 }
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
	
	return $server
}

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
		Write-Output "Performing SMO version check"
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

Function Get-ParamSqlCmsGroups
{
<# 
.SYNOPSIS 
Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary 
filled with server groups from specified SQL Server Central Management server name.

#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
		
	)
	
	if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.RegisteredServers") -eq $null) { return }
	
	try { $SqlCms = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }
	
	$sqlconnection = $SqlCms.ConnectionContext.SqlConnectionObject
	
	try { $cmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sqlconnection) }
	catch { return }
	
	if ($cmstore -eq $null) { return }
	
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$paramattributes = New-Object System.Management.Automation.ParameterAttribute
	$paramattributes.ParameterSetName = "__AllParameterSets"
	$paramattributes.Mandatory = $false
	
	$argumentlist = $cmstore.DatabaseEngineServerGroup.ServerGroups.name
	
	if ($argumentlist -ne $null)
	{
		$validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $argumentlist
		
		$combinedattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
		$combinedattributes.Add($paramattributes)
		$combinedattributes.Add($validationset)
		
		$SqlCmsGroups = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("SqlCmsGroups", [String[]], $combinedattributes)
		$newparams.Add("SqlCmsGroups", $SqlCmsGroups)
		
		return $newparams
	}
	else { return }
}

Function Get-ParamSqlLinkedServers
{
<# 
.SYNOPSIS 
Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary 
filled with Linked Servers from specified SQL Server Central Management server name.
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }
	
	# Populate arrays
	$linkedserverlist = @()
	foreach ($linkedserver in $server.LinkedServers)
	{
		$linkedserverlist += $linkedserver.name
	}
	
	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute
	
	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	
	# Database list parameter setup
	if ($linkedserverlist) { $dbvalidationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $linkedserverlist }
	$lsattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$lsattributes.Add($attributes)
	if ($linkedserverlist) { $lsattributes.Add($dbvalidationset) }
	$LinkedServers = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("LinkedServers", [String[]], $lsattributes)
	
	$newparams.Add("LinkedServers", $LinkedServers)
	$server.ConnectionContext.Disconnect()
	
	return $newparams
}

Function Get-ParamSqlCredentials
{
<# 
.SYNOPSIS 
Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary 
filled with SQL Credentials from specified SQL Server server name.
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }
	
	# Populate arrays
	$credentiallist = @()
	foreach ($credential in $server.credentials)
	{
		$credentiallist += $credential.name
	}
	
	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute
	
	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	
	# Database list parameter setup
	if ($credentiallist) { $dbvalidationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $credentiallist }
	$lsattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$lsattributes.Add($attributes)
	if ($credentiallist) { $lsattributes.Add($dbvalidationset) }
	$Credentials = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Credentials", [String[]], $lsattributes)
	
	$newparams.Add("Credentials", $Credentials)
	$server.ConnectionContext.Disconnect()
	
	return $newparams
}

Function Get-ParamSqlDatabases
{
<# 
.SYNOPSIS 
Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary 
filled with database list from specified SQL Server server.
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }
	
	$SupportDbs = "ReportServer", "ReportServerTempDb", "distribution"
	
	# Populate arrays
	$databaselist = @()
	foreach ($database in $server.databases)
	{
		if ((!$database.IsSystemObject) -and $SupportDbs -notcontains $database.name)
		{
			$databaselist += $database.name
		}
	}
	
	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute
	
	# Provide backwards compatability for improperly named parameter
	$alias = New-Object System.Management.Automation.AliasAttribute "Databases"
	
	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	
	# Database list parameter setup
	if ($databaselist) { $dbvalidationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $databaselist }
	$dbattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$dbattributes.Add($attributes)
	if ($databaselist) { $dbattributes.Add($dbvalidationset) }
	$dbattributes.Add($alias)
	$Database = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Database", [String[]], $dbattributes)
	
	$dbexcludeattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$dbexcludeattributes.Add($attributes)
	if ($databaselist) { $dbexcludeattributes.Add($dbvalidationset) }
	$Exclude = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Exclude", [String[]], $dbexcludeattributes)
	
	$newparams.Add("Database", $Database)
	$newparams.Add("Exclude", $Exclude)
	
	$server.ConnectionContext.Disconnect()
	
	return $newparams
}

Function Get-ParamSqlLogins
{
<# 
 .SYNOPSIS 
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary 
 filled with login list from specified SQL Server server.
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }
	$loginlist = @()
	
	foreach ($login in $server.logins)
	{
		if (!$login.name.StartsWith("##") -and $login.name -ne 'sa')
		{
			$loginlist += $login.name
		}
	}
	
	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute
	
	# Provide backwards compatability for improperly named parameter
	$alias = New-Object System.Management.Automation.AliasAttribute "Logins"
	
	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	
	# Login list parameter setup
	if ($loginlist) { $loginvalidationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $loginlist }
	
	$loginattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$loginattributes.Add($attributes)
	if ($loginlist) { $loginattributes.Add($loginvalidationset) }
	
	$loginattributes.Add($alias)
	$Login = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Login", [String[]], $loginattributes)
	
	$excludeattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$excludeattributes.Add($attributes)
	if ($loginlist) { $excludeattributes.Add($loginvalidationset) }
	$Exclude = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Exclude", [String[]], $excludeattributes)
	
	$newparams.Add("Login", $Login)
	$newparams.Add("Exclude", $Exclude)
	
	$server.ConnectionContext.Disconnect()
	
	return $newparams
}

Function Get-ParamSqlJobServer
{
<# 
 .SYNOPSIS 
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary 
 filled with job server objects from specified SQL Server server.
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }
	
	$jobobjects = "ProxyAccounts", "JobSchedule", "SharedSchedules", "AlertSystem", "JobCategories", "OperatorCategories"
	$jobobjects += "AlertCategories", "Alerts", "TargetServerGroups", "TargetServers", "Operators", "Jobs", "Mail"
	
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	
	foreach ($name in $jobobjects)
	{
		$items = $server.JobServer.$name.Name
		if ($items.count -gt 0)
		{
			$attributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
			$attributes.Add((New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $items))
		}
		
		$newparams.Add($name, (New-Object -Type System.Management.Automation.RuntimeDefinedParameter($name, [String[]], $attributes)))
	}
	$server.ConnectionContext.Disconnect()
	
	return $newparams
}

Function Get-ParamSqlDatabaseMail
{
<# 
 .SYNOPSIS 
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary 
 filled with Database Mail server objects from specified SQL Server server.
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }
	
	$objects = "ConfigurationValues", "Profiles", "Accounts", "MailServers"
	
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	
	foreach ($name in $objects)
	{
		if ($name -eq "MailServers") { $items = $server.Mail.Accounts.$name.Name }
		else { $items = $server.Mail.$name.Name }
		if ($items.count -gt 0)
		{
			$attributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
			$attributes.Add((New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $items))
		}
		
		$newparams.Add($name, (New-Object -Type System.Management.Automation.RuntimeDefinedParameter($name, [String[]], $attributes)))
	}
	$server.ConnectionContext.Disconnect()
	
	return $newparams
}

Function Get-ParamSqlServerTriggers
{
<# 
 .SYNOPSIS 
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary 
 filled with Server Triggers from specified SQL Server.
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }
	
	# Populate arrays
	$triggerlist = @()
	foreach ($trigger in $server.Triggers)
	{
		$triggerlist += $trigger.name
	}
	
	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute
	
	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	
	# Database list parameter setup
	if ($triggerlist) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $triggerlist }
	$objattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$objattributes.Add($attributes)
	if ($triggerlist) { $objattributes.Add($validationset) }
	$Triggers = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Triggers", [String[]], $objattributes)
	
	$newparams.Add("Triggers", $Triggers)
	$server.ConnectionContext.Disconnect()
	
	return $newparams
}

Function Get-ParamSqlBackupDevices
{
<# 
 .SYNOPSIS 
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary 
 filled with Backup Devices from specified SQL Server.
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }
	
	# Populate arrays
	$backupdevicelist = @()
	foreach ($backupdevice in $server.BackupDevices)
	{
		$backupdevicelist += $backupdevice.name
	}
	
	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute
	
	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	
	# Database list parameter setup
	if ($backupdevicelist) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $backupdevicelist }
	$objattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$objattributes.Add($attributes)
	if ($backupdevicelist) { $objattributes.Add($validationset) }
	$backupdevices = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("BackupDevices", [String[]], $objattributes)
	
	$newparams.Add("BackupDevices", $backupdevices)
	$server.ConnectionContext.Disconnect()
	
	return $newparams
}

Function Get-SqlCmsRegServers
{
<# 
 .SYNOPSIS 
 Internal function. Returns array of server names from CMS Server. If -Groups is specified,
 only servers within the given groups are returned.
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$SqlServer,
		[string[]]$groups,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.RegisteredServers") -eq $null) { return }
	
	$SqlCms = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	$sqlconnection = $SqlCms.ConnectionContext.SqlConnectionObject
	
	try { $cmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sqlconnection) }
	catch { throw "Cannot access Central Management Server" }
	
	$servers = @()
	if ($groups -ne $null)
	{
		foreach ($group in $groups)
		{
			$cms = $cmstore.ServerGroups["DatabaseEngineServerGroup"].ServerGroups[$group]
			$servers += ($cms.GetDescendantRegisteredServers()).servername
		}
	}
	else
	{
		$cms = $cmstore.ServerGroups["DatabaseEngineServerGroup"]
		$servers = ($cms.GetDescendantRegisteredServers()).servername
	}
	
	return $servers
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
		[bool]$ReuseFolderstructure,
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
		if ($ReuseFolderstructure -eq $true)
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
		if ($ReuseFolderstructure)
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
Internal function. Returns custom object that contains file structures and remote paths (\\sqlserver\m$\mssql\etc\etc\file.mdf) for
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
		[bool]$ReuseFolderstructure,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential
	)
	
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$source = $sourceserver.name
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
	$destination = $destserver.name
	
	$sourcenetbios = Get-NetBiosName $sourceserver
	$destnetbios = Get-NetBiosName $destserver
	
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
				if ($ReuseFolderstructure)
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
				if ($ReuseFolderstructure)
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
			if ($ReuseFolderstructure)
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
	
	if ($filepath.length -gt 0 -and $filepath -ne [System.DbNull]::Value)
	{
		$newpath = Join-Path "\\$servername\" $filepath.replace(':', '$')
		return $newpath
	}
	else { return }
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

Function Get-NetBiosName
{
 <#
.SYNOPSIS
Internal function. Takes a best guess at the NetBIOS name of a server. 		
 #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
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
	
	$source = $sourceserver.name
	$destination = $destserver.name
	
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
			if ($dbowner -eq $null -or $destserver.logins[$dbowner] -eq $null) { $dbowner = 'sa' }
			
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
		[ValidateNotNullOrEmpty()]
		[object]$SqlServer,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
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

Function Write-Exception
{
<#
.SYNOPSIS
Internal function. Writes exception to disk (.\dbatools-exceptions.txt) for later analysis.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$e
	)
	
	$errorlog = ".\dbatools-exceptions.txt"
	$message = $e.Exception
	
	if ($e.Exception.InnerException -ne $null) { $messsage = $e.Exception.InnerException }
	
	$message = $message.ToString()
	Add-Content $errorlog $(Get-Date)
	Add-Content $errorlog $message
	Write-Warning "See error log $(Resolve-Path $errorlog) for more details."
}