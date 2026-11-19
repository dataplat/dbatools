#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Stops running SQL Server traces by ID or piped input from Get-DbaTrace.
/// </summary>
/// <remarks>
/// The trace resolution (Get-DbaTrace), the default-trace guard, the sp_trace_setstatus stop call, the
/// re-query, and the closed-trace fallback projection all run the original dbatools PowerShell body
/// VERBATIM inside the dbatools module scope rather than being reimplemented in C#, so the engine decides
/// the observable details.
///
/// Process-only. The single ShouldProcess uses the OUTER $Pscmdlet, routed to $__realCmdlet (this,
/// ConfirmImpact Medium) so "Yes to All" persists across pipeline records (a fresh scriptblock $PSCmdlet
/// per record would reset it). The process hop scriptblock is [CmdletBinding(SupportsShouldProcess)] so
/// forwarded -WhatIf/-Confirm bind.
///
/// The three Stop-Function calls are all -Continue and gain -FunctionName Stop-DbaTrace (in-hop the
/// call-stack frame is the generated scriptblock, so the attribution must be explicit). The bare `return`
/// statements following a Stop-Function -Continue are dead in both worlds (-Continue issues a loop
/// `continue`; -EnableException throws before the return) and are kept verbatim.
///
/// $InputObject is reassigned from Get-DbaTrace only when it is unbound AND -SqlInstance is supplied,
/// which happens exactly on the single non-piped process invocation; when piped, $InputObject is always
/// bound and the branch is skipped. So the reassignment never leaks across records and no cross-record
/// carry is needed. Each stopped trace is re-queried (or a closed-trace fallback object built) and
/// emitted before a later trace's Query may throw under -EnableException, so the process hop uses
/// InvokeScopedStreaming to avoid losing the record of a trace that was actually stopped (DEF-001).
/// Surface pinned by migration/baselines/Stop-DbaTrace.json.
/// </remarks>
[Cmdlet(VerbsLifecycle.Stop, "DbaTrace", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class StopDbaTraceCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The numeric IDs of specific traces to stop.</summary>
    [Parameter(Position = 2)]
    public int[]? Id { get; set; }

    /// <summary>Trace objects piped in from Get-DbaTrace.</summary>
    [Parameter(Position = 3, ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare, which the inherited
    // [Parameter] already matches; no override needed.

    protected override void ProcessRecord()
    {
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
            InputObject, SqlInstance, SqlCredential, Id, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from the one $Pscmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess
    // and -FunctionName Stop-DbaTrace on the three Stop-Function sites. EnableException is bound so
    // Stop-Function's scope-walking default inherits the caller's value.
    private const string ProcessScript = """
param($InputObject, $SqlInstance, $SqlCredential, $Id, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([object[]]$InputObject, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [int[]]$Id, $EnableException, $__realCmdlet)
    if (-not $InputObject -and $SqlInstance) {
        $InputObject = Get-DbaTrace -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Id $Id
    }

    foreach ($trace in $InputObject) {
        if (-not $trace.id -and -not $trace.Parent) {
            Stop-Function -Message "Input is of the wrong type. Use Get-DbaTrace." -Continue -FunctionName Stop-DbaTrace
            return
        }

        $server = $trace.Parent
        $traceid = $trace.id
        $default = Get-DbaTrace -SqlInstance $server -Default

        if ($default.id -eq $traceid) {
            Stop-Function -Message "The default trace on $server cannot be stopped. Use Set-DbaSpConfigure to turn it off." -Continue -FunctionName Stop-DbaTrace
        }

        $sql = "sp_trace_setstatus $traceid, 0"

        if ($__realCmdlet.ShouldProcess($traceid, "Stopping the TraceID on $server")) {
            try {
                $server.Query($sql)
                $output = Get-DbaTrace -SqlInstance $server -Id $traceid
                if (-not $output) {
                    $output = [PSCustomObject]@{
                        ComputerName      = $server.ComputerName
                        InstanceName      = $server.ServiceName
                        SqlInstance       = $server.DomainInstanceName
                        Id                = $traceid
                        Status            = $null
                        IsRunning         = $false
                        Path              = $null
                        MaxSize           = $null
                        StopTime          = $null
                        MaxFiles          = $null
                        IsRowset          = $null
                        IsRollover        = $null
                        IsShutdown        = $null
                        IsDefault         = $null
                        BufferCount       = $null
                        BufferSize        = $null
                        FilePosition      = $null
                        ReaderSpid        = $null
                        StartTime         = $null
                        LastEventTime     = $null
                        EventCount        = $null
                        DroppedEventCount = $null
                        Parent            = $server
                    } | Select-DefaultView -Property 'ComputerName', 'InstanceName', 'SqlInstance', 'Id', 'IsRunning'
                }
                $output
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue -FunctionName Stop-DbaTrace
                return
            }
        }
    }
} $InputObject $SqlInstance $SqlCredential $Id $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
