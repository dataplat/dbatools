<#
		Function Backup-DbaDatabase
		{
			[CmdletBinding()]
			param (
				[object]$sqlInstance,
				[string]$dbname,
				[string]$backupfile,
				[int]$numberfiles
			)
			
			$sqlInstance.ConnectionContext.StatementTimeout = 0
			$backup = New-Object "Microsoft.SqlServer.Management.Smo.Backup"
			$backup.Database = $dbname
			$backup.Action = "Database"
			$backup.CopyOnly = $true
			$val = 0
			
			while ($val -lt $numberfiles)
			{
				$device = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem
				$device.DeviceType = "File"
				$device.Name = $backupfile.Replace(".bak", "-$val.bak")
				$backup.Devices.Add($device)
				$val++
			}
			
			$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
				Write-Progress -id 1 -activity "Backing up database $dbname to $backupfile" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
			}
			$backup.add_PercentComplete($percent)
			$backup.PercentCompleteNotification = 1
			$backup.add_Complete($complete)
			
			Write-Progress -id 1 -activity "Backing up database $dbname to $backupfile" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
			Write-Output "Backing up $dbname"
			
			try
			{
				$backup.SqlBackup($sqlInstance)
				Write-Progress -id 1 -activity "Backing up database $dbname to $backupfile" -status "Complete" -Completed
				Write-Output "Backup succeeded"
				return $true
			}
			catch
			{
				Write-Progress -id 1 -activity "Backup" -status "Failed" -completed
				Write-Exception $_
				return $false
			}
		}
	}
#>
