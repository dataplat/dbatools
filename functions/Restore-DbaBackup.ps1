function Restore-DbaBackup
{
<#
.SYNOPSIS 
Restores a SQL Server Database from a set of backupfiles

.DESCRIPTION
Scans a given folder for Full, Differential and Log backups. 
OR
Takes a set of folder arrays and processes them for Full, Differential and Log backups.

These are then filtered and restored to a specified SQL Server intance and file location

The backup LSN chain and RecoveryForkID will also be checked to ensure the restore is valid

It can also generate restore scripts, both as part of a restore or as it's only action

.PARAMETER SqlServer
The SQL Server instance. 

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER Path
Path to SQL Server backup file. This can be a full, differential or log backup file.

.PARAMETER Files
A Files object(s) containing SQL Server backup files. 

.PARAMETER RestoreLocation
Path to restore the SQL Server backups to on the target inance

.PARAMETER RestoreTime
Specify a DateTime object to which you want the database restored to. Default is to the latest point available 

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

.PARAMETER XpDirTree
Switch that indicated file scanning should be performed by the SQL Server instance using xp_dirtree
You must have sysadmin role membership on the instance for this to work.

.PARAMETER LogicalFileMapping
Accepts a hashtable of mappings to be used to rename Logical Files post restore, of the form:
$mapping = @{'LogicalFile1'='newname1';'LogicalFile2'='othername'}
You don't have to specify all files, and just those mapped will  be renamed
Exclusive with LogicalFilePrefix

.PARAMETER LogicalFilePrefix
Specify a string which will be prefixed to ALL logical files post restore.
Exlusive with LogicalFileMapping
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

.EXAMPLE
Get-ChildItem c:\SQLbackups1\, \\server\sqlbackups2 | Restore-DbaBackup -SqlServer server1\instance1 

Takes the provided files from multiple directories and restores them on  server1\instance1 

.EXAMPLE
$RestoreTime = Get-Date('11:19 23/12/2016')
Restore-DbaBackup -SqlServer server1\instance1' -path \\server2\backups\$ -OlaStyle -RestoreLocation c:\restores -RestoreTime $RestoreTime

Scans all the backup files in \\server2\backups$ stored in an Ola Hallengreen style folder structure,
 filters them and restores the database to the c:\restores folder on server1\instance1 up to 11:19 23/12/2016
#>
	[CmdletBinding()]
	param (
        [parameter(Mandatory = $true, ParameterSetName="Paths")]
        [string[]]$Path,
        [parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName="Files")]
        [object[]]$Files,
        [parameter(Mandatory = $true,ParameterSetName="Paths")]
        [parameter(Mandatory = $true,ParameterSetName="Files")]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[System.Management.Automation.PSCredential]$SqlCredential,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[string]$DatabaseName,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
        [String]$RestoreLocation,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
        [DateTime]$RestoreTime = (Get-Date).addyears(1),
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]  
		[switch]$NoRecovery,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[switch]$ReplaceDatabase,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[switch]$Scripts,
        [Parameter(ParameterSetName="Paths")]
        [Switch]$XpDirTree,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
        [switch]$ScriptOnly,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[switch]$VerifyOnly,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
        [switch]$OlaStyle,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[object]$filestructure,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[string]$LogicalFilePrefix,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[hashtable]$LogicalFileMapping			
	)
    BEGIN
    {
        $FunctionName = "Restore-DbaBackup"
        $BackupFiles = @()
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq "Paths")
        {
            Write-Verbose "$FunctionName : Paths passed in" 
            foreach ($p in $path)
            {  
                if ($XpDirTree)
                {
                    $BackupFiles += Get-XPDirTreeRestoreFile -path $p -SqlServer $SqlServer -SqlCredential $SqlCredential
                }
                elseif ((Get-Item $p).PSIsContainer -ne $true)
                {
                    Write-Verbose "$FunctionName : Single file"
                    $BackupFiles += Get-item $p
                } 
                elseif ($OlaStyle)
                {
                    Write-Verbose "$FunctionName : Ola Style"
                    $BackupFiles += Get-OlaHRestoreFile -path $p
                } 
                else 
                {
                    Write-Verbose "$FunctionName : Standard Directory"
                    $BackupFiles += Get-DirectoryRestoreFile -path $p
                }
            }
        }elseif($PSCmdlet.ParameterSetName -eq "Files")
        {
            Write-Verbose "$FunctionName : Files passed in $($files.count)" 
            Foreach ($file in $files)
            {
                Write-Verbose "$file"
                $BackupFiles += $file
            }
        }
    }
    END
    {
        $FilteredFiles = $BackupFiles | Get-FilteredRestoreFile -SqlServer $SqlServer -RestoreTime $RestoreTime

        if (($FilteredFiles.DatabaseName | Group-Object | Measure-Object).count -gt 1)
        {
            $dbs = ($FilteredFiles | select DatabaseName) -join (',')
            Write-Error "$FunctionName - We can only handle 1 Database at a time - $dbs"
        }
        if(Test-DbaLsnChain -FilteredRestoreFiles $FilteredFiles)
        {
            try{
                $FilteredFiles | Restore-DBFromFilteredArray -SqlServer $SqlServer -DBName $databasename -RestoreTime $RestoreTime -RestoreLocation $RestoreLocation -NoRecovery:$NoRecovery -ReplaceDatabase:$ReplaceDatabase -Scripts:$Scripts -ScriptOnly:$ScriptOnly -VerifyOnly:$VerifyOnly
                if ($LogicalFileMapping.count -ne 0 -or $LogicalFilePrefix -ne '')
                {
                    Rename-LogicalFile -SqlServer $sqlserver -DbName $DatabaseName -Mapping:$LogicalFileMapping -Prefix:$LogicalFilePrefix
                }
            }
            catch{
                Write-Exception $_
				return
            }
        }
    }
}


