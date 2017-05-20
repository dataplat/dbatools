#ValidationTags#FlowControl#
Function Get-DbaDatabaseSnapshot
{
<#
.SYNOPSIS
Get database snapshots with details

.DESCRIPTION
Retrieves the list of database snapshot available, along with their base (the db they are the snapshot of) and creation time

.PARAMETER SqlInstance 
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Database
Return information for only specific databases

.PARAMETER Exclude
The database(s) to exclude - this list is autopopulated from the server

.PARAMETER Snapshot
Return information for only specific snapshots
	
.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Snapshot
Author: niphlod

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0


.LINK
 https://dbatools.io/Get-DbaDatabaseSnapshot

.EXAMPLE
Get-DbaDatabaseSnapshot -SqlInstance sqlserver2014a

Returns a custom object displaying Server, Database, DatabaseCreated, SnapshotOf, SizeMB, DatabaseCreated

.EXAMPLE
Get-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting

Returns information for database snapshots having HR and Accounting as base dbs

.EXAMPLE
Get-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Snapshot HR_snapshot, Accounting_snapshot

Returns information for database snapshots HR_snapshot and Accounting_snapshot

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$Exclude,
		[switch]$Silent
	)

	process
	{
		foreach ($instance in $SqlInstance)
		{
			Write-Message -Level Verbose -Message "Connecting to $instance"
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $Credential
			} catch {
				Stop-Function -Message "Failed to connect to: $instance" -InnerErrorRecord $_ -Target $instance -Continue -Silent $Silent
			}
			
			$dbs = $server.Databases 

			if ($database) {
				$dbs = $dbs | Where-Object { $databases -contains $_.DatabaseSnapshotBaseName }
			}
			if ($snapshot) {
				$dbs = $dbs | Where-Object { $snapshot -contains $_.Name }
			}
			if (!$snapshot -and !$database) {
				$dbs = $dbs | Where-Object IsDatabaseSnapshot -eq $true | Sort-Object DatabaseSnapshotBaseName, Name
			}
			
			if ($exclude) {
				$dbs = $dbs | Where-Object { $exclue -notcontains $_.DatabaseSnapshotBaseName }
			}
			
			foreach ($db in $dbs)
			{
				$object = [PSCustomObject]@{
					ComputerName = $server.NetName
					InstanceName = $server.ServiceName
					SqlInstance = $server.DomainInstanceName
					Database = $db.name
					SnapshotOf = $db.DatabaseSnapshotBaseName
					SizeMB = [Math]::Round($db.Size,2) ##FIXME, should use the stats for sparse files
					DatabaseCreated = [dbadatetime]$db.createDate
					SnapshotDb = $db
				}
				
				Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, Database, SnapshotOf, SizeMB, DatabaseCreated
			}
		}
	}
}

