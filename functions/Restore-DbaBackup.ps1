function Restore-DbaBackup
{
<#
.SYNOPSIS 
Restores a SQL Server Database from a set of backupfile

.DESCRIPTION
Scans a given folder for Full, Differential and Log backups. These are then filtered and restored to a specified SQL Server intance and file location

It can also generate restore scripts, both as part of a restore or as it's only action

.PARAMETER SqlServer
The SQL Server instance. 

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER Path
Path to SQL Server backup file. This can be a full, differential or log backup file.

.PARAMETER RestoreLocation
Path to restore the SQL Server backups to on the target inance
		
.PARAMETER OlaStyle
Switch to indicate the backup files are in a folder structure as created by Ola Hallengreen's maintenance scripts

.PARAMETER FileDirectory
Switch to indicate the backup files just exist in a folder (this is the standard)
	
.PARAMETER FileList
Returns detailed information about the files within the backup

.PARAMETER DatabaseName
Name to restore the database under

.PARAMETER NoRecovery
Indicates if the database should be recovered after last restore. Default is to recover

.PARAMETER ReplaceDatabase
Switch indicated is the restore is allowed to replace an existing database.

.PARAMETER Scripts
Switch to indicate if T-SQL restore scripts should be written out

.PARAMETER ScriptOnly
Switch indicates that ONLY T-SQL scripts should be generated, no restore takes place

.PARAMETER VerifyOnly
Switch indicate that restore should be verified

.NOTES
Original Author: Stuart Moore (@napalmgram), stuart-moore.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE
Restore-DbaBackup -SqlServer server1\instance1 -path \\server2\backups\$ 

Scans all the backup files in \\server2\backups$, filters them and restores the database to server1\instance1

.EXAMPLE
Restore-DbaBackup -SqlServer server1\instance1' -path \\server2\backups\$ -OlaStyle -RestoreLocation c:\restores

Scans all the backup files in \\server2\backups$ stored in an Ola Hallengreen style folder structure,
 filters them and restores the database to the c:\restores folder on server1\instance1 

#>
	[CmdletBinding()]
	param (
        [parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[string]$DatabaseName,
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Path,
        [String]$RestoreLocation,
        [DateTime]$RestoreTime = (Get-Date).addyears(1),  
		[switch]$NoRecovery,
		[switch]$ReplaceDatabase,
		[switch]$Scripts,
        [switch]$ScriptOnly,
		[switch]$VerifyOnly,
        [switch]$OlaStyle,
		[object]$filestructure
		
	)

    if ((Get-Item $path).IsPSContainer -ne $true)
    {
        $files = Get-item $Path
    }elseif ($OlaStyle){
        $files = Get-OlaHRestoreFile -path $Path
    } else {
        $files = Get-DirectoryRestoreFile -path $path
    }
    $FilteredFiles = $files | Get-FilteredRestoreFile -SqlServer $SqlServer
    $FilteredFiles | Restore-DBFromFilteredArray -SqlServer $SqlServer -DBName $databasename -RestoreLocation $RestoreLocation -NoRecovery:$NoRecovery -ReplaceDatabase:$ReplaceDatabase -Scripts:$Scripts -ScriptOnly:$ScriptOnly -VerifyOnly:$VerifyOnly

}


