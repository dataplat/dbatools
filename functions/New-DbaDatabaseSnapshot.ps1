Function New-DbaDatabaseSnapshot
{
<#
.SYNOPSIS
Creates database snapshots

.DESCRIPTION
Creates database snapshots without hassles

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER AllDatabases
Creates snapshot for all eligible databases
	
.PARAMETER Databases
Creates snapshot for only specific databases

.PARAMETER Name
When you pass a simple string, it'll be appended to use it to build the name of the snapshot. By default snapshots are created with yyyyMMdd_HHmmss suffix
You can also pass a standard placeholder, in which case it'll be interpolated (e.g. '{0}' gets replaced with the database name)

.PARAMETER Path
Snapshot files will be created here (by default the filestructure will be created in the same folder as the base db)

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER Force
Databases with Filestream FG can be snapshotted, but the Filestream FG is marked offline
in the snapshot. To create a "partial" snapshot, you need to pass -Force explicitely

NB: You can't then restore the Database from the newly-created snapshot.
For details, check https://msdn.microsoft.com/en-us/library/bb895334.aspx

.NOTES
Tags: DisasterRecovery, Snapshot, Restore
Author: niphlod

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/New-DbaDatabaseSnapshot

.EXAMPLE
New-DbaDatabaseSnapshot -SqlServer sqlserver2014a -Database HR, Accounting

Creates snapshot for HR and Accounting, returning a custom object displaying Server, Database, DatabaseCreated, SnapshotOf, SizeMB, DatabaseCreated, PrimaryFilePath, Status, Notes

.EXAMPLE
New-DbaDatabaseSnapshot -SqlServer sqlserver2014a -Databases HR -Name _snap

Creates snapshot named "HR_snap" for HR

.EXAMPLE
New-DbaDatabaseSnapshot -SqlServer sqlserver2014a -Databases HR -Name 'fool_{0}_snap'

Creates snapshot named "fool_HR_snap" for HR

.EXAMPLE
New-DbaDatabaseSnapshot -SqlServer sqlserver2014a -Databases HR, Accounting -Path F:\snapshotpath

Creates snapshots for HR and Accounting databases, storing files under the F:\snapshotpath\ dir

#>

	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[string[]]$SqlInstance,
		[PsCredential]$Credential,
		[switch]$AllDatabases,
		[string]$Name,
		[string]$Path,
		[switch]$Force
	)

	DynamicParam
	{
		if ($SqlInstance)
		{
			return Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $Credential
		}
	}

	BEGIN
	{
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases

		$NoSupportForSnap = @('model', 'master', 'tempdb')
		# Evaluate the default suffix here for naming consistency
		$DefaultSuffix = (Get-Date -Format "yyyyMMdd_HHmmss")
		if ($Name.Length -gt 0)
		{
			#Validate if Name can be interpolated
			try
			{
				$null = $Name -f 'some_string'
			}
			catch
			{
				throw "Name parameter must be a template only containing one parameter {0}"
			}

		}

		function Resolve-SnapshotError($server)
		{
			$errhelp = ''
			$CurrentEdition = $server.Edition.toLower()
			$CurrentVersion = $server.Version.Major * 1000000 + $server.Version.Minor * 10000 + $server.Version.Build
			if ($server.Version.Major -lt 9)
			{
				$errhelp = 'Not supported before 2005'
			}
			if ($CurrentVersion -lt 12002000 -and $errhelp.Length -eq 0)
			{
				if ($CurrentEdition -notmatch '.*enterprise.*|.*developer.*|.*datacenter.*')
				{
					$errhelp = 'Supported only for Enterprise, Developer or Datacenter editions'
				}
			}
			$message = ""
			if ($errhelp.Length -gt 0)
			{
				$message += "Please make sure your version supports snapshots : ($errhelp)"
			}
			else
			{
				$message += "This module can't tell you why the snapshot creation failed. Feel free to report back to dbatools what happened"
			}
			Write-Warning $message
		}

	}


	PROCESS
	{
		if ($databases.Length -eq 0 -and $AllDatabases -eq $false -and !$smodatabase)
		{
			throw "You must specify a -AllDatabases or -Database to continue"
		}
		
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
			#Checks for path existence
			if ($Path.Length -gt 0)
			{
				if (!(Test-SqlPath -SqlServer $instance -Path $Path))
				{
					Write-Warning "'$instance' cannot access the directory '$Path'"
					Continue
				}
			}
			
			if ($AllDatabases)
			{
				$dbs = $server.Databases
			}
			
			if ($databases.count -gt 0)
			{
				$dbs = $server.Databases | Where-Object { $databases -contains $_.Name }
			}

			$sourcedbs = @()

			## double check for gotchas
			foreach ($db in $dbs)
			{
				if ($db.IsDatabaseSnapshot)
				{
					Write-Warning "'$($db.name)' is a snapshot, skipping"
				}
				elseif ($db.name -in $NoSupportForSnap)
				{
					Write-Warning "'$($db.name)' snapshots are prohibited"
				}
				else
				{
					$sourcedbs += $db
				}
			}

			foreach ($db in $sourcedbs)
			{
				if ($Name.Length -gt 0)
				{
					$SnapName = $Name -f $db.Name
					if ($SnapName -eq $Name)
					{
						#no interpolation, just append
						$SnapName = '{0}{1}' -f $db.Name, $Name
					}
				}
				else
				{
					$SnapName = "{0}_{1}" -f $db.Name, $DefaultSuffix
				}
				if ($SnapName -in $server.Databases.Name)
				{
					Write-Warning "A database named '$Snapname' already exists, skipping"
					Continue
				}
				$all_FSD = $db.FileGroups | Where-Object FileGroupType -eq 'FileStreamDataFileGroup'
				$all_MMO = $db.FileGroups | Where-Object FileGroupType -eq 'MemoryOptimizedDataFileGroup'
				$has_FSD = $all_FSD.Count -gt 0
				$has_MMO = $all_MMO.Count -gt 0
				if ($has_MMO)
				{
					Write-Warning "MEMORY_OPTIMIZED_DATA detected, snapshots are not possible"
					Continue
				}
				if ($has_FSD -and $Force -eq $false)
				{
					Write-Warning "Filestream detected, skipping. You need to specify -Force. See Get-Help for details"
					Continue
				}
				$snaptype = "db snapshot"
				if ($has_FSD)
				{
					$snaptype = "partial db snapshot"
				}
				If ($Pscmdlet.ShouldProcess($instance, "Create $snaptype '$SnapName' of '$($db.Name)'"))
				{
					$CustomFileStructure = @{ }
					$counter = 0
					foreach ($fg in $db.FileGroups)
					{
						$CustomFileStructure[$fg.Name] = @()
						if ($fg.FileGroupType -eq 'FileStreamDataFileGroup')
						{
							Continue
						}
						foreach ($file in $fg.Files)
						{
							$counter += 1
							# fixed extension is hardcoded as "ss", which seems a "de-facto" standard
							$fname = [IO.Path]::ChangeExtension($file.Filename, "ss")
							$fname = [IO.Path]::Combine((Split-Path $fname -Parent), ("{0}_{1}" -f $DefaultSuffix, (Split-Path $fname -Leaf)))

							# change path if specified
							if ($Path.Length -gt 0)
							{
								$basename = Split-Path $fname -Leaf
								# we need to avoid cases where basename is the same for multiple FG
								$basename = '{0:0000}_{1}' -f $counter, $basename
								$fname = [IO.Path]::Combine($Path, $basename)
							}
							$CustomFileStructure[$fg.Name] += @{ 'name' = $file.name; 'filename' = $fname }
						}
					}
					$SnapDB = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -ArgumentList $instance, $Snapname
					$SnapDB.DatabaseSnapshotBaseName = $db.Name
					foreach ($fg in $CustomFileStructure.Keys)
					{
						$SnapFG = New-Object -TypeName Microsoft.SqlServer.Management.Smo.FileGroup $SnapDB, $fg
						$SnapDB.FileGroups.Add($SnapFG)
						foreach ($file in $CustomFileStructure[$fg])
						{
							$SnapFile = New-Object -TypeName Microsoft.SqlServer.Management.Smo.DataFile $SnapFG, $file['name'], $file['filename']
							$SnapDB.FileGroups[$fg].Files.Add($SnapFile)
						}
					}

					# we're ready to issue a Create, but SMO is a little uncooperative here
					# there are cases we can manage and others we can't, and we need all the
					# info we can get both from testers and from users

					$sql = $SnapDB.Script()
					try
					{
						$SnapDB.Create()

						[PSCustomObject]@{
							Server = $server.name
							Database = $SnapDB.Name
							SnapshotOf = $SnapDB.DatabaseSnapshotBaseName
							SizeMB = [Math]::Round($SnapDB.Size, 2)
							DatabaseCreated = $SnapDB.createDate
							PrimaryFilePath = $SnapDB.PrimaryFilePath
							Status = 'Created'
							Notes = $null
							SnapshotDb = $SnapDB
						} | Select-DefaultView -Property Server, Database, SnapshotOf, SizeMB, DatabaseCreated, PrimaryFilePath, Status
					}
					catch
					{
						$Status = 'Created'
						# here we manage issues we DO know about, hoping that the first command
						# is always the one creating the snapshot, and give an helpful hint
						try
						{
							$server.Databases.Refresh()
							if ($SnapName -notin $server.Databases.Name)
							{
								# previous creation failed completely, snapshot is not there already
								$null = $server.ConnectionContext.ExecuteNonQuery($sql[0])
								$server.Databases.Refresh()
								$SnapDB = $server.Databases[$Snapname]
							}
							else
							{
								$SnapDB = $server.Databases[$Snapname]
							}
							$Notes = @()
							if ($db.ReadOnly -eq $true)
							{
								$Notes += 'SMO is probably trying to set a property on a read-only snapshot, run with -Debug to find out and report back'
							}
							if ($has_FSD)
							{
								$Status = 'Partial'
								$Notes += 'Filestream groups are not viable for snapshot'
							}
							$Notes = $Notes -Join ';'

							$hints = @("Executing these commands led to a partial failure")
							foreach ($stmt in $sql)
							{
								$hints += $stmt
							}
							Write-Debug ($hints -Join "`n")

							[PSCustomObject]@{
								Server = $server.name
								Database = $SnapDB.Name
								SnapshotOf = $SnapDB.DatabaseSnapshotBaseName
								SizeMB = [Math]::Round($SnapDB.Size, 2)
								DatabaseCreated = $SnapDB.createDate
								PrimaryFilePath = $SnapDB.PrimaryFilePath
								Status = $Status
								Notes = $Notes
								SnapshotDb = $SnapDB
							} | Select-DefaultView -Property Server, Database, SnapshotOf, SizeMB, DatabaseCreated, PrimaryFilePath, Status, Notes
						}
						catch
						{
							# we end up here when even the first issued command didn't create
							# a valid snapshot
							$ex = $_
							Write-Warning 'SMO failed to create the snapshot, run with -Debug to find out and report back'
							$hints = @("Executing these commands led to a failure")
							foreach ($stmt in $sql)
							{
								$hints += $stmt
							}
							Write-Exception $ex
							$inner = $_.Exception.Message
							if ($null -ne $ex.Exception.InnerException)
							{
								$inner = $ex.Exception.InnerException
							}
							if ($null -ne $inner.InnerException)
							{
								$inner = $inner.InnerException
							}
							Write-Warning "Original exception: $inner"
							Write-Debug ($hints -Join "`n")
							Resolve-SnapshotError $server
						}
					}
				}
			}
		}
	}
}
