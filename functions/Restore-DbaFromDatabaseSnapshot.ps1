#ValidationTags#FlowControl#
Function Restore-DbaFromDatabaseSnapshot
{
<#
.SYNOPSIS
Restores databases from snapshots

.DESCRIPTION
Restores the database from the snapshot, discarding every modification made to the database
NB: Restoring to a snapshot will result in every other snapshot of the same database to be dropped
It also fixes some long-standing bugs in SQL Server when restoring from snapshots

.PARAMETER SqlInstance
The SQL Server that you're connecting to

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Restores from the last snapshot databases with this names only
NB: you can pass either Databases or Snapshots

.PARAMETER Snapshots
Restores databases from snapshots with this names only
NB: you can pass either Databases or Snapshots

.PARAMETER Force
If restoring from a snapshot involves dropping any other shapshot, you need to explicitly
use -Force to let this command delete the ones not involved in the restore process.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages


.NOTES
Tags: DisasterRecovery, Snapshot, Backup, Restore
Author: niphlod

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0


.LINK
 https://dbatools.io/Restore-DbaFromDatabaseSnapshot

.EXAMPLE
Restore-DbaFromDatabaseSnapshot -SqlServer sqlserver2014a -Databases HR, Accounting

Restores HR and Accounting databases using the latest snapshot available

.EXAMPLE
Restore-DbaFromDatabaseSnapshot -SqlServer sqlserver2014a -Snapshots HR_snap_20161201, Accounting_snap_20161101

Restores databases from snapshots named HR_snap_20161201 and Accounting_snap_20161101

#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PsCredential]$Credential,
		[switch]$Force,
		[switch]$Silent
	)

	DynamicParam
	{
		if ($SqlInstance)
		{
			Get-ParamSqlSnapshotsAndDatabases -SqlServer $SqlInstance[0] -SqlCredential $Credential
		}
	}

	begin
	{
		$databases = $psboundparameters.Databases
		$snapshots = $psboundparameters.Snapshots
	}

	process
	{
		if ($snapshots.count -eq 0 -and $databases.count -eq 0) {
			Stop-Function -Message "You must specify either -Snapshots (to restore from) or -Databases (to restore to)"
		}

		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Connecting to $instance"
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $Credential
			} catch {
				Stop-Function -Message "Failed to connect to: $instance" -InnerErrorRecord $_ -Target $instance -Continue -Silent $Silent
			}

			$all_dbs = $server.Databases

			# vault to hold all programmed operations from --> to
			$operations = @()

			if ($snapshots.count -eq 0 -and $databases.count -eq 0) {
				# Restore all databases from the latest snapshot
				Write-Message -Level Verbose -Message "Selected all databases"
				$dbs = $all_dbs | Where-Object IsDatabaseSnapshot -eq $true
			} elseif ($databases.count -gt 0) {
				# Restore only these databases from their latest snapshot
				Write-Message -Level Verbose -Message "Selected only databases"
				$dbs = $all_dbs | Where-Object { $databases -contains $_.DatabaseSnapshotBaseName }
			} elseif ($snapshots.count -gt 0) {
				# Restore databases from these snapshots
				Write-Message -Level Verbose -Message "Selected only snapshots"
				$dbs = $all_dbs | Where-Object { $snapshots -contains $_.Name }
				$base_databases = $dbs | Select-Object -ExpandProperty DatabaseSnapshotBaseName | Get-Unique
				if($base_databases.count -ne $snapshots.count) {
					Write-Message -Level Warning -Message "Multiple snapshots selected for the same database, skipping" -Continue
				}
			}

			$opshash = @{}

			foreach($db in $dbs) {
				if($db.DatabaseSnapshotBaseName -notin $opshash.Keys) {
					if($snapshots.count -gt 0) {
						# just in the need to drop every other snapshot
						$todrop = $all_dbs | Where-Object {$_.DatabaseSnapshotBaseName -eq $db.DatabaseSnapshotBaseName}
						$todrop = $todrop | Select-Object Name
						$opshash[$db.DatabaseSnapshotBaseName] = @{
							'from' = $db | Select-Object Name, DatabaseSnapshotBaseName, CreateDate
							'drop' = $todrop
						}
					} else {
						$opshash[$db.DatabaseSnapshotBaseName] = @{
							'from' = $db
							'drop' = @()
						}
					}
				} else {
					# store each older snapshot in the drop list while enumerating
					if($db.createDate -gt $opshash[$db.DatabaseSnapshotBaseName]['from'].CreateDate) {
						$prev = $opshash[$db.DatabaseSnapshotBaseName]['from']
						$opshash[$db.DatabaseSnapshotBaseName]['from'] = $db | Select-Object Name, DatabaseSnapshotBaseName, CreateDate
						$opshash[$db.DatabaseSnapshotBaseName]['drop'] += $prev
					}
				}
			}
			foreach($dbname in $opshash.Keys) {
				$drop = @()
				foreach($todrop in $opshash[$dbname]['drop']) {
					$drop += $todrop.Name
				}
				$operations += @{
					'from' = $opshash[$dbname]['from'].Name
					'to'   = $dbname
					'drop' = $drop
				}
			}

			foreach($op in $operations) {
				# Check if there are FS, because then a restore is not possible
				$all_FS = $server.Databases[$op['to']].FileGroups | Where-Object FileGroupType -eq 'FileStreamDataFileGroup'
				if($all_FS.Count -gt 0) {
					Write-Message -Level Warning -Message "Database $($op['to']) has FileStream group(s). You cannot restore from snapshots"
					[PSCustomObject]@{
						Server   = $Server.Name
						Database = $op['to']
						Status   = 'Error'
						Notes    = "Database $($op['to']) has FileStream group(s). You cannot restore from snapshots"
					}
					break
				}
				# Get log size and autogrowth
				$orig_logproperties = $server.Databases[$op['to']].LogFiles | Select-Object id, size
				# Drop what needs to be dropped
				$operror = $false
				
				if($op['drop'].count -gt 1 -and $Force -eq $false) {
					$warnmsg = @()
					$warnmsg += "The restore process for $($op['to']) from $($op['from']) needs to drop the following:"
					foreach($db in $op['drop']) {
						$warnmsg += $db
					}
					$warnmsg += "Use -Force if you really want to drop these snapshots."
					Write-Message -Level Warning -Message ($warnmsg -join "`n")
					break
				}
				foreach($drop in $op['drop'])
				{
					If ($Pscmdlet.ShouldProcess($server.name, "Remove db snapshot $drop"))
					{
						# SKIP IT IF IT'S THE SAME NAME
						if ($drop -ne $($op['from']))
						{
							$dropped = Remove-SqlDatabase -SqlServer $server -DBName $drop -SqlCredential $Credential
							if ($dropped -notmatch "Success")
							{
								Write-Message -Level Warning -Message $dropped
								$operror = $true
								break
							}
						}
					}
				}
				if($operror) {
					Write-Message -Level Warning -Message "Errors trying to restore $($op['to']) from $($op['from'])"
					[PSCustomObject]@{
						SqlInstance = $Server.DomainInstanceName
						Database    = $op['to']
						Status      = 'Error'
						Notes       = "Failed to drop some snapshots"
					}
					break
				}

				# Need a proper restore now
				If ($Pscmdlet.ShouldProcess($server.DomainInstanceName, "Restore db $($op['to']) from $($op['from'])"))
				{
					$query = "RESTORE DATABASE [$($op['to'])] FROM DATABASE_SNAPSHOT='$($op['from'])'"
					try {
						$server.KillAllProcesses($op['to'])
						$server.ConnectionContext.ExecuteScalar($query)
					} catch {
						$operror = $true
						$inner = $_.Exception.Message
						Stop-Function -Message "Original exception: $inner, Query issued: $query" -ErrorRecord $_
					}
				}
				if($operror) {
					Write-Message -Level Warning "Errors trying to restore $($op['to']) from $($op['from'])"
					[PSCustomObject]@{
						SqlInstance   = $Server.DomainInstanceName
						Database      = $op['to']
						Status        = 'Error'
						Notes         = ''
					}
					break
				}
				# Comparing sizes before and after, need to reconnect to see if size
				# changed
				$server =  Connect-SqlInstance -SqlInstance $instance -SqlCredential $Credential
				foreach($log in $server.Databases[$op['to']].LogFiles)
				{
					$matching = $orig_logproperties | Where-Object ID -eq $log.ID
					if($matching.Size -ne $orig_logproperties.Size)
					{
						Write-Message -Level Verbose -Message "Resizing log to the original value"
						$log.Size = $matching.Size
						$log.Alter()
					}
				}
				[PSCustomObject]@{
					SqlInstance   = $Server.DomainInstanceName
					Database      = $op['to']
					Status        = 'Restored'
					Notes         = 'Remember to take a backup now, and also to remove the snapshot if not needed'
				}
			}
		}
	}
}

