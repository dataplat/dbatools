Function Restore-DBFromFilteredArray
{
<# 
	.SYNOPSIS
	Internal function. Restores .bak file to SQL database. Creates db if it doesn't exist. $filestructure is
	a custom object that contains logical and physical file locations.
#>
	[CmdletBinding()]
	param (
        [parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[string]$DbName,
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Files,
        [String]$DestinationDataDirectory,
		[String]$DestinationLogDirectory,
        [DateTime]$RestoreTime = (Get-Date).addyears(1),  
		[switch]$NoRecovery,
		[switch]$ReplaceDatabase,
		[switch]$Scripts,
        [switch]$ScriptOnly,
		[switch]$VerifyOnly,
		[object]$filestructure,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$UseDestinationDefaultDirectories
	)
    
	    Begin
    {
        $FunctionName = "Restore-DBFromFilteredArray"
        Write-Verbose "$FunctionName - Starting"



        $Results = @()
        $InternalFiles = @()
		$Output = @()

    }
    # -and $_.BackupStartDate -lt $RestoreTime
    process
        {

        foreach ($File in $Files){
            $InternalFiles += $File
        }
    }
    End
    {
		try 
		{
			$Server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential	
		}
		catch {
			$server.ConnectionContext.Disconnect()
			Write-Warning "$FunctionName - Cannot connect to $SqlServer" -WarningAction Stop

		}
		
		$ServerName = $Server.name
		$Server.ConnectionContext.StatementTimeout = 0
		$Restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
		$Restore.ReplaceDatabase = $ReplaceDatabase
		if ($UseDestinationDefaultDirectories)
		{
			$DestinationDataDirectory = $server.DefaultFile
			$DestinationLogDirectory = $Server.DefaultLog
		}

		If ($null -ne $Server.Databases[$DbName] -and $ScriptOnly -eq $false)
		{
			$null = $server.databases["Master"]
			If ($ReplaceDatabase -eq $true)
			{				
				try
				{
					Write-Verbose "$FunctionName - Set $DbName single_user to kill processes"
					#Invoke-SQLcmd2 -ServerInstance:$SqlServer -Credential:$SqlCredential -query "Alter database $DbName set single_user with rollback immediate;Alter database $DbName set Multi_user with rollback immediate;" -database master
					Invoke-SQLcmd2 -ServerInstance:$SqlServer -Credential:$SqlCredential -query "Alter database $DbName set offline with rollback immediate; Alter database $DbName set online with rollback immediate" -database master

				}
				catch
				{
					Write-Verbose "$FunctionName - No processes to kill"
				}
			}
			else 
			{
				Write-warning "$FunctionName - $DBname exists, must use WithReplace to overwrite" -WarningAction Stop
				break
			}
		}

		$RestorePoints = $InternalFiles | Sort-Object BackupTypeDescription, FirstLSN | Group-Object -Property FirstLSN | Select-Object -property Name 
		foreach ($RestorePoint in $RestorePoints)
		{
	
			$RestoreFiles = @($InternalFiles | Where-Object {$_.FirstLSN -eq $RestorePoint.Name})
			Write-verbose "$FunctionName - Restoring backup starting at LSN $($RestorePoint.Name) in $($RestoreFiles[0].BackupPath)"
			if ($Restore.RelocateFiles.count -gt 0)
			{
				$Restore.RelocateFiles.Clear()
			}
			foreach ($File in $RestoreFiles[0].Filelist)
			{

				if ($DestinationDataDirectory -ne '' -and $FileStructure -eq $NUll)
				{
					
					$MoveFile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
					$MoveFile.LogicalFileName = $File.LogicalName
					if ($File.Type -eq 'L' -and $DestinationLogDirectory -ne '')
					{
						$MoveFile.PhysicalFileName = $DestinationLogDirectory + '\' + (split-path $file.PhysicalName -leaf)					
					}
					else {
						$MoveFile.PhysicalFileName = $DestinationDataDirectory + '\' + (split-path $file.PhysicalName -leaf)	
					}
					$null = $Restore.RelocateFiles.Add($MoveFile)
					
				} elseif ($DestinationDataDirectory -eq '' -and $FileStructure -ne $NUll)
				{

					foreach ($key in $FileStructure.keys)
					{
						$MoveFile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
						$MoveFile.LogicalFileName = $key
						$MoveFile.PhysicalFileName = $filestructure[$key]

						$null = $Restore.RelocateFiles.Add($MoveFile)
					}	
				} elseif ($DestinationDataDirectory -ne '' -and $FileStructure -ne $NUll)
				{
					Write-Warning "$FunctionName - Conflicting options only one of FileStructure or DestinationDataDirectory allowed" -WarningAction Stop
				} 		
			}

			try
			{
				Write-Verbose "$FunctionName - Beginning Restore"
				$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
					Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
				}
				$Restore.add_PercentComplete($percent)
				$Restore.PercentCompleteNotification = 1
				$Restore.add_Complete($complete)
				$Restore.ReplaceDatabase = $ReplaceDatabase
				if ($RestoreTime -gt (Get-Date))
				{
						$restore.ToPointInTime = $null
				}
				elseif ($RestoreFiles[0].RecoveryModel -ne 'Simple')
				{
					$Restore.ToPointInTime = $RestoreTime
				} 
				else 
				{
					Write-Verbose "$FunctionName - Restoring a Simmple mode db, no restoretime"	
				}
				if ($DbName -ne '')
				{
					$Restore.Database = $DbName
				}
				else
				{
					$Restore.Database = $RestoreFiles[0].DatabaseName
				}
				$Action = switch ($RestoreFiles[0].BackupType)
					{
						'1' {'Database'}
						'2' {'Log'}
						'5' {'Database'}
						Default {'Unknown'}
					}
				Write-Verbose "$FunctionName - restore action = $Action"
				$restore.Action = $Action 
				if ($RestorePoint -eq $RestorePoints[-1] -and $NoRecovery -ne $true)
				{
					#Do recovery on last file
					Write-Verbose "$FunctionName - Doing Recovery on last file"
					$Restore.NoRecovery = $false
				}
				else 
				{
					Write-Verbose "$FunctionName - More files to restore, NoRecovery set"
					$Restore.NoRecovery = $true
				}
				Foreach ($RestoreFile in $RestoreFiles)
				{
					$Device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
					$Device.Name = $RestoreFile.BackupPath
					$Device.devicetype = "File"
					$Restore.Devices.Add($device)
				}
				Write-Verbose "$FunctionName - Performing restore action"
				$RestoreComplete = $true
				if ($ScriptOnly)
				{
					$script = $restore.Script($server)
				}
				elseif ($VerifyOnly)
				{
					Write-Progress -id 1 -activity "Verifying $dbname backup file on $servername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
					$Verify = $restore.sqlverify($server)
					Write-Progress -id 1 -activity "Verifying $dbname backup file on $servername" -status "Complete" -Completed
					
					if ($verify -eq $true)
					{
						return "Verify successful"
					}
					else
					{
						return "Verify failed"
					}
				}
				else
				{
					Write-Progress -id 1 -activity "Restoring $DbName to ServerName" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
					$Restore.sqlrestore($Server)
					if ($scripts)
					{
						$script = $restore.Script($Server)
					}
					Write-Progress -id 1 -activity "Restoring $DbName to $ServerName" -status "Complete" -Completed
					
				}

			}
			catch
			{
				write-verbose "$FunctionName - Closing Server connection"
				$RestoreComplete = $False
				$ExitError = $_.Exception.InnerException
				Write-Warning "$FunctionName - $ExitError" -WarningAction stop
				#Exit as once one restore has failed there's no point continuing
				break
				
			}
			finally
			{	
				[PSCustomObject]@{
                    SqlInstance = $SqlServer
                    DatabaseName = $DatabaseName
                    DatabaseOwner = $server.ConnectionContext.TrueLogin
					RestoreComplete  = $RestoreComplete
                    BackupFilesCount = $RestoreFiles.Length
                    RestoredFilesCount = $RestoreFiles[0].Filelist.PhysicalName.count
                    NoRecovery = $restore.NoRecovery
                    BackupSizeMB = ($RestoreFiles | measure-object -property BackupSizeMb -Sum).sum
                    CompressedBackupSizeMB = ($RestoreFiles | measure-object -property CompressedBackupSizeMb -Sum).sum
                    BackupFile = $RestoreFiles.BackupPath -join ','
					RestoredFile = $RestoreFiles[0].Filelist.PhysicalName -join ','
					BackupSize = ($RestoreFiles | measure-object -property BackupSize -Sum).sum
					CompressedBackupSize = ($RestoreFiles | measure-object -property CompressedBackupSize -Sum).sum
                    TSql = $script  
					BackupFileRaw = $RestoreFiles
					ExitError = $ExitError				
                } | Select-DefaultView -ExcludeProperty BackupSize, CompressedBackupSize, ExitError, BackupFileRaw 
				while ($Restore.Devices.count -gt 0)
				{
					$device = $restore.devices[0]
					$null = $restore.devices.remove($Device)
				}
				write-verbose "$FunctionName - Closing Server connection"
				$server.ConnectionContext.Disconnect()
			}
			
		}
		$server.ConnectionContext.Disconnect()
	}
}