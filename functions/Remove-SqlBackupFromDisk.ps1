Function Remove-SqlBackupFromDisk
{
<#
.SYNOPSIS
Remove SQL Server backups from disk

.DESCRIPTION
Provides all of the same functionality for removing SQL backups from disk as a standard maintenance plan would.

The only addition is the ability to check the Archive bit on files before deletion. This will allow you to ensure
backups have been archived to your archive location before removal.

.PARAMETER BackupFolder
Name of the base level folder to search for backup files. 
Deletion of backup files will be recursive from this location.

.PARAMETER BackupFileExtenstion
Extension of the backup files you wish to remove (typically bak or log)

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
Check the archive bit on files before deletion

.PARAMETER RemoveEmptyBackupFolders
Remove any empty folders after the cleanup process is complete.

.NOTES
Original Author: Chris Sommer @cjsommer, www.cjsommer.com

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
https://dbatools.io/Remove-SqlBackupFromDisk

.EXAMPLE
Remove-SqlBackupFromDisk -BackupFolder 'C:\MSSQL\Backup\' -BackupFileExtenstion 'trn' -RetentionPeriod '48h'

The cmdlet will remove '*.trn' files from 'C:\MSSQL\Backup\' and all subdirectories that are more than 48 hours. 

.EXAMPLE
Remove-SqlBackupFromDisk -BackupFolder 'C:\MSSQL\Backup\' -BackupFileExtenstion 'bak' -RetentionPeriod '7d' -CheckArchiveBit

The cmdlet will remove '*.bak' files from 'C:\MSSQL\Backup\' and all subdirectories that are more than 7 days old. 
It will also ensure that the bak files have been archived using the archive bit before removing them.

.EXAMPLE
Remove-SqlBackupFromDisk -BackupFolder 'C:\MSSQL\Backup\' -BackupFileExtenstion 'bak' -RetentionPeriod '1w' -RemoveEmptyBackupFolders

The cmdlet will remove '*.bak' files from 'C:\MSSQL\Backup\' and all subdirectories that are more than 1 week old. 
It will also remove any backup folders that no longer contain backup files.

.EXAMPLE
Remove-SqlBackupFromDisk -BackupFolder 'C:\MSSQL\Backup\' -BackupFileExtenstion 'bak' -RetentionPeriod '1m' CheckArchiveBit -RemoveEmptyBackupFolders

The cmdlet will remove '*.bak' files from 'C:\MSSQL\Backup\' and all subdirectories that are more than 1 month old. It will also ensure that the bak files
have been archived using the archive bit before removing them. It will also remove any backup folders that no longer contain backup files.

#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType 'Container'})]
		[string]$BackupFolder ,

		[parameter(Mandatory = $true)]
		[string]$BackupFileExtenstion ,

		[parameter(Mandatory = $false)]
		[string]$RetentionPeriod = '48h' ,

		[parameter(Mandatory = $false)]
		[switch]$CheckArchiveBit = $false ,

        [parameter(Mandatory = $false)]
		[switch]$RemoveEmptyBackupFolders = $false
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
            if ( $Units -notin @('h','d','w','m') ){
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
            Write-Verbose "Retention set to '$Value' $UnitString. Retention date/time '$ReturnDatetime'"
            $ReturnDatetime
        }

        # Initialize stuff
        $Start = Get-Date
	}
	PROCESS
	{
		# Process stuff
        Write-Output ("Started at $Start")
        Write-Output ("Removing backups from '$BackupFolder'")

        # Convert Retention Value to an actual DateTime
        try {
            $RetentionDate = Convert-UserFriendlyRetentionToDatetime -UserFriendlyRetention $RetentionPeriod
            Write-Output "Backup Retention Date set to '$RetentionDate'"
        } catch {
            throw $_
        }

        # Remove the files that are older than RetentionDate
        $FilesToDelete = Get-ChildItem "$DatabaseFolderName" -Filter "*.$BackupFileExtenstion" -Recurse | `
            Where-Object {$_.LastWriteTime -lt $RetentionDate}
            
        # Filter out unarchived files if -CheckArchiveBit parameter is used
        if ($CheckArchiveBit.IsPresent) {
            Write-Output 'Removing only archived file'
            $FilesToDelete = $FilesToDelete | Where-Object {$_.attributes -notmatch "Archive"} 
        }
        
        If ($Pscmdlet.ShouldProcess($env:computername, "Removing backup files from '$BackupFolder'")) {
            try {
                $FilesToDelete | Remove-Item -Force 
            } catch {
                throw $_
            }
        }

        # Remove empty backup folders if RemoveEmptyBackupFolders is passed in
        if ($RemoveEmptyBackupFolders.IsPresent) {
            If ($Pscmdlet.ShouldProcess($env:computername, "Removing empty folders under '$BackupFolder'")) {
                try {
                    Get-ChildItem -Path $BackupFolder -Recurse | Where-Object {$_.PSIsContainer -eq $true `
                        -and (Get-ChildItem -Path $_.FullName) -eq $null} | Remove-Item -Force
                } catch {
                    throw $_
                }
            }           
        }
	}

	END
	{
        # End cleanup
		if ($Pscmdlet.ShouldProcess("console", "Showing final message"))
		{
			$End = Get-Date
			Write-Output "Finished at $End"
			$Duration = $End - $start
			Write-Output "Script Duration: $Duration"
		}
	}
}
