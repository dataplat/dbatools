function Add-DbaAgDatabase {
    <#
    .SYNOPSIS
        Adds databases to an Availability Group with automated backup, restore, and synchronization handling.

    .DESCRIPTION
        Adds databases to an Availability Group and handles the complete process from backup through synchronization. This command eliminates the manual steps typically required when expanding Availability Groups with new databases, automatically managing seeding modes, backup/restore operations, and replica synchronization.

        The command executes a comprehensive five-step process for each database:
        * Step 1: Setting seeding mode if needed.
          - If -SeedingMode is used and the current seeding mode of the replica is not in the desired mode, the seeding mode of the replica is changed.
          - The seeding mode will not be changed back but stay in this mode.
          - If the seeding mode is changed to Automatic, the necessary rights to create databases will be granted.
        * Step 2: Running backup and restore if needed.
          - Action is only taken for replicas with a desired seeding mode of Manual and where the database does not yet exist.
          - If -UseLastBackup is used, the restore will be performed based on the backup history of the database.
          - Otherwise a full and log backup will be taken at the primary and those will be restored at the replica using the same folder structure.
        * Step 3: Add the database to the Availability Group on the primary replica.
          - This step is skipped, if the database is already part of the Availability Group.
        * Step 4: Add the database to the Availability Group on the secondary replicas.
          - This step is skipped for those replicas, where the database is already joined to the Availability Group.
        * Step 5: Wait for the database to finish joining the Availability Group on the secondary replicas.

        Use Test-DbaAvailabilityGroup with -AddDatabase to test if all prerequisites are met before running this command.

        For custom backup and restore requirements, perform those operations with Backup-DbaDatabase and Restore-DbaDatabase in advance, ensuring the last log backup has been restored before running Add-DbaAgDatabase.

    .PARAMETER SqlInstance
        The primary replica of the Availability Group. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to add to the Availability Group. Accepts single database names, arrays, or wildcard patterns.
        Use this when you need to add specific databases rather than piping database objects from Get-DbaDatabase.

    .PARAMETER AvailabilityGroup
        Specifies the target Availability Group name where databases will be added. The AG must already exist and be configured.
        Use this to identify which existing Availability Group should receive the new database members.

    .PARAMETER Secondary
        Specifies secondary replica instances to target for database addition. Auto-discovered if not specified.
        Use this when replicas use non-standard ports or when you want to limit the operation to specific secondary replicas rather than all replicas in the AG.

    .PARAMETER SecondarySqlCredential
        Authentication credentials for connecting to secondary replica instances when they require different credentials than the primary.
        Use this when secondary replicas are in different domains, use SQL authentication, or require service accounts with specific permissions for backup/restore operations.

    .PARAMETER InputObject
        Accepts database objects from pipeline input, typically from Get-DbaDatabase or Get-DbaDbSharePoint.
        Use this for workflow scenarios where you want to filter databases first, then pipe the results directly into the AG addition process.

    .PARAMETER SeedingMode
        Controls how database data is transferred to secondary replicas during AG addition. Valid values are 'Automatic' or 'Manual'.
        Automatic seeding transfers data directly over the network without requiring backup/restore operations, but needs sufficient network bandwidth and proper endpoint configuration.
        Manual seeding uses traditional backup/restore through shared storage, giving you more control over timing and storage location but requiring accessible file shares.

    .PARAMETER SharedPath
        Specifies the UNC network path where backups are stored during manual seeding operations. Required when using Manual seeding mode.
        All SQL Server service accounts from primary and secondary replicas must have read/write access to this location. Backup files remain on the share after completion for potential reuse or cleanup.

    .PARAMETER UseLastBackup
        Uses existing backup history instead of creating new backups for manual seeding. The most recent log backup must be newer than the most recent full backup.
        Use this when you have recent backups available and want to avoid taking additional backups, reducing backup storage requirements and time.

    .PARAMETER AdvancedBackupParams
        Passes additional parameters to Backup-DbaDatabase as a hashtable when creating backups during manual seeding.
        Use this to control backup compression, file count, or other backup-specific settings like @{CompressBackup=$true; FileCount=4} for faster backup operations.

    .PARAMETER NoWait
        Skips waiting for the database seeding and synchronization to complete on secondary replicas (Step 5).
        The underlying SQL command ALTER AVAILABILITY GROUP ... ADD DATABASE is immediate and does not wait for seeding to finish.
        Use this when you want the command to return immediately after adding the database to the AG, allowing seeding to continue in the background.
        This is particularly useful in deployments where seeding can take a long time and you want to start using the environment before synchronization completes.

    .PARAMETER SkipReuseSourceFolderStructure
        Prevents restores from using the source server's folder structure when restoring databases to secondary replicas.
        When enabled, Restore-DbaDatabase uses the replica's default data and log directories instead of attempting to replicate the primary's folder structure.
        This is automatically set to true when the primary and replica servers run on different operating system platforms (e.g., Windows primary with Linux replica).

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
        Author: Chrissy LeMaire (@cl), netnerds.net | Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaAgDatabase

    .EXAMPLE
        PS C:\> Add-DbaAgDatabase -SqlInstance sql2017a -AvailabilityGroup ag1 -Database db1, db2 -Confirm

        Adds db1 and db2 to ag1 on sql2017a. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017a | Out-GridView -Passthru | Add-DbaAgDatabase -AvailabilityGroup ag1

        Adds selected databases from sql2017a to ag1

    .EXAMPLE
        PS C:\> Get-DbaDbSharePoint -SqlInstance sqlcluster | Add-DbaAgDatabase -AvailabilityGroup SharePoint

        Adds SharePoint databases as found in SharePoint_Config on sqlcluster to ag1 on sqlcluster

    .EXAMPLE
        PS C:\> Get-DbaDbSharePoint -SqlInstance sqlcluster -ConfigDatabase SharePoint_Config_2019 | Add-DbaAgDatabase -AvailabilityGroup SharePoint

        Adds SharePoint databases as found in SharePoint_Config_2019 on sqlcluster to ag1 on sqlcluster

    .EXAMPLE
        PS C:\> $adv_param = @{
        >>    CompressBackup = $true
        >>    FileCount = 3
        >> }
        PS C:\> $splat = @{
        >>   SqlInstance = 'sql2017a'
        >>   AvailabilityGroup = 'ag1'
        >>   Database = 'db1'
        >>   Secondary = 'sql2017b'
        >>   SeedingMode = 'Manual'
        >>   SharedPath = '\\FS\Backup'
        >> }
        PS C:\> Add-DbaAgDatabase @splat -AdvancedBackupParams $adv_param

        Adds db1 to ag1 on sql2017a and sql2017b. Uses compression and three files while taking the backups.

    .EXAMPLE
        PS C:\> Add-DbaAgDatabase -SqlInstance sql2017a -AvailabilityGroup ag1 -Database db1 -NoWait

        Adds db1 to ag1 on sql2017a and returns immediately without waiting for seeding to complete on secondary replicas. Seeding will continue in the background.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.AvailabilityDatabase

        Returns one AvailabilityDatabase object per replica where the database was added. For example, adding one database to an AG with two replicas returns two objects - one for the primary and one for each secondary.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - AvailabilityGroup: Name of the availability group
        - LocalReplicaRole: Role of this replica (Primary or Secondary)
        - Name: Database name
        - SynchronizationState: Current synchronization state (NotSynchronizing, Synchronizing, Synchronized, Reverting, Initializing)
        - IsFailoverReady: Boolean indicating if the database is ready for failover
        - IsJoined: Boolean indicating if the database has joined the availability group
        - IsSuspended: Boolean indicating if data movement is suspended

        Additional properties available (from SMO AvailabilityDatabase object):
        - DatabaseGuid: Unique identifier for the database
        - EstimatedDataLoss: Estimated data loss in seconds
        - EstimatedRecoveryTime: Estimated recovery time in seconds
        - FileStreamSendRate: Rate of FILESTREAM data being sent (bytes/sec)
        - GroupDatabaseId: Unique identifier for the database within the AG
        - ID: Internal object ID
        - IsAvailabilityDatabaseSuspended: Boolean indicating suspension state
        - IsDatabaseDiskHealthy: Boolean indicating if database disk health is good
        - IsDatabaseJoined: Boolean indicating database join state
        - IsInstanceDiskHealthy: Boolean indicating if instance disk health is good
        - IsInstanceHealthy: Boolean indicating overall instance health
        - IsPendingSecondarySuspend: Boolean indicating if secondary suspend is pending
        - LastCommitLsn: Last commit log sequence number
        - LastCommitTime: Timestamp of last committed transaction
        - LastHardenedLsn: Last hardened log sequence number
        - LastHardenedTime: Timestamp when last LSN was hardened
        - LastReceivedLsn: Last received log sequence number
        - LastReceivedTime: Timestamp when last LSN was received
        - LastRedoneLsn: Last redone log sequence number
        - LastRedoneTime: Timestamp when last LSN was redone
        - LastSentLsn: Last sent log sequence number
        - LastSentTime: Timestamp when last LSN was sent
        - LogSendQueue: Size of log send queue in KB
        - LogSendRate: Rate of log sending (bytes/sec)
        - LowWaterMarkForGhostCleanup: Low water mark LSN for ghost cleanup
        - Parent: Reference to parent AvailabilityGroup SMO object
        - RecoveryLsn: Recovery log sequence number
        - RedoQueue: Size of redo queue in KB
        - RedoRate: Rate of redo operations (bytes/sec)
        - SecondaryLagSeconds: Lag in seconds for secondary replica
        - State: SMO object state (Existing, Creating, Pending, etc.)
        - SuspendReason: Reason for suspension if database is suspended
        - Urn: Uniform Resource Name for the SMO object
        - UserAccess: User access state

        All properties from the base SMO object are accessible even though only default properties are displayed without using Select-Object *.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [PSCredential]$SqlCredential,
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true)]
        [Parameter(ParameterSetName = 'Pipeline', Mandatory = $true, Position = 0)]
        [string]$AvailabilityGroup,
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true)]
        [string[]]$Database,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [DbaInstanceParameter[]]$Secondary,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [PSCredential]$SecondarySqlCredential,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [ValidateSet('Automatic', 'Manual')]
        [string]$SeedingMode,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [string]$SharedPath,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [switch]$UseLastBackup,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [hashtable]$AdvancedBackupParams,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [switch]$NoWait,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [switch]$SkipReuseSourceFolderStructure,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        # We have three while loops, that need a timeout to not loop forever if somethings goes wrong:
        # while ($agDb.State -ne 'Existing')         - should only take milliseconds, so we set a default timeout of one minute
        # while ($replicaAgDb.State -ne 'Existing')  - should only take milliseconds, so we set a default timeout of one minute
        # while ($stillWaiting)                      - can take a long time with automatic seeding, but progress is displayed, so we set a default timeout of one day
        # We will use two timeout configuration values, as we don't want to add more timeout parameters to the command. We will store the timeouts in seconds.
        # The timeout for synchronization can be set to a lower value to end the command even when the synchronization is not finished yet.
        # The synchronization will continue even the command or the powershell session stops.
        # Even when the SQL Server instance is restarted, the synchronization will continue after the restart.
        # Set-DbatoolsConfig -FullName commands.add-dbaagdatabase.timeout.existing -Value 60
        # Set-DbatoolsConfig -FullName commands.add-dbaagdatabase.timeout.synchronization -Value 86400
        $timeoutExisting = Get-DbatoolsConfigValue -FullName commands.add-dbaagdatabase.timeout.existing -Fallback 60
        $timeoutSynchronization = Get-DbatoolsConfigValue -FullName commands.add-dbaagdatabase.timeout.synchronization -Fallback 86400

        # While in a while loop, configure the time in milliseconds to wait for the next test:
        # Set-DbatoolsConfig -FullName commands.add-dbaagdatabase.wait.while -Value 100
        $waitWhile = Get-DbatoolsConfigValue -FullName commands.add-dbaagdatabase.wait.while -Fallback 100

        # With automatic seeding we add the current seeding progress in verbose output and a progress bar. This can be disabled:
        # Set-DbatoolsConfig -FullName commands.add-dbaagdatabase.report.seeding -Value $true
        $reportSeeding = Get-DbatoolsConfigValue -FullName commands.add-dbaagdatabase.report.seeding -Fallback $true
    }

    process {
        # We store information for the progress bar in a hashtable suitable for splatting.
        $progress = @{ }
        $progress['Id'] = Get-Random
        $progress['Activity'] = "Adding database(s) to Availability Group $AvailabilityGroup"

        $testResult = @( )

        foreach ($dbName in $Database) {
            try {
                $progress['Status'] = "Test prerequisites for joining database $dbName"
                Write-Progress @progress
                $testSplat = @{
                    SqlInstance            = $SqlInstance
                    SqlCredential          = $SqlCredential
                    Secondary              = $Secondary
                    SecondarySqlCredential = $SecondarySqlCredential
                    AvailabilityGroup      = $AvailabilityGroup
                    AddDatabase            = $dbName
                    UseLastBackup          = $UseLastBackup
                    EnableException        = $true
                }
                if ($SeedingMode) { $testSplat['SeedingMode'] = $SeedingMode }
                if ($SharedPath) { $testSplat['SharedPath'] = $SharedPath }
                $testResult += Test-DbaAvailabilityGroup @testSplat
            } catch {
                Stop-Function -Message "Testing prerequisites for joining database $dbName to Availability Group $AvailabilityGroup failed." -ErrorRecord $_ -Continue
            }
        }

        foreach ($db in $InputObject) {
            try {
                $progress['Status'] = "Test prerequisites for joining database $($db.Name)"
                Write-Progress @progress
                $testSplat = @{
                    SqlInstance            = $db.Parent
                    Secondary              = $Secondary
                    SecondarySqlCredential = $SecondarySqlCredential
                    AvailabilityGroup      = $AvailabilityGroup
                    AddDatabase            = $db.Name
                    UseLastBackup          = $UseLastBackup
                    EnableException        = $true
                }
                if ($SeedingMode) { $testSplat['SeedingMode'] = $SeedingMode }
                if ($SharedPath) { $testSplat['SharedPath'] = $SharedPath }
                $testResult += Test-DbaAvailabilityGroup @testSplat
            } catch {
                Stop-Function -Message "Testing prerequisites for joining database $($db.Name) to Availability Group $AvailabilityGroup failed." -ErrorRecord $_ -Continue
            }
        }

        Write-Message -Level Verbose -Message "Test for prerequisites returned $($testResult.Count) databases that will be joined to the Availability Group $AvailabilityGroup."

        foreach ($result in $testResult) {
            $server = $result.PrimaryServerSMO
            $ag = $result.AvailabilityGroupSMO
            $db = $result.DatabaseSMO
            $replicaServerSMO = $result.ReplicaServerSMO
            $restoreNeeded = $result.RestoreNeeded
            $backups = $result.Backups
            $replicaAgDbSMO = @{ }
            $targetSynchronizationState = @{ }
            $output = @( )

            $progress['Activity'] = "Adding database $($db.Name) to Availability Group $AvailabilityGroup"

            $progress['Status'] = "Step 1/5: Setting seeding mode if needed"
            Write-Message -Level Verbose -Message $progress['Status']
            Write-Progress @progress

            if ($SeedingMode) {
                Write-Message -Level Verbose -Message "Setting seeding mode to $SeedingMode."
                $failure = $false
                foreach ($replicaName in $replicaServerSMO.Keys) {
                    $replica = $ag.AvailabilityReplicas[$replicaName]
                    if ($replica.SeedingMode -ne $SeedingMode) {
                        if ($Pscmdlet.ShouldProcess($server, "Setting seeding mode for replica $replica to $SeedingMode")) {
                            try {
                                Write-Message -Level Verbose -Message "Setting seeding mode for replica $replica to $SeedingMode."
                                $replica.SeedingMode = $SeedingMode
                                $replica.Alter()
                                if ($SeedingMode -eq 'Automatic') {
                                    Write-Message -Level Verbose -Message "Setting GrantAvailabilityGroupCreateDatabasePrivilege on server $($replicaServerSMO[$replicaName]) for Availability Group $AvailabilityGroup."
                                    $null = Grant-DbaAgPermission -SqlInstance $replicaServerSMO[$replicaName] -Type AvailabilityGroup -AvailabilityGroup $AvailabilityGroup -Permission CreateAnyDatabase
                                }
                            } catch {
                                $failure = $true
                                Stop-Function -Message "Failed setting seeding mode for replica $replica to $SeedingMode." -ErrorRecord $_ -Continue
                            }
                        }
                    }
                }
                if ($failure) {
                    Stop-Function -Message "Failed setting seeding mode to $SeedingMode." -Continue
                }
            }

            $progress['Status'] = "Step 2/5: Running backup and restore if needed"
            Write-Message -Level Verbose -Message $progress['Status']
            Write-Progress @progress

            if ($restoreNeeded.Count -gt 0) {
                if (-not $backups) {
                    if ($Pscmdlet.ShouldProcess($server, "Taking full and log backup of database $($db.Name)")) {
                        try {
                            Write-Message -Level Verbose -Message "Taking full and log backup of database $($db.Name)."
                            if ($AdvancedBackupParams) {
                                $fullbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Full -EnableException @AdvancedBackupParams
                                $logbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Log -EnableException @AdvancedBackupParams
                            } else {
                                $fullbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Full -EnableException
                                $logbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Log -EnableException
                            }
                            $backups = $fullbackup, $logbackup
                        } catch {
                            Stop-Function -Message "Failed to take full and log backup of database $($db.Name)." -ErrorRecord $_ -Continue
                        }
                    }
                }
                $failure = $false
                foreach ($replicaName in $restoreNeeded.Keys) {
                    if ($Pscmdlet.ShouldProcess($replicaServerSMO[$replicaName], "Restore database $($db.Name) to replica $replicaName")) {
                        try {
                            Write-Message -Level Verbose -Message "Restore database $($db.Name) to replica $replicaName."
                            $restoreParams = @{
                                SqlInstance          = $replicaServerSMO[$replicaName]
                                NoRecovery           = $true
                                TrustDbBackupHistory = $true
                                EnableException      = $true
                            }

                            # Check if we should skip ReuseSourceFolderStructure
                            if (-not $SkipReuseSourceFolderStructure) {
                                # Check if primary and replica are on the same platform
                                $primaryPlatform = $server.HostPlatform
                                $replicaPlatform = $replicaServerSMO[$replicaName].HostPlatform
                                if ($primaryPlatform -ne $replicaPlatform) {
                                    Write-Message -Level Verbose -Message "Primary platform ($primaryPlatform) does not match replica platform ($replicaPlatform). Setting SkipReuseSourceFolderStructure."
                                    $SkipReuseSourceFolderStructure = $true
                                }
                            }

                            # Only use ReuseSourceFolderStructure if not skipped
                            if (-not $SkipReuseSourceFolderStructure) {
                                Write-Message -Level Verbose -Message "Using ReuseSourceFolderStructure to maintain consistent folder layout."
                                $restoreParams['ReuseSourceFolderStructure'] = $true
                            } else {
                                Write-Message -Level Verbose -Message "Using replica's default paths for database files."
                            }

                            $sourceOwner = $db.Owner
                            $replicaOwner = $replicaServerSMO[$replicaName].ConnectedAs
                            if ($sourceOwner -ne $replicaOwner) {
                                Write-Message -Level Verbose -Message "Source database owner is $sourceOwner, replica database owner would be $replicaOwner."
                                if ($replicaServerSMO[$replicaName].Logins[$db.Owner]) {
                                    Write-Message -Level Verbose -Message "Source database owner is found on replica, so using ExecuteAs with Restore-DbaDatabase to set correct owner."
                                    $restoreParams['ExecuteAs'] = $db.Owner
                                } else {
                                    Write-Message -Level Verbose -Message "Source database owner is not found on replica, so there is nothing we can do."
                                }
                            }
                            $null = $backups | Restore-DbaDatabase @restoreParams
                        } catch {
                            $failure = $true
                            Stop-Function -Message "Failed to restore database $($db.Name) to replica $replicaName." -ErrorRecord $_ -Continue
                        }
                    }
                }
                if ($failure) {
                    Stop-Function -Message "Failed to restore database $($db.Name)." -Continue
                }
            }

            $progress['Status'] = "Step 3/5: Add the database to the Availability Group on the primary replica"
            Write-Message -Level Verbose -Message $progress['Status']

            if ($Pscmdlet.ShouldProcess($server, "Add database $($db.Name) to Availability Group $AvailabilityGroup on the primary replica")) {
                try {
                    $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on is not yet known"
                    Write-Message -Level Verbose -Message "Object of type AvailabilityDatabase for $($db.Name) will be created. $($progress['CurrentOperation'])"
                    Write-Progress @progress

                    if ($ag.AvailabilityDatabases.Name -contains $db.Name) {
                        Write-Message -Level Verbose -Message "Database $($db.Name) is already joined to Availability Group $AvailabilityGroup. No action will be taken on the primary replica."
                    } else {
                        $agDb = Get-DbaAgDatabase -SqlInstance $server -AvailabilityGroup $ag.Name -Database $db.Name
                        $agDb = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($ag, $db.Name)
                        $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) is $($agDb.State)"
                        Write-Message -Level Verbose -Message "Object of type AvailabilityDatabase for $($db.Name) is created. $($progress['CurrentOperation'])"
                        Write-Progress @progress

                        $agDb.Create()
                        $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) is $($agDb.State)"
                        Write-Message -Level Verbose -Message "Method Create of AvailabilityDatabase for $($db.Name) is executed. $($progress['CurrentOperation'])"
                        Write-Progress @progress

                        # Wait for state to become Existing
                        # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
                        $timeout = (Get-Date).AddSeconds($timeoutExisting)
                        while ($agDb.State -ne 'Existing') {
                            $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) is $($agDb.State), waiting for Existing"
                            Write-Message -Level Verbose -Message $progress['CurrentOperation']
                            Write-Progress @progress

                            if ((Get-Date) -gt $timeout) {
                                Stop-Function -Message "Failed to add database $($db.Name) to Availability Group $AvailabilityGroup. Timeout of $timeoutExisting seconds is reached. State of AvailabilityDatabase for $($db.Name) is still $($agDb.State)." -Continue
                            }
                            Start-Sleep -Milliseconds $waitWhile
                            $agDb.Refresh()
                        }

                        # Get customized SMO for the output
                        $output += Get-DbaAgDatabase -SqlInstance $server -AvailabilityGroup $AvailabilityGroup -Database $db.Name -EnableException
                    }
                } catch {
                    Stop-Function -Message "Failed to add database $($db.Name) to Availability Group $AvailabilityGroup" -ErrorRecord $_ -Continue
                }
            }

            $progress['Status'] = "Step 4/5: Add the database to the Availability Group on the secondary replicas"
            Write-Message -Level Verbose -Message $progress['Status']

            $failure = $false
            foreach ($replicaName in $replicaServerSMO.Keys) {
                if ($Pscmdlet.ShouldProcess($replicaServerSMO[$replicaName], "Add database $($db.Name) to Availability Group $AvailabilityGroup on replica $replicaName")) {
                    $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on replica $replicaName is not yet known"
                    Write-Message -Level Verbose -Message $progress['CurrentOperation']
                    Write-Progress @progress

                    try {
                        $replicaAgDb = Get-DbaAgDatabase -SqlInstance $replicaServerSMO[$replicaName] -AvailabilityGroup $AvailabilityGroup -Database $db.Name -EnableException
                    } catch {
                        $failure = $true
                        Stop-Function -Message "Failed to get database $($db.Name) on replica $replicaName." -ErrorRecord $_ -Continue
                    }

                    if ($replicaAgDb.IsJoined) {
                        Write-Message -Level Verbose -Message "Database $($db.Name) is already joined to Availability Group $AvailabilityGroup. No action will be taken on the replica $replicaName."
                        $replicaAgDbSMO[$replicaName] = $replicaAgDb
                    } else {
                        # Save SMO in array for the output
                        $output += $replicaAgDb
                        # Save SMO in hashtable for further processing
                        $replicaAgDbSMO[$replicaName] = $replicaAgDb
                        # Save target targetSynchronizationState for further processing
                        # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.availabilityreplicaavailabilitymode
                        # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.availabilitydatabasesynchronizationstate
                        $availabilityMode = $ag.AvailabilityReplicas[$replicaName].AvailabilityMode
                        if ($availabilityMode -eq 'AsynchronousCommit') {
                            $targetSynchronizationState[$replicaName] = 'Synchronizing'
                        } elseif ($availabilityMode -eq 'SynchronousCommit') {
                            $targetSynchronizationState[$replicaName] = 'Synchronized'
                        } else {
                            $failure = $true
                            Stop-Function -Message "Unexpected value '$availabilityMode' for AvailabilityMode on replica $replicaName." -Continue
                        }

                        $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on replica $replicaName is $($replicaAgDb.State)"
                        Write-Message -Level Verbose -Message $progress['CurrentOperation']
                        Write-Progress @progress

                        # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
                        $timeout = (Get-Date).AddSeconds($timeoutExisting)
                        while ($replicaAgDb.State -ne 'Existing') {
                            $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on replica $replicaName is $($replicaAgDb.State), waiting for Existing."
                            Write-Message -Level Verbose -Message $progress['CurrentOperation']
                            Write-Progress @progress

                            if ((Get-Date) -gt $timeout) {
                                Stop-Function -Message "Failed to add database $($db.Name) on replica $replicaName. Timeout of $timeoutExisting seconds is reached. State of AvailabilityDatabase for $db is still $($replicaAgDb.State)." -Continue
                            }
                            Start-Sleep -Milliseconds $waitWhile
                            $replicaAgDb.Refresh()
                        }

                        # With automatic seeding, .JoinAvailablityGroup() is not needed, just wait for the magic to happen
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -ne 'Automatic') {
                            try {
                                $progress['CurrentOperation'] = "Joining database $($db.Name) on replica $replicaName"
                                Write-Message -Level Verbose -Message $progress['CurrentOperation']
                                Write-Progress @progress

                                # DO NOT fix the typo in "JoinAvailablityGroup()" as it is a typo the SMO.
                                $replicaAgDb.JoinAvailablityGroup()
                            } catch {
                                $failure = $true
                                Stop-Function -Message "Failed to join database $($db.Name) on replica $replicaName." -ErrorRecord $_ -Continue
                            }
                        }
                    }
                }
            }
            if ($failure) {
                Stop-Function -Message "Failed to add or join database $($db.Name)." -Continue
            }

            # Now we have configured everything and we only have to wait...

            $progress['Status'] = "Step 5/5: Wait for the database to finish joining the Availability Group on the secondary replicas"
            $progress['CurrentOperation'] = ''
            Write-Message -Level Verbose -Message $progress['Status']
            Write-Progress @progress

            if ($NoWait) {
                Write-Message -Level Verbose -Message "NoWait parameter specified. Skipping wait for database $($db.Name) to finish joining the Availability Group $AvailabilityGroup on the secondary replicas. Synchronization will continue in the background."
            } elseif ($Pscmdlet.ShouldProcess($server, "Wait for the database $($db.Name) to finish joining the Availability Group $AvailabilityGroup on the secondary replicas.")) {
                # We need to setup a progress bar for every replica to display them all at once.
                $syncProgressId = @{ }
                foreach ($replicaName in $replicaServerSMO.Keys) {
                    $syncProgressId[$replicaName] = Get-Random
                }

                $stillWaiting = $true
                $timeout = (Get-Date).AddSeconds($timeoutSynchronization)
                while ($stillWaiting) {
                    $stillWaiting = $false
                    $failure = $false
                    foreach ($replicaName in $replicaServerSMO.Keys) {
                        if (-not $targetSynchronizationState[$replicaName]) {
                            Write-Message -Level Verbose -Message "Database $($db.Name) is already joined to Availability Group $AvailabilityGroup. No action will be taken on the replica $replicaName."
                            continue
                        }

                        if (-not $replicaAgDbSMO[$replicaName].IsJoined -or $replicaAgDbSMO[$replicaName].SynchronizationState -ne $targetSynchronizationState[$replicaName]) {
                            $stillWaiting = $true
                        }

                        $syncProgress = @{ }
                        $syncProgress['Id'] = $syncProgressId[$replicaName]
                        $syncProgress['ParentId'] = $progress['Id']
                        $syncProgress['Activity'] = "Adding database $($db.Name) to Availability Group $AvailabilityGroup on replica $replicaName"
                        if ($replicaAgDbSMO[$replicaName].SynchronizationState -ne $targetSynchronizationState[$replicaName]) {
                            $syncProgress['Status'] = "IsJoined is $($replicaAgDbSMO[$replicaName].IsJoined), SynchronizationState is $($replicaAgDbSMO[$replicaName].SynchronizationState), waiting for $($targetSynchronizationState[$replicaName])"
                        } else {
                            $syncProgress['Status'] = "IsJoined is $($replicaAgDbSMO[$replicaName].IsJoined), SynchronizationState is $($replicaAgDbSMO[$replicaName].SynchronizationState), replica is in desired state"
                        }
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -eq 'Automatic' -and $reportSeeding) {
                            $physicalSeedingStats = $server.Query("SELECT TOP 1 * FROM sys.dm_hadr_physical_seeding_stats WHERE local_database_name = '$($db.Name)' AND remote_machine_name = '$($ag.AvailabilityReplicas[$replicaName].EndpointUrl)' ORDER BY start_time_utc DESC")
                            if ($physicalSeedingStats) {
                                if ($physicalSeedingStats.failure_message -ne [DBNull]::Value) {
                                    $failure = $true
                                    Stop-Function -Message "Failed while seeding database $($db.Name) to $replicaName. failure_message: $($physicalSeedingStats.failure_message)." -Continue
                                }

                                $syncProgress['PercentComplete'] = [int]($physicalSeedingStats.transferred_size_bytes * 100.0 / $physicalSeedingStats.database_size_bytes)
                                $syncProgress['SecondsRemaining'] = [int](($physicalSeedingStats.estimate_time_complete_utc - (Get-Date).ToUniversalTime()).TotalSeconds)
                                $syncProgress['CurrentOperation'] = "Seeding state: $($physicalSeedingStats.internal_state_desc), $([int]($physicalSeedingStats.transferred_size_bytes/1024/1024)) out of $([int]($physicalSeedingStats.database_size_bytes/1024/1024)) MB transferred"
                            }
                            $automaticSeeding = $server.Query("SELECT TOP 1 * FROM sys.dm_hadr_automatic_seeding WHERE ag_id = '$($ag.UniqueId.Guid.ToUpper())' AND ag_db_id = '$($ag.AvailabilityDatabases[$db.Name].UniqueId.Guid.ToUpper())' AND ag_remote_replica_id = '$($ag.AvailabilityReplicas[$replicaName].UniqueId.Guid.ToUpper())' ORDER BY start_time DESC")
                            Write-Message -Level Verbose -Message "Current automatic seeding state: $($automaticSeeding.current_state)"
                            if ($automaticSeeding.current_state -eq 'FAILED') {
                                $failure = $true
                                Stop-Function -Message "Failed while seeding database $($db.Name) to $replicaName. failure_message: $($automaticSeeding.failure_state_desc)." -Continue
                            }
                        }
                        Write-Message -Level Verbose -Message ($syncProgress['Status'] + $syncProgress['CurrentOperation'])
                        Write-Progress @syncProgress
                    }
                    if ($failure) {
                        $stillWaiting = $false
                        Stop-Function -Message "Failed while seeding database $($db.Name)." -Continue
                    }

                    if ((Get-Date) -gt $timeout) {
                        $stillWaiting = $false
                        $failure = $true
                        Stop-Function -Message "Failed to join or synchronize database $($db.Name). Timeout of $timeoutSynchronization seconds is reached. $progressOperation" -Continue
                    }
                    Start-Sleep -Milliseconds $waitWhile

                    foreach ($replicaName in $replicaServerSMO.Keys) {
                        $replicaAgDbSMO[$replicaName].Refresh()
                    }
                }
                foreach ($replicaName in $replicaServerSMO.Keys) {
                    Write-Progress -Id $syncProgressId[$replicaName] -ParentId $progress['Id'] -Activity Completed -Completed
                }
                if ($failure) {
                    Stop-Function -Message "Failed to join or synchronize database $($db.Name)." -Continue
                }
            }
            $output
        }
        Write-Progress @progress -Completed
    }
}