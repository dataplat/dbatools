function Add-DbaAgReplica {
    <#
    .SYNOPSIS
        Adds a replica to an availability group on one or more SQL Server instances.

    .DESCRIPTION
        Adds a replica to an availability group on one or more SQL Server instances.

        Automatically creates database mirroring endpoints if required.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instances using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Sets the display name for the availability group replica being added. Defaults to the SQL Server instance's domain instance name.
        Use this when you need a custom replica name that differs from the server name, such as for clarity in multi-subnet scenarios.
        This parameter is only supported when adding a replica to a single instance.

    .PARAMETER ClusterType
        Specifies the underlying clustering technology for the availability group. Only supported in SQL Server 2017 and above.
        Use 'Wsfc' for traditional Windows Server Failover Cluster setups, 'External' for Linux Pacemaker clusters, or 'None' for read-scale availability groups.
        Defaults to 'Wsfc' which handles most Windows-based high availability scenarios.

        The default can be changed with:
        Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.ClusterType' -Value '...' -Passthru | Register-DbatoolsConfig

    .PARAMETER AvailabilityMode
        Controls how the replica commits transactions relative to the primary replica. SynchronousCommit waits for secondary confirmation before committing, ensuring zero data loss but higher latency.
        AsynchronousCommit commits immediately on primary without waiting for secondary confirmation, providing better performance but potential data loss during failover.
        Defaults to SynchronousCommit for maximum data protection.

    .PARAMETER FailoverMode
        Determines whether the replica can automatically fail over when the primary becomes unavailable. Automatic failover requires SynchronousCommit availability mode and provides seamless high availability.
        Manual failover requires DBA intervention but works with both synchronous and asynchronous commit modes.
        Defaults to Automatic for immediate failover capabilities.

    .PARAMETER BackupPriority
        Sets the replica's preference for hosting backups within the availability group, ranging from 0-100 where higher values indicate higher priority.
        Use this to designate specific replicas for backup operations, such as setting secondary replicas to higher values to offload backup workloads from the primary.
        Defaults to 50, giving all replicas equal backup preference.

    .PARAMETER Endpoint
        Specifies the name of the database mirroring endpoint to use for availability group communication. Automatically locates existing endpoints or creates one if needed.
        Use this when you need a custom endpoint name instead of the default "hadr_endpoint" that gets created automatically.
        Each SQL Server instance requires a database mirroring endpoint for Always On availability group replication.

    .PARAMETER EndpointUrl
        Overrides the default endpoint URL with custom network addresses for availability group communication. Defaults to the FQDN from the existing endpoint.
        Required for special network configurations like multi-subnet deployments, NAT environments, or when replicas need specific IP addresses for cross-network communication.
        Must be in format 'TCP://system-address:port' with one entry per instance. When creating new endpoints, IPv4 addresses in the URL will be used for endpoint configuration.

    .PARAMETER Passthru
        Returns the replica object without actually creating it in the availability group, allowing for additional customization before final creation.
        Use this when you need to modify replica properties that aren't exposed as direct parameters before adding it to the availability group.

    .PARAMETER InputObject
        Accepts availability group objects from Get-DbaAvailabilityGroup for pipeline operations. This is the target availability group where the replica will be added.
        Use pipeline scenarios like 'Get-DbaAvailabilityGroup -AvailabilityGroup "AG1" | Add-DbaAgReplica -SqlInstance server2' for streamlined replica management.

    .PARAMETER ConnectionModeInPrimaryRole
        Controls which client connections are allowed when this replica is the primary. AllowAllConnections permits both read-write and read-only connections.
        AllowReadWriteConnections restricts access to connections that specify read-write intent, blocking read-only connection attempts.
        Defaults to AllowAllConnections for maximum compatibility with existing applications.

    .PARAMETER ConnectionModeInSecondaryRole
        Controls client access to secondary replicas for read operations. AllowNoConnections blocks all client connections to the secondary.
        AllowReadIntentConnectionsOnly permits only connections that specify ApplicationIntent=ReadOnly, ideal for reporting workloads.
        AllowAllConnections allows any client connection regardless of intent. Defaults to AllowNoConnections for security and performance.

        The default can be changed with:
        Set-DbatoolsConfig -FullName 'AvailabilityGroups.Default.ConnectionModeInSecondaryRole' -Value '...' -Passthru | Register-DbatoolsConfig

    .PARAMETER ReadOnlyRoutingList
        Defines the priority order of replica server names for routing read-only connections when this replica serves as the primary. Requires SQL Server 2016 or later.
        Use this to direct reporting queries to specific secondary replicas, creating an ordered list like @('Server2', 'Server3') to balance read-only workloads.
        This parameter is only supported when adding a replica to a single instance.

    .PARAMETER ReadonlyRoutingConnectionUrl
        Specifies the connection URL that clients use when connecting to this replica for read-only operations via read-only routing. Requires SQL Server 2016 or later.
        Must be in format 'TCP://system-address:port' and typically differs from the regular endpoint URL when using custom network configurations for read workloads.
        This parameter is only supported when adding a replica to a single instance.

    .PARAMETER SeedingMode
        Controls how databases are initially synchronized on the secondary replica. Requires SQL Server 2016 or later.
        Automatic seeding transfers data directly over the network without manual backup/restore operations, ideal for large databases or automated deployments.
        Manual seeding requires you to manually backup databases on the primary and restore them on the secondary, providing more control over the timing and process.

    .PARAMETER Certificate
        Configures certificate-based authentication for the database mirroring endpoint instead of Windows authentication. Requires the certificate name to exist on the SQL Server instance.
        Use this in environments where SQL Server instances run under different domain accounts or in workgroup configurations where Windows authentication isn't feasible.
        The remote replica must have a matching certificate with the corresponding public key for secure communication.

    .PARAMETER ConfigureXESession
        Automatically configures the AlwaysOn_health extended events session to start with SQL Server, matching the behavior of the SSMS availability group wizard.
        Use this to enable automatic collection of availability group health data for monitoring and troubleshooting replica connectivity, failover events, and performance issues.
        The session captures critical Always On events and is essential for proactive availability group management.

    .PARAMETER SessionTimeout
        Sets the timeout period in seconds for detecting replica connectivity failures. The replica waits this long for ping responses before marking a connection as failed.
        Lower values provide faster failure detection but may cause false failures under network stress. Higher values prevent false failures but delay failover detection.
        Microsoft recommends keeping this at 10 seconds or higher for stable operations.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.AvailabilityReplica

        Returns one AvailabilityReplica object for each replica added to the availability group.

        When -Passthru is specified, the replica object is returned before being added to the availability group, allowing for additional customization.

        When -Passthru is not specified, the replica is added to the availability group and the returned object includes added properties for display and context.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - AvailabilityGroup: Name of the availability group that contains this replica
        - Name: The name/display name of the availability replica
        - Role: Current role of the replica (Primary or Secondary)
        - RollupSynchronizationState: Synchronization state (NotSynchronizing, Synchronizing, Synchronized, Reverting, Initializing)
        - AvailabilityMode: Commit mode (SynchronousCommit or AsynchronousCommit)
        - BackupPriority: Backup preference priority (0-100)
        - EndpointUrl: Database mirroring endpoint URL for replica communication
        - SessionTimeout: Session timeout in seconds for failure detection
        - FailoverMode: Failover mode (Automatic or Manual)
        - ReadonlyRoutingList: Priority-ordered list of replicas for read-only routing

        Additional properties available (from SMO AvailabilityReplica object):
        - ConnectionModeInPrimaryRole: Connection mode when this replica is primary (AllowAllConnections or AllowReadWriteConnections)
        - ConnectionModeInSecondaryRole: Connection mode when this replica is secondary (AllowNoConnections, AllowReadIntentConnectionsOnly, or AllowAllConnections)
        - ReadonlyRoutingConnectionUrl: Connection URL for read-only routing operations
        - SeedingMode: Database seeding mode (Automatic or Manual) - SQL Server 2016+
        - Parent: Reference to the parent AvailabilityGroup object
        - State: The state of the SMO object (Existing, Creating, Pending, etc.)
        - Urn: Uniform resource name of the replica

        All properties from the base SMO AvailabilityReplica object are accessible even though only default properties are displayed without using Select-Object *.

    .NOTES
        Tags: AG, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaAgReplica

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017a -AvailabilityGroup SharePoint | Add-DbaAgReplica -SqlInstance sql2017b

        Adds sql2017b to the SharePoint availability group on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017a -AvailabilityGroup SharePoint | Add-DbaAgReplica -SqlInstance sql2017b -FailoverMode Manual

        Adds sql2017b to the SharePoint availability group on sql2017a with a manual failover mode.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017a -AvailabilityGroup SharePoint | Add-DbaAgReplica -SqlInstance sql2017b -EndpointUrl 'TCP://sql2017b.specialnet.local:5022'

        Adds sql2017b to the SharePoint availability group on sql2017a with a custom endpoint URL.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Name,
        [ValidateSet('Wsfc', 'External', 'None')]
        [string]$ClusterType = (Get-DbatoolsConfigValue -FullName 'AvailabilityGroups.Default.ClusterType' -Fallback 'Wsfc'),
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
        [string]$SeedingMode,
        [string]$Endpoint,
        [string[]]$EndpointUrl,
        [switch]$Passthru,
        [string[]]$ReadOnlyRoutingList,
        [string]$ReadonlyRoutingConnectionUrl,
        [string]$Certificate,
        [switch]$ConfigureXESession,
        [int]$SessionTimeout,
        [parameter(ValueFromPipeline, Mandatory)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($EndpointUrl) {
            if ($EndpointUrl.Count -ne $SqlInstance.Count) {
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

        if ($ReadonlyRoutingConnectionUrl -and ($ReadonlyRoutingConnectionUrl -notmatch 'TCP://.+:\d+')) {
            Stop-Function -Message "ReadonlyRoutingConnectionUrl not in correct format 'TCP://system-address:port'"
            return
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

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Certificate) {
                $cert = Get-DbaDbCertificate -SqlInstance $server -Certificate $Certificate
                if (-not $cert) {
                    Stop-Function -Message "Certificate $Certificate does not exist on $instance" -Target $Certificate -Continue
                }
            }

            # Split of endpoint URL here, as it will be used in two places.
            if ($EndpointUrl) {
                $epUrl, $EndpointUrl = $EndpointUrl
            }

            $ep = Get-DbaEndpoint -SqlInstance $server -Type DatabaseMirroring
            if (-not $ep) {
                if (-not $Endpoint) {
                    $Endpoint = "hadr_endpoint"
                }
                if ($Pscmdlet.ShouldProcess($server.Name, "Adding endpoint named $Endpoint to $instance")) {
                    $epParams = @{
                        SqlInstance         = $server
                        Name                = $Endpoint
                        Type                = 'DatabaseMirroring'
                        EndpointEncryption  = 'Supported'
                        EncryptionAlgorithm = 'Aes'
                        Certificate         = $Certificate
                    }
                    # If the endpoint URL is using an ipv4 address, we will use the URL to create a custom endpoint
                    if ($epUrl -match 'TCP://\d+\.\d+.\d+\.\d+:\d+') {
                        $epParams['IPAddress'] = $epUrl -replace 'TCP://(.+):\d+', '$1'
                        $epParams['Port'] = $epUrl -replace 'TCP://.+:(\d+)', '$1'
                    }
                    $ep = New-DbaEndpoint @epParams
                    $null = $ep | Start-DbaEndpoint
                    $epUrl = $ep.Fqdn
                }
            } else {
                $epUrl = $ep.Fqdn
            }

            if ((Test-Bound -Not -ParameterName Name)) {
                $Name = $server.DomainInstanceName
            }

            if ($Pscmdlet.ShouldProcess($server.Name, "Creating a replica for $($InputObject.Name) named $Name")) {
                try {
                    $replica = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityReplica -ArgumentList $InputObject, $Name
                    $replica.EndpointUrl = $epUrl
                    $replica.FailoverMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaFailoverMode]::$FailoverMode
                    $replica.AvailabilityMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaAvailabilityMode]::$AvailabilityMode
                    if ($server.EngineEdition -ne "Standard") {
                        $replica.ConnectionModeInPrimaryRole = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInPrimaryRole]::$ConnectionModeInPrimaryRole
                        $replica.ConnectionModeInSecondaryRole = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInSecondaryRole]::$ConnectionModeInSecondaryRole
                    }
                    $replica.BackupPriority = $BackupPriority

                    if ($ReadonlyRoutingList -and $server.VersionMajor -ge 13) {
                        $replica.ReadonlyRoutingList = $ReadonlyRoutingList
                    }

                    if ($ReadonlyRoutingConnectionUrl -and $server.VersionMajor -ge 13) {
                        $replica.ReadonlyRoutingConnectionUrl = $ReadonlyRoutingConnectionUrl
                    }

                    if ($SeedingMode -and $server.VersionMajor -ge 13) {
                        $replica.SeedingMode = $SeedingMode
                    }

                    if ($SessionTimeout) {
                        if ($SessionTimeout -lt 10) {
                            $Message = "We recommend that you keep the time-out period at 10 seconds or greater. Setting the value to less than 10 seconds creates the possibility of a heavily loaded system missing pings and falsely declaring failure. Please see sqlps.io/agrec for more information."
                            Write-Message -Level Warning -Message $Message
                        }
                        $replica.SessionTimeout = $SessionTimeout
                    }

                    # Add cluster permissions
                    if ($ClusterType -eq 'Wsfc') {
                        if ($Pscmdlet.ShouldProcess($server.Name, "Adding cluster permissions for availability group named $($InputObject.Name)")) {
                            Write-Message -Level Verbose -Message "WSFC Cluster requires granting [NT AUTHORITY\SYSTEM] a few things. Setting now."
                            # To support non-english systems, get the name of SYSTEM login by the sid
                            # See SECURITY_LOCAL_SYSTEM_RID on https://docs.microsoft.com/en-us/windows/win32/secauthz/well-known-sids
                            $systemLoginSidString = '1-1-0-0-0-0-0-5-18-0-0-0'
                            $systemLoginName = ($server.Logins | Where-Object { ($_.Sid -join '-') -eq $systemLoginSidString }).Name
                            if (-not $systemLoginName) {
                                Write-Message -Level Verbose -Message "SYSTEM login not found, so we hope system language is english and create login [NT AUTHORITY\SYSTEM]"
                                try {
                                    $null = New-DbaLogin -SqlInstance $server -Login 'NT AUTHORITY\SYSTEM'
                                    $systemLoginName = 'NT AUTHORITY\SYSTEM'
                                } catch {
                                    Stop-Function -Message "Failed to add login [NT AUTHORITY\SYSTEM]. If it's a non-english system you have to add the equivalent login manually." -ErrorRecord $_
                                }
                            }
                            $permissionSet = New-Object -TypeName Microsoft.SqlServer.Management.SMO.ServerPermissionSet(
                                [Microsoft.SqlServer.Management.SMO.ServerPermission]::AlterAnyAvailabilityGroup,
                                [Microsoft.SqlServer.Management.SMO.ServerPermission]::ConnectSql,
                                [Microsoft.SqlServer.Management.SMO.ServerPermission]::ViewServerState
                            )
                            try {
                                $server.Grant($permissionSet, $systemLoginName)
                            } catch {
                                Stop-Function -Message "Failure adding cluster service account permissions." -ErrorRecord $_
                            }
                        }
                    }

                    if ($ConfigureXESession) {
                        try {
                            Write-Message -Level Debug -Message "Getting session 'AlwaysOn_health' on $instance."
                            $xeSession = Get-DbaXESession -SqlInstance $server -Session AlwaysOn_health -EnableException
                            if ($xeSession) {
                                if (-not $xeSession.AutoStart) {
                                    Write-Message -Level Debug -Message "Setting autostart for session 'AlwaysOn_health' on $instance."
                                    $xeSession.AutoStart = $true
                                    $xeSession.Alter()
                                }
                                if (-not $xeSession.IsRunning) {
                                    Write-Message -Level Debug -Message "Starting session 'AlwaysOn_health' on $instance."
                                    $null = $xeSession | Start-DbaXESession -EnableException
                                }
                                Write-Message -Level Verbose -Message "ConfigureXESession was set, session 'AlwaysOn_health' is now configured and running on $instance."
                            } else {
                                Write-Message -Level Warning -Message "ConfigureXESession was set, but no session named 'AlwaysOn_health' was found on $instance."
                            }
                        } catch {
                            Write-Message -Level Warning -Message "ConfigureXESession was set, but configuration failed on $instance with this error: $_"
                        }

                    }

                    if ($Passthru) {
                        return $replica
                    }

                    $InputObject.AvailabilityReplicas.Add($replica)
                    $agreplica = $InputObject.AvailabilityReplicas[$Name]
                    if ($InputObject.State -eq 'Existing') {
                        Invoke-Create -Object $replica
                        $null = Join-DbaAvailabilityGroup -SqlInstance $instance -SqlCredential $SqlCredential -AvailabilityGroup $InputObject.Name
                        $agreplica.Alter()
                    }

                    if ($server.HostPlatform -ne "Linux") {
                        # Only grant CreateAnyDatabase permission if AG already exists.
                        # If this command is started from New-DbaAvailabilityGroup, this will be done there after AG is created.
                        if ($SeedingMode -eq "Automatic" -and $InputObject.State -eq 'Existing') {
                            if ($Pscmdlet.ShouldProcess($second.Name, "Granting CreateAnyDatabase permission to the availability group")) {
                                try {
                                    $null = Grant-DbaAgPermission -SqlInstance $server -Type AvailabilityGroup -AvailabilityGroup $InputObject.Name -Permission CreateAnyDatabase -EnableException
                                } catch {
                                    Stop-Function -Message "Failure granting CreateAnyDatabase permission to the availability group" -ErrorRecord $_
                                }
                            }
                        }
                        # In case a certificate is used, the endpoint is owned by the certificate and this step is not needed and in most cases not possible as the instance does not run under a domain account.
                        if (-not $Certificate) {
                            $serviceAccount = $server.ServiceAccount
                            if ($Pscmdlet.ShouldProcess($second.Name, "Granting Connect permission for the endpoint to service account $serviceAccount")) {
                                try {
                                    $null = Grant-DbaAgPermission -SqlInstance $server -Type Endpoint -Login $serviceAccount -Permission Connect -EnableException
                                } catch {
                                    Stop-Function -Message "Failure granting Connect permission for the endpoint to service account $serviceAccount" -ErrorRecord $_
                                }
                            }
                        }
                    }

                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name ComputerName -Value $agreplica.Parent.ComputerName
                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name InstanceName -Value $agreplica.Parent.InstanceName
                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name SqlInstance -Value $agreplica.Parent.SqlInstance
                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name AvailabilityGroup -Value $agreplica.Parent.Name
                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name Replica -Value $agreplica.Name # backwards compat

                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'AvailabilityGroup', 'Name', 'Role', 'RollupSynchronizationState', 'AvailabilityMode', 'BackupPriority', 'EndpointUrl', 'SessionTimeout', 'FailoverMode', 'ReadonlyRoutingList'
                    Select-DefaultView -InputObject $agreplica -Property $defaults
                } catch {
                    $msg = $_.Exception.InnerException.InnerException.Message
                    if (-not $msg) {
                        $msg = $_
                    }
                    Stop-Function -Message $msg -ErrorRecord $_ -Continue
                }
            }
        }
    }
}