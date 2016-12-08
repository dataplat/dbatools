function Restore-DBASQLBackup
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

.PARAMETER dbname
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
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

.EXAMPLE
Restore-SQLBackup -SQLServer 'server1\instance1' -path \\server2\backups\$ 

Scans all the backup files in \\server2\backups$, filters them and restores the database to server1\instance1

.EXAMPLE
Restore-SQLBackup -SQLServer 'server1\instance1' -path \\server2\backups\$ -OlaStyle -RestoreLocation c:\restores

Scans all the backup files in \\server2\backups$ stored in an Ola Hallengreen style folder structure,
 filters them and restores the database to the c:\restores folder on server1\instance1 

#>
	[CmdletBinding()]
	param (
        [parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[string]$DbName,
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
		[object]$filestructure,
		[System.Management.Automation.PSCredential]$SqlCredential
	)

    if ($OlaStyle){
        $files = Get-OlaHRestoreFile -path $Path
    } else {
        $files = Get-DirectoryRestoreFile -path $path
    }
    $FilteredFiles = $files | Get-FilteredRestoreFile -sqlserver $sqlserver
    $FilteredFiles | Restore-DBFromFilteredArray -SQLServer $sqlserver -DBName $dbname -RestoreLocation $RestoreLocation -NoRecovery:$NoRecovery -ReplaceDatabase:$ReplaceDatabase -Scripts:$Scripts -ScriptOnly:$ScriptOnly -VerifyOnly:$VerifyOnly

}


