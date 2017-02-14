<#

# If backup file isn't provided, auto generate in Default backup dir?
# Can you please compare the options Microsoft provides? If it's too crazy, we can make this 1.0
# needs to accept credential and needs help, per usual, this is just a skeleton.

Function Backup-DbaDatabase
		{
			[CmdletBinding()]
			param (
				[object]$SqlInstance,
				[string]$DatabaseName,
				[string]$BackupFile,
				[switch]$NoCopyOnly,
				[ValidateSet('Full', 'Log', 'Differential')] # Unsure of the names
				[string]$Type = "Full",
				[int]$FileCount = 1
				[parameter(ValueFromPipeline = $True)]
				[object]$Database # Gotten from Get-DbaDatabase
			)
			
			if ($Type -eq "Full") { $type = "Database" } #maybe others?
			$val = 0
			$copyonly = !$NoCopyOnly
			
			$server.ConnectionContext.StatementTimeout = 0
			$backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
			$backup.Database = $dbname
			$backup.Action = $Type
			$backup.CopyOnly = $copyonly
			
			while ($val -lt $filecount)
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
				$backup.SqlBackup($server)
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
