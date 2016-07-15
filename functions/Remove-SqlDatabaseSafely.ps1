Function Remove-SqlDatabaseSafely
{
<#
.SYNOPSIS
Safely removes a SQL Database and creates an Agent Job to restore it

.DESCRIPTION
Performs a DBCC CHECKDB on the database, backs up the database with Checksum and verify only to a Final Backup location, creates an Agent Job to restore from that backup, Drops the database, runs the agent job to restore the database,
performs a DBCC CHECKDB and drops the database

By default the initial DBCC CHECKDB is performed
By default the jobs and databases are created on the same server. Use -DestinationServer to use a seperate server

It will start the SQL Agent Service on the Destination Server if it is not running

.PARAMETER SqlServer
The SQL Server instance holding the databases to be removed.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationServer
If specified this is the server that the Agent Jobs will be created on. By default this is the same server as the SQLServer.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER DBNames
The database name to remove or an array of database names eg $DBNames = 'DB1','DB2','DB3'

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

.PARAMETER AllDbs
Runs the script for every user databases on a server - Useful when decomissioning a server - That would need a DestinationServer set

.PARAMETER ContinueAfterDBCCError
This switch will continue to perform rest of the actions and will create an Agent Job with DBCCERROR in the name and a Backup file with DBCC in the name

.NOTES 
Original Author: Rob Sewell @SQLDBAWithBeard, sqldbawithabeard.com
                 With huge thanks to Grant Fritchey and his verify your backups video 
                 Take a look its only 3 minutes long
                 http://sqlps.io/backuprant

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
https://dbatools.io/Remove-SqlDatabaseSafely

.EXAMPLE 
Remove-SqlDatabaseSafely -SqlServer 'Fade2Black' -DBNames RideTheLightning -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

For the database RideTheLightning on the server Fade2Black Will perform a DBCC CHECKDB and if there are no errors 
backup the database to the folder C:\MSSQL\Backup\Rationalised - DO NOT DELETE. It will then create an Agent Job to restore the database 
from that backup. It will drop the database, run the agent job to restore it, perform a DBCC ChECK DB and then drop the database.

Any DBCC errors will be located in C:\Temp

.EXAMPLE 
$DBNames = 'DemoNCIndex','RemoveTestDatabase'
Remove-SqlDatabaseSafely -SqlServer 'Fade2Black' -DBNames $DBNames -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

For the databases 'DemoNCIndex','RemoveTestDatabase' on the server Fade2Black Will perform a DBCC CHECKDB and if there are no errors 
backup the database to the folder C:\MSSQL\Backup\Rationalised - DO NOT DELETE. It will then create an Agent Job for each database 
to restore the database from that backup. It will drop the database, run the agent job, perform a DBCC ChECK DB and then drop the database

Any DBCC errors will be located in C:\Temp

.EXAMPLE 
Remove-SqlDatabaseSafely -SqlServer 'Fade2Black' -DestinationServer JusticeForAll -DBNames RideTheLightning -BackupFolder '\\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE'

For the database RideTheLightning on the server Fade2Black Will perform a DBCC CHECKDB and if there are no errors 
backup the database to the folder \\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE It will then create an Agent Job on the server 
JusticeForAll to restore the database from that backup. It will drop the database on Fade2Black, run the agent job to restore it on JusticeForAll, 
perform a DBCC ChECK DB and then drop the database

Any DBCC errors will be located in C:\Temp
.EXAMPLE 
Remove-SqlDatabaseSafely -SqlServer IronMaiden -DBNames $DBNames -DestinationServer TheWildHearts -DBCCErrorFolder C:\DBCCErrors -BackupFolder z:\Backups -NoDBCCCheck -UseDefaultFilePaths -JobOwner 'THEBEARD\Rob' 

For the databases $DBNames on the server IronMaiden Will NOT perform a DBCC CHECKDB 
It will backup the databases to the folder Z:\Backups It will then create an Agent Job on the server with a Job Owner of THEBEARD\Rob 
TheWildHearts to restore the database from that backup using the instance default filepaths. 
It will drop the database on IronMaiden, run the agent job to restore it on TheWildHearts using the default file paths for the instance, perform 
a DBCC ChECK DB and then drop the database

Any DBCC errors will be located in C:\Temp

.EXAMPLE 
Remove-SqlDatabaseSafely -SqlServer IronMaiden -DBNames $DBNames -DestinationServer TheWildHearts -DBCCErrorFolder C:\DBCCErrors -BackupFolder z:\Backups -UseDefaultFilePaths -ContinueAfterDBCCError

For the databases $DBNames on the server IronMaiden will backup the databases to the folder Z:\Backups It will then create an Agent Job
TheWildHearts to restore the database from that backup using the instance default filepaths. 
It will drop the database on IronMaiden, run the agent job to restore it on TheWildHearts using the default file paths for the instance, perform 
a DBCC ChECK DB and then drop the database

If there is a DBCC Error it will continue to perform rest of the actions and will create an Agent Job with DBCCERROR in the name and a Backup file with DBCCError in the name


#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		## Source SQL Server - Requires sysadmin access
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		## SQL Login for servers

		[parameter(Mandatory = $false)]
		[object]$SqlCredential,
		## Destination SQL Server for agent job, restores and DBCC - Requires ssyadmin access

		[parameter(Mandatory = $false)]
		[object]$DestinationServer = $SqlServer,
		## The Name of the database or an array of database names eg $DBNames = 'DB1','DB2','DB3' For all users databases on a server use -AllDBs

		[parameter(Mandatory = $false)]
		$DBNames,
		## If this switch is used the initial DBCC CHECK DB will be skipped. This will make the process quicker but will also create an agent job to restore a database backup containing a corrupt database. 

		## A second DBCC CHECKDB is performed on the restored database so you will still be notified BUT USE THIS WITH CARE

		[parameter(Mandatory = $false)]
		[switch]$NoDBCCCheck,
		## Final (Golden) Backup Folder for storing the backups. Be Careful if you are using a source and destination server that you use the full UNC path eg \\SERVER1\BACKUPSHARE\

		[parameter(Mandatory = $true)]
		[string]$BackupFolder,
		## Category Name for Agent Jobs -- defaults to Rationalisation

		[parameter(Mandatory = $false)]
		[string]$CategoryName = 'Rationalisation',
		## Agent Job Owner - defaults to sa

		[parameter(Mandatory = $false)]
		[string]$JobOwner = 'sa',
		## Use the instance default file paths for the mdf and ldf files to restore the database if not set will use the original file paths

		[switch]$UseDefaultFilePaths,
		## FolderPath for DBCC Error Output - defaults to C:\temp

		[parameter(Mandatory = $false)]
		[string]$DBCCErrorFolder = 'C:\temp',
		# no trailing slash

		## Performs action for All user databases on a server 

		[parameter(Mandatory = $false)]
		[switch]$AllDbs,

        ## Continue to process after a DBCC error. Default is to stop processing that database

		[parameter(Mandatory = $false)]
		[switch]$ContinueAfterDBCCError
	)
	DynamicParam { if ($sqlserver) { return Get-ParamSqlLogins -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	BEGIN
	{
		# Load SMO
		
		[void][Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO")
		[void][Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO.SMOExtended")
		# please continue to use these variable names for consistency
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential -ParameterConnection
		## Incase we want to add this as an option later
		$BackupCompression = 'Default' # 'Default' 'on' or 'off'
		
		if ($SqlServer -ne $DestinationServer)
		{
			$DestServer = Connect-SqlServer -SqlServer $DestinationServer -SqlCredential $SqlCredential
		}
		else
		{
			$DestinationServer = $SqlServer
			$DestServer = $sourceserver
		}
		if ($AllDbs)
		{
			$DBNames = ($sourceserver.Databases | Where-Object{ $_.IsSystemObject -eq $false }).Name
		}
		$source = $sourceserver.DomainInstanceName
		$JobName = "Rationalised Final Database Restore for $DBName"
		$JobStepName1 = "Restore the $DBName database from Final Backup"
		if (!($DestServer.Logins | Where-Object{ $_.Name -eq $JobOwner }))
		{
			Write-Warning "$DestinationServer Doesnot contain the login $JobOwner - Please fix and try again - Aborting"
			break
		}
		If ($Pscmdlet.ShouldProcess($destinationserver, "Starting SQL Agent"))
        {
		if ($destinationserver -notcontains '\')
		{
            $ServiceName = 'SQLSERVERAGENT'
        }
        else
        {
            $i = $destinationserver.Split('\')[1]
            $ServiceName = "SQLAGENT*$i"
            $SQLServiceName = "MSSQL*$i"
        }
			
           try
           {
                $ip = [System.Net.Dns]::GetHostAddresses($destinationserver) 
                $destnetbios = [System.Net.Dns]::GetHostbyAddress($ip.IPAddressToString)
                $agentservice = Get-Service -ComputerName $destnetbios -Name $ServiceName
			
			If ($Pscmdlet.ShouldProcess($destinationserver, "Starting SQL Agent"))
            {
			    if ($agentservice.Status -ne 'Running')
			    {
                    $agentservice.Start()
                    $timeout = new-timespan -seconds 60
                    $sw = [diagnostics.stopwatch]::StartNew()
                    $AgentStatus = (Get-Service -ComputerName $destnetbios -Name $ServiceName).Status
                    While ($DBStatus -ne 'Running' -and $sw.elapsed -lt $timeout)
                        {
                        $DBStatus = (Get-Service -ComputerName $destnetbios -Name $ServiceName).Status
                        }
			    }
            }

				}
            catch
            {
            Write-Exception $_
            }
			if ($agentservice.Status -ne 'Running')
			{
				Write-Warning "Cannot start Agent Service on $destinationserver - Aborting"
				break
			}
			# end ShouldProcess
		}
		
		
        if(!(Test-SQLPath -SqlServer $DestinationServer -Path $BackupFolder))
        {
        $SQLUser = (Get-WmiObject -Class Win32_Service -ComputerName $DestinationServer|where-object {$_.name -like $SQLServiceName}).startname
        Write-Warning "Can't access $BackupFolder Please check if $SQLUser has permissions"
        break
        }
		
		function Start-DBCCCheck
		{
			param ([object]$SQLServer,
				[string]$DBName,
                [string]$DBCCErrorFolder,
                [switch] $ContinueAfterDBCCError)
            $Server = $sqlserver.name
			$DB = $Sqlserver.Databases[$DBName]
			$DBCCGood = $True
            If ($Pscmdlet.ShouldProcess($sourceserver, "Running dbcc check on $DBName on $sourceserver"))
            {
			    try
			    {
			    	$DB.CheckTables('None')
			    	Write-Output "DBCC CHECKDB finished successfully for $DBName on $Server"
			    }
			    catch
			    {

                    try
                    {
			    	    if (!(Test-Path $DBCCErrorFolder))
			    	    {
			    	    	New-Item -Path $DBCCErrorFolder -ItemType Directory
			    	    }
                    }
                    catch
                    {
                        $DBCCErrorFolder = "$env:HOME\Documents"
                    }
                        $date = Get-Date -Format ddMMyyyy_HHmmss
			    	    [string]$ErrorFile = $DBCCErrorFolder + '\DBCC_Errors_for_' + $DBName + '_' + $Server + '_' + $Date + '.txt'
			    	    $_.Exception.InnerException | Out-File -Append $ErrorFile
			    	    $_.Exception.InnerException.InnerException.InnerException | Out-File -Append $ErrorFile
			    	    Write-Warning "UH-OH!! $DBName DBCC CHECKDB Error - Check this file $ErrorFile"
			    	    $DBCCGood = $false
			    	    return $DBCCGood
                        if($ContinueAfterDBCCError)
                        {}
                        else
                        {
			    	    continue
                        }
			    }
            }
		}
		function New-SQLAgentJobCategory
		{
			param ([string]$CategoryName,
				$JobServer)
			if (!$JobServer.JobCategories[$CategoryName])
			{
				try
				{
					Write-Output "Creating Agent Job Category $CategoryName"
					$Category = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobCategory
					$Category.Parent = $JobServer
					$Category.Name = $CategoryName
					$Category.Create()
					Write-Output "Created Agent Job Category $CategoryName"
				}
				catch
				{
					Write-Output "Creating Agent Job Category $CategoryName"
					Write-Warning "FAILED : To Create Agent Job Category $CategoryName - Aborting"
					Write-Exception $_
					continue
				}
			}
		}
		Function Restore-Database
		{
<# 
	.SYNOPSIS
	Internal function. Restores .bak file to SQL database. Creates db if it doesn't exist. $filestructure is
	a custom object that contains logical and physical file locations.

    ALTERED To Add TSQL switch and remove norecovery switch default
#>
			[CmdletBinding()]
			param (
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[Alias('ServerInstance', 'SqlInstance')]
				[object]$SqlServer,
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[string]$dbname,
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[string]$backupfile,
				[string]$filetype = 'Database',
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[object]$filestructure,
				[switch]$norecovery,
				[System.Management.Automation.PSCredential]$SqlCredential,
				[switch]$TSQL = $false
			)
			
			$SQLServer = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
			$SQLServername = $SQLServer.name
			$SQLServer.ConnectionContext.StatementTimeout = 0
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
				if ($TSQL)
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
					$RestoreScript = $restore.script($SQLServer)
					return $RestoreScript
				}
				else
				{
					$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
						Write-Progress -id 1 -activity "Restoring $dbname to $SQLServername" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
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
					
					Write-Progress -id 1 -activity "Restoring $dbname to $SQLServername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
					$restore.sqlrestore($SQLServer)
					Write-Progress -id 1 -activity "Restoring $dbname to $SQLServername" -status 'Complete' -Completed
					
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
		$Start = Get-Date
		Write-Output "Starting Rationalisation Script for $DBNames on $SQLServer to $DestinationServer"
		Write-Output "Started at $Start"
		foreach ($DBName in $DBNAMES)
		{
			$DBCCGood = $True
			$DB = $sourceserver.Databases[$DBName]
			$JobName = "Rationalised Database Restore Script for $DBName"
			$JobStepName1 = "Restore the $DBName database from Final Backup"
			if (!$DB)
			{
				Write-Warning "$DBName does not exist on $SQLServer"
				continue
			}
			$JobServer = $DestServer.JobServer
			If ($JobServer.Jobs[$JobName])
			{
				Write-Warning "FAILED : The Job $JobName already exists. Have you done this before? Rename the existing job and try again"
				continue
			}
			Write-Output "Starting Rationalisation of $DBName"
			## If we want to DBCC before to abort if we have a corrupt database to start with
			if (!$NoDBCCCheck)
			{
			    If ($Pscmdlet.ShouldProcess($DBName, "Running dbcc check on $DBName on $SourceServer"))
                {
                    Write-Output "Starting DBCC CHECKDB for $DBName on $SQLServer"
                    if($ContinueAfterDBCCError)
                    {
			    	$DBCCGood = Start-DBCCCheck -SQLserver $sourceserver -DBName $DBName -ContinueAfterDBCCError
                    Write-Output "DBCC Completed for $DBName on $SQLServer without Errors"
                    }
                    else
                    {
                    $DBCCGood = Start-DBCCCheck -SQLserver $sourceserver -DBName $DBName
                    Write-Output "DBCC Completed for $DBName on $SQLServer without Errors"
                    }
			    }
            }
			## If we have no DBCC errors or we havent run DBCC
			if ($DBCCGood)
			{
                    Write-Output "Starting Backup for $DBName on $SqlServer"
				    ## Take a Backup
				    try
				    {
				    If ($Pscmdlet.ShouldProcess($DestinationServer, "Backing up $DBName"))
                        {
					    $Backup = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Backup
					    $Backup.Action = [Microsoft.SQLServer.Management.SMO.BackupActionType]::Database
					    $Backup.BackupSetDescription = "Final Full Backup of $DBName Prior to Dropping"
					    $Backup.Database = $DBName
					    $Backup.Checksum = $True
					    if ($sourceserver.versionMajor -gt 9)
					    {
					    	$Backup.CompressionOption = $BackupCompression
					    }
                        if($ContinueAfterDBCCError -and $DBCCGood -eq $false)
                        {
                    $FileName = $BackupFolder + '\' + $DbName + '_' + 'DBCCERROR' + '_' + [DateTime]::Now.ToString('yyyyMMdd_HHmmss') + '.bak'
                    }
                        else
                        {
					$FileName = $BackupFolder + '\' + $DbName + '_' + 'Final_Before_Drop_' + [DateTime]::Now.ToString('yyyyMMdd_HHmmss') + '.bak'
					}
                        $DeviceType = [Microsoft.SqlServer.Management.Smo.DeviceType]::File
					    $BackupDevice = New-Object -TypeName Microsoft.SQLServer.Management.Smo.BackupDeviceItem($FileName, $DeviceType)
					    $Backup.Devices.Add($BackupDevice)
					    #Progress
					    $percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
					    	Write-Progress -id 1 -activity "Backing up database $DBName on $SqlServer to $FileName" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
					    }
					    $Backup.add_PercentComplete($percent)
					    $Backup.add_Complete($complete)
					    Write-Progress -id 1 -activity "Backing up database $DBName on $SqlServer to $FileName" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
					    $Backup.SqlBackup($sourceserver)
					    $Backup.Devices.Remove($BackupDevice)
					    Write-Progress -id 1 -activity "Backing up database $DBName  on $SqlServer to $FileName" -status "Complete" -Completed
					    Write-Output "Backup Completed for $DBName on $SqlServer "
					    Write-Output "Running Restore Verify only on Backup of $DBName on $SQLServer"
					    If ($Pscmdlet.ShouldProcess($DestinationServer, "Running restore verify on $FileName"))
                        {
                        try
					    {
					    	$restoreverify = New-Object 'Microsoft.SqlServer.Management.Smo.Restore'
					    	$restoreverify.Database = $DBName
					    	$restoreverify.Devices.AddDevice($FileName, $DeviceType)
					    	$result = $restoreverify.SqlVerify($SqlServer)
					    	if (!$Result)
					    	{
					    		Write-Warning "FAILED : Restore Verify Only failed for $FileName on $SqlServer - Aborting"
					    		continue
					    	}
					    	Write-Output "Restore Verify Only for $FileName Succeeded "
					    }
					    catch
					    {
					    	Write-Warning "FAILED : Restore Verify Only failed for $FileName on $SqlServer - Aborting"
					    	Write-Exception $_
					    	continue
					    }
                    }
				}
                    }
				    catch
				    {
					Write-Warning "FAILED : To backup database $DBName on $SqlServer - Aborting"
					Write-Exception $_
					continue
				} # End Backup
                
				Write-Output "Creating Automated Restore Job from Golden Backup for $DBName on $DestinationServer "
                    try
				    {
                    If($ContinueAfterDBCCError -and $DBCCGood -eq $false)
                    {
                    $JObName = $JobName -replace "Rationalised", "DBCC ERROR"
                    }
					## Create an agent job to restore the database
					$Job = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job $JobServer, $JobName
					$Job.Name = $JobName
					$Job.OwnerLoginName = $JobOwner
					$Job.Description = "This job will restore the $DBName database using the final backup located at $FileName"
					## Create a Job Category
					if (!$JobServer.JobCategories[$CategoryName])
					{
						New-SQLAgentJobCategory -JobServer $JobServer -CategoryName $CategoryName
					}
					$Job.Category = $CategoryName
					try
					{
                        If ($Pscmdlet.ShouldProcess($DestinationServer, "Creating Agent Job on $DestinationServer"))
                        {						
                            Write-Output "Created Agent Job $JobName on $DestinationServer "
						    $Job.Create()
					    }
                    }
					catch
					{
						Write-Warning "FAILED : To Create Agent Job $JobName on $DestinationServer - Aborting"
						Write-Exception $_
						continue
					}
					## Create Job Step
					## Aarons Suggestion: In the restore script, add a comment block that tells the last known size of each file in the database.
					## Suggestion check for disk space before restore
					## Create Restore Script
					try
					{
						$restore = New-Object 'Microsoft.SqlServer.Management.Smo.Restore'
						$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem $FileName, 'FILE'
						$restore.Devices.Add($device)
						try { $filelist = $restore.ReadFileList($DestServer) }
						catch { throw 'File list could not be determined. This is likely due to connectivity issues or tiemouts with the SQL Server, the database version is incorrect, or the SQL Server service account does not have access to the file share. Script terminating.' }
						$ReuseSourceFolderStructure = $true
						if ($UseDefaultFilePaths)
						{
							$ReuseSourceFolderStructure = $false
						}
						$filestructure = Get-OfflineSqlFileStructure $DestServer $DBName $filelist $ReuseSourceFolderStructure
						if ($filestructure -eq $false)
						{
							Write-Warning "$dbname contains FILESTREAM and filestreams are not supported by destination server. Skipping."
							$skippedb[$dbname] = "Database contains FILESTREAM and filestreams are not supported by destination server."
							continue
						}
						$JobStepCommmand = Restore-Database $DestServer $DBName $FileName "Database" $filestructure -TSQL -ErrorAction Stop
						$JobStep = new-object Microsoft.SqlServer.Management.Smo.Agent.JobStep $Job, $JobStepName1
						$JobStep.SubSystem = 'TransactSql' # 'PowerShell'
						$JobStep.DatabaseName = 'master'
						$JobStep.Command = $JobStepCommmand
						$JobStep.OnSuccessAction = 'QuitWithSuccess'
						$JobStep.OnFailAction = 'QuitWithFailure'
                        If ($Pscmdlet.ShouldProcess($DestinationServer, "Creating Agent JobStep on $DestinationServer"))
                        {
						$JobStep.Create()
                        }
						$JobStartStepid = $JobStep.ID
						Write-Output "Created Agent JobStep $JobStepName1 on $DestinationServer "
					}
					catch
					{
						Write-Warning "FAILED : To Create Agent JobStep $JobStepName1 on $DestinationServer - Aborting"
						Write-Exception $_
						continue
					}
                    If ($Pscmdlet.ShouldProcess($DestinationServer, "Applying Agent Job $JobName to $DestinationServer"))
                    {
					$Job.ApplyToTargetServer($DestinationServer)
					$Job.StartStepID = $JobStartStepid
					$Job.Alter()
                    }
				}
				    catch
				    {
					Write-Warning "FAILED : To Create Agent Job $JobName on $DestinationServer - Aborting"
					Write-Exception $_
					continue
				}
				}				
				## Drop the database
				try
				{
                    If ($Pscmdlet.ShouldProcess($DestinationServer, "Dropping Database $DBName on $sourceserver"))
                    {
  					    $sourceserver.KillAllProcesses($dbname)
					    $DB.drop()
                    }
					Write-Output "Dropped $DBName Database  on $SQLServer prior to running the Agent Job"
				}
				catch
				{
					Write-Warning "FAILED : To Drop database $DBName on $SQLServer - Aborting"
					Write-Exception $_
					continue
				}
				## Run the restore job to restore it
				Write-Output "Starting $JobName on $DestinationServer "
				try
				{
					$JOb = $DestServer.JobServer.Jobs[$JobName]
                    If ($Pscmdlet.ShouldProcess($DestinationServer, "Running Agent Job on $DestinationServer to restore $DBName"))
                    {
					$Job.Start()
                    }
					$Status = $Job.CurrentRunStatus
					While ($Status -ne 'Idle')
					{
						Write-Output "Restore Job for $DBName  on $DestinationServer is $Status"
						$Job.Refresh()
						$Status = $Job.CurrentRunStatus
						Start-Sleep -Seconds 5
					}
					Write-Output "Restore JOb $JobName has completed on $DestinationServer "
					Start-Sleep -Seconds 5 ## This is required to ensure the next DBCC Check succeeds
				}
				catch
				{
					Write-Warning "FAILED : Restore JOb $JobName failed on $DestinationServer - Aborting"
					Write-Exception $_
					continue
				}
				If ($JOb.LastRunOutcome -ne 'Succeeded')
				{
					Write-Warning "FAILED : Restore JOb $JobName failed on $DestinationServer - Aborting"
					Write-Warning "Check the Agent Job History on $DestinationServer - If you have SSMS2016 July release or later"
					Write-Warning "Get-SqlAgentJobHistory -JobName $jobName -ServerInstance $DestinationServer -OutcomesType Failed "
					continue
				}
				
				## Run a DBCC No choice here
				Write-Output "Starting DBCC CHECKDB for $DBName on $DestinationServer"
                If ($Pscmdlet.ShouldProcess($DBName, "Running DBCC CHECKDB on $DBName on $DestinationServer"))
                {                
				Start-DBCCCheck -SQLserver DestServer-DBName $DBName
                }
				## Drop the database
				try
				{
					$DestServer.Refresh()
                    $DestServer.KillAllProcesses($dbname)
					$DB = $DestServer.Databases[$DBName]
                    If ($Pscmdlet.ShouldProcess($DbName, "Dropping Database $DBName on $DestinationServer"))
                    {
					$DB.drop()
                    }
					Write-Output "Dropped $DBName Database on $DestinationServer"
				}
				catch
				{
					Write-Warning "FAILED : To Drop database $DBName on $DestinationServer - Aborting"
					Write-Exception $_
					continue
				}
				Write-Output "Rationalisation Finished for $DBName"
				## Finish
				continue
			} # End DBCC if
			else
			{
				Write-Warning "DBCC errors for $DBName - So Aborting"
				continue
			} # End DBCC else
		} #End DB foreach
		
	} # End Process
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$DestServer.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing final message"))
		{
			$End = Get-Date
			Write-Output "Rationalisation Finished for $DBNames on $SQLServer to $DestinationServer"
			Write-Output "Finished at $End"
			$Duration = $End - $Start
			Write-Output "Script Duration : - $Duration"
		}
	}
}

