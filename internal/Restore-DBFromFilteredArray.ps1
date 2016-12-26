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
        $FunctionName = "Filter-DBFromFilteredArray"
        Write-Verbose "$FunctionName - Starting"



        $results = @()
        $InternalFiles = @()
    }
    # -and $_.BackupStartDate -lt $RestoreTime
    process
        {

        foreach ($file in $files){
            $InternalFiles += $file
        }
    }
    End
    {

		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
		$servername = $server.name
		$server.ConnectionContext.StatementTimeout = 0
		$restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
		$restore.ReplaceDatabase = $ReplaceDatabase

		If ($null -ne $server.Databases[$DbName])
		{
			Stop-DbaProcess -Databases $DbName
		}

		$OrderedRestores = $InternalFiles | Sort-object -Property BackupStartDate, BackupType
		Write-Verbose "of = $($OrderedRestores.Backupfilename)"
		foreach ($restorefile in $OrderedRestores)
		{
			if ($restore.RelocateFiles.count -gt 0)
			{
				$restore.RelocateFiles.Clear()
			}
			foreach ($file in $restorefile.Filelist)
			{

				if ($RestoreLocation -ne '' -and $filestructure -eq $NUll)
				{
					
					$movefile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
					$movefile.LogicalFileName = $file.logicalname
					$movefile.PhysicalFileName = $RestoreLocation + (split-path $file.PhysicalName -leaf)
					$null = $restore.RelocateFiles.Add($movefile)
					
				} elseif ($RestoreLocation -eq '' -and $filestructure -ne $NUll)
				{

					$filestructure = $filestructure.values

					foreach ($file in $filestructure)
					{
						$movefile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
						$movefile.LogicalFileName = $file.logical
						$movefile.PhysicalFileName = $file.physical

						$null = $restore.RelocateFiles.Add($movefile)
					}	
				} elseif ($RestoreLocation -ne '' -and $filestructure -ne $NUll)
				{
					Write-Error "Conflicting options only one of FileStructure or RestoreLocation allowed"
				} 		
			}

			try
			{
				Write-Verbose "in try"
				$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
					Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
				}
				$restore.add_PercentComplete($percent)
				$restore.PercentCompleteNotification = 1
				$restore.add_Complete($complete)
				$restore.ReplaceDatabase = $ReplaceDatabase
				$restore.ToPointInTime = $RestoreTime
				if ($DbName -ne '')
				{
					$restore.Database = $dbname
				}
				else
				{
					$restore.Database = $restorefile.DatabaseName
				}
				$action = switch ($restorefile.BackupType)
					{
						'1' {'Database'}
						'2' {'Log'}
						'5' {'Database'}
						Default {}
					}
				Write-Verbose "action = $action"
				$restore.Action = $action 
				if ($restorefile -eq $OrderedRestores[-1] -and $NoRecovery -ne $true)
				{
					#Do recovery on last file
					$restore.NoRecovery = $false
				}
				else 
				{
					$restore.NoRecovery = $true
				}

					$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
					$device.name = $restorefile.BackupPath
					$device.devicetype = "File"
					$restore.Devices.Add($device)

				Write-Verbose "PAst setup"
				if ($ScriptOnly)
				{
					$restore.Script($server)
				}
				elseif ($VerifyOnly)
				{
					Write-Progress -id 1 -activity "Verifying $dbname backup file on $servername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
					$verify = $restore.sqlverify($server)
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
					Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
					$restore.sqlrestore($server)
					if ($scripts)
					{
						$restore.Script($server)
					}
					Write-Progress -id 1 -activity "Restoring $dbname to $servername" -status "Complete" -Completed
					
					#return "Success"
				}
				$null = $restore.Devices.Remove($device)
				Remove-Variable device

			}
			catch
			{
				Write-Warning $_.Exception.InnerException
			}
			
		}
	}
}