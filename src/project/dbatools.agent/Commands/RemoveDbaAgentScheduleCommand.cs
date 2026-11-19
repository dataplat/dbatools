#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoScheduleBase = Microsoft.SqlServer.Management.Smo.Agent.ScheduleBase;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes SQL Server Agent schedules.
/// </summary>
/// <remarks>
/// The schedule lookup (Get-DbaAgentSchedule), the input-combination validation, the in-use guard, the
/// job-schedule detachment, the confirmation gate, the Drop, and the result-object shaping all run the
/// original dbatools PowerShell body inside the dbatools module scope rather than being reimplemented in
/// C#, so the engine decides the observable details.
///
/// The function collects every schedule across the whole pipeline in its begin/process blocks and only
/// drops them in end, to avoid "Collection was modified" when piped directly from Get-DbaAgentSchedule.
/// The accumulator ($schedules) is pipeline-spanning state a per-record hop scope cannot hold, so it
/// lives in C#: begin seeds an empty list, each process record contributes its schedules (a
/// Get-DbaAgentSchedule lookup when -SqlInstance is supplied, or the bound InputObject otherwise), and
/// the end hop receives the full list plus the raw inputs needed by its validation and -Force gate.
///
/// The SqlInstance branch REPLACES the list ("$schedules = Get-..."); the InputObject branch APPENDS
/// ("$schedules += $InputObject"). Because SqlInstance is not pipeline-bound while InputObject is, the two
/// can co-occur and the lookup then runs per record replacing each time, so the SqlInstance branch must
/// replace rather than append (else duplicate schedules would be dropped repeatedly).
///
/// The SqlInstance path reproduces the source's "$params = $PSBoundParameters; remove Force/WhatIf/Confirm;
/// Get-DbaAgentSchedule @params" by receiving this cmdlet's own MyInvocation.BoundParameters and splatting
/// it (minus Force/WhatIf/Confirm) so the lookup sees the bound Schedule/ScheduleUid/Id/SqlCredential.
///
/// The end hop streams: it emits a result object per schedule as each Drop runs, before a later Drop may
/// throw under -EnableException. This cmdlet supplies the real ShouldProcess runtime (ConfirmImpact High).
/// Surface pinned by migration/baselines/Remove-DbaAgentSchedule.json.
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaAgentSchedule", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaAgentScheduleCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only remove schedules with these names.</summary>
    [Parameter(Position = 2)]
    [ValidateNotNullOrEmpty]
    [Alias("Schedules", "Name")]
    public string[]? Schedule { get; set; }

    /// <summary>Only remove schedules with these uids.</summary>
    [Parameter(Position = 3)]
    [Alias("Uid")]
    public string[]? ScheduleUid { get; set; }

    /// <summary>Only remove schedules with these ids.</summary>
    [Parameter(Position = 4)]
    public int[]? Id { get; set; }

    /// <summary>Agent schedule objects piped in from Get-DbaAgentSchedule.</summary>
    [Parameter(Position = 5, ValueFromPipeline = true)]
    public SmoScheduleBase[]? InputObject { get; set; }

    /// <summary>Remove schedules even when they are used by one or more jobs.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    // The pipeline-spanning accumulator: the source's begin "$schedules = @()", filled across process
    // records, drained in end.
    private List<PSObject> _schedules = null!;

    protected override void BeginProcessing()
    {
        _schedules = new List<PSObject>();
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        Hashtable bound = new Hashtable(MyInvocation.BoundParameters);

        List<PSObject> recordItems = new List<PSObject>();
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, InputObject, bound,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            if (item is not null)
            {
                recordItems.Add(item);
            }
        }

        // Source: "$schedules = Get-..." (REPLACE) for the SqlInstance branch, "$schedules += $InputObject"
        // (APPEND) for the InputObject branch.
        if (SqlInstance != null && SqlInstance.Length > 0)
        {
            _schedules = recordItems;
        }
        else
        {
            _schedules.AddRange(recordItems);
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        // The end block's validation needs the raw InputObject and query inputs (truthiness), the -Force
        // gate needs Force, and Stop-Function needs EnableException.
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
        }, EndScript,
            _schedules.ToArray(), InputObject, SqlInstance, Schedule, ScheduleUid, Id,
            Force.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block. The source assigns/appends to $schedules; here it EMITS the schedules and the
    // C# accumulates them (with the replace/append distinction above). The SqlInstance branch splats the
    // caller's bound parameters (minus Force/WhatIf/Confirm) to Get-DbaAgentSchedule exactly as the source
    // re-splat did.
    private const string ProcessScript = """
param($SqlInstance, $InputObject, $__bound, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [Microsoft.SqlServer.Management.Smo.Agent.ScheduleBase[]]$InputObject, [hashtable]$__bound)

    if ($SqlInstance) {
        $params = $__bound
        $null = $params.Remove('Force')
        $null = $params.Remove('WhatIf')
        $null = $params.Remove('Confirm')
        Get-DbaAgentSchedule @params
    } else {
        $InputObject
    }
} $SqlInstance $InputObject $__bound @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess and
    // -FunctionName Remove-DbaAgentSchedule on the direct Stop-Function/Write-Message sites. $schedules is
    // the accumulated list; $InputObject/$SqlInstance/$Schedule/$ScheduleUid/$Id are the raw inputs the
    // input-combination validation tests; $Force drives the in-use guard; $EnableException lets
    // Stop-Function's scope-walking default throw under -EnableException.
    private const string EndScript = """
param($schedules, $InputObject, $SqlInstance, $Schedule, $ScheduleUid, $Id, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($schedules, $InputObject, $SqlInstance, $Schedule, $ScheduleUid, $Id, $Force, $EnableException, $__realCmdlet)

    if ($InputObject -and ($Sqlinstance -or $Schedule -or $ScheduleUid -or $Id)) {
        Stop-Function -Message "You cannot use -InputObject with -SqlInstance, -Schedule, -ScheduleUid or -Id" -FunctionName Remove-DbaAgentSchedule
        return
    }
    # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaAgentSchedule.
    foreach ($sched in $schedules) {
        if ($sched.JobCount -ge 1 -and -not $Force) {
            Stop-Function -Message "The schedule $($sched.Name) with id $($sched.Id) and uid $($sched.ScheduleUid) is used in one or more jobs. If removal is neccesary use -Force." -Target $sched.Parent.Parent -Continue -FunctionName Remove-DbaAgentSchedule
        }
        if ($__realCmdlet.ShouldProcess($sched.Parent.Parent.Name, "Removing the schedule $($sched.Name) with id $($sched.Id) and uid $($sched.ScheduleUid) on $($sched.Parent.Parent.Name)")) {
            $output = [PSCustomObject]@{
                ComputerName = $sched.Parent.Parent.ComputerName
                InstanceName = $sched.Parent.Parent.ServiceName
                SqlInstance  = $sched.Parent.Parent.DomainInstanceName
                Schedule     = $sched.Name
                ScheduleId   = $sched.Id
                ScheduleUid  = $sched.ScheduleUid
                Status       = $null
                IsRemoved    = $false
            }
            try {
                if ($sched.JobCount -ge 1) {
                    foreach ($jobId in $sched.EnumJobReferences()) {
                        $jobSchedule = $sched.Parent.GetJobByID($jobId).JobSchedules | Where-Object { $_.ScheduleUid -eq $sched.ScheduleUid }
                        Write-Message -Level Verbose -Message "Removing the schedule $($sched.Name) with id $($sched.Id) and uid $($sched.ScheduleUid) from job $($jobSchedule.Parent)" -FunctionName Remove-DbaAgentSchedule -ModuleName "dbatools"
                        $jobSchedule.Drop($true)   # $true = we keep the schedule and drop it later
                    }
                }
                Write-Message -Level Verbose -Message "Removing the schedule $($sched.Name) with id $($sched.Id) and uid $($sched.ScheduleUid) on $($sched.Parent.Parent.Name)" -FunctionName Remove-DbaAgentSchedule -ModuleName "dbatools"
                Remove-TeppCacheItem -SqlInstance $sched.Parent.Parent -Type schedule -Name $sched.Name
                $sched.Drop()
                $output.Status = "Dropped"
                $output.IsRemoved = $true
            } catch {
                Stop-Function -Message "Failed removing the schedule $($sched.Name) with id $($sched.Id) and uid $($sched.ScheduleUid) on $($sched.Parent.Parent.Name)" -ErrorRecord $_ -FunctionName Remove-DbaAgentSchedule
                $output.Status = (Get-ErrorMessage -Record $_)
                $output.IsRemoved = $false
            }
            $output
        }
    }
} $schedules $InputObject $SqlInstance $Schedule $ScheduleUid $Id $Force $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
