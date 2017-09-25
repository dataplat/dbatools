function Test-DbaVirtualLogFile {
	<#
		.SYNOPSIS
			Returns database virtual log file information for database files on a SQL instance.

		.DESCRIPTION
			Having a transaction log file with too many virtual log files (VLFs) can hurt database performance.

			Too many VLFs can cause transaction log backups to slow down and can also slow down database recovery and, in extreme cases, even affect insert/update/delete performance.

			References:
				http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
				http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx

			If you've got a high number of VLFs, you can use Expand-SqlTLogResponsibly to reduce the number.

		.PARAMETER SqlInstance 
			Specifies the SQL Server instance(s) to scan.
			
		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Database
			Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.
		
		.PARAMETER ExcludeDatabase
			Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

		.PARAMETER IncludeSystemDBs
			If this switch is enabled, system database information will be displayed.

		.PARAMETER Detailed
			If this switch is enabled, all information provided by DBCC LOGINFO plus the server name and database name is returned.

		.NOTES
			Tags: DisasterRecovery, Backup

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Test-DbaVirtualLogFile

		.EXAMPLE
			Test-DbaVirtualLogFile -SqlInstance sqlcluster

			Returns all user database virtual log file counts for the sqlcluster instance.

		.EXAMPLE
			Test-DbaVirtualLogFile -SqlInstance sqlserver | Where-Object {$_.Count -ge 50}

			Returns user databases that have 50 or more VLFs.

		.EXAMPLE
			@('sqlserver','sqlcluster') | Test-DbaVirtualLogFile

			Returns all VLF information for the sqlserver and sqlcluster SQL Server instances. Processes data via the pipeline.

		.EXAMPLE
			Test-DbaVirtualLogFile -SqlInstance sqlcluster -Database db1, db2

			Returns VLF counts for the db1 and db2 databases on sqlcluster.
	#>
	[CmdletBinding()]
	[OutputType([System.Collections.ArrayList])]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[switch]$IncludeSystemDBs,
		[switch]$Detailed
	)

	PROCESS {
		foreach ($servername in $SqlInstance) {
			Write-Verbose "Connecting to $servername."
			try {
				$server = Connect-SqlInstance $servername -SqlCredential $SqlCredential
			}
			catch {
				Write-Warning "Can't connect to $instance, skipping."
				Continue
			}

			$dbs = $server.Databases
			#If IncludeSystemDBs is true, include systemdbs
			#only look at online databases (Status equal normal)

			if ($Database) {
				$dbs = $dbs | Where-Object { $Database -contains $_.Name }
			}
			if ($ExcludeDatabase) {
				$dbs = $dbs | Where-Object Name -notin $ExcludeDatabase
			}

			if ($IncludeSystemDBs) {
				$dbs = $dbs | Where-Object { $_.status -eq 'Normal' }
			}
			else {
				$dbs = $dbs | Where-Object { $_.status -eq 'Normal' -and $_.IsSystemObject -eq 0 }
			}

			foreach ($db in $dbs) {
				try {
					Write-Verbose "Querying $($db.name) on $servername."
					#Execute query against individual database and add to output

					if ($Detailed -eq $true) {
						$table = New-Object System.Data.Datatable
						$servercolumn = $table.Columns.Add("Server")
						$servercolumn.DefaultValue = $server.name
						$dbcolumn = $table.Columns.Add("Database")
						$dbcolumn.DefaultValue = $db.name

						$temptable = $db.ExecuteWithResults("DBCC LOGINFO").Tables

						foreach ($column in $temptable.Columns) {
							$null = $table.Columns.Add($column.ColumnName)
						}

						foreach ($row in $temptable.rows) {
							$table.ImportRow($row)
						}
						
						$table
					}
					else {
						[PSCustomObject]@{
							Server   = $server.name
							Database = $db.name
							Count    = $db.ExecuteWithResults("DBCC LOGINFO").Tables.Rows.Count
						}
					}
				}
				catch {
					Write-Exception $_
					Write-Warning "Unable to query $($db.name) on $servername."
					continue
				}
			}
		}
	}
}

