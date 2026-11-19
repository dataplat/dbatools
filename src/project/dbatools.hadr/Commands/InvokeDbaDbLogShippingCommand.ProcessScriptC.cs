#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class InvokeDbaDbLogShippingCommand
{
    // PS: the process block VERBATIM, final third; see ProcessScriptA for the frame.
    // The tail closes the dot-block and re-emits the sentinel with the interrupt
    // flag merged (the source's 10 plain process Stop-Function sites latch the
    // fn-scope flag that record N+1's Test-FunctionInterrupt reads in the function
    // world - carried here via the sentinel and gated C#-side).
    private const string ProcessScriptC = """
                # Now that all the checks have been done we can start with the fun stuff !

                # Restore the full backup
                if ($setupResult -ne 'Failed') {
                    if ($PSCmdlet.ShouldProcess($destInstance, "Restoring database $db to $SecondaryDatabase on $destInstance")) {
                        if ($GenerateFullBackup -or $UseExistingFullBackup -or $UseBackupFolder) {
                            try {
                                Write-Message -Message "Start database restore" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                if ($NoRecovery -or (-not $Standby)) {
                                    if ($Force) {
                                        $splatRestore = @{
                                            SqlInstance              = $destInstance
                                            SqlCredential            = $DestinationSqlCredential
                                            Path                     = $BackupPath
                                            DestinationFilePrefix    = $SecondaryDatabasePrefix
                                            DestinationFileSuffix    = $SecondaryDatabaseSuffix
                                            DestinationDataDirectory = $DatabaseRestoreDataFolder
                                            DestinationLogDirectory  = $DatabaseRestoreLogFolder
                                            DatabaseName             = $SecondaryDatabase
                                            DirectoryRecurse         = $true
                                            NoRecovery               = $true
                                            WithReplace              = $true
                                        }
                                        $null = Restore-DbaDatabase @splatRestore
                                    } else {
                                        $splatRestore = @{
                                            SqlInstance              = $destInstance
                                            SqlCredential            = $DestinationSqlCredential
                                            Path                     = $BackupPath
                                            DestinationFilePrefix    = $SecondaryDatabasePrefix
                                            DestinationFileSuffix    = $SecondaryDatabaseSuffix
                                            DestinationDataDirectory = $DatabaseRestoreDataFolder
                                            DestinationLogDirectory  = $DatabaseRestoreLogFolder
                                            DatabaseName             = $SecondaryDatabase
                                            DirectoryRecurse         = $true
                                            NoRecovery               = $true
                                        }
                                        $null = Restore-DbaDatabase @splatRestore
                                    }
                                }

                                # If the database needs to be in standby
                                if ($Standby) {
                                    # Setup the path to the standby file
                                    $StandbyDirectory = "$DatabaseCopyDestinationFolder"

                                    # Check if credentials need to be used
                                    if ($DestinationSqlCredential) {
                                        $splatRestoreStandby = @{
                                            SqlInstance              = $destInstance
                                            SqlCredential            = $DestinationSqlCredential
                                            Path                     = $BackupPath
                                            DestinationFilePrefix    = $SecondaryDatabasePrefix
                                            DestinationFileSuffix    = $SecondaryDatabaseSuffix
                                            DestinationDataDirectory = $DatabaseRestoreDataFolder
                                            DestinationLogDirectory  = $DatabaseRestoreLogFolder
                                            DatabaseName             = $SecondaryDatabase
                                            DirectoryRecurse         = $true
                                            StandbyDirectory         = $StandbyDirectory
                                        }
                                        $null = Restore-DbaDatabase @splatRestoreStandby
                                    } else {
                                        $splatRestoreStandby = @{
                                            SqlInstance              = $destInstance
                                            Path                     = $BackupPath
                                            DestinationFilePrefix    = $SecondaryDatabasePrefix
                                            DestinationFileSuffix    = $SecondaryDatabaseSuffix
                                            DestinationDataDirectory = $DatabaseRestoreDataFolder
                                            DestinationLogDirectory  = $DatabaseRestoreLogFolder
                                            DatabaseName             = $SecondaryDatabase
                                            DirectoryRecurse         = $true
                                            StandbyDirectory         = $StandbyDirectory
                                        }
                                        $null = Restore-DbaDatabase @splatRestoreStandby
                                    }
                                }
                            } catch {
                                $setupResult = "Failed"
                                $comment = "Something went wrong restoring the secondary database"
                                Stop-Function -Message "Something went wrong restoring the secondary database" -ErrorRecord $_ -Target $SourceSqlInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                            }

                            Write-Message -Message "Restore completed." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                        }
                    }
                }

                #region Set up log shipping on the primary instance
                # Set up log shipping on the primary instance
                if ($setupResult -ne 'Failed') {
                    if ($PSCmdlet.ShouldProcess($SourceSqlInstance, "Configuring logshipping for primary database $db on $SourceSqlInstance")) {
                        try {

                            Write-Message -Message "Configuring logshipping for primary database" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                            $splatPrimary = @{
                                SqlInstance               = $SourceSqlInstance
                                SqlCredential             = $SourceSqlCredential
                                Database                  = $($db.Name)
                                BackupDirectory           = $DatabaseLocalPath
                                BackupJob                 = $DatabaseBackupJob
                                BackupRetention           = $BackupRetention
                                BackupShare               = $DatabaseSharedPath
                                BackupThreshold           = $BackupThreshold
                                CompressBackup            = $BackupCompression
                                HistoryRetention          = $HistoryRetention
                                MonitorServer             = $PrimaryMonitorServer
                                MonitorServerSecurityMode = $PrimaryMonitorServerSecurityMode
                                MonitorCredential         = $PrimaryMonitorCredential
                                ThresholdAlertEnabled     = $PrimaryThresholdAlertEnabled
                                Force                     = $Force
                            }

                            # Add Azure credential if provided (for storage account key authentication)
                            if ($AzureCredential) {
                                $splatPrimary.AzureCredential = $AzureCredential
                            }
                            New-DbaLogShippingPrimaryDatabase @splatPrimary

                            # Check if the backup job needs to be enabled or disabled
                            if ($BackupScheduleDisabled) {
                                $null = Set-DbaAgentJob -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential -Job $DatabaseBackupJob -Disabled
                                Write-Message -Message "Disabling backup job $DatabaseBackupJob" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                            } else {
                                $null = Set-DbaAgentJob -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential -Job $DatabaseBackupJob -Enabled
                                Write-Message -Message "Enabling backup job $DatabaseBackupJob" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                            }

                            Write-Message -Message "Create backup job schedule $DatabaseBackupSchedule" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                            #Variable $BackupJobSchedule marked as unused by PSScriptAnalyzer replaced with $null for catching output
                            $splatBackupSchedule = @{
                                SqlInstance               = $SourceSqlInstance
                                SqlCredential             = $SourceSqlCredential
                                Job                       = $DatabaseBackupJob
                                Schedule                  = $DatabaseBackupSchedule
                                FrequencyType             = $BackupScheduleFrequencyType
                                FrequencyInterval         = $BackupScheduleFrequencyInterval
                                FrequencySubdayType       = $BackupScheduleFrequencySubdayType
                                FrequencySubdayInterval   = $BackupScheduleFrequencySubdayInterval
                                FrequencyRelativeInterval = $BackupScheduleFrequencyRelativeInterval
                                FrequencyRecurrenceFactor = $BackupScheduleFrequencyRecurrenceFactor
                                StartDate                 = $BackupScheduleStartDate
                                EndDate                   = $BackupScheduleEndDate
                                StartTime                 = $BackupScheduleStartTime
                                EndTime                   = $BackupScheduleEndTime
                                Force                     = $Force
                            }
                            $null = New-DbaAgentSchedule @splatBackupSchedule

                            Write-Message -Message "Configuring logshipping from primary to secondary database." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                            $splatPrimarySecondary = @{
                                SqlInstance            = $SourceSqlInstance
                                SqlCredential          = $SourceSqlCredential
                                PrimaryDatabase        = $($db.Name)
                                SecondaryDatabase      = $SecondaryDatabase
                                SecondaryServer        = $destInstance
                                SecondarySqlCredential = $DestinationSqlCredential
                            }
                            New-DbaLogShippingPrimarySecondary @splatPrimarySecondary
                        } catch {
                            $setupResult = "Failed"
                            $comment = "Something went wrong setting up log shipping for primary instance"
                            Stop-Function -Message "Something went wrong setting up log shipping for primary instance" -ErrorRecord $_ -Target $SourceSqlInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                        }
                    }
                }
                #endregion Set up log shipping on the primary instance

                #region Set up log shipping on the secondary instance
                # Set up log shipping on the secondary instance
                if ($setupResult -ne 'Failed') {
                    if ($PSCmdlet.ShouldProcess($destInstance, "Configuring logshipping for secondary database $SecondaryDatabase on $destInstance")) {
                        try {

                            Write-Message -Message "Configuring logshipping from secondary database $SecondaryDatabase to primary database $db." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                            $splatSecondaryPrimary = @{
                                SqlInstance                = $destInstance
                                SqlCredential              = $DestinationSqlCredential
                                BackupSourceDirectory      = $DatabaseSharedPath
                                BackupDestinationDirectory = $DatabaseCopyDestinationFolder
                                CopyJob                    = $DatabaseCopyJob
                                FileRetentionPeriod        = $BackupRetention
                                MonitorServer              = $SecondaryMonitorServer
                                MonitorServerSecurityMode  = $SecondaryMonitorServerSecurityMode
                                MonitorCredential          = $SecondaryMonitorCredential
                                PrimaryServer              = $SourceSqlInstance
                                PrimarySqlCredential       = $SourceSqlCredential
                                PrimaryDatabase            = $($db.Name)
                                RestoreJob                 = $DatabaseRestoreJob
                                Force                      = $Force
                            }

                            # Add Azure credential if provided (for storage account key authentication)
                            if ($AzureCredential) {
                                $splatSecondaryPrimary.AzureCredential = $AzureCredential
                            }
                            New-DbaLogShippingSecondaryPrimary @splatSecondaryPrimary

                            # For Azure: Remove the copy job created by sp_add_log_shipping_secondary_primary
                            # Azure backups go directly to blob storage, so no copy is needed
                            if ($UseAzure) {
                                Write-Message -Message "Removing unnecessary copy job for Azure: $DatabaseCopyJob" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                $null = Remove-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseCopyJob -Confirm:$false
                            }

                            # Skip copy job schedule for Azure (backups are already in the cloud)
                            if (-not $UseAzure) {
                                Write-Message -Message "Create copy job schedule $DatabaseCopySchedule" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                #Variable $CopyJobSchedule marked as unused by PSScriptAnalyzer replaced with $null for catching output
                                $splatCopySchedule = @{
                                    SqlInstance               = $destInstance
                                    SqlCredential             = $DestinationSqlCredential
                                    Job                       = $DatabaseCopyJob
                                    Schedule                  = $DatabaseCopySchedule
                                    FrequencyType             = $CopyScheduleFrequencyType
                                    FrequencyInterval         = $CopyScheduleFrequencyInterval
                                    FrequencySubdayType       = $CopyScheduleFrequencySubdayType
                                    FrequencySubdayInterval   = $CopyScheduleFrequencySubdayInterval
                                    FrequencyRelativeInterval = $CopyScheduleFrequencyRelativeInterval
                                    FrequencyRecurrenceFactor = $CopyScheduleFrequencyRecurrenceFactor
                                    StartDate                 = $CopyScheduleStartDate
                                    EndDate                   = $CopyScheduleEndDate
                                    StartTime                 = $CopyScheduleStartTime
                                    EndTime                   = $CopyScheduleEndTime
                                    Force                     = $Force
                                }
                                $null = New-DbaAgentSchedule @splatCopySchedule
                            }

                            Write-Message -Message "Create restore job schedule $DatabaseRestoreSchedule" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                            #Variable $RestoreJobSchedule marked as unused by PSScriptAnalyzer replaced with $null for catching output
                            $splatRestoreSchedule = @{
                                SqlInstance               = $destInstance
                                SqlCredential             = $DestinationSqlCredential
                                Job                       = $DatabaseRestoreJob
                                Schedule                  = $DatabaseRestoreSchedule
                                FrequencyType             = $RestoreScheduleFrequencyType
                                FrequencyInterval         = $RestoreScheduleFrequencyInterval
                                FrequencySubdayType       = $RestoreScheduleFrequencySubdayType
                                FrequencySubdayInterval   = $RestoreScheduleFrequencySubdayInterval
                                FrequencyRelativeInterval = $RestoreScheduleFrequencyRelativeInterval
                                FrequencyRecurrenceFactor = $RestoreScheduleFrequencyRecurrenceFactor
                                StartDate                 = $RestoreScheduleStartDate
                                EndDate                   = $RestoreScheduleEndDate
                                StartTime                 = $RestoreScheduleStartTime
                                EndTime                   = $RestoreScheduleEndTime
                                Force                     = $Force
                            }
                            $null = New-DbaAgentSchedule @splatRestoreSchedule

                            Write-Message -Message "Configuring logshipping for secondary database." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                            $splatSecondaryDatabase = @{
                                SqlInstance               = $destInstance
                                SqlCredential             = $DestinationSqlCredential
                                SecondaryDatabase         = $SecondaryDatabase
                                PrimaryServer             = $SourceSqlInstance
                                PrimarySqlCredential      = $SourceSqlCredential
                                PrimaryDatabase           = $($db.Name)
                                RestoreDelay              = $RestoreDelay
                                RestoreMode               = $DatabaseStatus
                                DisconnectUsers           = $DisconnectUsers
                                RestoreThreshold          = $RestoreThreshold
                                ThresholdAlertEnabled     = $SecondaryThresholdAlertEnabled
                                HistoryRetention          = $HistoryRetention
                                MonitorServer             = $SecondaryMonitorServer
                                MonitorServerSecurityMode = $SecondaryMonitorServerSecurityMode
                                MonitorCredential         = $SecondaryMonitorCredential
                            }
                            New-DbaLogShippingSecondaryDatabase @splatSecondaryDatabase

                            # Skip copy job enable/disable for Azure (no copy job exists)
                            if (-not $UseAzure) {
                                # Check if the copy job needs to be enabled or disabled
                                if ($CopyScheduleDisabled) {
                                    $null = Set-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseCopyJob -Disabled
                                } else {
                                    $null = Set-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseCopyJob -Enabled
                                }
                            }

                            # Check if the restore job needs to be enabled or disabled
                            if ($RestoreScheduleDisabled) {
                                $null = Set-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseRestoreJob -Disabled
                            } else {
                                $null = Set-DbaAgentJob -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -Job $DatabaseRestoreJob -Enabled
                            }

                        } catch {
                            $setupResult = "Failed"
                            $comment = "Something went wrong setting up log shipping for secondary instance"
                            Stop-Function -Message "Something went wrong setting up log shipping for secondary instance.`n$($_.Exception.Message)" -ErrorRecord $_ -Target $destInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                        }
                    }
                }
                #endregion Set up log shipping on the secondary instance

                Write-Message -Message "Completed configuring log shipping for database $db" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                [PSCustomObject]@{
                    PrimaryInstance   = $SourceServer.DomainInstanceName
                    SecondaryInstance = $DestinationServer.DomainInstanceName
                    PrimaryDatabase   = $($db.Name)
                    SecondaryDatabase = $SecondaryDatabase
                    Result            = $setupResult
                    Comment           = $comment
                }

            } # for each database
        } # end for each destination server
    }
    @{ __w4038State = @{ carry = $__state.carry; interrupted = ([bool]$__state.interrupted -or [bool](Get-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -ErrorAction Ignore -ValueOnly)) } }
} @__parameters -__state:$__state -__boundWhatIf:$__boundWhatIf -__boundConfirm:$__boundConfirm -__boundVerbose:$__boundVerbose -__boundDebug:$__boundDebug @__commonParameters 3>&1 2>&1
""";

    private static string ProcessScript => ProcessScriptA + "\n" + ProcessScriptB + "\n" + ProcessScriptC;
}
