function Install-SQLMaintenanceSolution_v2 {
    <#
    .SYNOPSIS
        Download and Install SQL Server Maintenance Solution created by Ola Hallengren (https://ola.hallengren.com)
    .DESCRIPTION
        This script will download and install the latest version of SQL Server Maintenance Solution created by Ola Hallengren
    .PARAMETER SqlInstance
        The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or higher.
    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
        $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 
        To connect as a different Windows user, run PowerShell as that user.        
    .PARAMETER Database
        The database where Ola Hallengren's solution will be installed. Defaults to master
    .PARAMETER BackupLocation
        Location of the backup root directory
    .PARAMETER CleanupTime
        Time in hours, after which backup files are deleted
    .PARAMETER OutputFileDirectory
        Specify the output file directory
    .PARAMETER ReplaceExisting
        If the objects are already present in the chosen database, we drop and recreate them
    .EXAMPLE
        This will create the Ola Hallengren's Solution objects. Existing objects are not affected in any way.
        Install-SQLMaintenanceSolution_v2 -SqlInstance RES14224 -Database DBA -BackupLocation "Z:\SQLBackup" -CleanupTime 72
    .EXAMPLE
        This will drop and then recreate the Ola Hallengren's Solution objects
        Install-SQLMaintenanceSolution_v2 -SqlInstance RES14224 -Database DBA -BackupLocation "Z:\SQLBackup" -CleanupTime 72 -ReplaceExisting 1
        The cleanup script will drop and recreate:
            - TABLE [dbo].[CommandLog]
            - STORED PROCEDURE [dbo].[CommandExecute]
            - STORED PROCEDURE [dbo].[DatabaseBackup]
            - STORED PROCEDURE [dbo].[DatabaseIntegrityCheck]
            - STORED PROCEDURE [dbo].[IndexOptimize]

        The follwing SQL Agent jobs will be deleted:
            - 'Output File Cleanup'
            - 'IndexOptimize - USER_DATABASES'
            - 'sp_delete_backuphistory'
            - 'DatabaseBackup - USER_DATABASES - LOG'
            - 'DatabaseBackup - SYSTEM_DATABASES - FULL'
            - 'DatabaseBackup - USER_DATABASES - FULL'
            - 'sp_purge_jobhistory'
            - 'DatabaseIntegrityCheck - SYSTEM_DATABASES'
            - 'CommandLog Cleanup'
            - 'DatabaseIntegrityCheck - USER_DATABASES'
            - 'DatabaseBackup - USER_DATABASES - DIFF'
    .NOTES
        Author: Viorel Ciucu, viorel.ciucu@gmail.com 
        Date: July, 2017
    .LINK
        http://www.cviorel.com/
    #>


        [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact="High")]
        param (
            [parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [Alias('ServerInstance', 'SqlServer')]
            [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
            [PSCredential]
            $SqlCredential,
            [object]$Database = "master",
            [switch]$Silent,
            [string]$BackupLocation,
            [int]$CleanupTime,
            [string]$OutputFileDirectory,
            [int]$ReplaceExisting = 0
        )

    begin {
        $passedparams = $psboundparameters.Keys | Where-Object { 'Silent', 'SqlServer', 'SqlCredential', 'OutputAs', 'ServerInstance', 'SqlInstance', 'Database' -notcontains $_ }
        $localparams = $psboundparameters
    }

    process {
            
                foreach ($instance in $SqlInstance) {
                    try {
                        Write-Message -Level Verbose -Message "Connecting to $instance"
                        $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
                    }
                    catch {
                        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                    }
                     
                        Write-Message -Level Verbose -Message "Working on server: $instance"

                        if ($Database.Length -eq 0) {
                            Write-Message -Level Warning -Message "Ola Hallengren's solution will be installed on master database."
                        } else {
                            Write-Message -Level Warning -Message "Ola Hallengren's solution will be installed on $Database database."
                        }

                        if ($ReplaceExisting -eq 1) {
                            Write-Message -Level Warning -Message "If Ola Hallengren's scripts are found, we will drop and recreate them!"
                        }

                        $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
                        $shell = New-Object -COM Shell.Application
                        $zipfile = "$temp\ola.zip"

                        # Start the download
                        $url = "https://github.com/olahallengren/sql-server-maintenance-solution/archive/master.zip"
                        $job = Start-BitsTransfer -Source $url -DisplayName Ola -Destination $zipfile -Asynchronous

                        while (($Job.JobState -eq "Transferring") -or ($Job.JobState -eq "Connecting")) { 
                            Start-Sleep 5;
                        } # Poll for status, sleep for 5 seconds, or perform an action.

                        Switch($Job.JobState) {
                            "Transferred" { Complete-BitsTransfer -BitsJob $Job; Write-Output "Download completed!" }
                            "Error" { $Job | Format-List } # List the errors.
                            default { Write-Output "You need to re-run the script, there is a problem with the proxy or the download link has changed!"; Exit } # Perform corrective action.
                        }

                        # Unblock if there's a block
                        Unblock-File $zipfile -ErrorAction SilentlyContinue

                        $shell = New-Object -COM Shell.Application
                        $zipPackage = $shell.NameSpace($zipfile)
                        $destinationFolder = $shell.NameSpace($temp)
                        $destinationFolder.CopyHere($zipPackage.Items())

                        Remove-Item -Path $zipfile

                        $path = "$temp\sql-server-maintenance-solution-master"

                        $listOfFiles = Get-ChildItem -Filter "*.sql" -Path $path | Select -Expand FullName

                        # In which database we install
                        if ($Database -ne 'master') {
                            $findDB = 'USE [master]'
                            $replaceDB = 'USE [' + $Database + ']'
                            foreach ($file in $listOfFiles) { 
                                (Get-Content -Path $file -Raw).Replace($findDB, $replaceDB) | Set-Content -Path $file
                            }
                        }

                        # Backup location
                        if ($BackupLocation.Length -ne 0) {
                            $findBKP = 'C:\Backup'
                            $replaceBKP = $BackupLocation
                            foreach ($file in $listOfFiles) { 
                                (Get-Content -Path $file -Raw).Replace($findBKP, $replaceBKP) | Set-Content -Path $file
                            }
                        }

                        # CleanupTime
                        if ($CleanupTime -ne 0) {
                            $findCleanupTime = 'SET @CleanupTime         = NULL'
                            $replaceCleanupTime = 'SET @CleanupTime         = ' + $CleanupTime
                            foreach ($file in $listOfFiles) { 
                                (Get-Content -Path $file -Raw).Replace($findCleanupTime, $replaceCleanupTime) | Set-Content -Path $file
                            }
                        }

                        # OutputFileDirectory
                        if ($OutputFileDirectory.Length -gt 0 ) {
                            $findOutputFileDirectory = 'SET @OutputFileDirectory = NULL'
                            $replaceOutputFileDirectory = 'SET @OutputFileDirectory = N''' + $OutputFileDirectory + ''''
                            foreach ($file in $listOfFiles) { 
                                (Get-Content -Path $file -Raw).Replace($findOutputFileDirectory, $replaceOutputFileDirectory) | Set-Content -Path $file
                            }

                        }

                        $CleanupQuery = ""
                        if ($ReplaceExisting -eq 1) {
                            [string] $CleanupQuery = $("
                            USE [$Database]
                            GO
                            DROP TABLE [dbo].[CommandLog]
                            DROP PROCEDURE [dbo].[CommandExecute]
                            DROP PROCEDURE [dbo].[DatabaseBackup]
                            DROP PROCEDURE [dbo].[DatabaseIntegrityCheck]
                            DROP PROCEDURE [dbo].[IndexOptimize]
                            ")
                            Write-Message -Level Warning -Message "Dropping objects created by Ola's Maintenance Solution"
                            $null = $server.databases[$Database].ExecuteNonQuery($CleanupQuery)
                            
                            # Remove Ola's Jobs                     
                            Write-Message -Level Warning -Message "Removing existing SQL Agent Jobs created by Ola's Maintenance Solution"
                            $jobs = (Get-SqlAgent -ServerInstance $instance | Get-SqlAgentJob) | Where {$_.Description -Match "hallengren" } | select Name
                            $jobs | % { Remove-DbaAgentJob -SqlInstance $instance -Job $_.Name }
                        }

                        try {
                            Write-Output "Installing on server $SqlInstance, database $Database"
                            foreach ($file in $listOfFiles) {
                                $sql = [IO.File]::ReadAllText($file)
                                try {
                                    $null = $server.databases[$Database].ExecuteNonQuery($sql)
                                }
                                catch {
                                    Write-Message -Level Warning -Message "Could not execute $file"
                                }
                            }
                                                    
                            
                        }
                        catch {
                            Write-Message -Level Warning -Message "Could not execute $file in $Database on $instance" -ErrorRecord $_
                        }   
                }
    }
    
    end {
        $server.ConnectionContext.Disconnect()
        # Do the housekeeping
        Remove-Item -Path $temp\sql-server-maintenance-solution-master -Recurse -Force
    }
}