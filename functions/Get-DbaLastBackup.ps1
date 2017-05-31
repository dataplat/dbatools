function Get-DbaLastBackup {
	<#
.SYNOPSIS
Get date/time for last known backups

.DESCRIPTION
Retrieves and compares the date/time for the last known backups, as well as the creation date/time for the database.

Default output includes columns Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated.

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Database
The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is autopopulated from the server

.PARAMETER Simple
Shows concise information including Server name, Database name, and the date the last time backups were performed

.NOTES
Tags: DisasterRecovery, Backup
Author: Klaas Vandenberghe ( @PowerDBAKlaas )

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
 https://dbatools.io/Get-DbaLastBackup

.EXAMPLE
Get-DbaLastBackup -SqlInstance ServerA\sql987

Returns a custom object displaying Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated

.EXAMPLE
Get-DbaLastBackup -SqlInstance ServerA\sql987 -Simple

Returns a custom object with Server name, Database name, and the date the last time backups were performed

.EXAMPLE
Get-DbaLastBackup -SqlInstance ServerA\sql987 | Out-Gridview

Returns a gridview displaying Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated

#>
	[CmdletBinding()]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[switch]$Simple
	)

	process {
		foreach ($instance in $SqlInstance) {
			Write-Verbose "Connecting to $instance"
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Write-Warning "Can't connect to $instance"
				Continue
			}

			$dbs = $server.Databases | Where-Object { $_.name -ne 'TempDb' }

			if ($Database) {
				$dbs = $dbs | Where-Object Name -In $Database
			}

			if ($ExcludeDatabase) {
				$dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
			}

			foreach ($db in $dbs) {
				$result = $null
				Write-Verbose "Processing $db on $instance"

				if ($db.IsAccessible -eq $false) {
					Write-Warning "The database $db on server $instance is not accessible. Skipping database."
					Continue
				}
				# To avoid complicated manipulations on datetimes depending on locale settings and culture,
				# dates are compared to 0, which represents 1/01/0001 0:00:00
				$SinceFull = if ($db.LastBackupdate -eq 0) { "" }
				else { (New-TimeSpan -Start $db.LastBackupdate).Tostring() }
				$SinceFull = if ($db.LastBackupdate -eq 0) { "" }
				else { $SinceFull.split('.')[0 .. ($SinceFull.split('.').count - 2)] -join ' days ' }

				$SinceDiff = if ($db.LastDifferentialBackupDate -eq 0) { "" }
				else { (New-TimeSpan -Start $db.LastDifferentialBackupDate).Tostring() }
				$SinceDiff = if ($db.LastDifferentialBackupDate -eq 0) { "" }
				else { $SinceDiff.split('.')[0 .. ($SinceDiff.split('.').count - 2)] -join ' days ' }

				$SinceLog = if ($db.LastLogBackupDate -eq 0) { "" }
				else { (New-TimeSpan -Start $db.LastLogBackupDate).Tostring() }
				$SinceLog = if ($db.LastLogBackupDate -eq 0) { "" }
				else { $SinceLog.split('.')[0 .. ($SinceLog.split('.').count - 2)] -join ' days ' }

				$daysSinceDbCreated = (New-TimeSpan -Start $db.createDate).Days

				if ($daysSinceDbCreated -lt 1 -and $db.LastBackupDate -eq 0) { $Status = 'New database, not backed up yet' }
				elseif ((New-TimeSpan -Start $db.LastBackupDate).Days -gt 0 -and (New-TimeSpan -Start $db.LastDifferentialBackupDate).Days -gt 0) { $Status = 'No Full or Diff Back Up in the last day' }
				elseif ($db.RecoveryModel -eq "Full" -and (New-TimeSpan -Start $db.LastLogBackupDate).Hours -gt 0) { $Status = 'No Log Back Up in the last hour' }
				else { $Status = 'OK' }

				$result = [PSCustomObject]@{
					ComputerName       = $server.NetName
					InstanceName       = $server.ServiceName
					SqlInstance        = $server.DomainInstanceName
					Database           = $db.name
					RecoveryModel      = $db.recoverymodel
					LastFullBackup     = if ($db.LastBackupdate -eq 0) { $null } else { $db.LastBackupdate.tostring() }
					LastDiffBackup     = if ($db.LastDifferentialBackupDate -eq 0) { $null } else { $db.LastDifferentialBackupDate.tostring() }
					LastLogBackup      = if ($db.LastLogBackupDate -eq 0) { $null } else { $db.LastLogBackupDate.tostring() }
					SinceFull          = $SinceFull
					SinceDiff          = $SinceDiff
					SinceLog           = $SinceLog
					DatabaseCreated    = $db.createDate
					DaysSinceDbCreated = $daysSinceDbCreated
					Status             = $status
				}
				if ($Simple) {
					$result | Select-Object ComputerName, InstanceName, Database, LastFullBackup, LastDiffBackup, LastLogBackup
				}
				else {
					$result
				}
			}
		}
	}
}