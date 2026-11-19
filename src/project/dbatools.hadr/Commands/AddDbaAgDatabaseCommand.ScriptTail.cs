#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class AddDbaAgDatabaseCommand
{
    // PS: the process block VERBATIM, second half (see ScriptHead for the composition
    // and substitution accounting). The state tail after the source body writes the
    // carried SkipReuseSourceFolderStructure back so later records observe the source's
    // function-scope persistence of that parameter mutation.
    private const string ProcessScriptTail = """
                                if ($replicaServerSMO[$replicaName].Logins[$db.Owner]) {
                                    Write-Message -Level Verbose -Message "Source database owner is found on replica, so using ExecuteAs with Restore-DbaDatabase to set correct owner." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                                    $restoreParams['ExecuteAs'] = $db.Owner
                                } else {
                                    Write-Message -Level Verbose -Message "Source database owner is not found on replica, so there is nothing we can do." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                                }
                            }
                            $null = $backups | Restore-DbaDatabase @restoreParams
                        } catch {
                            $failure = $true
                            Stop-Function -Message "Failed to restore database $($db.Name) to replica $replicaName." -ErrorRecord $_ -Continue -FunctionName Add-DbaAgDatabase
                        }
                    }
                }
                if ($failure) {
                    Stop-Function -Message "Failed to restore database $($db.Name)." -Continue -FunctionName Add-DbaAgDatabase
                }
            }

            $progress['Status'] = "Step 3/5: Add the database to the Availability Group on the primary replica"
            Write-Message -Level Verbose -Message $progress['Status'] -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"

            if ($__realCmdlet.ShouldProcess($server, "Add database $($db.Name) to Availability Group $AvailabilityGroup on the primary replica")) {
                try {
                    $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on is not yet known"
                    Write-Message -Level Verbose -Message "Object of type AvailabilityDatabase for $($db.Name) will be created. $($progress['CurrentOperation'])" -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                    Write-Progress @progress

                    if ($ag.AvailabilityDatabases.Name -contains $db.Name) {
                        Write-Message -Level Verbose -Message "Database $($db.Name) is already joined to Availability Group $AvailabilityGroup. No action will be taken on the primary replica." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                    } else {
                        $agDb = Get-DbaAgDatabase -SqlInstance $server -AvailabilityGroup $ag.Name -Database $db.Name
                        $agDb = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($ag, $db.Name)
                        $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) is $($agDb.State)"
                        Write-Message -Level Verbose -Message "Object of type AvailabilityDatabase for $($db.Name) is created. $($progress['CurrentOperation'])" -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                        Write-Progress @progress

                        $agDb.Create()
                        $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) is $($agDb.State)"
                        Write-Message -Level Verbose -Message "Method Create of AvailabilityDatabase for $($db.Name) is executed. $($progress['CurrentOperation'])" -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                        Write-Progress @progress

                        # Wait for state to become Existing
                        # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
                        $timeout = (Get-Date).AddSeconds($timeoutExisting)
                        while ($agDb.State -ne 'Existing') {
                            $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) is $($agDb.State), waiting for Existing"
                            Write-Message -Level Verbose -Message $progress['CurrentOperation'] -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                            Write-Progress @progress

                            if ((Get-Date) -gt $timeout) {
                                Stop-Function -Message "Failed to add database $($db.Name) to Availability Group $AvailabilityGroup. Timeout of $timeoutExisting seconds is reached. State of AvailabilityDatabase for $($db.Name) is still $($agDb.State)." -Continue -FunctionName Add-DbaAgDatabase
                            }
                            Start-Sleep -Milliseconds $waitWhile
                            $agDb.Refresh()
                        }

                        # Get customized SMO for the output
                        $output += Get-DbaAgDatabase -SqlInstance $server -AvailabilityGroup $AvailabilityGroup -Database $db.Name -EnableException
                    }
                } catch {
                    Stop-Function -Message "Failed to add database $($db.Name) to Availability Group $AvailabilityGroup" -ErrorRecord $_ -Continue -FunctionName Add-DbaAgDatabase
                }
            }

            $progress['Status'] = "Step 4/5: Add the database to the Availability Group on the secondary replicas"
            Write-Message -Level Verbose -Message $progress['Status'] -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"

            $failure = $false
            foreach ($replicaName in $replicaServerSMO.Keys) {
                if ($__realCmdlet.ShouldProcess($replicaServerSMO[$replicaName], "Add database $($db.Name) to Availability Group $AvailabilityGroup on replica $replicaName")) {
                    $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on replica $replicaName is not yet known"
                    Write-Message -Level Verbose -Message $progress['CurrentOperation'] -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                    Write-Progress @progress

                    try {
                        $replicaAgDb = Get-DbaAgDatabase -SqlInstance $replicaServerSMO[$replicaName] -AvailabilityGroup $AvailabilityGroup -Database $db.Name -EnableException
                    } catch {
                        $failure = $true
                        Stop-Function -Message "Failed to get database $($db.Name) on replica $replicaName." -ErrorRecord $_ -Continue -FunctionName Add-DbaAgDatabase
                    }

                    if ($replicaAgDb.IsJoined) {
                        Write-Message -Level Verbose -Message "Database $($db.Name) is already joined to Availability Group $AvailabilityGroup. No action will be taken on the replica $replicaName." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
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
                            Stop-Function -Message "Unexpected value '$availabilityMode' for AvailabilityMode on replica $replicaName." -Continue -FunctionName Add-DbaAgDatabase
                        }

                        $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on replica $replicaName is $($replicaAgDb.State)"
                        Write-Message -Level Verbose -Message $progress['CurrentOperation'] -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                        Write-Progress @progress

                        # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.sqlsmostate
                        $timeout = (Get-Date).AddSeconds($timeoutExisting)
                        while ($replicaAgDb.State -ne 'Existing') {
                            $progress['CurrentOperation'] = "State of AvailabilityDatabase for $($db.Name) on replica $replicaName is $($replicaAgDb.State), waiting for Existing."
                            Write-Message -Level Verbose -Message $progress['CurrentOperation'] -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                            Write-Progress @progress

                            if ((Get-Date) -gt $timeout) {
                                Stop-Function -Message "Failed to add database $($db.Name) on replica $replicaName. Timeout of $timeoutExisting seconds is reached. State of AvailabilityDatabase for $db is still $($replicaAgDb.State)." -Continue -FunctionName Add-DbaAgDatabase
                            }
                            Start-Sleep -Milliseconds $waitWhile
                            $replicaAgDb.Refresh()
                        }

                        # With automatic seeding, .JoinAvailablityGroup() is not needed, just wait for the magic to happen
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -ne 'Automatic') {
                            try {
                                $progress['CurrentOperation'] = "Joining database $($db.Name) on replica $replicaName"
                                Write-Message -Level Verbose -Message $progress['CurrentOperation'] -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                                Write-Progress @progress

                                # DO NOT fix the typo in "JoinAvailablityGroup()" as it is a typo the SMO.
                                $replicaAgDb.JoinAvailablityGroup()
                            } catch {
                                $failure = $true
                                Stop-Function -Message "Failed to join database $($db.Name) on replica $replicaName." -ErrorRecord $_ -Continue -FunctionName Add-DbaAgDatabase
                            }
                        }
                    }
                }
            }
            if ($failure) {
                Stop-Function -Message "Failed to add or join database $($db.Name)." -Continue -FunctionName Add-DbaAgDatabase
            }

            # Now we have configured everything and we only have to wait...

            $progress['Status'] = "Step 5/5: Wait for the database to finish joining the Availability Group on the secondary replicas"
            $progress['CurrentOperation'] = ''
            Write-Message -Level Verbose -Message $progress['Status'] -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
            Write-Progress @progress

            if ($NoWait) {
                Write-Message -Level Verbose -Message "NoWait parameter specified. Skipping wait for database $($db.Name) to finish joining the Availability Group $AvailabilityGroup on the secondary replicas. Synchronization will continue in the background." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
            } elseif ($__realCmdlet.ShouldProcess($server, "Wait for the database $($db.Name) to finish joining the Availability Group $AvailabilityGroup on the secondary replicas.")) {
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
                            Write-Message -Level Verbose -Message "Database $($db.Name) is already joined to Availability Group $AvailabilityGroup. No action will be taken on the replica $replicaName." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
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
                                    Stop-Function -Message "Failed while seeding database $($db.Name) to $replicaName. failure_message: $($physicalSeedingStats.failure_message)." -Continue -FunctionName Add-DbaAgDatabase
                                }

                                $syncProgress['PercentComplete'] = [int]($physicalSeedingStats.transferred_size_bytes * 100.0 / $physicalSeedingStats.database_size_bytes)
                                $syncProgress['SecondsRemaining'] = [int](($physicalSeedingStats.estimate_time_complete_utc - (Get-Date).ToUniversalTime()).TotalSeconds)
                                $syncProgress['CurrentOperation'] = "Seeding state: $($physicalSeedingStats.internal_state_desc), $([int]($physicalSeedingStats.transferred_size_bytes/1024/1024)) out of $([int]($physicalSeedingStats.database_size_bytes/1024/1024)) MB transferred"
                            }
                            $automaticSeeding = $server.Query("SELECT TOP 1 * FROM sys.dm_hadr_automatic_seeding WHERE ag_id = '$($ag.UniqueId.Guid.ToUpper())' AND ag_db_id = '$($ag.AvailabilityDatabases[$db.Name].UniqueId.Guid.ToUpper())' AND ag_remote_replica_id = '$($ag.AvailabilityReplicas[$replicaName].UniqueId.Guid.ToUpper())' ORDER BY start_time DESC")
                            Write-Message -Level Verbose -Message "Current automatic seeding state: $($automaticSeeding.current_state)" -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                            if ($automaticSeeding.current_state -eq 'FAILED') {
                                $failure = $true
                                Stop-Function -Message "Failed while seeding database $($db.Name) to $replicaName. failure_message: $($automaticSeeding.failure_state_desc)." -Continue -FunctionName Add-DbaAgDatabase
                            }
                        }
                        Write-Message -Level Verbose -Message ($syncProgress['Status'] + $syncProgress['CurrentOperation']) -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                        Write-Progress @syncProgress
                    }
                    if ($failure) {
                        $stillWaiting = $false
                        Stop-Function -Message "Failed while seeding database $($db.Name)." -Continue -FunctionName Add-DbaAgDatabase
                    }

                    if ((Get-Date) -gt $timeout) {
                        $stillWaiting = $false
                        $failure = $true
                        Stop-Function -Message "Failed to join or synchronize database $($db.Name). Timeout of $timeoutSynchronization seconds is reached. $progressOperation" -Continue -FunctionName Add-DbaAgDatabase
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
                    Stop-Function -Message "Failed to join or synchronize database $($db.Name)." -Continue -FunctionName Add-DbaAgDatabase
                }
            }
            $output
        }
        Write-Progress @progress -Completed

    @{ __w4001State = @{
        timeoutExisting        = $timeoutExisting
        timeoutSynchronization = $timeoutSynchronization
        waitWhile              = $waitWhile
        reportSeeding          = $reportSeeding
        skipReuse              = [bool]$SkipReuseSourceFolderStructure
    } }
} $SqlInstance $SqlCredential $AvailabilityGroup $Database $Secondary $SecondarySqlCredential $InputObject $SeedingMode $SharedPath $UseLastBackup $AdvancedBackupParams $NoWait $MasterKeySecurePassword $EnableException $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug $__boundProgressAction @__commonParameters 3>&1 2>&1
""";

    private static string ProcessScript => ProcessScriptHead + "\n" + ProcessScriptTail;
}
