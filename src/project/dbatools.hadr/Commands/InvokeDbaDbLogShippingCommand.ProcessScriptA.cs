#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class InvokeDbaDbLogShippingCommand
{
    // PS: the process block VERBATIM, first third (composed as ProcessScript =
    // A + newline + B + newline + C; re-parsed at build verification),
    // CRLF-preserved. Whole-record hop. Frame: the caller-bound parameter-table splat
    // (bound-only, same contract as the begin frame),
    // the 47-variable carry injection from the begin sentinel, and a reproduction
    // of begin line 588's `if ($Force) { $ConfirmPreference = 'none' }` (fn-scope
    // suppression the 7 inner-PSCmdlet gates read - begin set it once in the
    // function world; the hop scope needs it re-established). The source's
    // process-top Test-FunctionInterrupt rides verbatim (within a fresh hop it
    // scope-walks to nothing; the cross-hop latch is carried via the sentinel and
    // gated C#-side). Substitutions across all thirds: 96 -FunctionName appends
    // only; stripping reproduces the source bytes cmp-exact.
    private const string ProcessScriptA = """
param($__parameters, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SourceSqlInstance, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$DestinationSqlInstance, [System.Management.Automation.PSCredential]$SourceSqlCredential, [System.Management.Automation.PSCredential]$SourceCredential, [System.Management.Automation.PSCredential]$DestinationSqlCredential, [System.Management.Automation.PSCredential]$DestinationCredential, [object[]]$Database, [string]$SharedPath, [string]$LocalPath, [string]$AzureBaseUrl, [string]$AzureCredential, [string]$BackupJob, [int]$BackupRetention, [string]$BackupSchedule, $BackupScheduleFrequencyType, [object[]]$BackupScheduleFrequencyInterval, $BackupScheduleFrequencySubdayType, [int]$BackupScheduleFrequencySubdayInterval, $BackupScheduleFrequencyRelativeInterval, [int]$BackupScheduleFrequencyRecurrenceFactor, [string]$BackupScheduleStartDate, [string]$BackupScheduleEndDate, [string]$BackupScheduleStartTime, [string]$BackupScheduleEndTime, [int]$BackupThreshold, [string]$CopyDestinationFolder, [string]$CopyJob, [int]$CopyRetention, [string]$CopySchedule, $CopyScheduleFrequencyType, [object[]]$CopyScheduleFrequencyInterval, $CopyScheduleFrequencySubdayType, [int]$CopyScheduleFrequencySubdayInterval, $CopyScheduleFrequencyRelativeInterval, [int]$CopyScheduleFrequencyRecurrenceFactor, [string]$CopyScheduleStartDate, [string]$CopyScheduleEndDate, [string]$CopyScheduleStartTime, [string]$CopyScheduleEndTime, [string]$FullBackupPath, [int]$HistoryRetention, [string]$PrimaryMonitorServer, [System.Management.Automation.PSCredential]$PrimaryMonitorCredential, $PrimaryMonitorServerSecurityMode, [string]$RestoreDataFolder, [string]$RestoreLogFolder, [int]$RestoreDelay, [int]$RestoreAlertThreshold, [string]$RestoreJob, [int]$RestoreRetention, [string]$RestoreSchedule, $RestoreScheduleFrequencyType, [object[]]$RestoreScheduleFrequencyInterval, $RestoreScheduleFrequencySubdayType, [int]$RestoreScheduleFrequencySubdayInterval, $RestoreScheduleFrequencyRelativeInterval, [int]$RestoreScheduleFrequencyRecurrenceFactor, [string]$RestoreScheduleStartDate, [string]$RestoreScheduleEndDate, [string]$RestoreScheduleStartTime, [string]$RestoreScheduleEndTime, [int]$RestoreThreshold, [string]$SecondaryDatabasePrefix, [string]$SecondaryDatabaseSuffix, [string]$SecondaryMonitorServer, [System.Management.Automation.PSCredential]$SecondaryMonitorCredential, $SecondaryMonitorServerSecurityMode, [string]$StandbyDirectory, [string]$UseBackupFolder, [switch]$BackupScheduleDisabled, [switch]$CompressBackup, [switch]$CopyScheduleDisabled, [switch]$DisconnectUsers, [switch]$Force, [switch]$GenerateFullBackup, [switch]$IgnoreFileChecks, [switch]$NoInitialization, [switch]$NoRecovery, [switch]$PrimaryThresholdAlertEnabled, [switch]$RestoreScheduleDisabled, [switch]$SecondaryThresholdAlertEnabled, [switch]$Standby, [switch]$UseExistingFullBackup, [switch]$EnableException, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($__carryName in $__state.carry.Keys) { Set-Variable -Name $__carryName -Value $__state.carry[$__carryName] -WhatIf:$false -Confirm:$false }
    if ($Force) { $ConfirmPreference = 'none' } # FRAME: begin line 588 fn-scope suppression, re-established per hop

    . {

        if (Test-FunctionInterrupt) { return }

        foreach ($destInstance in $DestinationSqlInstance) {

            $setupResult = "Success"
            $comment = ""

            # Try connecting to the instance
            try {
                $destinationServer = Connect-DbaInstance -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destInstance -Continue -FunctionName Invoke-DbaDbLogShipping
            }

            $DestinationServerName, $DestinationInstanceName = $destInstance.FullName.Split("\")

            if ($null -eq $DestinationInstanceName) {
                $DestinationInstanceName = "MSSQLSERVER"
            }

            $IsDestinationLocal = $false

            # Check if it's local or remote
            if ($DestinationServerName -in ".", "localhost", $env:ServerName, "127.0.0.1") {
                $IsDestinationLocal = $true
            }

            # Check the instance names and the database settings
            if (($SourceSqlInstance -eq $destInstance) -and (-not $SecondaryDatabasePrefix -or $SecondaryDatabaseSuffix)) {
                $setupResult = "Failed"
                $comment = "The destination database is the same as the source"
                Stop-Function -Message "The destination database is the same as the source`nPlease enter a prefix or suffix using -SecondaryDatabasePrefix or -SecondaryDatabaseSuffix." -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
                return
            }

            if ($DestinationServer.ConnectionContext.StatementTimeout -ne 0) {
                $DestinationServer.ConnectionContext.StatementTimeout = 0
                Write-Message -Message "Connection timeout of $DestinationServer is set to 0" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
            }

            # Check the copy destination
            if (-not $CopyDestinationFolder) {
                if ($UseAzure) {
                    # For Azure, use the same URL as source (no actual copy needed)
                    $CopyDestinationFolder = $AzureBaseUrl
                    Write-Message -Message "Using Azure blob storage URL for copy destination (no local copy): $CopyDestinationFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                } else {
                    # Make a default copy destination by retrieving the backup folder and adding a directory
                    $CopyDestinationFolder = "$($DestinationServer.Settings.BackupDirectory)\Logshipping"

                    # Check to see if the path already exists
                    Write-Message -Message "Testing copy destination path $CopyDestinationFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                    if (Test-DbaPath -Path $CopyDestinationFolder -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) {
                        Write-Message -Message "Copy destination $CopyDestinationFolder already exists" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                    } else {
                        # Check if force is being used
                        if (-not $Force) {
                            # Set up the confirm part
                            $message = "The copy destination is missing. Do you want to use the default $($CopyDestinationFolder)?"
                            $choiceYes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Answer Yes."
                            $choiceNo = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Answer No."
                            $options = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)
                            $result = $host.ui.PromptForChoice($title, $message, $options, 0)

                            # Check the result from the confirm
                            switch ($result) {
                                # If yes
                                0 {
                                    # Try to create the new directory
                                    try {
                                        # If the destination server is remote and the credential is set
                                        if (-not $IsDestinationLocal -and $DestinationCredential) {
                                            Invoke-Command2 -ComputerName $DestinationServerName -Credential $DestinationCredential -ScriptBlock {
                                                Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                                $null = New-Item -Path $CopyDestinationFolder -ItemType Directory -Force:$Force
                                            }
                                        }
                                        # If the server is local and the credential is set
                                        elseif ($DestinationCredential) {
                                            Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
                                                Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                                $null = New-Item -Path $CopyDestinationFolder -ItemType Directory -Force:$Force
                                            }
                                        }
                                        # If the server is local and the credential is not set
                                        else {
                                            Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                            $null = New-Item -Path $CopyDestinationFolder -ItemType Directory -Force:$Force
                                        }
                                        Write-Message -Message "Copy destination $CopyDestinationFolder created." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                    } catch {
                                        $setupResult = "Failed"
                                        $comment = "Something went wrong creating the copy destination folder"
                                        Stop-Function -Message "Something went wrong creating the copy destination folder $CopyDestinationFolder. `n$_" -Target $destInstance -ErrorRecord $_ -FunctionName Invoke-DbaDbLogShipping
                                        return
                                    }
                                }
                                1 {
                                    $setupResult = "Failed"
                                    $comment = "Copy destination is a mandatory parameter"
                                    Stop-Function -Message "Copy destination is a mandatory parameter. Please make sure the value is entered." -Target $destInstance -FunctionName Invoke-DbaDbLogShipping
                                    return
                                }
                            } # switch
                        } # if not force
                        else {
                            # Try to create the copy destination on the local server
                            try {
                                Write-Message -Message "Creating copy destination folder $CopyDestinationFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                $null = New-Item -Path $CopyDestinationFolder -ItemType Directory -Force:$Force
                                Write-Message -Message "Copy destination $CopyDestinationFolder created." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                            } catch {
                                $setupResult = "Failed"
                                $comment = "Something went wrong creating the copy destination folder"
                                Stop-Function -Message "Something went wrong creating the copy destination folder $CopyDestinationFolder. `n$_" -Target $destInstance -ErrorRecord $_ -FunctionName Invoke-DbaDbLogShipping
                                return
                            }
                        } # else not force
                    } # if test path copy destination
                } # else not Azure
            } # if not copy destination

            # Validate copy destination (skip for Azure since it's a URL)
            if (-not $UseAzure) {
                Write-Message -Message "Testing copy destination path $CopyDestinationFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                if ((Test-DbaPath -Path $CopyDestinationFolder -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                    $setupResult = "Failed"
                    $comment = "Copy destination folder $CopyDestinationFolder is not valid or can't be reached"
                    Stop-Function -Message "Copy destination folder $CopyDestinationFolder is not valid or can't be reached." -Target $destInstance -FunctionName Invoke-DbaDbLogShipping
                    return
                } elseif ($CopyDestinationFolder.StartsWith("\\") -and $CopyDestinationFolder -notmatch $RegexUnc) {
                    $setupResult = "Failed"
                    $comment = "Copy destination folder $CopyDestinationFolder has to be in the form of \\server\share"
                    Stop-Function -Message "Copy destination folder $CopyDestinationFolder has to be in the form of \\server\share." -Target $destInstance -FunctionName Invoke-DbaDbLogShipping
                    return
                }
            }

            if (-not ($SecondaryDatabasePrefix -or $SecondaryDatabaseSuffix) -and ($SourceServer.Name -eq $DestinationServer.Name) -and ($SourceServer.InstanceName -eq $DestinationServer.InstanceName)) {
                if ($Force) {
                    $SecondaryDatabaseSuffix = "_LS"
                } else {
                    $setupResult = "Failed"
                    $comment = "Destination database is the same as source database"
                    Stop-Function -Message "Destination database is the same as source database.`nPlease check the secondary server, database prefix or suffix or use -Force to set the secondary database using a suffix." -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
                    return
                }
            }

            # Check if standby is being used
            if ($Standby) {
                # Check the stand-by directory (skip for Azure SQL as it manages storage)
                if ($StandbyDirectory) {
                    # Check if the path is reachable for the destination server
                    if (-not $DestinationServer.IsAzure) {
                        if ((Test-DbaPath -Path $StandbyDirectory -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                            $setupResult = "Failed"
                            $comment = "The directory $StandbyDirectory cannot be reached by the destination instance"
                            Stop-Function -Message "The directory $StandbyDirectory cannot be reached by the destination instance. Please check the permission and credentials." -Target $destInstance -FunctionName Invoke-DbaDbLogShipping
                            return
                        }
                    }
                } elseif (-not $StandbyDirectory -and $Force) {
                    $StandbyDirectory = $destInstance.BackupDirectory
                    Write-Message -Message "Stand-by directory was not set. Setting it to $StandbyDirectory" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                } else {
                    $setupResult = "Failed"
                    $comment = "Please set the parameter -StandbyDirectory when using -Standby"
                    Stop-Function -Message "Please set the parameter -StandbyDirectory when using -Standby" -Target $SourceSqlInstance -FunctionName Invoke-DbaDbLogShipping
                    return
                }
            }

            # Loop through each of the databases
            foreach ($db in $DatabaseCollection) {

                # Check the status of the database
                if ($db.RecoveryModel -ne 'Full') {
                    $setupResult = "Failed"
                    $comment = "Database $db is not in FULL recovery mode"

                    Stop-Function -Message  "Database $db is not in FULL recovery mode" -Target $SourceSqlInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                }

                # Set the intital destination database
                $SecondaryDatabase = $db.Name

                # Set the database prefix
                if ($SecondaryDatabasePrefix) {
                    $SecondaryDatabase = "$SecondaryDatabasePrefix$($db.Name)"
                }

                # Set the database suffix
                if ($SecondaryDatabaseSuffix) {
                    $SecondaryDatabase += $SecondaryDatabaseSuffix
                }

                # Check is the database is already initialized a check if the database exists on the secondary instance
                if ($NoInitialization -and ($DestinationServer.Databases.Name -notcontains $SecondaryDatabase)) {
                    $setupResult = "Failed"
                    $comment = "Database $SecondaryDatabase needs to be initialized before log shipping setting can continue"

                    Stop-Function -Message "Database $SecondaryDatabase needs to be initialized before log shipping setting can continue." -Target $SourceSqlInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                }

                # Check the local backup path
                if ($LocalPath) {
                    if ($LocalPath.EndsWith("\")) {
                        $DatabaseLocalPath = "$LocalPath$($db.Name)"
                    } else {
                        $DatabaseLocalPath = "$LocalPath\$($db.Name)"
                    }
                } else {
                    $LocalPath = $SharedPath

                    if ($LocalPath.EndsWith("\")) {
                        $DatabaseLocalPath = "$LocalPath$($db.Name)"
                    } else {
                        $DatabaseLocalPath = "$LocalPath\$($db.Name)"
                    }
                }
                Write-Message -Message "Backup local path set to $DatabaseLocalPath." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                # Setting the backup network path for the database
                if ($UseAzure) {
                    # For Azure, append database name to URL path
                    $DatabaseSharedPath = "$SharedPath/$($db.Name)"
                    $DatabaseLocalPath = $DatabaseSharedPath
                    Write-Message -Message "Azure backup URL set to $DatabaseSharedPath." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                } else {
                    if ($SharedPath.EndsWith("\")) {
                        $DatabaseSharedPath = "$SharedPath$($db.Name)"
                    } else {
                        $DatabaseSharedPath = "$SharedPath\$($db.Name)"
                    }
                    Write-Message -Message "Backup network path set to $DatabaseSharedPath." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                }


                # Checking if the database network path exists (skip for Azure)
                if ($setupResult -ne 'Failed' -and -not $UseAzure) {
                    Write-Message -Message "Testing database backup network path $DatabaseSharedPath" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                    if ((Test-DbaPath -Path $DatabaseSharedPath -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential) -ne $true) {
                        # To to create the backup directory for the database
                        try {
                            Write-Message -Message "Database backup network path $DatabaseSharedPath not found. Trying to create it.." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                            Invoke-Command2 -Credential $SourceCredential -ScriptBlock {
                                Write-Message -Message "Creating backup folder $DatabaseSharedPath" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                $null = New-Item -Path $DatabaseSharedPath -ItemType Directory -Force:$Force
                            }
                        } catch {
                            $setupResult = "Failed"
                            $comment = "Something went wrong creating the backup directory"

                            Stop-Function -Message "Something went wrong creating the backup directory" -ErrorRecord $_ -Target $SourceSqlInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                        }
                    }
                }

                # Check if the backup job name is set
                if ($BackupJob) {
                    $DatabaseBackupJob = "$($BackupJob)$($db.Name)"
                } else {
                    $DatabaseBackupJob = "LSBackup_$($db.Name)"
                }
                Write-Message -Message "Backup job name set to $DatabaseBackupJob" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                # Check if the backup job schedule name is set
                if ($BackupSchedule) {
                    $DatabaseBackupSchedule = "$($BackupSchedule)$($db.Name)"
                } else {
                    $DatabaseBackupSchedule = "LSBackupSchedule_$($db.Name)"
                }
                Write-Message -Message "Backup job schedule name set to $DatabaseBackupSchedule" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                # Check if secondary database is present on secondary instance
                if (-not $Force -and -not $NoInitialization -and ($DestinationServer.Databases[$SecondaryDatabase].Status -ne 'Restoring') -and ($DestinationServer.Databases.Name -contains $SecondaryDatabase)) {
                    $setupResult = "Failed"
                    $comment = "Secondary database already exists on instance"

                    Stop-Function -Message "Secondary database already exists on instance $destInstance." -Target $destInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                }

                # Check if the secondary database needs to be initialized
                if ($setupResult -ne 'Failed') {
                    if (-not $NoInitialization) {
                        # Check if the secondary database exists on the secondary instance
                        if ($DestinationServer.Databases.Name -notcontains $SecondaryDatabase) {
                            # Check if force is being used and no option to generate the full backup is set
                            if ($Force -and -not ($GenerateFullBackup -or $UseExistingFullBackup)) {
                                # Set the option to generate a full backup
                                Write-Message -Message "Set option to initialize secondary database with full backup" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                $GenerateFullBackup = $true
                            } elseif (-not $Force -and -not $GenerateFullBackup -and -not $UseExistingFullBackup -and -not $UseBackupFolder) {
                                # Set up the confirm part
                                $message = "The database $SecondaryDatabase does not exist on instance $destInstance. `nDo you want to initialize it by generating a full backup?"
                                $choiceYes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Answer Yes."
                                $choiceNo = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Answer No."
                                $options = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)
                                $result = $host.ui.PromptForChoice($title, $message, $options, 0)

                                # Check the result from the confirm
                                switch ($result) {
                                    # If yes
                                    0 {
                                        # Set the option to generate a full backup
                                        Write-Message -Message "Set option to initialize secondary database with full backup." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                        $GenerateFullBackup = $true
                                    }
                                    1 {
                                        $setupResult = "Failed"
                                        $comment = "The database is not initialized on the secondary instance"

                                        Stop-Function -Message "The database is not initialized on the secondary instance. `nPlease initialize the database on the secondary instance, use -GenerateFullbackup or use -Force." -Target $destInstance -FunctionName Invoke-DbaDbLogShipping
                                        return
                                    }
                                } # switch
                            }
                        }
                    }
                }


""";
}
