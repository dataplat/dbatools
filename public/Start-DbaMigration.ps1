function Start-DbaMigration {
    <#
    .SYNOPSIS
        Migrates entire SQL Server instances including all databases, logins, server configuration, and server objects from source to destination servers.

    .DESCRIPTION
        Start-DbaMigration consolidates most of the migration tools in dbatools into one command for complete instance migrations. This function serves as an "easy button" when you need to move an entire SQL Server instance to new hardware, perform version upgrades, or consolidate servers. It's less flexible than using individual migration functions but handles the complexity of orchestrating a full migration workflow.

        The function migrates:

        All user databases to exclude support databases such as ReportServerTempDB (Use -IncludeSupportDbs for this). Use -Exclude Databases to skip.
        All logins. Use -Exclude Logins to skip.
        All database mail objects. Use -Exclude DatabaseMail
        All credentials. Use -Exclude Credentials to skip.
        All objects within the Job Server (SQL Agent). Use -Exclude AgentServer to skip.
        All linked servers. Use -Exclude LinkedServers to skip.
        All groups and servers within Central Management Server. Use -Exclude CentralManagementServer to skip.
        All SQL Server configuration objects (everything in sp_configure). Use -Exclude SpConfigure to skip.
        All user objects in system databases. Use -Exclude SysDbUserObjects to skip.
        All system triggers. Use -Exclude SystemTriggers to skip.
        All system backup devices. Use -Exclude BackupDevices to skip.
        All Audits. Use -Exclude Audits to skip.
        All Endpoints. Use -Exclude Endpoints to skip.
        All Extended Events. Use -Exclude ExtendedEvents to skip.
        All Policy Management objects. Use -Exclude PolicyManagement to skip.
        All Resource Governor objects. Use -Exclude ResourceGovernor to skip.
        All Server Audit Specifications. Use -Exclude ServerAuditSpecifications to skip.
        All Custom Errors (User Defined Messages). Use -Exclude CustomErrors to skip.
        All Data Collector collection sets. Does not configure the server. Use -Exclude DataCollector to skip.
        All startup procedures. Use -Exclude StartupProcedures to skip.

        This script provides the ability to migrate databases using detach/copy/attach or backup/restore. SQL Server logins, including passwords, SID and database/server roles can also be migrated. In addition, job server objects can be migrated and server configuration settings can be exported or migrated. This script works with named instances, clusters and SQL Express.

        By default, databases will be migrated to the destination SQL Server's default data and log directories. You can override this by specifying -ReuseSourceFolderStructure. Filestreams and filegroups are also migrated. Safety is emphasized.

    .PARAMETER Source
        Specifies the source SQL Server instance to migrate from. Accepts server name, server\instance, or connection string formats.
        This is the instance where all databases, logins, and server objects currently exist.

    .PARAMETER SourceSqlCredential
        Specifies credentials to connect to the source SQL Server instance. Use when the current Windows account lacks sufficient permissions.
        Accepts PowerShell credential objects created with Get-Credential for SQL Authentication or alternative Windows accounts.

    .PARAMETER Destination
        Specifies one or more destination SQL Server instances to migrate to. Accepts server name, server\instance, or connection string formats.
        When specifying multiple destinations, all objects will be migrated to each destination server.
        Multiple destinations require -Reattach when using -DetachAttach method.

    .PARAMETER DestinationSqlCredential
        Specifies credentials to connect to the destination SQL Server instance(s). Use when the current Windows account lacks sufficient permissions.
        Accepts PowerShell credential objects created with Get-Credential for SQL Authentication or alternative Windows accounts.

    .PARAMETER BackupRestore
        Uses backup and restore method to migrate databases instead of detach/attach. Creates copy-only backups to preserve existing backup chains.
        Requires either -SharedPath for new backups or -UseLastBackup to restore from existing backup files.
        This method is safer for production environments as it doesn't detach databases.

    .PARAMETER SharedPath
        Specifies the network path where backup files will be created and stored during migration. Must be a UNC path (\\server\share) or Azure Storage URL.
        Both source and destination SQL Server service accounts require read/write permissions to this location.
        Only used with -BackupRestore method when not using -UseLastBackup.

    .PARAMETER WithReplace
        Forces restore operations to overwrite existing databases with the same name on the destination.
        Use this when you need to replace existing databases or when destination databases have different file paths than source.
        Only applies to backup/restore method.

    .PARAMETER ReuseSourceFolderStructure
        Preserves the original file paths from the source server when restoring databases on the destination.
        By default, databases are restored to the destination's default data and log directories.
        Use this when you need to maintain specific drive letters or folder structures on the destination server.

    .PARAMETER DetachAttach
        Uses detach, copy, and attach method to migrate databases. Temporarily makes databases unavailable during the migration process.
        Files are copied using BITS over administrative shares and databases are reattached if destination attachment fails.
        This method is faster than backup/restore but requires downtime and breaks mirroring/replication.

    .PARAMETER Reattach
        Reattaches all databases to the source server after a detach/attach migration completes.
        Use this when you want to keep the source databases online after migration, such as for testing or gradual cutover scenarios.
        Required when using -DetachAttach with multiple destination servers.

    .PARAMETER NoRecovery
        Restores databases in NORECOVERY mode, leaving them in a restoring state for additional log backups.
        Use this when you plan to apply differential or transaction log backups after the initial restore.
        Only applies to backup/restore method and prevents normal database access until recovered.

    .PARAMETER IncludeSupportDbs
        Includes system support databases in the migration: ReportServer, ReportServerTempDB, SSISDB, and distribution databases.
        By default, these databases are excluded to prevent conflicts with existing services.
        Use this when migrating servers with SQL Server Reporting Services, Integration Services, or replication configured.

    .PARAMETER SetSourceReadOnly
        Sets migrated databases to read-only mode on the source server before migration begins.
        This prevents data changes during migration and helps ensure data consistency.
        When combined with -Reattach, databases remain read-only after being reattached to the source.

    .PARAMETER AzureCredential
        Specifies the name of a SQL Server credential for accessing Azure Storage when SharedPath points to an Azure Storage account.
        The credential must already exist on both source and destination servers with proper access to the Azure Storage container.
        Only needed when using Azure Storage URLs for the SharedPath parameter.

    .PARAMETER Exclude
        Specifies which migration components to skip during the migration process.
        Use this to exclude specific object types when you only need partial migrations or when certain objects should remain on the source.
        Valid values: Databases, Logins, AgentServer, Credentials, LinkedServers, SpConfigure, CentralManagementServer, DatabaseMail, SysDbUserObjects, SystemTriggers, BackupDevices, Audits, Endpoints, ExtendedEvents, PolicyManagement, ResourceGovernor, ServerAuditSpecifications, CustomErrors, DataCollector, StartupProcedures, AgentServerProperties, MasterCertificates.

    .PARAMETER ExcludeSaRename
        Prevents renaming the sa account on the destination to match the source server's sa account name.
        By default, the destination sa account is renamed to match the source for consistency.
        Use this when you want to maintain the destination server's original sa account name.

    .PARAMETER DisableJobsOnDestination
        Disables all migrated SQL Agent jobs on the destination server after migration completes.
        Use this to prevent jobs from running automatically on the destination until you're ready to activate them.
        Helpful for staged migrations or when you need to update job schedules before activation.

    .PARAMETER DisableJobsOnSource
        Disables all SQL Agent jobs on the source server during the migration process.
        Use this to prevent jobs from running and potentially interfering with database migrations.
        Jobs remain disabled on the source after migration completes.

    .PARAMETER UseLastBackup
        Uses existing backup files instead of creating new backups during database migration.
        The function will locate the most recent full, differential, and log backups for each database.
        Backup files must be accessible to all destination servers, typically on a network share.

    .PARAMETER Continue
        Attempts to apply additional transaction log backups to databases already in RESTORING or STANDBY states.
        Use this to bring destination databases up-to-date when they were previously restored with NORECOVERY.
        Only works with -UseLastBackup and requires databases to already exist in a restoring state.

    .PARAMETER KeepCDC
        Preserves Change Data Capture (CDC) configuration and data during database migration.
        By default, CDC information is not migrated to avoid potential conflicts with existing CDC configurations.
        Use this when you need to maintain CDC functionality on the destination server.

    .PARAMETER KeepReplication
        Preserves replication configuration and metadata during database migration.
        By default, replication settings are not migrated to prevent conflicts with existing replication topologies.
        Use this when migrating databases that participate in replication and you want to maintain those settings.

    .PARAMETER MasterKeyPassword
        Specifies the password for creating or opening database master keys during certificate migration.
        Required when migrating databases with encrypted objects or certificates that need master key protection.
        Must be provided as a SecureString object for security.

    .PARAMETER Force
        Overwrites existing objects on the destination server without prompting for confirmation.
        For databases: drops existing databases with matching names before restoring.
        For logins: drops and recreates existing logins instead of skipping them.
        For DetachAttach method: breaks database mirroring and removes databases from Availability Groups.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Start-DbaMigration

    .EXAMPLE
        PS C:\> Start-DbaMigration -Source sqlserver\instance -Destination sqlcluster -DetachAttach

        All databases, logins, job objects and sp_configure options will be migrated from sqlserver\instance to sqlcluster. Databases will be migrated using the detach/copy files/attach method. Dbowner will be updated. User passwords, SIDs, database roles and server roles will be migrated along with the login.

    .EXAMPLE
        PS C:\> $params = @{
        >> Source = "sqlcluster"
        >> Destination = "sql2016"
        >> SourceSqlCredential = $scred
        >> DestinationSqlCredential = $cred
        >> SharedPath = "\\fileserver\share\sqlbackups\Migration"
        >> BackupRestore = $true
        >> ReuseSourceFolderStructure = $true
        >> Force = $true
        >> }
        >>
        PS C:\> Start-DbaMigration @params -Verbose

        Utilizes splatting technique to set all the needed parameters. This will migrate databases using the backup/restore method. It will also include migration of the logins, database mail configuration, credentials, SQL Agent, Central Management Server, and SQL Server global configuration.

    .EXAMPLE
        PS C:\> Start-DbaMigration -Verbose -Source sqlcluster -Destination sql2016 -DetachAttach -Reattach -SetSourceReadonly

        Migrates databases using detach/copy/attach. Reattach at source and set source databases read-only. Also migrates everything else.

    .EXAMPLE
        PS C:\> $PSDefaultParameters = @{
        >> "dbatools:Source" = "sqlcluster"
        >> "dbatools:Destination" = "sql2016"
        >> }
        >>
        PS C:\> Start-DbaMigration -Verbose -Exclude Databases, Logins

        Utilizes the PSDefaultParameterValues system variable, and sets the Source and Destination parameters for any function in the module that has those parameter names. This prevents the need from passing them in constantly.
        The execution of the function will migrate everything but logins and databases.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter]$Source,
        [DbaInstanceParameter[]]$Destination,
        [switch]$DetachAttach,
        [switch]$Reattach,
        [switch]$BackupRestore,
        [parameter(HelpMessage = "Specify a valid network share in the format \\server\share that can be accessed by your account and both Sql Server service accounts, or a URL to an Azure Storage account")]
        [string]$SharedPath,
        [switch]$WithReplace,
        [switch]$NoRecovery,
        [switch]$SetSourceReadOnly,
        [switch]$ReuseSourceFolderStructure,
        [switch]$IncludeSupportDbs,
        [PSCredential]$SourceSqlCredential,
        [PSCredential]$DestinationSqlCredential,
        [ValidateSet('Databases', 'Logins', 'AgentServer', 'Credentials', 'LinkedServers', 'SpConfigure', 'CentralManagementServer', 'DatabaseMail', 'SysDbUserObjects', 'SystemTriggers', 'BackupDevices', 'Audits', 'Endpoints', 'ExtendedEvents', 'PolicyManagement', 'ResourceGovernor', 'ServerAuditSpecifications', 'CustomErrors', 'DataCollector', 'StartupProcedures', 'AgentServerProperties', 'MasterCertificates')]
        [string[]]$Exclude,
        [switch]$DisableJobsOnDestination,
        [switch]$DisableJobsOnSource,
        [switch]$ExcludeSaRename,
        [switch]$UseLastBackup,
        [switch]$KeepCDC,
        [switch]$KeepReplication,
        [switch]$Continue,
        [switch]$Force,
        [string]$AzureCredential,
        [Security.SecureString]$MasterKeyPassword,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        if ($Exclude -notcontains "Databases") {
            if (-not $BackupRestore -and -not $DetachAttach -and -not $UseLastBackup) {
                Stop-Function -Message "You must specify a database migration method (-BackupRestore or -DetachAttach) or -Exclude Databases"
                return
            }
        }
        if ($DetachAttach -and ($BackupRestore -or $UseLastBackup)) {
            Stop-Function -Message "-DetachAttach cannot be used with -BackupRestore or -UseLastBackup"
            return
        }
        if ($BackupRestore -and (-not $SharedPath -and -not $UseLastBackup)) {
            Stop-Function -Message "When using -BackupRestore, you must specify -SharedPath or -UseLastBackup"
            return
        }
        if ($SharedPath -and $UseLastBackup) {
            Stop-Function -Message "-SharedPath cannot be used with -UseLastBackup because the backup path is determined by the paths in the last backups"
            return
        }
        if ($DetachAttach -and -not $Reattach -and $Destination.Count -gt 1) {
            Stop-Function -Message "When using -DetachAttach with multiple servers, you must specify -Reattach to reattach database at source"
            return
        }
        if ($Continue -and -not $UseLastBackup) {
            Stop-Function -Message "-Continue cannot be used without -UseLastBackup"
            return
        }
        if ($UseLastBackup -and -not $BackupRestore) {
            $BackupRestore = $true
        }

        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $started = Get-Date
        $stepCounter = 0
    }

    process {
        if (Test-FunctionInterrupt) { return }

        # testing twice for whatif reasons
        if ($Exclude -notcontains "Databases") {
            if (-not $BackupRestore -and -not $DetachAttach -and -not $UseLastBackup) {
                Stop-Function -Message "You must specify a database migration method (-BackupRestore or -DetachAttach) or -Exclude Databases"
                return
            }
        }

        if ($DetachAttach -and ($BackupRestore -or $UseLastBackup)) {
            Stop-Function -Message "-DetachAttach cannot be used with -BackupRestore or -UseLastBackup"
            return
        }
        if ($BackupRestore -and (-not $SharedPath -and -not $UseLastBackup)) {
            Stop-Function -Message "When using -BackupRestore, you must specify -SharedPath or -UseLastBackup"
            return
        }
        if ($SharedPath -like 'https*' -and $DetachAttach) {
            Stop-Function -Message "URL shared storage is only supported by BackupRstore"
            return
        }
        if ($SharedPath -and $UseLastBackup) {
            Stop-Function -Message "-SharedPath cannot be used with -UseLastBackup because the backup path is determined by the paths in the last backups"
            return
        }
        if ($DetachAttach -and -not $Reattach -and $Destination.Count -gt 1) {
            Stop-Function -Message "When using -DetachAttach with multiple servers, you must specify -Reattach to reattach database at source"
            return
        }
        if ($Continue -and -not $UseLastBackup) {
            Stop-Function -Message "-Continue cannot be used without -UseLastBackup"
            return
        }
        if ($UseLastBackup -and -not $BackupRestore) {
            $BackupRestore = $true
        }

        try {
            $sourceserver = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        if ($Exclude -notcontains 'SpConfigure') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating SQL Server Configuration"
            Write-Message -Level Verbose -Message "Migrating SQL Server Configuration"
            Copy-DbaSpConfigure -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential
        }

        if ($Exclude -notcontains 'MasterCertificates') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Copying certificates in the master database"
            Write-Message -Level Verbose -Message "Copying certificates in the master database"
            Copy-DbaDbCertificate -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -EncryptionPassword (Get-RandomPassword) -MasterKeyPassword $MasterKeyPassword -Database master -SharedPath $SharedPath

        }

        if ($Exclude -notcontains 'CustomErrors') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating custom errors (user defined messages)"
            Write-Message -Level Verbose -Message "Migrating custom errors (user defined messages)"
            Copy-DbaCustomError -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Credentials') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating SQL credentials"
            Write-Message -Level Verbose -Message "Migrating SQL credentials"
            Copy-DbaCredential -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'DatabaseMail') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating database mail"
            Write-Message -Level Verbose -Message "Migrating database mail"
            Copy-DbaDbMail -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'CentralManagementServer') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Central Management Server"
            Write-Message -Level Verbose -Message "Migrating Central Management Server"
            Copy-DbaRegServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'BackupDevices') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Backup Devices"
            Write-Message -Level Verbose -Message "Migrating Backup Devices"
            Copy-DbaBackupDevice -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'SystemTriggers') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating System Triggers"
            Write-Message -Level Verbose -Message "Migrating System Triggers"
            Copy-DbaInstanceTrigger -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Databases') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating databases"
            Write-Message -Level Verbose -Message "Migrating databases"

            $CopyDatabaseSplat = @{
                Source                     = $sourceserver
                Destination                = $Destination
                DestinationSqlCredential   = $DestinationSqlCredential
                SetSourceReadOnly          = $SetSourceReadOnly
                ReuseSourceFolderStructure = $ReuseSourceFolderStructure
                AllDatabases               = $true
                Force                      = $Force
                IncludeSupportDbs          = $IncludeSupportDbs
            }

            if ($BackupRestore) {
                $CopyDatabaseSplat += @{
                    BackupRestore   = $true
                    NoRecovery      = $NoRecovery
                    WithReplace     = $WithReplace
                    KeepCDC         = $KeepCDC
                    KeepReplication = $KeepReplication
                }
                if ($UseLastBackup) {
                    $CopyDatabaseSplat += @{
                        UseLastBackup = $UseLastBackup
                        Continue      = $Continue
                    }
                } else {
                    $CopyDatabaseSplat += @{
                        SharedPath      = $SharedPath
                        AzureCredential = $AzureCredential
                    }
                }
            } else {
                $CopyDatabaseSplat += @{
                    DetachAttach = $DetachAttach
                    Reattach     = $Reattach
                }
            }

            Copy-DbaDatabase @CopyDatabaseSplat
        }

        if ($Exclude -notcontains 'Logins') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating logins"
            Write-Message -Level Verbose -Message "Migrating logins"
            $syncit = $ExcludeSaRename -eq $false
            Copy-DbaLogin -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force -SyncSaName:$syncit
        }

        if ($Exclude -notcontains 'Logins' -and $Exclude -notcontains 'Databases' -and -not $NoRecovery) {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Updating database owners to match newly migrated logins"
            Write-Message -Level Verbose -Message "Updating database owners to match newly migrated logins"
            foreach ($dest in $Destination) {
                $null = Update-SqlDbOwner -Source $sourceserver -Destination $dest -DestinationSqlCredential $DestinationSqlCredential
            }
        }

        if ($Exclude -notcontains 'LinkedServers') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating linked servers"
            Write-Message -Level Verbose -Message "Migrating linked servers"
            Copy-DbaLinkedServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'DataCollector') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Data Collector collection sets"
            Write-Message -Level Verbose -Message "Migrating Data Collector collection sets"
            Copy-DbaDataCollector -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Audits') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Audits"
            Write-Message -Level Verbose -Message "Migrating Audits"
            Copy-DbaInstanceAudit -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'ServerAuditSpecifications') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Server Audit Specifications"
            Write-Message -Level Verbose -Message "Migrating Server Audit Specifications"
            Copy-DbaInstanceAuditSpecification -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Endpoints') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Endpoints"
            Write-Message -Level Verbose -Message "Migrating Endpoints"
            Copy-DbaEndpoint -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'PolicyManagement') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Policy Management"
            Write-Message -Level Verbose -Message "Migrating Policy Management"
            Copy-DbaPolicyManagement -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'ResourceGovernor') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Resource Governor"
            Write-Message -Level Verbose -Message "Migrating Resource Governor"
            Copy-DbaResourceGovernor -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'SysDbUserObjects') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating user objects in system databases (this can take a second)"
            Write-Message -Level Verbose -Message "Migrating user objects in system databases (this can take a second)."
            If ($Pscmdlet.ShouldProcess($destination, "Copying user objects.")) {
                Copy-DbaSystemDbUserObject -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$force
            }
        }

        if ($Exclude -notcontains 'ExtendedEvents') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating Extended Events"
            Write-Message -Level Verbose -Message "Migrating Extended Events"
            Copy-DbaXESession -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'AgentServer') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating job server"
            Write-Message -Level Verbose -Message "Migrating job server"
            $ExcludeAgentServerProperties = $Exclude -contains 'AgentServerProperties'
            Copy-DbaAgentServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -DisableJobsOnDestination:$DisableJobsOnDestination -DisableJobsOnSource:$DisableJobsOnSource -Force:$Force -ExcludeServerProperties:$ExcludeAgentServerProperties
        }

        if ($Exclude -notcontains 'StartupProcedures') {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Migrating startup procedures"
            Write-Message -Level Verbose -Message "Migrating startup procedures"
            Copy-DbaStartupProcedure -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }
        $totaltime = ($elapsed.Elapsed.toString().Split(".")[0])
        Write-Message -Level Verbose -Message "SQL Server migration complete."
        Write-Message -Level Verbose -Message "Migration started: $started"
        Write-Message -Level Verbose -Message "Migration completed: $(Get-Date)"
        Write-Message -Level Verbose -Message "Total Elapsed time: $totaltime"
    }
}