#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets SQL Server startup parameters via remote WMI. Port of
/// public/Set-DbaStartupParameter.ps1 (W3-097). STRUCTURALLY IMMUNE to the
/// cross-record class: NO parameter is ValueFromPipeline, so exactly one process record
/// ever exists (B's exposure filter) - the whole process body rides ONE verbatim hop,
/// no sentinel, and the inner-$PSCmdlet gate (required by the Copy-family
/// `if ($Force) { $ConfirmPreference = 'none' }` convention riding at hop top) needs NO
/// prompt-state transplant (single hop = single runtime; the template hold is not
/// touched). VFP-LOCAL CLASSIFICATION TABLE (promoted question answered): $Offline is
/// param-MUTATED inside the instance loop (connect-failure fallback) and read by later
/// iterations - source keeps it in the fn scope, the port keeps it in the hop scope,
/// identical reach because both span the single record's whole loop (this is also why
/// the loop stays WHOLE-ARRAY, not per-element); $server/$currentStartup/$newStartup/
/// $parameterString/$originalParamString/$instanceName/$displayName are per-iteration;
/// $SingleUserDetails/$TraceFlag are param-mutations with hop-scope reach == fn-scope
/// reach (single record). $PSBoundParameters is read as a DICTIONARY (key tests at the
/// StartupConfig/TraceFlag sites AND the key-matched VALUE-copy loop into $newStartup) -
/// carried as new Hashtable(MyInvocation.BoundParameters) and substituted
/// $__boundParams (Keys/.Item() semantics identical; switch values arrive as the same
/// SwitchParameter instances the function binder stores). BEGIN block: the
/// Force/ConfirmPreference line rides at process-hop top; Test-ElevationRequirement
/// (the Get-PSCallStack attribution class, FOURTH instance) runs in a BEGIN hop through
/// the named-wrapper shim, and its non-EE Stop-Function LATCH rides back as
/// interrupted, feeding the process hop's carried $__hopInterrupted ahead of the
/// verbatim Test-FunctionInterrupt gate. QUIRKS verbatim: the $wmi variable inside the
/// remote scriptblock is provided by Invoke-ManagedComputerCommand's remote context;
/// the mid-loop `$Offline = $true` connect fallback; `$newStartup.TraceFlags = if (...)
/// { }` assigning null through an empty then-block; the Credential-vs-not output split
/// (Notes only on the credential-less path); Get-DbaStartupParameter re-read inside the
/// gate. [PsIntCast] on MemoryToReserve (W1-043). All MUTATING paths are env-blocked on
/// the lane topology (WMI guest->partition, the W3-084/W3-092 class); the smoke
/// exercises the deep parameterString/branch/gate paths via module-scope SHADOWS of the
/// WMI-dependent helpers (the W3-084 emission-probe technique) - identical instruments
/// in both worlds. NO WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Set-DbaStartupParameter.json (implicit positions 0-9, SqlInstance
/// Mandatory pos0 NOT VFP, ConfirmImpact High).
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaStartupParameter", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed partial class SetDbaStartupParameterCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>SQL login credential for the instance connection.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Windows credential for the remote WMI work.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>Path to the master database data file (-d).</summary>
    [Parameter(Position = 3)]
    public string? MasterData { get; set; }

    /// <summary>Path to the master database log file (-l).</summary>
    [Parameter(Position = 4)]
    public string? MasterLog { get; set; }

    /// <summary>Path to the error log (-e).</summary>
    [Parameter(Position = 5)]
    public string? ErrorLog { get; set; }

    /// <summary>Trace flag(s) to enable (-T).</summary>
    [Parameter(Position = 6)]
    public string[]? TraceFlag { get; set; }

    /// <summary>Starts with the command-prompt flag (-c).</summary>
    [Parameter]
    public SwitchParameter CommandPromptStart { get; set; }

    /// <summary>Starts with minimal configuration (-f).</summary>
    [Parameter]
    public SwitchParameter MinimalStart { get; set; }

    /// <summary>Memory in MB reserved outside the buffer pool (-g).</summary>
    [Parameter(Position = 7)]
    [PsIntCast]
    public int MemoryToReserve { get; set; }

    /// <summary>Starts in single-user mode (-m).</summary>
    [Parameter]
    public SwitchParameter SingleUser { get; set; }

    /// <summary>Login allowed to connect in single-user mode.</summary>
    [Parameter(Position = 8)]
    public string? SingleUserDetails { get; set; }

    /// <summary>Disables Windows application event logging (-n).</summary>
    [Parameter]
    public SwitchParameter NoLoggingToWinEvents { get; set; }

    /// <summary>Starts as a named instance (-s).</summary>
    [Parameter]
    public SwitchParameter StartAsNamedInstance { get; set; }

    /// <summary>Disables performance monitoring (-x).</summary>
    [Parameter]
    public SwitchParameter DisableMonitoring { get; set; }

    /// <summary>Enables increased extents (-E).</summary>
    [Parameter]
    public SwitchParameter IncreasedExtents { get; set; }

    /// <summary>Replaces existing trace flags instead of appending.</summary>
    [Parameter]
    public SwitchParameter TraceFlagOverride { get; set; }

    /// <summary>A Get-DbaStartupParameter object to apply wholesale.</summary>
    [Parameter(Position = 9)]
    public object? StartupConfig { get; set; }

    /// <summary>Works via WMI only, without a SQL connection.</summary>
    [Parameter]
    public SwitchParameter Offline { get; set; }

    /// <summary>Skips path validation and confirmation prompts.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The begin-block Test-ElevationRequirement latch (Test-FunctionInterrupt cannot
    // cross hop scopes - the W3-081 pattern).
    private bool _hopInterrupted;

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            SqlInstance, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3097State"))
            {
                Hashtable? latch = sentinel["__w3097State"] as Hashtable;
                if (latch is not null && latch["interrupted"] is bool interrupted && interrupted)
                    _hopInterrupted = true;
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, SqlCredential, Credential, MasterData, MasterLog, ErrorLog,
            TraceFlag, CommandPromptStart.ToBool(), MinimalStart.ToBool(),
            MemoryToReserve, SingleUser.ToBool(), SingleUserDetails,
            NoLoggingToWinEvents.ToBool(), StartAsNamedInstance.ToBool(),
            DisableMonitoring.ToBool(), IncreasedExtents.ToBool(),
            TraceFlagOverride.ToBool(), StartupConfig, Offline.ToBool(), Force.ToBool(),
            EnableException.ToBool(), new Hashtable(MyInvocation.BoundParameters),
            _hopInterrupted,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // PS: the begin block's elevation check VERBATIM (the Force/ConfirmPreference line
    // rides at process-hop top instead, where the gate lives). Substitutions: the
    // ATTRIBUTION SHIM around Test-ElevationRequirement (W3-084/W3-092 class - it stamps
    // Stop-Function with the caller frame), invoked DOT-SOURCED so the helper's
    // dot-sourced Stop-Function latch (-Scope 1 = the helper's caller) lands in THIS
    // scriptblock scope where Test-FunctionInterrupt reads it - a plain wrapper call
    // parks the latch in the wrapper frame and loses it (r2 smoke-caught).
    // $EnableException is carried because the helper's [bool]$EnableException =
    // $EnableException default scope-walks the caller chain (r1 smoke-caught: an
    // uncarried scope resolved a stray "" and the transformation threw). The latch
    // returns through the sentinel.
    private const string BeginScript = """
param($SqlInstance, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    function Set-DbaStartupParameter {
        param($__splat)
        Test-ElevationRequirement @__splat
    }

    $null = . Set-DbaStartupParameter -__splat @{ ComputerName = $SqlInstance[0] }

    @{ __w3097State = @{ interrupted = (Test-FunctionInterrupt) } }
} $SqlInstance $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = ProcessScriptHead + "\n" + ProcessScriptTail;
}
