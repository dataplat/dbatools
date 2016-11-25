Function Restore-Database
{
<# 
	.SYNOPSIS
	Internal function. Restores .bak file to SQL database. Creates db if it doesn't exist. $filestructure is
	a custom object that contains logical and physical file locations.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$dbname,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$backupfile,
		[string]$filetype = "Database",
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$filestructure,
		[switch]$norecovery = $true,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	$servername = $server.name
	$server.ConnectionContext.StatementTimeout = 0
	$restore = New-Object "Microsoft.SqlServer.Management.Smo.Restore"
	$restore.ReplaceDatabase = $true
	
	foreach ($file in $filestructure.values)
	{
		$movefile = New-Object "Microsoft.SqlServer.Management.Smo.RelocateFile"
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
		$restore.ReplaceDatabase = $true
		$restore.Database = $dbname
		$restore.Action = $filetype
		$restore.NoRecovery = $norecovery
		$device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
		$device.name = $backupfile
		$device.devicetype = "File"
		$restore.Devices.Add($device)
		
		Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
		$restore.sqlrestore($server)
		Write-Progress -id 1 -activity "Restoring $dbname to $servername" -status "Complete" -Completed
		
		return $true
	}
	catch
	{
		Write-Error "Restore failed: $($_.Exception)"
		return $false
	}
}
