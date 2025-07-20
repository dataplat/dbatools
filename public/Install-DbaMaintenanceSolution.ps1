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

        Note - The tables for `LogToTable` and `InstallParallel` will only be dropped if those options are also specified.

    .PARAMETER LogToTable
        If this switch is enabled, the Maintenance Solution will be configured to log commands to a table.

    .PARAMETER Solution
        Specifies which portion of the Maintenance solution to install. Valid values are All (full solution), Backup, IntegrityCheck and IndexOptimize.

    .PARAMETER InstallJobs
        If this switch is enabled, the corresponding SQL Agent Jobs will be created.

    .PARAMETER AutoScheduleJobs
        Scheduled jobs during an optimal time. When AutoScheduleJobs is used, this time will be used as the start time for the jobs unless a schedule already
        exists in the same time slot. If so, then it will add an hour until it finds an open time slot. Defaults to 1:15 AM.

        WeeklyFull will create weekly full, daily differential and 15 minute log backups of _user_ databases.

        _System_ databases will always be backed up daily.

        Differentials will be skipped when NoDiff or DailyFull is specified.

        To perform log backups each hour instead of every 15 minutes, specify HourlyLog in the values.

        Recommendations can be found on Ola's site: https://ola.hallengren.com/frequently-asked-questions.html

    .PARAMETER StartTime
        When AutoScheduleJobs is used, this time will be used as the start time for the jobs unless a schedule already
        exists in the same time slot. If so, then it will add an hour until it finds an open time slot. Defaults to 1:15 AM.

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
        PS C:\> Install-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA -InstallJobs -CleanupTime 72

        Installs Ola Hallengren's Solution objects on RES14224 in the DBA database.
        Backups will default to the default Backup Directory.
        If the Maintenance Solution already exists, the script will be halted.

    .EXAMPLE
        PS C:\> Install-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA -InstallJobs -BackupLocation "Z:\SQLBackup" -CleanupTime 72

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

        Since the `LogToTable` switch is enabled, the CommandLog table will be dropped and recreated also.

        If the tables relating to `InstallParallel` are present, they will not be dropped.

    .EXAMPLE
        PS C:\> $params = @{
        >> SqlInstance = 'RES14224'
        >> Database = 'DBA'
        >> InstallJobs = $true
        >> BackupLocation = 'Z:\SQLBackup'
        >> CleanupTime = 72
        >> ReplaceExisting = $true
        >> }
        PS C:\> Install-DbaMaintenanceSolution @params

        This will drop and then recreate the Ola Hallengren's Solution objects
        The cleanup script will drop and recreate:
        - STORED PROCEDURE [dbo].[CommandExecute]
        - STORED PROCEDURE [dbo].[DatabaseBackup]
        - STORED PROCEDURE [dbo].[DatabaseIntegrityCheck]
        - STORED PROCEDURE [dbo].[IndexOptimize]

        The tables will not be dropped as the `LogToTable` and `InstallParallel` switches are not enabled.
        - [dbo].[CommandLog]
        - [dbo].[Queue]
        - [dbo].[QueueDatabase]

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

    .EXAMPLE
        PS C:\> $params = @{
        >> SqlInstance = "localhost"
        >> InstallJobs = $true
        >> CleanupTime = 720
        >> AutoSchedule = "WeeklyFull"
        >> }
        >> Install-DbaMaintenanceSolution @params

        This will create the Ola Hallengren's Solution objects and the SQL Agent Jobs.

        WeeklyFull will create weekly full, daily differential and 15 minute log backups of _user_ databases.

        _System_ databases will be backed up daily.

        Databases will be backed up to the default location for the instance, and backups will be deleted after 720 hours (30 days).

        See https://github.com/dataplat/dbatools/pull/8911 for details on job schedules.

    .EXAMPLE
        PS C:\> $params = @{
        >> SqlInstance = "localhost"
        >> InstallJobs = $true
        >> CleanupTime = 720
        >> AutoScheduleJobs = "DailyFull", "HourlyLog"
        >> BackupLocation = "\\sql\backups"
        >> StartTime = "231500"
        >> }

        PS C:\> Install-DbaMaintenanceSolution @params

        This will create the Ola Hallengren's Solution objects and the SQL Agent Jobs.

        The jobs will be scheduled to run daily full user backups at 11:15pm, no differential backups will be created and hourly log backups will be made.
        System databases will be backed up at 1:15 am, two hours after the user databases.

        Databases will be backed up to a fileshare, and the backups will be deleted after 720 hours (30 days).

        See https://blog.netnerds.net/2023/05/install-dbamaintenancesolution-now-supports-auto-scheduling/ for more information.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Internal functions are ignored")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database = "master",
        [string]$BackupLocation,
        [int]$CleanupTime,
        [string]$OutputFileDirectory,
        [switch]$ReplaceExisting,
        [switch]$LogToTable,
        [ValidateSet('All', 'Backup', 'IntegrityCheck', 'IndexOptimize')]
        [string[]]$Solution = 'All',
        [switch]$InstallJobs,
        [ValidateSet('WeeklyFull', 'DailyFull', 'NoDiff', 'FifteenMinuteLog', 'HourlyLog')]
        [string[]]$AutoScheduleJobs,
        [string]$StartTime = "011500",
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


        # does this machine have internet access to download the files if required?
        if (-not $isLinux -and -not $isMacOs) {
            if ((Get-Command -Name Get-NetConnectionProfile -ErrorAction SilentlyContinue)) {
                $script:internet = (Get-NetConnectionProfile -ErrorAction SilentlyContinue).IPv4Connectivity -contains "Internet"
            } else {
                try {
                    $network = [Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}")
                    $script:internet = ([Activator]::CreateInstance($network)).GetNetworkConnections() | ForEach-Object { $_.GetNetwork().GetConnectivity() } | Where-Object { ($_ -band 64) -eq 64 }
                } catch {
                    # probably a container with internet
                    $script:internet = $true
                }
            }

            if (-not $internet) {
                Write-Message -Level Verbose -Message "No internet connection found, using included copy of Maintenance Solution."
                $localCachedCopy = [System.IO.Path]::Combine($script:PSModuleRoot, "bin", "maintenancesolution")
            }
        }

        if (-not $localCachedCopy) {
            # Do we need a fresly cached version of the software?
            $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
            $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child 'sql-server-maintenance-solution-main'
            if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
                if ($PSCmdlet.ShouldProcess('MaintenanceSolution', 'Update local cached copy of the software')) {
                    try {
                        Save-DbaCommunitySoftware -Software MaintenanceSolution -LocalFile $LocalFile -EnableException
                    } catch {
                        # this will help offline Linux machines too
                        Write-Message -Level Verbose -Message "No internet connection found, using included copy of Maintenance Solution."
                        $localCachedCopy = [System.IO.Path]::Combine($script:PSModuleRoot, "bin", "maintenancesolution")
                    }
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
                            IF OBJECT_ID('[dbo].[CommandExecute]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[CommandExecute];
                            IF OBJECT_ID('[dbo].[DatabaseBackup]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[DatabaseBackup];
                            IF OBJECT_ID('[dbo].[DatabaseIntegrityCheck]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[DatabaseIntegrityCheck];
                            IF OBJECT_ID('[dbo].[IndexOptimize]', 'P') IS NOT NULL
                                DROP PROCEDURE [dbo].[IndexOptimize];
                            ")

                if ($LogToTable) {
                    $cleanupQuery += $("
                            IF OBJECT_ID('[dbo].[CommandLog]', 'U') IS NOT NULL
                                DROP TABLE [dbo].[CommandLog];
                            ")
                }

                if ($InstallParallel) {
                    $cleanupQuery += $("
                            IF OBJECT_ID('[dbo].[QueueDatabase]', 'U') IS NOT NULL
                                DROP TABLE [dbo].[QueueDatabase];
                            IF OBJECT_ID('[dbo].[Queue]', 'U') IS NOT NULL
                                DROP TABLE [dbo].[Queue];
                            ")
                }

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
                                $null = Remove-DbaAgentJob -SqlInstance $server -Job $_.name -Confirm:$false
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

            if ($PSBoundParameters.AutoScheduleJobs) {
                Write-ProgressHelper -ExcludePercent -Message "Scheduling jobs"

                <#
                    WeeklyFull will create weekly full, daily differential and 15 minute log backups.

                    To skip diffs, specify NoDiff in the values. To perform log backups each hour instead of every
                    15 minutes, specify HourlyLog in the values.

                    System databases:
                    Full backup every day
                    Integrity check one day per week

                    I (Ola) recommend that you run a full backup after the index maintenance. The following differential backups will then be small. I also recommend that you perform the full backup after the integrity check. Then you know that the integrity of the backup is okay.

                    Cleanup:

                    sp_delete_backuphistory one day per week
                    sp_purge_jobhistory one day per week
                    CommandLog cleanup one day per week
                    Output file cleanup one day per week
                #>
                $null = $server.Refresh()
                $null = $server.JobServer.Jobs.Refresh()

                $schedules = Get-DbaAgentSchedule -SqlInstance $server
                $sunday = $schedules | Where-Object FrequencyInterval -eq 1
                $start = $StartTime
                $hour = New-TimeSpan -Hours 1
                $twohours = New-TimeSpan -Hours 2
                $twelvehours = New-TimeSpan -Hours 12
                $twentyfourhours = New-TimeSpan -Hours 24

                if ($sunday) {
                    foreach ($time in $sunday) {
                        if ($time.ActiveStartTimeOfDay) {
                            if ($time.ActiveStartTimeOfDay.ToString().Replace(":", "") -eq $start) {
                                $start = $time.ActiveStartTimeOfDay.Add($hour).ToString().Replace(":", "")
                            }
                        }
                    }
                }

                if ("WeeklyFull" -in $AutoScheduleJobs) {
                    $fullparams = @{
                        SqlInstance       = $server
                        Job               = "DatabaseBackup - USER_DATABASES - FULL"
                        Schedule          = "Weekly Full User Backup"
                        FrequencyType     = "Weekly"
                        FrequencyInterval = "Sunday" # 1
                        StartTime         = $start
                        Force             = $true
                    }
                } elseif ("DailyFull" -in $AutoScheduleJobs) {
                    $fullparams = @{
                        SqlInstance       = $server
                        Job               = "DatabaseBackup - USER_DATABASES - FULL"
                        Schedule          = "Daily Full User Backup"
                        FrequencyType     = "Daily"
                        FrequencyInterval = "EveryDay"
                        StartTime         = $start
                        Force             = $true
                    }
                }

                $fullschedule = New-DbaAgentSchedule @fullparams

                if ($fullschedule.ActiveStartTimeOfDay) {
                    $systemdaily = $fullschedule.ActiveStartTimeOfDay.Add($twohours) -replace ":|\-|1\.", ""
                } else {
                    $systemdaily = "031500"
                }

                $fullsystemparams = @{
                    SqlInstance       = $server
                    Job               = "DatabaseBackup - SYSTEM_DATABASES - FULL"
                    Schedule          = "Daily Full System Backup"
                    FrequencyType     = "Daily"
                    FrequencyInterval = "EveryDay"
                    StartTime         = $systemdaily
                    Force             = $true
                }

                $null = New-DbaAgentSchedule @fullsystemparams

                if ($fullschedule.ActiveStartTimeOfDay) {
                    $integrity = $fullschedule.ActiveStartTimeOfDay.Subtract($twelvehours) -replace ":|\-|1\.", ""
                } else {
                    $integrity = "044500"
                }

                $integrityparams = @{
                    SqlInstance       = $server
                    Job               = "DatabaseIntegrityCheck - SYSTEM_DATABASES", "DatabaseIntegrityCheck - USER_DATABASES"
                    Schedule          = "Weekly Integrity Check"
                    FrequencyType     = "Weekly"
                    FrequencyInterval = "Saturday" # 6
                    StartTime         = $integrity
                    Force             = $true
                }

                $null = New-DbaAgentSchedule @integrityparams

                if ($fullschedule.ActiveStartTimeOfDay) {
                    $indexoptimize = $fullschedule.ActiveStartTimeOfDay.Subtract($twentyfourhours) -replace ":|\-|1\.", ""
                } else {
                    $indexoptimize = "224500"
                }


                $integrityparams = @{
                    SqlInstance       = $server
                    Job               = "IndexOptimize - USER_DATABASES"
                    Schedule          = "Weekly Index Optimization"
                    FrequencyType     = "Weekly"
                    FrequencyInterval = "Saturday" # 6
                    StartTime         = $indexoptimize
                    Force             = $true
                }

                $null = New-DbaAgentSchedule @integrityparams

                if ("NoDiff" -notin $AutoScheduleJobs -and "DailyFull" -notin $AutoScheduleJobs) {
                    $diffparams = @{
                        SqlInstance       = $server
                        Job               = "DatabaseBackup - USER_DATABASES - DIFF"
                        Schedule          = "Daily Diff Backup"
                        FrequencyType     = "Weekly"
                        FrequencyInterval = 126 # all days but sunday
                        StartTime         = $start
                        Force             = $true
                    }
                    $null = New-DbaAgentSchedule @diffparams
                }

                if ("HourlyLog" -in $AutoScheduleJobs) {
                    $logparams = @{
                        SqlInstance       = $server
                        Job               = "DatabaseBackup - USER_DATABASES - LOG"
                        Schedule          = "Hourly Log Backup"
                        FrequencyType     = "Daily"
                        FrequencyInterval = 1
                        StartTime         = "003000"
                        Force             = $true
                    }
                } else {
                    $logparams = @{
                        SqlInstance             = $server
                        Job                     = "DatabaseBackup - USER_DATABASES - LOG"
                        Schedule                = "15 Minute Log Backup"
                        FrequencyType           = "Daily"
                        FrequencyInterval       = 1
                        FrequencySubDayInterval = 15
                        FrequencySubDayType     = "Minute"
                        StartTime               = "000000"
                        Force                   = $true
                    }
                }
                $null = New-DbaAgentSchedule @logparams

                # You know... why not? These are lightweight tasks.
                $cleanparams = @{
                    SqlInstance       = $server
                    Job               = "Output File Cleanup", "sp_delete_backuphistory", "sp_purge_jobhistory", "CommandLog Cleanup"
                    Schedule          = "Weekly Clean and Purge"
                    FrequencyType     = "Weekly"
                    FrequencyInterval = "Sunday"
                    StartTime         = "235000" # 11:50 pm
                    Force             = $true
                }

                $null = New-DbaAgentSchedule @cleanparams
            }

            if ($query) {
                # then whatif wasn't passed
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Results      = $result
                }
            }

            # Close non-pooled connection as this is not done automatically. If it is a reused Server SMO, connection will be opened again automatically on next request.
            $null = $server | Disconnect-DbaInstance
        }

        Write-ProgressHelper -ExcludePercent -Message "Installation complete"
    }
}