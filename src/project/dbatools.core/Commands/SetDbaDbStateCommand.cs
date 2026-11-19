#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets database states (RW / status / access, or detach). Port of
/// public/Set-DbaDbState.ps1 (W3-090). Begin/process lifecycle: the BEGIN hop runs the
/// verbatim Get-WrongCombo exclusive-switch validations (three ladders over a carried
/// clone of the REAL $PSBoundParameters - begin runs before pipeline binding, so the
/// clone matches the source's begin-time view) and returns the Stop-Function latch;
/// per-record PROCESS hops run the whole verbatim process body (the
/// `if (Test-FunctionInterrupt) { return }` gate rides verbatim, preceded by the
/// carried $__hopInterrupted so a record-1 validation latch skips later records exactly
/// like the source fn scope). The Copy-family `if ($Force) { $ConfirmPreference =
/// 'none' }` line rides at process-hop top with the INNER $Pscmdlet serving all EIGHT
/// state gates plus the Detached gates (W3-005/W3-064 convention). VFP-LOCAL
/// CLASSIFICATION TABLE (mandatory template rule): $dbs/$warn/$db_status/$dbStatuses/
/// $server/$partial/$snaps/$agname/$newstate are all assigned unconditionally at the
/// top of their record/iteration = SAFE; $InputObject is read-only here (no += ) = no
/// accumulation axis; NO leaked locals cross records. Engine state: ShouldProcess
/// Yes/No-to-All rides the sentinel via the lastShouldProcessContinueStatus transplant
/// (W3-082 mechanism - inner-$Pscmdlet + dual VFP row); the begin/process Stop-Function
/// latch rides as interrupted. QUIRKS preserved verbatim: the per-db `$dbStatuses =
/// @{ }` reset defeats the caching structure (Get-DbaDbState re-queried per db); the
/// LOWERCASE `if ($database)` filter; the system-db skip warning; Get-DbState mutates
/// $base.Status in place; the Detached branch's $warn += "Failed to detach" after a
/// -Continue Stop-Function is unreachable dead code (Stop-Function -Continue continues
/// the caller loop) and rides as-is. Helper functions (Edit-DatabaseState, Get-DbState,
/// $statusHash) are begin-scope in the source and re-declared at process-hop top
/// (function definitions cannot cross hop scopes - W3-083 class). NO WarningAction
/// carrier (codex W3-005 r3). Surface pinned by migration/baselines/Set-DbaDbState.json
/// (no positions, three sets incl. the PHANTOM memberless Default, SqlInstance Mandatory
/// VFPBPN Server-set, InputObject PSObject[] Mandatory VFP Database-set, ConfirmImpact
/// Medium).
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbState", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium, DefaultParameterSetName = "Default")]
public sealed partial class SetDbaDbStateCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, ParameterSetName = "Server")]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter]
    public object[]? Database { get; set; }

    /// <summary>Database(s) to exclude.</summary>
    [Parameter]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Required safety switch to target all databases on the instance.</summary>
    [Parameter]
    public SwitchParameter AllDatabases { get; set; }

    /// <summary>Sets the database READ_ONLY.</summary>
    [Parameter]
    public SwitchParameter ReadOnly { get; set; }

    /// <summary>Sets the database READ_WRITE.</summary>
    [Parameter]
    public SwitchParameter ReadWrite { get; set; }

    /// <summary>Brings the database ONLINE.</summary>
    [Parameter]
    public SwitchParameter Online { get; set; }

    /// <summary>Takes the database OFFLINE.</summary>
    [Parameter]
    public SwitchParameter Offline { get; set; }

    /// <summary>Sets the database to EMERGENCY.</summary>
    [Parameter]
    public SwitchParameter Emergency { get; set; }

    /// <summary>Detaches the database (breaks mirroring/AG with -Force).</summary>
    [Parameter]
    public SwitchParameter Detached { get; set; }

    /// <summary>Restricts access to SINGLE_USER.</summary>
    [Parameter]
    public SwitchParameter SingleUser { get; set; }

    /// <summary>Restricts access to RESTRICTED_USER.</summary>
    [Parameter]
    public SwitchParameter RestrictedUser { get; set; }

    /// <summary>Opens access to MULTI_USER.</summary>
    [Parameter]
    public SwitchParameter MultiUser { get; set; }

    /// <summary>Rolls back open transactions / kills sessions to force the change.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>Objects from Get-DbaDbState or Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Mandatory = true, ParameterSetName = "Database")]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Cross-record engine state only (see the classification table in the class doc):
    // the begin/process Stop-Function latch + the ShouldProcess prompt status.
    private Hashtable? _state;
    private bool _hopInterrupted;

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Set-DbaDbState");

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            new Hashtable(MyInvocation.BoundParameters), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3090State"))
            {
                _state = sentinel["__w3090State"] as Hashtable;
                if (_state is not null && _state["interrupted"] is bool interrupted && interrupted)
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, AllDatabases.ToBool(),
            ReadOnly.ToBool(), ReadWrite.ToBool(), Online.ToBool(), Offline.ToBool(),
            Emergency.ToBool(), Detached.ToBool(), SingleUser.ToBool(),
            RestrictedUser.ToBool(), MultiUser.ToBool(), Force.ToBool(), InputObject,
            EnableException.ToBool(), _state, _hopInterrupted,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3090State"))
            {
                Hashtable? latch = sentinel["__w3090State"] as Hashtable;
                if (latch is not null)
                {
                    if (latch["interrupted"] is bool interrupted && interrupted)
                        _hopInterrupted = true;
                    if (_state is null)
                        _state = latch;
                    else
                        _state["shouldProcessContinueStatus"] = latch["shouldProcessContinueStatus"];
                }
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

    // PS: the begin-block Get-WrongCombo helper + the three exclusive-switch validation
    // ladders VERBATIM. Substitutions only: $allParams reads the CARRIED clone of the
    // real cmdlet's bound parameters (the inner scriptblock's own $PSBoundParameters
    // would see hop plumbing, not user input) and Stop-Function carries -FunctionName
    // Set-DbaDbState (W1-090). The latch returns through the sentinel.
    private const string BeginScript = """
param($__allParams, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__allParams, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    function Get-WrongCombo($optset, $allParams) {
        $x = 0
        foreach ($opt in $optset) {
            if ($allParams.ContainsKey($opt)) { $x += 1 }
        }
        if ($x -gt 1) {
            $msg = $optset -Join ',-'
            $msg = "You can only specify one of: -" + $msg
            throw $msg
        }
    }

    . {
        $RWExclusive = @('ReadOnly', 'ReadWrite')
        $statusExclusive = @('Online', 'Offline', 'Emergency', 'Detached')
        $accessExclusive = @('SingleUser', 'RestrictedUser', 'MultiUser')
        $allParams = $__allParams
        try {
            Get-WrongCombo -optset $RWExclusive -allparams $allParams
        } catch {
            Stop-Function -Message $_ -FunctionName Set-DbaDbState
            return
        }
        try {
            Get-WrongCombo -optset $statusExclusive -allparams $allParams
        } catch {
            Stop-Function -Message $_ -FunctionName Set-DbaDbState
            return
        }
        try {
            Get-WrongCombo -optset $accessExclusive -allparams $allParams
        } catch {
            Stop-Function -Message $_ -FunctionName Set-DbaDbState
            return
        }
    }

    @{ __w3090State = @{ interrupted = (Test-FunctionInterrupt) } }
} $__allParams $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = ProcessScriptHead + "\n" + ProcessScriptTail;
}
