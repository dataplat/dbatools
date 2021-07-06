function Add-DbaAgDatabase {
    <#
    .SYNOPSIS
        Adds database(s) to an Availability Group on a SQL Server instance.

    .DESCRIPTION
        Adds database(s) to an Availability Group on a SQL Server instance.

        After checking for prerequisites, the commands runs these five steps for every database:
        Step 1: Setting seeding mode if needed.
            If -SeedingMode is used and the current seeding mode of the replica is not in the desired mode, the seeding mode of the replica is changed.
            The seeding mode will not be changed back but stay in this mode.
            If the seeding mode is changed to Automatic, the necessary rigths to create databases will be granted.
        Step 2: Running backup and restore if needed.
            Action is only taken for replicas with a desired seeding mode of Manual and where the database does not yet exist.
            If -UseLastBackup is used, the restore will be performed based on the backup history of the database.
            Otherwise a full and log backup will be taken at the primary and those will be restored at the replica.
        Step 3: Add the database to the Availability Group on the primary replica.
        Step 4: Add the database to the Availability Group on the secondary replicas.
        Step 5: Wait for the database to finish joining the Availability Group on the secondary replicas.

        Use Test-DbaAvailabilityGroup with -AddDatabase to test if all prerequisites are met.

        In case you need a special setup for the database at the replicas, please do the backup restore part

        If you have special requirements for the setup for the database at the replicas,
        perform the backup and restore part with Backup-DbaDatabase and Restore-DbaDatabase in advance.
        Please make sure that the last log backup has been restored before running Add-DbaAgDatabase.

        Known limitations:

        It is not possible to use this command to add the database to a newly added replica,
        because the command fails if the database is already part of the Availability Group.
        This limitation will be removed in a later version.

   .PARAMETER SqlInstance
        The primary replica of the Availability Group. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to add.

    .PARAMETER AvailabilityGroup
        The name of the Availability Group where the databases will be added.

    .PARAMETER Secondary
        Not required - the command will figure this out. But use this parameter if secondary replicas listen on a non default port.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase, Get-DbaDbSharePoint and more.

    .PARAMETER SeedingMode
        Specifies how the secondary replica will be initially seeded.

        Automatic enables direct seeding. This method will seed the secondary replica over the network. This method does not require you to backup and restore a copy of the primary database on the replica.

        Manual uses full and log backup to initially transfer the data to the secondary replica. The command skips this if the database is found in restoring state at the secondary replica.

        If not specified, the setting from the availability group replica will be used. Otherwise the setting will be updated.

    .PARAMETER SharedPath
        The network share where the backups will be backed up and restored from.

        Each SQL Server service account must have access to this share.

        NOTE: If a backup / restore is performed, the backups will be left in tact on the network share.

    .PARAMETER UseLastBackup
        Use the last full and log backup of the database. A log backup must be the last backup.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG
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
        [switch]$EnableException
    )

    begin {
        # We have three while loops, that need a timeout to not loop forever if somethings goes wrong:
        # while ($agDb.State -ne 'Existing')         - should only take milliseconds, so we set a default timeout of one minute
        # while ($replicaAgDb.State -ne 'Existing')  - should only take milliseconds, so we set a default timeout of one minute
        # while ($stillWaiting)                      - can take a long time with automatic seeding, but progress is displayed, so we set a default timeout of one day
        # We will use two timeout configuration values, as we don't want to add more timeout parameters to the command. We will store the timeouts in seconds.
        # The timout for synchronization can be set to a lower value to end the command even when the synchronization is not finished yet.
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
        $progress['Activity'] = "Adding database(s) to Availability Group $AvailabilityGroup."

        $testResult = @( )

        foreach ($dbName in $Database) {
            try {
                $progress['Status'] = "Test prerequisites for joining database $dbName."
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
                $progress['Status'] = "Test prerequisites for joining database $($db.Name)."
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

            $progress['Activity'] = "Adding database $($db.Name) to Availability Group $AvailabilityGroup."

            $progress['Status'] = "Step 1/5: Setting seeding mode if needed."
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
                                    $replicaServerSMO[$replicaName].GrantAvailabilityGroupCreateDatabasePrivilege($AvailabilityGroup)
                                    $replicaServerSMO[$replicaName].Alter()
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

            $progress['Status'] = "Step 2/5: Running backup and restore if needed."
            Write-Message -Level Verbose -Message $progress['Status']
            Write-Progress @progress

            if ($restoreNeeded.Count -gt 0) {
                if (-not $backups) {
                    if ($Pscmdlet.ShouldProcess($server, "Taking full and log backup of database $($db.Name)")) {
                        try {
                            Write-Message -Level Verbose -Message "Taking full and log backup of database $($db.Name)."
                            $fullbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Full -EnableException
                            $logbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Log -EnableException
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
                            $null = $backups | Restore-DbaDatabase -SqlInstance $replicaServerSMO[$replicaName] -NoRecovery -TrustDbBackupHistory -EnableException
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

            $progress['Status'] = "Step 3/5: Add the database to the Availability Group on the primary replica."
            Write-Message -Level Verbose -Message $progress['Status']

            if ($Pscmdlet.ShouldProcess($server, "Add database $($db.Name) to Availability Group $AvailabilityGroup on the primary replica")) {
                try {
                    $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on is not yet known."
                    Write-Message -Level Verbose -Message "Object of type AvailabilityDatabase for $($db.Name) will be created. $($progress['CurrentOperation'])"
                    Write-Progress @progress

                    $agDb = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($ag, $db.Name)
                    $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) is $($agDb.State)."
                    Write-Message -Level Verbose -Message "Object of type AvailabilityDatabase for $($db.Name) is created. $($progress['CurrentOperation'])"
                    Write-Progress @progress

                    $agDb.Create()
                    $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) is $($agDb.State)."
                    Write-Message -Level Verbose -Message "Method Create of AvailabilityDatabase for $($db.Name) is executed. $($progress['CurrentOperation'])"
                    Write-Progress @progress

                    # Wait for state to become Existing
                    # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
                    $timeout = (Get-Date).AddSeconds($timeoutExisting)
                    while ($agDb.State -ne 'Existing') {
                        $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) is $($agDb.State), waiting for Existing."
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
                } catch {
                    Stop-Function -Message "Failed to add database $($db.Name) to Availability Group $AvailabilityGroup" -ErrorRecord $_ -Continue
                }
            }

            $progress['Status'] = "Step 4/5: Add the database to the Availability Group on the secondary replicas."
            Write-Message -Level Verbose -Message $progress['Status']

            $failure = $false
            foreach ($replicaName in $replicaServerSMO.Keys) {
                if ($Pscmdlet.ShouldProcess($replicaServerSMO[$replicaName], "Add database $($db.Name) to Availability Group $AvailabilityGroup on replica $replicaName")) {
                    $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on replica $replicaName is not yet known."
                    Write-Message -Level Verbose -Message $progress['CurrentOperation']
                    Write-Progress @progress

                    try {
                        $replicaAgDb = Get-DbaAgDatabase -SqlInstance $replicaServerSMO[$replicaName] -AvailabilityGroup $AvailabilityGroup -Database $db.Name -EnableException
                    } catch {
                        $failure = $true
                        Stop-Function -Message "Failed to get database $($db.Name) on replica $replicaName." -ErrorRecord $_ -Continue
                    }

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

                    $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on replica $replicaName is $($replicaAgDb.State)."
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
                            $progress['CurrentOperation'] = "Joining database $($db.Name) on replica $replicaName."
                            Write-Message -Level Verbose -Message $progress['CurrentOperation']
                            Write-Progress @progress

                            $replicaAgDb.JoinAvailablityGroup()
                        } catch {
                            $failure = $true
                            Stop-Function -Message "Failed to join database $($db.Name) on replica $replicaName." -ErrorRecord $_ -Continue
                        }
                    }
                }
            }
            if ($failure) {
                Stop-Function -Message "Failed to add or join database $($db.Name)." -Continue
            }

            # Now we have configured everything and we only have to wait...

            $progress['Status'] = "Step 5/5: Wait for the database to finish joining the Availability Group on the secondary replicas."
            $progress['CurrentOperation'] = ''
            Write-Message -Level Verbose -Message $progress['Status']
            Write-Progress @progress

            if ($Pscmdlet.ShouldProcess($server, "Wait for the database $($db.Name) to finish joining the Availability Group $AvailabilityGroup on the secondary replicas.")) {
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
                        if (-not $replicaAgDbSMO[$replicaName].IsJoined -or $replicaAgDbSMO[$replicaName].SynchronizationState -ne $targetSynchronizationState[$replicaName]) {
                            $stillWaiting = $true
                        }

                        $syncProgress = @{ }
                        $syncProgress['Id'] = $syncProgressId[$replicaName]
                        $syncProgress['ParentId'] = $progress['Id']
                        $syncProgress['Activity'] = "Adding database(s) to Availability Group $AvailabilityGroup."
                        if ($replicaAgDbSMO[$replicaName].SynchronizationState -ne $targetSynchronizationState[$replicaName]) {
                            $syncProgress['Status'] = "IsJoined is $($replicaAgDbSMO[$replicaName].IsJoined), SynchronizationState is $($replicaAgDbSMO[$replicaName].SynchronizationState), waiting for $($targetSynchronizationState[$replicaName])."
                        } else {
                            $syncProgress['Status'] = "IsJoined is $($replicaAgDbSMO[$replicaName].IsJoined), SynchronizationState is $($replicaAgDbSMO[$replicaName].SynchronizationState), replica is in desired state."
                        }
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -eq 'Automatic' -and $reportSeeding) {
                            $seedingStats = $server.Query("SELECT * FROM sys.dm_hadr_physical_seeding_stats WHERE local_database_name = '$($db.Name)' AND remote_machine_name = '$($ag.AvailabilityReplicas[$replicaName].EndpointUrl)'")
                            if ($seedingStats) {
                                if ($seedingStats.failure_message -ne [DBNull]::Value) {
                                    $failure = $true
                                    Stop-Function -Message "Failed while seeding database $($db.Name) to $replicaName. failure_message: $($seedingStats.failure_message)." -Continue
                                }

                                $syncProgress['PercentComplete'] = [int]($seedingStats.transferred_size_bytes * 100.0 / $seedingStats.database_size_bytes)
                                $syncProgress['SecondsRemaining'] = [int](($seedingStats.estimate_time_complete_utc - (Get-Date).ToUniversalTime()).TotalSeconds)
                                $syncProgress['CurrentOperation'] = "Seeding state: $($seedingStats.internal_state_desc), $([int]($seedingStats.transferred_size_bytes/1024/1024)) out of $([int]($seedingStats.database_size_bytes/1024/1024)) MB transferred."
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
                if ($failure) {
                    Stop-Function -Message "Failed to join or synchronize database $($db.Name)." -Continue
                }
            }
            $output
        }
    }
}
