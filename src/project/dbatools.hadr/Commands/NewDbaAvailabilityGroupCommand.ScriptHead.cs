#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class NewDbaAvailabilityGroupCommand
{
    // PS: the begin block's Force -> ConfirmPreference suppression rides verbatim at the hop
    // top, then the source process block VERBATIM, first half (composed as ProcessScript =
    // head + newline + tail; re-parsed at build verification), CRLF-preserved. Bracketing the
    // body: the carried \ (destructively shifted per replica, so it SHORTENS and a
    // later piped record sees the shorter array) is seeded before the body, and the W3-082
    // prompt-state transplant is injected before any gate. Substitutions across both halves:
    // 34 -FunctionName appends (28 Stop-Function + 6 Write-Message) and the single Test-Bound
    // rewrite (SOURCE comment); stripping reproduces the source bytes byte-exact.
    private const string ProcessScriptHead = """
param($Primary, $PrimarySqlCredential, $Secondary, $SecondarySqlCredential, $Name, $ClusterType, $AutomatedBackupPreference, $FailureConditionLevel, $HealthCheckTimeout, $Database, $SharedPath, $AvailabilityMode, $FailoverMode, $BackupPriority, $ConnectionModeInPrimaryRole, $ConnectionModeInSecondaryRole, $SeedingMode, $Endpoint, $EndpointUrl, $Certificate, $IPAddress, $SubnetMask, $Port, $ClusterConnectionOption, $MasterKeySecurePassword, $IsContained, $ReuseSystemDatabases, $DtcSupport, $Basic, $DatabaseHealthTrigger, $Passthru, $UseLastBackup, $Force, $ConfigureXESession, $Dhcp, $EnableException, $__boundUseLastBackup, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Primary, [PSCredential]$PrimarySqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Secondary, [PSCredential]$SecondarySqlCredential, [string]$Name, [string]$ClusterType, [string]$AutomatedBackupPreference, [string]$FailureConditionLevel, [int]$HealthCheckTimeout, [string[]]$Database, [string]$SharedPath, [string]$AvailabilityMode, [string]$FailoverMode, [int]$BackupPriority, [string]$ConnectionModeInPrimaryRole, [string]$ConnectionModeInSecondaryRole, [string]$SeedingMode, [string]$Endpoint, [string[]]$EndpointUrl, [string]$Certificate, [ipaddress[]]$IPAddress, [ipaddress]$SubnetMask, [int]$Port, [string]$ClusterConnectionOption, [Security.SecureString]$MasterKeySecurePassword, $IsContained, $ReuseSystemDatabases, $DtcSupport, $Basic, $DatabaseHealthTrigger, $Passthru, $UseLastBackup, $Force, $ConfigureXESession, $Dhcp, $EnableException, $__boundUseLastBackup, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($Force) { $ConfirmPreference = 'none' }

    # cross-record PARAMETER state: the source shifts $EndpointUrl destructively once per
    # replica, and parameters are fn-scope, so a later piped record starts from the SHORTENED
    # array (and then trips the element-count validation). Seed it before the body runs.
    if ($null -ne $__state -and $__state.ContainsKey('endpointUrl')) {
        # assign even when the carried value is $null: the per-replica shifts can CONSUME the
        # array entirely, and that consumed state is exactly what the next record must observe -
        # it is what makes the element-count validation fire on the following record
        $EndpointUrl = $__state.endpointUrl
    }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified)
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "New-DbaAvailabilityGroup: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        $stepCounter = $wait = 0

        if ($Force -and $Secondary -and (-not $SharedPath -and -not $UseLastBackup) -and ($SeedingMode -ne 'Automatic')) {
            Stop-Function -Message "SharedPath or UseLastBackup is required when Force is used" -FunctionName New-DbaAvailabilityGroup
            return
        }

        if ($EndpointUrl) {
            if ($EndpointUrl.Count -ne (1 + $Secondary.Count)) {
                Stop-Function -Message "The number of elements in EndpointUrl is not correct" -FunctionName New-DbaAvailabilityGroup
                return
            }
            foreach ($epUrl in $EndpointUrl) {
                if ($epUrl -notmatch 'TCP://.+:\d+') {
                    Stop-Function -Message "EndpointUrl '$epUrl' not in correct format 'TCP://system-address:port'" -FunctionName New-DbaAvailabilityGroup
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
            Stop-Function -Message "You cannot specify both an IP address and the Dhcp switch for the listener." -FunctionName New-DbaAvailabilityGroup
            return
        }

        try {
            $server = Connect-DbaInstance -SqlInstance $Primary -SqlCredential $PrimarySqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Primary -FunctionName New-DbaAvailabilityGroup
            return
        }

        if ($SeedingMode -eq 'Automatic' -and $server.VersionMajor -lt 13) {
            Stop-Function -Message "Automatic seeding mode only supported in SQL Server 2016 and above" -Target $Primary -FunctionName New-DbaAvailabilityGroup
            return
        }

        if ($Basic -and $server.VersionMajor -lt 13) {
            Stop-Function -Message "Basic availability groups are only supported in SQL Server 2016 and above" -Target $Primary -FunctionName New-DbaAvailabilityGroup
            return
        }

        if ($IsContained -and $server.VersionMajor -lt 16) {
            Stop-Function -Message "Contained availability groups are only supported in SQL Server 2022 and above" -Target $Primary -FunctionName New-DbaAvailabilityGroup
            return
        }

        if ($ReuseSystemDatabases -and $IsContained -eq $false) {
            Stop-Function -Message "Reuse system databases is only applicable in contained availability groups" -Target $Primary -FunctionName New-DbaAvailabilityGroup
            return
        }

        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Checking requirements"
        $requirementsFailed = $false

        if (-not $server.IsHadrEnabled) {
            $requirementsFailed = $true
            Write-Message -Level Warning -Message "Availability Group (HADR) is not configured for the instance: $Primary. Use Enable-DbaAgHadr to configure the instance." -FunctionName New-DbaAvailabilityGroup -ModuleName "dbatools"
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
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaAvailabilityGroup
                }

                if (-not $second.IsHadrEnabled) {
                    $requirementsFailed = $true
                    Write-Message -Level Warning -Message "Availability Group (HADR) is not configured for the instance: $instance. Use Enable-DbaAgHadr to configure the instance." -FunctionName New-DbaAvailabilityGroup -ModuleName "dbatools"
                }

                if ($SeedingMode -eq "Automatic") {
                    $secondarypath = Get-DbaDefaultPath -SqlInstance $second
                    if ($primarypath.Data -ne $secondarypath.Data) {
                        Write-Message -Level Warning -Message "Primary and secondary ($instance) default data paths do not match. Trying anyway." -FunctionName New-DbaAvailabilityGroup -ModuleName "dbatools"
                    }
                    if ($primarypath.Log -ne $secondarypath.Log) {
                        Write-Message -Level Warning -Message "Primary and secondary ($instance) default log paths do not match. Trying anyway." -FunctionName New-DbaAvailabilityGroup -ModuleName "dbatools"
                    }
                }
            }
        }

        if ($requirementsFailed) {
            Write-Progress -Activity "Adding new availability group" -Completed
            Stop-Function -Message "Prerequisites are not completly met, so stopping here. See warning messages for details." -FunctionName New-DbaAvailabilityGroup
            return
        }

        # Don't reuse $server here, it fails
        if (Get-DbaAvailabilityGroup -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -AvailabilityGroup $Name) {
            Write-Progress -Activity "Adding new availability group" -Completed
            Stop-Function -Message "Availability group named $Name already exists on $Primary" -FunctionName New-DbaAvailabilityGroup
            return
        }

        if ($Certificate) {
            $cert = Get-DbaDbCertificate -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Certificate $Certificate
            if (-not $cert) {
                Write-Progress -Activity "Adding new availability group" -Completed
                Stop-Function -Message "Certificate $Certificate does not exist on $Primary" -Target $Primary -FunctionName New-DbaAvailabilityGroup
                return
            }
        }

        if (($SharedPath)) {
            if (-not (Test-DbaPath -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Path $SharedPath)) {
                Write-Progress -Activity "Adding new availability group" -Completed
                Stop-Function -Continue -Message "Cannot access $SharedPath from $Primary" -FunctionName New-DbaAvailabilityGroup
                return
            }
        }

        if ($Database -and -not $UseLastBackup -and -not $SharedPath -and $Secondary -and $SeedingMode -ne 'Automatic') {
            Write-Progress -Activity "Adding new availability group" -Completed
            Stop-Function -Continue -Message "You must specify a SharedPath when adding databases to a manually seeded availability group" -FunctionName New-DbaAvailabilityGroup
            return
        }

        if ($server.HostPlatform -eq "Linux") {
            # New to SQL Server 2017 (14.x) is the introduction of a cluster type for AGs. For Linux, there are two valid values: External and None.
            if ($ClusterType -notin "External", "None") {
                Write-Progress -Activity "Adding new availability group" -Completed
                Stop-Function -Continue -Message "Linux only supports ClusterType of External or None" -FunctionName New-DbaAvailabilityGroup
                return
            }
            # Microsoft Distributed Transaction Coordinator (DTC) is not supported under Linux in SQL Server 2017
            if ($DtcSupport) {
                Write-Progress -Activity "Adding new availability group" -Completed
                Stop-Function -Continue -Message "Microsoft Distributed Transaction Coordinator (DTC) is not supported under Linux" -FunctionName New-DbaAvailabilityGroup
                return
            }
        }

        if ($ClusterType -eq "None" -and $server.VersionMajor -lt 14) {
            Write-Progress -Activity "Adding new availability group" -Completed
            Stop-Function -Message "ClusterType of None only supported in SQL Server 2017 and above" -FunctionName New-DbaAvailabilityGroup
            return
        }

        # Check if ConnectionModeInSecondaryRole is set on Standard Edition
        if ($ConnectionModeInSecondaryRole -and $ConnectionModeInSecondaryRole -ne "AllowNoConnections") {
            $instances = @($server) + $secondaries
            foreach ($instance in $instances) {
                if ($instance.EngineEdition -eq "Standard") {
                    Write-Message -Level Warning -Message "ConnectionModeInSecondaryRole is not supported on Standard Edition. The setting will be ignored on $($instance.Name). Consider using Enterprise or Developer Edition for read-only secondary replicas." -FunctionName New-DbaAvailabilityGroup -ModuleName "dbatools"
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
                Stop-Function -Message "Cannot setup mirroring on database ($($primarydb.Name)) due to its current mirroring state: $($primarydb.MirroringStatus)" -FunctionName New-DbaAvailabilityGroup
                return
            }

            if ($primarydb.Status -ne "Normal") {
                Write-Progress -Activity "Adding new availability group" -Completed
                Stop-Function -Message "Cannot setup mirroring on database ($($primarydb.Name)) due to its current state: $($primarydb.Status)" -FunctionName New-DbaAvailabilityGroup
                return
            }

            if ($primarydb.RecoveryModel -ne "Full") {
                if ($__boundUseLastBackup) { # SOURCE: if ((Test-Bound -ParameterName UseLastBackup)) {
                    Write-Progress -Activity "Adding new availability group" -Completed
                    Stop-Function -Message "$($primarydb.Name) not set to full recovery. UseLastBackup cannot be used." -FunctionName New-DbaAvailabilityGroup
                    return
                } else {
                    Set-DbaDbRecoveryModel -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Database $primarydb.Name -RecoveryModel Full
                }
            }
        }

        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Creating availability group named $Name on $Primary"

        # Start work
""";
}
