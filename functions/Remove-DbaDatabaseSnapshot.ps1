#ValidationTags#FlowControl#
function Remove-DbaDatabaseSnapshot {
	<#
.SYNOPSIS
Removes database snapshots

.DESCRIPTION
Removes (drops) database snapshots from the server

.PARAMETER SqlInstance
The SQL Server that you're connecting to

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Database
Restores from the last snapshot databases with this names only
NB: you can pass either Databases or Snapshots

.PARAMETER ExcludeDatabase
Processes all databases excepting the these 
NB: you can pass either Databases or Snapshots

.PARAMETER Snapshot
Restores databases from snapshots with this names only
NB: you can pass either Databases or Snapshots

.PARAMETER AllSnapshots
Specifies that you want to remove all snapshots from the server

.PARAMETER Force
Will forcibly kill all running queries that prevent the drop process.

.PARAMETER WhatIf
Shows what would happen if the command were to run

.PARAMETER Confirm
Prompts for confirmation of every step.

.PARAMETER PipelineSnapshot
Internal parameter

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Snapshot, Database
Author: niphlod

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
 https://dbatools.io/Remove-DbaDatabaseSnapshot

.EXAMPLE
Remove-DbaDatabaseSnapshot -SqlInstance sqlserver2014a

Removes all database snapshots from sqlserver2014a

.EXAMPLE
Remove-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Snapshot HR_snap_20161201, HR_snap_20161101

Removes database snapshots named HR_snap_20161201 and HR_snap_20161101

.EXAMPLE
Remove-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting

Removes all database snapshots having HR and Accounting as base dbs

.EXAMPLE
Remove-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Snapshot HR_snapshot, Accounting_snapshot

Removes HR_snapshot and Accounting_snapshot

.EXAMPLE
Get-DbaDatabaseSnapshot -SqlInstance sql2016 | Where SnapshotOf -like '*dumpsterfire*' | Remove-DbaDatabaseSnapshot

Removes all snapshots associated with databases that have dumpsterfire in the name

#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $false, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[object[]]$Snapshot,
		[parameter(ValueFromPipeline = $true)]
		[object]$PipelineSnapshot,
		[switch]$AllSnapshots,
		[switch]$Force,
		[switch]$Silent
	)

	process {
		if (!$Snapshot -and !$Database -and !$AllSnapshots -and $null -eq $PipelineSnapshot -and !$ExcludeDatabase) {
			Stop-Function -Message "You must specify -Snapshot, -Database, -Exclude or -AllSnapshots"
			return
		}
		# handle the database object passed by the pipeline
		# do we need a specialized type back ?
		if ($null -ne $PipelineSnapshot -and $PipelineSnapshot.getType().Name -eq 'pscustomobject') {
			if ($Pscmdlet.ShouldProcess($PipelineSnapshot.SnapshotDb.Parent.DomainInstanceName, "Remove db snapshot $($PipelineSnapshot.SnapshotDb.Name)")) {
				try {
					$server = Connect-SqlInstance -SqlInstance $PipelineSnapshot.SnapshotDb.Parent.DomainInstanceName -SqlCredential $Credential
				} catch {
					Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
				}
				try {
					if ($Force) {
						$server.KillAllProcesses($PipelineSnapshot.SnapshotDb.Name)
					}
					$null = $server.ConnectionContext.ExecuteNonQuery("drop database [$($PipelineSnapshot.SnapshotDb.Name)]")
					$status = "Dropped"
				} catch {
					Write-Message -Level Warning -Message $_
					$status = "Drop failed"
				}

				[PSCustomObject]@{
					SqlInstance = $PipelineSnapshot.SnapshotDb.Parent.DomainInstanceName
					Database    = $PipelineSnapshot.Database
					SnapshotOf  = $PipelineSnapshot.SnapshotOf
					Status      = $status
				}
			}
			return
		}

		# if piped value either doesn't exist or is not the proper type
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Connecting to $instance"
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $Credential
			} catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			

			$dbs = $server.Databases

			if ($Database) {
				$dbs = $dbs | Where-Object { $Databases -contains $_.DatabaseSnapshotBaseName }
			}
			if ($ExcludeDatabase) {
				$dbs = $dbs | Where-Object { $ExcludeDatabase -notcontains $_.DatabaseSnapshotBaseName }
			}
			if ($Snapshot) {
				$dbs = $dbs | Where-Object { $Snapshot -contains $_.Name }
			}
			if (!$Snapshot -and !$Database) {
				$dbs = $dbs | Where-Object IsDatabaseSnapshot -eq $true | Sort-Object DatabaseSnapshotBaseName, Name
			}

			foreach ($db in $dbs) {
				if ($db.IsAccessible -eq $false) {
					Write-Message -Level Warning -Message "Database $db is not accessible."
					continue
				}
				If ($Pscmdlet.ShouldProcess($server.name, "Remove db snapshot $db")) {
					try {
						if ($Force) {
							# cannot drop the snapshot if someone is using it
							$server.KillAllProcesses($db)
						}
						$null = $server.ConnectionContext.ExecuteNonQuery("drop database $db")
						$status = "Dropped"
					} catch {
						Write-Message -Level Warning -Message $_
						$status = "Drop failed"
					}
					[PSCustomObject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance  = $server.DomainInstanceName
						Database     = $db.Name
						SnapshotOf   = $db.DatabaseSnapshotBaseName
						Status       = $status
					}
				}
			}
		}
	}
}

