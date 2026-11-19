#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Imports a perfmon collector-set template. Port of
/// public/Import-DbaPfDataCollectorSetTemplate.ps1 (W1-107). The ENTIRE process body
/// rides one VERBATIM module hop per record (both loops and every contained
/// Stop-Function -Continue), with $Pscmdlet.ShouldProcess routed to the REAL cmdlet
/// (the W1-085 pattern) and Test-Bound modeled as carried flags. Function-scope
/// mutations persist across records through a state bag: $Path grows via += (the
/// ReferenceEquals reset detects a pipeline-by-property rebind - FullName alias),
/// Set-Variable DisplayName sticks once set, the `foreach ($instance in $instances)`
/// loop variable SHADOWS the -Instance parameter and its leftover gates later service
/// discovery, and a WhatIf-denied branch re-emits the STALE prior $output - all
/// preserved. The begin block resolves the module root with the source-carried
/// RB-IMP-51 fallback. Surface pinned by
/// migration/baselines/Import-DbaPfDataCollectorSetTemplate.json.
/// </summary>
[Cmdlet(VerbsData.Import, "DbaPfDataCollectorSetTemplate", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed partial class ImportDbaPfDataCollectorSetTemplateCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = BuildDefaultComputerName();

    private static DbaInstanceParameter[]? BuildDefaultComputerName()
    {
        string? name = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(name))
            return null;
        return new DbaInstanceParameter[] { new DbaInstanceParameter(name) };
    }

    /// <summary>Windows credential for the remote work.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Display name for the imported set.</summary>
    [Parameter(Position = 2)]
    public string? DisplayName { get; set; }

    /// <summary>Enables the set's schedules.</summary>
    [Parameter]
    public SwitchParameter SchedulesEnabled { get; set; }

    /// <summary>Root output path.</summary>
    [Parameter(Position = 3)]
    public string? RootPath { get; set; }

    /// <summary>Enables segmenting.</summary>
    [Parameter]
    public SwitchParameter Segment { get; set; }

    /// <summary>Maximum segment duration.</summary>
    [Parameter(Position = 4)]
    public int SegmentMaxDuration { get; set; }

    /// <summary>Maximum segment size.</summary>
    [Parameter(Position = 5)]
    public int SegmentMaxSize { get; set; }

    /// <summary>Output subdirectory.</summary>
    [Parameter(Position = 6)]
    public string? Subdirectory { get; set; }

    /// <summary>Subdirectory format value.</summary>
    [Parameter(Position = 7)]
    public int SubdirectoryFormat { get; set; } = 3;

    /// <summary>Subdirectory format pattern.</summary>
    [Parameter(Position = 8)]
    public string SubdirectoryFormatPattern { get; set; } = "yyyyMMdd\\-NNNNNN";

    /// <summary>Associated task name.</summary>
    [Parameter(Position = 9)]
    public string? Task { get; set; }

    /// <summary>Runs the task as self.</summary>
    [Parameter]
    public SwitchParameter TaskRunAsSelf { get; set; }

    /// <summary>Task arguments.</summary>
    [Parameter(Position = 10)]
    public string? TaskArguments { get; set; }

    /// <summary>Task user text arguments.</summary>
    [Parameter(Position = 11)]
    public string? TaskUserTextArguments { get; set; }

    /// <summary>Stops the set on completion.</summary>
    [Parameter]
    public SwitchParameter StopOnCompletion { get; set; }

    /// <summary>Template file path(s).</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 12)]
    [Alias("FullName")]
    public string[]? Path { get; set; }

    /// <summary>Bundled template name(s).</summary>
    [Parameter(Position = 13)]
    public string[]? Template { get; set; }

    /// <summary>SQL instance name(s) for counter cloning.</summary>
    [Parameter(Position = 14)]
    public string[]? Instance { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _moduleRoot;

    // PS function-scope locals persisting across records (the state bag rides the hop
    // and comes back as the sentinel item).
    private Hashtable? _state;
    private object? _pathState;
    private object? _lastBoundPath;
    private object? _displayNameState;
    private bool _displayNameInitialized;

    protected override void BeginProcessing()
    {
        Collection<PSObject> results = NestedCommand.InvokeScoped(this, ModuleRootScript);
        _moduleRoot = results.Count == 1 ? results[0] : null;
    }

    protected override void ProcessRecord()
    {
        // PS: named $Path keeps ONE array reference across records (the += growth
        // persists); pipeline-by-property (FullName) re-binds a fresh array per record.
        if (!ReferenceEquals(Path, _lastBoundPath) || _pathState is null)
        {
            _pathState = Path;
            _lastBoundPath = Path;
        }

        if (!_displayNameInitialized)
        {
            // PS: an unbound [string] parameter reads "".
            _displayNameState = DisplayName ?? "";
            _displayNameInitialized = true;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w1107State"))
            {
                _state = sentinel["__w1107State"] as Hashtable;
                if (_state is not null)
                {
                    _pathState = _state["Path"];
                    _displayNameState = _state["DisplayName"];
                }
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
            ComputerName, Credential, _displayNameState, SchedulesEnabled.ToBool(), RootPath ?? "",
            Segment.ToBool(), SegmentMaxDuration, SegmentMaxSize, Subdirectory ?? "",
            SubdirectoryFormat, SubdirectoryFormatPattern, Task ?? "", TaskRunAsSelf.ToBool(),
            TaskArguments ?? "", TaskUserTextArguments ?? "", StopOnCompletion.ToBool(),
            _pathState, Template, Instance, _moduleRoot, _state,
            TestBound("Path"), TestBound("Template"), TestBound("DisplayName"), TestBound("RootPath"),
            EnableException.ToBool(), this, BoundVerbose(), BoundDebug());
    }

    /// <summary>A bound -Debug carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundDebug()
    {
        object? debug;
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundVerbose()
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }
}
