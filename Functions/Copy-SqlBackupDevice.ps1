Function Copy-SqlBackupDevice {
 <#
            .SYNOPSIS
             Copies backup devices one by one. Copies both SQL code and the backup file itself. Backups are migrating using Admin shares.
			 
			 If destination directory does not exist, the default backup directory will be used.
			 
			 If backup device with same name exists on destination, it will not be dropped and recreated unless -force is used.
			
        #>
		[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess = $true)] 
        param(
			[parameter(Mandatory = $true)]
			[object]$Source,
			[parameter(Mandatory = $true)]
			[object]$Destination,
			[System.Management.Automation.PSCredential]$SourceSqlCredential,
			[System.Management.Automation.PSCredential]$DestinationSqlCredential,
			[switch]$force
		)
DynamicParam  { if ($source) { return (Get-ParamSqlBackupDevices -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
PROCESS {
	$backupdevices = $psboundparameters.BackupDevices
	
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential

	$source = $sourceserver.name
	$destination = $destserver.name	
	
	if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
	if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }
	
	$serverbackupdevices = $sourceserver.BackupDevices
	$destbackupdevices = $destserver.BackupDevices
	
	Write-Output "Resolving NetBios name"
	$destnetbios = Get-NetBiosName $destserver
	$sourcenetbios = Get-NetBiosName $sourceserver
		
	foreach ($backupdevice in $serverbackupdevices) {
		$devicename = $backupdevice.name
		
		if ($BackupDevices.length -gt 0 -and $BackupDevices -notcontains $devicename) { continue }
		
		if ($destbackupdevices.name -contains $devicename) {
			if ($force -eq $false) {
				Write-Warning "backup device $devicename exists at destination. Use -Force to drop and migrate."
				continue
			} else {
				If ($Pscmdlet.ShouldProcess($destination,"Dropping backup device $devicename")) {
					try {
						Write-Output "Dropping backup device $devicename"
						$destserver.BackupDevices[$devicename].Drop()
					} catch { Write-Exception $_ ; continue }
				}
			}
		}
			
		If ($Pscmdlet.ShouldProcess($destination,"Generating SQL code for $devicename")) {
			Write-Output "Scripting out SQL for $devicename"
			try {
				$sql = $backupdevice.Script()
			} catch { Write-Exception $_ ; continue }
		}

		If ($Pscmdlet.ShouldProcess("console","Stating that the actual file copy is about to occur")) {
			Write-Output "Preparing to copy actual backup file"
		}
		
		$path = Split-Path $sourceserver.BackupDevices[$devicename].PhysicalLocation
		$filename = Split-Path -Leaf $sourceserver.BackupDevices[$devicename].PhysicalLocation
		
		$destpath = Join-AdminUnc $destnetbios $path
		$sourcepath = Join-AdminUnc $sourcenetbios $sourceserver.BackupDevices[$devicename].PhysicalLocation

		Write-Output "Checking if directory $destpath exists"
		
		if ($(Test-Path $destpath) -eq $false) {
			$backupdirectory = $destserver.BackupDirectory
			$destpath = Join-AdminUnc $destnetbios $backupdirectory
			
			# if ($force -eq $false) { Write-Warning "Destination directory does not exist. Use -Force to use the default backup directory at $backupdirectory "; continue }
			If ($Pscmdlet.ShouldProcess($destination,"Updating create code to use new path")) {
				Write-Warning "$path doesn't exist on $destination"
				Write-Warning "Using default backup directory $backupdirectory"

				try {
					Write-Output "Updating $devicename to use $backupdirectory"
					$sql = $sql.Replace($path,$backupdirectory)
				} catch { Write-Exception $_ ; continue }
			}
		}
		
		If ($Pscmdlet.ShouldProcess($destination,"Adding backup device $devicename")) {
			Write-Output "Adding backup device $devicename on $destination"
			try {
				$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
				$destserver.BackupDevices.Refresh()
			} catch { Write-Exception $_ ; continue }
		}
		
		If ($Pscmdlet.ShouldProcess($destination,"Copying $sourcepath to $destpath using BITSTransfer")) {
			try { 
				Start-BitsTransfer -Source $sourcepath -Destination $destpath
				Write-Output "Backup device $devicename successfully copied"
			} catch { Write-Exception $_ }
		}
	}
}

END {
	$sourceserver.ConnectionContext.Disconnect()
	$destserver.ConnectionContext.Disconnect()
	If ($Pscmdlet.ShouldProcess("console","Showing finished message")) { Write-Output "backup device migration finished" }
}
}