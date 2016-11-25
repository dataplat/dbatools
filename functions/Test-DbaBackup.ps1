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
		[Alias("ServerInstance", "SqlInstance", "Source")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[object]$Destination = $SqlServer,
		[string]$BackupPath,
		[string]$BackupsDirectory,
		[string]$DataDirectory,
		[string]$LogDirectory,
		[switch]$NoCheck,
		[switch]$Force
		
	)
	
	DynamicParam { if ($sqlserver) { return Get-ParamSqlDatabases -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
		$sourceserver = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $sqlCredential
		
		if ($SqlServer -ne $destination)
		{
			$destserver = Connect-SqlServer -SqlServer $destination -SqlCredential $sqlCredential
			
			$sourcenb = $sourceserver.ComputerNamePhysicalNetBIOS
			$destnb = $sourceserver.ComputerNamePhysicalNetBIOS
			
			if ($BackupFolder)
			{
				if ($BackupFolder.StartsWith("\\") -eq $false -and $sourcenb -ne $destnb)
				{
					throw "Backup folder must be a network share if the source and destination servers are not the same."
				}
			}
			
		}
		else
		{
			$destserver = $sourceserver
		}
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if (!$datadirectory)
		{
			$datadirectory = Get-SqlDefaultPaths -SqlServer $destserver -FileType mdf
		}
		
		if (!$logdirectory)
		{
			$logdirectory = Get-SqlDefaultPaths -SqlServer $destserver -FileType ldf
		}
		
		if ($databases.count -eq 0)
		{
			$databases = $sourceserver.databases.Name
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
					Write-Verbose "Dbcc CHECKDB finished successfully for $dbname on $servername"
					return "Success"
				}
				catch
				{
					Write-Exception $_ -WarningAction SilentlyCOntinue
					$inner = $_.Exception.Message
					return "Failure: $inner"
				}
			}
		}
	}
	PROCESS
	{
		<#
			$restorelist = Get-RestoreFileList -server $server -filepath C:\temp\whatever.bak
			$filelist = $restorelist.Filelist
			$dbname = $restorelist.DatabaseName
		#>
		
		<#
		if (!(Test-SqlPath -SqlServer $destserver -Path $backupFolder))
		{
			$serviceaccount = $destserver.ServiceAccount
			throw "Can't access $backupFolder Please check if $serviceaccount has permissions"
		}
		#>
		
		if ($databases)
		{
			foreach ($dbname in $databases)
			{
				
				$db = $sourceserver.databases[$dbname]
				
				# The db check is needed when the number of databases exceeds 255, then it's no longer autopopulated
				if (!$db)
				{
					Write-Warning "$dbname does not exist on $source."
					continue
				}
				
				$lastbackup = Get-DbaBackupHistory -SqlServer $sourceserver -Databases $dbname -LastFull
				
				if ($lastbackup -eq $null)
				{
					$lastbackup = @{ Path = "Not found" }
					$fileexists = $false
					$restoreresult = "Skipped"
					$dbccresult = "Skipped"
				}
				elseif ($source -ne $destination -and $lastbackup[0].Path.StartsWith('\\') -eq $false)
				{
					$fileexists = "Skipped"
					$restoreresult = "Restore not located on shared location"
					$dbccresult = "Skipped"
				}
				elseif ((Test-SqlPath -SqlServer $destserver -Path $lastbackup[0].Path) -eq $false)
				{
					$fileexists = $false
					$restoreresult = "Skipped"
					$dbccresult = "Skipped"
				}
				else
				{
					$restorelist = Get-RestoreFileList -server $destserver -filepath $lastbackup[0].Path
					$fileexists = $true
					
					$filelist = $restorelist.Filelist
					$dbname = $restorelist.DatabaseName
					$temprestoreinfo = @()
					
					foreach ($file in $filelist)
					{
						if ($file.Type -eq 'L')
						{
							$dir = $logdirectory
						}
						else
						{
							$dir = $datadirectory
						}
						
						$fn = Split-Path $file.PhysicalName -Leaf
						$temprestoreinfo += [pscustomobject]@{
							Logical = $file.LogicalName
							Physical = "$dir\dbatools-testrestore-$fn"
						}
					}
					
					$ogdbname = $dbname
					$dbname = "dbatools-testrestore-$dbname"
					
					## Run a Dbcc No choice here
					if ($Pscmdlet.ShouldProcess($destination, "Restoring $ogdbname as $dbname"))
					{
						Write-Verbose "Starting Dbcc CHECKDB for $dbname on $destination"
						$restoreresult = Restore-Database -SqlServer $destserver -DbName $dbname -backupfile $lastbackup.path -filestructure $temprestoreinfo
					}
					
					## Run a Dbcc No choice here
					if ($Pscmdlet.ShouldProcess($dbname, "Running Dbcc CHECKDB on $dbname on $destination"))
					{
						Write-Verbose "Starting Dbcc CHECKDB for $dbname on $destination"
						$dbccresult = Start-DbccCheck -Server $destserver -DbName $dbname
					}
					
					if ($Pscmdlet.ShouldProcess($dbname, "Dropping Database $dbname on $destination"))
					{
						## Drop the database
						try
						{
							$null = Remove-SqlDatabase -SqlServer $destserver -DbName $dbname
							Write-Verbose "Dropped $dbname Database on $destination"
						}
						catch
						{
							Write-Warning "FAILED : To Drop database $dbname on $destination - Aborting"
							Write-Exception $_
							continue
						}
					}
				}
				
				if ($Pscmdlet.ShouldProcess("console", "Showing results"))
				{
					[pscustomobject]@{
						Server = $source
						Database = $db.name
						File = $lastbackup.Path
						FileExists = $fileexists
						RestoreResult = $restoreresult
						DbccResult = $dbccresult
					}
				}
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
	}
}