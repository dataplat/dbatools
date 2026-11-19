#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Renames databases, filegroups, logical files and physical filenames. Port of
/// public/Rename-DbaDatabase.ps1 (W3-081) - the largest lane-D hop port (620-line process
/// body, verbatim). Begin block splits three ways per the established laws: the
/// SetOffline-without-FileName validation and $CurrentDate (Get-Date, midnight-stable only
/// within a day) ride a BEGIN hop whose sentinel carries the Stop-Function LATCH state
/// (the W1-108/W3-066 class: the source gates every process record on
/// Test-FunctionInterrupt, whose function-scope latch cannot cross hop scopes - the C#
/// _hopInterrupted flag replays it, fed by both the begin and per-record process
/// sentinels); the Copy-family `if ($Force) { $ConfirmPreference = 'none' }` line rides at
/// PROCESS-hop top with the INNER $PSCmdlet serving every ShouldProcess gate (W3-005/
/// W3-064 convention - NO $__realCmdlet in this port); the two begin-scope helper
/// functions (Get-DbaNameStructure, Get-DbaKeyByValue) are re-declared at process-hop top
/// (function definitions cannot cross hop scopes). The process body rides VERBATIM inside
/// a dot-sourced block (two `Stop-Function; return` early exits re-fire per record); all
/// per-record state ($InstanceDbs/$InstanceFiles/$Pending_Renames/$Entities_Before) is
/// record-local in the source. Mechanical W1-090 pass: -FunctionName Rename-DbaDatabase
/// appended to all 26 Stop-Function/Write-Message call sites. Private/dependency calls
/// ride the hop (Get-DbaFile, Test-PSRemoting, Resolve-DbaNetworkName, Join-AdminUnc,
/// Invoke-Command2, Set-DbaDbState, Select-DefaultView, [DbaValidate]). NO
/// DefaultParameterSetName (the source declares none - zero-determining-arg invocations
/// fail set resolution identically). NO WarningAction carrier (codex W3-005 r3). Surface
/// pinned by migration/baselines/Rename-DbaDatabase.json (sets Server {SqlInstance
/// Mandatory, Database} + Pipe {InputObject Database[] Mandatory VFP}, no positions,
/// ConfirmImpact Medium).
/// </summary>
[Cmdlet(VerbsCommon.Rename, "DbaDatabase", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed partial class RenameDbaDatabaseCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Server")]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(ParameterSetName = "Server")]
    public object[]? Database { get; set; }

    /// <summary>Database(s) to exclude.</summary>
    [Parameter]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Process all databases.</summary>
    [Parameter]
    public SwitchParameter AllDatabases { get; set; }

    /// <summary>New database name template (&lt;DBN&gt;/&lt;DATE&gt; placeholders).</summary>
    [Parameter]
    public string? DatabaseName { get; set; }

    /// <summary>New filegroup name template.</summary>
    [Parameter]
    public string? FileGroupName { get; set; }

    /// <summary>New logical file name template.</summary>
    [Parameter]
    public string? LogicalName { get; set; }

    /// <summary>New physical file name template.</summary>
    [Parameter]
    public string? FileName { get; set; }

    /// <summary>Strip pre-existing entity names from placeholders before composing.</summary>
    [Parameter]
    public SwitchParameter ReplaceBefore { get; set; }

    /// <summary>Kills connections and suppresses prompts (ConfirmPreference override).</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>Performs the physical file moves after renaming.</summary>
    [Parameter]
    public SwitchParameter Move { get; set; }

    /// <summary>Sets the database offline after filename renames.</summary>
    [Parameter]
    public SwitchParameter SetOffline { get; set; }

    /// <summary>Shows what would be renamed without doing it.</summary>
    [Parameter]
    public SwitchParameter Preview { get; set; }

    /// <summary>SMO Database object(s), typically from Get-DbaDatabase.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "Pipe")]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin-computed $CurrentDate rides the state bag; the begin/process Stop-Function
    // latch replays through _hopInterrupted (Test-FunctionInterrupt cannot cross hops).
    private Hashtable? _state;
    private bool _hopInterrupted;

    protected override void BeginProcessing()
    {
        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Rename-DbaDatabase");

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            EnableException.ToBool(),
            TestBound(nameof(SetOffline)), TestBound(nameof(FileName)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3081State"))
            {
                _state = sentinel["__w3081State"] as Hashtable;
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
            DatabaseName, FileGroupName, LogicalName, FileName, ReplaceBefore.ToBool(),
            Force.ToBool(), Move.ToBool(), SetOffline.ToBool(), Preview.ToBool(),
            InputObject, EnableException.ToBool(), _state, _hopInterrupted,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3081State"))
            {
                Hashtable? latch = sentinel["__w3081State"] as Hashtable;
                if (latch is not null)
                {
                    if (latch["interrupted"] is bool interrupted && interrupted)
                        _hopInterrupted = true;
                    // Cross-record carry (B batch): leaked fn-scope locals + the
                    // ShouldProcess Yes/No-to-All engine state, merged into the begin
                    // bag so the next record's hop restores them like the source scope.
                    if (_state is not null)
                    {
                        _state["Final_Renames"] = latch["Final_Renames"];
                        _state["dirfiles"] = latch["dirfiles"];
                        _state["shouldProcessContinueStatus"] = latch["shouldProcessContinueStatus"];
                    }
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

    // PS: the begin-block validation + $CurrentDate VERBATIM (helper functions and the
    // ConfirmPreference line live at process-hop top instead - see the class doc). The
    // sentinel carries $CurrentDate plus the Stop-Function latch state.
    private const string BeginScript = """
param($EnableException, $__boundSetOffline, $__boundFileName, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($EnableException, $__boundSetOffline, $__boundFileName, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $CurrentDate = Get-Date -Format 'yyyyMMdd'

    if (($__boundSetOffline) -and (-not($__boundFileName))) {
        Stop-Function -Category InvalidArgument -Message "-SetOffline is only useful when -FileName is passed. Quitting." -FunctionName Rename-DbaDatabase
    }

    @{ __w3081State = @{ CurrentDate = $CurrentDate; interrupted = (Test-FunctionInterrupt) } }
} $EnableException $__boundSetOffline $__boundFileName $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the ENTIRE process body VERBATIM per record inside a dot-sourced block (two
    // validation early returns re-fire per record). Substitutions only: the
    // Test-FunctionInterrupt gate -> the carried $__hopInterrupted flag, and the
    // mechanical -FunctionName Rename-DbaDatabase appends (W1-090) on every
    // Stop-Function/Write-Message. $PSCmdlet stays UNSUBSTITUTED: the inner block's own
    // cmdlet serves the gates so the verbatim Force/ConfirmPreference override works
    // (W3-005/W3-064 Copy-family convention). The trailing sentinel re-reads the latch so
    // a mid-record no-Continue Stop-Function suppresses LATER records like the source.
    // The verbatim process-body hop script lives in the two Script* partials (400-line
    // file rule): compile-time concatenation is byte-identical to the single constant.
    private const string ProcessScript = ProcessScriptHead + "\n" + ProcessScriptTail;
}
