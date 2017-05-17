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

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Snapshots
Removes snapshot databases with this names only

.PARAMETER Databases
Removes snapshots for only specific base dbs

.PARAMETER Snapshots
Removes specific snapshots

.PARAMETER AllSnapshots
Specifies that you want to remove all snapshots from the server

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
Remove-DbaDatabaseSnapshot -SqlServer sqlserver2014a

Removes all database snapshots from sqlserver2014a

.EXAMPLE
Remove-DbaDatabaseSnapshot -SqlServer sqlserver2014a -Snapshots HR_snap_20161201, HR_snap_20161101

Removes database snapshots named HR_snap_20161201 and HR_snap_20161101

.EXAMPLE
Remove-DbaDatabaseSnapshot -SqlServer sqlserver2014a -Databases HR, Accounting

Removes all database snapshots having HR and Accounting as base dbs

.EXAMPLE
Remove-DbaDatabaseSnapshot -SqlServer sqlserver2014a -Snapshots HR_snapshot, Accounting_snapshot

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
		[PsCredential]$Credential,
		[parameter(ValueFromPipeline = $true)]
		[object]$PipelineSnapshot,
		[switch]$AllSnapshots,
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
		if ($snapshots.count -eq 0 -and $databases.count -eq 0 -and $AllSnapshots -eq $false -and $null -eq $PipelineSnapshot) {
			Stop-Function -Message "You must specify -Snapshots, -Databases or -AllSnapshots"
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
			
			if ($databases.count -gt 0) {
				$dbs = $dbs | Where-Object { $databases -contains $_.DatabaseSnapshotBaseName }
			}
			if ($snapshots.count -gt 0) {
				$dbs = $dbs | Where-Object { $snapshots -contains $_.Name }
			}
			if ($snapshots.count -eq 0 -and $databases.count -eq 0) {
				$dbs = $dbs | Where-Object IsDatabaseSnapshot -eq $true | Sort-Object DatabaseSnapshotBaseName, Name
			}
			
			foreach ($db in $dbs)
			{
				If ($Pscmdlet.ShouldProcess($server.name, "Remove db snapshot $($db.Name)"))
				{
					$dropped = Remove-SqlDatabase -SqlServer $server -DBName $db.Name -SqlCredential $Credential
					if ($dropped -match "Success") {
						$status = "Dropped"
					} else {
						Write-Message -Level Warning -Message $dropped
						$status = "Drop failed"
					}
					[PSCustomObject]@{
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
