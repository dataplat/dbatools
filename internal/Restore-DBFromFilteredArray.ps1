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
        [String]$RestoreLocation,
        [DateTime]$RestoreTime = (Get-Date).addyears(1),  
		[switch]$NoRecovery,
		[switch]$ReplaceDatabase,
		[switch]$Scripts,
        [switch]$ScriptOnly,
		[switch]$VerifyOnly,
		[object]$filestructure,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
    
	    Begin
    {
        $FunctionName = "Restore-DBFromFilteredArray"
        Write-Verbose "$FunctionName - Starting"



        $Results = @()
        $InternalFiles = @()
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

		$Server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
		$ServerName = $Server.name
		$Server.ConnectionContext.StatementTimeout = 0
		$Restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
		$Restore.ReplaceDatabase = $ReplaceDatabase

		If ($null -ne $Server.Databases[$DbName])
		{
			try
			{
				Write-Verbose "$FunctionName - Set $DbName offline to kill processes"
				Invoke-SQLcmd2 -ServerInstance:$SqlServer -Credential:$SqlCredential -query "Alter database $DbName set offline with rollback immediate; use $DbName"

			}
			catch
			{
				Write-Verbose "$FunctionName - No processes to kill"
			}
		}

		$OrderedRestores = $InternalFiles | Sort-object -Property BackupStartDate, BackupType
		Write-Verbose "of = $($OrderedRestores.Backupfilename)"
		foreach ($RestoreFile in $OrderedRestores)
		{
			if ($Restore.RelocateFiles.count -gt 0)
			{
				$Restore.RelocateFiles.Clear()
			}
			foreach ($File in $RestoreFile.Filelist)
			{

				if ($RestoreLocation -ne '' -and $FileStructure -eq $NUll)
				{
					
					$MoveFile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
					$MoveFile.LogicalFileName = $File.LogicalName
					$MoveFile.PhysicalFileName = $RestoreLocation + (split-path $file.PhysicalName -leaf)
					$null = $Restore.RelocateFiles.Add($MoveFile)
					
				} elseif ($RestoreLocation -eq '' -and $FileStructure -ne $NUll)
				{

					$FileStructure = $FileStructure.values

					foreach ($File in $FileStructure)
					{
						$MoveFile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
						$MoveFile.LogicalFileName = $File.logical
						$MoveFile.PhysicalFileName = $File.physical

						$null = $Restore.RelocateFiles.Add($MoveFile)
					}	
				} elseif ($RestoreLocation -ne '' -and $FileStructure -ne $NUll)
				{
					Write-Error "Conflicting options only one of FileStructure or RestoreLocation allowed"
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
				$Restore.ToPointInTime = $RestoreTime
				if ($DbName -ne '')
				{
					$Restore.Database = $DbName
				}
				else
				{
					$Restore.Database = $RestoreRile.DatabaseName
				}
				$Action = switch ($RestoreFile.BackupType)
					{
						'1' {'Database'}
						'2' {'Log'}
						'5' {'Database'}
						Default {}
					}
				Write-Verbose "$FunctionName restore action = $Action"
				$restore.Action = $Action 
				if ($RestoreFile -eq $OrderedRestores[-1] -and $NoRecovery -ne $true)
				{
					#Do recovery on last file
					Write-Verbose "$FunctionName - Doing Recovery on last file"
					$Restore.NoRecovery = $false
				}
				else 
				{
					$Restore.NoRecovery = $true
				}

					$Device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
					$Device.Name = $RestoreFile.BackupPath
					$Device.devicetype = "File"
					$Restore.Devices.Add($device)

				Write-Verbose "$FunctionName - Performaing restore action"
				if ($ScriptOnly)
				{
					$restore.Script($server)
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
						$restore.Script($Server)
					}
					Write-Progress -id 1 -activity "Restoring $DbName to $ServerName" -status "Complete" -Completed
					
					#return "Success"
				}
				$null = $Restore.Devices.Remove($Device)
				Remove-Variable device
			}
			catch
			{
				Write-Warning $_.Exception.InnerException
			}
			
		}
		if ($NoRecovery -eq $false -and $ScriptOnly -eq $false)
		{
			Invoke-SQLcmd2 -ServerInstance:$SqlServer -Credential:$SqlCredential -query "Restore database $DbName with recovery"
		}
		#$server.ConnectionContext.Disconnect()
	}
}