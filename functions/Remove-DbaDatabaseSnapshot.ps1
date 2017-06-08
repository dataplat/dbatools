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

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.
	
.PARAMETER PipelineSnapshot
Internal parameter

.NOTES
Tags: Snapshot
Author: niphlod

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

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
		[string[]]$SqlInstance,
		[PsCredential]$Credential,
		[parameter(ValueFromPipeline = $true)]
		[object]$PipelineSnapshot,
		[switch]$AllSnapshots
	)
	
	DynamicParam
	{
		if ($SqlInstance)
		{
			Get-ParamSqlSnapshotsAndDatabases -SqlServer $SqlInstance[0] -SqlCredential $Credential
		}
	}
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
		$snapshots = $psboundparameters.Snapshots
	}
	
	PROCESS
	{
		if ($snapshots.count -eq 0 -and $databases.count -eq 0 -and $AllSnapshots -eq $false -and $PipelineSnapshot -eq $null)
		{
			Write-Warning "You must specify -Snapshots, -Databases or -AllSnapshots"
			return
		}
		
		# handle the database object passed by the pipeline
		if ($PipelineSnapshot.PSTypeNames -eq 'dbatools.customobject')
		{
			If ($Pscmdlet.ShouldProcess($PipelineSnapshot.SnapshotDb.Parent.name, "Remove db snapshot '$($PipelineSnapshot.SnapshotDb.Name)'"))
			{
				$dropped = Remove-SqlDatabase -SqlServer $PipelineSnapshot.SnapshotDb.Parent -DBName $PipelineSnapshot.SnapshotDb.Name
				
				if ($dropped -match "Success")
				{
					$status = "Dropped"
				}
				else
				{
					Write-Warning $dropped
					$status = "Drop failed"
				}
				
				[PSCustomObject]@{
					Server = $PipelineSnapshot.Server
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
			Write-Verbose "Connecting to $instance"
			try
			{
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $Credential
				
			}
			catch
			{
				Write-Warning "Can't connect to $instance"
				Continue
			}
			
			$dbs = $server.Databases
			
			if ($databases.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $databases -contains $_.DatabaseSnapshotBaseName }
			}
			
			if ($snapshots.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $snapshots -contains $_.Name }
			}
			
			if ($snapshots.count -eq 0 -and $databases.count -eq 0)
			{
				$dbs = $dbs | Where-Object IsDatabaseSnapshot -eq $true | Sort-Object DatabaseSnapshotBaseName, Name
			}
			
			foreach ($db in $dbs)
			{
				If ($Pscmdlet.ShouldProcess($server.name, "Remove db snapshot $($db.Name)"))
				{
					$dropped = Remove-SqlDatabase -SqlServer $server -DBName $db.Name -SqlCredential $Credential
					
					if ($dropped -match "Success")
					{
						$status = "Dropped"
					}
					else
					{
						Write-Warning $dropped
						$status = "Drop failed"
					}
					
					[PSCustomObject]@{
						Server = $server.name
						Database = $db.Name
						SnapshotOf = $db.DatabaseSnapshotBaseName
						Status = $status
					}
				}
			}
		}
	}
}
