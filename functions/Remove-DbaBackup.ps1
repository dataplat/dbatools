function Remove-DbaBackup {
	<#
		.SYNOPSIS
			Removes SQL Server backups from disk.

		.DESCRIPTION
			Provides all of the same functionality for removing SQL backups from disk as a standard maintenance plan would.

			As an addition you have the ability to check the Archive bit on files before deletion. This will allow you to ensure backups have been archived to your archive location before removal.

			Also included is the ability to remove empty folders as part of this cleanup activity.

		.PARAMETER Path
			Specifies the name of the base level folder to search for backup files. Deletion of backup files will be recursive from this location.

		.PARAMETER BackupFileExtension
			Specifies the filename extension of the backup files you wish to remove (typically 'bak', 'trn' or 'log'). Do not include the period.

		.PARAMETER RetentionPeriod
			Specifies the retention period for backup files. Correct format is ##U.

			## is the retention value and must be an integer value
			U signifies the units where the valid units are:
			h = hours
			d = days
			w = weeks
			m = months

			Formatting Examples:
			'48h' = 48 hours
			'7d' = 7 days
			'4w' = 4 weeks
			'1m' = 1 month

		.PARAMETER CheckArchiveBit
			If this switch is enabled, the filesystem Archive bit is checked before deletion. If this bit is set (which translates to "it has not been backed up to another location yet", the file won't be deleted.

		.PARAMETER RemoveEmptyBackupFolder
			If this switch is enabled, empty folders will be removed after the cleanup process is complete.
			
		.PARAMETER EnableException
			By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
			This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
			Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
				
       .PARAMETER WhatIf
			If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

		.PARAMETER Confirm
			If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.i

		.NOTES
			Tags: Storage, DisasterRecovery, Backup
			Author: Chris Sommer, @cjsommer, www.cjsommer.com

			dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
			Copyright (C) 2016 Chrissy LeMaire
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Remove-DbaBackup

		.EXAMPLE
			Remove-DbaBackup -Path 'C:\MSSQL\SQL Backup\' -BackupFileExtension trn -RetentionPeriod 48h

			'*.trn' files in 'C:\MSSQL\SQL Backup\' and all subdirectories that are more than 48 hours old will be removed. 

		.EXAMPLE
			Remove-DbaBackup -Path 'C:\MSSQL\SQL Backup\' -BackupFileExtension trn -RetentionPeriod 48h -WhatIf

			Same as example #1, but doesn't actually remove any files. The function will instead show you what would be done. This is useful when first experimenting with using the function.

		.EXAMPLE
			Remove-DbaBackup -Path 'C:\MSSQL\Backup\' -BackupFileExtension bak -RetentionPeriod 7d -CheckArchiveBit

			'*.bak' files in 'C:\MSSQL\Backup\' and all subdirectories that are more than 7 days old will be removed, but only if the files have been backed up to another location as verified by checking the Archive bit. 

		.EXAMPLE
			Remove-DbaBackup -Path 'C:\MSSQL\Backup\' -BackupFileExtension bak -RetentionPeriod 1w -RemoveEmptyBackupFolder

			'*.bak' files in 'C:\MSSQL\Backup\' and all subdirectories that are more than 1 week old will be removed. Any folders left empty will be removed as well. 
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, HelpMessage = "Full path to the root level backup folder (ex. 'C:\SQL\Backups'")]
		[Alias("BackupFolder")]
		[ValidateScript( {Test-Path $_ -PathType 'Container'})]
		[string]$Path,
		[parameter(Mandatory = $true, HelpMessage = "Backup File extension to remove (ex. bak, trn, dif)")]
		[string]$BackupFileExtension ,
		[parameter(Mandatory = $true, HelpMessage = "Backup retention period. (ex. 24h, 7d, 4w, 6m)")]
		[string]$RetentionPeriod ,
		[parameter(Mandatory = $false)]
		[switch]$CheckArchiveBit = $false ,
		[parameter(Mandatory = $false)]
		[switch]$RemoveEmptyBackupFolder = $false,
		[switch][Alias('Silent')]$EnableException
	)

	begin {
		### Local Functions
		function Convert-UserFriendlyRetentionToDatetime {
			[cmdletbinding()]
			param (
				[string]$UserFriendlyRetention
			)

			<#
			Convert a user friendly retention value into a datetime.
			The last character of the string will indicate units (validated)
			Valid units are: (h = hours, d = days, w = weeks, m = months)

			The preceeding characters are the value and must be an integer (validated)

			Examples:
				'48h' = 48 hours
				'7d' = 7 days
				'4w' = 4 weeks
				'1m' = 1 month
			#>

			[int]$Length = ($UserFriendlyRetention).Length
			$Value = ($UserFriendlyRetention).Substring(0, $Length - 1)
			$Units = ($UserFriendlyRetention).Substring($Length - 1, 1)

			# Validate that $Units is an accepted unit of measure
			if ( $Units -notin @('h', 'd', 'w', 'm') ) {
				throw "RetentionPeriod '$UserFriendlyRetention' units invalid! See Get-Help for correct formatting and examples."
			}

			# Validate that $Value is an INT
			if ( ![int]::TryParse($Value, [ref]"") ) {
				throw "RetentionPeriod '$UserFriendlyRetention' format invalid! See Get-Help for correct formatting and examples."
			}

			switch ($Units) {
				'h' { $UnitString = 'Hours'; [datetime]$ReturnDatetime = (Get-Date).AddHours(-$Value)  }
				'd' { $UnitString = 'Days'; [datetime]$ReturnDatetime = (Get-Date).AddDays(-$Value)   }
				'w' { $UnitString = 'Weeks'; [datetime]$ReturnDatetime = (Get-Date).AddDays(-$Value * 7) }
				'm' { $UnitString = 'Months'; [datetime]$ReturnDatetime = (Get-Date).AddMonths(-$Value) }
			}
			$ReturnDatetime
		}

		# Validations
		# Ensure BackupFileExtension does not begin with a .
		if ($BackupFileExtension -match "^[.]") {
			Write-Message -Level Warning -Message "Parameter -BackupFileExtension begins with a period '$BackupFileExtension'. A period is automatically prepended to -BackupFileExtension and need not be passed in."
		}

	}
	process {
		# Process stuff
		Write-Message -Message "Started" -Level Significant -EnableException $EnableException
		Write-Message -Message "Removing backups from $Path" -Level Significant -EnableException $EnableException
		# Convert Retention Value to an actual DateTime
		try {
			$RetentionDate = Convert-UserFriendlyRetentionToDatetime -UserFriendlyRetention $RetentionPeriod
			Write-Message -Message "Backup Retention Date set to $RetentionDate" -Level Verbose -EnableException $EnableException
		}
		catch {
			Stop-Function -Message "Failed to interpret retention time!" -ErrorRecord $_
		}

		# Filter out unarchived files if -CheckArchiveBit parameter is used
		if ($CheckArchiveBit) {
			Write-Message -Message "Removing only archived files." -Level Verbose -EnableException $EnableException
			Filter DbaArchiveBitFilter {
				If ($_.Attributes -notmatch "Archive") {
					$_
				}
			}
		}
		else {
			Filter DbaArchiveBitFilter {
				$_
			}
		}
		# Enumeration may take a while. Without resorting to "esoteric" file listing facilities
		# and given we need to fetch at least the LastWriteTime, let's just use "streaming" processing
		# here to avoid issues like described in #970
		Get-ChildItem $Path -Filter "*.$BackupFileExtension" -File -Recurse -ErrorAction SilentlyContinue -ErrorVariable EnumErrors |
			Where-Object LastWriteTime -lt $RetentionDate | DbaArchiveBitFilter |
			Foreach-Object {
			$file = $_
			if ($PSCmdlet.ShouldProcess($file.Directory.FullName, "Removing backup file $($file.Name)")) {
				try {
					$file
					$file | Remove-Item -Force -EA Stop
				}
				catch {
					Write-Message -Message "Failed to remove $file." -Level Warning -ErrorRecord $_
				}
			}
		}
		if ($EnumErrors) {
			Write-Message "Errors encountered enumerating files." -Level Warning -ErrorRecord $EnumErrors
		}
		Write-Message -Message "File Cleaning ended." -Level Significant -EnableException $EnableException
		# Cleanup empty backup folders.
		if ($RemoveEmptyBackupFolder) {
			Write-Message -Message "Removing empty folders." -Level Significant -EnableException $EnableException
			(Get-ChildItem -Directory -Path $Path -Recurse -ErrorAction SilentlyContinue -ErrorVariable EnumErrors).FullName |
				Sort-Object -Descending |
				Foreach-Object {
				$OrigPath = $_
				try {
					$Contents = @(Get-ChildItem -Force $OrigPath -ErrorAction Stop)
				}
				catch {
					Write-Message -Message "Can't enumerate $OrigPath." -Level Warning -ErrorRecord $_
				}
				if ($Contents.Count -eq 0) {
					return $_
				}
			} |
				Foreach-Object {
				$FolderPath = $_
				if ($PSCmdlet.ShouldProcess($Path, "Removing empty folder .$($FolderPath.Replace($Path, ''))")) {
					try {
						$FolderPath
						$FolderPath | Remove-Item -ErrorAction Stop
					}
					catch {
						Write-Message -Message "Failed to remove $FolderPath." -Level Warning -ErrorRecord $_
					}
				}
			}
			if ($EnumErrors) {
				Write-Message "Errors encountered enumerating folders." -Level Warning -ErrorRecord $EnumErrors
			}
			Write-Message -Message "Removed empty folders." -Level Significant -EnableException $EnableException
		}
	}
}
