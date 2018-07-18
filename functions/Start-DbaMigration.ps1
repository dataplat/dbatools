function Start-DbaMigration {
    <#
        .SYNOPSIS
            Migrates SQL Server *ALL* databases, logins, database mail profiles/accounts, credentials, SQL Agent objects, linked servers,
            Central Management Server objects, server configuration settings (sp_configure), user objects in systems databases,
            system triggers and backup devices from one SQL Server to another.

            For more granular control, please use one of the -No parameters and use the other functions available within the dbatools module.

        .DESCRIPTION
            Start-DbaMigration consolidates most of the migration tools in dbatools into one command.  This is useful when you're looking to migrate entire instances. It less flexible than using the underlying functions. Think of it as an easy button. It migrates:

            All user databases to exclude support databases such as ReportServerTempDB (Use -IncludeSupportDbs for this). Use -NoDatabases to skip.
            All logins. Use -NoLogins to skip.
            All database mail objects. Use -NoDatabaseMail
            All credentials. Use -NoCredentials to skip.
            All objects within the Job Server (SQL Agent). Use -NoAgentServer to skip.
            All linked servers. Use -NoLinkedServers to skip.
            All groups and servers within Central Management Server. Use -NoCentralManagementServer to skip.
            All SQL Server configuration objects (everything in sp_configure). Use -NoSpConfigure to skip.
            All user objects in system databases. Use -NoSysDbUserObjects to skip.
            All system triggers. Use -NoSystemTriggers to skip.
            All system backup devices. Use -NoBackupDevices to skip.
            All Audits. Use -NoAudits to skip.
            All Endpoints. Use -NoEndpoints to skip.
            All Extended Events. Use -NoExtendedEvents to skip.
            All Policy Management objects. Use -NoPolicyManagement to skip.
            All Resource Governor objects. Use -NoResourceGovernor to skip.
            All Server Audit Specifications. Use -NoServerAuditSpecifications to skip.
            All Custom Errors (User Defined Messages). Use -NoCustomErrors to skip.
            Copies All Data Collector collection sets. Does not configure the server. Use -NoDataCollector to skip.

            This script provides the ability to migrate databases using detach/copy/attach or backup/restore. SQL Server logins, including passwords, SID and database/server roles can also be migrated. In addition, job server objects can be migrated and server configuration settings can be exported or migrated. This script works with named instances, clusters and SQL Express.

            By default, databases will be migrated to the destination SQL Server's default data and log directories. You can override this by specifying -ReuseSourceFolderStructure. Filestreams and filegroups are also migrated. Safety is emphasized.

        .PARAMETER Source
            Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SourceSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Destination
            Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

        .PARAMETER DestinationSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER BackupRestore
            If this switch is enabled, the Copy-Only backup and restore method is used to perform database migrations. You must specify -NetworkShare with a valid UNC format as well (\\server\share).

        .PARAMETER NetworkShare
            Specifies the network location for the backup files. The SQL Server service accounts on both Source and Destination must have read/write permission to access this location.

        .PARAMETER WithReplace
            If this switch is enabled, databases are restored from backup using WITH REPLACE. This is useful if you want to stage some complex file paths.

        .PARAMETER ReuseSourceFolderStructure
            If this switch is enabled, the data and log directory structures on Source will be kept on Destination. Otherwise, databases will be migrated to Destination's default data and log directories.

            Consider this if you're migrating between different versions and use part of Microsoft's default SQL structure (MSSQL12.INSTANCE, etc.).

        .PARAMETER DetachAttach
            If this switch is enabled, the the detach/copy/attach method is used to perform database migrations. No files are deleted on Source. If the destination attachment fails, the source database will be reattached. File copies are performed over administrative shares (\\server\x$\mssql) using BITS. If a database is being mirrored, the mirror will be broken prior to migration.

        .PARAMETER Reattach
            If this switch is enabled, all databases are reattached to Source after a DetachAttach migration is complete.

            .PARAMETER NoRecovery
            If this switch is enabled, databases will be left in the No Recovery state to enable further backups to be added.

        .PARAMETER IncludeSupportDbs
            If this switch is enabled, the ReportServer, ReportServerTempDb, SSIDb, and distribution databases will be migrated if they exist. A logfile named $SOURCE-$DESTINATION-$date-Sqls.csv will be written to the current directory. Requires -BackupRestore or -DetachAttach.

        .PARAMETER SetSourceReadOnly
            If this switch is enabled, all migrated databases will be set to ReadOnly on the source instance prior to detach/attach & backup/restore. If -Reattach is specified, the database is set to read-only after reattaching.

        .PARAMETER NoDatabases
            If this switch is enabled, databases will not be migrated.

        .PARAMETER NoLogins
            If this switch is enabled, Logins will not be migrated.

        .PARAMETER NoAgentServer
            If this switch is enabled, SQL Agent jobs will not be migrated.

        .PARAMETER NoCredentials
            If this switch is enabled, Credentials will not be migrated.

        .PARAMETER NoLinkedServers
            If this switch is enabled, Linked Servers will not be migrated.

        .PARAMETER NoSpConfigure
            If this switch is enabled, options configured via sp_configure will not be migrated.

        .PARAMETER NoCentralManagementServer
            If this switch is enabled, Central Management Server will not be migrated.

        .PARAMETER NoDatabaseMail
            If this switch is enabled, Database Mail will not be migrated.

        .PARAMETER NoSysDbUserObjects
            If this switch is enabled, user objects found in the master, msdb and model databases will not be migrated.

        .PARAMETER NoSystemTriggers
            If this switch is enabled, System Triggers will not be migrated.

        .PARAMETER NoBackupDevices
            If this switch is enabled, Backup Devices will not be migrated.

        .PARAMETER NoAudits
            If this switch is enabled, Audits will not be migrated.

        .PARAMETER NoEndpoints
            If this switch is enabled, Endpoints will not be migrated.

        .PARAMETER NoExtendedEvents
            If this switch is enabled, Extended Events will not be migrated.

        .PARAMETER NoPolicyManagement
            If this switch is enabled, Policy-Based Management will not be migrated.

        .PARAMETER NoResourceGovernor
            If this switch is enabled, Resource Governor will not be migrated.

        .PARAMETER NoServerAuditSpecifications
            If this switch is enabled, the Server Audit Specification will not be migrated.

        .PARAMETER NoCustomErrors
            If this switch is enabled, Custom Errors (User Defined Messages) will not be migrated.

        .PARAMETER NoDataCollector
            If this switch is enabled, the Data Collector will not be migrated.

        .PARAMETER NoSaRename
            If this switch is enabled, the sa account will not be renamed on the destination instance to match the source.

        .PARAMETER DisableJobsOnDestination
            If this switch is enabled, migrated SQL Agent jobs will be disabled on the destination instance.

        .PARAMETER DisableJobsOnSource
            If this switch is enabled, SQL Agent jobs will be disabled on the source instance.

        .PARAMETER Force
            If migrating users, forces drop and recreate of SQL and Windows logins.
            If migrating databases, deletes existing databases with matching names.
            If using -DetachAttach, -Force will break mirrors and drop dbs from Availability Groups.

            For other migration objects, it will just drop existing items and readd, if -force is supported within the underlying function.

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
            Author: Chrissy LeMaire
            Limitations:     Doesn't cover what it doesn't cover (certificates, etc)
                            SQL Server 2000 login migrations have some limitations (server perms aren't migrated)
                            SQL Server 2000 databases cannot be directly migrated to SQL Server 2012 and above.
                            Logins within SQL Server 2012 and above logins cannot be migrated to SQL Server 2008 R2 and below.
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Start-DbaMigration

        .EXAMPLE
            Start-DbaMigration -Source sqlserver\instance -Destination sqlcluster -DetachAttach

            All databases, logins, job objects and sp_configure options will be migrated from sqlserver\instance to sqlcluster. Databases will be migrated using the detach/copy files/attach method. Dbowner will be updated. User passwords, SIDs, database roles and server roles will be migrated along with the login.

        .EXAMPLE
            Start-DbaMigration -Verbose -Source sqlcluster -Destination sql2016 -SourceSqlCredential $scred -ReuseSourceFolderStructure -DestinationSqlCredential $cred -Force -NetworkShare \\fileserver\share\sqlbackups\Migration -BackupRestore

            Migrate databases uses backup/restore. Also migrate logins, database mail, credentials, SQL Agent, Central Management Server, SQL global configuration.

        .EXAMPLE
            Start-DbaMigration -Verbose -Source sqlcluster -Destination sql2016 -NoDatabases -NoLogins

            Migrates everything but logins and databases.

        .EXAMPLE
            Start-DbaMigration -Verbose -Source sqlcluster -Destination sql2016 -DetachAttach -Reattach -SetSourceReadonly

            Migrate databases using detach/copy/attach. Reattach at source and set source databases read-only. Also migrates everything else.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    Param (
        [parameter(Position = 1, Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [parameter(Position = 2, Mandatory = $true)]
        [DbaInstanceParameter[]]$Destination,
        [parameter(Position = 3, Mandatory = $true, ParameterSetName = "DbAttachDetach")]
        [switch]$DetachAttach,
        [parameter(Position = 4, ParameterSetName = "DbAttachDetach")]
        [switch]$Reattach,
        [parameter(Position = 5, Mandatory = $true, ParameterSetName = "DbBackup")]
        [switch]$BackupRestore,
        [parameter(Position = 6, Mandatory = $true, ParameterSetName = "DbBackup",
                   HelpMessage = "Specify a valid network share in the format \\server\share that can be accessed by your account and both Sql Server service accounts.")]
        [string]$NetworkShare,
        [parameter(Position = 7, ParameterSetName = "DbBackup")]
        [switch]$WithReplace,
        [parameter(Position = 8, ParameterSetName = "DbBackup")]
        [switch]$NoRecovery,
        [parameter(Position = 9, ParameterSetName = "DbBackup")]
        [parameter(Position = 10, ParameterSetName = "DbAttachDetach")]
        [switch]$SetSourceReadOnly,
        [Alias("ReuseFolderStructure")]
        [parameter(Position = 11, ParameterSetName = "DbBackup")]
        [parameter(Position = 12, ParameterSetName = "DbAttachDetach")]
        [switch]$ReuseSourceFolderStructure,
        [parameter(Position = 13, ParameterSetName = "DbBackup")]
        [parameter(Position = 14, ParameterSetName = "DbAttachDetach")]
        [switch]$IncludeSupportDbs,
        [parameter(Position = 15)]
        [PSCredential]$SourceSqlCredential,
        [parameter(Position = 16)]
        [PSCredential]$DestinationSqlCredential,
        [Alias("SkipDatabases")]
        [switch]$NoDatabases,
        [switch]$NoLogins,
        [Alias("SkipJobServer", "NoJobServer")]
        [switch]$NoAgentServer,
        [Alias("SkipCredentials")]
        [switch]$NoCredentials,
        [Alias("SkipLinkedServers")]
        [switch]$NoLinkedServers,
        [Alias("SkipSpConfigure")]
        [switch]$NoSpConfigure,
        [Alias("SkipCentralManagementServer")]
        [switch]$NoCentralManagementServer,
        [Alias("SkipDatabaseMail")]
        [switch]$NoDatabaseMail,
        [Alias("SkipSysDbUserObjects")]
        [switch]$NoSysDbUserObjects,
        [Alias("SkipSystemTriggers")]
        [switch]$NoSystemTriggers,
        [Alias("SkipBackupDevices")]
        [switch]$NoBackupDevices,
        [switch]$NoAudits,
        [switch]$NoEndpoints,
        [switch]$NoExtendedEvents,
        [switch]$NoPolicyManagement,
        [switch]$NoResourceGovernor,
        [switch]$NoServerAuditSpecifications,
        [switch]$NoCustomErrors,
        [switch]$NoDataCollector,
        [switch]$DisableJobsOnDestination,
        [switch]$DisableJobsOnSource,
        [switch]$NoSaRename,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $started = Get-Date
        $sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential

        if ($BackupRestore -eq $false -and $DetachAttach -eq $false -and $NoDatabases -eq $false) {
            Stop-Function -Message "You must specify a database migration method (-BackupRestore or -DetachAttach) or -NoDatabases"
            return
        }

        if (-not $NoDatabases) {
            if (-not $DetachAttach -and !$BackupRestore) {
                Stop-Function -Message "You must specify a migration method using -BackupRestore or -DetachAttach."
                return
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $NoSpConfigure) {
            Write-Message -Level Verbose -Message "Migrating SQL Server Configuration"
            Copy-DbaSpConfigure -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential
        }

        if (-not $NoCustomErrors) {
            Write-Message -Level Verbose -Message "Migrating custom errors (user defined messages)"
            Copy-DbaCustomError -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoCredentials) {
            Write-Message -Level Verbose -Message "Migrating SQL credentials"
            Copy-DbaCredential -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoDatabaseMail) {
            Write-Message -Level Verbose -Message "Migrating database mail"
            Copy-DbaDatabaseMail -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoSysDbUserObjects) {
            Write-Message -Level Verbose -Message "Migrating user objects in system databases (this can take a second)."
            If ($Pscmdlet.ShouldProcess($destination, "Copying user objects.")) {
                Copy-DbaSysDbUserObject -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential
            }
        }

        if (-not $NoCentralManagementServer) {
            Write-Message -Level Verbose -Message "Migrating Central Management Server"
            Copy-DbaCentralManagementServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoBackupDevices) {
            Write-Message -Level Verbose -Message "Migrating Backup Devices"
            Copy-DbaBackupDevice -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoLinkedServers) {
            Write-Message -Level Verbose -Message "Migrating linked servers"
            Copy-DbaLinkedServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoSystemTriggers) {
            Write-Message -Level Verbose -Message "Migrating System Triggers"
            Copy-DbaServerTrigger -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoDatabases) {
            # Do it
            Write-Message -Level Verbose -Message "Migrating databases"
            if ($BackupRestore) {
                Copy-DbaDatabase -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -AllDatabases -SetSourceReadOnly:$SetSourceReadOnly -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -BackupRestore -NetworkShare $NetworkShare -Force:$Force -NoRecovery:$NoRecovery -WithReplace:$WithReplace -IncludeSupportDbs:$IncludeSupportDbs
            }
            else {
                Copy-DbaDatabase -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -AllDatabases -SetSourceReadOnly:$SetSourceReadOnly -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -DetachAttach:$DetachAttach -Reattach:$Reattach -Force:$Force -IncludeSupportDbs:$IncludeSupportDbs
            }
        }

        if (-not $NoLogins) {
            Write-Message -Level Verbose -Message "Migrating logins"
            $syncit = $NoSaRename -eq $false
            Copy-DbaLogin -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force -SyncSaName:$syncit
        }

        if (-not $NoLogins -and -not $NoDatabases -and -not $NoRecovery) {
            Write-Message -Level Verbose -Message "Updating database owners to match newly migrated logins"
            foreach ($dest in $Destination) {
                $null = Update-SqlDbOwner -Source $sourceserver -Destination $dest -DestinationSqlCredential $DestinationSqlCredential
            }
        }
        
        if (-not $NoDataCollector) {
            Write-Message -Level Verbose -Message "Migrating Data Collector collection sets"
            Copy-DbaSqlDataCollector -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoAudits) {
            Write-Message -Level Verbose -Message "Migrating Audits"
            Copy-DbaServerAudit -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoServerAuditSpecifications) {
            Write-Message -Level Verbose -Message "Migrating Server Audit Specifications"
            Copy-DbaServerAuditSpecification -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoEndpoints) {
            Write-Message -Level Verbose -Message "Migrating Endpoints"
            Copy-DbaEndpoint -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoPolicyManagement) {
            Write-Message -Level Verbose -Message "Migrating Policy Management"
            Copy-DbaSqlPolicyManagement -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoResourceGovernor) {
            Write-Message -Level Verbose -Message "Migrating Resource Governor"
            Copy-DbaResourceGovernor -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoExtendedEvents) {
            Write-Message -Level Verbose -Message "Migrating Extended Events"
            Copy-DbaExtendedEvent -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if (-not $NoAgentServer) {
            Write-Message -Level Verbose -Message "Migrating job server"
            Copy-DbaSqlServerAgent -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -DisableJobsOnDestination:$DisableJobsOnDestination -DisableJobsOnSource:$DisableJobsOnSource -Force:$Force
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