#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates databases with optional advanced file-layout configuration. Port of
/// public/New-DbaDatabase.ps1 (W3-066). Begin: the advancedconfig flag is a pure function of
/// sixteen bound parameters (TestBound any-of) computed C#-side; when set, a begin HOP emits
/// the once-per-invocation "Advanced data file configuration will be invoked" Verbose. The
/// process body rides one VERBATIM module hop per record inside a DOT-SOURCED inner block
/// (W1-108: the secondary-file do/while catch fires Stop-Function WITHOUT -Continue then
/// `return` - an early exit that ALSO latches Test-FunctionInterrupt, so the sentinel carries
/// an interrupted flag feeding the C#-side latch exactly like the Move-family begin latch).
/// The __w3066State sentinel carries the SIX size parameters the source mutates WITHOUT a
/// Test-Bound re-gate (PrimaryFilesize/PrimaryFileMaxSize/LogSize/LogMaxSize/
/// SecondaryFilesize/SecondaryFileMaxSize - later instances compare model-db sizes against
/// the MUTATED values) plus the stale-able locals. QUIRKS PRESERVED VERBATIM: unbound -Name
/// re-randomizes PER INSTANCE (Test-Bound reads bound state, not the variable); the do/while
/// $bail flag is dead (the return exits first); the SQL 2000 advancedconfig abort; Azure
/// https path separators; $PSCmdlet/$Pscmdlet casing. ShouldProcess routes to the REAL
/// cmdlet (no ConfirmPreference override; ConfirmImpact Low mirrored). Bind-time casts:
/// [PsStringCast] on the ValidateSet RecoveryModel and DefaultFileGroup (W1-032). Private
/// Add-TeppCacheItem and nested Get-DbaAvailableCollation/Get-DbaDefaultPath/Test-DbaPath/
/// New-DbaDirectory/Get-DbaDatabase ride the hop. NO WarningAction carrier (codex W3-005 r3:
/// host replay owns every value). Surface pinned by migration/baselines/New-DbaDatabase.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDatabase", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed partial class NewDbaDatabaseCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database name(s); a random name is generated when omitted.</summary>
    [Parameter(Position = 2)]
    [Alias("Database")]
    public string[]? Name { get; set; }

    /// <summary>The collation for the new database; instance default when omitted.</summary>
    [Parameter(Position = 3)]
    public string? Collation { get; set; }

    /// <summary>The recovery model; model-database default when omitted.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    [ValidateSet("Simple", "Full", "BulkLogged")]
    public string? RecoveryModel { get; set; }

    /// <summary>The database owner login set after creation.</summary>
    [Parameter(Position = 5)]
    public string? Owner { get; set; }

    /// <summary>Data file directory (or Azure URL); instance default data path when omitted.</summary>
    [Parameter(Position = 6)]
    public string? DataFilePath { get; set; }

    /// <summary>Log file directory (or Azure URL); instance default log path when omitted.</summary>
    [Parameter(Position = 7)]
    public string? LogFilePath { get; set; }

    /// <summary>Primary file size in MB; model-derived when omitted.</summary>
    [Parameter(Position = 8)]
    public int PrimaryFilesize { get; set; }

    /// <summary>Primary file growth in MB.</summary>
    [Parameter(Position = 9)]
    public int PrimaryFileGrowth { get; set; }

    /// <summary>Primary file max size in MB.</summary>
    [Parameter(Position = 10)]
    public int PrimaryFileMaxSize { get; set; }

    /// <summary>Log file size in MB.</summary>
    [Parameter(Position = 11)]
    public int LogSize { get; set; }

    /// <summary>Log file growth in MB.</summary>
    [Parameter(Position = 12)]
    public int LogGrowth { get; set; }

    /// <summary>Log file max size in MB.</summary>
    [Parameter(Position = 13)]
    public int LogMaxSize { get; set; }

    /// <summary>Secondary file size in MB.</summary>
    [Parameter(Position = 14)]
    public int SecondaryFilesize { get; set; }

    /// <summary>Secondary file growth in MB.</summary>
    [Parameter(Position = 15)]
    public int SecondaryFileGrowth { get; set; }

    /// <summary>Secondary file max size in MB.</summary>
    [Parameter(Position = 16)]
    public int SecondaryFileMaxSize { get; set; }

    /// <summary>Number of secondary data files.</summary>
    [Parameter(Position = 17)]
    public int SecondaryFileCount { get; set; }

    /// <summary>Which filegroup becomes the default (Primary or Secondary).</summary>
    [Parameter(Position = 18)]
    [PsStringCast]
    [ValidateSet("Primary", "Secondary")]
    public string? DefaultFileGroup { get; set; }

    /// <summary>Suffix appended to the primary data file name.</summary>
    [Parameter(Position = 19)]
    public string? DataFileSuffix { get; set; }

    /// <summary>Suffix appended to the log file name; defaults to _log.</summary>
    [Parameter(Position = 20)]
    public string LogFileSuffix { get; set; } = "_log";

    /// <summary>Suffix appended to the secondary filegroup and file names.</summary>
    [Parameter(Position = 21)]
    public string? SecondaryDataFileSuffix { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The source's Stop-Function-without-Continue latch inside the secondary-file catch
    // (Test-FunctionInterrupt): the sentinel reports it, subsequent records early-return.
    private bool _hopInterrupted;

    // PS begin: $advancedconfig is a pure function of the sixteen bound parameters.
    private bool _advancedConfig;

    // Fn-scope state persisting across records: the six size params the source mutates
    // WITHOUT Test-Bound re-gates, plus stale-able locals (the bag rides the hop).
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        // PS begin: if (Test-Bound -ParameterName <16 names>) { $advancedconfig = $true;
        // Write-Message "Advanced data file configuration will be invoked" -Level Verbose }
        if (TestBound("DataFilePath", "DefaultFileGroup", "LogFilePath", "LogGrowth", "LogMaxSize",
            "LogSize", "PrimaryFileGrowth", "PrimaryFileMaxSize", "PrimaryFilesize",
            "SecondaryFileCount", "SecondaryFileGrowth", "SecondaryFileMaxSize", "SecondaryFilesize",
            "DataFileSuffix", "LogFileSuffix", "SecondaryDataFileSuffix"))
        {
            _advancedConfig = true;
            foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
                EnableException.ToBool(),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
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
            }
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // PS: if (Test-FunctionInterrupt) { return } - latched by the secondary-file
        // catch's Stop-Function-without-Continue on an earlier record.
        if (_hopInterrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3066State"))
            {
                _state = sentinel["__w3066State"] as Hashtable;
                if (_state is not null && LanguagePrimitives.IsTrue(_state["interrupted"]))
                {
                    _hopInterrupted = true;
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
            SqlInstance, SqlCredential, Name, Collation, RecoveryModel, Owner ?? "",
            DataFilePath, LogFilePath, PrimaryFilesize, PrimaryFileGrowth, PrimaryFileMaxSize,
            LogSize, LogGrowth, LogMaxSize, SecondaryFilesize, SecondaryFileGrowth,
            SecondaryFileMaxSize, SecondaryFileCount, DefaultFileGroup, DataFileSuffix ?? "",
            LogFileSuffix, SecondaryDataFileSuffix ?? "", EnableException.ToBool(),
            _advancedConfig, _state,
            TestBound(nameof(Name)), TestBound(nameof(DataFilePath)), TestBound(nameof(LogFilePath)),
            TestBound(nameof(PrimaryFilesize)), TestBound(nameof(PrimaryFileGrowth)),
            TestBound(nameof(PrimaryFileMaxSize)), TestBound(nameof(LogSize)),
            TestBound(nameof(LogGrowth)), TestBound(nameof(LogMaxSize)),
            TestBound(nameof(SecondaryFilesize)), TestBound(nameof(SecondaryFileGrowth)),
            TestBound(nameof(SecondaryFileMaxSize)), TestBound(nameof(SecondaryFileCount)),
            this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

}
