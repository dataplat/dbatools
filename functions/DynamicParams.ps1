<#

	These are all the functions for tab completion (auto-population of params)
	To use, place this after params in a function

	DynamicParam { if ($source) { return (Get-ParamSqlXyz -SqlServer $Source -SqlCredential $SourceSqlCredential) } }

#>
Function Get-ParamSqlServerConfigs
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with Server Configs from specified SQL Server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$configlist = @()
	$server.Configuration.ShowAdvancedOptions.ConfigValue = $true
	$null = $server.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE")
	$configlist = $server.Configuration.PsObject.Properties.Name | Where-Object { $_ -notin "Parent", "Properties" }
	$server.Configuration.ShowAdvancedOptions.ConfigValue = $false
	$null = $server.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE")

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($configlist) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $configlist }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($configlist) { $attributeCollection.Add($validationset) }
	$Configs = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Configs", [String[]], $attributeCollection)

	$newparams.Add("Configs", $Configs)
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
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	$SupportDbs = "ReportServer", "ReportServerTempDb", "distribution"

	# Populate arrays
	$databaselist = @()

	if ($server.Databases.Count -gt 255)
	{
		# Don't slow them down by building a list that likely won't be used anyway
		$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
		$attributes = New-Object System.Management.Automation.ParameterAttribute
		$attributes.ParameterSetName = "__AllParameterSets"
		$attributes.Mandatory = $false
		$Databases = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Databases", [String[]], $attributes)
		$newparams.Add("Databases", $Databases)
		$Exclude = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Exclude", [String[]], $attributes)
		$newparams.Add("Exclude", $Exclude)
		return $newparams
	}

	foreach ($database in $server.databases)
	{
		if ((!$database.IsSystemObject) -and $SupportDbs -notcontains $database.name)
		{
			$databaselist += $database.name
		}
	}

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

	# Provide backwards compatability for improperly named parameter
	# Scratch that. I'm going with plural. Sorry, Snoves!
	$alias = New-Object System.Management.Automation.AliasAttribute "Database"

	$attributes = New-Object System.Management.Automation.ParameterAttribute
	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($databaselist) { $dbvalidationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $databaselist }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($databaselist) { $attributeCollection.Add($dbvalidationset) }
	$attributeCollection.Add($alias)
	$Databases = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Databases", [String[]], $attributeCollection)


	$eattributes = New-Object System.Management.Automation.ParameterAttribute
	$eattributes.ParameterSetName = "__AllParameterSets"
	$eattributes.Mandatory = $false
	$eattributes.Position = 20
	$dbexcludeattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$dbexcludeattributes.Add($eattributes)
	if ($databaselist) { $dbexcludeattributes.Add($dbvalidationset) }
	$Exclude = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Exclude", [String[]], $dbexcludeattributes)

	$newparams.Add("Databases", $Databases)
	$newparams.Add("Exclude", $Exclude)

	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlDatabase
{
<#
.SYNOPSIS
Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
filled with database list from specified SQL Server server.

#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$databaselist = @()

	if ($server.Databases.Count -gt 255)
	{
		# Don't slow them down by building a list that likely won't be used anyway
		$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
		$attributes = New-Object System.Management.Automation.ParameterAttribute
		$attributes.ParameterSetName = "__AllParameterSets"
		$attributes.Mandatory = $false
		$Database = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Database", [String], $attributes)
		$newparams.Add("Database", $Database)
		return $newparams
	}

	$databaselist = $server.databases.name

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute
	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($databaselist) { $dbvalidationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $databaselist }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($databaselist) { $attributeCollection.Add($dbvalidationset) }
	$attributeCollection.Add($alias)
	$Database = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Database", [String], $attributeCollection)

	$newparams.Add("Database", $Database)
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
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }


	if ($server.logins.count -gt 255)
	{
		# Don't slow them down by building a list that likely won't be used anyway
		$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
		$attributes = New-Object System.Management.Automation.ParameterAttribute
		$attributes.ParameterSetName = "__AllParameterSets"
		$attributes.Mandatory = $false
		$Logins = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Logins", [String[]], $attributes)
		$newparams.Add("Logins", $Logins)
		$Exclude = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Exclude", [String[]], $attributes)
		$newparams.Add("Exclude", $Exclude)
		return $newparams
	}

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
	# Scratch that. I'm going with plural. Sorry, Snoves!
	$alias = New-Object System.Management.Automation.AliasAttribute "Login"

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Login list parameter setup
	if ($loginlist) { $loginvalidationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $loginlist }

	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($loginlist) { $attributeCollection.Add($loginvalidationset) }

	$attributeCollection.Add($alias)
	$Logins = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Logins", [String[]], $attributeCollection)

	$excludeattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$excludeattributes.Add($attributes)
	if ($loginlist) { $excludeattributes.Add($loginvalidationset) }
	$Exclude = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Exclude", [String[]], $excludeattributes)

	$newparams.Add("Logins", $Logins)
	$newparams.Add("Exclude", $Exclude)

	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlServerRoles
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with Server Roles from specified SQL Server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$rolelist = @()
	$roles = $server.roles | Where-Object { $_.IsFixedRole -eq $false -and $_.Name -ne 'public' }
	foreach ($role in $roles)
	{
		$rolelist += $role.name
	}

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($rolelist) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $rolelist }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($rolelist) { $attributeCollection.Add($validationset) }
	$roles = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Roles", [String[]], $attributeCollection)

	$newparams.Add("Roles", $roles)
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
		[Alias("ServerInstance","SqlInstance")]
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
	$attributes.Position = 3

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

Function Get-ParamSqlServerAudits
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with Server Audits from specified SQL Server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$auditlist = @()
	foreach ($audit in $server.audits)
	{
		$auditlist += $audit.name
	}

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($auditlist) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $auditlist }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($auditlist) { $attributeCollection.Add($validationset) }
	$audits = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Audits", [String[]], $attributeCollection)

	$newparams.Add("Audits", $audits)
	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlServerServerAuditSpecifications
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with Server ServerAuditSpecifications from specified SQL Server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$auditspeclist = @()
	foreach ($auditspec in $server.ServerAuditSpecifications)
	{
		$auditspeclist += $auditspecname
	}

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($auditspeclist) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $auditspeclist }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($auditspeclist) { $attributeCollection.Add($validationset) }
	$serverAuditSpecifications = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("ServerAuditSpecifications", [String[]], $attributeCollection)

	$newparams.Add("ServerAuditSpecifications", $serverAuditSpecifications)
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
		[Alias("ServerInstance","SqlInstance")]
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
	$attributes.Position = 3

	# Database list parameter setup
	if ($backupdevicelist) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $backupdevicelist }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($backupdevicelist) { $attributeCollection.Add($validationset) }
	$backupdevices = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("BackupDevices", [String[]], $attributeCollection)

	$newparams.Add("BackupDevices", $backupdevices)
	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlServerEndpoints
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with Server Endpoints from specified SQL Server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$endpointlist = @()
	$usernedponit = $server.Endpoints | Where-Object { $_.IsSystemObject -eq $false }
	foreach ($endpoint in $server.Endpoints)
	{
		$endpointlist += $endpointname
	}

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($endpointlist) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $endpointlist }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($endpointlist) { $attributeCollection.Add($validationset) }
	$Endpoints = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Endpoints", [String[]], $attributeCollection)

	$newparams.Add("Endpoints", $Endpoints)
	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlLinkedServers
{
<#
.SYNOPSIS
Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
filled with Linked Servers from specified server name.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$linkedserverlist = @()
	foreach ($linkedserver in $server.LinkedServers)
	{
		# skip the replication linked server
		if ($linkedserver.name -ne 'repl_distributor')
		{
			$linkedserverlist += $linkedserver.name
		}
	}

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

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

Function Get-ParamSqlPolicyManagement
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with Sql Policy Management objects from specified SQL Server server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	if ([System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Dmf") -eq $null)
		{
			return
		}

	$sqlconn = $server.ConnectionContext.SqlConnectionObject
	$sqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sqlconn

	# DMF is the Declarative Management Framework, Policy Based Management's old name
	$store = New-Object Microsoft.SqlServer.Management.DMF.PolicyStore $sqlStoreConnection

	$objects = "Policies", "Conditions" # Maybe other stuff later? I don't know PBM well enough yet to know.

	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

	$attributes = New-Object System.Management.Automation.ParameterAttribute
	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	foreach ($name in $objects)
	{
		$items = $store.$name.Name
		if ($items.count -gt 0)
		{
			$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
			$attributeCollection.Add($attributes)
			$attributeCollection.Add((New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $items))
		}

		$newparams.Add($name, (New-Object -Type System.Management.Automation.RuntimeDefinedParameter($name, [String[]], $attributeCollection)))
	}
	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlResourceGovernor
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with Resource Governor objects from specified SQL Server server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	$pools = $server.ResourceGovernor.ResourcePools | Where-Object { $_.Name -notin "internal", "default" }

	if ($pools.count -gt 0)
	{
		$attributes = New-Object System.Management.Automation.ParameterAttribute
		$attributes.ParameterSetName = "__AllParameterSets"
		$attributes.Mandatory = $false
		$attributes.Position = 3

		$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
		$attributeCollection.Add($attributes)
		$attributeCollection.Add((New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $pools.Name))

		$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
		$newparams.Add("ResourcePools", (New-Object -Type System.Management.Automation.RuntimeDefinedParameter("ResourcePools", [String[]], $attributeCollection)))
	}
	$server.ConnectionContext.Disconnect()
	return $newparams
}

Function Get-ParamSqlExtendedEvents
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with Extended Event objects from specified SQL Server server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	if ([System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.XEvent") -eq $null)
	{
		return
	}

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	$sqlconn = $server.ConnectionContext.SqlConnectionObject
	$sqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sqlconn

	$store = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $sqlStoreConnection

	$objects = "Sessions" # Maybe packages later? I don't understand xEvents well enough yet to know.

	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

	$attributes = New-Object System.Management.Automation.ParameterAttribute
	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	foreach ($name in $objects)
	{
		$items = $store.$name.Name
		if ($items.count -gt 0)
		{
			$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
			$attributeCollection.Add($attributes)
			$attributeCollection.Add((New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $items))
		}

		$newparams.Add($name, (New-Object -Type System.Management.Automation.RuntimeDefinedParameter($name, [String[]], $attributeCollection)))
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
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	$objects = "ConfigurationValues", "Profiles", "Accounts", "MailServers"

	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

	$attributes = New-Object System.Management.Automation.ParameterAttribute
	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	foreach ($name in $objects)
	{
		if ($name -eq "MailServers") { $items = $server.Mail.Accounts.$name.Name }
		else { $items = $server.Mail.$name.Name }
		if ($items.count -gt 0)
		{
			$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
			$attributeCollection.Add($attributes)
			$attributeCollection.Add((New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $items))
		}

		$newparams.Add($name, (New-Object -Type System.Management.Automation.RuntimeDefinedParameter($name, [String[]], $attributeCollection)))
	}
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
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	$jobobjects = "ProxyAccounts", "JobSchedule", "SharedSchedules", "AlertSystem", "JobCategories", "OperatorCategories"
	$jobobjects += "AlertCategories", "Alerts", "TargetServerGroups", "TargetServers", "Operators", "Jobs", "Mail"

	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute
	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	foreach ($name in $jobobjects)
	{
		$items = $server.JobServer.$name.Name
		if ($items.count -gt 0)
		{
			$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
			$attributeCollection.Add($attributes)
			$attributeCollection.Add((New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $items))
		}

		$newparams.Add($name, (New-Object -Type System.Management.Automation.RuntimeDefinedParameter($name, [String[]], $attributeCollection)))
	}
	$server.ConnectionContext.Disconnect()

	return $newparams
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
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential

	)

	if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.RegisteredServers") -eq $null)
		{
			return
		}

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
	$paramattributes.Position = 3

	$argumentlist = $cmstore.DatabaseEngineServerGroup.ServerGroups.name

	if ($argumentlist -ne $null)
	{
		$validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $argumentlist

		$combinedattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
		$combinedattributes.Add($paramattributes)
		$combinedattributes.Add($validationset)
		$SqlCmsGroups = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("SqlCmsGroups", [String[]], $combinedattributes)
		$newparams.Add("SqlCmsGroups", $SqlCmsGroups)
		$Group = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Group", [String[]], $combinedattributes)
		$newparams.Add("Group", $Group)

		return $newparams
	}
	else { return }
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
		[Alias("ServerInstance","SqlInstance")]
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
	$attributes.Position = 3

	# Database list parameter setup
	if ($triggerlist) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $triggerlist }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($triggerlist) { $attributeCollection.Add($validationset) }
	$Triggers = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Triggers", [String[]], $attributeCollection)

	$newparams.Add("Triggers", $Triggers)
	$server.ConnectionContext.Disconnect()

	return $newparams
}


Function Get-ParamSqlCustomErrors
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with ID of Server Custom Errors/User Defined Messages from specified SQL Server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$messagelist = @()
	$uniquemessageid = $server.UserDefinedMessages | Select ID | Sort-Object | Get-Unique
	foreach ($message in $uniquemessageid)
	{
		$messagelist += $message.ID
	}

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($messagelist) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $messagelist }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($messagelist) { $attributeCollection.Add($validationset) }
	$CustomErrors = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("CustomErrors", [String[]], $attributeCollection)

	$newparams.Add("CustomErrors", $CustomErrors)
	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlDatabaseAssemblies
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with assemblies from specified SQL Server.

 Assembly name is in database.assemblyname format.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	######### Assemblies
	$list = @()

	foreach ($database in $server.Databases)
	{
		try
		{
			# a bug here requires a try/catch
			$userAssemblies = $($database.assemblies | Where-Object { $_.isSystemObject -eq $false })
			foreach ($assembly in $userAssemblies)
			{
				$name = "$($database.name).$($assembly.name)"
				$list += $name
			}
		}
		catch { }
	}

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($list)
	{
		$validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $list
	}
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($list) { $attributeCollection.Add($validationset) }
	$Assemblies = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Assemblies", [String[]], $attributeCollection)

	$newparams.Add("Assemblies", $Assemblies)

	$server.ConnectionContext.Disconnect()

	return $newparams
}


Function Get-ParamSqlDataCollectionSets
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with Collection Sets from specified SQL Server's Data Collection object.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	if ([System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.Collector") -eq $null)
		{
			return
		}

	$sqlconn = $server.ConnectionContext.SqlConnectionObject
	$storeconn = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sqlconn
	$store = New-Object Microsoft.SqlServer.Management.Collector.CollectorConfigStore $storeconn

	# Populate arrays
	$list = @()

	$collectionsets = $store.CollectionSets | Where-Object { $_.isSystem -eq $false }
	foreach ($collectionset in $collectionsets)
	{
		$list += $collectionset.name
	}

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($list) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $list }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($list) { $attributeCollection.Add($validationset) }
	$CollectionSets = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("CollectionSets", [String[]], $attributeCollection)

	$newparams.Add("CollectionSets", $CollectionSets)
	$server.ConnectionContext.Disconnect()

	return $newparams
}


Function Get-ParamSqlAlerts
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with Alerts from specified SQL Server Job Server (SQL Agent).
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$list = $server.JobServer.Alerts.Name

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($list) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $list }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($list) { $attributeCollection.Add($validationset) }
	$Alerts = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Alerts", [String[]], $attributeCollection)

	$newparams.Add("Alerts", $Alerts)
	$server.ConnectionContext.Disconnect()

	return $newparams
}


Function Get-ParamSqlOperators
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with Operators from specified SQL Server Job Server (SQL Agent).
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$list = $server.JobServer.Operators.Name

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($list) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $list }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($list) { $attributeCollection.Add($validationset) }
	$Operators = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Operators", [String[]], $attributeCollection)

	$newparams.Add("Operators", $Operators)
	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlOperatorCategories
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with OperatorCategories from specified SQL Server Job Server (SQL Agent).
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$list = ($server.JobServer.OperatorCategories | Where-Object { $_.ID -ge 100 }).Name

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($list) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $list }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($list) { $attributeCollection.Add($validationset) }
	$OperatorCategories = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("OperatorCategories", [String[]], $attributeCollection)

	$newparams.Add("OperatorCategories", $OperatorCategories)
	$server.ConnectionContext.Disconnect()

	return $newparams
}


Function Get-ParamSqlProxyAccounts
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with ProxyAccounts from specified SQL Server Job Server (SQL Agent).
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$list = $server.JobServer.ProxyAccounts.Name

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($list) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $list }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($list) { $attributeCollection.Add($validationset) }
	$ProxyAccounts = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("ProxyAccounts", [String[]], $attributeCollection)

	$newparams.Add("ProxyAccounts", $ProxyAccounts)
	$server.ConnectionContext.Disconnect()

	return $newparams
}



Function Get-ParamSqlSharedSchedules
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with SharedSchedules from specified SQL Server Job Server (SQL Agent).
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$list = $server.JobServer.SharedSchedules.Name

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($list) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $list }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($list) { $attributeCollection.Add($validationset) }
	$SharedSchedules = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("SharedSchedules", [String[]], $attributeCollection)

	$newparams.Add("SharedSchedules", $SharedSchedules)
	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlJobCategories
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with JobCategories from specified SQL Server Job Server (SQL Agent).
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$list = ($server.JobServer.JobCategories | Where-Object { $_.ID -ge 100 }).Name

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($list) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $list }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($list) { $attributeCollection.Add($validationset) }
	$JobCategories = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("JobCategories", [String[]], $attributeCollection)

	$newparams.Add("JobCategories", $JobCategories)
	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlAlertCategories
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with AlertCategories from specified SQL Server Job Server (SQL Agent).
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$list = ($server.JobServer.AlertCategories | Where-Object { $_.ID -ge 100 }).Name

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($list) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $list }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($list) { $attributeCollection.Add($validationset) }
	$AlertCategories = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("AlertCategories", [String[]], $attributeCollection)

	$newparams.Add("AlertCategories", $AlertCategories)
	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlTargetServers
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with TargetServers from specified SQL Server Job Server (SQL Agent).
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$list = $server.JobServer.TargetServers.Name

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($list) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $list }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($list) { $attributeCollection.Add($validationset) }
	$TargetServers = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("TargetServers", [String[]], $attributeCollection)

	$newparams.Add("TargetServers", $TargetServers)
	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlTargetServerGroups
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with TargetServerGroups from specified SQL Server Job Server (SQL Agent).
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$list = $server.JobServer.TargetServerGroups.Name

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($list) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $list }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($list) { $attributeCollection.Add($validationset) }
	$TargetServerGroups = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("TargetServerGroups", [String[]], $attributeCollection)

	$newparams.Add("TargetServerGroups", $TargetServerGroups)
	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlJobs
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with Jobs from specified SQL Server Job Server (SQL Agent).
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays
	$list = $server.JobServer.Jobs.Name

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	# Database list parameter setup
	if ($list) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $list }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($list) { $attributeCollection.Add($validationset) }
	$Jobs = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Jobs", [String[]], $attributeCollection)
	$Exclude = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Exclude", [String[]], $attributeCollection)

	$newparams.Add("Jobs", $Jobs)
	$newparams.Add("Exclude", $Exclude)
	$server.ConnectionContext.Disconnect()

	return $newparams
}

Function Get-ParamSqlAgentCategories
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with job server objects from specified SQL Server server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	$jobobjects = "JobCategories", "OperatorCategories", "AlertCategories"

	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute
	$attributes.ParameterSetName = "__AllParameterSets"
	$attributes.Mandatory = $false
	$attributes.Position = 3

	foreach ($name in $jobobjects)
	{
		$items = ($server.JobServer.$name | Where-Object { $_.ID -ge 100 }).Name
		if ($items.count -gt 0)
		{
			$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
			$attributeCollection.Add($attributes)
			$attributeCollection.Add((New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $items))
		}

		$newparams.Add($name, (New-Object -Type System.Management.Automation.RuntimeDefinedParameter($name, [String[]], $attributeCollection)))
	}

	return $newparams
}

Function Get-ParamSqlDatabaseFileTypes
{
<#
 .SYNOPSIS
 Internal function. Returns System.Management.Automation.RuntimeDefinedParameterDictionary
 filled with Server Configs from specified SQL Server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

	try { $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential -ParameterConnection }
	catch { return }

	# Populate arrays

	if ($server.versionMajor -eq 8)
	{
		$sql = "select distinct CASE WHEN groupid = 1 THEN 'ROWS' WHEN groupid = 0 THEN 'LOG' END as filetype from sysaltfiles"
	}
	else
	{
		$sql = "SELECT distinct CASE type_desc WHEN 'ROWS' then 'DATA' ELSE type_desc END AS FileType FROM sys.master_files mf INNER JOIN sys.databases db ON db.database_id = mf.database_id"
	}

	$dbfiletable = $server.ConnectionContext.ExecuteWithResults($sql)
	$filetypes = ($dbfiletable.Tables[0].Rows).FileType

	if ($server.versionMajor -eq 8)
	{
		$filetypes += "FULLTEXT"
	}

	# Reusable parameter setup
	$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
	$attributes = New-Object System.Management.Automation.ParameterAttribute

	$attributes.ParameterSetName = "FileTypes"
	$attributes.Mandatory = $true
	$attributes.Position = 3

	# Database list parameter setup
	if ($filetypes) { $validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $filetypes }
	$attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
	$attributeCollection.Add($attributes)
	if ($filetypes) { $attributeCollection.Add($validationset) }
	$FileType = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("FileType", [String[]], $attributeCollection)

	$newparams.Add("FileType", $FileType)
	$server.ConnectionContext.Disconnect()

	return $newparams
}