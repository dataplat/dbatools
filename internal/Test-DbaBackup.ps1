Function Test-DbaBackup
{
<#
.SYNOPSIS
Safely removes a SQL Database and creates an Agent Job to restore it

.DESCRIPTION
Performs a DBCC CHECKDB on the database, backs up the database with Checksum and verify only to a Final Backup location, creates an Agent Job to restore from that backup, Drops the database, runs the agent job to restore the database,
performs a DBCC CHECKDB and drops the database

By default the initial DBCC CHECKDB is performed
By default the jobs and databases are created on the same server. Use -Destination to use a seperate server

It will start the SQL Agent Service on the Destination Server if it is not running

.PARAMETER SqlServer
The SQL Server instance holding the databases to be removed.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationServer
If specified this is the server that the Agent Jobs will be created on. By default this is the same server as the SQLServer.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER Databases
The database name to remove or an array of database names eg $Databases = 'DB1','DB2','DB3'

.PARAMETER NoDBCCCheck
If this switch is used the initial DBCC CHECK DB will be skipped. This will make the process quicker but will also create an agent job to restore a database backup containing a corrupt database. 
A second DBCC CHECKDB is performed on the restored database so you will still be notified BUT USE THIS WITH CARE

.PARAMETER BackupFolder
Final (Golden) Backup Folder for storing the backups. Be Careful if you are using a source and destination server that you use the full UNC path eg \\SERVER1\BACKUPSHARE\

.PARAMETER JobOwner
The account that will own the Agent Jobs - Defaults to sa

.PARAMETER UseDefaultFilePaths
Use the instance default file paths for the mdf and ldf files to restore the database if not set will use the original file paths

.PARAMETER DBCCErrorFolder 
FolderPath for DBCC Error Output - defaults to C:\temp

.PARAMETER AllDatabases
Runs the script for every user databases on a server - Useful when decomissioning a server - That would need a DestinationServer set

.PARAMETER Force
This switch will continue to perform rest of the actions and will create an Agent Job with DBCCERROR in the name and a Backup file with DBCC in the name

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-DbaBackup

.EXAMPLE 
Test-DbaBackup -SqlServer 'Fade2Black' -Databases RideTheLightning -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

For the database RideTheLightning on the server Fade2Black Will perform a DBCC CHECKDB and if there are no errors 
backup the database to the folder C:\MSSQL\Backup\Rationalised - DO NOT DELETE. It will then create an Agent Job to restore the database 
from that backup. It will drop the database, run the agent job to restore it, perform a DBCC ChECK DB and then drop the database.

Any DBCC errors will be written to your documents folder

.EXAMPLE 
$Databases = 'DemoNCIndex','RemoveTestDatabase'
Test-DbaBackup -SqlServer 'Fade2Black' -Databases $Databases -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

For the databases 'DemoNCIndex','RemoveTestDatabase' on the server Fade2Black Will perform a DBCC CHECKDB and if there are no errors 
backup the database to the folder C:\MSSQL\Backup\Rationalised - DO NOT DELETE. It will then create an Agent Job for each database 
to restore the database from that backup. It will drop the database, run the agent job, perform a DBCC ChECK DB and then drop the database

Any DBCC errors will be written to your documents folder

.EXAMPLE 
Test-DbaBackup -SqlServer 'Fade2Black' -DestinationServer JusticeForAll -Databases RideTheLightning -BackupFolder '\\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE'

For the database RideTheLightning on the server Fade2Black Will perform a DBCC CHECKDB and if there are no errors 
backup the database to the folder \\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE It will then create an Agent Job on the server 
JusticeForAll to restore the database from that backup. It will drop the database on Fade2Black, run the agent job to restore it on JusticeForAll, 
perform a DBCC ChECK DB and then drop the database

Any DBCC errors will be written to your documents folder
.EXAMPLE 
Test-DbaBackup -SqlServer IronMaiden -Databases $Databases -DestinationServer TheWildHearts -DBCCErrorFolder C:\DBCCErrors -BackupFolder z:\Backups -NoDBCCCheck -UseDefaultFilePaths -JobOwner 'THEBEARD\Rob' 

For the databases $Databases on the server IronMaiden Will NOT perform a DBCC CHECKDB 
It will backup the databases to the folder Z:\Backups It will then create an Agent Job on the server with a Job Owner of THEBEARD\Rob 
TheWildHearts to restore the database from that backup using the instance default filepaths. 
It will drop the database on IronMaiden, run the agent job to restore it on TheWildHearts using the default file paths for the instance, perform 
a DBCC ChECK DB and then drop the database

Any DBCC errors will be written to your documents folder

.EXAMPLE 
Test-DbaBackup -SqlServer IronMaiden -Databases $Databases -DestinationServer TheWildHearts -DBCCErrorFolder C:\DBCCErrors -BackupFolder z:\Backups -UseDefaultFilePaths -ContinueAfterDbccError

For the databases $Databases on the server IronMaiden will backup the databases to the folder Z:\Backups It will then create an Agent Job
TheWildHearts to restore the database from that backup using the instance default filepaths. 
It will drop the database on IronMaiden, run the agent job to restore it on TheWildHearts using the default file paths for the instance, perform 
a DBCC ChECK DB and then drop the database

If there is a DBCC Error it will continue to perform rest of the actions and will create an Agent Job with DBCCERROR in the name and a Backup file with DBCCError in the name


#>
	[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Default")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[parameter(Mandatory = $false)]
		[object]$SqlCredential,
		[parameter(Mandatory = $false)]
		[object]$Destination = $SqlServer,
		[parameter(Mandatory = $false)]
		[switch]$NoCheck,
		[parameter(Mandatory = $false)]
		[string]$DbccErrorFolder = [Environment]::GetFolderPath("mydocuments"),
		[parameter(Mandatory = $false)]
		[switch]$AllDatabases,
		[switch]$Force
		
	)
	
	DynamicParam { if ($sqlserver) { return Get-ParamSqlDatabases -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
		
		if ($AllDatabases -eq $false -and $databases.length -eq 0)
		{
			throw "You must specify at least one database. Use -Databases or -AllDatabases."
		}
		
		$sourceserver = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $sqlCredential -ParameterConnection
		
		
		if ($SqlServer -ne $destination)
		{
			$destserver = Connect-SqlServer -SqlServer $destination -SqlCredential $sqlCredential
			
			$sourcenb = $sourceserver.ComputerNamePhysicalNetBIOS
			$destnb = $sourceserver.ComputerNamePhysicalNetBIOS
			
			if ($BackupFolder.StartsWith("\\") -eq $false -and $sourcenb -ne $destnb)
			{
				throw "Backup folder must be a network share if the source and destination servers are not the same."
			}
		}
		else
		{
			$destserver = $sourceserver
		}
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if ($alldatabases -or $databases.count -eq 0)
		{
			$databases = ($sourceserver.databases | Where-Object{ $_.IsSystemObject -eq $false }).Name
		}
		
		if (!(Test-SqlPath -SqlServer $destserver -Path $backupFolder))
		{
			$serviceaccount = $destserver.ServiceAccount
			throw "Can't access $backupFolder Please check if $serviceaccount has permissions"
		}
		
		$jobname = "Rationalised Final Database Restore for $dbname"
		$jobStepName = "Restore the $dbname database from Final Backup"
		
		if (!($destserver.Logins | Where-Object{ $_.Name -eq $jobowner }))
		{
			throw "$destination does not contain the login $jobowner - Please fix and try again - Aborting"
		}
		
		Function Start-DbccCheck
		{
			param (
				[object]$server,
				[string]$dbname
			)
			
			$servername = $server.name
			$db = $server.databases[$dbname]
			
			if ($Pscmdlet.ShouldProcess($sourceserver, "Running dbcc check on $dbname on $servername"))
			{
				try
				{
					$null = $db.CheckTables('None')
					Write-Output "Dbcc CHECKDB finished successfully for $dbname on $servername"
				}
				
				catch
				{
					Write-Warning "DBCC CHECKDB failed"
					Write-Exception $_
					
					if ($force)
					{
						return $true
					}
					else
					{
						return $false
					}
				}
			}
		}
		
		Function Restore-Database1
		{
			<# 
				.SYNOPSIS
				Internal function. Restores .bak file to Sql database. Creates db if it doesn't exist. $filestructure is
				a custom object that contains logical and physical file locations.

				ALTERED To Add TSql switch and remove norecovery switch default
			#>
			
			[CmdletBinding()]
			param (
				[Parameter(Mandatory = $true)]
				[Alias('ServerInstance', 'SqlInstance')]
				[object]$server,
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[string]$dbname,
				[Parameter(Mandatory = $true)]
				[string]$backupfile,
				[string]$filetype = 'Database',
				[Parameter(Mandatory = $true)]
				[object]$filestructure,
				[switch]$norecovery,
				[System.Management.Automation.PSCredential]$sqlCredential,
				[switch]$TSql = $false
			)
			
			$server = Connect-SqlServer -SqlServer $server -SqlCredential $sqlCredential
			$servername = $server.name
			$server.ConnectionContext.StatementTimeout = 0
			$restore = New-Object 'Microsoft.SqlServer.Management.Smo.Restore'
			$restore.ReplaceDatabase = $true
			
			foreach ($file in $filestructure.values)
			{
				$movefile = New-Object 'Microsoft.SqlServer.Management.Smo.RelocateFile'
				$movefile.LogicalFileName = $file.logical
				$movefile.PhysicalFileName = $file.physical
				$null = $restore.RelocateFiles.Add($movefile)
			}
			
			try
			{
				if ($TSql)
				{
					$restore.PercentCompleteNotification = 1
					$restore.add_Complete($complete)
					$restore.ReplaceDatabase = $true
					$restore.Database = $dbname
					$restore.Action = $filetype
					$restore.NoRecovery = $norecovery
					$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
					$device.name = $backupfile
					$device.devicetype = 'File'
					$restore.Devices.Add($device)
					$restorescript = $restore.script($server)
					return $restorescript
				}
				else
				{
					$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
						Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
					}
					$restore.add_PercentComplete($percent)
					$restore.PercentCompleteNotification = 1
					$restore.add_Complete($complete)
					$restore.ReplaceDatabase = $true
					$restore.Database = $dbname
					$restore.Action = $filetype
					$restore.NoRecovery = $norecovery
					$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
					$device.name = $backupfile
					$device.devicetype = 'File'
					$restore.Devices.Add($device)
					
					Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
					$restore.sqlrestore($server)
					Write-Progress -id 1 -activity "Restoring $dbname to $servername" -status 'Complete' -Completed
					
					return $true
				}
			}
			catch
			{
				Write-Error "Restore failed: $($_.Exception)"
				return $false
			}
		}
		
	}
	PROCESS
	{
		$start = Get-Date
		Write-Output "Starting Rationalisation Script at $start"
		
		foreach ($dbname in $databases)
		{
			
			$db = $sourceserver.databases[$dbname]
			
			# The db check is needed when the number of databases exceeds 255, then it's no longer autopopulated
			if (!$db)
			{
				Write-Warning "$dbname does not exist on $source. Aborting routine for this database"
				continue
			}
			
			Write-Output "Starting Rationalisation of $dbname"
			## if we want to Dbcc before to abort if we have a corrupt database to start with
			if ($NoCheck -eq $false)
			{
				if ($Pscmdlet.ShouldProcess($dbname, "Running dbcc check on $dbname on $source"))
				{
					Write-Output "Starting Dbcc CHECKDB for $dbname on $source"
					$dbccgood = Start-DbccCheck -Server $sourceserver -DBName $dbname
					
					if ($dbccgood -eq $false)
					{
						if ($force -eq $false)
						{
							Write-Output "DBCC failed for $dbname (you should check that).  Aborting routine for this database"
							continue
						}
						else
						{
							Write-Output "DBCC failed, but Force specified. Continuing."
						}
					}
				}
			}
			
			if ($Pscmdlet.ShouldProcess($source, "Backing up $dbname"))
			{
				Write-Output "Starting Backup for $dbname on $source"
				## Take a Backup
				try
				{
					$timenow = [DateTime]::Now.ToString('yyyyMMdd_HHmmss')
					$backup = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Backup
					$backup.Action = [Microsoft.SqlServer.Management.SMO.BackupActionType]::Database
					$backup.BackupSetDescription = "Final Full Backup of $dbname Prior to Dropping"
					$backup.Database = $dbname
					$backup.Checksum = $True
					if ($sourceserver.versionMajor -gt 9)
					{
						$backup.CompressionOption = $backupCompression
					}
					if ($force -and $dbccgood -eq $false)
					{
						
						$filename = "$backupFolder\$($dbname)_DBCCERROR_$timenow.bak"
					}
					else
					{
						$filename = "$backupFolder\$($dbname)_Final_Before_Drop_$timenow.bak"
					}
					
					$devicetype = [Microsoft.SqlServer.Management.Smo.DeviceType]::File
					$backupDevice = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem($filename, $devicetype)
					
					$backup.Devices.Add($backupDevice)
					#Progress
					$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
						Write-Progress -id 1 -activity "Backing up database $dbname on $source to $filename" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
					}
					$backup.add_PercentComplete($percent)
					$backup.add_Complete($complete)
					Write-Progress -id 1 -activity "Backing up database $dbname on $source to $filename" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
					$backup.SqlBackup($sourceserver)
					$null = $backup.Devices.Remove($backupDevice)
					Write-Progress -id 1 -activity "Backing up database $dbname  on $source to $filename" -status "Complete" -Completed
					Write-Output "Backup Completed for $dbname on $source "
					
					Write-Output "Running Restore Verify only on Backup of $dbname on $source"
					try
					{
						$restoreverify = New-Object 'Microsoft.SqlServer.Management.Smo.Restore'
						$restoreverify.Database = $dbname
						$restoreverify.Devices.AddDevice($filename, $devicetype)
						$result = $restoreverify.SqlVerify($sourceserver)
						
						if ($result -eq $false)
						{
							Write-Warning "FAILED : Restore Verify Only failed for $filename on $server - aborting routine for this database"
							continue
						}
						
						Write-Output "Restore Verify Only for $filename Succeeded "
					}
					catch
					{
						Write-Warning "FAILED : Restore Verify Only failed for $filename on $server - aborting routine for this database"
						Write-Exception $_
						continue
					}
				}
				catch
				{
					Write-Exception $_
					Write-Warning "FAILED : To backup database $dbname on $server - aborting routine for this database"
					continue
				}
			}
			
			## Run a Dbcc No choice here
			if ($Pscmdlet.ShouldProcess($dbname, "Running Dbcc CHECKDB on $dbname on $destination"))
			{
				Write-Output "Starting Dbcc CHECKDB for $dbname on $destination"
				$null = Start-DbccCheck -Server $destserver -DbName $dbname
			}
			
			if ($Pscmdlet.ShouldProcess($dbname, "Dropping Database $dbname on $destination"))
			{
				## Drop the database
				try
				{
					$null = Remove-SqlDatabase -SqlServer $sourceserver -DbName $dbname
					Write-Output "Dropped $dbname Database on $destination"
				}
				catch
				{
					Write-Warning "FAILED : To Drop database $dbname on $destination - Aborting"
					Write-Exception $_
					continue
				}
			}
			Write-Output "Rationalisation Finished for $dbname"
		}
	}

END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		
		if ($Pscmdlet.ShouldProcess("console", "Showing final message"))
		{
			$End = Get-Date
			Write-Output "Finished at $End"
			$Duration = $End - $start
			Write-Output "Script Duration: $Duration"
		}
	}
}