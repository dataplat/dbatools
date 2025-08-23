function Export-DbaInstance {
    <#
    .SYNOPSIS
        Exports complete SQL Server instance configuration as T-SQL scripts for migration or disaster recovery

    .DESCRIPTION
        Export-DbaInstance consolidates most of the export scripts in dbatools into one command that captures everything needed to recreate or migrate a SQL Server instance.

        This command saves hours of manual work when migrating instances to new servers, creating disaster recovery scripts, or documenting configurations for compliance. It generates individual T-SQL script files for each component type, organized in a timestamped folder structure that's perfect for version control or automated deployment pipelines.

        Unless an -Exclude is specified, it exports:

        All database 'restore from backup' scripts.  Note: if a database does not have a backup the 'restore from backup' script won't be generated.
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
        All OLEDB Providers.

        The exported files are written to a folder using the naming convention "machinename$instance-yyyyMMddHHmmss", making it easy to identify the source instance and export timestamp.

        This command is particularly valuable for:
        - Instance migrations when moving to new hardware or cloud platforms
        - Creating standardized development and test environments that match production
        - Disaster recovery planning by maintaining current configuration snapshots
        - Compliance documentation that automatically captures security settings and configurations
        - Change management workflows where you need baseline configurations before major updates

        Two folder management options are supported:
        1. Default behavior creates new timestamped folders for historical archiving
        2. Using -Force overwrites files in the same location, ideal for scheduled exports that feed into version control systems

        For more granular control, please use one of the -Exclude parameters and use the other functions available within the dbatools module.

    .PARAMETER SqlInstance
        The target SQL Server instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Alternative Windows credentials for exporting Linked Servers and Credentials. Accepts credential objects (Get-Credential)

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER WithReplace
        If this switch is used, databases are restored from backup using WITH REPLACE. This is useful if you want to stage some complex file paths.

    .PARAMETER NoRecovery
        If this switch is used, databases will be left in the No Recovery state to enable further backups to be added.

    .PARAMETER AzureCredential
        Optional AzureCredential to connect to blob storage holding the backups

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
        OleDbProvider

    .PARAMETER BatchSeparator
        Batch separator for scripting output. "GO" by default based on (Get-DbatoolsConfigValue -FullName 'formatting.batchseparator').

    .PARAMETER NoPrefix
        If this switch is used, the scripts will not include prefix information containing creator and datetime.

    .PARAMETER ExcludePassword
        If this switch is used, the scripts will not include passwords for Credentials, LinkedServers or Logins.

    .PARAMETER ScriptingOption
        Add scripting options to scripting output for all objects except Registered Servers and Extended Events.

    .PARAMETER Force
        Overwrite files in the location specified by -Path. Note: The Server Name is used when creating the folder structure.

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

        All databases, logins, job objects and sp_configure options will be exported from sqlserver\instance to an automatically generated folder name in Documents. For example, %userprofile%\Documents\DbatoolsExport\sqldev1$sqlcluster-20201108140000

    .EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlcluster -Exclude Databases, Logins -Path C:\dr\sqlcluster

        Exports everything but logins and database restore scripts to a folder such as C:\dr\sqlcluster\sqldev1$sqlcluster-20201108140000

    .EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlcluster -Path C:\servers\ -NoPrefix

        Exports everything to a folder such as C:\servers\sqldev1$sqlcluster-20201108140000 but scripts will not include prefix information.

    .EXAMPLE
        PS C:\> Export-DbaInstance -SqlInstance sqlcluster -Path C:\servers\ -Force

        Exports everything to a folder such as C:\servers\sqldev1$sqlcluster and will overwrite/refresh existing files in that folder. Note: when the -Force param is used the generated folder name will not include a timestamp. This supports the use case of running Export-DbaInstance on a schedule and writing to the same dir each time.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [Alias("FilePath")]
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [switch]$NoRecovery,
        [string]$AzureCredential,
        [switch]$IncludeDbMasterKey,
        [ValidateSet('AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider')]
        [string[]]$Exclude,
        [string]$BatchSeparator = (Get-DbatoolsConfigValue -FullName 'formatting.batchseparator'),
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOption,
        [switch]$NoPrefix = $false,
        [switch]$ExcludePassword,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path

        if (-not $ScriptingOption) {
            $ScriptingOption = New-DbaScriptingOption
        }

        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $started = Get-Date

        $eol = [System.Environment]::NewLine
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            $stepCounter = 0
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Force) {
                # when the caller requests to overwrite existing scripts we won't add the dynamic timestamp to the folder name, so that a pre-existing location can be overwritten.
                $exportPath = Join-DbaPath -Path $Path -Child "$($server.name.replace('\', '$'))"
            } else {
                $timeNow = (Get-Date -UFormat (Get-DbatoolsConfigValue -FullName 'formatting.uformat'))
                $exportPath = Join-DbaPath -Path $Path -Child "$($server.name.replace('\', '$'))-$timeNow"
            }

            # Ensure the export dir exists.
            if (-not (Test-Path $exportPath)) {
                try {
                    $null = New-Item -ItemType Directory -Path $exportPath -Force -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                    return
                }
            }

            if ($Exclude -notcontains 'SpConfigure') {
                Write-Message -Level Verbose -Message "Exporting SQL Server Configuration"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting SQL Server Configuration"
                Export-DbaSpConfigure -SqlInstance $server -FilePath "$exportPath\sp_configure.sql"
                # no call to Get-ChildItem because Export-DbaSpConfigure does it
            }

            if ($Exclude -notcontains 'CustomErrors') {
                Write-Message -Level Verbose -Message "Exporting custom errors (user defined messages)"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting custom errors (user defined messages)"
                $null = Get-DbaCustomError -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\customererrors.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\customererrors.sql"
            }

            if ($Exclude -notcontains 'ServerRoles') {
                Write-Message -Level Verbose -Message "Exporting server roles"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting server roles"
                $null = Get-DbaServerRole -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\serverroles.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\serverroles.sql"
            }

            if ($Exclude -notcontains 'Credentials') {
                Write-Message -Level Verbose -Message "Exporting SQL credentials"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting SQL credentials"
                $null = Export-DbaCredential -SqlInstance $server -Credential $Credential -FilePath "$exportPath\credentials.sql" -ExcludePassword:$ExcludePassword
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\credentials.sql"
            }

            if ($Exclude -notcontains 'Logins') {
                Write-Message -Level Verbose -Message "Exporting logins"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting logins"
                Export-DbaLogin -SqlInstance $server -FilePath "$exportPath\logins.sql" -ExcludePassword:$ExcludePassword -NoPrefix:$NoPrefix -WarningAction SilentlyContinue
                # no call to Get-ChildItem because Export-DbaLogin does it
            }

            if ($Exclude -notcontains 'DatabaseMail') {
                Write-Message -Level Verbose -Message "Exporting database mail"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database mail"
                # The first invocation to Export-DbaScript needs to have -Append:$false so that the previous file contents are discarded. Otherwise, the file would end up with duplicate SQL.
                # The subsequent calls to Export-DbaScript need to have -Append:$true because this is a multi-step export and the objects are written to the same file.
                $null = Get-DbaDbMailConfig -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$false -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaDbMailAccount -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaDbMailProfile -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaDbMailServer -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\dbmail.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix

                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\dbmail.sql"
            }

            if ($Exclude -notcontains 'CentralManagementServer') {
                Write-Message -Level Verbose -Message "Exporting Central Management Server"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Central Management Server"
                $outputFilePath = "$exportPath\regserver.xml"
                $null = Export-DbaRegServer -SqlInstance $server -FilePath $outputFilePath -Overwrite:$Force
                Get-ChildItem -ErrorAction Ignore -Path $outputFilePath
            }

            if ($Exclude -notcontains 'BackupDevices') {
                Write-Message -Level Verbose -Message "Exporting Backup Devices"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Backup Devices"
                $null = Get-DbaBackupDevice -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\backupdevices.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\backupdevices.sql"
            }

            if ($Exclude -notcontains 'LinkedServers') {
                Write-Message -Level Verbose -Message "Exporting linked servers"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting linked servers"
                Export-DbaLinkedServer -SqlInstance $server -FilePath "$exportPath\linkedservers.sql" -Credential $Credential -ExcludePassword:$ExcludePassword
                # no call to Get-ChildItem because Export-DbaLinkedServer does it
            }

            if ($Exclude -notcontains 'SystemTriggers') {
                Write-Message -Level Verbose -Message "Exporting System Triggers"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting System Triggers"
                $null = Get-DbaInstanceTrigger -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\servertriggers.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $triggers = Get-Content -Path "$exportPath\servertriggers.sql" -Raw -ErrorAction Ignore
                if ($triggers) {
                    $triggers = $triggers.ToString() -replace 'CREATE TRIGGER', "$BatchSeparator$($eol)CREATE TRIGGER"
                    $triggers = $triggers.ToString() -replace 'ENABLE TRIGGER', "$BatchSeparator$($eol)ENABLE TRIGGER"
                    $null = $triggers | Set-Content -Path "$exportPath\servertriggers.sql" -Force
                    Get-ChildItem -ErrorAction Ignore -Path "$exportPath\servertriggers.sql"
                }
            }

            if ($Exclude -notcontains 'Databases') {
                Write-Message -Level Verbose -Message "Exporting database restores"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting database restores"
                Get-DbaDbBackupHistory -SqlInstance $server -Last -WarningAction SilentlyContinue | Restore-DbaDatabase -SqlInstance $server -NoRecovery:$NoRecovery -WithReplace -OutputScriptOnly -WarningAction SilentlyContinue -AzureCredential $AzureCredential | Out-File -FilePath "$exportPath\databases.sql"
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\databases.sql"
            }

            if ($Exclude -notcontains 'Audits') {
                Write-Message -Level Verbose -Message "Exporting Audits"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Audits"
                $null = Get-DbaInstanceAudit -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\audits.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\audits.sql"
            }

            if ($Exclude -notcontains 'ServerAuditSpecifications') {
                Write-Message -Level Verbose -Message "Exporting Server Audit Specifications"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Server Audit Specifications"
                $null = Get-DbaInstanceAuditSpecification -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\auditspecs.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\auditspecs.sql"
            }

            if ($Exclude -notcontains 'Endpoints') {
                Write-Message -Level Verbose -Message "Exporting Endpoints"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Endpoints"
                $null = Get-DbaEndpoint -SqlInstance $server | Where-Object IsSystemObject -EQ $false | Export-DbaScript -FilePath "$exportPath\endpoints.sql" -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\endpoints.sql"
            }

            if ($Exclude -notcontains 'PolicyManagement' -and $PSVersionTable.PSEdition -eq "Core") {
                Write-Message -Level Verbose -Message "Skipping Policy Management -- not supported by PowerShell Core"
            }
            if ($Exclude -notcontains 'PolicyManagement' -and $PSVersionTable.PSEdition -ne "Core") {
                Write-Message -Level Verbose -Message "Exporting Policy Management"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Policy Management"

                $outputFilePath = "$exportPath\policymanagement.sql"
                $scriptText = ""
                $policyObjects = @()

                # the policy objects are a different set of classes and are not compatible with the SMO object usage in Export-DbaScript

                $policyObjects += Get-DbaPbmCondition -SqlInstance $server
                $policyObjects += Get-DbaPbmObjectSet -SqlInstance $server
                $policyObjects += Get-DbaPbmPolicy -SqlInstance $server

                foreach ($policyObject in $policyObjects) {
                    $tsqlScript = $policyObject.ScriptCreate()
                    $scriptText += $tsqlScript.GetScript() + "$eol$BatchSeparator$eol$eol"
                }

                Set-Content -Path $outputFilePath -Value $scriptText

                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\policymanagement.sql"
            }

            if ($Exclude -notcontains 'ResourceGovernor') {
                Write-Message -Level Verbose -Message "Exporting Resource Governor"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Resource Governor"
                # The first invocation to Export-DbaScript needs to have -Append:$false so that the previous file contents are discarded. Otherwise, the file would end up with duplicate SQL.
                # The subsequent calls to Export-DbaScript need to have -Append:$true because this is a multi-step export and the objects are written to the same file.
                $null = Get-DbaRgClassifierFunction -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$false -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaRgResourcePool -SqlInstance $server | Where-Object Name -NotIn 'default', 'internal' | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaRgWorkloadGroup -SqlInstance $server | Where-Object Name -NotIn 'default', 'internal' | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaResourceGovernor -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\resourcegov.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\resourcegov.sql"
            }

            if ($Exclude -notcontains 'ExtendedEvents') {
                Write-Message -Level Verbose -Message "Exporting Extended Events"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting Extended Events"
                $null = Get-DbaXESession -SqlInstance $server | Export-DbaXESession -FilePath "$exportPath\extendedevents.sql" -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\extendedevents.sql"
            }

            if ($Exclude -notcontains 'AgentServer') {
                Write-Message -Level Verbose -Message "Exporting job server"

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting job server"
                # The first invocation to Export-DbaScript needs to have -Append:$false so that the previous file contents are discarded. Otherwise, the file would end up with duplicate SQL.
                # The subsequent calls to Export-DbaScript need to have -Append:$true because this is a multi-step export and the objects are written to the same file.
                $null = Get-DbaAgentJobCategory -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$false -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentOperator -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentAlert -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentProxy -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentSchedule -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                $null = Get-DbaAgentJob -SqlInstance $server | Export-DbaScript -FilePath "$exportPath\sqlagent.sql" -Append:$true -BatchSeparator $BatchSeparator -ScriptingOptionsObject $ScriptingOption -NoPrefix:$NoPrefix
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\sqlagent.sql"
            }

            if ($Exclude -notcontains 'ReplicationSettings') {
                Write-Message -Level Verbose -Message "Exporting replication settings"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting replication settings"

                try {
                    $null = Export-DbaReplServerSetting -SqlInstance $instance -SqlCredential $SqlCredential -FilePath "$exportPath\replication.sql" -EnableException
                    Get-ChildItem -ErrorAction Ignore -Path "$exportPath\replication.sql"
                } catch {
                    Write-Message -Level Verbose -Message "Replication failed, skipping"
                }
            }

            if ($Exclude -notcontains 'SysDbUserObjects') {
                Write-Message -Level Verbose -Message "Exporting user objects in system databases (this can take a minute)."
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting user objects in system databases (this can take a minute)."
                $outputFile = "$exportPath\userobjectsinsysdbs.sql"
                $sysDbUserObjects = Export-DbaSysDbUserObject -SqlInstance $server -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix -ScriptingOptionsObject $ScriptingOption -PassThru
                Set-Content -Path $outputFile -Value $sysDbUserObjects # this approach is needed because -Append is used in Export-DbaSysDbUserObject.ps1
                Get-ChildItem -ErrorAction Ignore -Path $outputFile
            }

            if ($Exclude -notcontains 'AvailabilityGroups') {
                Write-Message -Level Verbose -Message "Exporting availability group"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting availability groups"
                $null = Get-DbaAvailabilityGroup -SqlInstance $server -WarningAction SilentlyContinue | Export-DbaScript -FilePath "$exportPath\AvailabilityGroups.sql" -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\AvailabilityGroups.sql"
            }

            if ($Exclude -notcontains 'OleDbProvider') {
                Write-Message -Level Verbose -Message "Exporting OLEDB Providers"
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting OLEDB Providers"
                $null = Get-DbaOleDbProvider -SqlInstance $server -WarningAction SilentlyContinue | Export-DbaScript -FilePath "$exportPath\OleDbProvider.sql" -BatchSeparator $BatchSeparator -NoPrefix:$NoPrefix -ScriptingOptionsObject $ScriptingOption
                Get-ChildItem -ErrorAction Ignore -Path "$exportPath\oledbprovider.sql"
            }


            Write-Progress -Activity "Performing Instance Export for $instance" -Completed
        }
    }
    end {
        $totalTime = ($elapsed.Elapsed.toString().Split(".")[0])
        Write-Message -Level Verbose -Message "SQL Server export complete."
        Write-Message -Level Verbose -Message "Export started: $started"
        Write-Message -Level Verbose -Message "Export completed: $(Get-Date)"
        Write-Message -Level Verbose -Message "Total Elapsed time: $totalTime"
    }
}