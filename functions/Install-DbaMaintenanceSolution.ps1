function Install-DbaMaintenanceSolution {
    <#
        .SYNOPSIS
            Download and Install SQL Server Maintenance Solution created by Ola Hallengren (https://ola.hallengren.com)
        .DESCRIPTION
            This script will download and install the latest version of SQL Server Maintenance Solution created by Ola Hallengren

        .PARAMETER SqlInstance
            The target SQL Server instance onto which the Maintenance Solution will be installed.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            The database where Ola Hallengren's solution will be installed. Defaults to master.

        .PARAMETER BackupLocation
            Location of the backup root directory. If this is not supplied, the default backup directory will be used.

        .PARAMETER CleanupTime
            Time in hours, after which backup files are deleted.

        .PARAMETER OutputFileDirectory
            Specify the output file directory where the Maintenance Solution will write to.

        .PARAMETER ReplaceExisting
            If this switch is enabled, objects already present in the target database will be dropped and recreated.

        .PARAMETER LogToTable
            If this switch is enabled, the Maintenance Solution will be configured to log commands to a table.

        .PARAMETER Solution
            Specifies which portion of the Maintenance solution to install. Valid values are All (full solution), Backup, IntegrityCheck and IndexOptimize.

        .PARAMETER InstallJobs
            If this switch is enabled, the corresponding SQL Agent Jobs will be created.

       .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Viorel Ciucu, viorel.ciucu@gmail.com, cviorel.com

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            http://dbatools.io/Install-DbaMaintenanceSolution

        .EXAMPLE
            Install-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA -CleanupTime 72

            Installs Ola Hallengren's Solution objects on RES14224 in the DBA database.
            Backups will default to the default Backup Directory.
            If the Maintenance Solution already exists, the script will be halted.

        .EXAMPLE
            Install-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA -ReplaceExisting -CleanupTime 72 -LogToTable -Solution "Backup" -BackupLocation "Z:\SQLBackup" -InstallJobs

        .EXAMPLE
            Install-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA -BackupLocation "Z:\SQLBackup" -CleanupTime 72

            This will create the Ola Hallengren's Solution objects. Existing objects are not affected in any way.

        .EXAMPLE
            Install-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA -BackupLocation "Z:\SQLBackup" -CleanupTime 72 -ReplaceExisting

            This will drop and then recreate the Ola Hallengren's Solution objects
            The cleanup script will drop and recreate:
                - TABLE [dbo].[CommandLog]
                - STORED PROCEDURE [dbo].[CommandExecute]
                - STORED PROCEDURE [dbo].[DatabaseBackup]
                - STORED PROCEDURE [dbo].[DatabaseIntegrityCheck]
                - STORED PROCEDURE [dbo].[IndexOptimize]

            The following SQL Agent jobs will be deleted:
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
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias('ServerInstance', 'SqlServer')]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object]$Database = "master",
        [string]$BackupLocation,
        [int]$CleanupTime,
        [string]$OutputFileDirectory,
        [switch]$ReplaceExisting,
        [switch]$LogToTable,
        [ValidateSet('All', 'Backup', 'IntegrityCheck', 'IndexOptimize')]
        [string]$Solution = 'All',
        [switch]$InstallJobs,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -NonPooled
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ((Test-Bound -Parameter ReplaceExisting -Not)) {
                $procs = Get-DbaSqlModule -SqlInstance $server -Database $Database | Where-Object Name -in 'CommandExecute', 'DatabaseBackup', 'DatabaseIntegrityCheck', 'IndexOptimize'
                $table = Get-DbaTable -SqlInstance $server -Database $Database -Table CommandLog -IncludeSystemDBs  | Where-Object Database -eq $Database

                if ($null -ne $procs -or $null -ne $table) {
                    Stop-Function -Message "The Maintenance Solution already exists in $Database on $instance. Use -ReplaceExisting to automatically drop and recreate."
                    return
                }
            }

            if ((Test-Bound -Parameter BackupLocation -Not)) {
                $BackupLocation = (Get-DbaDefaultPath -SqlInstance $server).Backup
            }

            Write-Message -Level Output -Message "Ola Hallengren's solution will be installed on database $Database."

            $db = $server.Databases[$Database]

            if ($InstallJobs -and $Solution -ne 'All') {
                Stop-Function -Message "To create SQL Agent jobs you need to use '-Solution All' and '-InstallJobs Create'."
                return
            }

            if ($ReplaceExisting -eq $true) {
                Write-Message -Level Verbose -Message "If Ola Hallengren's scripts are found, we will drop and recreate them!"
            }

            if ($CleanupTime -ne 0 -and $InstallJobs -eq $false) {
                Write-Message -Level Output -Message "CleanupTime $CleanupTime value will be ignored because you chose not to create SQL Agent Jobs."
            }

            # Required
            $required = @('CommandExecute.sql')

            if ($LogToTable) {
                $required += 'CommandLog.sql'
            }

            if ($Solution -match 'Backup') {
                $required += 'DatabaseBackup.sql'
            }

            if ($Solution -match 'IntegrityCheck') {
                $required += 'DatabaseIntegrityCheck.sql'
            }

            if ($Solution -match 'IndexOptimize') {
                $required += 'IndexOptimize.sql'
            }

            if ($Solution -match 'All') {
                $required += 'MaintenanceSolution.sql'
            }

            $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
            $zipfile = "$temp\ola.zip"

            # Start the download
            $url = "https://github.com/olahallengren/sql-server-maintenance-solution/archive/master.zip"
            try {
                Start-BitsTransfer -Source $url -DisplayName 'Downloading SQL Server Maintenance Solution - https://ola.hallengren.com' -Destination $zipfile -ErrorAction Stop
            }
            catch {
                Stop-Function -Message "You need to re-run the script, there is a problem with the proxy or the download link has changed." -ErrorRecord $_
            }

            # Unblock if there's a block
            Unblock-File $zipfile -ErrorAction SilentlyContinue

            $path = "$temp\sql-server-maintenance-solution-master"

            # We don't like default parameters messed with so we start clean
            if ((Test-Path $path)) {
                Remove-Item -Path $temp\sql-server-maintenance-solution-master -Recurse -Force -ErrorAction SilentlyContinue
            }

            # internal if it doesn't exist
            Expand-Archive -Path $zipfile -DestinationPath $temp -Force
            Remove-Item -Path $zipfile

            $listOfFiles = Get-ChildItem -Filter "*.sql" -Path $path | Select-Object -ExpandProperty FullName

            # In which database we install
            if ($Database -ne 'master') {
                $findDB = 'USE [master]'
                $replaceDB = 'USE [' + $Database + ']'
                foreach ($file in $listOfFiles) {
                    (Get-Content -Path $file -Raw).Replace($findDB, $replaceDB) | Set-Content -Path $file
                }
            }

            # Backup location
            if ($BackupLocation) {
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
            if ($OutputFileDirectory.Length -gt 0) {
                $findOutputFileDirectory = 'SET @OutputFileDirectory = NULL'
                $replaceOutputFileDirectory = 'SET @OutputFileDirectory = N''' + $OutputFileDirectory + ''''
                foreach ($file in $listOfFiles) {
                    (Get-Content -Path $file -Raw).Replace($findOutputFileDirectory, $replaceOutputFileDirectory) | Set-Content -Path $file
                }

            }

            # LogToTable
            if (!$LogToTable) {
                $findLogToTable = "SET @LogToTable          = 'Y'"
                $replaceLogToTable = "SET @LogToTable          = 'N'"
                foreach ($file in $listOfFiles) {
                    (Get-Content -Path $file -Raw).Replace($findLogToTable, $replaceLogToTable) | Set-Content -Path $file
                }
            }

            # Create Jobs
            if ($InstallJobs -eq $false) {
                $findCreateJobs = "SET @CreateJobs          = 'Y'"
                $replaceCreateJobs = "SET @CreateJobs          = 'N'"
                foreach ($file in $listOfFiles) {
                    (Get-Content -Path $file -Raw).Replace($findCreateJobs, $replaceCreateJobs) | Set-Content -Path $file
                }
            }

            $CleanupQuery = $null
            if ($ReplaceExisting) {
                [string]$CleanupQuery = $("
                            IF OBJECT_ID('[dbo].[CommandLog]', 'U') IS NOT NULL
                                DROP TABLE [dbo].[CommandLog];
                            IF OBJECT_ID('[dbo].[CommandExecute]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[CommandExecute];
                            IF OBJECT_ID('[dbo].[DatabaseBackup]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[DatabaseBackup];
                            IF OBJECT_ID('[dbo].[DatabaseIntegrityCheck]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[DatabaseIntegrityCheck];
                            IF OBJECT_ID('[dbo].[IndexOptimize]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[IndexOptimize];
                            ")

                Write-Message -Level Output -Message "Dropping objects created by Ola's Maintenance Solution"
                $null = $db.Query($CleanupQuery)

                # Remove Ola's Jobs
                if ($InstallJobs -and $ReplaceExisting) {
                    Write-Message -Level Output -Message "Removing existing SQL Agent Jobs created by Ola's Maintenance Solution."
                    $jobs = Get-DbaAgentJob -SqlInstance $server | Where-Object Description -match "hallengren"
                    if ($jobs) {
                        $jobs | ForEach-Object { Remove-DbaAgentJob -SqlInstance $instance -Job $_.name }
                    }
                }
            }

            try {
                Write-Message -Level Output -Message "Installing on server $SqlInstance, database $Database."

                foreach ($file in $listOfFiles) {
                    $shortFileName = Split-Path $file -Leaf
                    if ($required.Contains($shortFileName)) {
                        Write-Message -Level Output -Message "Installing $file."
                        $sql = [IO.File]::ReadAllText($file)
                        try {
                            foreach ($query in ($sql -Split "\nGO\b")) {
                                $null = $db.Query($query)
                            }
                        }
                        catch {
                            Stop-Function -Message "Could not execute $file in $Database on $instance." -ErrorRecord $_ -Target $db -Continue
                        }
                    }
                }
            }
            catch {
                Stop-Function -Message "Could not execute $file in $Database on $instance." -ErrorRecord $_ -Target $db -Continue
            }
        }

        if ((Test-Path $path)) {
            Remove-Item -Path $temp\sql-server-maintenance-solution-master -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Only here due to need for non-pooled connection in this command
        try {
            $server.ConnectionContext.Disconnect()
        }
        catch {
        }

        Write-Message -Level Output -Message "Installation complete."
    }
}
