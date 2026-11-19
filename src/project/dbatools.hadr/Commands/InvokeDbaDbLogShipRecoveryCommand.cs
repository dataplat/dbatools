#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Recovers log-shipped secondary databases from standby or restoring state to normal.
/// Port of public/Invoke-DbaDbLogShipRecovery.ps1; surface pinned by
/// migration/baselines/Invoke-DbaDbLogShipRecovery.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbLogShipRecovery", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class InvokeDbaDbLogShipRecoveryCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>The log-shipped secondary databases to recover.</summary>
    [Parameter(Position = 1)]
    public string[]? Database { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 2)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Database objects piped from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>Leaves the database in restoring state, skipping RESTORE WITH RECOVERY.</summary>
    [Parameter]
    public SwitchParameter NoRecovery { get; set; }

    /// <summary>Recovers all log-shipped databases and suppresses confirmation prompts.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>Polling interval in seconds between copy/restore job status checks.</summary>
    [Parameter(Position = 4)]
    public int Delay { get; set; } = 5;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Invoke-DbaDbLogShipRecovery");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop per the W3-005/W4-011 convention: the begin block's
        // Force -> ConfirmPreference suppression and $stepCounter seed ride at the
        // hop top, and every ShouldProcess gate runs on the INNER scriptblock's own
        // $Pscmdlet - the suppression is hop-scope-local, so -Force still silences
        // the prompt (the ratified Copy-family/W3-005 handling; NOT routed to
        // $__realCmdlet, which reads the outer preference and would re-prompt under
        // -Force). Because InputObject is a per-record VFP axis, the ShouldProcess
        // Yes/No-to-All answer must survive BETWEEN piped records the way the
        // source's single function-scope $Pscmdlet does: the W3-082 prompt-state
        // transplant carries lastShouldProcessContinueStatus through the
        // __w4039State sentinel. The loop-less validation Stop-Function+return sites
        // exit the record via the dot-block frame; the -Continue sites are loop-local.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4039State"))
            {
                _state = sentinel["__w4039State"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, Database, SqlCredential, NoRecovery.ToBool(), Force.ToBool(),
            InputObject, Delay, EnableException.ToBool(), _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block's Force -> ConfirmPreference suppression and $stepCounter
    // seed ride verbatim at the hop top, then the source process block VERBATIM,
    // CRLF-preserved and cmp-proven byte-exact after stripping 26 -FunctionName
    // appends (13 Stop-Function + 13 Write-Message). ShouldProcess gates use the
    // inner block's own $Pscmdlet; the dot-block preserves the validation returns.
    // Write-ProgressHelper's Get-PSCallStack-derived step count affects only the
    // Write-Progress percent (progress stream, not probe-visible) and is dispositioned
    // per the W4-001 Write-Progress precedent - no named-wrapper shim.
    private const string ProcessScript = """
param($SqlInstance, $Database, $SqlCredential, $NoRecovery, $Force, $InputObject, $Delay, $EnableException, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [string[]]$Database, [PSCredential]$SqlCredential, $NoRecovery, $Force, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, [int]$Delay, $EnableException, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($Force) { $ConfirmPreference = 'none' }

    $stepCounter = 0

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified)
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Invoke-DbaDbLogShipRecovery: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        foreach ($instance in $SqlInstance) {
            if (-not $Force -and -not $Database) {
                Stop-Function -Message "You must specify a -Database or -Force for all databases" -Target $server.name -FunctionName Invoke-DbaDbLogShipRecovery
                return
            }
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        # Loop through all the databases
        foreach ($db in $InputObject) {
            $stepCounter = 0
            $server = $db.Parent
            $instance = $server.Name
            $activity = "Performing log shipping recovery for $($db.Name) on $($server.Name)"
            # Try to get the agent service details
            try {
                # Get the service details
                $agentStatus = $server.Query("SELECT COUNT(*) AS AgentCount FROM master.dbo.sysprocesses WITH (NOLOCK) WHERE program_name LIKE 'SQLAgent%'")

                if ($agentStatus.AgentCount -lt 1) {
                    Stop-Function -Message "The agent service is not in a running state. Please start the service." -Target $server.name -FunctionName Invoke-DbaDbLogShipRecovery
                    return
                }
            } catch {
                Stop-Function -Message "Unable to get SQL Server Agent Service status" -ErrorRecord $_ -Target $server.name -FunctionName Invoke-DbaDbLogShipRecovery
                return
            }
            # Query for retrieving the log shipping information
            $query = "SELECT lss.primary_server, lss.primary_database, lsd.secondary_database, lss.backup_source_directory,
                    lss.backup_destination_directory, lss.last_copied_file, lss.last_copied_date,
                    lsd.last_restored_file, sj1.name AS 'copyjob', sj2.name AS 'restorejob'
                FROM msdb.dbo.log_shipping_secondary AS lss
                    INNER JOIN msdb.dbo.log_shipping_secondary_databases AS lsd ON lsd.secondary_id = lss.secondary_id
                    INNER JOIN msdb.dbo.sysjobs AS sj1 ON sj1.job_id = lss.copy_job_id
                    INNER JOIN msdb.dbo.sysjobs AS sj2 ON sj2.job_id = lss.restore_job_id
                WHERE lsd.secondary_database = '$($db.Name)'"

            # Retrieve the log shipping information from the secondary instance
            try {
                Write-Message -Message "Retrieving log shipping information from the secondary instance" -Level Verbose -FunctionName Invoke-DbaDbLogShipRecovery -ModuleName "dbatools"
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Retrieving log shipping information from the secondary instance"
                $logshipping_details = $server.Query($query)
            } catch {
                Stop-Function -Message "Error retrieving the log shipping details: $($_.Exception.Message)" -ErrorRecord $_ -Target $server.name -FunctionName Invoke-DbaDbLogShipRecovery
                return
            }

            # Check if there are any databases to recover
            if ($null -eq $logshipping_details) {
                Stop-Function -Message "The database $db is not configured as a secondary database for log shipping." -Continue -FunctionName Invoke-DbaDbLogShipRecovery
            } else {
                # Loop through each of the log shipped databases
                foreach ($ls in $logshipping_details) {
                    $secondarydb = $ls.secondary_database

                    $recoverResult = "Success"
                    $comment = ""
                    $jobOutputs = @()

                    # Check if the database is in the right state
                    if ($server.Databases[$secondarydb].Status -notin ('Normal, Standby', 'Standby', 'Restoring')) {
                        Stop-Function -Message "The database $db doesn't have the right status to be recovered" -Continue -FunctionName Invoke-DbaDbLogShipRecovery
                    } else {
                        Write-Message -Message "Started Recovery for $secondarydb" -Level Verbose -FunctionName Invoke-DbaDbLogShipRecovery -ModuleName "dbatools"

                        # Start the job to get the latest files
                        if ($PSCmdlet.ShouldProcess($server.name, ("Starting copy job $($ls.copyjob)"))) {
                            Write-Message -Message "Starting copy job $($ls.copyjob)" -Level Verbose -FunctionName Invoke-DbaDbLogShipRecovery -ModuleName "dbatools"

                            Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Starting copy job"
                            try {
                                $null = Start-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob
                            } catch {
                                $recoverResult = "Failed"
                                $comment = "Something went wrong starting the copy job $($ls.copyjob)"
                                Stop-Function -Message "Something went wrong starting the copy job.`n$($_)" -ErrorRecord $_ -Target $server.name -FunctionName Invoke-DbaDbLogShipRecovery
                            }

                            if ($recoverResult -ne 'Failed') {
                                Write-Message -Message "Copying files to $($ls.backup_destination_directory)" -Level Verbose -FunctionName Invoke-DbaDbLogShipRecovery -ModuleName "dbatools"

                                Write-Message -Message "Waiting for the copy action to complete.." -Level Verbose -FunctionName Invoke-DbaDbLogShipRecovery -ModuleName "dbatools"

                                # Get the job status
                                $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob

                                while ($jobStatus.CurrentRunStatus -ne 'Idle') {
                                    # Sleep for while to let the files be copied
                                    Start-Sleep -Seconds $Delay

                                    # Get the job status
                                    $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob
                                }

                                # Check the lat outcome of the job
                                if ($jobStatus.LastRunOutcome -eq 'Failed') {
                                    $recoverResult = "Failed"
                                    $comment = "The copy job for database $db failed. Please check the error log."
                                    Stop-Function -Message "The copy job for database $db failed. Please check the error log." -FunctionName Invoke-DbaDbLogShipRecovery
                                }

                                $jobOutputs += $jobStatus

                                Write-Message -Message "Copying of backup files finished" -Level Verbose -FunctionName Invoke-DbaDbLogShipRecovery -ModuleName "dbatools"
                            }
                        } # if should process

                        # Disable the log shipping copy job on the secondary instance
                        if ($recoverResult -ne 'Failed') {
                            Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Disabling copy job"

                            if ($PSCmdlet.ShouldProcess($server.name, "Disabling copy job $($ls.copyjob)")) {
                                try {
                                    Write-Message -Message "Disabling copy job $($ls.copyjob)" -Level Verbose -FunctionName Invoke-DbaDbLogShipRecovery -ModuleName "dbatools"
                                    $null = Set-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob -Disabled
                                } catch {
                                    $recoverResult = "Failed"
                                    $comment = "Something went wrong disabling the copy job."
                                    Stop-Function -Message "Something went wrong disabling the copy job.`n$($_)" -ErrorRecord $_ -Target $server.name -FunctionName Invoke-DbaDbLogShipRecovery
                                }
                            }
                        }

                        if ($recoverResult -ne 'Failed') {
                            # Start the restore job
                            Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Starting restore job"

                            if ($PSCmdlet.ShouldProcess($server.name, ("Starting restore job " + $ls.restorejob))) {
                                Write-Message -Message "Starting restore job $($ls.restorejob)" -Level Verbose -FunctionName Invoke-DbaDbLogShipRecovery -ModuleName "dbatools"
                                try {
                                    $null = Start-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob
                                } catch {
                                    $comment = "Something went wrong starting the restore job."
                                    Stop-Function -Message "Something went wrong starting the restore job.`n$($_)" -ErrorRecord $_ -Target $server.name -FunctionName Invoke-DbaDbLogShipRecovery
                                }

                                Write-Message -Message "Waiting for the restore action to complete.." -Level Verbose -FunctionName Invoke-DbaDbLogShipRecovery -ModuleName "dbatools"

                                # Get the job status
                                $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob

                                while ($jobStatus.CurrentRunStatus -ne 'Idle') {
                                    # Sleep for while to let the files be copied
                                    Start-Sleep -Seconds $Delay

                                    # Get the job status
                                    $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob
                                }

                                # Check the lat outcome of the job
                                if ($jobStatus.LastRunOutcome -eq 'Failed') {
                                    $recoverResult = "Failed"
                                    $comment = "The restore job for database $db failed. Please check the error log."
                                    Stop-Function -Message "The restore job for database $db failed. Please check the error log." -FunctionName Invoke-DbaDbLogShipRecovery
                                }

                                $jobOutputs += $jobStatus
                            }
                        }

                        if ($recoverResult -ne 'Failed') {
                            # Disable the log shipping restore job on the secondary instance
                            if ($PSCmdlet.ShouldProcess($server.name, "Disabling restore job $($ls.restorejob)")) {
                                try {
                                    Write-Message -Message ("Disabling restore job " + $ls.restorejob) -Level Verbose -FunctionName Invoke-DbaDbLogShipRecovery -ModuleName "dbatools"
                                    $null = Set-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob -Disabled
                                } catch {
                                    $recoverResult = "Failed"
                                    $comment = "Something went wrong disabling the restore job."
                                    Stop-Function -Message "Something went wrong disabling the restore job.`n$($_)" -ErrorRecord $_ -Target $server.name -FunctionName Invoke-DbaDbLogShipRecovery
                                }
                            }
                        }

                        if ($recoverResult -ne 'Failed') {
                            # Check if the database needs to recovered to its normal state
                            if ($NoRecovery -eq $false) {
                                if ($PSCmdlet.ShouldProcess($secondarydb, "Restoring database with recovery")) {
                                    Write-Message -Message "Restoring the database to it's normal state" -Level Verbose -FunctionName Invoke-DbaDbLogShipRecovery -ModuleName "dbatools"
                                    try {
                                        $query = "RESTORE DATABASE [$secondarydb] WITH RECOVERY"
                                        $server.Query($query)

                                    } catch {
                                        $recoverResult = "Failed"
                                        $comment = "Something went wrong restoring the database to a normal state."
                                        Stop-Function -Message "Something went wrong restoring the database to a normal state.`n$($_)" -ErrorRecord $_ -Target $secondarydb -FunctionName Invoke-DbaDbLogShipRecovery
                                    }
                                }
                            } else {
                                $comment = "Skipping restore with recovery."
                                Write-Message -Message "Skipping restore with recovery" -Level Verbose -FunctionName Invoke-DbaDbLogShipRecovery -ModuleName "dbatools"
                            }

                            Write-Message -Message ("Finished Recovery for $secondarydb") -Level Verbose -FunctionName Invoke-DbaDbLogShipRecovery -ModuleName "dbatools"
                        }

                        # Reset the log ship details
                        $logshipping_details = $null

                        [PSCustomObject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.InstanceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $secondarydb
                            RecoverResult = $recoverResult
                            Comment       = $comment
                        }

                    }
                }
            }
            Write-Progress -Activity $activity -Completed
            $stepCounter = 0
        }
    }

    @{ __w4039State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $Database $SqlCredential $NoRecovery $Force $InputObject $Delay $EnableException $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
