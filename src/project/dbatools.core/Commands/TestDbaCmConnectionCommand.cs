#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests management connectivity (CIM/WMI/PSRemoting) to a computer. Port of
/// public/Test-DbaCmConnection.ps1 (W3-107). Begin + per-record hops; the source's end
/// block is EMPTY (no EndProcessing override). CLASSIFICATION TABLE (ComputerName is
/// the VFP; promoted question answered): begin state = the $disable_cache config
/// snapshot (read ONCE, rides the __w3107State sentinel - a mid-pipeline config change
/// must not affect later records, matching the source's begin snapshot) and the four
/// Test-Connection* helper functions (function-scope in the source, so RE-DECLARED
/// inside the process hop per the W3-100 relocation; they contain no
/// Stop-Function/Write-Message - no helper-frame concern); everything else is
/// per-iteration ($con mutations land on the LIVE connection object and the
/// ConnectionHost cache, which are process-global in both worlds). NO
/// ShouldProcess/gates (plain CmdletBinding - no WhatIf/Confirm plumbing); no
/// Test-FunctionInterrupt in the source and both Stop-Function sites use -Continue
/// INSIDE the per-record foreach (no latch, no relay - the W3-102/W3-103 classes do
/// not apply). The :types labeled loop and break types ride verbatim inside the hop.
/// Checklist greps done: New-DbaCimSessionOptionWithTimeout is a scope-walk-free,
/// callstack-free PS function; Get-DbatoolsConfigValue is compiled; hop-frame
/// Stop-Function/Write-Message carry -FunctionName (W1-090). No bind-time casts
/// (typed, non-mandatory, unvalidated params). NO WarningAction carrier (codex W3-005
/// r3). Surface pinned by migration/baselines/Test-DbaCmConnection.json (no sets,
/// implicit positions: ComputerName DbaCmConnectionParameter[] pos0 VFP with the
/// $env:COMPUTERNAME default applied in BeginProcessing per DEF-007, Credential pos1, Type ManagementConnectionType[] pos2
/// with the four-type default).
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaCmConnection")]
public sealed partial class TestDbaCmConnectionCommand : DbaBaseCmdlet
{
    /// <summary>The computer(s) to test against; defaults to this computer.</summary>
    // DEF-007: NO property initializer here. A C# initializer runs at CONSTRUCTION, on every
    // invocation, before binding - and DbaCmConnectionParameter's ctor REGISTERS into the live
    // ConnectionHost cache (Parameter/DbaCmConnectionParameter.cs:69-70), so the default's
    // converter mutated shared state even when -ComputerName was explicitly bound, where the PS
    // bind-time default evaluates ZERO times when the parameter is EXPLICITLY bound. Applied
    // in BeginProcessing instead - see the measured case table on that gate.
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaCmConnectionParameter[]? ComputerName { get; set; }

    /// <summary>Credential for the remote tests.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Connection protocol(s) to test.</summary>
    [Parameter(Position = 2)]
    public ManagementConnectionType[] Type { get; set; } = new[]
    {
        ManagementConnectionType.CimRM,
        ManagementConnectionType.CimDCOM,
        ManagementConnectionType.Wmi,
        ManagementConnectionType.PowerShellRemoting
    };

    /// <summary>Overrides the known-bad-credentials skip.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin-snapshotted configuration value.
    private Hashtable? _state;

    // DEF-007: the $env:COMPUTERNAME default. MEASURED source semantics (ctor-logging probe on
    // the source shape [SideEffecting[]]$ComputerName = $env:COMPUTERNAME):
    //   -ComputerName sql01     -> sql01                                   (default NOT evaluated)
    //   "sql01" | cmd           -> LOCALBOX, sql01
    //   "sql01","sql02" | cmd   -> LOCALBOX, sql01, LOCALBOX, sql02
    //   <no args>               -> LOCALBOX
    //   @() | cmd               -> LOCALBOX                                (process never runs)
    // i.e. PS applies the typed default at invocation start AND RE-APPLIES it before every
    // subsequent pipeline record, so the number of default conversions is max(1, recordCount) -
    // and it is skipped entirely only when the parameter was bound on the COMMAND LINE.
    // That is why _boundOnCommandLine is snapshotted in BeginProcessing: by ProcessRecord,
    // BoundParameters also carries pipeline-bound values and can no longer tell the two apart.
    // RESIDUAL, deliberate and NOT fully benign: for records after the first, PS converts the
    // default BEFORE binding the record's own value; a compiled cmdlet binds before
    // ProcessRecord runs, so the port converts in the opposite order within such a record.
    // Scope of the difference, stated precisely rather than waved off (codex r3 corrected an
    // earlier "unobservable" claim here): the resulting KEY SET and the object each key maps to
    // are identical either way, because the ctor's effect is
    // ConnectionHost.Connections[name] = connection keyed BY NAME - for two different names
    // order cannot change the mapping, and for the same name one call registers while the other
    // finds the existing entry. What CAN differ is Dictionary INSERTION ORDER, which leaks
    // through ConnectionHost.Connections.Keys/.Values and hence through Get-DbaCmConnection's
    // output ordering - reachable only if something removes the local-box key mid-pipeline
    // between records. Closing it would require converting the default ahead of the binder,
    // which a compiled cmdlet cannot do. Flagged for the re-gate; not asserted as a non-issue.
    private DbaCmConnectionParameter[]? _defaultComputerName;
    private bool _boundOnCommandLine;
    private bool _seenFirstRecord;

    private static DbaCmConnectionParameter[]? ConvertComputerNameDefault() =>
        (DbaCmConnectionParameter[])LanguagePrimitives.ConvertTo(
            Environment.GetEnvironmentVariable("COMPUTERNAME"),
            typeof(DbaCmConnectionParameter[]), System.Globalization.CultureInfo.InvariantCulture);

    protected override void BeginProcessing()
    {
        // DEF-007: snapshot command-line boundness and apply the default once for the
        // invocation (this is also the ONLY conversion an empty pipeline gets, matching the
        // source, whose process block never runs but whose default has already been applied).
        // Reset per invocation, not just assigned: a reused cmdlet instance would otherwise
        // carry _seenFirstRecord=true into the next invocation and convert the default twice
        // for its first record (codex r3).
        _seenFirstRecord = false;
        _defaultComputerName = null;
        _boundOnCommandLine = MyInvocation.BoundParameters.ContainsKey(nameof(ComputerName));
        if (!_boundOnCommandLine)
        {
            _defaultComputerName = ConvertComputerNameDefault();
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3107State"))
            {
                _state = sentinel["__w3107State"] as Hashtable;
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

        // DEF-007: PS re-applies the typed default before every record after the first.
        if (!_boundOnCommandLine && _seenFirstRecord)
        {
            _defaultComputerName = ConvertComputerNameDefault();
        }
        _seenFirstRecord = true;

        // Pipeline binding wins for this record; otherwise the freshly-applied default.
        DbaCmConnectionParameter[]? computers =
            MyInvocation.BoundParameters.ContainsKey(nameof(ComputerName))
                ? ComputerName
                : _defaultComputerName;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            computers, Credential, Type, Force.ToBool(), EnableException.ToBool(),
            _state,
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

}
