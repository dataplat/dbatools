Function Get-DbaDatabaseSnapshot {
<#
.SYNOPSIS
Get database snapshots with details

.DESCRIPTION
Retrieves the list of database snapshot available, along with their base (the db they are the snapshot of) and creation time

.PARAMETER SqlInstance 
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Return information for only specific base dbs

.PARAMETER Snapshots
Return information for only specific snapshots

.NOTES
Tags: Snapshot
Author: niphlod

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
 https://dbatools.io/Get-DbaDatabaseSnapshot

.EXAMPLE
Get-DbaDatabaseSnapshot -SqlServer sqlserver2014a

Returns a custom object displaying Server, Database, DatabaseCreated, SnapshotOf, SizeMB, DatabaseCreated

.EXAMPLE
Get-DbaDatabaseSnapshot -SqlServer sqlserver2014a -Databases HR, Accounting

Returns information for database snapshots having HR and Accounting as base dbs

.EXAMPLE
Get-DbaDatabaseSnapshot -SqlServer sqlserver2014a -Snapshots HR_snapshot, Accounting_snapshot

Returns information for database snapshots HR_snapshot and Accounting_snapshot

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[string[]]$SqlInstance,
		[PsCredential]$Credential
	)
	
	DynamicParam {
		if ($SqlInstance) {
			Get-ParamSqlSnapshotsAndDatabases -SqlServer $SqlInstance[0] -SqlCredential $Credential
		}
	}
	
	BEGIN {
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		$snapshots = $psboundparameters.Snapshots
	}
	
	PROCESS {
		foreach ($instance in $SqlInstance) {
			Write-Verbose "Connecting to $instance"
			try {
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $Credential
				
			}
			catch {
				Write-Warning "Can't connect to $instance"
				Continue
			}
			
			$dbs = $server.Databases
			
			if ($databases.count -gt 0) {
				$dbs = $dbs | Where-Object { $databases -contains $_.DatabaseSnapshotBaseName }
			}
			
			if ($snapshots.count -gt 0) {
				$dbs = $dbs | Where-Object { $snapshots -contains $_.Name }
			}
			
			if ($snapshots.count -eq 0 -and $databases.count -eq 0) {
				$dbs = $dbs | Where-Object IsDatabaseSnapshot -eq $true | Sort-Object DatabaseSnapshotBaseName, Name
			}
			
			
			foreach ($db in $dbs) {
				$object = [PSCustomObject]@{
					Server = $server.name
					Database = $db.name
					SnapshotOf = $db.DatabaseSnapshotBaseName
					SizeMB = [Math]::Round($db.Size, 2)
					DatabaseCreated = $db.createDate
					SnapshotDb = $db
				}
				
				Select-DefaultView -InputObject $object -Property Server, Database, SnapshotOf, SizeMB, DatabaseCreated
			}
		}
	}
}
