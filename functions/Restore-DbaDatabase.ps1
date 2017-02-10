function Restore-DbaDatabase
{
<#
.SYNOPSIS 
Restores a SQL Server Database from a set of backupfiles

.DESCRIPTION
Upon bein passed a list of potential backups files this command will scan the files, select those that contain SQL Server
backup sets. It will then filter those files down to a set that can perform the requested restore, checking that we have a 
full restore chain to the point in time requested by the caller.

Various means can be used to pass in a list of files to be considered. The default is to non recursively scan the folder
passed in. 

.PARAMETER SqlServer
The SQL Server instance. 

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER Path
Path to SQL Server backup files. These files will be scanned using the desired method, default is a non recursive folder scan
Accepts multiple paths seperated by ','

.PARAMETER FileList
A Files object(s) containing SQL Server backup files. Each file passed in will be parsed.

.PARAMETER DestinationDataDirectory
Path to restore the SQL Server backups to on the target instance.
If only this parameter is specified, then all database files (data and log) will be restored to this location

.PARAMETER DestinationLogDirectory
Path to restore the database log files to.
This parameter can only be specified alongside DestinationDataDirectory.

.PARAMETER UseDestinationDefaultDirectories
Switch that tells the restore to use the default Data and Log locations on the target server

.PARAMETER RestoreTime
Specify a DateTime object to which you want the database restored to. Default is to the latest point available 

.PARAMETER MaintenanceSolutionBackup
Switch to indicate the backup files are in a folder structure as created by Ola Hallengreen's maintenance scripts.
This swith enables a faster check for suitable backups. Other options require all files to be read first to ensure
we have an anchoring full backup. Because we can rely on specific locations for backups performed with OlaHallengren's 
backup solution, we can rely on file locations.

.PARAMETER DatabaseName
Name to restore the database under

.PARAMETER NoRecovery
Indicates if the database should be recovered after last restore. Default is to recover

.PARAMETER WithReplace
Switch indicated is the restore is allowed to replace an existing database.

.PARAMETER OutputScript
Switch to indicate if T-SQL restore scripts should be written out

.PARAMETER OutputScriptOnly
Switch indicates that ONLY T-SQL scripts should be generated, no restore takes place

.PARAMETER VerifyOnly
Switch indicate that restore should be verified

.PARAMETER XpDirTree
Switch that indicated file scanning should be performed by the SQL Server instance using xp_dirtree
This will scan recursively from the passed in path
You must have sysadmin role membership on the instance for this to work.

.PARAMETER FileMapping
A hashtable that can be used to move specific files to a location.
$FileMapping = @{'DataFile1'='c:\restoredfiles\Datafile1.mdf';'DataFile3'='d:\DataFile3.mdf'}
And files not specified in the mapping will be restore to their original location
This Parameter is exclusive with DestinationDataDirectory

.PARAMETER IgnoreLogBackup
This switch tells the function to ignore transaction log backups. The process will restore to the latest full or differential backup point only

.NOTES
Original Author: Stuart Moore (@napalmgram), stuart-moore.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE
Restore-DbaDatabase -SqlServer server1\instance1 -path \\server2\backups 

Scans all the backup files in \\server2\backups, filters them and restores the database to server1\instance1

.EXAMPLE
Restore-DbaDatabase -SqlServer server1\instance1 -path \\server2\backups -MaintenanceSolutionBackup -DestinationDataDirectory c:\restores

Scans all the backup files in \\server2\backups$ stored in an Ola Hallengren style folder structure,
 filters them and restores the database to the c:\restores folder on server1\instance1 

.EXAMPLE
Get-ChildItem c:\SQLbackups1\, \\server\sqlbackups2 | Restore-DbaDatabase -SqlServer server1\instance1 

Takes the provided files from multiple directories and restores them on  server1\instance1 

.EXAMPLE
$RestoreTime = Get-Date('11:19 23/12/2016')
Restore-DbaDatabase -SqlServer server1\instance1 -path \\server2\backups -MaintenanceSolutionBackup -DestinationDataDirectory c:\restores -RestoreTime $RestoreTime

Scans all the backup files in \\server2\backups stored in an Ola Hallengren style folder structure,
 filters them and restores the database to the c:\restores folder on server1\instance1 up to 11:19 23/12/2016

.EXAMPLE
Restore-DbaDatabase -SqlServer server1\instance1 -path \\server2\backups -DestinationDataDirectory c:\restores -OutputScriptOnly | Out-File -Filepath c:\scripts\restore.sql

Scans all the backup files in \\server2\backups stored in an Ola Hallengren style folder structure,
 filters them and generate the T-SQL Scripts to restore the database to the latest point in time, 
 and then stores the output in a file for later retrieval

.EXAMPLE
Restore-DbaDatabase -SqlServer server1\instance1 -path c:\backups -DestinationDataDirectory c:\DataFiles -DestinationLogDirectory c:\LogFile

Scans all the files in c:\backups and then restores them onto the SQL Server Instance server1\instance1, placing data files
c:\DataFiles and all the log files into c:\LogFiles
 

#>
	[CmdletBinding()]
	param (
        [parameter(Mandatory = $true, ParameterSetName="Paths")]
        [string[]]$Path,
        [parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName="Files")]
        [object[]]$FileList,
        [parameter(Mandatory = $true,ParameterSetName="Paths")]
        [parameter(Mandatory = $true,ParameterSetName="Files")]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[System.Management.Automation.PSCredential]$SqlCredential,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[string]$DatabaseName,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
        [String]$DestinationDataDirectory,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
        [String]$DestinationLogDirectory,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
        [DateTime]$RestoreTime = (Get-Date).addyears(1),
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]  
		[switch]$NoRecovery,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[switch]$WithReplace,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[switch]$OutputScript,
        [Parameter(ParameterSetName="Paths")]
        [Switch]$XpDirTree,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
        [switch]$OutputScriptOnly,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[switch]$VerifyOnly,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
        [switch]$MaintenanceSolutionBackup ,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[hashtable]$FileMapping,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
		[switch]$IgnoreLogBackup,
        [Parameter(ParameterSetName="Paths")][Parameter(ParameterSetName="Files")]
        [switch]$UseDestinationDefaultDirectories					
	)
    BEGIN
    {
        $FunctionName = "Restore-DbaDatabase"
        $BackupFiles = @()
        
        if ($DestinationLogDirectory -ne '' -and $UseDestinationDefaultDirectories)
        {
            Write-Warning  "$FunctionName - DestinationLogDirectory and UseDestinationDefaultDirectories are mutually exclusive" -WarningAction Stop  
        }
        if ($DestinationLogDirectory -ne '' -and $DestinationDataDirectory -eq '')
        {
            Write-Warning  "$FunctionName - DestinationLogDirectory can only be specified with DestinationDataDirectory" -WarningAction Stop
        }
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
                elseif ($MaintenanceSolutionBackup )
                {
                    Write-Verbose "$FunctionName : Ola Style Folder"
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
            Write-Verbose "$FunctionName : Files passed in $($FileList.count)" 
            Foreach ($File in $FileList)
            {
                $BackupFiles += $File
            }
        }
    }
    END
    {
        $AllFilteredFiles = $BackupFiles | Get-FilteredRestoreFile -SqlServer:$SqlServer -RestoreTime:$RestoreTime -SqlCredential:$SqlCredential -IgnoreLogBackup:$IgnoreLogBackup
        Write-Verbose "$FunctionName - $($AllFilteredFiles.count) dbs to restore"
        
        ForEach ($FilteredFileSet in $AllFilteredFiles)
      
        {
            $FilteredFiles = $FilteredFileSet.values
           
            Write-Verbose "$FunctionName - Starting FileSet"
            if (($FilteredFiles.DatabaseName | Group-Object | Measure-Object).count -gt 1)
            {
                $dbs = ($FilteredFiles | Select DatabaseName) -join (',')
                Write-Warning "$FunctionName - We can only handle 1 Database at a time - $dbs" -WarningAction Stop
            }

            IF($DatabaseName -eq '')
            {
                $DatabaseName = ($FilteredFiles | Select DatabaseName -unique).DatabaseName
                Write-Verbose "$FunctionName - Dbname set from backup = $DatabaseName"
            }

            if((Test-DbaLsnChain -FilteredRestoreFiles $FilteredFiles) -and (Test-DbaRestoreVersion -FilteredRestoreFiles $FilteredFiles -SqlServer $SqlServer -SqlCredential $SqlCredential))
            {
                try{
                    $FilteredFiles | Restore-DBFromFilteredArray -SqlServer $SqlServer -DBName $databasename -SqlCredential $SqlCredential -RestoreTime $RestoreTime -DestinationDataDirectory $DestinationDataDirectory -DestinationLogDirectory $DestinationLogDirectory -NoRecovery:$NoRecovery -Replace:$WithReplace -Scripts:$OutputScript -ScriptOnly:$OutputScriptOnly -FileStructure:$FileMapping -VerifyOnly:$VerifyOnly
                    $Completed='successfully'
                }
                catch{
                    Write-Exception $_
                    $Completed='unsuccessfully'
                    return
                }
                Finally
                {
                    Write-Verbose "Database $databasename restored $Completes"
                }
            }
            $DatabaseName = ''
        }
    }
}


