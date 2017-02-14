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
		[string]$BackupPath,
		[string]$BackupFileName,
		[switch]$NoCopyOnly,
		[ValidateSet('Full', 'Log', 'Differential','Diff','Database')] # Unsure of the names
		[string]$BackupType = "Full",
		[int]$FileCount = 1,
		[switch]$CreateFolder=$true

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
		if ($databases.count -gt 1 -and $BackupFileName -ne '')
		{
			Write-warning "$FunctionName - 1 BackupFile specified, but more than 1 database."
			break
		}
		if ($databases.count -gt 1 -and $BackupPath -eq '')
		{
			$BackupPath = $server.BackupDirectory
		}
		else 
		{
			$MultiFile = $true	
		}
		$BackupHistory = Get-DbaBackupHistory -SqlServer $SqlInstance -databases ($Databases.Name -join ',') -LastFull -ErrorAction SilentlyContinue
		ForEach ($Database in $Databases)
		{
			Write-Verbose "$FunctionName - Backup up database $($Database.name)"
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
			$Suffix = "bak"
			if ($BackupType -eq "Log")
			{
					$Type = "Log" 
					$Suffix = "trn"
			}
			$backup.Action = $Type
			$backup.CopyOnly = $copyonly
			if ($Type -eq "Differential")
			{
				$backup.Incremental = $true
			}
			if ($MultiFile)
			{
				Write-Verbose "$($Database.name)"
				if ($CreateFolder)
				{
					if((Test-Path ($BackupPath+'\'+$Database.name)) -eq $false)
					{
						$BackupPath = $BackupPath+'\'+$Database.name
						New-Item $BackupPath -type Directory
						
					}
				}
				$TimeStamp = (Get-date -Format yyyyMMddHHmm)
				$BackupFile = $BackupPath+"\"+($Database.name)+"_"+$Timestamp+"."+$suffix

			}
			Write-Verbose "$FunctionName - Backing up to $backupfile"
		
			while ($val -lt $filecount)
			{
				$device = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem
				$device.DeviceType = "File"
				$device.Name = $backupfile.Replace(".$suffix", "-$val.$suffix")
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

