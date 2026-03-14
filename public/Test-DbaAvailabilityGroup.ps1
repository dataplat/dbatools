function Test-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Validates Availability Group replica connectivity and database prerequisites for AG operations

    .DESCRIPTION
        Verifies that all replicas in an Availability Group are connected and communicating properly by checking ConnectionState across all replicas from the primary's perspective. This helps you identify connectivity issues that could impact failover capabilities or data synchronization.

        When used with the AddDatabase parameter, performs comprehensive prerequisite validation before adding databases to an AG. Checks that target databases have Full recovery model, Normal status, and proper backup history. Also validates seeding mode compatibility, tests connectivity to secondary replicas, and ensures database restore requirements can be met.

        This prevents common AG setup failures by catching configuration issues early, so you don't have to troubleshoot failed Add-DbaAgDatabase operations later.

    .PARAMETER SqlInstance
        The primary replica of the Availability Group.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies the Availability Group name to validate for replica connectivity and database prerequisites.
        Use this to target a specific AG when testing health status or preparing to add databases.

    .PARAMETER Secondary
        Specifies secondary replica endpoints when they use non-standard ports or custom connection strings.
        The function auto-discovers secondary replicas from the AG configuration, but use this when replicas listen on custom ports or require specific connection parameters.

    .PARAMETER SecondarySqlCredential
        Specifies credentials for connecting to secondary replica instances during validation.
        Use this when secondary replicas require different authentication than the primary replica, such as in cross-domain scenarios or when using SQL authentication on secondaries.

    .PARAMETER AddDatabase
        Specifies database names to validate for Availability Group addition prerequisites.
        Triggers comprehensive validation including recovery model, database status, backup history, and seeding compatibility checks. Use this to prevent Add-DbaAgDatabase failures by catching configuration issues early.

    .PARAMETER SeedingMode
        Specifies the database seeding method for validation when using AddDatabase parameter.
        Use 'Automatic' for SQL Server 2016+ environments or 'Manual' when you need to control backup/restore operations. This determines the prerequisite validation logic performed.

    .PARAMETER SharedPath
        Specifies the network path accessible by all replicas for backup and restore operations during manual seeding validation.
        Required when AddDatabase uses manual seeding and databases need to be restored on secondary replicas. Must be accessible by all SQL Server service accounts.

    .PARAMETER UseLastBackup
        Validates that the most recent database backup chain can be used for AG database addition.
        Enables validation using existing backups instead of creating new ones, but requires the last backup to be a transaction log backup. Use this to test AG readiness with your current backup strategy.

    .PARAMETER Policy
        Evaluates all 13 predefined Always On Availability Group policies as defined by Microsoft's Policy-Based Management
        framework. See https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-policies-for-operational-issues-always-on-availability

        When specified, the function tests each policy condition and returns one object per policy check with the result.

        The policies are grouped by facet:
        - Server: WSFC cluster state (Critical)
        - Availability group: online state, automatic failover readiness, replica connection state, replica data
          synchronization state, replica role state, synchronous replica data synchronization state
        - Availability replica: replica role state, join state, data synchronization state
        - Availability database: suspension state, data synchronization state, join state

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG, Test
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaAvailabilityGroup

    .OUTPUTS
        PSCustomObject

        With the -Policy parameter, returns one object per policy check with the following properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - AvailabilityGroup: The name of the Availability Group being tested
        - PolicyName: The name of the Always On policy being evaluated
        - Category: Severity of the policy - Critical or Warning
        - Facet: The SMO facet the policy applies to - Server, Availability group, Availability replica, or Availability database
        - Status: Result of the policy check - Healthy or Unhealthy
        - Issue: The human-readable issue description from Microsoft documentation
        - Details: Specific values found during the check

        Without the -AddDatabase parameter, returns one object per Availability Group tested with the following properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - AvailabilityGroup: The name of the Availability Group being tested

        With the -AddDatabase parameter, returns one object per database being added with the following properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - AvailabilityGroupName: The name of the Availability Group
        - DatabaseName: The name of the database being added to the AG
        - AvailabilityGroupSMO: The Microsoft.SqlServer.Management.Smo.AvailabilityGroup object for the AG
        - DatabaseSMO: The Microsoft.SqlServer.Management.Smo.Database object for the database
        - PrimaryServerSMO: The Microsoft.SqlServer.Management.Smo.Server object for the primary replica
        - ReplicaServerSMO: A hashtable mapping secondary replica names to their Microsoft.SqlServer.Management.Smo.Server objects
        - RestoreNeeded: A hashtable mapping replica names to boolean values indicating if database restore is needed on that replica
        - Backups: An array of backup history objects from Get-DbaDbBackupHistory (when -UseLastBackup is specified)

    .EXAMPLE
        PS C:\> Test-DbaAvailabilityGroup -SqlInstance SQL2016 -AvailabilityGroup TestAG1 -Policy

        Evaluates all 13 Always On policies for Availability Group TestAG1 on SQL2016.

    .EXAMPLE
        PS C:\> Test-DbaAvailabilityGroup -SqlInstance SQL2016 -AvailabilityGroup TestAG1 -Policy | Where-Object Status -eq Unhealthy

        Shows only unhealthy policy results for Availability Group TestAG1.

    .EXAMPLE
        PS C:\> Test-DbaAvailabilityGroup -SqlInstance SQL2016 -AvailabilityGroup TestAG1

        Test Availability Group TestAG1 with SQL2016 as the primary replica.

    .EXAMPLE
        PS C:\> Test-DbaAvailabilityGroup -SqlInstance SQL2016 -AvailabilityGroup TestAG1 -AddDatabase AdventureWorks -SeedingMode Automatic

        Test if database AdventureWorks can be added to the Availability Group TestAG1 with automatic seeding.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory = $true)]
        [string]$AvailabilityGroup,
        [DbaInstanceParameter[]]$Secondary,
        [PSCredential]$SecondarySqlCredential,
        [string[]]$AddDatabase,
        [ValidateSet('Automatic', 'Manual')]
        [string]$SeedingMode,
        [string]$SharedPath,
        [switch]$UseLastBackup,
        [switch]$Policy,
        [switch]$EnableException
    )
    process {
        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }

        try {
            $ag = Get-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $AvailabilityGroup -EnableException
        } catch {
            Stop-Function -Message "Availability Group $AvailabilityGroup not found on $server." -ErrorRecord $_
            return
        }

        if (-not $ag) {
            Stop-Function -Message "Availability Group $AvailabilityGroup not found on $server."
            return
        }

        if ($ag.LocalReplicaRole -ne 'Primary') {
            Stop-Function -Message "LocalReplicaRole of replica $server is not Primary, but $($ag.LocalReplicaRole). Please connect to the current primary replica $($ag.PrimaryReplica)."
            return
        }

        if ($Policy) {
            # Implements the 13 Always On Availability Group policies from Microsoft's Policy-Based Management framework.
            # Source: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-policies-for-operational-issues-always-on-availability
            # Conditions verified via: Get-DbaPbmCondition -SqlInstance <instance> -IncludeSystemObject | Where-Object Name -Match AlwaysOn

            # Policy: WSFC Cluster State (Critical, Server facet)
            # AlwaysOnAgWSFClusterHealthCondition: @ClusterQuorumState = Enum('...ClusterQuorumState', 'NormalQuorum')
            $wsfcStatus = if ($server.ClusterQuorumState -eq "NormalQuorum") { "Healthy" } else { "Unhealthy" }
            [PSCustomObject]@{
                ComputerName      = $server.ComputerName
                InstanceName      = $server.InstanceName
                SqlInstance       = $server.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "WSFC Cluster State"
                Category          = "Critical"
                Facet             = "Server"
                Status            = $wsfcStatus
                Issue             = "WSFC cluster service is offline."
                Details           = "ClusterQuorumState is $($server.ClusterQuorumState)"
            }

            # Get AG state object for all IAvailabilityGroupState facet policies
            $agState = New-Object -TypeName "Microsoft.SqlServer.Management.Smo.AvailabilityGroupState" -ArgumentList $ag

            # Policy: Availability Group Online State (Critical, Availability group facet)
            # AlwaysOnAgOnlineStateHealthCondition: @IsOnline = True()
            $agOnlineStatus = if ($agState.IsOnline) { "Healthy" } else { "Unhealthy" }
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "Availability Group Online State"
                Category          = "Critical"
                Facet             = "Availability group"
                Status            = $agOnlineStatus
                Issue             = "Availability group is offline."
                Details           = "IsOnline is $($agState.IsOnline)"
            }

            # Policy: Availability Group Automatic Failover Readiness (Critical, Availability group facet)
            # AlwaysOnAgAutomaticFailoverHealthCondition: (@IsAutoFailover = True() AND @NumberOfSynchronizedSecondaryReplicas > 0) OR @IsAutoFailover = False()
            $autoFailoverHealthy = (-not $agState.IsAutoFailover) -or ($agState.NumberOfSynchronizedSecondaryReplicas -gt 0)
            $autoFailoverStatus = if ($autoFailoverHealthy) { "Healthy" } else { "Unhealthy" }
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "Availability Group Automatic Failover Readiness"
                Category          = "Critical"
                Facet             = "Availability group"
                Status            = $autoFailoverStatus
                Issue             = "Availability group is not ready for automatic failover."
                Details           = "IsAutoFailover is $($agState.IsAutoFailover), NumberOfSynchronizedSecondaryReplicas is $($agState.NumberOfSynchronizedSecondaryReplicas)"
            }

            # Policy: Availability Replicas Connection State (Warning, Availability group facet)
            # AlwaysOnAgReplicasConnectionHealthCondition: @NumberOfDisconnectedReplicas = 0
            $replicasConnStatus = if ($agState.NumberOfDisconnectedReplicas -eq 0) { "Healthy" } else { "Unhealthy" }
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "Availability Replicas Connection State"
                Category          = "Warning"
                Facet             = "Availability group"
                Status            = $replicasConnStatus
                Issue             = "Some availability replicas are disconnected."
                Details           = "NumberOfDisconnectedReplicas is $($agState.NumberOfDisconnectedReplicas)"
            }

            # Policy: Availability Replicas Data Synchronization State (Warning, Availability group facet)
            # AlwaysOnAgReplicasDataSynchronizationHealthCondition: @NumberOfNotSynchronizingReplicas = 0
            $replicasSyncStatus = if ($agState.NumberOfNotSynchronizingReplicas -eq 0) { "Healthy" } else { "Unhealthy" }
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "Availability Replicas Data Synchronization State"
                Category          = "Warning"
                Facet             = "Availability group"
                Status            = $replicasSyncStatus
                Issue             = "Some availability replicas are not synchronizing data."
                Details           = "NumberOfNotSynchronizingReplicas is $($agState.NumberOfNotSynchronizingReplicas)"
            }

            # Policy: Availability Replicas Role State (Warning, Availability group facet)
            # AlwaysOnAgReplicasRoleHealthCondition: @NumberOfReplicasWithUnhealthyRole = 0
            $replicasRoleStatus = if ($agState.NumberOfReplicasWithUnhealthyRole -eq 0) { "Healthy" } else { "Unhealthy" }
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "Availability Replicas Role State"
                Category          = "Warning"
                Facet             = "Availability group"
                Status            = $replicasRoleStatus
                Issue             = "Some availability replicas do not have a healthy role."
                Details           = "NumberOfReplicasWithUnhealthyRole is $($agState.NumberOfReplicasWithUnhealthyRole)"
            }

            # Policy: Synchronous Replicas Data Synchronization State (Warning, Availability group facet)
            # AlwaysOnAgSynchronousReplicasDataSynchronizationHealthCondition: @NumberOfNotSynchronizedReplicas = 0
            $syncReplicasStatus = if ($agState.NumberOfNotSynchronizedReplicas -eq 0) { "Healthy" } else { "Unhealthy" }
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                PolicyName        = "Synchronous Replicas Data Synchronization State"
                Category          = "Warning"
                Facet             = "Availability group"
                Status            = $syncReplicasStatus
                Issue             = "Some synchronous replicas are not synchronized."
                Details           = "NumberOfNotSynchronizedReplicas is $($agState.NumberOfNotSynchronizedReplicas)"
            }

            # Replica-level policies (one result per replica per policy)
            foreach ($replica in $ag.AvailabilityReplicas) {
                # Policy: Availability Replica Role State (Critical, Availability replica facet)
                # AlwaysOnArRoleHealthCondition: @Role = Primary OR @Role = Secondary
                $replicaRoleHealthy = $replica.Role -eq "Primary" -or $replica.Role -eq "Secondary"
                $replicaRoleStatus = if ($replicaRoleHealthy) { "Healthy" } else { "Unhealthy" }
                [PSCustomObject]@{
                    ComputerName      = $ag.ComputerName
                    InstanceName      = $ag.InstanceName
                    SqlInstance       = $ag.SqlInstance
                    AvailabilityGroup = $ag.Name
                    PolicyName        = "Availability Replica Role State"
                    Category          = "Critical"
                    Facet             = "Availability replica"
                    Status            = $replicaRoleStatus
                    Issue             = "Availability replica does not have a healthy role."
                    Details           = "Replica $($replica.Name): Role is $($replica.Role)"
                }

                # Policy: Availability Replica Join State (Warning, Availability replica facet)
                # AlwaysOnArJoinStateHealthCondition: @JoinState != Enum('...AvailabilityReplicaJoinState', 'NotJoined')
                $replicaJoinStatus = if ($replica.JoinState -ne "NotJoined") { "Healthy" } else { "Unhealthy" }
                [PSCustomObject]@{
                    ComputerName      = $ag.ComputerName
                    InstanceName      = $ag.InstanceName
                    SqlInstance       = $ag.SqlInstance
                    AvailabilityGroup = $ag.Name
                    PolicyName        = "Availability Replica Join State"
                    Category          = "Warning"
                    Facet             = "Availability replica"
                    Status            = $replicaJoinStatus
                    Issue             = "Availability Replica is not joined."
                    Details           = "Replica $($replica.Name): JoinState is $($replica.JoinState)"
                }

                # Policy: Availability Replica Data Synchronization State (Warning, Availability replica facet)
                # AlwaysOnArDataSynchronizationHealthCondition:
                #   ((@AvailabilityMode = AsynchronousCommit AND (@RollupSynchronizationState = Synchronizing OR @RollupSynchronizationState = Synchronized)) OR @RollupSynchronizationState = Synchronized)
                $replicaSyncHealthy = ($replica.AvailabilityMode -eq "AsynchronousCommit" -and ($replica.RollupSynchronizationState -eq "Synchronizing" -or $replica.RollupSynchronizationState -eq "Synchronized")) -or $replica.RollupSynchronizationState -eq "Synchronized"
                $replicaSyncStatus = if ($replicaSyncHealthy) { "Healthy" } else { "Unhealthy" }
                [PSCustomObject]@{
                    ComputerName      = $ag.ComputerName
                    InstanceName      = $ag.InstanceName
                    SqlInstance       = $ag.SqlInstance
                    AvailabilityGroup = $ag.Name
                    PolicyName        = "Availability Replica Data Synchronization State"
                    Category          = "Warning"
                    Facet             = "Availability replica"
                    Status            = $replicaSyncStatus
                    Issue             = "Data synchronization state of some availability database is not healthy."
                    Details           = "Replica $($replica.Name): AvailabilityMode is $($replica.AvailabilityMode), RollupSynchronizationState is $($replica.RollupSynchronizationState)"
                }
            }

            # Database-level policies (one result per database per replica per policy)
            # Uses Get-DbaAgDatabaseReplicaState which wraps DatabaseReplicaState SMO objects
            $dbReplicaStates = Get-DbaAgDatabaseReplicaState -InputObject $ag

            foreach ($dbState in $dbReplicaStates) {
                # Policy: Availability Database Suspension State (Warning, Availability database facet)
                # AlwaysOnDbrSuspendStateCondition: @IsSuspended = False()
                $dbSuspendStatus = if (-not $dbState.IsSuspended) { "Healthy" } else { "Unhealthy" }
                [PSCustomObject]@{
                    ComputerName      = $ag.ComputerName
                    InstanceName      = $ag.InstanceName
                    SqlInstance       = $ag.SqlInstance
                    AvailabilityGroup = $ag.Name
                    PolicyName        = "Availability Database Suspension State"
                    Category          = "Warning"
                    Facet             = "Availability database"
                    Status            = $dbSuspendStatus
                    Issue             = "Availability database is suspended."
                    Details           = "Database $($dbState.DatabaseName) on replica $($dbState.ReplicaServerName): IsSuspended is $($dbState.IsSuspended)"
                }

                # Policy: Availability Database Data Synchronization State (Warning, Availability database facet)
                # AlwaysOnDbrDataSynchronizationCondition:
                #   ((@ReplicaAvailabilityMode = AsynchronousCommit AND @SynchronizationState != NotSynchronizing) OR @SynchronizationState = Synchronized)
                $dbSyncHealthy = ($dbState.ReplicaAvailabilityMode -eq "AsynchronousCommit" -and $dbState.SynchronizationState -ne "NotSynchronizing") -or $dbState.SynchronizationState -eq "Synchronized"
                $dbSyncStatus = if ($dbSyncHealthy) { "Healthy" } else { "Unhealthy" }
                [PSCustomObject]@{
                    ComputerName      = $ag.ComputerName
                    InstanceName      = $ag.InstanceName
                    SqlInstance       = $ag.SqlInstance
                    AvailabilityGroup = $ag.Name
                    PolicyName        = "Availability Database Data Synchronization State"
                    Category          = "Warning"
                    Facet             = "Availability database"
                    Status            = $dbSyncStatus
                    Issue             = "Data synchronization state of availability database is not healthy."
                    Details           = "Database $($dbState.DatabaseName) on replica $($dbState.ReplicaServerName): ReplicaAvailabilityMode is $($dbState.ReplicaAvailabilityMode), SynchronizationState is $($dbState.SynchronizationState)"
                }

                # Policy: Availability Database Join State (Warning, Availability database facet)
                # AlwaysOnDbrJoinStateCondition: @IsJoined = True()
                $dbJoinStatus = if ($dbState.IsJoined) { "Healthy" } else { "Unhealthy" }
                [PSCustomObject]@{
                    ComputerName      = $ag.ComputerName
                    InstanceName      = $ag.InstanceName
                    SqlInstance       = $ag.SqlInstance
                    AvailabilityGroup = $ag.Name
                    PolicyName        = "Availability Database Join State"
                    Category          = "Warning"
                    Facet             = "Availability database"
                    Status            = $dbJoinStatus
                    Issue             = "Secondary database is not joined."
                    Details           = "Database $($dbState.DatabaseName) on replica $($dbState.ReplicaServerName): IsJoined is $($dbState.IsJoined)"
                }
            }
            return
        }

        # Test for health of Availability Group

        # Later: Get replica and database states like in SSMS dashboard
        # Now: Just test for ConnectionState -eq 'Connected'

        # Note on further development:
        # As long as there are no databases in the Availability Group, test for RollupSynchronizationState is not useful

        # The primary replica always has the best information about all the replicas.
        # We can maybe also connect to the secondary replicas and test their view of the situation, but then only test the local replica.

        $failure = $false
        foreach ($replica in $ag.AvailabilityReplicas) {
            if ($replica.ConnectionState -ne 'Connected') {
                $failure = $true
                Stop-Function -Message "ConnectionState of replica $replica is not Connected, but $($replica.ConnectionState)." -Continue
            }
        }
        if ($failure) {
            Stop-Function -Message "ConnectionState of one or more replicas is not Connected."
            return
        }


        # For now, just output the base information.

        if (-not $AddDatabase) {
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.AvailabilityGroup
            }
        }


        # Test for Add-DbaAgDatabase

        foreach ($dbName in $AddDatabase) {
            $db = $server.Databases[$dbName]

            if ($SeedingMode -eq 'Automatic' -and $server.VersionMajor -lt 13) {
                Stop-Function -Message "Automatic seeding mode only supported in SQL Server 2016 and above" -Target $server
                return
            }

            if (-not $db) {
                Stop-Function -Message "Database [$dbName] is not found on $server." -Continue
            }

            $null = $db.Refresh()

            if ($db.RecoveryModel -ne 'Full') {
                Stop-Function -Message "RecoveryModel of database $db is not Full, but $($db.RecoveryModel)." -Continue
            }

            if ($db.Status -ne 'Normal') {
                Stop-Function -Message "Status of database $db is not Normal, but $($db.Status)." -Continue
            }

            $backups = @( )
            if ($UseLastBackup) {
                try {
                    $backups = Get-DbaDbBackupHistory -SqlInstance $server -Database $db.Name -IncludeCopyOnly -Last -EnableException
                } catch {
                    Stop-Function -Message "Failed to get backup history for database $db." -ErrorRecord $_ -Continue
                }
                if ($backups.Type -notcontains 'Log') {
                    Stop-Function -Message "Cannot use last backup for database $db. A log backup must be the last backup taken." -Continue
                }
            }

            if ($SeedingMode -eq 'Automatic' -and $server.VersionMajor -lt 13) {
                Stop-Function -Message "Automatic seeding mode only supported in SQL Server 2016 and above." -Continue
            }

            # Try to connect to secondary replicas as soon as possible to fail the command before making any changes to the Availability Group.
            # Also test if these are really secondary replicas for that availability group. Only needed if -Secondary is used, but will do it anyway to simplify code.
            # Also test if database is already at the secondary and if so if Status is Restoring.
            # We store the server SMO in a hashtable based on the DomainInstanceName of the server as this is equal to the name of the replica in $ag.AvailabilityReplicas.
            if ($Secondary) {
                $secondaryReplicas = $Secondary
            } else {
                $secondaryReplicas = ($ag.AvailabilityReplicas | Where-Object { $_.Role -eq 'Secondary' }).Name
            }

            $replicaServerSMO = @{ }
            $restoreNeeded = @{ }
            $backupNeeded = $false
            $failure = $false
            foreach ($replica in $secondaryReplicas) {
                try {
                    $replicaServer = Connect-DbaInstance -SqlInstance $replica -SqlCredential $SecondarySqlCredential
                } catch {
                    $failure = $true
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $replica -Continue
                }

                try {
                    $replicaAg = Get-DbaAvailabilityGroup -SqlInstance $replicaServer -AvailabilityGroup $AvailabilityGroup -EnableException
                    $replicaName = $replicaAg.Parent.DomainInstanceName
                } catch {
                    $failure = $true
                    Stop-Function -Message "Availability Group $AvailabilityGroup not found on replica $replicaServer." -ErrorRecord $_ -Continue
                }

                if (-not $replicaAg) {
                    $failure = $true
                    Stop-Function -Message "Availability Group $AvailabilityGroup not found on replica $replicaServer." -Continue
                }

                if ($replicaAg.LocalReplicaRole -ne 'Secondary') {
                    $failure = $true
                    Stop-Function -Message "LocalReplicaRole of replica $replicaServer is not Secondary, but $($replicaAg.LocalReplicaRole)." -Continue
                }

                $replicaDb = $replicaAg.Parent.Databases[$db.Name]

                if ($replicaDb) {
                    # Database already present on replica, so test if already joined or if we can use it.
                    if ($replicaDb.AvailabilityGroupName -eq $AvailabilityGroup) {
                        Write-Message -Level Verbose -Message "Database $db is already part of the Availability Group on replica $replicaName."
                    } else {
                        if ($replicaDb.Status -ne 'Restoring') {
                            $failure = $true
                            Stop-Function -Message "Status of database $db on replica $replicaName is not Restoring, but $($replicaDb.Status)" -Continue
                        }
                        if ($UseLastBackup) {
                            $failure = $true
                            Stop-Function -Message "Database $db is already present on $replicaName, so -UseLastBackup must not be used. Please remove database from replica to use -UseLastBackup." -Continue
                        }
                        Write-Message -Level Verbose -Message "Database $db is already present in restoring status on replica $replicaName."
                    }
                } else {
                    # No database on replica, so test if we need a backup.
                    # We need to restore a backup if the desired or the current seeding mode is manual.
                    # To have a detailed verbose message, we test in small steps.
                    if ($SeedingMode -eq 'Automatic') {
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -eq 'Automatic') {
                            Write-Message -Level Verbose -Message "Database $db will use automatic seeding on replica $replicaName. The replica is already configured accordingly."
                        } else {
                            Write-Message -Level Verbose -Message "Database $db will use automatic seeding on replica $replicaName. The replica will be configured accordingly."
                        }
                        if ($db.LastBackupDate.Year -eq 1) {
                            # Automatic seeding only works with databases that are really in RecoveryModel Full, so a full backup has been taken.
                            Write-Message -Level Verbose -Message "Database $db will need a backup first. This is ok if one of the other replicas uses manual seeding."
                            $backupNeeded = $true
                        }
                    } elseif ($SeedingMode -eq 'Manual') {
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -eq 'Manual') {
                            Write-Message -Level Verbose -Message "Database $db will need a restore on replica $replicaName. The replica is already configured accordingly."
                        } else {
                            Write-Message -Level Verbose -Message "Database $db will need a restore on replica $replicaName. The replica will be configured accordingly."
                        }
                        $restoreNeeded[$replicaName] = $true
                    } else {
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -eq 'Automatic') {
                            Write-Message -Level Verbose -Message "Database $db will use automatic seeding on replica $replicaName."
                            if ($db.LastBackupDate.Year -eq 1) {
                                # Automatic seeding only works with databases that are really in RecoveryModel Full, so a full backup has been taken.
                                Write-Message -Level Verbose -Message "Database $db will need a backup first. This is ok if one of the other replicas uses manual seeding."
                                $backupNeeded = $true
                            }
                        } else {
                            Write-Message -Level Verbose -Message "Database $db will need a restore on replica $replicaName."
                            $restoreNeeded[$replicaName] = $true
                        }
                    }
                }
                $replicaServerSMO[$replicaName] = $replicaAg.Parent
            }
            if ($failure) {
                Stop-Function -Message "Availability Group $AvailabilityGroup or database $db not found in suitable state on all secondary replicas." -Continue
            }
            if ($restoreNeeded.Count -gt 0 -and -not $SharedPath -and -not $UseLastBackup) {
                Stop-Function -Message "A restore of database $db is needed on one or more replicas, but -SharedPath or -UseLastBackup are missing." -Continue
            }
            if ($backupNeeded -and $restoreNeeded.Count -eq 0) {
                Stop-Function -Message "All replicas are configured to use automatic seeding, but the database $db was never backed up. Please backup the database or use manual seeding." -Continue
            }

            [PSCustomObject]@{
                ComputerName          = $ag.ComputerName
                InstanceName          = $ag.InstanceName
                SqlInstance           = $ag.SqlInstance
                AvailabilityGroupName = $ag.Name
                DatabaseName          = $db.Name
                AvailabilityGroupSMO  = $ag
                DatabaseSMO           = $db
                PrimaryServerSMO      = $server
                ReplicaServerSMO      = $replicaServerSMO
                RestoreNeeded         = $restoreNeeded
                Backups               = $backups
            }
        }
    }
}
