<# 
 .SYNOPSIS 
    Tracks SQL Server logins: which host they came from, what database they're using, and what program is being used to log in.

 .DESCRIPTION 
    Watch-DBLogins.ps1 uses SQL Server process enumeration to track logins in a SQL Server table. This is helpful when you 
	need to migrate a SQL Server, and update connection strings, but have inadequate documentation on which servers/applications 
	are logging into your SQL instance. 
	
	Running this script every 5 minutes for a week should give you a sufficient idea about database and login usage.

 .PARAMETER WatchDBServer
	The SQL Server that stores the Watch database
	
 .PARAMETER CMServer
	A list of servers to watch is required. If you would like to gather that list from a Central Management Server, use -CMServer servername.
	
 .PARAMETER cmgroups
	This is an auto-populated array that contains your Central Management Server top-level groups. You can use one or many.
	If -cmgroups is not specified, the Watch-DBLogins.ps1 script will run against all servers in your Central Management Server.
	
 .PARAMETER ServersFromFile
	A list of servers to watch is required. You can use a file formatted as such:
	sqlserver1
	sqlserver2

 .PARAMETER WatchDB
	The Watch database. By default, this is WatchDBLogins.

.PARAMETER WatchTable
	The Watch table. By default, this is DBLogins.

 .NOTES 
    Author  : Chrissy LeMaire
    Requires: 	PowerShell Version 3.0, SQL Server SMO, 
				sysadmin access on all SQL Servers for
				the most accurate results
	DateUpdated: 2015-Jan-13

 .LINK 
  	http://gallery.technet.microsoft.com/scriptcenter/SQL-Server-DatabaseApp-4abbd73a

 .EXAMPLE   
.\Watch-DBLogins.ps1 -WatchDBServer sqlserver -CMServer cmserver1

In the above example, a list of servers is generated using all database instances within the Central Management Server "cmserver1". Using this list, the script then enumerates all the processes and gathers login information, and saves it to the table "DBlogins" within the "WatchDBLogins" database on the SQL Server "sqlserver".

 .EXAMPLE   
.\Watch-DBLogins.ps1 -WatchDBServer sqlcluster -WatchDB CentralAudit -ServersFromFile .\sqlservers.txt

In the above example, a list of servers is gathered from the file sqlservers.txt in the current directory. Using this list, the script then enumerates all the processes and gathers login information, and saves it to the table "DBlogins" within the "CentralAudit" database on the SQL Server "sqlcluster".

 .EXAMPLE   
.\Watch-DBLogins.ps1 -WatchDBServer sqlserver -CMServer cmserver1 -cmgroups SQL2014Clusters

In the above example, a list of servers is generated using database instance names within the "SQL2014Clusters" group on the Central Management Server "cmserver1". Using this list, the script then enumerates all the processes and gathers login information, and saves it to the table "DBlogins" within the "WatchDBLogins" database on "sqlserver".

#> 
#Requires -Version 3.0
[CmdletBinding(DefaultParameterSetName="Default")]

Param(
	[parameter(Mandatory = $true)]
	[string]$WatchDBServer,
	[string]$WatchDB = "WatchDBLogins",
	[string]$WatchTable = "DBLogins",
	 
	# Central Management Server
	[string]$CMServer,
	
	# File with one server per line
	[string]$ServersFromFile
	)
	
DynamicParam  {
	if ($CMServer) {
		if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") -eq $null) {return}
		if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.RegisteredServers") -eq $null) {return}

		$server = New-Object Microsoft.SqlServer.Management.Smo.Server $cmserver
		$sqlconnection = $server.ConnectionContext.SqlConnectionObject

		try { $cmstore = new-object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sqlconnection)}
		catch { return }
		
		if ($cmstore -eq $null) { return }
		
		$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
		$paramattributes = New-Object System.Management.Automation.ParameterAttribute
		$paramattributes.ParameterSetName = "__AllParameterSets"
		$paramattributes.Mandatory = $false
		
		$argumentlist = $cmstore.DatabaseEngineServerGroup.ServerGroups.name
		
		if ($argumentlist -ne $null) {
			$validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $argumentlist
			
			$combinedattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
			$combinedattributes.Add($paramattributes)
			$combinedattributes.Add($validationset)

			$CMGroups = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("CMGroups", [String[]], $combinedattributes)
			$newparams.Add("CMGroups", $CMGroups)
			
			return $newparams
		} else { return $false }
	}
}

BEGIN {

Function Test-SQLSA      {
 <#
            .SYNOPSIS
              Ensures sysadmin account access on SQL Server. $server is an SMO server object.

            .EXAMPLE
              if (!(Test-SQLSA $server)) { throw "Not a sysadmin on $source. Quitting." }  

            .OUTPUTS
                $true if syadmin
                $false if not
			
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$server	
		)
		
try {
		$issysadmin = $server.Logins[$server.ConnectionContext.trueLogin].IsMember("sysadmin")
		if ($issysadmin -eq $true) { return $true } else { return $false }
	}
	catch { return $false }
}

}

PROCESS { 
	
	if ([string]::IsNullOrEmpty($CMServer) -and [string]::IsNullOrEmpty($ServersFromFile)) {
		throw "You must specify a server list source using -CMServer or -ServersFromFile" 
	}
	
	if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") -eq $null )
	{ throw "Quitting: SMO Required. You can download it from http://goo.gl/R4yA6u" }
	 if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.RegisteredServers") -eq $null )
	{ throw "Quitting: SMO Required. You can download it from http://goo.gl/R4yA6u" }
	
	if ($cmgroups.Value -ne $null) {$cmgroups = @($cmgroups.Value)}  else {$cmgroups = $null}
	
	<#
	
						Setup datatable & bulk copy
	
	#>
	
	$connectionstring = "Data Source=$WatchDBServer;Integrated Security=true;Initial Catalog=$WatchDB;" 
	$bulkcopy = new-object ("Data.SqlClient.Sqlbulkcopy") $connectionstring 
	$bulkcopy.DestinationTableName = $WatchTable

	$datatable = New-Object "System.Data.DataTable"
	$null = $datatable.Columns.Add("SQLServer") 
	$null = $datatable.Columns.Add("Loginname") 
	$null = $datatable.Columns.Add("Host") 
	$null = $datatable.Columns.Add("DBname") 
	$null = $datatable.Columns.Add("Program") 

	$systemdbs = "master","msdb","model","tempdb"
	$excludedPrograms = "Microsoft SQL Server Management Studio - Query","SQL Management"

	<#
	
			Get servers to query from Central Management Server or File
	
	#>
	$servers = @()
	if ($CMServer) {
		$server = New-Object Microsoft.SqlServer.Management.Smo.Server $cmserver
		$sqlconnection = $server.ConnectionContext.SqlConnectionObject

		try { $cmstore = new-object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sqlconnection)}
		catch { throw "Cannot access Central Management Server" }
	
		if ($cmgroups -ne $null) {
			foreach ($groupname in $cmgroups) {
				$CMS = $cmstore.ServerGroups["DatabaseEngineServerGroup"].ServerGroups[$groupname]
				$servers += ($cms.GetDescendantRegisteredServers()).servername	
			}
		} else {
			$CMS = $cmstore.ServerGroups["DatabaseEngineServerGroup"]
			$servers = ($cms.GetDescendantRegisteredServers()).servername
			if ($servers -notcontains $CMServer) { $servers += $CMServer }
		}
	}

	If ($ServersFromFile) {
		$servers = Get-Content $ServersFromFile
	}
	
	<#
	
				Process each server
	
	#>
	
	foreach ($servername in $servers) {
		Write-Host "Attempting to connect to $servername"  -ForegroundColor Yellow
		$server = New-Object Microsoft.SqlServer.Management.Smo.Server $servername
		try { $server.ConnectionContext.Connect() } catch { Write-Warning "Can't connect to $servername. Moving on."; continue }
		if (!(Test-SQLSA $server)) { Write-Warning "Not a sysadmin on $servername, resultset would be underwhelming. Moving on." }

		$procs = $server.EnumProcesses() | Where-Object { $_.Host -ne $sourceserver.ComputerNamePhysicalNetBIOS -and ![string]::IsNullOrEmpty($_.Host) }
		$procs = $procs | Where-Object {$systemdbs -notcontains $_.Database -and $excludedPrograms -notcontains $_.Program }| Select Login, Host, Database, Program

		foreach ($p in $procs) {
			$row = $datatable.NewRow() 
			$row.itemarray = $server.name, $p.Login, $p.Host, $p.Database, $p.Program
			$datatable.Rows.Add($row)
		}
		$server.ConnectionContext.Disconnect()
		Write-Host "Added process information for $servername to datatable." -ForegroundColor Yellow
	}

	<#
	
				Write to $WatchTable in $WatchDB on $WatchDBServer
	
	#>
	
	try {
		$bulkcopy.WriteToServer($datatable)
		if ($datatable.rows.count -eq 0) {
			Write-Warning "Nothing done."
		}
		$bulkcopy.Close()
		Write-Host "Updated $WatchTable in $WatchDB on $WatchDBServer with $($datatable.rows.count) rows." -ForegroundColor Green
	} catch {Write-Warning "Could not update $WatchTable in $WatchDB on $WatchDBServer. Do you have access to this database?"}

	
}

END {
	Write-Host "Script completed" -ForegroundColor Green
	}
	
<#
---- SQL database and table ----

CREATE DATABASE WatchDBLogins
GO
USE WatchDBLogins
GO
CREATE TABLE [dbo].[DBLogins]( 
[SQLServer] varchar(128),
[LoginName] varchar(128),
[Host] varchar(128),
[DBName] varchar(128),
[Program] varchar(256),
[Timestamp] datetime default getdate(),
)
-- Create Unique Clustered Index with IGNORE_DUPE_KEY=ON to avoid duplicates
CREATE UNIQUE CLUSTERED INDEX [ClusteredIndex-Combo] ON [dbo].[DBLogins]
(
	 [SQLServer] ASC,
     [LoginName] ASC,
     [Host] ASC,
     [DBName] ASC,
	 [Program] ASC
) WITH (IGNORE_DUP_KEY = ON)
GO
#>