#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class NewDbaAvailabilityGroupCommand
{
    // PS: the source process block VERBATIM, second half (see ScriptHead for framing and the
    // substitution inventory). The tail closes the dot-block, then harvests the cross-record
    // state - the destructively shifted \ and the ShouldProcess prompt status -
    // into the sentinel ProcessRecord captures.
    private const string ProcessScriptTail = """
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
                Stop-Function -Message $msg -ErrorRecord $_ -Target $Primary -FunctionName New-DbaAvailabilityGroup
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
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $second -Continue -FunctionName New-DbaAvailabilityGroup
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
            Stop-Function -Message $msg -ErrorRecord $_ -Target $Primary -FunctionName New-DbaAvailabilityGroup
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
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $second -Continue -FunctionName New-DbaAvailabilityGroup
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
            Write-Message -Level Warning -Message "One or more replicas are still not connected and ready. If you encounter this error often, please let us know and we'll increase the timeout. Moving on and trying the next step." -FunctionName New-DbaAvailabilityGroup -ModuleName "dbatools"
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
                    Stop-Function -Message "Failure" -ErrorRecord $_ -FunctionName New-DbaAvailabilityGroup
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
                        Stop-Function -Message "Failed to remove databases from secondary replicas." -ErrorRecord $_ -FunctionName New-DbaAvailabilityGroup
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
                if ($MasterKeySecurePassword) { $addDatabaseParams['MasterKeySecurePassword'] = $MasterKeySecurePassword }
                try {
                    $null = Add-DbaAgDatabase @addDatabaseParams
                } catch {
                    Write-Progress -Activity "Adding new availability group" -Completed
                    Stop-Function -Message "Failed to add databases to Availability Group." -ErrorRecord $_ -FunctionName New-DbaAvailabilityGroup
                }
            }
        }
        Write-Progress -Activity "Adding new availability group" -Completed

        # Get results
        Get-DbaAvailabilityGroup -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -AvailabilityGroup $Name
    }

    @{ __w4043State = @{ endpointUrl = $EndpointUrl; shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $Primary $PrimarySqlCredential $Secondary $SecondarySqlCredential $Name $ClusterType $AutomatedBackupPreference $FailureConditionLevel $HealthCheckTimeout $Database $SharedPath $AvailabilityMode $FailoverMode $BackupPriority $ConnectionModeInPrimaryRole $ConnectionModeInSecondaryRole $SeedingMode $Endpoint $EndpointUrl $Certificate $IPAddress $SubnetMask $Port $ClusterConnectionOption $MasterKeySecurePassword $IsContained $ReuseSystemDatabases $DtcSupport $Basic $DatabaseHealthTrigger $Passthru $UseLastBackup $Force $ConfigureXESession $Dhcp $EnableException $__boundUseLastBackup $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
