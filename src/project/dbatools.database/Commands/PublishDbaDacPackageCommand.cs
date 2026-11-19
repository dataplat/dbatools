#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Publishes a DAC package (dacpac/bacpac) to one or more databases. Port of
/// public/Publish-DbaDacPackage.ps1 (418 lines); the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// BEGIN+PROCESS, two hops. -Database and -Path bind ValueFromPipelineByPropertyName (NOT plain
/// ValueFromPipeline), so process fires once per PIPED OBJECT whose properties supply them - a real
/// cross-record axis. Two named sets with an explicit default: Obj (default) and Xml. ZERO positional
/// parameters. Surface confirmed against migration/baselines/Publish-DbaDacPackage.json with the
/// per-set reader.
///
/// INTERRUPT CARRY IS LIVE. Begin's non-Continue guards (:172 instance/connstring required, :187
/// bacpac+scriptonly conflict, :207 DacFx load failure) set the module latch, and process opens with
/// "if (Test-FunctionInterrupt) { return }" at :216. The begin hop reads the latch at
/// Get-Variable -Scope 0 and carries it; C# skips process. Mechanism measured in
/// migration/logs/probe-20260718-latch-sentinel.
///
/// FOUR CARRIES, found with the corrected detectors BEFORE coding:
///
/// 1. $ConnectionString - begin MUTATES it (:176, "$ConnectionString = $ConnectionString |
///    Convert-ConnectionString") and process ACCUMULATES it (:256, "+=" per instance) then iterates
///    it (:297). It is NOT one of the pipeline-bound parameters, so the binder never rewrites it: the
///    Convert'd value rides begin -> process, and the accumulation rides record -> record. Same class
///    as New-DbaDacProfile's $ConnectionString (W2-142), here compounded by a begin mutation.
///
/// 2. $Type - process MUTATES it (:227, bacpac auto-detect from the .bacpac extension of $Path). $Path
///    is per-record (VFPBPN), so record 1 may set $Type='Bacpac' and, because $Type is NOT the
///    pipeline parameter, the SOURCE keeps that value for a later record whose $Path is a .dacpac -
///    processing it as a Bacpac. Bug-for-bug: $Type carries record -> record so the port reproduces
///    it. Begin's own read of $Type (to pick $defaultColumns) uses the ORIGINAL value, which is why
///    $defaultColumns is carried from begin as-is and never recomputed - see 3.
///
/// 3. $defaultColumns - computed ONCE in begin (:180/:182/:189) from $Type and the ScriptOnly/
///    GenerateDeploymentReport boundness, read in process at :413 for Select-DefaultView. Because it
///    is fixed in begin, the source shows a quirk that rides verbatim: an auto-detected Bacpac
///    (:227) still emits the Dacpac column set begin chose. Carried from begin, never recomputed.
///
/// 4. Get-ServerName - a helper DEFINED in begin (:192) but CALLED in process (:299). Begin's scope
///    dies before process runs, so it is recreated verbatim at the top of the process hop, the same
///    treatment New-DbaDacProfile's helpers needed. It closes over nothing carried, so recreation is
///    faithful.
///
/// SIX CARRIES TOTAL. Beyond the four above, codex r1 found two more cross-record variables I had
/// missed - both non-obvious because their reads are on failure/declined paths:
///   $result (:348/:352) - assigned only inside the publish/script ShouldProcess gates, but read in
///     the finally at :367/:373. Under -WhatIf, or a declined gate, it is unassigned this record and
///     the SOURCE reads a PREVIOUS record's $result. Carried with an Assigned flag.
///   $server (:252/:384) - assigned in the SqlInstance loop, but read as -Target at :333 when
///     DacServices construction fails. A ConnectionString-only record never enters that loop, so the
///     source reads the prior record's $server. Carried with an Assigned flag; affects an error's
///     target object, so low-severity but a real divergence.
///
/// TWO CANDIDATES REFUTED, recorded so a reviewer does not re-add them:
///   $dacPackage (:262) / $bacPackage (:269) - assigned in a try whose catch is a NON-Continue
///     Stop-Function followed by return (:265/:272), so a load failure exits the record before the
///     reads at :348/:352/:357; and on the success path each is reassigned before its read within the
///     same record. No stale cross-record read is reachable.
///   $dacServices (:331) - REFUTED (codex r2 raised it; the finding is wrong). It is assigned in a
///     try (:330-332) whose catch (:333) is "Stop-Function ... -Continue", and its reads (:337
///     Register-ObjectEvent, then :348/:352/:357) are all in the SECOND try that FOLLOWS the catch.
///     Because PowerShell's continue is dynamically scoped, the catch's continue unwinds the
///     enclosing "foreach ($dbName)" loop, so on a construction failure :337 is never reached - every
///     read of $dacServices is gated behind a SUCCESSFUL construction that just assigned it. A stale
///     cross-record value is therefore unobservable. This is the continue-in-catch class: a read
///     INSIDE the catch (like $server's -Target at :333) is reachable and does carry; a read AFTER
///     the catch does not. Measured with a fall-through control in
///     migration/logs/probe-20260718-continue-propagation.
///
/// $deploymentReport (:366) needs NO carry, but the earlier rationale was imprecise (codex r1): its
/// read at :397 is UNCONDITIONAL in the output object, not inside the :365 report guard. The safety
/// is instead that GenerateDeploymentReport is a CONSTANT switch across records - so it is either
/// assigned-before-read every time (GDR true) or never assigned and read as $null every time (GDR
/// false). Neither differs from the source's persistent scope.
///
/// SEVEN Test-Bound PARAMETERS become carried caller-boundness flags, split across the blocks:
/// SqlInstance, ConnectionString, ScriptOnly, GenerateDeploymentReport in begin; Type, PublishXml,
/// DacOption, ScriptOnly, GenerateDeploymentReport in process (the last two tested in both). Type's
/// flag is load-bearing: the :226 auto-detect only fires when -Type was NOT explicitly passed, so a
/// value test would misfire when a caller passes -Type Dacpac for a .bacpac path.
///
/// FOUR $Pscmdlet.ShouldProcess gates (:347 generating script, :351 dacpac publish, :356 bacpac
/// import, :364 report/output) route to the real cmdlet via $__realCmdlet - the three destructive
/// operations plus the output stage, all reachable at the default $ConfirmPreference under
/// ConfirmImpact Medium. In-hop Stop-Function/Write-Message calls carry -FunctionName. -DacOption
/// carries Alias("Option"). The three switches (GenerateDeploymentReport, ScriptOnly,
/// IncludeSqlCmdVars) and inherited EnableException cross as SwitchParameter OBJECTS received untyped.
/// -OutputPath's default derives from Get-DbatoolsConfigValue - a DEF-007 bind-time default resolved
/// in the hop. Surface pinned by migration/baselines/Publish-DbaDacPackage.json.
/// </summary>
[Cmdlet(VerbsData.Publish, "DbaDacPackage", DefaultParameterSetName = "Obj", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed partial class PublishDbaDacPackageCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance(s). Source declares [DbaInstance[]]; the accelerator
    /// resolves to DbaInstanceParameter[] on the surface, which the baseline confirms.</summary>
    [Parameter]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Path to the dacpac or bacpac file.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true)]
    [PsStringCast]
    public string Path { get; set; } = null!;

    /// <summary>Path to a publish profile XML (Xml parameter set).</summary>
    [Parameter(ParameterSetName = "Xml")]
    [PsStringCast]
    public string? PublishXml { get; set; }

    /// <summary>The database(s) to publish to.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true)]
    [PsStringArrayCast]
    public string[] Database { get; set; } = null!;

    /// <summary>Connection strings to publish against instead of connecting.</summary>
    [Parameter]
    [PsStringArrayCast]
    public string[]? ConnectionString { get; set; }

    /// <summary>Generate a deployment report.</summary>
    [Parameter]
    public SwitchParameter GenerateDeploymentReport { get; set; }

    /// <summary>Generate the script only, without executing.</summary>
    [Parameter]
    public SwitchParameter ScriptOnly { get; set; }

    /// <summary>The package type; auto-detected from a .bacpac extension when not passed.</summary>
    [Parameter]
    [ValidateSet("Dacpac", "Bacpac")]
    [PsStringCast]
    public string Type { get; set; } = "Dacpac";

    /// <summary>Directory for generated script/report output.</summary>
    [Parameter]
    [PsStringCast]
    public string? OutputPath { get; set; }

    /// <summary>Prompt for SqlCmd variable values.</summary>
    [Parameter]
    public SwitchParameter IncludeSqlCmdVars { get; set; }

    /// <summary>A pre-built publish options object (Obj parameter set).</summary>
    [Parameter(ParameterSetName = "Obj")]
    [Alias("Option")]
    public object? DacOption { get; set; }

    /// <summary>Path to the DacFx assembly to load.</summary>
    [Parameter]
    [PsStringCast]
    public string? DacFxPath { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin's $ConnectionString/$defaultColumns; opaque to C#.
    private Hashtable? _beginState;
    // the $ConnectionString accumulator and mutated $Type carried record -> record; opaque to C#.
    private Hashtable? _state;
    // a failed begin guard silences every record.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            ConnectionString, ScriptOnly, GenerateDeploymentReport, Type, DacFxPath, EnableException,
            MyInvocation.BoundParameters.ContainsKey("SqlInstance"),
            MyInvocation.BoundParameters.ContainsKey("ConnectionString"),
            MyInvocation.BoundParameters.ContainsKey("ScriptOnly"),
            MyInvocation.BoundParameters.ContainsKey("GenerateDeploymentReport"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__publishDbaDacPackageBegin"))
            {
                if (sentinel["__publishDbaDacPackageBegin"] is Hashtable state)
                {
                    _beginState = state;
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
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

    protected override void ProcessRecord()
    {
        if (Interrupted || _interrupted)
            return;

        // Streaming, not buffered (DEF-001): the command publishes database by database and emits a
        // result object per database, so a buffered hop would discard the record of publishes already
        // performed when a later database's failure terminated the hop under -EnableException.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__publishDbaDacPackageProcess"))
            {
                _state = sentinel["__publishDbaDacPackageProcess"] as Hashtable;
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
            SqlInstance, SqlCredential, Path, PublishXml, Database, ConnectionString,
            GenerateDeploymentReport, Type, OutputPath, IncludeSqlCmdVars, DacOption, EnableException,
            _beginState, _state, this,
            MyInvocation.BoundParameters.ContainsKey("Type"),
            MyInvocation.BoundParameters.ContainsKey("PublishXml"),
            MyInvocation.BoundParameters.ContainsKey("DacOption"),
            MyInvocation.BoundParameters.ContainsKey("ScriptOnly"),
            MyInvocation.BoundParameters.ContainsKey("GenerateDeploymentReport"),
            MyInvocation.BoundParameters.ContainsKey("OutputPath"),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
}