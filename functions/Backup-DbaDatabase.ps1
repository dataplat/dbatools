<#

# If backup file isn't provided, auto generate in Default backup dir?
# Can you please compare the options Microsoft provides? If it's too crazy, we can make this 1.0
# needs to accept credential and needs help, per usual, this is just a skeleton.
#>
Function Backup-DbaDatabase
{
	[CmdletBinding()]
	param (
		[parameter(ValueFromPipeline = $True)]
		[object[]]$DatabaseName, # Gotten from Get-DbaDatabase
		[object]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[string]$BackupFile,
		[switch]$NoCopyOnly,
		[ValidateSet('Full', 'Log', 'Differential','Diff','Database')] # Unsure of the names
		[string]$BackupType = "Full",
		[int]$FileCount = 1

	)
	BEGIN
	{
		$FunctionName = $FunctionName =(Get-PSCallstack)[0].Command
		$Databases = @()
	}
	PROCESS
	{
	
		foreach ($Name in $DatabaseName)
		{
			if ($Name -is [String])
			{
				$Databases += [PSCustomObject]@{Name = $Name; RecoveryModel=''}
			}
			elseif ($Name -is [System.Object] -and $Name.Name.Length -ne 0 )
			{
				$Databases += [PSCustomObject]@{Name = 'name'; RecoveryModel= $RecoveryModel}
			}
		}
	}
	END
	{
		try 
		{
			$Server = Connect-SqlServer -SqlServer $SqlInstance -SqlCredential $SqlCredential	          
		}
		catch {
            $server.ConnectionContext.Disconnect()
			Write-Warning "$FunctionName - Cannot connect to $SqlInstance" -WarningAction Stop
		}
		$BackupHistory = Get-DbaBackupHistory -SqlServer $SqlInstance -databases ($Databases.Name -join ',') -LastFull
		ForEach ($Database in $Databases)
		{
			if ($Database.RecoveryModel -ne '')
			{
				$Database.RecoveryModel = $server.databases[$Database.Name].RecoveryModel
			}
			
			if ($Database.RecoveryModel -eq 'Simple' -and $BackupType -eq 'Log')
			{
				Write-Warning "$FunctionName - $($Database.Name) is in simple recovery mode, cannot take log backup"
				break
			}
			$FullExists = $BackupHistory | Where-Object {$_.Database -eq $Database.Name}
			if ($BackupType -ne "Full" -and $FullExists.length -eq 0)
			{
				Write-Warning "$FunctionName - $($Database.Name) does not have an existing full backup, cannot take log or differentialbackup"
				break				
			}

			$val = 0
			$copyonly = !$NoCopyOnly
			
			$server.ConnectionContext.StatementTimeout = 0
			$backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
			$backup.Database = $Database.Name
			$Type = "Database"
			if ($BackupType -eq "Log") {$Type = "Log" }
			$backup.Action = $Type
			$backup.CopyOnly = $copyonly
			if ($Type -eq "Differential")
			{
				$backup.Incremental = $true
			}
			while ($val -lt $filecount)
			{
				$device = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem
				$device.DeviceType = "File"
				$device.Name = $backupfile.Replace(".bak", "-$val.bak")
				$backup.Devices.Add($device)
				$val++
			}
			$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
				Write-Progress -id 1 -activity "Backing up database $($Database.Name)  to $backupfile" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
			}
			$backup.add_PercentComplete($percent)
			$backup.PercentCompleteNotification = 1
			$backup.add_Complete($complete)
			
			Write-Progress -id 1 -activity "Backing up database $($Database.Name)  to $backupfile" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
			Write-Output "Backing up $($Database.Name)"
			
			try
			{
				$backup.SqlBackup($server)
				Write-Progress -id 1 -activity "Backing up database $($Database.Name)  to $backupfile" -status "Complete" -Completed
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

}

