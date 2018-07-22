function Export-DbaInstance {
    <#
        .SYNOPSIS
            Exports SQL Server *ALL* databases, logins, database mail profiles/accounts, credentials, SQL Agent objects, linked servers,
            Central Management Server objects, server configuration settings (sp_configure), user objects in systems databases,
            system triggers and backup devices from one SQL Server to another.

            For more granular control, please use one of the -Exclude parameters and use the other functions available within the dbatools module.

        .DESCRIPTION
            Export-DbaInstance consolidates most of the export scripts in dbatools into one command.  This is useful when you're looking to Export entire instances. It less flexible than using the underlying functions. Think of it as an easy button. It Exports:

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
            
        .PARAMETER SqlInstance
            The target SQL Server instances

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER NetworkShare
            Specifies the network location for the backup files. The SQL Server service accounts on both Source and Destination must have read/write permission to access this location.

        .PARAMETER WithReplace
            If this switch is enabled, databases are restored from backup using WITH REPLACE. This is useful if you want to stage some complex file paths.

        .PARAMETER NoRecovery
            If this switch is enabled, databases will be left in the No Recovery state to enable further backups to be added.

        .PARAMETER ExcludeDatabases
            If this switch is enabled, databases will not be exported.

        .PARAMETER ExcludeLogins
            If this switch is enabled, Logins will not be exported.

        .PARAMETER ExcludeAgentServer
            If this switch is enabled, SQL Agent jobs will not be exported.

        .PARAMETER ExcludeCredentials
            If this switch is enabled, Credentials will not be exported.

        .PARAMETER ExcludeLinkedServers
            If this switch is enabled, Linked Servers will not be exported.

        .PARAMETER ExcludeSpConfigure
            If this switch is enabled, options configured via sp_configure will not be exported.

        .PARAMETER ExcludeCentralManagementServer
            If this switch is enabled, Central Management Server will not be exported.

        .PARAMETER ExcludeDatabaseMail
            If this switch is enabled, Database Mail will not be exported.

        .PARAMETER ExcludeSysDbUserObjects
            If this switch is enabled, user objects found in the master, msdb and model databases will not be exported.

        .PARAMETER ExcludeSystemTriggers
            If this switch is enabled, System Triggers will not be exported.

        .PARAMETER ExcludeBackupDevices
            If this switch is enabled, Backup Devices will not be exported.

        .PARAMETER ExcludeAudits
            If this switch is enabled, Audits will not be exported.

        .PARAMETER ExcludeEndpoints
            If this switch is enabled, Endpoints will not be exported.

        .PARAMETER ExcludeExtendedEvents
            If this switch is enabled, Extended Events will not be exported.

        .PARAMETER ExcludePolicyManagement
            If this switch is enabled, Policy-Based Management will not be exported.

        .PARAMETER ExcludeResourceGovernor
            If this switch is enabled, Resource Governor will not be exported.

        .PARAMETER ExcludeServerAuditSpecifications
            If this switch is enabled, the Server Audit Specification will not be exported.

        .PARAMETER ExcludeCustomErrors
            If this switch is enabled, Custom Errors (User Defined Messages) will not be exported.

        .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Export
            Author: Chrissy LeMaire
            Limitations:     Doesn't cover what it doesn't cover (certificates, etc)
                            SQL Server 2000 login exports have some limitations (server perms aren't exported)
                            SQL Server 2000 databases cannot be directly exported to SQL Server 2012 and above.
                            Logins within SQL Server 2012 and above logins cannot be exported to SQL Server 2008 R2 and below.
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Export-DbaInstance

        .EXAMPLE
            Export-DbaInstance -Source sqlserver\instance -Destination sqlcluster -DetachAttach

            All databases, logins, job objects and sp_configure options will be exported from sqlserver\instance to sqlcluster. Databases will be exported using the detach/copy files/attach method. Dbowner will be updated. User passwords, SIDs, database roles and server roles will be exported along with the login.

        .EXAMPLE
            Export-DbaInstance -Verbose -Source sqlcluster -Destination sql2016 -SqlCredential $scred -ReuseSourceFolderStructure -DestinationSqlCredential $cred -Force -NetworkShare \\fileserver\share\sqlbackups\export -BackupRestore

            Export databases uses backup/restore. Also Export logins, database mail, credentials, SQL Agent, Central Management Server, SQL global configuration.

        .EXAMPLE
            Export-DbaInstance -Verbose -Source sqlcluster -Destination sql2016 -NoDatabases -NoLogins

            Exports everything but logins and databases.

        .EXAMPLE
            Export-DbaInstance -Verbose -Source sqlcluster -Destination sql2016 -DetachAttach -Reattach -SetSourceReadonly

            Export databases using detach/copy/attach. Reattach at source and set source databases read-only. Also Exports everything else.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Path,
        [switch]$WithReplace,
        [switch]$NoRecovery,
        [switch]$IncludeSupportDbs,
        [switch]$ExcludeDatabases,
        [switch]$ExcludeLogins,
        [switch]$ExcludeAgentServer,
        [switch]$ExcludeCredentials,
        [switch]$ExcludeLinkedServers,
        [switch]$ExcludeSpConfigure,
        [switch]$ExcludeCentralManagementServer,
        [switch]$ExcludeDatabaseMail,
        [switch]$ExcludeSysDbUserObjects,
        [switch]$ExcludeSystemTriggers,
        [switch]$ExcludeBackupDevices,
        [switch]$ExcludeAudits,
        [switch]$ExcludeEndpoints,
        [switch]$ExcludeExtendedEvents,
        [switch]$ExcludePolicyManagement,
        [switch]$ExcludeResourceGovernor,
        [switch]$ExcludeServerAuditSpecifications,
        [switch]$ExcludeCustomErrors,
        [switch]$EnableException
    )
    begin {
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $started = Get-Date
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
            if (-not (Test-Bound -ParameterName Path)) {
                $Path = $instance.Replace('\', '$')
                $Path = "$Path.sql"
            }
            
            if (-not $ExcludeSpConfigure) {
                Write-Message -Level Verbose -Message "Exporting SQL Server Configuration"
                Export-DbaSpConfigure -SqlInstance $server -Path $Path
            }
            
            if (-not $ExcludeCustomErrors) {
                Write-Message -Level Verbose -Message "Exporting custom errors (user defined messages)"
                Get-DbaCustomError -SqlInstance $server | Export-DbaScript -Path $Path
            }
            
            if (-not $ExcludeCredentials) {
                Write-Message -Level Verbose -Message "Exporting SQL credentials"
                #Export-DbaCredential -SqlInstance $server
            }
            
            if (-not $ExcludeDatabaseMail) {
                Write-Message -Level Verbose -Message "Exporting database mail"
                #Get-DbaDatabaseMail -SqlInstance $server
            }
            
            if (-not $ExcludeCentralManagementServer) {
                Write-Message -Level Verbose -Message "Exporting Central Management Server"
                Export-DbaRegisteredServer -SqlInstance $server -Path $Path
            }
            
            if (-not $ExcludeBackupDevices) {
                Write-Message -Level Verbose -Message "Exporting Backup Devices"
                Get-DbaBackupDevice -SqlInstance $server | Export-DbaScript -Path $Path
            }
            
            if (-not $ExcludeLinkedServers) {
                Write-Message -Level Verbose -Message "Exporting linked servers"
                #Export-DbaLinkedServer -SqlInstance $server
            }
            
            if (-not $ExcludeSystemTriggers) {
                # Need to make Get-DbaTrigger an SMO object
                Write-Message -Level Verbose -Message "Exporting System Triggers"
                #Get-DbaTrigger -SqlInstance $server 
            }
            
            if (-not $ExcludeDatabases) {
                Write-Message -Level Verbose -Message "Exporting database restores"
                Restore-DbaDatabase -SqlInstance $server -NoRecovery:$NoRecovery -WithReplace:$WithReplace -OutputScriptOnly
            }
            
            if (-not $ExcludeLogins) {
                Write-Message -Level Verbose -Message "Exporting logins"
                Export-DbaLogin -SqlInstance $server -FilePath $Path
            }
            
            if (-not $ExcludeAudits) {
                Write-Message -Level Verbose -Message "Exporting Audits"
                Get-DbaServerAudit -SqlInstance $server | Export-DbaScript -Path $Path
            }
            
            if (-not $ExcludeServerAuditSpecifications) {
                Write-Message -Level Verbose -Message "Exporting Server Audit Specifications"
                Get-DbaServerAuditSpecification -SqlInstance $server | Export-DbaScript -Path $Path
            }
            
            if (-not $ExcludeEndpoints) {
                Write-Message -Level Verbose -Message "Exporting Endpoints"
                Get-DbaEndpoint -SqlInstance $server | Export-DbaScript -Path $Path
            }
            
            if (-not $ExcludePolicyManagement) {
                Write-Message -Level Verbose -Message "Exporting Policy Management"
                Get-DbaPolicy -SqlInstance $server | Export-DbaScript -Path $Path
            }
            
            if (-not $ExcludeResourceGovernor) {
                Write-Message -Level Verbose -Message "Exporting Resource Governor"
                #Get-DbaResourceGovernor -SqlInstance $server
            }
            
            if (-not $ExcludeSysDbUserObjects) {
                Write-Message -Level Verbose -Message "Exporting user objects in system databases (this can take a second)."
                #Get-DbaSysDbUserObject -SqlInstance $server
            }
            
            if (-not $ExcludeExtendedEvents) {
                Write-Message -Level Verbose -Message "Exporting Extended Events"
                Get-DbaXESession -SqlInstance $server | Export-DbaScript -Path $Path
            }
            
            if (-not $ExcludeAgentServer) {
                Write-Message -Level Verbose -Message "Exporting job server"
                
                Get-DbaAgentJobCategory -SqlInstance $instance
                Get-DbaAgentOperator -SqlInstance $instance
                Get-DbaAgentAlert -SqlInstance $instance -IncludeDefaults
                Get-DbaAgentProxy -SqlInstance $instance
                Get-DbaAgentSchedule -SqlInstance $instance
                Get-DbaAgentJob -SqlInstance $instance -DisableOnDestination:$DisableJobsOnDestination -DisableOnSource:$DisableJobsOnSource
            }
        }
    }
    end {
        $totaltime = ($elapsed.Elapsed.toString().Split(".")[0])
        Write-Message -Level Verbose -Message "SQL Server export complete."
        Write-Message -Level Verbose -Message "Export started: $started"
        Write-Message -Level Verbose -Message "Export completed: $(Get-Date)"
        Write-Message -Level Verbose -Message "Total Elapsed time: $totaltime"
    }
}