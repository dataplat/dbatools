Function Restore-Database
{
<# 
	.SYNOPSIS
	Internal function. Restores .bak file to SQL database. Creates db if it doesn't exist. $filestructure is
	a custom object that contains logical and physical file locations.
#>
	[CmdletBinding()]
	param (
		[Alias("ServerInstance", "SqlServer")]
		[object]$SqlInstance,
		[string]$DbName,
		[string[]]$BackupFile,
		[string]$FileType = "Database",
		[object]$FileStructure,
		[switch]$NoRecovery,
		[switch]$ReplaceDatabase,
		[Alias("Tsql")]
		[switch]$ScriptOnly,
		[switch]$VerifyOnly,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential
	)
	
	$server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
	$servername = $server.name
	$server.ConnectionContext.StatementTimeout = 0
	$restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
	$restore.ReplaceDatabase = $ReplaceDatabase
	
	if ($filestructure.values -ne $null)
	{
		$filestructure = $filestructure.values
	}
	
	foreach ($file in $filestructure)
	{
		$movefile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
		$movefile.LogicalFileName = $file.logical
		$movefile.PhysicalFileName = $file.physical
		$null = $restore.RelocateFiles.Add($movefile)
	}
	
	try
	{
		$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
			Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
		}
		
		$restore.add_PercentComplete($percent)
		$restore.PercentCompleteNotification = 1
		$restore.add_Complete($complete)
		$restore.ReplaceDatabase = $ReplaceDatabase
		$restore.Database = $dbname
		$restore.Action = $filetype
		$restore.NoRecovery = $norecovery
		
		foreach ($file in $backupfile)
		{
			$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
			$device.name = $file
			$device.devicetype = "File"
			$restore.Devices.Add($device)
		}
		
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
			Write-Progress -id 1 -activity "Restoring $dbname to $servername" -status "Complete" -Completed
			
			return "Success"
		}
	}
	catch
	{
		Write-Warning $_.Exception
		Write-Exception $_
		return "Failed: $_"
	}
}
