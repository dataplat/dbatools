function Export-DbaInstance {
    <#
    .SYNOPSIS
        Exports SQL Server *ALL* database restore scripts, logins, database mail profiles/accounts, credentials, SQL Agent objects, linked servers,
        Central Management Server objects, server configuration settings (sp_configure), user objects in systems databases,
        system triggers and backup devices from one SQL Server to another.

        For more granular control, please use one of the -Exclude parameters and use the other functions available within the dbatools module.

    .DESCRIPTION
        Export-DbaInstance consolidates most of the export scripts in dbatools into one command.

        This is useful when you're looking to Export entire instances. It less flexible than using the underlying functions.
        Think of it as an easy button. Unless an -Exclude is specified, it exports:

        All database restore scripts.
        All logins.
        All database mail objects.
        All credentials.
        All objects within the Job Server (SQL Agent).
        All linked servers.
        All groups and servers within Central Management Server.
        All SQL Server configuration objects (everything in sp_configure).
        All user objects in system databases.
        All system triggers.
        All system backup devices.
        All Audits.
        All Endpoints.
        All Extended Events.
        All Policy Management objects.
        All Resource Governor objects.
        All Server Audit Specifications.
        All Custom Errors (User Defined Messages).
        All Server Roles.
        All Availability Groups.

    .PARAMETER SqlInstance
        The target SQL Server instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Credential
        Alternative Windows credentials for exporting Linked Servers and Credentials. Accepts credential objects (Get-Credential)

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER FilePath
        Specifies the full file path of the output file.

    .PARAMETER WithReplace
        If this switch is used, databases are restored from backup using WITH REPLACE. This is useful if you want to stage some complex file paths.

    .PARAMETER NoRecovery
        If this switch is used, databases will be left in the No Recovery state to enable further backups to be added.

    .PARAMETER IncludeDbMasterKey
        Exports the db master key then logs into the server to copy it to the $Path

    .PARAMETER Exclude
        Exclude one or more objects to export

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
        ServerRoles
        AvailabilityGroups
        ReplicationSettings

    .PARAMETER BatchSeparator
        Batch separator for scripting output. "GO" by default.

    .PARAMETER NoPrefix
        If this switch is used, the scripts will not include prefix information containing creator and datetime.

    .PARAMETER ExcludePassword
        If this switch is used, the scripts will not include passwords for Credentials, LinkedServers or Logins.

    .PARAMETER ScriptingOption
        Add scripting options to scripting output for all objects except Registered Servers and Extended Events.

    .PARAMETER Append
        Append to the target file instead of overwriting.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Export
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaInstance

    .EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlserver\instance

        All databases, logins, job objects and sp_configure options will be exported from
        sqlserver\instance to an automatically generated folder name in Documents.

    .EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlcluster -Exclude Databases, Logins -Path C:\dr\sqlcluster

        Exports everything but logins and database restore scripts to C:\dr\sqlcluster

.EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlcluster -Path C:\servers\ -NoPrefix

        Exports everything to C:\servers but scripts do not include prefix information.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [switch]$NoRecovery,
        [switch]$IncludeDbMasterKey,
        [ValidateSet('Databases', 'Logins', 'AgentServer', 'Credentials', 'LinkedServers', 'SpConfigure', 'CentralManagementServer', 'DatabaseMail', 'SysDbUserObjects', 'SystemTriggers', 'BackupDevices', 'Audits', 'Endpoints', 'ExtendedEvents', 'PolicyManagement', 'ResourceGovernor', 'ServerAuditSpecifications', 'CustomErrors', 'ServerRoles', 'AvailabilityGroups', 'ReplicationSettings')]
        [string[]]$Exclude,
        [string]$BatchSeparator = 'GO',
        [switch]$Append,
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOption,
        [switch]$NoPrefix = $false,
        [switch]$ExcludePassword,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path

        if (-not $ScriptingOption) {
            $ScriptingOption = New-DbaScriptingOption
        }

        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $started = Get-Date

        $ScriptingOptions = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
        $ScriptingOptions.ScriptBatchTerminator = $true

    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            $stepCounter = $filecounter = 0
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
            $path = Join-DbaPath -Path $Path -Child "$($server.name.replace('\', '$'))-$timenow"

            if (-not (Test-Path $Path)) {
                try {
                    $null = New-Item -ItemType Directory -Path $Path -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                    return
                }
            }

            if ($Exclude -notcontains 'SpConfigure') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting SQL Server Configuration"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting SQL Server Configuration"
                Export-DbaSpConfigure -SqlInstance $server -FilePath "$Path\$fileCounter-sp_configure.sql"
                if (-not (Test-Path "$Path\$fileCounter-sp_configure.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'CustomErrors') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting custom errors (user defined messages)"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting custom errors (user defined messages)"
                $null = Get-DbaCustomError -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-customererrors.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-customererrors.sql"
                if (-not (Test-Path "$Path\$fileCounter-customererrors.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'ServerRoles') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting server roles"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting server roles"
                $null = Get-DbaServerRole -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-serverroles.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-serverroles.sql"
                if (-not (Test-Path "$Path\$fileCounter-serverroles.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'Credentials') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting SQL credentials"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting SQL credentials"
                $null = Export-DbaCredential -SqlInstance $server -Credential $Credential -FilePath "$Path\$fileCounter-credentials.sql" -Append:$Append -ExcludePassword:$ExcludePassword
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-credentials.sql"
                if (-not (Test-Path "$Path\$fileCounter-credentials.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'DatabaseMail') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting database mail"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database mail"
                $null = Get-DbaDbMailConfig -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-dbmail.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaDbMailAccount -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-dbmail.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaDbMailProfile -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-dbmail.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaDbMailServer -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-dbmail.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaDbMail -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-dbmail.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-dbmail.sql"
                if (-not (Test-Path "$Path\$fileCounter-dbmail.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'CentralManagementServer') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting Central Management Server"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Central Management Server"
                $null = Get-DbaRegServerGroup -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-regserver.sql" -Append:$Append -BatchSeparator 'GO' -NoPrefix:$NoPrefix
                $null = Get-DbaRegServer -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-regserver.sql" -Append:$Append -BatchSeparator 'GO' -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-regserver.sql"
                if (-not (Test-Path "$Path\$fileCounter-regserver.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'BackupDevices') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting Backup Devices"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Backup Devices"
                $null = Get-DbaBackupDevice -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-backupdevices.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-backupdevices.sql"
                if (-not (Test-Path "$Path\$fileCounter-backupdevices.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'LinkedServers') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting linked servers"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting linked servers"
                Export-DbaLinkedServer -SqlInstance $server -FilePath "$Path\$fileCounter-linkedservers.sql" -Credential $Credential -Append:$Append -ExcludePassword:$ExcludePassword
                if (-not (Test-Path "$Path\$fileCounter-linkedservers.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'SystemTriggers') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting System Triggers"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting System Triggers"
                $null = Get-DbaInstanceTrigger -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-servertriggers.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $triggers = Get-Content -Path "$Path\$fileCounter-servertriggers.sql" -Raw -ErrorAction Ignore
                if ($triggers) {
                    $triggers = $triggers.ToString() -replace 'CREATE TRIGGER', "GO`r`nCREATE TRIGGER"
                    $triggers = $triggers.ToString() -replace 'ENABLE TRIGGER', "GO`r`nENABLE TRIGGER"
                    $null = $triggers | Set-Content -Path "$Path\$fileCounter-servertriggers.sql" -Force
                    Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-servertriggers.sql"
                }
                if (-not (Test-Path "$Path\$fileCounter-servertriggers.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'Databases') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting database restores"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database restores"
                Get-DbaDbBackupHistory -SqlInstance $server -Last | Restore-DbaDatabase -SqlInstance $server -NoRecovery:$NoRecovery -WithReplace -OutputScriptOnly -WarningAction SilentlyContinue | Out-File -FilePath "$Path\$fileCounter-databases.sql" -Append:$Append
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-databases.sql"
                if (-not (Test-Path "$Path\$fileCounter-databases.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'Logins') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting logins"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting logins"
                Export-DbaLogin -SqlInstance $server -FilePath "$Path\$fileCounter-logins.sql" -Append:$Append -ExcludePassword:$ExcludePassword -NoPrefix:$NoPrefix -WarningAction SilentlyContinue
                if (-not (Test-Path "$Path\$fileCounter-logins.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'Audits') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting Audits"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Audits"
                $null = Get-DbaInstanceAudit -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-audits.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-audits.sql"
                if (-not (Test-Path "$Path\$fileCounter-audits.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'ServerAuditSpecifications') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting Server Audit Specifications"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Server Audit Specifications"
                $null = Get-DbaInstanceAuditSpecification -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-auditspecs.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-auditspecs.sql"
                if (-not (Test-Path "$Path\$fileCounter-auditspecs.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'Endpoints') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting Endpoints"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Endpoints"
                $null = Get-DbaEndpoint -SqlInstance $server | Where-Object IsSystemObject -eq $false | Export-DbaScript -FilePath "$Path\$fileCounter-endpoints.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-endpoints.sql"
                if (-not (Test-Path "$Path\$fileCounter-endpoints.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'PolicyManagement') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting Policy Management"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Policy Management"
                $null = Get-DbaPbmCondition -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-policymanagement.sql" -Append:$Append -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix
                $null = Get-DbaPbmObjectSet -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-policymanagement.sql" -Append:$Append -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix
                $null = Get-DbaPbmPolicy -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-policymanagement.sql" -Append:$Append -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-policymanagement.sql"
                if (-not (Test-Path "$Path\$fileCounter-policymanagement.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'ResourceGovernor') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting Resource Governor"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Resource Governor"
                $null = Get-DbaResourceGovernor -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-resourcegov.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaRgClassifierFunction -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-resourcegov.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaRgResourcePool -SqlInstance $server | Where-Object Name -notin 'default', 'internal' | Export-DbaScript -FilePath "$Path\$fileCounter-resourcegov.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaRgWorkloadGroup -SqlInstance $server | Where-Object Name -notin 'default', 'internal' | Export-DbaScript -FilePath "$Path\$fileCounter-resourcegov.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Add-Content -Value "ALTER RESOURCE GOVERNOR RECONFIGURE" -Path "$Path\$fileCounter-resourcegov.sql"
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-resourcegov.sql"
                if (-not (Test-Path "$Path\$fileCounter-resourcegov.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'ExtendedEvents') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting Extended Events"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Extended Events"
                $null = Get-DbaXESession -SqlInstance $server | Export-DbaXeSession -FilePath "$Path\$fileCounter-extendedevents.sql" -Append:$Append -BatchSeparator 'GO' -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-extendedevents.sql"
                if (-not (Test-Path "$Path\$fileCounter-extendedevents.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'AgentServer') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting job server"

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting job server"
                $null = Get-DbaAgentJobCategory -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-sqlagent.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentOperator -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-sqlagent.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentAlert -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-sqlagent.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentProxy -SqlInstance $server | Export-DbaScript  -FilePath "$Path\$fileCounter-sqlagent.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentSchedule -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-sqlagent.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentJob -SqlInstance $server | Export-DbaScript -FilePath "$Path\$fileCounter-sqlagent.sql" -Append:$Append -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-sqlagent.sql"
                if (-not (Test-Path "$Path\$fileCounter-sqlagent.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'ReplicationSettings') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting replication settings"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting replication settings"
                $null = Export-DbaRepServerSetting -SqlInstance $instance -SqlCredential $SqlCredential -FilePath "$Path\$fileCounter-replication.sql"
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-replication.sql"
                if (-not (Test-Path "$Path\$fileCounter-replication.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'SysDbUserObjects') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting user objects in system databases (this can take a minute)."
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting user objects in system databases (this can take a minute)."
                $null = Get-DbaSysDbUserObjectScript -SqlInstance $server | Out-File -FilePath "$Path\$fileCounter-userobjectsinsysdbs.sql" -Append:$Append
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-userobjectsinsysdbs.sql"
                if (-not (Test-Path "$Path\$fileCounter-userobjectsinsysdbs.sql")) {
                    $fileCounter--
                }
            }

            if ($Exclude -notcontains 'AvailabilityGroups') {
                $fileCounter++
                Write-Message -Level Verbose -Message "Exporting availability group"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting availability groups"
                $null = Get-DbaAvailabilityGroup -SqlInstance $server -WarningAction SilentlyContinue | Export-DbaScript -FilePath "$Path\$fileCounter-DbaAvailabilityGroups.sql" -Append:$Append -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix #-ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$Path\$fileCounter-DbaAvailabilityGroups.sql"
                if (-not (Test-Path "$Path\$fileCounter-DbaAvailabilityGroups.sql")) {
                    $fileCounter--
                }
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