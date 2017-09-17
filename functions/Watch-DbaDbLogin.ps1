function Watch-DbaDbLogin {
	<#
		.SYNOPSIS
			Tracks SQL Server logins: which host they came from, what database they're using, and what program is being used to log in.

		.DESCRIPTION
			Watch-DbaDbLogin uses SQL Server process enumeration to track logins in a SQL Server table. This is helpful when you need to migrate a SQL Server and update connection strings, but have inadequate documentation on which servers/applications are logging into your SQL instance.

			Running this script every 5 minutes for a week should give you a sufficient idea about database and login usage.

		.PARAMETER SqlInstance
			The SQL Server that stores the Watch database.

		.PARAMETER SqlCms
			Specifies a Central Management Server to query for a list of servers to watch.

		.PARAMETER SqlCmsGroups
			This is an auto-populated array that contains your Central Management Server top-level groups. You can use one or many groups.

			If -SqlCmsGroups is not specified, the Watch-DbaDbLogin script will run against all servers in your Central Management Server.

		.PARAMETER ServersFromFile
			Specifies a file containing a list of servers to watch. This file must contain one server name per line.

		.PARAMETER Database
			The name of the Watch database. By default, this is DatabaseLogins.

		.PARAMETER Table
			The name of the Watch table. By default, this is DbLogins.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.NOTES
			Tags: Login
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on all SQL Servers for the most accurate results

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Watch-DbaDbLogin

		.EXAMPLE
			Watch-DbaDbLogin -SqlInstance sqlserver -SqlCms SqlCms1

			A list of all database instances within the Central Management Server SqlCms1 is generated. Using this list, the script enumerates all the processes and gathers login information and saves it to the table Dblogins in the DatabaseLogins database on SQL Server sqlserver.

		.EXAMPLE
			Watch-DbaDbLogin -SqlInstance sqlcluster -Database CentralAudit -ServersFromFile .\sqlservers.txt

			A list of servers is gathered from the file sqlservers.txt in the current directory. Using this list, the script enumerates all the processes and gathers login information and saves it to the table Dblogins in the CentralAudit database on SQL Server sqlcluster.

		.EXAMPLE
			Watch-DbaDbLogin -SqlInstance sqlserver -SqlCms SqlCms1 -SqlCmsGroups SQL2014Clusters -SqlCredential $cred

			A list of servers is generated using database instance names within the SQL2014Clusters group on the Central Management Server SqlCms1. Using this list, the script enumerates all the processes and gathers login information and saves it to the table Dblogins in the DatabaseLogins database on sqlserver.

	#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstance]$SqlInstance,
		[object[]]$Database = "DatabaseLogins",
		[string]$Table = "DbLogins",
		[PSCredential]$SqlCredential,
		# Central Management Server

		[string]$SqlCms,
		# File with one server per line

		[string]$ServersFromFile
	)

	process {
		if ([string]::IsNullOrEmpty($SqlCms) -and [string]::IsNullOrEmpty($ServersFromFile)) {
			throw "You must specify a server list source using -SqlCms or -ServersFromFile"
		}

		<#
			Setup datatable & bulk copy
		#>

		if ($SqlCredential.UserName) {
			$username = $SqlCredential.Username
			$password = $SqlCredential.GetNetworkCredential().Password
			$connectionstring = "Data Source=$SqlInstance;Initial Catalog=$Database;User Id=$username;Password=$password;"
		}
		else {
			$connectionstring = "Data Source=$SqlInstance;Integrated Security=true;Initial Catalog=$Database;"
		}

		$bulkcopy = New-Object ("Data.SqlClient.SqlBulkCopy") $connectionstring
		$bulkcopy.DestinationTableName = $Table

		$datatable = New-Object "System.Data.DataTable"
		$null = $datatable.Columns.Add("SQLServer")
		$null = $datatable.Columns.Add("LoginName")
		$null = $datatable.Columns.Add("Host")
		$null = $datatable.Columns.Add("DbName")
		$null = $datatable.Columns.Add("Program")

		$systemdbs = "master", "msdb", "model", "tempdb"
		$excludedPrograms = "Microsoft SQL Server Management Studio - Query", "SQL Management"

		<#
			Get servers to query from Central Management Server or File
		#>
		if ($SqlCms) {
			try {
				$servers = Get-DbaRegisteredServerName -SqlInstance $SqlCms -SqlCredential $SqlCredential -Silent
			}
			catch {
				Write-Warning "The CMS server, $SqlCms, was not accessible."
				return
			}
		}
		if (Test-Bound 'ServersFromFile') {
			if (Test-Path $ServersFromFile) {
				$servers = Get-Content $ServersFromFile
			}
			else {
				Write-Warning "$ServersFromFile was not found."
				return
			}
		}

		<#
			Process each server
		#>

		foreach ($instance in $servers) {
			Write-Output "Attempting to connect to $instance."
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Write-Error "Can't connect to $instance. Skipping.";
				continue
			}

			if (!(Test-SqlSa $server)) {
				Write-Warning "Not a sysadmin on $instance, resultset would be underwhelming. Skipping.";
				continue
			}

			$procs = $server.EnumProcesses() | Where-Object { $_.Host -ne $sourceserver.ComputerNamePhysicalNetBIOS -and ![string]::IsNullOrEmpty($_.Host) }
			$procs = $procs | Where-Object { $systemdbs -notcontains $_.Database -and $excludedPrograms -notcontains $_.Program } | Select-Object Login, Host, Database, Program

			foreach ($p in $procs) {
				$row = $datatable.NewRow()
				$row.itemarray = $server.name, $p.Login, $p.Host, $p.Database, $p.Program
				$datatable.Rows.Add($row)
			}
			$server.ConnectionContext.Disconnect()
			Write-Output "Added process information for $instance to datatable."
		}

		<#
			Write to $Table in $Database on $SqlInstance
		#>

		try {
			$bulkcopy.WriteToServer($datatable)
			if ($datatable.rows.count -eq 0) {
				Write-Warning "Nothing done."
			}
			$bulkcopy.Close()
			Write-Output "Updated $Table in $Database on $SqlInstance with $($datatable.rows.count) rows."
		}
		catch { Write-Error "Could not update $Table in $Database on $SqlInstance. Do the database and table exist and do you have access?" }

	}

	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Watch-SqlDbLogin
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
