function New-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Creates SQL Server availability groups with automated replica setup, database seeding, and listener configuration.

    .DESCRIPTION
        Creates availability groups with full automation, eliminating the manual multi-step process typically required through T-SQL or SSMS. This command handles the entire workflow from initial validation through final configuration, so you don't have to manually coordinate across multiple servers and troubleshoot common setup issues.

        Perfect for setting up high availability environments, disaster recovery solutions, or read-scale deployments. Supports both traditional Windows Server Failover Cluster (WSFC) environments and modern cluster-less configurations for containers and Linux.

        * Validates prerequisites across all instances
        * Creates availability group and configures primary replica
        * Sets up database mirroring endpoints with proper authentication
        * Adds and joins secondary replicas automatically
        * Seeds databases using backup/restore or direct seeding
        * Configures listeners with static IP or DHCP
        * Grants necessary cluster and endpoint permissions
        * Enables AlwaysOn_health extended events sessions

        The command handles the complex coordination between servers that trips up manual setups - endpoint permissions, service account access, database seeding modes, and cluster integration.

        NOTES:
        - If a backup / restore is performed, the backups will be left intact on the network share.
        - If you're using SQL Server on Linux and a fully qualified domain name is required, please use the FQDN to create a proper Endpoint

        PLEASE NOTE THE CHANGED DEFAULTS:
        Starting with version 1.1.x we changed the defaults of the following parameters to have the same defaults
        as the T-SQL command "CREATE AVAILABILITY GROUP" and the wizard in SQL Server Management Studio:
        * ClusterType from External to Wsfc (Windows Server Failover Cluster).
        * FailureConditionLevel from OnServerDown (Level 1) to OnCriticalServerErrors (Level 3).
        * ConnectionModeInSecondaryRole from AllowAllConnections (ALL) to AllowNoConnections (NO).
        To change these defaults we have introduced configuration parameters for all of them, see documentation of the parameters for details.

        Thanks for this, Thomas Stringer! https://blogs.technet.microsoft.com/heyscriptingguy/2013/04/29/set-up-an-alwayson-availability-group-with-powershell/

    .PARAMETER Primary
        The primary SQL Server instance. Server version must be SQL Server version 2012 or higher.

    .PARAMETER PrimarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Secondary
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        The name of the Availability Group.

    .PARAMETER IsContained
        Builds the Availability Group as contained. Only supported in SQL Server 2022 or higher.

        https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/contained-availability-groups-overview

    .PARAMETER ReuseSystemDatabases
        Used when rebuilding an availability group with the same name, where system databases already exist for the contained availability group.

    .PARAMETER DtcSupport
        Indicates whether the DtcSupport is enabled

    .PARAMETER ClusterType
        Cluster type of the Availability Group. Only supported in SQL Server 2017 and above.
        Options include: Wsfc, External or None.

        Defaults to Wsfc (Windows Server Failover Cluster).

        The default can be changed with:
        Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.ClusterType' -Value '...' -Passthru | Register-DbatoolsConfig

    .PARAMETER AutomatedBackupPreference
        Specifies how replicas in the primary role are treated in the evaluation to pick the desired replica to perform a backup.

    .PARAMETER FailureConditionLevel
        Specifies the different conditions that can trigger an automatic failover in Availability Group.

        Defaults to OnCriticalServerErrors (Level 3).

        From https://docs.microsoft.com/en-us/sql/t-sql/statements/create-availability-group-transact-sql:
            Level 1 = OnServerDown
            Level 2 = OnServerUnresponsive
            Level 3 = OnCriticalServerErrors (the default in CREATE AVAILABILITY GROUP and in this command)
            Level 4 = OnModerateServerErrors
            Level 5 = OnAnyQualifiedFailureCondition

        The default can be changed with:
        Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.FailureConditionLevel' -Value 'On...' -Passthru | Register-DbatoolsConfig

    .PARAMETER HealthCheckTimeout
        This setting used to specify the length of time, in milliseconds, that the SQL Server resource DLL should wait for information returned by the sp_server_diagnostics stored procedure before reporting the Always On Failover Cluster Instance (FCI) as unresponsive.

        Changes that are made to the timeout settings are effective immediately and do not require a restart of the SQL Server resource.

        Defaults to 30000 (30 seconds).

    .PARAMETER Basic
        Indicates whether the availability group is Basic Availability Group.

        https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/basic-availability-groups-always-on-availability-groups

    .PARAMETER DatabaseHealthTrigger
        Indicates whether the availability group triggers the database health.

    .PARAMETER Passthru
        Don't create the availability group, just pass thru an object that can be further customized before creation.

    .PARAMETER Database
        The database or databases to add.

    .PARAMETER SharedPath
        The network share where the backups will be backed up and restored from.

        Each SQL Server service account must have access to this share.

        NOTE: If a backup / restore is performed, the backups will be left in tact on the network share.

    .PARAMETER UseLastBackup
        Use the last full and log backup of database. A log backup must be the last backup.

    .PARAMETER Force
        Drop and recreate the database on remote servers using fresh backup.

    .PARAMETER AvailabilityMode
        Sets the availability mode of the availability group replica. Options are: AsynchronousCommit and SynchronousCommit. SynchronousCommit is default.

    .PARAMETER FailoverMode
        Sets the failover mode of the availability group replica. Options are Automatic, Manual and External. Automatic is default.

    .PARAMETER BackupPriority
        Sets the backup priority availability group replica. Default is 50.

    .PARAMETER Endpoint
        By default, this command will attempt to find a DatabaseMirror endpoint. If one does not exist, it will create it.

        If an endpoint must be created, the name "hadr_endpoint" will be used. If an alternative is preferred, use Endpoint.

    .PARAMETER EndpointUrl
        By default, the property Fqdn of Get-DbaEndpoint is used as EndpointUrl.

        Use EndpointUrl if different URLs are required due to special network configurations.
        EndpointUrl has to be an array of strings in format 'TCP://system-address:port', one entry for every instance.
        First entry for the primary instance, following entries for secondary instances in the order they show up in Secondary.
        See details regarding the format at: https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/specify-endpoint-url-adding-or-modifying-availability-replica

    .PARAMETER ConnectionModeInPrimaryRole
        Specifies the connection intent modes of an Availability Replica in primary role. AllowAllConnections by default.

    .PARAMETER ConnectionModeInSecondaryRole
        Specifies the connection modes of an Availability Replica in secondary role.
        Options include: AllowNoConnections (Alias: No), AllowReadIntentConnectionsOnly (Alias: Read-intent only),  AllowAllConnections (Alias: Yes)

        Defaults to AllowNoConnections.

        The default can be changed with:
        Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.ConnectionModeInSecondaryRole' -Value '...' -Passthru | Register-DbatoolsConfig

    .PARAMETER SeedingMode
        Specifies how the secondary replica will be initially seeded.

        Automatic enables direct seeding. This method will seed the secondary replica over the network. This method does not require you to backup and restore a copy of the primary database on the replica.

        Manual requires you to create a backup of the database on the primary replica and manually restore that backup on the secondary replica.

    .PARAMETER Certificate
        Specifies that the endpoint is to authenticate the connection using the certificate specified by certificate_name to establish identity for authorization.

        The far endpoint must have a certificate with the public key matching the private key of the specified certificate.

    .PARAMETER ConfigureXESession
        Configure the AlwaysOn_health extended events session to start automatically on every replica as the SSMS wizard would do.
        https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-extended-events#BKMK_alwayson_health

    .PARAMETER IPAddress
        Sets the IP address of the availability group listener.

    .PARAMETER SubnetMask
        Sets the subnet IP mask of the availability group listener.

    .PARAMETER Port
        Sets the number of the port used to communicate with the availability group.

    .PARAMETER Dhcp
        Indicates whether the object is DHCP.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaAvailabilityGroup

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2016a -Name SharePoint

        Creates a new availability group on sql2016a named SharePoint

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2016a -Name SharePoint -Secondary sql2016b

        Creates a new availability group on sql2016a named SharePoint with a secondary replica, sql2016b

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2016std -Name BAG1 -Basic -Confirm:$false

        Creates a basic availability group named BAG1 on sql2016std and does not confirm when setting up

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2022n01 -Secondary sql2022n02 -Name AgContained -IsContained

        Creates a contained availability group named AgContained on nodes sql2022n01 and sql2022n02

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2016b -Name AG1 -Dhcp -Database db1 -UseLastBackup

        Creates an availability group on sql2016b with the name ag1. Uses the last backups available to add the database db1 to the AG.

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2017 -Name SharePoint -ClusterType None -FailoverMode Manual

        Creates a new availability group on sql2017 named SharePoint with a cluster type of none and a failover mode of manual

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql1 -Secondary sql2 -Name ag1 -Database pubs -ClusterType None -SeedingMode Automatic -FailoverMode Manual

        Creates a new availability group with a primary replica on sql1 and a secondary on sql2. Automatically adds the database pubs.

    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql1 -Secondary sql2 -Name ag1 -Database pubs -EndpointUrl 'TCP://sql1.specialnet.local:5022', 'TCP://sql2.specialnet.local:5022'

        Creates a new availability group with a primary replica on sql1 and a secondary on sql2 with custom endpoint urls. Automatically adds the database pubs.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> $params = @{
        >> Primary = "sql1"
        >> PrimarySqlCredential = $cred
        >> Secondary = "sql2"
        >> SecondarySqlCredential = $cred
        >> Name = "test-ag"
        >> Database = "pubs"
        >> ClusterType = "None"
        >> SeedingMode = "Automatic"
        >> FailoverMode = "Manual"
        >> Confirm = $false
        >> }
        PS C:\> New-DbaAvailabilityGroup @params

        This exact command was used to create an availability group on docker!
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter]$Primary,
        [PSCredential]$PrimarySqlCredential,
        [DbaInstanceParameter[]]$Secondary,
        [PSCredential]$SecondarySqlCredential,
        # AG

        [parameter(Mandatory)]
        [string]$Name,
        [switch]$IsContained,
        [switch]$ReuseSystemDatabases,
        [switch]$DtcSupport,
        [ValidateSet('Wsfc', 'External', 'None')]
        [string]$ClusterType = (Get-DbatoolsConfigValue -FullName 'AvailabilityGroups.Default.ClusterType' -Fallback 'Wsfc'),
        [ValidateSet('None', 'Primary', 'Secondary', 'SecondaryOnly')]
        [string]$AutomatedBackupPreference = 'Secondary',
        [ValidateSet('OnAnyQualifiedFailureCondition', 'OnCriticalServerErrors', 'OnModerateServerErrors', 'OnServerDown', 'OnServerUnresponsive')]
        [string]$FailureConditionLevel = (Get-DbatoolsConfigValue -FullName 'AvailabilityGroups.Default.FailureConditionLevel' -Fallback 'OnCriticalServerErrors'),
        [int]$HealthCheckTimeout = 30000,
        [switch]$Basic,
        [switch]$DatabaseHealthTrigger,
        [switch]$Passthru,
        # database

        [string[]]$Database,
        [string]$SharedPath,
        [switch]$UseLastBackup,
        [switch]$Force,
        # replica

        [ValidateSet('AsynchronousCommit', 'SynchronousCommit')]
        [string]$AvailabilityMode = "SynchronousCommit",
        [ValidateSet('Automatic', 'Manual', 'External')]
        [string]$FailoverMode = "Automatic",
        [int]$BackupPriority = 50,
        [ValidateSet('AllowAllConnections', 'AllowReadWriteConnections')]
        [string]$ConnectionModeInPrimaryRole = 'AllowAllConnections',
        [ValidateSet('AllowNoConnections', 'AllowReadIntentConnectionsOnly', 'AllowAllConnections', 'No', 'Read-intent only', 'Yes')]
        [string]$ConnectionModeInSecondaryRole = (Get-DbatoolsConfigValue -FullName 'AvailabilityGroups.Default.ConnectionModeInSecondaryRole' -Fallback 'AllowNoConnections'),
        [ValidateSet('Automatic', 'Manual')]
        [string]$SeedingMode = 'Manual',
        [string]$Endpoint,
        [string[]]$EndpointUrl,
        [string]$Certificate,
        [switch]$ConfigureXESession,
        # network

        [ipaddress[]]$IPAddress,
        [ipaddress]$SubnetMask = "255.255.255.0",
        [int]$Port = 1433,
        [switch]$Dhcp,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        $stepCounter = $wait = 0

        if ($Force -and $Secondary -and (-not $SharedPath -and -not $UseLastBackup) -and ($SeedingMode -ne 'Automatic')) {
            Stop-Function -Message "SharedPath or UseLastBackup is required when Force is used"
            return
        }

        if ($EndpointUrl) {
            if ($EndpointUrl.Count -ne (1 + $Secondary.Count)) {
                Stop-Function -Message "The number of elements in EndpointUrl is not correct"
                return
            }
            foreach ($epUrl in $EndpointUrl) {
                if ($epUrl -notmatch 'TCP://.+:\d+') {
                    Stop-Function -Message "EndpointUrl '$epUrl' not in correct format 'TCP://system-address:port'"
                    return
                }
            }
        }

        if ($ConnectionModeInSecondaryRole) {
            $ConnectionModeInSecondaryRole =
            switch ($ConnectionModeInSecondaryRole) {
                "No" { "AllowNoConnections" }
                "Read-intent only" { "AllowReadIntentConnectionsOnly" }
                "Yes" { "AllowAllConnections" }
                default { $ConnectionModeInSecondaryRole }
            }
        }

        if ($IPAddress -and $Dhcp) {
            Stop-Function -Message "You cannot specify both an IP address and the Dhcp switch for the listener."
            return
        }

        try {
            $server = Connect-DbaInstance -SqlInstance $Primary -SqlCredential $PrimarySqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Primary
            return
        }

        if ($SeedingMode -eq 'Automatic' -and $server.VersionMajor -lt 13) {
            Stop-Function -Message "Automatic seeding mode only supported in SQL Server 2016 and above" -Target $Primary
            return
        }

        if ($Basic -and $server.VersionMajor -lt 13) {
            Stop-Function -Message "Basic availability groups are only supported in SQL Server 2016 and above" -Target $Primary
            return
        }

        if ($IsContained -and $server.VersionMajor -lt 16) {
            Stop-Function -Message "Contained availability groups are only supported in SQL Server 2022 and above" -Target $Primary
            return
        }

        if ($ReuseSystemDatabases -and $IsContained -eq $false) {
            Stop-Function -Message "Reuse system databases is only applicable in contained availability groups" -Target $Primary
            return
        }

        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Checking requirements"
        $requirementsFailed = $false

        if (-not $server.IsHadrEnabled) {
            $requirementsFailed = $true
            Write-Message -Level Warning -Message "Availability Group (HADR) is not configured for the instance: $Primary. Use Enable-DbaAgHadr to configure the instance."
        }

        if ($Secondary) {
            $secondaries = @()
            if ($SeedingMode -eq "Automatic") {
                $primarypath = Get-DbaDefaultPath -SqlInstance $server
            }
            foreach ($instance in $Secondary) {
                try {
                    $second = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SecondarySqlCredential
                    $secondaries += $second
                } catch {
                    Write-Progress -Activity "Adding new availability group" -Completed
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                if (-not $second.IsHadrEnabled) {
                    $requirementsFailed = $true
                    Write-Message -Level Warning -Message "Availability Group (HADR) is not configured for the instance: $instance. Use Enable-DbaAgHadr to configure the instance."
                }

                if ($SeedingMode -eq "Automatic") {
                    $secondarypath = Get-DbaDefaultPath -SqlInstance $second
                    if ($primarypath.Data -ne $secondarypath.Data) {
                        Write-Message -Level Warning -Message "Primary and secondary ($instance) default data paths do not match. Trying anyway."
                    }
                    if ($primarypath.Log -ne $secondarypath.Log) {
                        Write-Message -Level Warning -Message "Primary and secondary ($instance) default log paths do not match. Trying anyway."
                    }
                }
            }
        }

        if ($requirementsFailed) {
            Write-Progress -Activity "Adding new availability group" -Completed
            Stop-Function -Message "Prerequisites are not completly met, so stopping here. See warning messages for details."
            return
        }

        # Don't reuse $server here, it fails
        if (Get-DbaAvailabilityGroup -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -AvailabilityGroup $Name) {
            Write-Progress -Activity "Adding new availability group" -Completed
            Stop-Function -Message "Availability group named $Name already exists on $Primary"
            return
        }

        if ($Certificate) {
            $cert = Get-DbaDbCertificate -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Certificate $Certificate
            if (-not $cert) {
                Write-Progress -Activity "Adding new availability group" -Completed
                Stop-Function -Message "Certificate $Certificate does not exist on $Primary" -Target $Primary
                return
            }
        }

        if (($SharedPath)) {
            if (-not (Test-DbaPath -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Path $SharedPath)) {
                Write-Progress -Activity "Adding new availability group" -Completed
                Stop-Function -Continue -Message "Cannot access $SharedPath from $Primary"
                return
            }
        }

        if ($Database -and -not $UseLastBackup -and -not $SharedPath -and $Secondary -and $SeedingMode -ne 'Automatic') {
            Write-Progress -Activity "Adding new availability group" -Completed
            Stop-Function -Continue -Message "You must specify a SharedPath when adding databases to a manually seeded availability group"
            return
        }

        if ($server.HostPlatform -eq "Linux") {
            # New to SQL Server 2017 (14.x) is the introduction of a cluster type for AGs. For Linux, there are two valid values: External and None.
            if ($ClusterType -notin "External", "None") {
                Write-Progress -Activity "Adding new availability group" -Completed
                Stop-Function -Continue -Message "Linux only supports ClusterType of External or None"
                return
            }
            # Microsoft Distributed Transaction Coordinator (DTC) is not supported under Linux in SQL Server 2017
            if ($DtcSupport) {
                Write-Progress -Activity "Adding new availability group" -Completed
                Stop-Function -Continue -Message "Microsoft Distributed Transaction Coordinator (DTC) is not supported under Linux"
                return
            }
        }

        if ($ClusterType -eq "None" -and $server.VersionMajor -lt 14) {
            Write-Progress -Activity "Adding new availability group" -Completed
            Stop-Function -Message "ClusterType of None only supported in SQL Server 2017 and above"
            return
        }

        # database checks
        if ($Database) {
            $dbs += Get-DbaDatabase -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Database $Database
        }

        foreach ($primarydb in $dbs) {
            if ($primarydb.MirroringStatus -ne "None") {
                Write-Progress -Activity "Adding new availability group" -Completed
                Stop-Function -Message "Cannot setup mirroring on database ($($primarydb.Name)) due to its current mirroring state: $($primarydb.MirroringStatus)"
                return
            }

            if ($primarydb.Status -ne "Normal") {
                Write-Progress -Activity "Adding new availability group" -Completed
                Stop-Function -Message "Cannot setup mirroring on database ($($primarydb.Name)) due to its current state: $($primarydb.Status)"
                return
            }

            if ($primarydb.RecoveryModel -ne "Full") {
                if ((Test-Bound -ParameterName UseLastBackup)) {
                    Write-Progress -Activity "Adding new availability group" -Completed
                    Stop-Function -Message "$($primarydb.Name) not set to full recovery. UseLastBackup cannot be used."
                    return
                } else {
                    Set-DbaDbRecoveryModel -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Database $primarydb.Name -RecoveryModel Full
                }
            }
        }

        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Creating availability group named $Name on $Primary"

        # Start work
        if ($Pscmdlet.ShouldProcess($Primary, "Setting up availability group named $Name and adding primary replica")) {
            try {
                $ag = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroup -ArgumentList $server, $Name
                $ag.AutomatedBackupPreference = [Microsoft.SqlServer.Management.Smo.AvailabilityGroupAutomatedBackupPreference]::$AutomatedBackupPreference
                $ag.FailureConditionLevel = [Microsoft.SqlServer.Management.Smo.AvailabilityGroupFailureConditionLevel]::$FailureConditionLevel
                $ag.HealthCheckTimeout = $HealthCheckTimeout

                if ($server.VersionMajor -ge 13) {
                    $ag.BasicAvailabilityGroup = $Basic
                    $ag.DatabaseHealthTrigger = $DatabaseHealthTrigger
                    $ag.DtcSupportEnabled = $DtcSupport
                }

                if ($server.VersionMajor -ge 14) {
                    $ag.ClusterType = $ClusterType
                }

                if ($server.VersionMajor -ge 16) {
                    $ag.IsContained = $IsContained
                    $ag.ReuseSystemDatabases = $ReuseSystemDatabases
                }

                if ($PassThru) {
                    $defaults = 'LocalReplicaRole', 'Name as AvailabilityGroup', 'PrimaryReplicaServerName as PrimaryReplica', 'AutomatedBackupPreference', 'AvailabilityReplicas', 'AvailabilityDatabases', 'AvailabilityGroupListeners'
                    Write-Progress -Activity "Adding new availability group" -Completed
                    return (Select-DefaultView -InputObject $ag -Property $defaults)
                }

                $replicaparams = @{
                    InputObject                   = $ag
                    ClusterType                   = $ClusterType
                    AvailabilityMode              = $AvailabilityMode
                    FailoverMode                  = $FailoverMode
                    BackupPriority                = $BackupPriority
                    ConnectionModeInPrimaryRole   = $ConnectionModeInPrimaryRole
                    ConnectionModeInSecondaryRole = $ConnectionModeInSecondaryRole
                    Endpoint                      = $Endpoint
                    Certificate                   = $Certificate
                    ConfigureXESession            = $ConfigureXESession
                }

                if ($EndpointUrl) {
                    $epUrl, $EndpointUrl = $EndpointUrl
                    $replicaparams += @{EndpointUrl = $epUrl }
                }

                if ($server.VersionMajor -ge 13) {
                    $replicaparams += @{SeedingMode = $SeedingMode }
                }

                $null = Add-DbaAgReplica @replicaparams -EnableException -SqlInstance $server
            } catch {
                $msg = $_.Exception.InnerException.InnerException.Message
                if (-not $msg) {
                    $msg = $_
                }
                Write-Progress -Activity "Adding new availability group" -Completed
                Stop-Function -Message $msg -ErrorRecord $_ -Target $Primary
                return
            }
        }

        # Add replicas
        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Adding secondary replicas"

        foreach ($second in $secondaries) {
            if ($Pscmdlet.ShouldProcess($second.Name, "Adding replica to availability group named $Name")) {
                try {
                    # Add replicas
                    if ($EndpointUrl) {
                        $epUrl, $EndpointUrl = $EndpointUrl
                        $replicaparams['EndpointUrl'] = $epUrl
                    }

                    $null = Add-DbaAgReplica @replicaparams -EnableException -SqlInstance $second
                } catch {
                    Write-Progress -Activity "Adding new availability group" -Completed
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $second -Continue
                }
            }
        }

        try {
            # something is up with .net create(), force a stop
            Invoke-Create -Object $ag
        } catch {
            $msg = $_.Exception.InnerException.InnerException.Message
            if (-not $msg) {
                $msg = $_
            }
            Write-Progress -Activity "Adding new availability group" -Completed
            Stop-Function -Message $msg -ErrorRecord $_ -Target $Primary
            return
        }

        # Add listener
        if ($IPAddress -or $Dhcp) {
            $progressmsg = "Adding listener"
        } else {
            $progressmsg = "Joining availability group"
        }
        Write-ProgressHelper -StepNumber ($stepCounter++) -Message $progressmsg

        if ($IPAddress) {
            if ($Pscmdlet.ShouldProcess($Primary, "Adding static IP listener for $Name to the primary replica")) {
                $null = Add-DbaAgListener -InputObject $ag -IPAddress $IPAddress -SubnetMask $SubnetMask -Port $Port
            }
        } elseif ($Dhcp) {
            if ($Pscmdlet.ShouldProcess($Primary, "Adding DHCP listener for $Name to the primary replica")) {
                $null = Add-DbaAgListener -InputObject $ag -Port $Port -Dhcp
            }
        }

        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Joining availability group"

        foreach ($second in $secondaries) {
            if ($Pscmdlet.ShouldProcess("Joining $($second.Name) to $Name")) {
                try {
                    # join replicas to ag
                    Join-DbaAvailabilityGroup -SqlInstance $second -InputObject $ag -EnableException
                } catch {
                    Write-Progress -Activity "Adding new availability group" -Completed
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $second -Continue
                }
                $second.AvailabilityGroups.Refresh()
            }
        }

        # Wait for the availability group to be ready
        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Waiting for replicas to be connected and ready"
        do {
            Start-Sleep -Milliseconds 500
            $wait++
            $ready = $true
            $states = Get-DbaAgReplica -SqlInstance $secondaries | Where-Object Role -notin "Primary", "Unknown"
            foreach ($state in $states) {
                if ($state.ConnectionState -ne "Connected") {
                    $ready = $false
                }
            }
        } until ($ready -or $wait -gt 40) # wait up to 20 seconds (500ms * 40)

        if (-not $ready -or $wait -gt 40) {
            Write-Message -Level Warning -Message "One or more replicas are still not connected and ready. If you encounter this error often, please let us know and we'll increase the timeout. Moving on and trying the next step."
        }

        $wait = 0

        # This can not be moved to Add-DbaAgReplica, as the AG has to be existing to grant this permission
        if ($SeedingMode -eq "Automatic") {
            if ($Pscmdlet.ShouldProcess($second.Name, "Granting CreateAnyDatabase permission to the availability group on every replica")) {
                try {
                    $null = Grant-DbaAgPermission -SqlInstance $server -Type AvailabilityGroup -AvailabilityGroup $Name -Permission CreateAnyDatabase -EnableException
                    foreach ($second in $secondaries) {
                        $null = Grant-DbaAgPermission -SqlInstance $second -Type AvailabilityGroup -AvailabilityGroup $Name -Permission CreateAnyDatabase -EnableException
                    }
                } catch {
                    Write-Progress -Activity "Adding new availability group" -Completed
                    Stop-Function -Message "Failure" -ErrorRecord $_
                }
            }
        }

        # Add databases
        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Adding databases"
        if ($Database) {
            if ($Pscmdlet.ShouldProcess($server.Name, "Adding databases to Availability Group.")) {
                if ($Force) {
                    try {
                        Get-DbaDatabase -SqlInstance $secondaries -Database $Database -EnableException | Remove-DbaDatabase -EnableException
                    } catch {
                        Write-Progress -Activity "Adding new availability group" -Completed
                        Stop-Function -Message "Failed to remove databases from secondary replicas." -ErrorRecord $_
                    }
                }

                $addDatabaseParams = @{
                    SqlInstance       = $server
                    AvailabilityGroup = $Name
                    Database          = $Database
                    Secondary         = $secondaries
                    UseLastBackup     = $UseLastBackup
                    EnableException   = $true
                }
                if ($SeedingMode) { $addDatabaseParams['SeedingMode'] = $SeedingMode }
                if ($SharedPath) { $addDatabaseParams['SharedPath'] = $SharedPath }
                try {
                    $null = Add-DbaAgDatabase @addDatabaseParams
                } catch {
                    Write-Progress -Activity "Adding new availability group" -Completed
                    Stop-Function -Message "Failed to add databases to Availability Group." -ErrorRecord $_
                }
            }
        }
        Write-Progress -Activity "Adding new availability group" -Completed

        # Get results
        Get-DbaAvailabilityGroup -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -AvailabilityGroup $Name
    }
}