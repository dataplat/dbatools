function Copy-DbaBackupDevice {
	<#
		.SYNOPSIS
			Copies backup devices one by one. Copies both SQL code and the backup file itself.

		.DESCRIPTION
			Backups are migrated using Admin shares.  If destination directory does not exist, SQL Server's default backup directory will be used.

			If backup device with same name exists on destination, it will not be dropped and recreated unless -Force is used.

		.PARAMETER Source
			Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Force
			Drops and recreates the backup device if it exists

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, DisasterRecovery, Backup
			Original Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaBackupDevice

		.EXAMPLE
			Copy-DbaBackupDevice -Source sqlserver2014a -Destination sqlcluster

			Copies all server backup devices from sqlserver2014a to sqlcluster, using Windows credentials. If backup devices with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE
			Copy-DbaBackupDevice -Source sqlserver2014a -Destination sqlcluster -BackupDevice backup01 -SourceSqlCredential $cred -Force

			Copies a single backup device, backup01, from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a
			and Windows credentials for sqlcluster. If a backup device with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

		.EXAMPLE
			Copy-DbaBackupDevice -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

			Shows what would happen if the command were executed using force.
	#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SourceSqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationSqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[switch]$Force,
		[switch]$Silent
	)

	begin {

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName

		$serverBackupDevices = $sourceServer.BackupDevices
		$destBackupDevices = $destServer.BackupDevices

		Write-Output "Resolving NetBios name"
		$sourceNetBios = Resolve-NetBiosName $sourceServer
		$destNetBios = Resolve-NetBiosName $destServer
	}
	process	{
		foreach ($backupDevice in $serverBackupDevices) {
			$deviceName = $backupDevice.Name

			$copyBackupDeviceStatus = [pscustomobject]@{
				SourceServer = $sourceServer.Name
				DestinationServer = $destServer.Name
				Name = $deviceName
				Type = "BackupDevice"
				Status = $null
				DateTime = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
			}

			if ($backupDevices.Length -gt 0 -and $backupDevices -notcontains $deviceName) {
				continue
			}

			if ($destBackupDevices.Name -contains $deviceName) {
				if ($force -eq $false) {
					$copyBackupDeviceStatus.Status = "Skipped"
					$copyBackupDeviceStatus

					Write-Message -Level Warning -Message "backup device $deviceName exists at destination. Use -Force to drop and migrate."
					continue
				}
				else {
					if ($Pscmdlet.ShouldProcess($destination, "Dropping backup device $deviceName")) {
						try {
							Write-Message -Level Verbose -Message "Dropping backup device $deviceName"
							$destServer.BackupDevices[$deviceName].Drop()
						}
						catch {
							$copyBackupDeviceStatus.Status = "Failed"
							$copyBackupDeviceStatus

							Stop-Function -Message "Issue dropping backup device" -Target $deviceName -InnerErrorRecord $_ -Continue
						}
					}
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Generating SQL code for $deviceName")) {
				Write-Message -Level Verbose -Message "Scripting out SQL for $deviceName"
				try {
					$sql = $backupDevice.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
				}
				catch {
					$copyBackupDeviceStatus.Status = "Failed"
					$copyBackupDeviceStatus

					Stop-Function -Message "Issue scripting out backup device" -Target $deviceName -InnerErrorRecord $_ -Continue
				}
			}

			if ($Pscmdlet.ShouldProcess("console", "Stating that the actual file copy is about to occur")) {
				Write-Message -Level Verbose -Message "Preparing to copy actual backup file"
			}

			$path = Split-Path $sourceServer.BackupDevices[$deviceName].PhysicalLocation
			$destPath = Join-AdminUnc $destNetBios $path
			$sourcepath = Join-AdminUnc $sourceNetBios $sourceServer.BackupDevices[$deviceName].PhysicalLocation

			Write-Message -Level Verbose -Message "Checking if directory $destPath exists"

			if ($(Test-DbaSqlPath -SqlInstance $Destination -Path $path) -eq $false) {
				$backupDirectory = $destServer.BackupDirectory
				$destPath = Join-AdminUnc $destNetBios $backupDirectory

				if ($Pscmdlet.ShouldProcess($destination, "Updating create code to use new path")) {
					Write-Message -Level Warning -Message "$path doesn't exist on $destination"
					Write-Message -Level Warning -Message "Using default backup directory $backupDirectory"

					try {
						Write-Message -Level Verbose -Message "Updating $deviceName to use $backupDirectory"
						$sql = $sql -replace $path, $backupDirectory
					}
					catch {
						$copyBackupDeviceStatus.Status = "Failed"
						$copyBackupDeviceStatus

						Stop-Function -Message "Issue updating script of backup device with new path" -Target $deviceName -InnerErrorRecord $_ -Continue
					}
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Copying $sourcepath to $destPath using BITSTransfer")) {
				try {
					Start-BitsTransfer -Source $sourcepath -Destination $destPath -ErrorAction Stop
					Write-Message -Level Verbose -Message "Backup device $deviceName successfully copied"
				}
				catch {
					$copyBackupDeviceStatus.Status = "Failed"
					$copyBackupDeviceStatus

					Stop-Function -Message "Issue copying backup device to destination" -Target $deviceName -InnerErrorRecord $_
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Adding backup device $deviceName")) {
				Write-Message -Level Verbose -Message "Adding backup device $deviceName on $destination"
				try {
					$destServer.Query($sql)
					$destServer.BackupDevices.Refresh()

					$copyBackupDeviceStatus.Status = "Successful"
					$copyBackupDeviceStatus
				}
				catch {
					$copyBackupDeviceStatus.Status = "Failed"
					$copyBackupDeviceStatus

					Stop-Function -Message "Issue adding backup device" -Target $deviceName -InnerErrorRecord $_ -Continue
				}
			}
		} #end foreach backupDevice
	}
	end	{
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlBackupDevice
	}
}
