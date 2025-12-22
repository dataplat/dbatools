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
        Specifies the SQL Server instance that will host the primary replica of the availability group.
        This instance must have AlwaysOn Availability Groups enabled and be running SQL Server 2012 or higher.
        Use this when setting up the main server that will handle write operations and coordinate with secondary replicas.

    .PARAMETER PrimarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Secondary
        Specifies one or more SQL Server instances that will host secondary replicas in the availability group.
        All instances must have AlwaysOn enabled and be running SQL Server 2012 or higher.
        These servers will receive synchronized copies of your databases and can serve read-only workloads or provide disaster recovery.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies the name for the new availability group.
        This name must be unique across all availability groups in the Windows Server Failover Cluster.
        Choose a descriptive name that reflects the application or purpose, as this will be used for monitoring and management.

    .PARAMETER IsContained
        Creates a contained availability group that includes system databases alongside user databases.
        Only supported in SQL Server 2022 and above, this eliminates the need to manually synchronize logins and jobs.
        Use this for simplified management when you need consistent security objects across all replicas.

    .PARAMETER ReuseSystemDatabases
        Reuses existing system databases when recreating a contained availability group with the same name.
        Only applicable with contained availability groups (-IsContained).
        Use this when rebuilding an AG to avoid conflicts with previously created system database copies.

    .PARAMETER DtcSupport
        Enables support for distributed transactions using Microsoft Distributed Transaction Coordinator (DTC).
        Required when applications use distributed transactions that span databases in the availability group.
        Note that DTC support is not available on Linux SQL Server instances.

    .PARAMETER ClusterType
        Defines the clustering technology used by the availability group (SQL Server 2017+).
        Options: Wsfc (Windows Server Failover Cluster), External (Linux Pacemaker), or None (no cluster).
        Use 'None' for read-scale scenarios without automatic failover, 'External' for Linux environments, or 'Wsfc' for traditional Windows clustering.

    .PARAMETER AutomatedBackupPreference
        Controls which replicas are preferred for automated backup operations.
        Options: Primary, Secondary, SecondaryOnly, or None.
        Use 'Secondary' to offload backup I/O from the primary, or 'SecondaryOnly' to ensure backups never impact primary performance.

    .PARAMETER FailureConditionLevel
        Determines what conditions trigger automatic failover in the availability group.
        Default is Level 3 (OnCriticalServerErrors), which balances protection against false positives.
        Use Level 1 for fastest failover, Level 5 for maximum sensitivity, or adjust based on your tolerance for automatic failover events.

    .PARAMETER HealthCheckTimeout
        Sets the timeout in milliseconds for health check responses from the sp_server_diagnostics procedure.
        Default is 30000 (30 seconds). Lower values provide faster failure detection but may cause false positives.
        Increase this value in environments with high I/O load or slower storage to prevent unnecessary failovers.

    .PARAMETER Basic
        Creates a Basic Availability Group limited to one database and two replicas.
        Available in SQL Server 2016 Standard Edition and above as an alternative to Database Mirroring.
        Use this for simple two-node high availability scenarios when you don't need multiple databases or advanced features.

    .PARAMETER DatabaseHealthTrigger
        Enables database-level health monitoring that can trigger automatic failover.
        When enabled, database corruption or other critical database errors can initiate failover.
        Use this for additional protection when database integrity is more critical than minimizing failover events.

    .PARAMETER Passthru
        Returns the availability group object without creating it, allowing further customization.
        Use this when you need to modify advanced properties or add custom configurations before creating the AG.
        The returned object can be passed to other dbatools commands or have properties modified directly.

    .PARAMETER Database
        Specifies which databases to add to the availability group during creation.
        Databases must be in Full recovery model and have recent transaction log backups.
        Use this to automatically include databases rather than adding them separately after AG creation.

    .PARAMETER SharedPath
        Specifies the network path where database backups will be stored during secondary replica initialization.
        All SQL Server service accounts must have read/write access to this location.
        Required for manual seeding mode when adding databases - backups remain on the share after completion.

    .PARAMETER UseLastBackup
        Uses existing backup files instead of creating new ones for database initialization.
        The most recent full backup and subsequent log backups will be restored to secondary replicas.
        Use this to save time and storage when recent backups are already available and accessible.

    .PARAMETER Force
        Removes existing databases on secondary replicas before restoring from backup.
        Use this when databases already exist on secondary servers but you want to refresh them.
        Requires SharedPath or UseLastBackup to be specified for the restore operation.

    .PARAMETER AvailabilityMode
        Controls whether transaction commits wait for secondary replica acknowledgment.
        SynchronousCommit ensures zero data loss but may impact performance over distance.
        Use AsynchronousCommit for disaster recovery replicas or when network latency affects performance.

    .PARAMETER FailoverMode
        Determines how failover occurs for the availability group.
        Automatic enables cluster-managed failover with synchronous replicas, Manual requires DBA intervention.
        Use External for Linux environments with Pacemaker cluster management.

    .PARAMETER BackupPriority
        Sets the priority for backup operations on this replica (0-100, default 50).
        Higher values make this replica more preferred for automated backup jobs.
        Use lower values on primary replicas to offload backup I/O, higher values on dedicated backup servers.

    .PARAMETER Endpoint
        Specifies the name for the database mirroring endpoint used for availability group communication.
        If not specified, the command searches for existing endpoints or creates 'hadr_endpoint'.
        Use a custom name when you have specific endpoint naming standards or multiple AGs on the same instance.

    .PARAMETER EndpointUrl
        Specifies custom TCP URLs for availability group endpoints when automatic detection isn't suitable.
        Required format: 'TCP://hostname:port' for each instance (primary first, then secondaries).
        Use this in complex network environments with custom DNS, firewalls, or when instances use non-default ports.

    .PARAMETER ConnectionModeInPrimaryRole
        Controls what connections are allowed to the primary replica.
        AllowAllConnections (default) permits both read-write and read-intent connections.
        Use AllowReadWriteConnections to restrict read-only workloads to secondary replicas only.

    .PARAMETER ConnectionModeInSecondaryRole
        Controls what connections are allowed to secondary replicas.
        Default is AllowNoConnections to prevent accidental writes or outdated reads.
        Use AllowReadIntentConnectionsOnly for reporting workloads, or AllowAllConnections for maximum flexibility.

    .PARAMETER SeedingMode
        Determines how databases are initialized on secondary replicas.
        Manual (default) uses backup/restore through shared storage, Automatic uses direct network streaming.
        Use Automatic for SQL Server 2016+ to simplify setup when network bandwidth is sufficient and shared storage is limited.

    .PARAMETER Certificate
        Specifies the certificate name for endpoint authentication instead of Windows authentication.
        Both endpoints must have matching certificates with corresponding public/private key pairs.
        Use this for cross-domain scenarios or when Windows authentication is not available between replicas.

    .PARAMETER ConfigureXESession
        Automatically starts the AlwaysOn_health Extended Events session on all replicas.
        This session captures availability group events for monitoring and troubleshooting.
        Use this to match the behavior of the SQL Server Management Studio AG wizard and enable built-in diagnostics.

    .PARAMETER IPAddress
        Specifies one or more static IP addresses for the availability group listener.
        Each IP should correspond to a different subnet if replicas span multiple subnets.
        Use static IPs when DHCP is not available or when you need predictable listener addresses for applications.

    .PARAMETER SubnetMask
        Specifies the subnet mask for static IP listener configuration.
        Default is 255.255.255.0, which works for most standard network configurations.
        Adjust this to match your network's subnet configuration when using custom IP addressing.

    .PARAMETER Port
        Specifies the TCP port for the availability group listener.
        Default is 1433 (standard SQL Server port). Applications connect to this port to reach the current primary.
        Use a different port when 1433 is already in use or for security through obscurity.

    .PARAMETER Dhcp
        Configures the availability group listener to use DHCP for IP address assignment.
        The cluster will request an IP address from DHCP servers on each replica's subnet.
        Use this when static IP management is not desired and DHCP reservations can provide consistent addressing.

    .PARAMETER ClusterConnectionOption
        Specifies connection options for TDS 8.0 support in SQL Server 2025 and above.
        This allows the Windows Server Failover Cluster (WSFC) to connect to SQL Server instances using ODBC with TLS 1.3 encryption.
        The value is a string containing semicolon-delimited key-value pairs.

        Available keys:
        - Encrypt: Controls connection encryption
        - TrustServerCertificate: Whether to trust the server certificate
        - HostNameInCertificate: Expected hostname in the certificate
        - ServerCertificate: Path to server certificate

        This setting is persisted by WSFC in the registry and used continuously for cluster-to-instance communication.
        Note: PowerShell does not validate these values - invalid combinations will be rejected by SMO or the ODBC driver.

        Example: "Encrypt=Strict;TrustServerCertificate=False"

        For detailed documentation, see:
        https://learn.microsoft.com/en-us/sql/t-sql/statements/create-availability-group-transact-sql

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
        [string]$ClusterConnectionOption,
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

        # Check if ConnectionModeInSecondaryRole is set on Standard Edition
        if ($ConnectionModeInSecondaryRole -and $ConnectionModeInSecondaryRole -ne "AllowNoConnections") {
            $instances = @($server) + $secondaries
            foreach ($instance in $instances) {
                if ($instance.EngineEdition -eq "Standard") {
                    Write-Message -Level Warning -Message "ConnectionModeInSecondaryRole is not supported on Standard Edition. The setting will be ignored on $($instance.Name). Consider using Enterprise or Developer Edition for read-only secondary replicas."
                }
            }
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

                if ($server.VersionMajor -ge 17 -and $ClusterConnectionOption) {
                    $ag.ClusterConnectionOptions = $ClusterConnectionOption
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