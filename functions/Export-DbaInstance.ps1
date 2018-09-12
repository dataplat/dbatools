function Export-DbaInstance {
    <#
        .SYNOPSIS
            Exports SQL Server *ALL* databases, logins, database mail profiles/accounts, credentials, SQL Agent objects, linked servers,
            Central Management Server objects, server configuration settings (sp_configure), user objects in systems databases,
            system triggers and backup devices from one SQL Server to another.

            For more granular control, please use one of the -Exclude parameters and use the other functions available within the dbatools module.

        .DESCRIPTION
            Export-DbaInstance consolidates most of the export scripts in dbatools into one command.  This is useful when you're looking to Export entire instances. It less flexible than using the underlying functions. Think of it as an easy button. It Exports:

            All user databases to exclude support databases such as ReportServerTempDB (Use -IncludeSupportDbs for this). Use -ExcludeDatabases to skip.
            All logins. Use -ExcludeLogins to skip.
            All database mail objects. Use -ExcludeDatabaseMail
            All credentials. Use -ExcludeCredentials to skip.
            All objects within the Job Server (SQL Agent). Use -ExcludeAgentServer to skip.
            All linked servers. Use -ExcludeLinkedServers to skip.
            All groups and servers within Central Management Server. Use -ExcludeCentralManagementServer to skip.
            All SQL Server configuration objects (everything in sp_configure). Use -ExcludeSpConfigure to skip.
            All user objects in system databases. Use -ExcludeSysDbUserObjects to skip.
            All system triggers. Use -ExcludeSystemTriggers to skip.
            All system backup devices. Use -ExcludeBackupDevices to skip.
            All Audits. Use -ExcludeAudits to skip.
            All Endpoints. Use -ExcludeEndpoints to skip.
            All Extended Events. Use -ExcludeExtendedEvents to skip.
            All Policy Management objects. Use -ExcludePolicyManagement to skip.
            All Resource Governor objects. Use -ExcludeResourceGovernor to skip.
            All Server Audit Specifications. Use -ExcludeServerAuditSpecifications to skip.
            All Custom Errors (User Defined Messages). Use -ExcludeCustomErrors to skip.
            All Server Roles. Use -ExcludeServerRoles to skip.
            All Availability Groups. Use -ExcludeAvailabilityGroups to skip.

        .PARAMETER SqlInstance
            The target SQL Server instances

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Credential
            Alternative Windows credentials for exporting Linked Servers and Credentials. Accepts credential objects (Get-Credential)

        .PARAMETER Path
            The path to the export file

        .PARAMETER NetworkShare
            Specifies the network location for the backup files. The SQL Server service accounts on both Source and Destination must have read/write permission to access this location.

        .PARAMETER WithReplace
            If this switch is used, databases are restored from backup using WITH REPLACE. This is useful if you want to stage some complex file paths.

        .PARAMETER NoRecovery
            If this switch is used, databases will be left in the No Recovery state to enable further backups to be added.

        .PARAMETER IncludeDbMasterKey
            Exports the db master key then logs into the server to copy it to the $Path
    
        .PARAMETER ExcludeDatabases
            If this switch is used, databases will not be exported.

        .PARAMETER ExcludeLogins
            If this switch is used, Logins will not be exported.

        .PARAMETER ExcludeAgentServer
            If this switch is used, SQL Agent jobs will not be exported.

        .PARAMETER ExcludeCredentials
            If this switch is used, Credentials will not be exported.

        .PARAMETER ExcludeLinkedServers
            If this switch is used, Linked Servers will not be exported.

        .PARAMETER ExcludeSpConfigure
            If this switch is used, options configured via sp_configure will not be exported.

        .PARAMETER ExcludeCentralManagementServer
            If this switch is used, Central Management Server will not be exported.

        .PARAMETER ExcludeDatabaseMail
            If this switch is used, Database Mail will not be exported.

        .PARAMETER ExcludeSysDbUserObjects
            If this switch is used, user objects found in the master, msdb and model databases will not be exported.

        .PARAMETER ExcludeSystemTriggers
            If this switch is used, System Triggers will not be exported.

        .PARAMETER ExcludeBackupDevices
            If this switch is used, Backup Devices will not be exported.

        .PARAMETER ExcludeAudits
            If this switch is used, Audits will not be exported.

        .PARAMETER ExcludeEndpoints
            If this switch is used, Endpoints will not be exported.

        .PARAMETER ExcludeExtendedEvents
            If this switch is used, Extended Events will not be exported.

        .PARAMETER ExcludePolicyManagement
            If this switch is used, Policy-Based Management will not be exported.

        .PARAMETER ExcludeResourceGovernor
            If this switch is used, Resource Governor will not be exported.

        .PARAMETER ExcludeServerAuditSpecifications
            If this switch is used, the Server Audit Specification will not be exported.

        .PARAMETER ExcludeCustomErrors
            If this switch is used, Custom Errors (User Defined Messages) will not be exported.

        .PARAMETER ExcludeServerRoles
            If this switch is used, Server Roles will not be exported.
            
        .PARAMETER IncludeSupportDbs
            If this switch is used, the ReportServer, ReportServerTempDb, SSIDb, and distribution databases will be migrated if they exist. A logfile named $SOURCE-$DESTINATION-$date-Sqls.csv will be written to the current directory. Requires -BackupRestore or -DetachAttach.
        
        .PARAMETER ExcludeAvailabilityGroups
            If this switch is used, Availability Groups will not be exported.
    
        .PARAMETER BatchSeparator
            Batch separator for scripting output. "GO" by default.
    
        .PARAMETER ScriptingOption
            Add scripting options to scripting output for all objects except Registered Servers and Extended Events.
    
        .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Export
            Author: Chrissy LeMaire (@cl), netnerds.net
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
            Export-DbaInstance -SqlInstance sqlserver\instance -Destination sqlcluster

            All databases, logins, job objects and sp_configure options will be exported from sqlserver\instance to to disk.

        .EXAMPLE
            Export-DbaInstance -SqlInstance sqlcluster -ExcludeDatabases -ExcludeLogins -Verbose

            Exports everything but logins and databases.
    
        .EXAMPLE
            Export-DbaInstance -Verbose -SqlInstance sqlcluster -ExcludeDatabases -ExcludeLogins

            Exports everything but logins and databases.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string]$Path,
        [switch]$NoRecovery,
        [switch]$IncludeDbMasterKey,
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
        [switch]$ExcludeServerRoles,
        [switch]$ExcludeAvailabilityGroups,
        [string]$BatchSeparator = 'GO',
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOption,
        [switch]$EnableException
    )
    begin {
        if ((Test-Bound -ParameterName Path)) {
            if (-not ((Get-Item $Path -ErrorAction Ignore) -is [System.IO.DirectoryInfo])) {
                Stop-Function -Message "Path must be a directory"
            }
        }
        
        if (-not $ScriptingOption) {
            $ScriptingOption = New-DbaScriptingOption
        }
        
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $started = Get-Date
        function Write-ProgressHelper {
            # thanks adam!
            # https://www.adamtheautomator.com/building-progress-bar-powershell-scripts/
            param (
                [int]$StepNumber,
                [string]$Message,
                [int]$TotalSteps = 20

            )
            Write-Progress -Activity "Performing Instance Export for $instance" -Status $Message -PercentComplete (($StepNumber / $TotalSteps) * 100)
        }
        
        $ScriptingOptions = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
        $ScriptingOptions.ScriptBatchTerminator = $true
        
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (-not (Test-Bound -ParameterName Path)) {
                $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
                $mydocs = [Environment]::GetFolderPath('MyDocuments')
                $path = "$mydocs\$($server.name.replace('\', '$'))-$timenow"
            }

            if (-not (Test-Path $Path)) {
                try {
                    $null = New-Item -ItemType Directory -Path $Path -ErrorAction Stop
                }
                catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                    return
                }
            }

            if (-not $ExcludeSpConfigure) {
                Write-Message -Level Verbose -Message "Exporting SQL Server Configuration"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting SQL Server Configuration"
                Export-DbaSpConfigure -SqlInstance $server -Path "$Path\$stepCounter-sp_configure.sql"
            }

            if (-not $ExcludeCustomErrors) {
                Write-Message -Level Verbose -Message "Exporting custom errors (user defined messages)"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting custom errors (user defined messages)"
                $null = Get-DbaCustomError -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-customererrors.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-customererrors.sql"
            }
            
            if (-not $ExcludeServerRoles) {
                Write-Message -Level Verbose -Message "Exporting server roles"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting server roles"
                $null = Get-DbaServerRole -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-serverroles.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-serverroles.sql"
            }
            
            if (-not $ExcludeCredentials) {
                Write-Message -Level Verbose -Message "Exporting SQL credentials"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting SQL credentials"
                $null = Export-DbaCredential -SqlInstance $server -Credential $Credential -Path "$Path\$stepCounter-credentials.sql" -Append
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-credentials.sql"
            }

            if (-not $ExcludeDatabaseMail) {
                Write-Message -Level Verbose -Message "Exporting database mail"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database mail"
                $null = Get-DbaDbMailConfig -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-dbmail.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $null = Get-DbaDbMailAccount -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-dbmail.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $null = Get-DbaDbMailProfile -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-dbmail.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $null = Get-DbaDbMailServer -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-dbmail.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $null = Get-DbaDbMail -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-dbmail.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-dbmail.sql"
            }

            if (-not $ExcludeCentralManagementServer) {
                Write-Message -Level Verbose -Message "Exporting Central Management Server"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Central Management Server"
                $null = Get-DbaRegisteredServerGroup -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-regserver.sql" -Append -BatchSeparator 'GO'
                $null = Get-DbaRegisteredServer -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-regserver.sql" -Append -BatchSeparator 'GO'
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-regserver.sql"
            }

            if (-not $ExcludeBackupDevices) {
                Write-Message -Level Verbose -Message "Exporting Backup Devices"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Backup Devices"
                $null = Get-DbaBackupDevice -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-backupdevices.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-backupdevices.sql"
            }

            if (-not $ExcludeLinkedServers) {
                Write-Message -Level Verbose -Message "Exporting linked servers"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting linked servers"
                Export-DbaLinkedServer -SqlInstance $server -Path "$Path\$stepCounter-linkedservers.sql" -Credential $Credential -Append
            }

            if (-not $ExcludeSystemTriggers) {
                Write-Message -Level Verbose -Message "Exporting System Triggers"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting System Triggers"
                $null = Get-DbaServerTrigger -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-servertriggers.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $triggers = Get-Content -Path "$Path\$stepCounter-servertriggers.sql" -Raw -ErrorAction Ignore
                if ($triggers) {
                    $triggers = $triggers.ToString() -replace 'CREATE TRIGGER', "GO`r`nCREATE TRIGGER"
                    $triggers = $triggers.ToString() -replace 'ENABLE TRIGGER', "GO`r`nENABLE TRIGGER"
                    $null = $triggers | Set-Content -Path "$Path\$stepCounter-servertriggers.sql" -Force
                    Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-servertriggers.sql"
                }
            }
            
            if (-not $ExcludeDatabases) {
                Write-Message -Level Verbose -Message "Exporting database restores"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database restores"
                Get-DbaBackupHistory -SqlInstance $server -Last | Restore-DbaDatabase -SqlInstance $server -NoRecovery:$NoRecovery -WithReplace -OutputScriptOnly -WarningAction SilentlyContinue | Out-File -FilePath "$Path\$stepCounter-databases.sql" -Append
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-databases.sql"
            }

            if (-not $ExcludeLogins) {
                Write-Message -Level Verbose -Message "Exporting logins"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting logins"
                Export-DbaLogin -SqlInstance $server -Path "$Path\$stepCounter-logins.sql" -Append -WarningAction SilentlyContinue
            }

            if (-not $ExcludeAudits) {
                Write-Message -Level Verbose -Message "Exporting Audits"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Audits"
                $null = Get-DbaServerAudit -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-audits.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-audits.sql"
            }

            if (-not $ExcludeServerAuditSpecifications) {
                Write-Message -Level Verbose -Message "Exporting Server Audit Specifications"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Server Audit Specifications"
                $null = Get-DbaServerAuditSpecification -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-auditspecs.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-auditspecs.sql"
            }

            if (-not $ExcludeEndpoints) {
                Write-Message -Level Verbose -Message "Exporting Endpoints"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Endpoints"
                $null = Get-DbaEndpoint -SqlInstance $server | Where-Object IsSystemObject -eq $false | Export-DbaScript -Path "$Path\$stepCounter-endpoints.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-endpoints.sql"
            }

            if (-not $ExcludePolicyManagement) {
                Write-Message -Level Verbose -Message "Exporting Policy Management"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Policy Management"
                $null = Get-DbaPbmCondition -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-policymanagement.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $null = Get-DbaPbmPolicy -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-policymanagement.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-policymanagement.sql"
            }

            if (-not $ExcludeResourceGovernor) {
                Write-Message -Level Verbose -Message "Exporting Resource Governor"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Resource Governor"
                $null = Get-DbaResourceGovernor -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-resourcegov.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $null = Get-DbaRgClassifierFunction -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-resourcegov.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $null = Get-DbaRgResourcePool -SqlInstance $server | Where-Object Name -notin 'default', 'internal' | Export-DbaScript -Path "$Path\$stepCounter-resourcegov.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $null = Get-DbaRgWorkloadGroup -SqlInstance $server | Where-Object Name -notin 'default','internal' | Export-DbaScript -Path "$Path\$stepCounter-resourcegov.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-resourcegov.sql"
            }
            if (-not $ExcludeSysDbUserObjects) {
                Write-Message -Level Verbose -Message "Exporting user objects in system databases (this can take a second)."
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting user objects in system databases (this can take a second)."
                $null = Get-DbaSysDbUserObjectScript -SqlInstance $server | Out-File -FilePath "$Path\$stepCounter-userobjectsinsysdbs.sql" -Append
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-userobjectsinsysdbs.sql"
            }

            if (-not $ExcludeExtendedEvents) {
                Write-Message -Level Verbose -Message "Exporting Extended Events"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Extended Events"
                $null = Get-DbaXESession -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-extendedevents.sql" -Append -BatchSeparator 'GO'
               Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-extendedevents.sql"
            }

            if (-not $ExcludeAgentServer) {
                Write-Message -Level Verbose -Message "Exporting job server"
                
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting job server"
                $null = Get-DbaAgentJobCategory -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-sqlagent.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $null = Get-DbaAgentOperator -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-sqlagent.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $null = Get-DbaAgentAlert -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-sqlagent.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $null = Get-DbaAgentProxy -SqlInstance $server | Export-DbaScript  -Path "$Path\$stepCounter-sqlagent.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $null = Get-DbaAgentSchedule -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-sqlagent.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                $null = Get-DbaAgentJob -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-sqlagent.sql" -Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-sqlagent.sql"
            }
            
            if (-not $ExcludeAvailabilityGroups) {
                Write-Message -Level Verbose -Message "Exporting availability group"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting availability groups"
                $null = Get-DbaAvailabilityGroup -SqlInstance $server | Export-DbaScript -Path "$Path\$stepCounter-availabilitygroups.sql" -Append -BatchSeparator $BatchSeparator #-ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$stepCounter-availabilitygroups.sql"
            }
            
            Write-Progress -Activity "Performing Instance Export for $instance" -Completed
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