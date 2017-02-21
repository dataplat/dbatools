function Expand-SqlTLogResponsibly
{
<#

.SYNOPSIS
This command will help you to automatically grow your T-Log database file in a responsible way (preventing the generation of too many VLFs).

.DESCRIPTION
As you may already know, having a TLog file with too many VLFs can hurt your database performance in many ways.

Example:
    Too many virtual log files can cause transaction log backups to slow down and can also slow down database recovery and, in extreme cases, even affect insert/update/delete performance. 
    References:
        http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
        http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx
        http://www.brentozar.com/blitz/high-virtual-log-file-vlf-count/
    
	In order to get rid of this fragmentation we need to grow the file taking the following into consideration:
        - How many VLFs are created when we perform a grow operation or when an auto-grow is invoked?
    Note: In SQL Server 2014 this algorithm has changed (http://www.sqlskills.com/blogs/paul/important-change-vlf-creation-algorithm-sql-server-2014/)

Attention:
    We are growing in MB instead of GB because of known issue prior to SQL 2012:
        More detail here: 
            http://www.sqlskills.com/BLOGS/PAUL/post/Bug-log-file-growth-broken-for-multiples-of-4GB.aspx
	    and 
            http://connect.microsoft.com/SQLServer/feedback/details/481594/log-growth-not-working-properly-with-specific-growth-sizes-vlfs-also-not-created-appropriately
	    or 
            https://connect.microsoft.com/SQLServer/feedback/details/357502/transaction-log-file-size-will-not-grow-exactly-4gb-when-filegrowth-4gb

Understanding related problems:
        http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
        http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx
        http://www.brentozar.com/blitz/high-virtual-log-file-vlf-count/
    
Known bug before SQL Server 2012
        http://www.sqlskills.com/BLOGS/PAUL/post/Bug-log-file-growth-broken-for-multiples-of-4GB.aspx
        http://connect.microsoft.com/SQLServer/feedback/details/481594/log-growth-not-working-properly-with-specific-growth-sizes-vlfs-also-not-created-appropriately
        https://connect.microsoft.com/SQLServer/feedback/details/357502/transaction-log-file-size-will-not-grow-exactly-4gb-when-filegrowth-4gb

.PARAMETER SqlServer 
    Represents the name/ip of the instance where the database(s) that you want to grow exist
     
.PARAMETER Databases
    This is a list of databases that this command will execute against. You can pass one or many. The database parameter can be passed via the pipeline (see examples).
	
.PARAMETER TargetLogSizeMB
    Represents the target size of the log file, expressed in MB.
    
.PARAMETER IncrementSizeMB
    Represents the incremental size of each growth, expressed in MB.
    If you don't provide this parameter, the value will be calculated automatically. Otherwise, the input value will be compared with the suggested value for your target size. If these values differ, you will be prompted to confirm your choice. 

.PARAMETER LogFileId
    If you want to grow additional T-Log files, you can specify the log file number (FileId column from DBCC LOGINFO output). If you do not specify the log file number, only the first T-log file will be processed.
    
.PARAMETER ShrinkLogFile
This command can automatically shrink your log files for you.

.PARAMETER ShrinkSizeMB
The target size of the log file after the shrink is performed.

.PARAMETER BackupDirectory
Backups must be performed in order to shrink the T-log. Designate a location for your backups. If you do not specify the backup directory, the SQL Server's default backup directory will be used. 

.NOTES
This script will not analyze the actual number of VLFs. Use Test-DbaVirtualLogFile or run t-sql "DBCC LOGINFO" statements
This script uses Get-DbaDiskSpace dbatools command to get the TLog's drive free space
       
Original Author: Cláudio Silva (@ClaudioESSilva)
Requires: ALTER DATABASE permission
Limitations: Freespace cannot be validated on the directory where the log file resides in SQL Server 2005.

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Expand-SqlTLogResponsibly
	
.EXAMPLE
    Expand-SqlTLogResponsibly -SqlServer sqlcluster -Databases db1 -TargetLogSizeMB 50000

    This is the simplest example. The increment value will be calculated and will grow the T-Log of the db1 database on sqlcluster to 50000 MB.

.EXAMPLE
    Expand-SqlTLogResponsibly -SqlServer sqlcluster -Databases db1, db2 -TargetLogSizeMB 10000 -IncrementSizeMB 200
    
	Grows the T-Log of db1 and db2 databases on sqlcluster to 1000MB. If you don't provide this parameter, the value will be calculated automatically. Otherwise, the input value will be compared with the suggested value for your target size. If these values differ, you will be prompted to confirm your choice. 

.EXAMPLE
    Expand-SqlTLogResponsibly -SqlServer sqlcluster -Databases db1 -TargetLogSizeMB 10000 -LogFileId 9

    Grows the T-Log with FielId 9 of the db1 database on sqlcluster instance to 10000MB.

.EXAMPLE
    Expand-SqlTLogResponsibly -SqlServer sqlcluster -Databases (Get-Content D:\DBs.txt) -TargetLogSizeMB 50000

    Grows the T-Log of the databases specified in the file 'D:\DBs.txt' on sqlcluster instance to 50000MB.

.EXAMPLE
    Expand-SqlTLogResponsibly -SqlServer sqlcluster -Databases db1, db2 -TargetLogSizeMB 50000

    Grows the T-Log of the databases db1 and db2 on the sqlcluster instance to 50000MB.

.EXAMPLE
    Expand-SqlTLogResponsibly -SqlServer sqlcluster -Databases 'db with space' -TargetLogSizeMB 50000 -Verbose

    Use -Verbose to view in detail all actions performed by this script

.EXAMPLE
	Expand-SqlTLogResponsibly -SqlServer sqlserver -Databases db1,db2 -TargetLogSizeMB 100 -IncrementSizeMB 10 -ShrinkLogFile -ShrinkSizeMB 10 -BackupDirectory R:\MSSQL\Backup
    
#>
	[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default')]
	param (
		[parameter(Position = 1, Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[parameter(Position = 3)]
		[System.Management.Automation.PSCredential]$SqlCredential,
		[parameter(Position = 4, Mandatory = $true)]
		[int]$TargetLogSizeMB,
		[parameter(Position = 5)]
		[int]$IncrementSizeMB = -1,
		[parameter(Position = 6)]
		[int]$LogFileId = -1,
		[parameter(Position = 7, ParameterSetName = 'Shrink', Mandatory = $true)]
		[switch]$ShrinkLogFile,
		[parameter(Position = 8, ParameterSetName = 'Shrink', Mandatory = $true)]
		[int]$ShrinkSizeMB,
		[parameter(Position = 9, ParameterSetName = 'Shrink')]
		[AllowEmptyString()]
		[string]$BackupDirectory
	)
	
	DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer -SqlCredential $SourceSqlCredential } }
	
	BEGIN
	{
		Write-Verbose "Set ErrorActionPreference to Inquire"
		$ErrorActionPreference = 'Inquire'
		
		#Convert MB to KB (SMO works in KB)
		Write-Verbose "Convert variables MB to KB (SMO works in KB)"
		[int]$TargetLogSizeKB = $TargetLogSizeMB * 1024
		[int]$LogIncrementSize = $incrementSizeMB * 1024
		[int]$ShrinkSize = $ShrinkSizeMB * 1024
		[int]$SuggestLogIncrementSize = 0
		[bool]$LogByFileID = if ($LogFileId -eq -1)
		{
			$false
		}
		else
		{
			$true
		}
		
		#Set base information
		Write-Verbose "Initialize the instance '$SqlServer'"
		
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
		
		if ($ShrinkLogFile -eq $true)
		{
			if ($BackupDirectory.length -eq 0)
			{
				$backupdirectory = $server.Settings.BackupDirectory
			}
			
			$pathexists = Test-SqlPath -SqlServer $server -Path $backupdirectory
			
			if ($pathexists -eq $false)
			{
				throw "Backup directory does not exist"
			}
		}
	}
	
	PROCESS
	{
		
		try
		{
			$databases = $psboundparameters.Databases
			
			[datetime]$initialTime = Get-Date
			
			#control the iteration number
			$databaseProgressbar = 0;

            Write-Output "Resolving NetBIOS name"
            $sourcenetbios = Resolve-NetBiosName $server
			
			#go through all databases
			Write-Verbose "Processing...foreach database..."
			foreach ($db in $Databases)
			{
				$databaseProgressbar += 1
				
				#set step to reutilize on logging operations
				[string]$step = "$databaseProgressbar/$($Databases.Count)"
				
				if ($server.Databases[$db])
				{
					Write-Progress `
								   -Id 1 `
								   -Activity "Using database: $db on Instance: '$SqlServer'" `
								   -PercentComplete ($databaseProgressbar / $Databases.Count * 100) `
								   -Status "Processing - $databaseProgressbar of $($Databases.Count)"
					
					#Validate which file will grow
					if ($LogByFileID)
					{
						$logfile = $server.Databases[$db].LogFiles.ItemById($LogFileId)
					}
					else
					{
						$logfile = $server.Databases[$db].LogFiles[0]
					}
					
					Write-Verbose "$step - Use log file: $logfile"
					$currentSize = $logfile.Size				

					Write-Verbose "$step - Log file current size: $([System.Math]::Round($($currentSize/1024.0), 2)) MB "
					[long]$requiredSpace = ($TargetLogSizeKB - $currentSize)
					
					Write-Verbose "Verifying if sufficient space exists ($([System.Math]::Round($($requiredSpace / 1024.0), 2))MB) on the volume to perform this task"
					
					# SQL 2005 or lower version. The "VolumeFreeSpace" property is empty
                    # When using SMO v12 and validating SQL 2008 also empty (BUG?)
                    [long]$TotalTLogFreeDiskSpaceKB = 0
                    Write-Output "Get TLog drive free space"
                    [object]$AllDrivesFreeDiskSpace = Get-DbaDiskSpace -ComputerName $sourcenetbios -Unit KB | Select-Object Name, SizeInKB
                    
                    #Verfiy path using Split-Path on $logfile.FileName in backwards. This way we will catch the LUNs. Example: "K:\Log01" as LUN name
                    $DrivePath = Split-Path $logfile.FileName -parent
                    Do  
                    {
                        if ($AllDrivesFreeDiskSpace | Where-Object {$DrivePath -eq "$($_.Name)"})
                        {
                            $TotalTLogFreeDiskSpaceKB = ($AllDrivesFreeDiskSpace | Where-Object {$DrivePath -eq $_.Name}).SizeInKB
                            $match = $true
                            break
                        }
                        else
                        {
                            $match = $false
                            $DrivePath = Split-Path $DrivePath -parent
                        }

                    }
                    while (!$match -or ([string]::IsNullOrEmpty($DrivePath)))

                    Write-Verbose "Total TLog Free Disk Space in MB: $([System.Math]::Round($($TotalTLogFreeDiskSpaceKB / 1024.0), 2))"

					if (($TotalTLogFreeDiskSpaceKB -le 0) -or ([string]::IsNullOrEmpty($TotalTLogFreeDiskSpaceKB)))
					{
						$title = "Choose increment value for database '$db':"
						$message = "Cannot validate freespace on drive where the log file resides. Do you wish to continue? (Y/N)"
						$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
						$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
						$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
						$result = $host.ui.PromptForChoice($title, $message, $options, 0)
						#no
						if ($result -eq 1)
						{
							Write-Warning "You have cancelled the execution"
							return
						}
					}

					if ($requiredSpace -gt $TotalTLogFreeDiskSpaceKB)
					{
						Write-Output "There is not enough space on volume to perform this task. `r`n" `
									 "Available space: $([System.Math]::Round($($TotalTLogFreeDiskSpaceKB / 1024.0), 2))MB;`r`n" `
									 "Required space: $([System.Math]::Round($($requiredSpace / 1024.0), 2))MB;"
						return
					}
					else
					{
						if ($currentSize -ige $TargetLogSizeKB -and ($ShrinkLogFile -eq $false))
						{
							Write-Output "$step - [INFO] The T-Log file '$logfile' size is already equal or greater than target size - No action required"
						}
						else
						{
							Write-Verbose "$step - [OK] There is sufficient free space to perform this task"
							
							# If SQL Server version is greater or equal to 2012
							if ($server.Version.Major -ge "11")
							{
								switch ($TargetLogSizeMB)
								{
									{ $_ -le 64 } { $SuggestLogIncrementSize = 64 }
									{ $_ -ge 64 -and $_ -lt 256 } { $SuggestLogIncrementSize = 256 }
									{ $_ -ge 256 -and $_ -lt 1024 } { $SuggestLogIncrementSize = 512 }
									{ $_ -ge 1024 -and $_ -lt 4096 } { $SuggestLogIncrementSize = 1024 }
									{ $_ -ge 4096 -and $_ -lt 8192 } { $SuggestLogIncrementSize = 2048 }
									{ $_ -ge 8192 -and $_ -lt 16384 } { $SuggestLogIncrementSize = 4096 }
									{ $_ -ge 16384 } { $SuggestLogIncrementSize = 8192 }
								}
							}
							else # 2008 R2 or under
							{
								switch ($TargetLogSizeMB)
								{
									{ $_ -le 64 } { $SuggestLogIncrementSize = 64 }
									{ $_ -ge 64 -and $_ -lt 256 } { $SuggestLogIncrementSize = 256 }
									{ $_ -ge 256 -and $_ -lt 1024 } { $SuggestLogIncrementSize = 512 }
									{ $_ -ge 1024 -and $_ -lt 4096 } { $SuggestLogIncrementSize = 1024 }
									{ $_ -ge 4096 -and $_ -lt 8192 } { $SuggestLogIncrementSize = 2048 }
									{ $_ -ge 8192 -and $_ -lt 16384 } { $SuggestLogIncrementSize = 4000 }
									{ $_ -ge 16384 } { $SuggestLogIncrementSize = 8000 }
								}
								
								if (($IncrementSizeMB % 4096) -eq 0)
								{
									Write-Output "Your instance version is below SQL 2012, remember the known BUG mentioned on HELP. `r`nUse Get-Help Expand-SqlTLogFileResponsibly to read help`r`nUse a different value for incremental size`r`n"
									return
								}
							}
							Write-Verbose "Instance $server version: $($server.Version.Major) - Suggested TLog increment size: $($SuggestLogIncrementSize)MB"
							
							# Shrink Log File to desired size before re-growth to desired size (You need to remove as many VLF's as possible to ensure proper growth)
							$ShrinkSizeMB = $ShrinkSize/1024
							if ($ShrinkLogFile -eq $true)
							{
								if ($server.Databases[$db].RecoveryModel -eq [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple)
								{
									Write-Warning "Database '$db' is in Simple RecoveryModel which does not allow log backups. Do not specify -ShrinkLogFile and -ShrinkSizeMB parameters."
									Continue
								}
								
								try
								{
									$sql = "SELECT last_log_backup_lsn FROM sys.database_recovery_status WHERE database_id = DB_ID('$db')"
									$sqlResult = $server.ConnectionContext.ExecuteWithResults($sql);
									
									if ($sqlResult.Tables[0].Rows[0]["last_log_backup_lsn"] -is [System.DBNull])
									{
										Write-Warning  "First, you need to make a full backup before you can do Tlog backup on database '$db' (last_log_backup_lsn is null)"
										Continue
									}
								}
								catch
								{
									throw "Can't execute SQL on $server. `r`n $($_)"
								}
								
								If ($Pscmdlet.ShouldProcess($($server.name), "Backing up TLog for $db"))
								{
									Write-Output "We are about to backup the Tlog for database '$db' to '$backupdirectory' and shrink the Log"
									$currentSizeMB = $currentSize/1024
									Write-Verbose "Starting Size = $currentSizeMB"
									
									$DefaultCompression = $server.Configuration.DefaultBackupCompression.ConfigValue
									
									if ($currentSizeMB -gt $ShrinkSizeMB)
									{
										$backupRetries = 1
										Do
										{
											try
											{
												$percent = $null
												$backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
												$backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Log
												$backup.BackupSetDescription = "Transaction Log backup of " + $db
												$backup.BackupSetName = $db + " Backup"
												$backup.Database = $db
												$backup.MediaDescription = "Disk"
												$dt = get-date -format yyyyMMddHHmmssms
												$dir = $backup.Devices.AddDevice($backupdirectory + "\" + $db + "_db_" + $dt + ".trn", 'File')
												if ($DefaultCompression = $true)
												{
													$backup.CompressionOption = 1
												}
												else
												{
													$backup.CompressionOption = 0
												}
												$percnt = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
													Write-Progress -id 2 -ParentId 1 -activity "Backing up $db to $server" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
												}
												$backup.add_PercentComplete($percent)
												$backup.PercentCompleteNotification = 10
												$backup.add_Complete($complete)
												Write-Progress -id 2 -ParentId 1 -activity "Backing up $db to $server" -percentcomplete 0 -statu ([System.String]::Format("Progress: {0} %", 0))
												$backup.SqlBackup($server)
												Write-Progress -id 2 -ParentId 1 -activity "Backing up $db to $server" -status "Complete" -Completed
												$logfile.Shrink($ShrinkSizeMB, [Microsoft.SQLServer.Management.SMO.ShrinkMethod]::TruncateOnly)
												$logfile.Refresh()
											}
											catch
											{
												Write-Progress -id 1 -activity "Backup" -status "Failed" -completed
												Write-Error "Backup failed for database '$db' with the following exception: $_"
												Continue
											}
											
										}
										while (($logfile.Size/1024) -gt $ShrinkSizeMB -and ++$backupRetries -lt 6)
										
										$currentSize = $logfile.Size
										Write-Output "TLog backup and truncate for database '$db' finished. Current tlog size after $backupRetries backups is $($currentSize/1024)MB"
									}
								}
							}
							
							# SMO uses values in KB
							$SuggestLogIncrementSize = $SuggestLogIncrementSize * 1024
							
							# If default, use $SuggestedLogIncrementSize
							if ($IncrementSizeMB -eq -1)
							{
								$LogIncrementSize = $SuggestLogIncrementSize
							}
							else
							{
								$title = "Choose increment value for database '$db':"
								$message = "The input value for increment size was $([System.Math]::Round($LogIncrementSize/1024, 0))MB. However the suggested value for increment is $($SuggestLogIncrentSize/1024)MB.`r`n Do you want to use the suggested value of $([System.Math]::Round($SuggestLogIncrementSize/1024, 0))MB insted of $([System.Math]::Round($LogIncrementSize/1024, 0))MB"
								$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Uses recomended size."
								$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will use parameter value."
								$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
								$result = $host.ui.PromptForChoice($title, $message, $options, 0)
								#yes
								if ($result -eq 0)
								{
									$LogIncrementSize = $SuggestLogIncrementSize
								}
							}
							
							#start grow file
							If ($Pscmdlet.ShouldProcess($($server.name), "Starting log growth. Increment chunk size: $($LogIncrementSize/1024)MB for database '$db'"))
							{
								Write-Output "Starting log growth. Increment chunk size: $($LogIncrementSize/1024)MB for database '$db'"
								
								Write-Verbose "$step - While current size less than target log size"
								
								while ($currentSize -lt $TargetLogSizeKB)
								{
									
									Write-Progress `
												   -Id 2 `
												   -ParentId 1 `
												   -Activity "Growing file $logfile on '$db' database" `
												   -PercentComplete ($currentSize / $TargetLogSizeKB * 100) `
												   -Status "Remaining - $([System.Math]::Round($($($TargetLogSizeKB - $currentSize) / 1024.0), 2)) MB"
									
									Write-Verbose "$step - Verifying if the log can grow or if it's already at the desired size"
									if (($TargetLogSizeKB - $currentSize) -lt $LogIncrementSize)
									{
										Write-Verbose "$step - Log size is lower than the increment size. Setting current size equals $TargetLogSizeKB"
										$currentSize = $TargetLogSizeKB
									}
									else
									{
										Write-Verbose "$step - Grow the $logfile file in $([System.Math]::Round($($LogIncrementSize / 1024.0), 2)) MB"
										$currentSize += $LogIncrementSize
									}
								}
								
								#When -WhatIf Switch, do not run
								if ($PSCmdlet.ShouldProcess("$step - File will grow to $([System.Math]::Round($($currentSize/1024.0), 2)) MB", "This action will grow the file $logfile on database $db to $([System.Math]::Round($($currentSize/1024.0), 2)) MB .`r`nDo you wish to continue?", "Performe grow"))
								{
									Write-Verbose "$step - Set size $logfile to $([System.Math]::Round($($currentSize/1024.0), 2)) MB"
									$logfile.size = $currentSize
									
									Write-Verbose "$step - Applying changes"
									$logfile.Alter()
									Write-Verbose "$step - Changes have been applied"
									
									#Will put the info like VolumeFreeSpace up to date
									$logfile.Refresh()
								}
								
								Write-Verbose "`r`n$step - [OK] Growth process for logfile '$logfile' on database '$db', has been finished."
								
								Write-Verbose "$step - Grow $logfile log file on $db database finished"
							}
						}
					} #else space available
				}
				else #else verifying existance
				{
					Write-Output "Database '$db' does not exist on instance '$SqlServer'"
				}
			}
		}
		catch
		{
			Write-Error "Logfile $logfile on database $db not processed. Error: $($_.Exception.Message). Line Number:  $($_InvocationInfo.ScriptLineNumber)"
		}
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
		Write-Output "Process finished $((Get-Date) - ($initialTime))"
	}
}