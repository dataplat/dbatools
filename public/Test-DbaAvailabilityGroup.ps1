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
