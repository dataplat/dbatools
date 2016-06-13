Function Watch-SqlDbLogin
{
<# 
.SYNOPSIS 
Tracks SQL Server logins: which host they came from, what database they're using, and what program is being used to log in.

.DESCRIPTION 
Watch-SqlDbLogin uses SQL Server process enumeration to track logins in a SQL Server table. This is helpful when you 
need to migrate a SQL Server, and update connection strings, but have inadequate documentation on which servers/applications 
are logging into your SQL instance. 

Running this script every 5 minutes for a week should give you a sufficient idea about database and login usage.

.PARAMETER SqlServer
The SQL Server that stores the Watch database

.PARAMETER SqlCms
A list of servers to watch is required. If you would like to gather that list from a Central Management Server, use -SqlCms servername.

.PARAMETER SqlCmsGroups
This is an auto-populated array that contains your Central Management Server top-level groups. You can use one or many.
If -SqlCmsGroups is not specified, the Watch-SqlDbLogin script will run against all servers in your Central Management Server.

.PARAMETER ServersFromFile
A list of servers to watch is required. You can use a file formatted as such:
sqlserver1
sqlserver2

.PARAMETER Database
The Watch database. By default, this is DatabaseLogins.

.PARAMETER Table
The Watch table. By default, this is DbLogins.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$cred = Get-Credential, this pass this $cred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on all SQL Servers for
the most accurate results

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Watch-SqlDbLogin

.EXAMPLE   
Watch-SqlDbLogin -SqlServer sqlserver -SqlCms SqlCms1

In the above example, a list of servers is generated using all database instances within the Central Management Server "SqlCms1". Using this list, the script then enumerates all the processes and gathers login information, and saves it to the table "Dblogins" within the "DatabaseLogins" database on the SQL Server "sqlserver".

.EXAMPLE   
Watch-SqlDbLogin -SqlServer sqlcluster -Database CentralAudit -ServersFromFile .\sqlservers.txt

In the above example, a list of servers is gathered from the file sqlservers.txt in the current directory. Using this list, the script then enumerates all the processes and gathers login information, and saves it to the table "Dblogins" within the "CentralAudit" database on the SQL Server "sqlcluster".

.EXAMPLE   
Watch-SqlDbLogin -SqlServer sqlserver -SqlCms SqlCms1 -SqlCmsGroups SQL2014Clusters -SqlCredential $cred

In the above example, a list of servers is generated using database instance names within the "SQL2014Clusters" group on the Central Management Server "SqlCms1". Using this list, the script then enumerates all the processes and gathers login information, and saves it to the table "Dblogins" within the "DatabaseLogins" database on "sqlserver".

#>	
	[CmdletBinding(DefaultParameterSetName = "Default")]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[string]$SqlServer,
		[string]$Database = "DatabaseLogins",
		[string]$Table = "DbLogins",
		[System.Management.Automation.PSCredential]$SqlCredential,
		# Central Management Server

		[string]$SqlCms,
		# File with one server per line

		[string]$ServersFromFile
	)
	
	DynamicParam { if ($SqlCms) { return (Get-ParamSqlCmsGroups -SqlServer $SqlCms -SqlCredential $SqlCredential) } }
	
	PROCESS
	{
		
		$SqlCmsGroups = $psboundparameters.SqlCmsGroups
		
		if ([string]::IsNullOrEmpty($SqlCms) -and [string]::IsNullOrEmpty($ServersFromFile))
		{
			throw "You must specify a server list source using -SqlCms or -ServersFromFile"
		}
		
<#

	Setup datatable & bulk copy

#>
		
		if ($sqlcredential.Username -ne $null)
		{
			$username = $sqlcredential.Username
			$password = $SqlCredential.GetNetworkCredential().Password
			$connectionstring = "Data Source=$SqlServer;Initial Catalog=$Database;User Id=$username;Password=$password;"
		}
		else { $connectionstring = "Data Source=$SqlServer;Integrated Security=true;Initial Catalog=$Database;" }
		
		
		$bulkcopy = New-Object ("Data.SqlClient.Sqlbulkcopy") $connectionstring
		$bulkcopy.DestinationTableName = $Table
		
		$datatable = New-Object "System.Data.DataTable"
		$null = $datatable.Columns.Add("SQLServer")
		$null = $datatable.Columns.Add("Loginname")
		$null = $datatable.Columns.Add("Host")
		$null = $datatable.Columns.Add("Dbname")
		$null = $datatable.Columns.Add("Program")
		
		$systemdbs = "master", "msdb", "model", "tempdb"
		$excludedPrograms = "Microsoft SQL Server Management Studio - Query", "SQL Management"
		
<#

	Get servers to query from Central Management Server or File

#>
		$servers = @()
		if ($SqlCms)
		{
			$server = New-Object Microsoft.SqlServer.Management.Smo.Server $SqlCms
			$sqlconnection = $server.ConnectionContext.SqlConnectionObject
			
			try { $cmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sqlconnection) }
			catch { throw "Cannot access Central Management Server" }
			
			if ($SqlCmsGroups -ne $null)
			{
				foreach ($groupname in $SqlCmsGroups)
				{
					$CMS = $cmstore.ServerGroups["DatabaseEngineServerGroup"].ServerGroups[$groupname]
					$servers += ($cms.GetDescendantRegisteredServers()).servername
				}
			}
			else
			{
				$CMS = $cmstore.ServerGroups["DatabaseEngineServerGroup"]
				$servers = ($cms.GetDescendantRegisteredServers()).servername
				if ($servers -notcontains $SqlCms) { $servers += $SqlCms }
			}
		}
		
		If ($ServersFromFile)
		{
			$servers = Get-Content $ServersFromFile
		}
		
<#

			Process each server

#>
		
		foreach ($servername in $servers)
		{
			Write-Output "Attempting to connect to $servername"
			try { $server = Connect-SqlServer -SqlServer $servername -SqlCredential $SqlCredential }
			catch { Write-Error "Can't connect to $servername. Skipping."; continue }
			
			if (!(Test-SqlSa $server)) { Write-Warning "Not a sysadmin on $servername, resultset would be underwhelming. Skipping."; continue }
			
			
			$procs = $server.EnumProcesses() | Where-Object { $_.Host -ne $sourceserver.ComputerNamePhysicalNetBIOS -and ![string]::IsNullOrEmpty($_.Host) }
			$procs = $procs | Where-Object { $systemdbs -notcontains $_.Database -and $excludedPrograms -notcontains $_.Program } | Select Login, Host, Database, Program
			
			foreach ($p in $procs)
			{
				$row = $datatable.NewRow()
				$row.itemarray = $server.name, $p.Login, $p.Host, $p.Database, $p.Program
				$datatable.Rows.Add($row)
			}
			$server.ConnectionContext.Disconnect()
			Write-Output "Added process information for $servername to datatable."
		}
		
<#

			Write to $Table in $Database on $SqlServer

#>
		
		try
		{
			$bulkcopy.WriteToServer($datatable)
			if ($datatable.rows.count -eq 0)
			{
				Write-Warning "Nothing done."
			}
			$bulkcopy.Close()
			Write-Output "Updated $Table in $Database on $SqlServer with $($datatable.rows.count) rows."
		}
		catch { Write-Error "Could not update $Table in $Database on $SqlServer. Do the database and table exist and do you have access?" }
		
	}
	
	END
	{
		Write-Output "Script completed"
	}
<#
---- SQL database and table ----

    CREATE DATABASE DatabaseLogins
    GO
    USE DatabaseLogins
    GO
        CREATE TABLE [dbo].[DbLogins]( 
        [SQLServer] varchar(128),
        [LoginName] varchar(128),
        [Host] varchar(128),
        [DbName] varchar(128),
        [Program] varchar(256),
        [Timestamp] datetime default getdate(),
    )
-- Create Unique Clustered Index with IGNORE_DUPE_KEY=ON to avoid duplicates
    CREATE UNIQUE CLUSTERED INDEX [ClusteredIndex-Combo] ON [dbo].[DbLogins]
        (
        [SQLServer] ASC,
        [LoginName] ASC,
        [Host] ASC,
        [DbName] ASC,
        [Program] ASC
    ) WITH (IGNORE_DUP_KEY = ON)
    GO
#>
}
