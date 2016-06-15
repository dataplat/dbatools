function Expand-SqlTLogResponsibly
{
	#AUTHOR: Cláudio Silva
	#DATE: 2015-06-13
	#Follow me on twitter @ClaudioESSilva
	
<#

.SYNOPSIS
This module will help you to automatically grow your T-Log database file in a responsible way (preventing generation of too many VLFs).

.DESCRIPTION
As you may already know, having a TLog file with too many VLFs can hurt your database performance in many ways.

Example:
    Too many virtual log files can cause transaction log backups to slow down and can also slow down database recovery, and in extreme cases, even affect insert/update/delete performance. 
    References:
        http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
        http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx
        http://www.brentozar.com/blitz/high-virtual-log-file-vlf-count/

    In order to get rid of this fragmentation we need to growth the file taking the following consideration:
        - How many VLFs are created when we do a grow or when auto-grows hits
    Note: In SQL Server 2014 this algorithm has changed (http://www.sqlskills.com/blogs/paul/important-change-vlf-creation-algorithm-sql-server-2014/)

Atention:
    We are growing in MB instead of GB because of known issue prior to SQL 2012:
        More detail here: 
            http://www.sqlskills.com/BLOGS/PAUL/post/Bug-log-file-growth-broken-for-multiples-of-4GB.aspx
	    and 
            http://connect.microsoft.com/SQLServer/feedback/details/481594/log-growth-not-working-properly-with-specific-growth-sizes-vlfs-also-not-created-appropriately
	    or 
            https://connect.microsoft.com/SQLServer/feedback/details/357502/transaction-log-file-size-will-not-grow-exactly-4gb-when-filegrowth-4gb

.NOTES
    What this script will NOT DO for you:
        1. Analyse the actual number of VLFs (use DBCC LOGINFO)
        2. T-Log backups (BACKUP LOG <databasename> TO DISK="<path>" or using third-party tools)
        3. Truncate your transaction log (DBCC SHRINKFILE (N'<database_log>', TRUNCATEONLY).
        *************************************************************************************************************
        4. Repeat steps 2 and 3 until you have your T-Log with the desired initial size. Then you may run this script.
		   Steps 2 and 3 are likely to be automated in the future.
        *************************************************************************************************************

    You have to make those analysis and take these actions before run this script otherwise only half of the correct process will be made

.LINK
    Understand related problems:
        http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
        http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx
        http://www.brentozar.com/blitz/high-virtual-log-file-vlf-count/
    
    Known BUG before SQL Server 2012
        http://www.sqlskills.com/BLOGS/PAUL/post/Bug-log-file-growth-broken-for-multiples-of-4GB.aspx
        http://connect.microsoft.com/SQLServer/feedback/details/481594/log-growth-not-working-properly-with-specific-growth-sizes-vlfs-also-not-created-appropriately
        https://connect.microsoft.com/SQLServer/feedback/details/357502/transaction-log-file-size-will-not-grow-exactly-4gb-when-filegrowth-4gb

.PARAMETER SqlServer 
    Represents the name/ip of the instance where the database(s) that you want to grow exists
     
.PARAMETER Databases
    This is the list of databases within Instance that this script will grow their t-log files.
    You can pass only one or many. Can be input by pipeline. (view examples)

.PARAMETER TargetLogSizeMB
    Represents the target log size that log will grow. Expressed in MB.
    
.PARAMETER IncrementSizeMB
    Represents the size of each grow will perform. Expressed in MB.
    If you don't provide this parameter the value will be calculated automatically. Otherwise, the input value will be compared with the suggested 
    for your target size. If it is different will ask which one you would like to assume.

.PARAMETER LogFileId
    If you want to grow a secondary, tertiary, other T-Log file you can mention the log file number (FileId column from DBCC LOGINFO output).
    When not provided, will do on the first T-Log file.

.NOTES 
Author: Cláudio Silva (@claudioessilva)
Requires: ALTER DATABASE permission
Limitations: On SQL Server 2005 cannot validate freespace on drive where log file resides.

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com / claudiosil100@gmail.com)
Copyright (C) 2016 Cláudio Silva

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

.EXAMPLE
    Expand-DatabaseTLogFileResponsibly -SqlServer '.' -Databases 'Test' -TargetLogSizeMB 50000
    This is the simplest example. The increment value will be calculated and will grow the T-Log of 'Test' database on 'Localhost' instance 
    to 50000 MB.

.EXAMPLE
    Expand-DatabaseTLogFileResponsibly -SqlServer '.' -Databases 'Test' -TargetLogSizeMB 10000 -IncrementSizeMB 200
    Grows the T-Log of 'Test' database on 'Localhost' instance to 1000MB. The increment value will be asked if want to use the input value or 
    the suggested one (calculated automatically)

.EXAMPLE
    Expand-DatabaseTLogFileResponsibly -SqlServer '.' -Databases 'Test' -TargetLogSizeMB 10000 -LogFileNumber 9
    Grows the T-Log with FielId 9 of 'Test' database on 'Localhost' instance to 10000MB.

.EXAMPLE
    Expand-DatabaseTLogFileResponsibly -SqlServer '.' -Databases (gc D:\DBs.txt) -TargetLogSizeMB 50000
    Grows the T-Log of the databases specified in the file 'D:\DBs.txt' on 'Localhost' instance to 50000MB.

.EXAMPLE
    Expand-DatabaseTLogFileResponsibly -SqlServer '.' -Databases @("DB1", "DB2") -TargetLogSizeMB 50000
    Grows the T-Log of the databases DB1 and DB2 on 'Localhost' instance to 50000MB.

.EXAMPLE
    Expand-DatabaseTLogFileResponsibly -SqlServer '.' -Databases 'Test' -TargetLogSizeMB 50000 -Verbose
    Use -Verbose to view in detail all actions performed by this script
#>
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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
		[int]$LogFileId = -1
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
	}
	
	PROCESS
	{
		try
		{
			$databases = $psboundparameters.Databases
			
			[datetime]$initialTime = Get-Date
			
			#control the iteration number
			$i = 0;
			
			#go through all databases
			Write-Verbose "Processing...foreach database..."
			foreach ($db in $Databases)
			{
				$i += 1
				
				#set step to reutilize on logging operations
				[string]$step = "$i/$($Databases.Count)"
				
				if ($server.Databases[$db])
				{
					Write-Progress `
								   -Id 1 `
								   -Activity "Using database: $db on Instance: '$SqlServer'" `
								   -PercentComplete ($i / $Databases.Count * 100) `
								   -Status "Processing - $i of $($Databases.Count)"
					
					#Validate which log that file will grow
					if ($LogByFileID)
					{
						$logfile = $server.Databases[$db].LogFiles.ItemById($LogFileId)
					}
					else
					{
						$logfile = $server.Databases[$db].LogFiles[0]
					}
					
					Write-Verbose "$step - Use log file: $logfile"
					$CurrSize = $logfile.Size
					
					Write-Verbose "$step - Log file current size: $([System.Math]::Round($($CurrSize/1024.0), 2)) MB "
					[long]$requiredSpace = ($TargetLogSizeKB - $CurrSize)
					
					Write-Output $logfile
					
					Write-Verbose "Verifying if exists sufficient space ($([System.Math]::Round($($requiredSpace / 1024.0), 2))MB) on the volume to performe this task"
					
					#Only available from 2008 R2 towards... maybe validate the version and issue a warning saying "can't verify volume free space"
					if ($requiredSpace -gt $logfile.VolumeFreeSpace)
					{
						Write-Output "There is not enough space on volume to perform this task. `r`n" `
									 "Available space: $([System.Math]::Round($($logfile.VolumeFreeSpace / 1024.0), 2))MB;`r`n" `
									 " Required space: $([System.Math]::Round($($requiredSpace / 1024.0), 2))MB;"
						return
					}
					else
					{
						# SQL 2005 or lower version. The "VolumeFreeSpace" property is empty
						if ($logfile.VolumeFreeSpace -eq $null)
						{
							$choice = ""
							while ($choice -notmatch "[y|n]")
							{
								$choice = read-host "Cannot validate freespace on drive where log file resides? Do you wish to continue (Y/N)"
							}
							
							if ($choice.ToLower() -eq "n")
							{
								Write-Output "You have cancelled the execution"
								#end script
								return
							}
							
						}
						
						if ($CurrSize -ige $TargetLogSizeKB)
						{
							Write-Output "$step - [INFO] The T-Log file '$logfile' size is already equal or greater than target size - No action required"
						}
						else
						{
							Write-Verbose "$step - [OK] There is sufficient free space to perform this task"
							
							# If version greater or equal 2012
							if ($server.Version.Major -ge "11")
							{
								switch ($TargetLogSizeMB)
								{
									{ $_ -le 64 } { $SuggestLogIncrementSize = 64 }
									{ $_ -gt 64 -and $_ -lt 256 } { $SuggestLogIncrementSize = 256 }
									{ $_ -gt 256 -and $_ -lt 1024 } { $SuggestLogIncrementSize = 512 }
									{ $_ -gt 1024 -and $_ -lt 4096 } { $SuggestLogIncrementSize = 1024 }
									{ $_ -gt 4096 -and $_ -lt 8192 } { $SuggestLogIncrementSize = 2048 }
									{ $_ -gt 8192 -and $_ -lt 16384 } { $SuggestLogIncrementSize = 4096 }
									{ $_ -ge 16384 } { $SuggestLogIncrementSize = 8192 }
								}
							}
							else # 2008 R2 or under

							{
								switch ($TargetLogSizeMB)
								{
									{ $_ -le 64 } { $SuggestLogIncrementSize = 64 }
									{ $_ -gt 64 -and $_ -lt 256 } { $SuggestLogIncrementSize = 256 }
									{ $_ -gt 256 -and $_ -lt 1024 } { $SuggestLogIncrementSize = 512 }
									{ $_ -gt 1024 -and $_ -lt 4096 } { $SuggestLogIncrementSize = 1024 }
									{ $_ -gt 4096 -and $_ -lt 8192 } { $SuggestLogIncrementSize = 2048 }
									{ $_ -gt 8192 -and $_ -lt 16384 } { $SuggestLogIncrementSize = 4000 }
									{ $_ -ge 16384 } { $SuggestLogIncrementSize = 8000 }
								}
								
								if (($IncrementSizeMB % 4096) -eq 0)
								{
									Write-Output "Your instance version is below SQL 2012, remember the known BUG mentioned on HELP. `r`nUse Get-Help Expand-SqlTLogFileResponsibly to read help`r`nUse a different value for incremente size`r`n"
									#TODO: Write-error???
									return
								}
							}
							Write-Verbose "Instance $server version: $($server.Version.Major) - Suggested TLog increment size: $($SuggestLogIncrementSize)MB"
							
							# SMO use values in KB
							$SuggestLogIncrementSize = $SuggestLogIncrementSize * 1024
							
							# If default will use $SuggestedLogIncrementSize
							if ($IncrementSizeMB -eq -1)
							{
								$LogIncrementSize = $SuggestLogIncrementSize
							}
							else
							{
								if ($PSCmdlet.ShouldProcess("Confirm increment value", `
								"The input value is $([System.Math]::Round($LogIncrementSize/1024, 0))MB. However the suggested value for increment is $($SuggestLogIncrementSize/1024)MB.`r`n Do you want to use the suggested value of $([System.Math]::Round($SuggestLogIncrementSize/1024, 0))MB insted of $([System.Math]::Round($LogIncrementSize/1024, 0))MB",
								"Choose increment value:"))
								{
									$LogIncrementSize = $SuggestLogIncrementSize
								}
							}
							Write-Output "Chunk size: $($LogIncrementSize/1024)MB"
							
							#start grow file
							Write-Verbose "$step - While current size less than wanted log size"
							while ($CurrSize -lt $TargetLogSizeKB)
							{
								
								Write-Progress `
											   -Id 2 `
											   -ParentId 1 `
											   -Activity "Growing file $logfile on '$db' database" `
											   -PercentComplete ($CurrSize / $TargetLogSizeKB * 100) `
											   -Status "Remaining - $([System.Math]::Round($($($TargetLogSizeKB - $CurrSize) / 1024.0), 2)) MB"
								
								Write-Verbose "$step - Verifying if the log can grow or if has already the desired space allocated"
								if (($TargetLogSizeKB - $CurrSize) -lt $LogIncrementSize)
								{
									Write-Verbose "$step - Log size is lower than the increment size. Setting current size equals $TargetLogSizeKB"
									$CurrSize = $TargetLogSizeKB
								}
								else
								{
									Write-Verbose "$step - Grow the $logfile file in $([System.Math]::Round($($LogIncrementSize / 1024.0), 2)) MB"
									$CurrSize += $LogIncrementSize
								}
								
								#When -WhatIf Switch, do not run
								if ($PSCmdlet.ShouldProcess("$step - File will grow to $([System.Math]::Round($($CurrSize/1024.0), 2)) MB", "This action will grow the file $logfile on database $db to $([System.Math]::Round($($CurrSize/1024.0), 2)) MB .`r`nDo you wish to continue?", "Performe grow"))
								{
									Write-Verbose "$step - Set size $logfile to $([System.Math]::Round($($CurrSize/1024.0), 2)) MB"
									$logfile.size = $CurrSize
									
									Write-Verbose "$step - Applying changes"
									$logfile.Alter()
									Write-Verbose "$step - Changes have been applied"
									
									#Will put the info like VolumeFreeSpace up to date
									$logfile.Refresh()
								}
							}
							Write-Verbose "`r`n$step - [OK] Growth process for logfile '$logfile' on database '$db', has been finished."
							
							Write-Verbose "$step - Grow $logfile log file on $db database finished"
						}
					} #else space available
				}
				else #else verifying existance

				{
					Write-Output "Database '$db' not exists on instance '$SqlServer'"
				}
			}
		}
		catch
		{
			Write-Output "Logfile $logfile on database $db not processed. Error: $($_.Exception.Message). Line Number:  $($_InvocationInfo.ScriptLineNumber)"
		}
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
		Write-Output "Process finished $((Get-Date) - ($initialTime))"
	}
}
