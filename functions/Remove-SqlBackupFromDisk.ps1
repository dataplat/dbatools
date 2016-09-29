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

.PARAMETER BackupFileExtenstion
Extension of the backup files you wish to remove (typically bak or log)

.PARAMETER RetentionTime
Time span for file retention. 1w will retain 1 wee's worth of files. 1d will retain 1 day. 1M will retain 1 month.

.PARAMETER Recurse
Find all files below the BackupFolder recursively

.PARAMETER DeleteArchivedFilesOnly
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
Remove-SqlBackupFromDisk -BackupFolder 'C:\MSSQL\Backup\' -FileExtension 'bak' -DeleteOlderThan '1w' -Recurse -DeleteArchivedFilesOnly

For the database RideTheLightning on the server Fade2Black Will perform a DBCC CHECKDB and if there are no errors 
backup the database to the folder C:\MSSQL\Backup\Rationalised - DO NOT DELETE. It will then create an Agent Job to restore the database 
from that backup. It will drop the database, run the agent job to restore it, perform a DBCC ChECK DB and then drop the database.

Any DBCC errors will be written to your documents folder

#>
	[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Default")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[string]$BackupFolder ,

		[parameter(Mandatory = $true)]
		[string]$BackupFileExtenstion ,

		[parameter(Mandatory = $true)]
		[string]$RetentionTime ,

		[parameter(Mandatory = $false)]
		[switch]$Recurse = $false ,

		[parameter(Mandatory = $false)]
		[switch]$DeleteArchivedFilesOnly = $false ,

        [parameter(Mandatory = $false)]
		[switch]$RemoveEmptyBackupFolders = $false 
        		
	)
	
	BEGIN
	{
        # Initialize stuff
        $Start = Get-Date

        $a= '1month'

        [regex]::match($a,”[A-Za-z]”)

        # Convert RetentionTime to an actual DateTime
        switch -Wildcard ($RetentionTime)
        {
            "*h" { Write-Verbose 'Hours'
            }

            "*d" { Write-Verbose 'Days'
            }

            "*w" { Write-Verbose 'Weeks'
            }

            "*m" { Write-Verbose 'Months'
            }

            "*y" { Write-Verbose 'Years'
            }

            default { Write-Verbose 'Default (Hours)'
            }
        }
		
	}
	PROCESS
	{
		# Process stuff
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


$param1 = @{
    	'BackupFolder' = 'c:\temp';
		'BackupFileExtenstion' = 'bak';
        'RetentionTime' = '1Y' ;
        'Recurse' = $false ;
        'DeleteArchivedFilesOnly' = $false ;
        'RemoveEmptyBackupFolders' = $false ;
        'Verbose' = $true
}

Remove-SqlBackupFromDisk @param1
