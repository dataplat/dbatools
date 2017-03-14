Function Set-DbaDatabaseState
{
<#
.SYNOPSIS
Sets various options for databases, hereby called "states"

.DESCRIPTION
Sets some common "states" on databases:
 - "RW" options (ReadOnly, ReadWrite)
 - "Status" options (Online, Offline, Emergency, plus a special "Detached")
 - "Access" options (SingleUser, RestrictedUser, MultiUser)

Returns an object with SqlInstance, Database, RW, Status, Access, Notes

Notes gets filled when something went wrong setting the state

.PARAMETER SqlInstance
The SQL Server that you're connecting to

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Database
Sets options only on these databases

.PARAMETER Exclude
Sets options for all but these specific databases

.PARAMETER AllDatabases
This is a parameter that was included for safety, so you don't accidentally set options on all databases without specifying

.PARAMETER ReadOnly
RW Option : Sets the database as READ_ONLY

.PARAMETER ReadWrite
RW Option : Sets the database as READ_WRITE

.PARAMETER Online
Status Option : Sets the database as ONLINE

.PARAMETER Offline
Status Option : Sets the database as OFFLINE

.PARAMETER Emergency
Status Option : Sets the database as EMERGENCY

.PARAMETER Detached
Status Option : Detaches the database

.PARAMETER SingleUser
Access Option : Sets the database as SINGLE_USER

.PARAMETER RestrictedUser
Access Option : Sets the database as RESTRICTED_USER

.PARAMETER MultiUser
Access Option : Sets the database as MULTI_USER

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER Force
For most options, this translates to istantly rolling back any open transactions
that may be stopping the process.
For -Detached it is required to break mirroring and Availability Groups

.PARAMETER SmoDatabase
Internal parameter for piped objects - this will likely go away once we move to better dynamic parameters
	
.NOTES
Author: niphlod

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
https://dbatools.io/Set-DbaDatabaseState

.EXAMPLE
Set-DbaDatabaseState -SqlServer sqlserver2014a -Database HR -Offline

Sets the HR database as OFFLINE

.EXAMPLE
Set-DbaDatabaseState -SqlServer sqlserver2014a -AllDatabases -Exclude HR -Readonly -Force

Sets all databases of the sqlserver2014a instance, except for HR, as READ_ONLY

.EXAMPLE	
Get-DbaDatabaseState -SqlInstance sql2016 | Where-Object Status -eq 'Offline' | Set-DbaDatabaseState -Online
	
Finds all offline databases and sets them to online

.EXAMPLE
Set-DbaDatabaseState -SqlServer sqlserver2014a -Database HR -SingleUser

Sets the HR database as SINGLE_USER

.EXAMPLE
Set-DbaDatabaseState -SqlServer sqlserver2014a -Database HR -SingleUser -Force

Sets the HR database as SINGLE_USER, dropping all other connections (and rolling back open transactions)

#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipelineByPropertyName, ParameterSetName = "Server")]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$Credential,
		[switch]$AllDatabases,
		[switch]$ReadOnly,
		[switch]$ReadWrite,
		[switch]$Online,
		[switch]$Offline,
		[switch]$Emergency,
		[switch]$Detached,
		[switch]$SingleUser,
		[switch]$RestrictedUser,
		[switch]$MultiUser,
		[switch]$Force,
		[parameter(Mandatory = $true, ValueFromPipeline, ParameterSetName = "Database")]
		[PsCustomObject[]]$SmoDatabase
	)
	
	DynamicParam
	{
		if ($SqlInstance)
		{
			Get-ParamSqlDatabases -SqlInstance $SqlInstance[0] -SqlCredential $Credential -NoSystem
		}
	}
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
		
		function Get-WrongCombo($optset, $allparams)
		{
			$x = 0
			foreach ($opt in $optset)
			{
				if ($allparams.ContainsKey($opt)) { $x += 1 }
			}
			if ($x -gt 1)
			{
				$msg = $optset -Join ',-'
				$msg = "You can only specify one of: -" + $msg
				throw $msg
			}
		}
		
		function Edit-DatabaseState($sqlinstance, $dbname, $opt, $immediate = $false)
		{
			$warn = $null
			$sql = "ALTER DATABASE [$dbname] SET $opt"
			if ($immediate)
			{
				$sql += " WITH ROLLBACK IMMEDIATE"
			}
			else
			{
				$sql += " WITH NO_WAIT"
			}
			try
			{
				Write-Verbose $sql
				if ($immediate)
				{
					# this can be helpful only for SINGLE_USER databases
					# but since $immediate is called, it does no more harm
					# than the immediate rollback
					$sqlinstance.KillAllProcesses($dbname)
				}
				$null = $sqlinstance.ConnectionContext.ExecuteNonQuery($sql)
			}
			catch
			{
				Write-Exception $_
				$warn = "Failed to set '$dbname' to $opt"
				Write-Warning $warn
			}
			return $warn
		}
		
		$UserAccessHash = @{
			'Single' = 'SINGLE_USER'
			'Restricted' = 'RESTRICTED_USER'
			'Multiple' = 'MULTI_USER'
		}
		$ReadOnlyHash = @{
			$true = 'READ_ONLY'
			$false = 'READ_WRITE'
		}
		$StatusHash = @{
			'Offline' = 'OFFLINE'
			'Normal' = 'ONLINE'
			'EmergencyMode' = 'EMERGENCY'
		}
		
		function Get-DbState($db)
		{
			$base = [PSCustomObject]@{
				'Access' = $null
				'Status' = $null
				'RW' = $null
			}
			$base.RW = $ReadOnlyHash[$db.ReadOnly]
			$base.Access = $UserAccessHash[$db.UserAccess.toString()]
			foreach ($status in $StatusHash.Keys)
			{
				if ($db.Status -match $status)
				{
					$base.Status = $StatusHash[$status]
					break
				}
			}
			return $base
		}
		
		$RWExclusive = @('ReadOnly', 'ReadWrite')
		$StatusExclusive = @('Online', 'Offline', 'Emergency', 'Detached')
		$AccessExclusive = @('SingleUser', 'RestrictedUser', 'MultiUser')
		$allparams = $PSBoundParameters
		Get-WrongCombo -optset $RWExclusive -allparams $allparams
		Get-WrongCombo -optset $StatusExclusive -allparams $allparams
		Get-WrongCombo -optset $AccessExclusive -allparams $allparams
		
		$dbs = @()
	}
	PROCESS
	{
		# use PROCESS to gather info, and END to execute on it
		if ($databases.Length -eq 0 -and $AllDatabases -eq $false -and !$smodatabase)
		{
			throw "You must specify a -AllDatabases or -Database to continue"
		}
		
		if ($smodatabase)
		{
			$dbs += $smodatabase.Database
		}
		else
		{
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
				$all_dbs = $server.Databases
				$dbs += $all_dbs | Where-Object { @('master', 'model', 'msdb', 'tempdb', 'distribution') -notcontains $_.Name }
				
				if ($databases.count -gt 0)
				{
					$dbs = $dbs | Where-Object { $databases -contains $_.Name }
				}
				if ($exclude.count -gt 0)
				{
					$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
				}
			}
		}
	}
	
	END
	{
		if ($Detached -eq $true)
		{
			# we need to see what snaps are on the server, as base databases cannot be dropped
			$snaps = $dbs | Where-Object { $_.DatabaseSnapshotBaseName.Length -gt 0 }
			$snaps = $snaps | Select-Object -ExpandProperty DatabaseSnapshotBaseName | Get-Unique
		}
		
		# need to pick up here
		foreach ($db in $dbs)
		{
			$db_status = Get-DbState $db
			
			# normalizing properties returned by SMO to something more "fixed"
			$warn = @()
			
			if ($db.DatabaseSnapshotBaseName.Length -gt 0)
			{
				Write-Warning "Database $db is a snapshot, skipping"
				Continue
			}
			
			if (!$Force)
			{
				if ($ReadOnly, $Offline, $Emergency, $SingleUser, $RestrictedUser, $Detached -contains $true)
				{
					if (Get-DbaProcess -SqlServer $server -SqlCredential $Credential -Databases $db.name)
					{
						Write-Warning "Users are currently connected to the database $db and Force was not specified. Skipping."
						continue
					}
				}
			}
			
			if ($ReadOnly -eq $true)
			{
				if ($db_status.RW -eq 'READ_ONLY')
				{
					Write-Verbose "Database $db is already READ_ONLY"
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($instance, "Set $db to READ_ONLY"))
					{
						Write-Verbose "Setting database $db to READ_ONLY"
						$warn += Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "READ_ONLY" -immediate $Force
					}
				}
			}
			
			if ($ReadWrite -eq $true)
			{
				if ($db_status.RW -eq 'READ_WRITE')
				{
					Write-Verbose "Database $db is already READ_WRITE"
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($instance, "Set $db to READ_WRITE"))
					{
						Write-Verbose "Setting database $db to READ_WRITE"
						$warn += Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "READ_WRITE" -immediate $Force
					}
				}
			}
			
			if ($Online -eq $true)
			{
				if ($db_status.Status -eq 'ONLINE')
				{
					Write-Verbose "Database $db is already ONLINE"
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($instance, "Set $db to ONLINE"))
					{
						Write-Verbose "Setting database $db to ONLINE"
						$warn += Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "ONLINE" -immediate $Force
					}
				}
			}
			
			if ($Offline -eq $true)
			{
				if ($db_status.Status -eq 'OFFLINE')
				{
					Write-Verbose "Database $db is already OFFLINE"
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($instance, "Set $db to OFFLINE"))
					{
						Write-Verbose "Setting database $db to OFFLINE"
						$warn = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "OFFLINE" -immediate $Force
					}
				}
			}
			
			if ($Emergency -eq $true)
			{
				if ($db_status.Status -eq 'EMERGENCY')
				{
					Write-Verbose "Database $db is already EMERGENCY"
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($instance, "Set $db to EMERGENCY"))
					{
						Write-Verbose "Setting database $db to EMERGENCY"
						$warn += Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "EMERGENCY" -immediate $Force
					}
				}
			}
			
			if ($SingleUser -eq $true)
			{
				if ($db_status.Access -eq 'SINGLE_USER')
				{
					Write-Verbose "Database $db is already SINGLE_USER"
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($instance, "Set $db to SINGLE_USER"))
					{
						Write-Verbose "Setting $db to SINGLE_USER"
						$warn += Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "SINGLE_USER" -immediate $Force
					}
				}
			}
			
			if ($RestrictedUser -eq $true)
			{
				if ($db_status.Access -eq 'RESTRICTED_USER')
				{
					Write-Verbose "Database $db is already RESTRICTED_USER"
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($instance, "Set $db to RESTRICTED_USER"))
					{
						Write-Verbose "Setting $db to RESTRICTED_USER"
						$warn += Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "RESTRICTED_USER" -immediate $Force
					}
				}
			}
			
			if ($MultiUser -eq $true)
			{
				if ($db_status.Access -eq 'MULTI_USER')
				{
					Write-Verbose "Database $db is already MULTI_USER"
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($instance, "Set $db to MULTI_USER"))
					{
						Write-Verbose "Setting $db to MULTI_USER"
						$warn += Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "MULTI_USER" -immediate $Force
					}
				}
			}
			
			# Refresh info about database state here (before detaching)
			$db.Refresh()
			
			if ($Detached -eq $true)
			{
				if ($db.Name -in $snaps)
				{
					Write-Warning "Database $db has snapshots, you need to drop them before detaching, skipping..."
					Continue
				}
				if ($db.IsMirroringEnabled -eq $true -or $db.AvailabilityGroupName.Length -gt 0)
				{
					if ($Force -eq $false)
					{
						Write-Warning "Needs -Force to detach $db, skipping"
						Continue
					}
				}
				
				if ($db.IsMirroringEnabled)
				{
					If ($Pscmdlet.ShouldProcess($instance, "Break mirroring for $db"))
					{
						try
						{
							$db.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
							$db.Alter()
							$db.Refresh()
							Write-Verbose "Broke mirroring for $db"
						}
						catch
						{
							Write-Warning "Could not break mirror for $db. Skipping."
							Write-Exception $_
							Continue
						}
					}
				}
				
				if ($database.AvailabilityGroupName.Length -gt 0)
				{
					$agname = $db.AvailabilityGroupName
					If ($Pscmdlet.ShouldProcess($instance, "Removing $db from AG [$agname]"))
					{
						try
						{
							$server.AvailabilityGroups[$db.AvailabilityGroupName].AvailabilityDatabases[$db.Name].Drop()
							Write-Verbose "Successfully removed $db from AG [$agname] on $server"
						}
						catch
						{
							Write-Warning "Could not remove $db from AG [$agname] on $server"
							Write-Exception $_
							Continue
						}
					}
				}
				
				# DBA 101 should encourage detaching just OFFLINE databases
				# we can do that here
				If ($Pscmdlet.ShouldProcess($instance, "Detaching $db"))
				{
					if ($db_status.Status -ne 'OFFLINE')
					{
						$opstatus = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "OFFLINE" -immediate $true
					}
					try
					{
						$sql = "EXEC master.dbo.sp_detach_db N$db"
						Write-Verbose $sql
						$null = $server.ConnectionContext.ExecuteNonQuery($sql)
						$newstate.Status = 'DETACHED'
					}
					catch
					{
						Write-Exception $_
						Write-Warning "Failed to detach $db"
						$warn += "Failed to detach"
					}
				}
				
			}
			if ($warn.Count -gt 0)
			{
				$warn = $warn | Get-Unique
				$warn = $warn -Join ';'
			}
			else
			{
				$warn = $null
			}
			
			$db.Refresh()
			$newstate = Get-DbState $db
			
			[PSCustomObject]@{
				SqlInstance = $server.Name
				InstanceName = $server.ServiceName
				ComputerName = $server.NetName
				DatabaseName = $db.Name
				RW = $newstate.RW
				Status = $newstate.Status
				Access = $newstate.Access
				Notes = $warn
				Database = $db
			} | Select-DefaultView -ExcludeProperty Database
		}
	}
	
}
