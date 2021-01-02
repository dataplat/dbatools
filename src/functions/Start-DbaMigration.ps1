function Start-DbaMigration {
    <#
    .SYNOPSIS
        Migrates SQL Server *ALL* databases, logins, database mail profiles/accounts, credentials, SQL Agent objects, linked servers,
        Central Management Server objects, server configuration settings (sp_configure), user objects in systems databases,
        system triggers and backup devices from one SQL Server to another.

        For more granular control, please use Exclude or use the other functions available within the dbatools module.

    .DESCRIPTION
        Start-DbaMigration consolidates most of the migration tools in dbatools into one command.  This is useful when you're looking to migrate entire instances. It less flexible than using the underlying functions. Think of it as an easy button. It migrates:

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
        Source SQL Server.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You may specify multiple servers.

        Note that when using -BackupRestore with multiple servers, the backup will only be performed once and backups will be deleted at the end (if you didn't specify -ExcludeBackupCleanup).

        When using -DetachAttach with multiple servers, -Reattach must be specified.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER BackupRestore
        If this switch is enabled, the Copy-Only backup and restore method is used to perform database migrations. You must specify -SharedPath with a valid UNC format as well (\\server\share).

    .PARAMETER SharedPath
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

    .PARAMETER AzureCredential
        Name of the AzureCredential if SharedPath is Azure page blob

    .PARAMETER Exclude
        Exclude one or more objects to migrate

        Databases
        Logins
        AgentServer
        Credentials
        LinkedServers
        SpConfigure
        CentralManagementServer
        DatabaseMail
        SysDbUserObjects
        SystemTriggers
        BackupDevices
        Audits
        Endpoints
        ExtendedEvents
        PolicyManagement
        ResourceGovernor
        ServerAuditSpecifications
        CustomErrors
        DataCollector
        StartupProcedures
        AgentServerProperties

    .PARAMETER ExcludeSaRename
        If this switch is enabled, the sa account will not be renamed on the destination instance to match the source.

    .PARAMETER DisableJobsOnDestination
        If this switch is enabled, migrated SQL Agent jobs will be disabled on the destination instance.

    .PARAMETER DisableJobsOnSource
        If this switch is enabled, SQL Agent jobs will be disabled on the source instance.

    .PARAMETER UseLastBackup
        Use the last full, diff and logs instead of performing backups. Note that the backups must exist in a location accessible by all destination servers, such a network share.

    .PARAMETER Continue
        If specified, will to attempt to restore transaction log backups on top of existing database(s) in Recovering or Standby states. Only usable with -UseLastBackup

    .PARAMETER KeepCDC
        Indicates whether CDC information should be copied as part of the database

    .PARAMETER KeepReplication
        Indicates whether replication configuration should be copied as part of the database copy operation

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
        [ValidateSet('Databases', 'Logins', 'AgentServer', 'Credentials', 'LinkedServers', 'SpConfigure', 'CentralManagementServer', 'DatabaseMail', 'SysDbUserObjects', 'SystemTriggers', 'BackupDevices', 'Audits', 'Endpoints', 'ExtendedEvents', 'PolicyManagement', 'ResourceGovernor', 'ServerAuditSpecifications', 'CustomErrors', 'DataCollector', 'StartupProcedures', 'AgentServerProperties')]
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
        $sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
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
        if ($Exclude -notcontains 'SpConfigure') {
            Write-Message -Level Verbose -Message "Migrating SQL Server Configuration"
            Copy-DbaSpConfigure -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential
        }

        if ($Exclude -notcontains 'CustomErrors') {
            Write-Message -Level Verbose -Message "Migrating custom errors (user defined messages)"
            Copy-DbaCustomError -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Credentials') {
            Write-Message -Level Verbose -Message "Migrating SQL credentials"
            Copy-DbaCredential -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'DatabaseMail') {
            Write-Message -Level Verbose -Message "Migrating database mail"
            Copy-DbaDbMail -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'CentralManagementServer') {
            Write-Message -Level Verbose -Message "Migrating Central Management Server"
            Copy-DbaRegServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'BackupDevices') {
            Write-Message -Level Verbose -Message "Migrating Backup Devices"
            Copy-DbaBackupDevice -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'SystemTriggers') {
            Write-Message -Level Verbose -Message "Migrating System Triggers"
            Copy-DbaInstanceTrigger -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Databases') {
            # Do it
            Write-Message -Level Verbose -Message "Migrating databases"
            if ($BackupRestore) {
                if ($UseLastBackup) {
                    Copy-DbaDatabase -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -AllDatabases -SetSourceReadOnly:$SetSourceReadOnly -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -BackupRestore -Force:$Force -NoRecovery:$NoRecovery -WithReplace:$WithReplace -IncludeSupportDbs:$IncludeSupportDbs -UseLastBackup:$UseLastBackup -Continue:$Continue -KeepCDC:$KeepCDC -KeepReplication:$KeepReplication
                } else {
                    Copy-DbaDatabase -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -AllDatabases -SetSourceReadOnly:$SetSourceReadOnly -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -BackupRestore -SharedPath $SharedPath -Force:$Force -NoRecovery:$NoRecovery -WithReplace:$WithReplace -IncludeSupportDbs:$IncludeSupportDbs -AzureCredential $AzureCredential -KeepCDC:$KeepCDC -KeepReplication:$KeepReplication
                }
            } else {
                Copy-DbaDatabase -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -AllDatabases -SetSourceReadOnly:$SetSourceReadOnly -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -DetachAttach:$DetachAttach -Reattach:$Reattach -Force:$Force -IncludeSupportDbs:$IncludeSupportDbs -KeepCDC:$KeepCDC -KeepReplication:$KeepReplication
            }
        }

        if ($Exclude -notcontains 'Logins') {
            Write-Message -Level Verbose -Message "Migrating logins"
            $syncit = $ExcludeSaRename -eq $false
            Copy-DbaLogin -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force -SyncSaName:$syncit
        }

        if ($Exclude -notcontains 'Logins' -and $Exclude -notcontains 'Databases' -and -not $NoRecovery) {
            Write-Message -Level Verbose -Message "Updating database owners to match newly migrated logins"
            foreach ($dest in $Destination) {
                $null = Update-SqlDbOwner -Source $sourceserver -Destination $dest -DestinationSqlCredential $DestinationSqlCredential
            }
        }

        if ($Exclude -notcontains 'LinkedServers') {
            Write-Message -Level Verbose -Message "Migrating linked servers"
            Copy-DbaLinkedServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'DataCollector') {
            Write-Message -Level Verbose -Message "Migrating Data Collector collection sets"
            Copy-DbaDataCollector -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Audits') {
            Write-Message -Level Verbose -Message "Migrating Audits"
            Copy-DbaInstanceAudit -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'ServerAuditSpecifications') {
            Write-Message -Level Verbose -Message "Migrating Server Audit Specifications"
            Copy-DbaInstanceAuditSpecification -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'Endpoints') {
            Write-Message -Level Verbose -Message "Migrating Endpoints"
            Copy-DbaEndpoint -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'PolicyManagement') {
            Write-Message -Level Verbose -Message "Migrating Policy Management"
            Copy-DbaPolicyManagement -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'ResourceGovernor') {
            Write-Message -Level Verbose -Message "Migrating Resource Governor"
            Copy-DbaResourceGovernor -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'SysDbUserObjects') {
            Write-Message -Level Verbose -Message "Migrating user objects in system databases (this can take a second)."
            If ($Pscmdlet.ShouldProcess($destination, "Copying user objects.")) {
                Copy-DbaSysDbUserObject -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$force
            }
        }

        if ($Exclude -notcontains 'ExtendedEvents') {
            Write-Message -Level Verbose -Message "Migrating Extended Events"
            Copy-DbaXESession -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -Force:$Force
        }

        if ($Exclude -notcontains 'AgentServer') {
            Write-Message -Level Verbose -Message "Migrating job server"
            $ExcludeAgentServerProperties = $Exclude -contains 'AgentServerProperties'
            Copy-DbaAgentServer -Source $sourceserver -Destination $Destination -DestinationSqlCredential $DestinationSqlCredential -DisableJobsOnDestination:$DisableJobsOnDestination -DisableJobsOnSource:$DisableJobsOnSource -Force:$Force -ExcludeServerProperties:$ExcludeAgentServerProperties
        }

        if ($Exclude -notcontains 'StartupProcedures') {
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