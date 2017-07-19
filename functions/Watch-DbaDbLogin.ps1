function Watch-DbaDbLogin {
    <#
.SYNOPSIS
Tracks SQL Server logins: which host they came from, what database they're using, and what program is being used to log in.

.DESCRIPTION
Watch-DbaDbLogin uses SQL Server process enumeration to track logins in a SQL Server table. This is helpful when you
need to migrate a SQL Server, and update connection strings, but have inadequate documentation on which servers/applications
are logging into your SQL instance.

Running this script every 5 minutes for a week should give you a sufficient idea about database and login usage.

.PARAMETER SqlInstance
The SQL Server that stores the Watch database

.PARAMETER SqlCms
A list of servers to watch is required. If you would like to gather that list from a Central Management Server, use -SqlCms servername.

.PARAMETER SqlCmsGroups
This is an auto-populated array that contains your Central Management Server top-level groups. You can use one or many.
If -SqlCmsGroups is not specified, the Watch-DbaDbLogin script will run against all servers in your Central Management Server.

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
Tags: Logins
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on all SQL Servers for
the most accurate results

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Watch-DbaDbLogin

.EXAMPLE
Watch-DbaDbLogin -SqlInstance sqlserver -SqlCms SqlCms1

In the above example, a list of servers is generated using all database instances within the Central Management Server "SqlCms1". Using this list, the script then enumerates all the processes and gathers login information, and saves it to the table "Dblogins" within the "DatabaseLogins" database on the SQL Server "sqlserver".

.EXAMPLE
Watch-DbaDbLogin -SqlInstance sqlcluster -Database CentralAudit -ServersFromFile .\sqlservers.txt

In the above example, a list of servers is gathered from the file sqlservers.txt in the current directory. Using this list, the script then enumerates all the processes and gathers login information, and saves it to the table "Dblogins" within the "CentralAudit" database on the SQL Server "sqlcluster".

.EXAMPLE
Watch-DbaDbLogin -SqlInstance sqlserver -SqlCms SqlCms1 -SqlCmsGroups SQL2014Clusters -SqlCredential $cred

In the above example, a list of servers is generated using database instance names within the "SQL2014Clusters" group on the Central Management Server "SqlCms1". Using this list, the script then enumerates all the processes and gathers login information, and saves it to the table "Dblogins" within the "DatabaseLogins" database on "sqlserver".

#>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    Param (
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [string]$Database = "DatabaseLogins",
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

        if ($sqlcredential.UserName) {
            $username = $sqlcredential.Username
            $password = $SqlCredential.GetNetworkCredential().Password
            $connectionstring = "Data Source=$SqlInstance;Initial Catalog=$Database;User Id=$username;Password=$password;"
        }
        else { $connectionstring = "Data Source=$SqlInstance;Integrated Security=true;Initial Catalog=$Database;" }


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
        if ($SqlCms) {
            $server = New-Object Microsoft.SqlServer.Management.Smo.Server $SqlCms
            $sqlconnection = $server.ConnectionContext.SqlConnectionObject

            try { $cmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sqlconnection) }
            catch { throw "Cannot access Central Management Server" }

            if ($SqlCmsGroups) {
                foreach ($groupname in $SqlCmsGroups) {
                    $CMS = $cmstore.ServerGroups["DatabaseEngineServerGroup"].ServerGroups[$groupname]
                    $servers += ($cms.GetDescendantRegisteredServers()).servername
                }
            }
            else {
                $CMS = $cmstore.ServerGroups["DatabaseEngineServerGroup"]
                $servers = ($cms.GetDescendantRegisteredServers()).servername
                if ($servers -notcontains $SqlCms) { $servers += $SqlCms }
            }
        }

        If ($ServersFromFile) {
            $servers = Get-Content $ServersFromFile
        }

        <#
			Process each server
		#>

        foreach ($servername in $servers) {
            Write-Output "Attempting to connect to $servername"
            try { $server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $SqlCredential }
            catch { Write-Error "Can't connect to $servername. Skipping."; continue }

            if (!(Test-SqlSa $server)) { Write-Warning "Not a sysadmin on $servername, resultset would be underwhelming. Skipping."; continue }


            $procs = $server.EnumProcesses() | Where-Object { $_.Host -ne $sourceserver.ComputerNamePhysicalNetBIOS -and ![string]::IsNullOrEmpty($_.Host) }
            $procs = $procs | Where-Object { $systemdbs -notcontains $_.Database -and $excludedPrograms -notcontains $_.Program } | Select-Object Login, Host, Database, Program

            foreach ($p in $procs) {
                $row = $datatable.NewRow()
                $row.itemarray = $server.name, $p.Login, $p.Host, $p.Database, $p.Program
                $datatable.Rows.Add($row)
            }
            $server.ConnectionContext.Disconnect()
            Write-Output "Added process information for $servername to datatable."
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
        Write-Output "Script completed"
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
