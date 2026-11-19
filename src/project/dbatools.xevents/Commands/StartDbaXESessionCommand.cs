#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using XeSession = Microsoft.SqlServer.Management.XEvent.Session;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Starts stopped Extended Events sessions on one or more SQL Server instances (by name, all non-system, or
/// by piped session object), optionally scheduling start/stop via Agent jobs.
/// </summary>
/// <remarks>
/// The session resolution, the -Session/-AllSessions filtering, the Start, the -StartAt/-StopAt Agent-job
/// scheduling, and the re-query all run the original dbatools PowerShell body VERBATIM inside the dbatools
/// module scope rather than being reimplemented in C#, so the engine decides the observable details.
///
/// The source begin block defines TWO nested helpers (Start-XESessions and New-Job), so it is ported
/// PROCESS-ONLY with both definitions PREPENDED into the process hop (redefined per record - harmless).
///
/// SHOULDPROCESS (3 sites, handled two ways, same as Stop-DbaXESession):
///  - The ONE process-block ShouldProcess uses the OUTER $Pscmdlet, routed to $__realCmdlet (this,
///    ConfirmImpact Medium) so "Yes to All" persists across pipeline records (a fresh scriptblock $PSCmdlet
///    per record would reset it).
///  - The ShouldProcess inside Start-XESessions and inside New-Job each use their OWN nested $Pscmdlet
///    (their own [CmdletBinding(SupportsShouldProcess)], Medium) - kept VERBATIM.
/// The process hop scriptblock is [CmdletBinding(SupportsShouldProcess)] so the nested functions inherit the
/// forwarded WhatIf/Confirm. The nested Write-Message/Stop-Function carry no -FunctionName, so they infer
/// "Start-XESessions"/"New-Job" from the call stack in both source and hop (kept verbatim).
///
/// The "-Force" tokens are arguments to the New-DbaAgentSchedule/Job/JobStep calls inside New-Job, NOT a
/// -Force parameter of this command (there is none). Nothing reads Test-FunctionInterrupt (the one
/// Stop-Function is -Continue) -> no interrupt/Interrupted guard. $InputObject is only READ -> no
/// cross-record carry. Three parameter sets: Session (default), All, Object; StartAt/StopAt are
/// __AllParameterSets. StartAt/StopAt bind with the invariant culture (matching the script binder) and
/// are passed into the hop as $null when unbound: the source gates its Agent-job scheduling branches on
/// the parameters' truthiness, and an unbound [datetime] is $null (falsy) in the script world, where
/// the compiled property's default would be a truthy date. Each re-queried/started session is emitted
/// before a later Start may fail under -EnableException (DEF-001), so the process hop uses
/// InvokeScopedStreaming. Surface pinned by migration/baselines/Start-DbaXESession.json.
/// </remarks>
[Cmdlet(VerbsLifecycle.Start, "DbaXESession", DefaultParameterSetName = "Session", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class StartDbaXESessionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 1, ParameterSetName = "Session")]
    [Parameter(Mandatory = true, Position = 1, ParameterSetName = "All")]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(ParameterSetName = "Session")]
    [Parameter(ParameterSetName = "All")]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) of the Extended Events session(s) to start.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Session")]
    [Alias("Sessions")]
    public object[]? Session { get; set; }

    /// <summary>Schedule the session to start at this time (via an Agent job).</summary>
    [Parameter]
    [PsDateTimeCast]
    public DateTime StartAt { get; set; }

    /// <summary>Schedule the session to stop at this time (via an Agent job).</summary>
    [Parameter]
    [PsDateTimeCast]
    public DateTime StopAt { get; set; }

    /// <summary>Start all non-system Extended Events sessions.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "All")]
    public SwitchParameter AllSessions { get; set; }

    /// <summary>Extended Events Session objects piped in (e.g. from Get-DbaXESession).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "Object")]
    public XeSession[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (no set named), which
    // reflects as __AllParameterSets and matches the inherited [Parameter]; no per-set override needed.

    protected override void ProcessRecord()
    {
        // An unbound [datetime] is $null in the script world and falsy; the C# property default
        // (DateTime.MinValue) is truthy to PowerShell and would wrongly take the "if ($StartAt)"
        // Agent-job scheduling branches. Pass null when unbound so the hop's truthiness gates match.
        object? startAt = TestBound(nameof(StartAt)) ? StartAt : null;
        object? stopAt = TestBound(nameof(StopAt)) ? StopAt : null;

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
        }, ProcessScript,
            InputObject, SqlInstance, SqlCredential, Session, startAt, stopAt, AllSessions.ToBool(),
            EnableException.ToBool(), this, NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the nested Start-XESessions + New-Job functions prepended VERBATIM (their ShouldProcess uses each
    // nested $Pscmdlet; Write-Message/Stop-Function keep verbatim call-stack attribution), then the process
    // block VERBATIM apart from the one outer $Pscmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess.
    private const string ProcessScript = """
param($InputObject, $SqlInstance, $SqlCredential, $Session, $StartAt, $StopAt, $AllSessions, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Session, $StartAt, $StopAt, $AllSessions, $EnableException, $__realCmdlet)
    function Start-XESessions {
        [CmdletBinding(SupportsShouldProcess)]
        param ([Microsoft.SqlServer.Management.XEvent.Session[]]$xeSessions)

        foreach ($xe in $xeSessions) {
            $instance = $xe.Parent.Name
            $session = $xe.Name

            if (-Not $xe.isRunning) {
                Write-Message -Level Verbose -Message "Starting XEvent Session $session on $instance."
                if ($Pscmdlet.ShouldProcess("$instance", "Starting XEvent Session $session")) {
                    try {
                        $xe.Start()
                    } catch {
                        Stop-Function -Message "Could not start XEvent Session on $instance." -Target $session -ErrorRecord $_ -Continue
                    }
                }
            } else {
                Write-Message -Level Warning -Message "$session on $instance is already running."
            }
            Get-DbaXESession -SqlInstance $xe.Parent -Session $session
        }
    }

    function New-Job {
        [CmdletBinding(SupportsShouldProcess)]
        param (
            [Microsoft.SqlServer.Management.XEvent.Session[]]$xeSessions,
            [string]$Action,
            [datetime]$At
        )

        foreach ($xe in $xeSessions) {
            $server = $xe.Parent
            $session = $xe.Name
            $name = "XE Session $Action - $session"
            Write-Message -Level Verbose -Message "Making New XEvent Job for $Action of $session on $server"
            if ($Pscmdlet.ShouldProcess("$server", "Making New XEvent Job for $Action of $session")) {
                # Setup the schedule time

                # Create the schedule
                $StartDateDatePart = Get-Date -Date $At -format 'yyyyMMdd'
                $StartDateTimePart = Get-Date -Date $At -format 'HHmmss'
                $schedule = New-DbaAgentSchedule -SqlInstance $server -Schedule $name -FrequencyType Once -StartDate $StartDateDatePart -StartTime $StartDateTimePart -Force

                # Create the job and attach the schedule
                $job = New-DbaAgentJob -SqlInstance $server -Job $name -Schedule $schedule -DeleteLevel Always -Force

                # Create the job step
                $sql = "ALTER EVENT SESSION [$session] ON SERVER STATE = $Action;"
                #Variable $jobstep marked as unused by PSScriptAnalyzer replace with $null to catch output
                $null = New-DbaAgentJobStep -SqlInstance $server -Job $job -StepName 'T-SQL Stop' -Subsystem TransactSql -Command $sql -Force
            }
        }
    }

    if ($InputObject) {
        Start-XESessions $InputObject
    } else {
        foreach ($instance in $SqlInstance) {
            $xeSessions = Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential

            # Filter xeSessions based on parameters
            if ($Session) {
                $xeSessions = $xeSessions | Where-Object { $_.Name -in $Session }
            } elseif ($AllSessions) {
                $systemSessions = @('AlwaysOn_health', 'system_health', 'telemetry_xevents')
                $xeSessions = $xeSessions | Where-Object { $_.Name -notin $systemSessions }
            }

            if ($__realCmdlet.ShouldProcess("$instance", "Configuring XEvent Session $session to start")) {
                if ($StartAt) {
                    New-Job -xeSessions $xeSessions -Action START -At $StartAt
                    $xeSessions
                } else {
                    Start-XESessions $xeSessions
                }

                if ($StopAt) {
                    New-Job -xeSessions $xeSessions -Action STOP -At $StopAt
                }
            }
        }
    }
} $InputObject $SqlInstance $SqlCredential $Session $StartAt $StopAt $AllSessions $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
