#ValidationTags#FlowControl#
Function Remove-DbaDatabaseSnapshot
{
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

.PARAMETER Snapshot
Restores databases from snapshots with this names only
NB: you can pass either Databases or Snapshots

.PARAMETER AllSnapshot
Specifies that you want to remove all snapshots from the server

.PARAMETER WhatIf
Shows what would happen if the command were to run
	
.PARAMETER Confirm
Prompts for confirmation of every step. 

.PARAMETER PipelineSnapshot
Internal parameter

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Snapshot
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
Get-DbaDatabaseSnapshot -SqlServer sql2016 | Where SnapshotOf -like '*dumpsterfire*' | Remove-DbaDatabaseSnapshot

Removes all snapshots associated with databases that have dumpsterfire in the name

#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$Snapshot,
		[parameter(ValueFromPipeline = $true)]
		[object]$PipelineSnapshot,
		[switch]$AllSnapshots,
		[switch]$Silent
	)
	
	process
	{
		if (!$snapshot -and !$databases -and !$AllSnapshots -and $null -eq $PipelineSnapshot -and !$Exclude) {
			Stop-Function -Message "You must specify -Snapshot, -Database, -Exclude or -AllSnapshots"
		}
		# handle the database object passed by the pipeline
		if ($null -ne $PipelineSnapshot -and $PipelineSnapshot.getType().Name -eq 'pscustomobject') # do we need a specialized type back ?
		{
			If ($Pscmdlet.ShouldProcess($PipelineSnapshot.SnapshotDb.Parent.DomainInstanceName, "Remove db snapshot $($PipelineSnapshot.SnapshotDb.Name)")) {
				$dropped = Remove-SqlDatabase -SqlServer $PipelineSnapshot.SnapshotDb.Parent.DomainInstanceName -DBName $PipelineSnapshot.SnapshotDb.Name -SqlCredential $Credential
				if ($dropped -match "Success") {
					$status = "Dropped"
				} else {
					Write-Message -Level Warning -Message $dropped
					$status = "Drop failed"
				}
				
				[PSCustomObject]@{
					SqlInstance = $PipelineSnapshot.SnapshotDb.Parent.DomainInstanceName
					Database = $PipelineSnapshot.Database
					SnapshotOf = $PipelineSnapshot.SnapshotOf
					Status = $status
				}
			}
			return
		}
		
		# if piped value either doesn't exist or is not the proper type
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
			if (!$snapshot -and !$databases) {
				$dbs = $dbs | Where-Object IsDatabaseSnapshot -eq $true | Sort-Object DatabaseSnapshotBaseName, Name
			}
			
			foreach ($db in $dbs)
			{
				If ($Pscmdlet.ShouldProcess($server.name, "Remove db snapshot $db"))
				{
					$dropped = Remove-SqlDatabase -SqlServer $server -DBName $db.Name -SqlCredential $Credential
					if ($dropped -match "Success") {
						$status = "Dropped"
					} else {
						Write-Message -Level Warning -Message $dropped
						$status = "Drop failed"
					}
					[PSCustomObject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						Database = $db.Name
						SnapshotOf = $db.DatabaseSnapshotBaseName
						Status = $status
					}
				}
			}
		}
	}
}

