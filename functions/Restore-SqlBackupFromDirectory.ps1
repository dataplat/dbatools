Function Restore-SqlBackupFromDirectory
{
<# 
.SYNOPSIS 
Restores SQL Server databases from the backup directory structure created by Ola Hallengren's database maintenance scripts. Different structures coming soon.

.DESCRIPTION 
Many SQL Server database administrators use Ola Hallengren's SQL Server Maintenance Solution which can be found at http://ola.hallengren.com
Hallengren uses a predictable backup structure which made it relatively easy to create a script that can restore an entire SQL Server database instance, down to the master database (next version), to a new server. This script is intended to be used in the event that the originating SQL Server becomes unavailable, thus rendering my other SQL restore script (http://goo.gl/QmfQ6s) ineffective.

.PARAMETER ServerName
Required. The SQL Server to which you will be restoring the databases.

.PARAMETER Path
Required. The directory that contains the database backups (ex. \\fileserver\share\sqlbackups\SQLSERVERA)

.PARAMETER ReuseSourceFolderStructure
Restore-SqlBackupFromDirectory will restore to the default user data and log directories, unless this switch is used. Useful if you're restoring from a server that had a complex db file structure.

.PARAMETER Databases
Migrates ONLY specified databases. This list is auto-populated for tab completion.

.PARAMETER Exclude
Excludes specified databases from migration. This list is auto-populated for tab completion.

.PARAMETER Force
Will overwrite any existing databases on $SqlServer. 

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$cred = Get-Credential, this pass this $cred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.NOTES 
Author  : Chrissy LeMaire, netnerds.net
Requires: sysadmin access on destination SQL Server.

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.


.LINK 
https://dbatools.io/Restore-SqlBackupFromDirectory

.EXAMPLE   
Restore-SqlBackupFromDirectory -ServerName sqlcluster -Path \\fileserver\share\sqlbackups\SQLSERVER2014A

Description

All user databases contained within \\fileserver\share\sqlbackups\SQLSERVERA will be restored to sqlcluster, down the most recent full/differential/logs.

#>	
	#Requires -Version 3.0
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[string]$SqlServer,
		[parameter(Mandatory = $true)]
		[string]$Path,
		[switch]$NoRecovery,
		[Alias("ReuseFolderStructure")]
		[switch]$ReuseSourceFolderStructure,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$Force
		
	)
	
	DynamicParam
	{
		
		if ($Path)
		{
			$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
			$paramattributes = New-Object System.Management.Automation.ParameterAttribute
			$paramattributes.ParameterSetName = "__AllParameterSets"
			$paramattributes.Mandatory = $false
			$systemdbs = @("master", "msdb", "model", "SSIS")
			$dblist = (Get-ChildItem -Path $Path -Directory).Name | Where-Object { $systemdbs -notcontains $_ }
			$argumentlist = @()
			
			foreach ($db in $dblist)
			{
				$argumentlist += [Regex]::Escape($db)
			}
			
			$validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $argumentlist
			$combinedattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
			$combinedattributes.Add($paramattributes)
			$combinedattributes.Add($validationset)
			$Databases = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Databases", [String[]], $combinedattributes)
			$Exclude = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Exclude", [String[]], $combinedattributes)
			$newparams.Add("Databases", $Databases)
			$newparams.Add("Exclude", $Exclude)
			return $newparams
		}
	}
	
	BEGIN {
	
		if (!([string]::IsNullOrEmpty($Path)))
		{
			if (!($Path.StartsWith("\\")))
			{
				throw "Path must be a valid UNC path (\\server\share)."
			}
			
			if (!(Test-Path $Path))
			{
				throw "$Path does not exist or cannot be accessed."
			}
		}
		
		Write-Output "Attempting to connect to SQL Server.."
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
		$server.ConnectionContext.StatementTimeout = 0
		
		if ($server.versionMajor -lt 8 -and $server.versionMajor -lt 8)
		{
			throw "This script can only be run on SQL Server 2000 and above. Quitting."
		}
		
		if ($server.versionMajor -eq 8 -and $IncludeSystemDbs)
		{
			throw "Migrating system databases not supported in SQL Server 2000."
		}
		
		# Convert from RuntimeDefinedParameter  object to regular array
		$Databases = $psboundparameters.Databases
		$Exclude = $psboundparameters.Exclude
	
	}
	PROCESS
	
	{
		
		$dblist = @(); $skippedb = @{ }; $migrateddb = @{ };
		$systemdbs = @("master", "msdb", "model")
		
		
		$subdirectories = (Get-ChildItem -Directory $Path).FullName
		foreach ($subdirectory in $subdirectories)
		{
			if ((Get-ChildItem $subdirectory).Name -eq "FULL") { $dblist += $subdirectory; continue }
		}
		
		if ($dblist.count -eq 0)
		{
			throw "No databases to restore. Did you use the correct file path? Format should be \\fileshare\share\sqlbackups\sqlservername"
		}
		
		foreach ($db in $dblist)
		{
			$full = Get-ChildItem "$db\FULL\*.bak" | sort LastWriteTime | select -last 1
			$since = $full.LastWriteTime; $full = $full.FullName
			
			$diff = $null; $logs = $null
			if (Test-Path  "$db\DIFF")
			{
				$diff = Get-ChildItem "$db\DIFF\*.bak" | Where { $_.LastWriteTime -gt $since } | sort LastWriteTime | select -last 1
				$since = $diff.LastWriteTime; $diff = $diff.fullname
			}
			if (Test-Path  "$db\LOG")
			{
				$logs = (Get-ChildItem "$db\LOG\*.trn" | Where { $_.LastWriteTime -gt $since })
				$logs = ($logs | Sort-Object LastWriteTime).Fullname
			}
			
			$restore = New-Object "Microsoft.SqlServer.Management.Smo.Restore"
			$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem $full, "FILE"
			$restore.Devices.Add($device)
			try { $filelist = $restore.ReadFileList($server) }
			catch { throw "File list could not be determined. This is likely due to connectivity issues or tiemouts with the SQL Server, the database version is incorrect, or the SQL Server service account does not have access to the file share. Script terminating." }
			
			$header = $restore.ReadBackupHeader($server)
			$dbname = $header.DatabaseName
			
			if ($systemdbs -contains $dbname) { continue }
			if (!([string]::IsNullOrEmpty($Databases)) -and $Databases -notcontains $dbname) { continue }
			if (!([string]::IsNullOrEmpty($Exclude)) -and $Exclude -contains $dbname)
			{
				$skippedb.Add($dbname, "Explicitly Skipped")
				Continue
			}
			if ($systemdbs -contains $dbname) { continue }
			
			if ($server.databases[$dbname] -ne $null -and !$force -and $systemdbs -notcontains $dbname)
			{
				Write-Warning "$dbname exists at $SqlServer. Use -Force to drop and migrate."
				$skippedb[$dbname] = "Database exists at $SqlServer. Use -Force to drop and migrate."
				continue
			}
			
			if ($server.databases[$dbname] -ne $null -and $force -and $systemdbs -notcontains $dbname)
			{
				If ($Pscmdlet.ShouldProcess($SqlServer, "DROP DATABASE $dbname"))
				{
					Write-Output "$dbname already exists. -Force was specified. Dropping $dbname on $SqlServer."
					$dropresult = Remove-SqlDatabase $server $dbname
					if (!$dropresult) { $skippedb[$dbname] = "Database exists and could not be dropped."; continue }
				}
			}
			
			$filestructure = Get-OfflineSqlFileStructure $server $dbname $filelist $ReuseSourceFolderStructure
			
			if ($filestructure -eq $false)
			{
				Write-Warning "$dbname contains FILESTREAM and filestreams are not supported by destination server. Skipping."
				$skippedb[$dbname] = "Database contains FILESTREAM and filestreams are not supported by destination server."
				continue
			}
			$backupinfo = $restore.ReadBackupHeader($server)
			$backupversion = [version]("$($backupinfo.SoftwareVersionMajor).$($backupinfo.SoftwareVersionMinor).$($backupinfo.SoftwareVersionBuild)")
			
			Write-Output "Restoring FULL backup to $dbname to $SqlServer"
			$result = Restore-Database $server $dbname $full "Database" $filestructure
			
			if ($result -eq $true)
			{
				if ($diff)
				{
					Write-Output "Restoring DIFFERENTIAL backup"
					$result = Restore-Database $server $dbname $diff "Database" $filestructure
					if ($result -ne $true) { $result | fl -force; return }
				}
				if ($logs)
				{
					Write-Output "Restoring $($logs.count) LOGS"
					foreach ($log in $logs)
					{
						$result = Restore-Database $server $dbname $log "Log" $filestructure
					}
				}
			}
			
			if ($result -eq $false) { Write-Warning "$dbname could not be restored."; continue }
			
			if ($norecovery -eq $false)
			{
				$sql = "RESTORE DATABASE [$dbname] WITH RECOVERY"
				try
				{
					$server.databases['master'].ExecuteNonQuery($sql)
					$migrateddb.Add($dbname, "Successfully restored.")
					Write-Output "Successfully restored $dbname."
				}
				catch { Write-Error "$dbname could not be set to recovered." }
					try
					{
						try
						{
							$sa = Get-SqlSaLogin $server
						}
						catch
						{
							$sa = "sa"
						}
					
					$server.databases.refresh()
					$server.databases[$dbname].SetOwner($sa)
					$server.databases[$dbname].Alter()
					Write-Output "Successfully changed $dbname dbowner to sa"
				}
				catch { Write-Error "Could not update dbowner to sa." }
			}
			
		} #end of for each database folder
	}
	
	END
	{
		#Clean up
		$server.ConnectionContext.Disconnect()
		Write-Output "Database restores complete"
	}
}