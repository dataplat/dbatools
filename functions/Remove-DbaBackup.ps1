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

.PARAMETER RemoveEmptyBackupFolder
Remove any empty folders after the cleanup process is complete.

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
		[switch]$RemoveEmptyBackupFolder = $false
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

        function Get-EmptyBackupFolder 
        {
            [cmdletbinding()]
            param (
                [string]$BaseLocation
            )
            Get-ChildItem -Path $BaseLocation -Recurse | Where-Object {$_.PSIsContainer -eq $true -and (Get-ChildItem -Path $_.FullName) -eq $null}
        }


        # Validations
        # Ensure BackupFileExtension does not begin with a .
        if ($BackupFileExtension -match "^[.]") {
            Write-Warning "Parameter -BackupFileExtension begins with a period '$BackupFileExtension'. A period is automatically prepended to -BackupFileExtension and need not be passed in."
        } 

        # Initialize stuff
        $Start = Get-Date
	}
	PROCESS
	{
		# Process stuff
        Write-Output ("Started at $Start")
        Write-Output ("Removing backups from $Path")

        # Convert Retention Value to an actual DateTime
        try {
            $RetentionDate = Convert-UserFriendlyRetentionToDatetime -UserFriendlyRetention $RetentionPeriod
            Write-Output "Backup Retention Date set to $RetentionDate"
        } catch {
            throw $_
        }

        # Generate list of files that are to be removed
        $FilesToDelete = Get-ChildItem "$Path" -Filter "*.$BackupFileExtension" -Recurse | `
            Where-Object {$_.LastWriteTime -lt $RetentionDate}
            
        # Filter out unarchived files if -CheckArchiveBit parameter is used
        if ($CheckArchiveBit.IsPresent) {
            Write-Output 'Removing only archived files'
            $FilesToDelete = $FilesToDelete | Where-Object {$_.attributes -notmatch "Archive"} 
        }
        
        # Perform the deletion or show which file will be deleted if WhatIf is used
        foreach ($file in $filestodelete) { 
            If ($Pscmdlet.ShouldProcess( $(($file.FullName).Replace($file.Name, '')), "Removing backup file '$($file.name)'")) {
                try {
                    Write-Output "Removing backup file '$($file.FullName)'"
                    $file.FullName | Remove-Item -Force
                } catch {
                    throw $_
                }
            }
        }
 
        # Cleanup empty backup folders. Using a DO/WHILE loop to force it to go through the logic at least once so we can display WhatIf if we need to
        do {
            if ($RemoveEmptyBackupFolder.IsPresent) {
                # Get the empty backup folders
                $EmptyBackupFolder = Get-EmptyBackupFolder -BaseLocation $Path

                foreach ($folder in $EmptyBackupFolder) {
                    if ($Pscmdlet.ShouldProcess($Path, "Removing empty folder '.$(($folder.FullName).Replace($Path,''))")) {
                        try {
                            Write-Output "Removing empty folder '$($folder.FullName)'"
                            $folder.FullName | Remove-Item -Force
                        } catch {
                            throw $_
                        }
                    }
                }
            }
            # Refresh the empty folders. This will allow us to recursively clean them up
            $EmptyBackupFolder = Get-EmptyBackupFolder -BaseLocation $Path
          
        } while ($RemoveEmptyBackupFolder.IsPresent -and !$WhatIfPreference -and $EmptyBackupFolder)
	}

	END
	{
        # End cleanup
		if ($Pscmdlet.ShouldProcess($env:computername, "Showing final message"))
		{
			$End = Get-Date
			Write-Output "Finished at $End"
			$Duration = $End - $start
			Write-Output "Script Duration: $Duration"
		} 
	}
}
