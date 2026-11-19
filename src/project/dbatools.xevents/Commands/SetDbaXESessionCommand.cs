#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using XeSession = Microsoft.SqlServer.Management.XEvent.Session;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters existing Extended Events sessions on one or more SQL Server instances - session options and the
/// set of collected events - and re-emits each session decorated like Get-DbaXESession.
/// </summary>
/// <remarks>
/// The session resolution, the option/event assignments, the Alter, and the output all run a module-scoped
/// PowerShell body inside the dbatools module scope rather than being reimplemented in C#, so the body can
/// call Get-DbaXESession, Stop-Function and Write-Message directly and the engine decides the observable
/// details. This is a brand-new command with no PowerShell ancestor; the surface is pinned by
/// migration/designed/Set-DbaXESession.json (owner-signed), diffed EXACT-match in the gate.
///
/// SAFETY: the sole Alter runs only inside a passed $__realCmdlet.ShouldProcess gate, so a -WhatIf run never
/// calls Session.Alter() and therefore never triggers ProviderImpl.ValidateAlter's transient "dummy_session"
/// CREATE against the server - a -WhatIf leaves no server-side trace. All in-memory changes are staged and a
/// single Alter() lets SMO emit its own fixed statement order (event drops, target drops/adds, options, event
/// adds); removes are applied before adds to mirror that order. Only explicitly-bound options are assigned so
/// an unbound parameter leaves the property untouched (Session.Alter no-ops silently when nothing is dirty).
/// MaxDispatchLatency is assigned through the seconds-valued CLR property, matching the parameter.
///
/// Either -SqlInstance or a piped session (the §1.2 Test-Bound duality, no parameter sets) - a requested
/// session name absent on the instance warns and continues (terminating under -EnableException). This cmdlet
/// supplies the real ShouldProcess runtime (ConfirmImpact Medium, no -Force). No cross-record state is carried,
/// so each record runs an independent hop.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaXESession", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(XeSession))]
public sealed class SetDbaXESessionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) of the Extended Events session(s) to alter (server-side filter when feeding from -SqlInstance).</summary>
    [Parameter(Position = 2)]
    [Alias("Sessions")]
    public object[]? Session { get; set; }

    /// <summary>Extended Events Session objects piped in (e.g. from Get-DbaXESession).</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public XeSession[]? InputObject { get; set; }

    /// <summary>Fully qualified event names to add to the session (e.g. sqlserver.sql_statement_completed).</summary>
    [Parameter]
    public string[]? AddEvent { get; set; }

    /// <summary>Fully qualified event names to remove from the session.</summary>
    [Parameter]
    public string[]? RemoveEvent { get; set; }

    /// <summary>Configures the session to start automatically when the instance starts.</summary>
    [Parameter]
    public SwitchParameter AutoStart { get; set; }

    /// <summary>The maximum memory (KB) the session allocates for event buffering.</summary>
    [Parameter]
    public int MaxMemory { get; set; }

    /// <summary>The maximum time (seconds) events are buffered before dispatch.</summary>
    [Parameter]
    public int MaxDispatchLatency { get; set; }

    /// <summary>The maximum size (MB) of a single event.</summary>
    [Parameter]
    public int MaxEventSize { get; set; }

    /// <summary>How the session behaves when event buffers are full.</summary>
    [Parameter]
    public XeSession.EventRetentionModeEnum EventRetentionMode { get; set; }

    /// <summary>How event buffer memory is partitioned across the server.</summary>
    [Parameter]
    public XeSession.MemoryPartitionModeEnum MemoryPartitionMode { get; set; }

    /// <summary>Tracks a causal relationship between events on the same task.</summary>
    [Parameter]
    public SwitchParameter TrackCausality { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the designed spec declares it in __AllParameterSets,
    // so the inherited [Parameter] already matches; no per-set override needed.

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
                return;
            }
            WriteObject(item);
        }, BodyScript,
            SqlInstance, SqlCredential, Session, InputObject, AddEvent, RemoveEvent,
            AutoStart.ToBool(), MaxMemory, MaxDispatchLatency, MaxEventSize, EventRetentionMode,
            MemoryPartitionMode, TrackCausality.ToBool(), EnableException.ToBool(), this,
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), TestBound(nameof(AutoStart)),
            TestBound(nameof(MaxMemory)), TestBound(nameof(MaxDispatchLatency)), TestBound(nameof(MaxEventSize)),
            TestBound(nameof(EventRetentionMode)), TestBound(nameof(MemoryPartitionMode)),
            TestBound(nameof(TrackCausality)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the module-scoped body. Sessions come from -SqlInstance (resolved live via Get-DbaXESession, a
    // requested-but-missing name warns and continues) or piped -InputObject. Only bound options are assigned,
    // removes precede adds, and a single Alter runs inside a passed ShouldProcess so -WhatIf never touches the
    // server. Each changed session is re-emitted via Get-DbaXESession so its decoration matches exactly.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Session, $InputObject, $AddEvent, $RemoveEvent, $AutoStart, $MaxMemory, $MaxDispatchLatency, $MaxEventSize, $EventRetentionMode, $MemoryPartitionMode, $TrackCausality, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundAutoStart, $__boundMaxMemory, $__boundMaxDispatchLatency, $__boundMaxEventSize, $__boundEventRetentionMode, $__boundMemoryPartitionMode, $__boundTrackCausality, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Session, [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject, [string[]]$AddEvent, [string[]]$RemoveEvent, $AutoStart, $MaxMemory, $MaxDispatchLatency, $MaxEventSize, $EventRetentionMode, $MemoryPartitionMode, $TrackCausality, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundAutoStart, $__boundMaxMemory, $__boundMaxDispatchLatency, $__boundMaxEventSize, $__boundEventRetentionMode, $__boundMemoryPartitionMode, $__boundTrackCausality)

    if (-not $__boundSqlInstance -and -not $__boundInputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Set-DbaXESession
        return
    }

    $sessionsToProcess = New-Object System.Collections.Generic.List[object]
    if ($__boundInputObject) {
        foreach ($piped in $InputObject) { $sessionsToProcess.Add($piped) }
    }

    if ($__boundSqlInstance) {
        foreach ($instance in $SqlInstance) {
            try {
                $allSessions = Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential -EnableException
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaXESession
                continue
            }

            if ($Session) {
                foreach ($request in $Session) {
                    $requestName = if ($request -is [Microsoft.SqlServer.Management.XEvent.Session]) { $request.Name } else { [string]$request }
                    $match = $allSessions | Where-Object { $_.Name -eq $requestName }
                    if (-not $match) {
                        Stop-Function -Message "Extended Events session $requestName does not exist on $instance" -Target $requestName -Category ObjectNotFound -Continue -FunctionName Set-DbaXESession
                        continue
                    }
                    foreach ($found in $match) { $sessionsToProcess.Add($found) }
                }
            } else {
                foreach ($found in $allSessions) { $sessionsToProcess.Add($found) }
            }
        }
    }

    foreach ($currentSession in $sessionsToProcess) {
        $server = $currentSession.Parent

        $wantChange = $__boundAutoStart -or $__boundMaxMemory -or $__boundMaxDispatchLatency -or $__boundMaxEventSize -or $__boundEventRetentionMode -or $__boundMemoryPartitionMode -or $__boundTrackCausality -or $AddEvent -or $RemoveEvent
        $changed = $false

        if ($wantChange -and $__realCmdlet.ShouldProcess($server, "Altering Extended Events session $($currentSession.Name)")) {
            try {
                if ($__boundMaxMemory) { $currentSession.MaxMemory = $MaxMemory }
                if ($__boundMaxDispatchLatency) { $currentSession.MaxDispatchLatency = $MaxDispatchLatency }
                if ($__boundMaxEventSize) { $currentSession.MaxEventSize = $MaxEventSize }
                if ($__boundEventRetentionMode) { $currentSession.EventRetentionMode = $EventRetentionMode }
                if ($__boundMemoryPartitionMode) { $currentSession.MemoryPartitionMode = $MemoryPartitionMode }
                if ($__boundAutoStart) { $currentSession.AutoStart = [bool]$AutoStart }
                if ($__boundTrackCausality) { $currentSession.TrackCausality = [bool]$TrackCausality }

                foreach ($eventName in $RemoveEvent) {
                    $existingEvent = $currentSession.Events[$eventName]
                    if ($existingEvent) { $currentSession.RemoveEvent($existingEvent) }
                }
                foreach ($eventName in $AddEvent) {
                    $currentSession.AddEvent($eventName)
                }

                $currentSession.Alter()
                $changed = $true
            } catch {
                Stop-Function -Message "Failed to alter Extended Events session $($currentSession.Name) on $server." -ErrorRecord $_ -Target $currentSession -Continue -FunctionName Set-DbaXESession
                continue
            }
        }

        if ($changed) {
            Get-DbaXESession -SqlInstance $server -Session $currentSession.Name
        }
    }
} $SqlInstance $SqlCredential $Session $InputObject $AddEvent $RemoveEvent $AutoStart $MaxMemory $MaxDispatchLatency $MaxEventSize $EventRetentionMode $MemoryPartitionMode $TrackCausality $EnableException $__realCmdlet $__boundSqlInstance $__boundInputObject $__boundAutoStart $__boundMaxMemory $__boundMaxDispatchLatency $__boundMaxEventSize $__boundEventRetentionMode $__boundMemoryPartitionMode $__boundTrackCausality @__commonParameters 3>&1 2>&1
""";
}
