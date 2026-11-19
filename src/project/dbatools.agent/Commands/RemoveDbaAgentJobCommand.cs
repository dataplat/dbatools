#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoAgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes SQL Server Agent jobs.
/// </summary>
/// <remarks>
/// The instance connection, the job collection/filtering, the null-Job guard, the sp_delete_job removal,
/// the TEPP cache eviction, and the result-object shaping all run the original dbatools PowerShell body
/// inside the dbatools module scope rather than being reimplemented in C#, so the engine decides the
/// observable details.
///
/// InputObject is the only pipeline-bound parameter; the body gathers each SqlInstance/Job match into
/// $InputObject and then drops every job in $InputObject. The gathered collection does not carry across
/// records (a VFP param is rebound each record), and every other local is per-iteration, so a single
/// per-record hop reproduces the whole body with no cross-record sentinel. The stale $instance used in the
/// second loop's ShouldProcess target is a source quirk faithfully reproduced: it is either re-set by the
/// first loop (SqlInstance array) or consistently unset (pure pipeline) within the same record - SqlInstance
/// is not pipeline-bound, so there is no cross-record dimension to it.
///
/// Output streams: each removed job's result is emitted as its Drop runs, before a later job may fail, so
/// buffering would hide jobs that were actually dropped.
///
/// This cmdlet supplies the real ShouldProcess runtime to the hop (ConfirmImpact High, no -Force).
/// Surface pinned by migration/baselines/Remove-DbaAgentJob.json.
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaAgentJob", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaAgentJobCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name of the SQL Server Agent job(s) to remove.</summary>
    [Parameter(Position = 2)]
    public object[]? Job { get; set; }

    /// <summary>Preserve job execution history when removing the job.</summary>
    [Parameter]
    public SwitchParameter KeepHistory { get; set; }

    /// <summary>Preserve job schedules that are not used by other jobs when removing this job.</summary>
    [Parameter]
    public SwitchParameter KeepUnusedSchedule { get; set; }

    /// <summary>Agent job objects piped in from Get-DbaAgentJob.</summary>
    [Parameter(Position = 3, ValueFromPipeline = true)]
    public SmoAgentJob[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, BodyScript,
            SqlInstance, SqlCredential, Job, InputObject, EnableException.ToBool(),
            MyInvocation.BoundParameters.ContainsKey("Job"),
            MyInvocation.BoundParameters.ContainsKey("KeepHistory"),
            MyInvocation.BoundParameters.ContainsKey("KeepUnusedSchedule"),
            this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess, the
    // three Test-Bound sites -> carried $__boundJob / $__boundKeepHistory / $__boundKeepUnusedSchedule flags,
    // and -FunctionName Remove-DbaAgentJob on the direct Stop-Function/Write-Message sites. KeepHistory /
    // KeepUnusedSchedule are only read via Test-Bound (never by value), so only their bound flags are passed.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Job, $InputObject, $EnableException, $__boundJob, $__boundKeepHistory, $__boundKeepUnusedSchedule, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Job, [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject, $EnableException, $__boundJob, $__boundKeepHistory, $__boundKeepUnusedSchedule, $__realCmdlet)
    # Check if Job parameter is bound with null, empty, or whitespace-only values
    if ($__boundJob) {
        if ($null -eq $Job -or $Job.Count -eq 0 -or ($Job | Where-Object { [string]::IsNullOrWhiteSpace($_) })) {
            Write-Message -Level Verbose -Message "The -Job parameter was explicitly provided but contains null, empty, or whitespace-only values. This may indicate an uninitialized variable. Skipping operation." -FunctionName Remove-DbaAgentJob -ModuleName "dbatools"
            return
        }
    }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Remove-DbaAgentJob
        }

        foreach ($j in $Job) {
            if ($Server.JobServer.Jobs.Name -notcontains $j) {
                Stop-Function -Message "Job $j doesn't exist on $instance." -Continue -Target $instance -Category InvalidData -FunctionName Remove-DbaAgentJob
            }
            $InputObject += ($Server.JobServer.Jobs | Where-Object Name -eq $j)
        }
    }
    foreach ($currentJob in $InputObject) {
        $j = $currentJob.Name
        $server = $currentJob.Parent.Parent

        if ($__realCmdlet.ShouldProcess($instance, "Removing the job $j from $server")) {
            try {
                $dropHistory = $dropSchedule = 1

                if ($__boundKeepHistory) {
                    Write-Message -Level SomewhatVerbose -Message "Job history will be kept" -FunctionName Remove-DbaAgentJob -ModuleName "dbatools"
                    $dropHistory = 0
                }
                if ($__boundKeepUnusedSchedule) {
                    Write-Message -Level SomewhatVerbose -Message "Unused job schedules will be kept" -FunctionName Remove-DbaAgentJob -ModuleName "dbatools"
                    $dropSchedule = 0
                }
                Write-Message -Level SomewhatVerbose -Message "Removing job" -FunctionName Remove-DbaAgentJob -ModuleName "dbatools"
                $dropJobQuery = ("EXEC dbo.sp_delete_job @job_name = '{0}', @delete_history = {1}, @delete_unused_schedule = {2}" -f $currentJob.Name.Replace("'", "''"), $dropHistory, $dropSchedule)
                $server.Databases['msdb'].ExecuteNonQuery($dropJobQuery)
                $server.JobServer.Jobs.Refresh()
                Remove-TeppCacheItem -SqlInstance $server -Type job -Name $currentJob.Name
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Name         = $currentJob.Name
                    Status       = 'Dropped'
                }
            } catch {
                Write-Message -Level Verbose -Message "Could not drop job $job on $server" -FunctionName Remove-DbaAgentJob -ModuleName "dbatools"

                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Name         = $currentJob.Name
                    Status       = "Failed. $(Get-ErrorMessage -Record $_)"
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Job $InputObject $EnableException $__boundJob $__boundKeepHistory $__boundKeepUnusedSchedule $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
