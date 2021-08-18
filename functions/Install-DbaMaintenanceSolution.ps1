function Install-DbaMaintenanceSolution {
    <#
    .SYNOPSIS
        Download and Install SQL Server Maintenance Solution created by Ola Hallengren (https://ola.hallengren.com)

    .DESCRIPTION
        This script will download and install the latest version of SQL Server Maintenance Solution created by Ola Hallengren

    .PARAMETER SqlInstance
        The target SQL Server instance onto which the Maintenance Solution will be installed.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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

    .PARAMETER LocalFile
        Specifies the path to a local file to install Ola's solution from. This *should* be the zip file as distributed by the maintainers.
        If this parameter is not specified, the latest version will be downloaded and installed from https://github.com/olahallengren/sql-server-maintenance-solution

    .PARAMETER Force
        If this switch is enabled, the Ola's solution will be downloaded from the internet even if previously cached.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER InstallParallel
        If this switch is enabled, the Queue and QueueDatabase tables are created, for use when  @DatabasesInParallel = 'Y' are set in the jobs.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, OlaHallengren
        Author: Viorel Ciucu, cviorel.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://ola.hallengren.com

    .LINK
         https://dbatools.io/Install-DbaMaintenanceSolution

    .EXAMPLE
        PS C:\> Install-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA -CleanupTime 72

        Installs Ola Hallengren's Solution objects on RES14224 in the DBA database.
        Backups will default to the default Backup Directory.
        If the Maintenance Solution already exists, the script will be halted.

    .EXAMPLE
        PS C:\> Install-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA -BackupLocation "Z:\SQLBackup" -CleanupTime 72

        This will create the Ola Hallengren's Solution objects. Existing objects are not affected in any way.

    .EXAMPLE
        PS C:\> $params = @{
        >> SqlInstance = 'MyServer'
        >> Database = 'maintenance'
        >> ReplaceExisting = $true
        >> InstallJobs = $true
        >> LogToTable = $true
        >> BackupLocation = 'C:\Data\Backup'
        >> CleanupTime = 65
        >> Verbose = $true
        >> }
        >> Install-DbaMaintenanceSolution @params

        Installs Maintenance Solution to myserver in database. Adds Agent Jobs, and if any currently exist, they'll be replaced.

    .EXAMPLE
        PS C:\> Install-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA -BackupLocation "Z:\SQLBackup" -CleanupTime 72 -ReplaceExisting

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

    .EXAMPLE
        PS C:\> Install-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA -InstallParallel

        This will create the Queue and QueueDatabase tables for uses when manually changing jobs to use the @DatabasesInParallel = 'Y' flag

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Internal functions are ignored")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object]$Database = "master",
        [string]$BackupLocation,
        [int]$CleanupTime,
        [string]$OutputFileDirectory,
        [switch]$ReplaceExisting,
        [switch]$LogToTable,
        [ValidateSet('All', 'Backup', 'IntegrityCheck', 'IndexOptimize')]
        [string[]]$Solution = 'All',
        [switch]$InstallJobs,
        [string]$LocalFile,
        [switch]$Force,
        [switch]$InstallParallel,
        [switch]$EnableException

    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        if ($Solution -contains 'All') {
            $Solution = @('All');
        }

        if ($InstallJobs -and $Solution -notcontains 'All') {
            Stop-Function -Message "Jobs can only be created for all solutions. To create SQL Agent jobs you need to use '-Solution All' (or not specify the Solution and let it default to All) and '-InstallJobs'."
            return
        }

        if ((Test-Bound -ParameterName CleanupTime) -and -not $InstallJobs) {
            Stop-Function -Message "CleanupTime is only useful when installing jobs. To install jobs, please use '-InstallJobs' in addition to CleanupTime."
            return
        }

        if ($ReplaceExisting -eq $true) {
            Write-ProgressHelper -ExcludePercent -Message "If Ola Hallengren's scripts are found, we will drop and recreate them"
        }

        # Do we need a new local cached version of the software?
        $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
        $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child 'sql-server-maintenance-solution-master'
        if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
            if ($PSCmdlet.ShouldProcess('MaintenanceSolution', 'Update local cached copy of the software')) {
                try {
                    Save-DbaCommunitySoftware -Software MaintenanceSolution -LocalFile $LocalFile -EnableException
                } catch {
                    Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_
                }
            }
        }

        function Get-DbaOlaWithParameters($listOfFiles) {

            $fileContents = @{ }
            foreach ($file in $listOfFiles) {
                $fileContents[$file] = Get-Content -Path $file -Raw
            }

            foreach ($file in $($fileContents.Keys)) {
                # In which database we install
                if ($Database -ne 'master') {
                    $findDB = 'USE [master]'
                    $replaceDB = 'USE [' + $Database + ']'
                    $fileContents[$file] = $fileContents[$file].Replace($findDB, $replaceDB)
                }

                # Backup location
                if ($BackupLocation) {
                    $findBKP = 'DECLARE @BackupDirectory nvarchar(max)     = NULL'
                    $replaceBKP = 'DECLARE @BackupDirectory nvarchar(max)     = N''' + $BackupLocation + ''''
                    $fileContents[$file] = $fileContents[$file].Replace($findBKP, $replaceBKP)
                }

                # CleanupTime
                if ($CleanupTime -ne 0) {
                    $findCleanupTime = 'DECLARE @CleanupTime int                   = NULL'
                    $replaceCleanupTime = 'DECLARE @CleanupTime int                   = ' + $CleanupTime
                    $fileContents[$file] = $fileContents[$file].Replace($findCleanupTime, $replaceCleanupTime)
                }

                # OutputFileDirectory
                if ($OutputFileDirectory) {
                    $findOutputFileDirectory = 'DECLARE @OutputFileDirectory nvarchar(max) = NULL'
                    $replaceOutputFileDirectory = 'DECLARE @OutputFileDirectory nvarchar(max) = N''' + $OutputFileDirectory + ''''
                    $fileContents[$file] = $fileContents[$file].Replace($findOutputFileDirectory, $replaceOutputFileDirectory)
                }

                # LogToTable
                if (!$LogToTable) {
                    $findLogToTable = "DECLARE @LogToTable nvarchar(max)          = 'Y'"
                    $replaceLogToTable = "DECLARE @LogToTable nvarchar(max)          = 'N'"
                    $fileContents[$file] = $fileContents[$file].Replace($findLogToTable, $replaceLogToTable)
                }

                # Create Jobs
                if (-not $InstallJobs) {
                    $findCreateJobs = "DECLARE @CreateJobs nvarchar(max)          = 'Y'"
                    $replaceCreateJobs = "DECLARE @CreateJobs nvarchar(max)          = 'N'"
                    $fileContents[$file] = $fileContents[$file].Replace($findCreateJobs, $replaceCreateJobs)
                }
            }
            return $fileContents
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -NonPooledConnection
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $db = $server.Databases[$Database]
            if ($null -eq $db) {
                Stop-Function -Message "Database $Database not found on $instance. Skipping." -Target $instance -Continue
            }

            if ((Test-Bound -ParameterName ReplaceExisting -Not)) {
                $procs = Get-DbaModule -SqlInstance $server -Database $Database | Where-Object Name -in 'CommandExecute', 'DatabaseBackup', 'DatabaseIntegrityCheck', 'IndexOptimize'
                $tables = Get-DbaDbTable -SqlInstance $server -Database $Database -Table CommandLog, Queue, QueueDatabase -IncludeSystemDBs | Where-Object Database -eq $Database

                if ($null -ne $procs -or $null -ne $tables) {
                    Stop-Function -Message "The Maintenance Solution already exists in $Database on $instance. Use -ReplaceExisting to automatically drop and recreate."
                    continue
                }
            }

            if ((Test-Bound -ParameterName BackupLocation -Not)) {
                $BackupLocation = (Get-DbaDefaultPath -SqlInstance $server).Backup
            }
            Write-ProgressHelper -ExcludePercent -Message "Ola Hallengren's solution will be installed on database $Database"

            if ($Solution -notcontains 'All') {
                $required = @('CommandExecute.sql')
            }

            if ($LogToTable -and $InstallJobs -eq $false) {
                $required += 'CommandLog.sql'
            }

            if ($Solution -contains 'Backup') {
                $required += 'DatabaseBackup.sql'
            }

            if ($Solution -contains 'IntegrityCheck') {
                $required += 'DatabaseIntegrityCheck.sql'
            }

            if ($Solution -contains 'IndexOptimize') {
                $required += 'IndexOptimize.sql'
            }

            if ($Solution -contains 'All' -and $InstallJobs) {
                $required += 'MaintenanceSolution.sql'
            }

            if ($Solution -contains 'All' -and $InstallJobs -eq $false) {
                $required += 'CommandExecute.sql'
                $required += 'DatabaseBackup.sql'
                $required += 'DatabaseIntegrityCheck.sql'
                $required += 'IndexOptimize.sql'
            }

            if ($InstallParallel) {
                $required += 'Queue.sql'
                $required += 'QueueDatabase.sql'
            }

            $listOfFiles = Get-ChildItem -Filter "*.sql" -Path $localCachedCopy -Recurse | Select-Object -ExpandProperty FullName

            $fileContents = Get-DbaOlaWithParameters -listOfFiles $listOfFiles

            $cleanupQuery = $null
            if ($ReplaceExisting) {
                [string]$cleanupQuery = $("
                            IF OBJECT_ID('[dbo].[CommandLog]', 'U') IS NOT NULL
                                DROP TABLE [dbo].[CommandLog];
                            IF OBJECT_ID('[dbo].[QueueDatabase]', 'U') IS NOT NULL
                                DROP TABLE [dbo].[QueueDatabase];
                            IF OBJECT_ID('[dbo].[Queue]', 'U') IS NOT NULL
                                DROP TABLE [dbo].[Queue];
                            IF OBJECT_ID('[dbo].[CommandExecute]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[CommandExecute];
                            IF OBJECT_ID('[dbo].[DatabaseBackup]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[DatabaseBackup];
                            IF OBJECT_ID('[dbo].[DatabaseIntegrityCheck]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[DatabaseIntegrityCheck];
                            IF OBJECT_ID('[dbo].[IndexOptimize]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[IndexOptimize];
                            ")

                if ($Pscmdlet.ShouldProcess($instance, "Dropping all objects created by Ola's Maintenance Solution")) {
                    Write-ProgressHelper -ExcludePercent -Message "Dropping objects created by Ola's Maintenance Solution"
                    $null = $db.Invoke($cleanupQuery)
                }

                # Remove Ola's Jobs
                if ($InstallJobs -and $ReplaceExisting) {
                    Write-ProgressHelper -ExcludePercent -Message "Removing existing SQL Agent Jobs created by Ola's Maintenance Solution"
                    $jobs = Get-DbaAgentJob -SqlInstance $server | Where-Object Description -match "hallengren"
                    if ($jobs) {
                        $jobs | ForEach-Object {
                            if ($Pscmdlet.ShouldProcess($instance, "Dropping job $_.name")) {
                                $null = Remove-DbaAgentJob -SqlInstance $server -Job $_.name
                            }
                        }
                    }
                }
            }

            Write-ProgressHelper -ExcludePercent -Message "Installing on server $instance, database $Database"

            $result = "Success"
            foreach ($file in $fileContents.Keys | Sort-Object) {
                $shortFileName = Split-Path $file -Leaf
                if ($required.Contains($shortFileName)) {
                    if ($Pscmdlet.ShouldProcess($instance, "Installing $shortFileName")) {
                        Write-ProgressHelper -ExcludePercent -Message "Installing $shortFileName"
                        $sql = $fileContents[$file]
                        try {
                            foreach ($query in ($sql -Split "\nGO\b")) {
                                $null = $db.Invoke($query)
                            }
                        } catch {
                            $result = "Failed"
                            Stop-Function -Message "Could not execute $shortFileName in $Database on $instance" -ErrorRecord $_ -Target $db -Continue
                        }
                    }
                }
            }
            [pscustomobject]@{
                ComputerName = $server.ComputerName
                InstanceName = $server.ServiceName
                SqlInstance  = $instance
                Results      = $result
            }

            # Close non-pooled connection as this is not done automatically. If it is a reused Server SMO, connection will be opened again automatically on next request.
            $server | Disconnect-DbaInstance
        }

        Write-ProgressHelper -ExcludePercent -Message "Installation complete"
    }
}
