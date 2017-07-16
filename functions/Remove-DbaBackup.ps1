Function Remove-DbaBackup
{
<#
.SYNOPSIS
Remove SQL Server backups from disk

.DESCRIPTION
Provides all of the same functionality for removing SQL backups from disk as a standard maintenance plan would.

As an addition you have the ability to check the Archive bit on files before deletion. This will allow you to ensure
backups have been archived to your archive location before removal.

Also included is the ability to remove empty folders as part of this cleanup activity.

.PARAMETER Path
Name of the base level folder to search for backup files.
Deletion of backup files will be recursive from this location.

.PARAMETER BackupFileExtension
Extension of the backup files you wish to remove (typically bak, trn or log)

.PARAMETER RetentionPeriod
Retention period for backup files. Correct format is ##U.

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
Checks the archive bit before deletion. If the file is "ready for archiving" (which translates to "it has not been backed up yet") it won't be removed

.PARAMETER RemoveEmptyBackupFolder
Remove any empty folders after the cleanup process is complete.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.NOTES
Tags: Storage, DisasterRecovery, Backup
Original Author: Chris Sommer, @cjsommer, www.cjsommer.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Remove-DbaBackup

.EXAMPLE
Remove-DbaBackup -Path 'C:\MSSQL\SQL Backup\' -BackupFileExtension trn -RetentionPeriod 48h

The cmdlet will remove '*.trn' files from 'C:\MSSQL\SQL Backup\' and all subdirectories that are more than 48 hours. 

.EXAMPLE
Remove-DbaBackup -Path 'C:\MSSQL\SQL Backup\' -BackupFileExtension trn -RetentionPeriod 48h -WhatIf

Same as example #1, but using the WhatIf parameter. The WhatIf parameter will allow the cmdlet show you what it will do, without actually doing it.
In this case, no trn files will be deleted. Instead, the cmdlet will output what it will do when it runs. This is a good preventatitive measure
especially when you are first configuring the cmdlet calls.

.EXAMPLE
Remove-DbaBackup -Path 'C:\MSSQL\Backup\' -BackupFileExtension bak -RetentionPeriod 7d -CheckArchiveBit

The cmdlet will remove '*.bak' files from 'C:\MSSQL\Backup\' and all subdirectories that are more than 7 days old. 
It will also ensure that the bak files have been archived using the archive bit before removing them.

.EXAMPLE
Remove-DbaBackup -Path 'C:\MSSQL\Backup\' -BackupFileExtension bak -RetentionPeriod 1w -RemoveEmptyBackupFolder

The cmdlet will remove '*.bak' files from 'C:\MSSQL\Backup\' and all subdirectories that are more than 1 week old. 
It will also remove any backup folders that no longer contain backup files.


#>
	[CmdletBinding(SupportsShouldProcess=$true)]
	Param (
		[parameter(Mandatory = $true,HelpMessage="Full path to the root level backup folder (ex. 'C:\SQL\Backups'")]
		[Alias("BackupFolder")]
		[ValidateScript({Test-Path $_ -PathType 'Container'})]
		[string]$Path,

		[parameter(Mandatory = $true,HelpMessage="Backup File extension to remove (ex. bak, trn, dif)")]
		[string]$BackupFileExtension ,

		[parameter(Mandatory = $true,HelpMessage="Backup retention period. (ex. 24h, 7d, 4w, 6m)")]
		[string]$RetentionPeriod ,

		[parameter(Mandatory = $false)]
		[switch]$CheckArchiveBit = $false ,

		[parameter(Mandatory = $false)]
		[switch]$RemoveEmptyBackupFolder = $false,

		[switch]$Silent
	)

	BEGIN
	{
		### Local Functions
		function Convert-UserFriendlyRetentionToDatetime
		{
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
			$Value = ($UserFriendlyRetention).Substring(0,$Length-1)
			$Units = ($UserFriendlyRetention).Substring($Length-1,1)

			# Validate that $Units is an accepted unit of measure
			if ( $Units -notin @('h','d','w','m') ) {
				throw "RetentionPeriod '$UserFriendlyRetention' units invalid! See Get-Help for correct formatting and examples."
			}

			# Validate that $Value is an INT
			if ( ![int]::TryParse($Value,[ref]"") ) {
				throw "RetentionPeriod '$UserFriendlyRetention' format invalid! See Get-Help for correct formatting and examples."
			}

			switch ($Units)
			{
				'h' { $UnitString = 'Hours'; [datetime]$ReturnDatetime = (Get-Date).AddHours(-$Value)  }
				'd' { $UnitString = 'Days';  [datetime]$ReturnDatetime = (Get-Date).AddDays(-$Value)   }
				'w' { $UnitString = 'Weeks'; [datetime]$ReturnDatetime = (Get-Date).AddDays(-$Value*7) }
				'm' { $UnitString = 'Months';[datetime]$ReturnDatetime = (Get-Date).AddMonths(-$Value) }
			}
			$ReturnDatetime
		}

		# Validations
		# Ensure BackupFileExtension does not begin with a .
		if ($BackupFileExtension -match "^[.]") {
			Write-Message -Level Warning -Message "Parameter -BackupFileExtension begins with a period '$BackupFileExtension'. A period is automatically prepended to -BackupFileExtension and need not be passed in."
		}

	}
	PROCESS
	{
		# Process stuff
		Write-Message -Message "Started" -Level 3 -Silent $Silent
		Write-Message -Message "Removing backups from $Path" -Level 3 -Silent $Silent
		# Convert Retention Value to an actual DateTime
		try {
			$RetentionDate = Convert-UserFriendlyRetentionToDatetime -UserFriendlyRetention $RetentionPeriod
			Write-Message -Message "Backup Retention Date set to $RetentionDate" -Level 5 -Silent $Silent
		} catch {
			Stop-Function -Message "Failed to interpret retention time!" -ErrorRecord $_
		}

		# Filter out unarchived files if -CheckArchiveBit parameter is used
		if ($CheckArchiveBit) {
			Write-Message -Message "Removing only archived files" -Level 5 -Silent $Silent
			Filter DbaArchiveBitFilter {
				If ($_.Attributes -notmatch "Archive") {
					$_
				}
			}
		} else {
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
					} catch {
						Write-Message -Message "Failed to remove $file" -Level Warning -ErrorRecord $_
					}
				}
			}
		if ($EnumErrors) {
			Write-Message "Errors encountered enumerating files" -Level Warning -ErrorRecord $EnumErrors
		}
		Write-Message -Message "File Cleaning ended" -Level 3 -Silent $Silent
		# Cleanup empty backup folders.
		if ($RemoveEmptyBackupFolder) {
			Write-Message -Message "Removing empty folders" -Level 3 -Silent $Silent
			(Get-ChildItem -Directory -Path $Path -Recurse -ErrorAction SilentlyContinue -ErrorVariable EnumErrors).FullName |
				Sort-Object -Descending |
					Foreach-Object {
						$OrigPath = $_
						try {
							$Contents = @(Get-ChildItem -Force $OrigPath -ErrorAction Stop)
						} catch {
							Write-Message -Message "Can't enumerate $OrigPath" -Level Warning -ErrorRecord $_
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
								} catch {
									Write-Message -Message "Failed to remove $FolderPath" -Level Warning -ErrorRecord $_
								}
							}
						}
			if ($EnumErrors) {
				Write-Message "Errors encountered enumerating folders" -Level Warning -ErrorRecord $EnumErrors
			}
			Write-Message -Message "Removed empty folders" -Level 3 -Silent $Silent
		}
	}
}
