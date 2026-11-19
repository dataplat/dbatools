#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Masks data in database tables from a masking configuration file. Port of
/// public/Invoke-DbaDbDataMasking.ps1; the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// This is a BEGIN+PROCESS command shipped as TWO hops. FilePath is ValueFromPipeline, so
/// process fires once per piped configuration file. The begin block runs once: it resolves the
/// supported randomizer type/subtype lists (two Get-DbaRandomizedType calls) and applies the
/// falsy-int defaults (ModulusFactor 10, CommandTimeout 300, BatchSize 1000, Retry 1000, each
/// with its Verbose message). Folding begin into every record would re-run those calls and
/// re-emit those messages per record, so the split is required for parity. The begin results
/// carry to process in an OPAQUE hashtable the C# side never interprets (container cast only -
/// values built by PS functions arrive PSObject-wrapped, and a C# "as" cast on a wrapped value
/// silently nulls it; the Compare-DbaDbSchema carry defect class).
///
/// The process hop STREAMS (InvokeScopedStreaming, not buffered InvokeScoped): this command
/// mass-mutates table data and emits one result object per table - the audit trail of work
/// already done. Buffered invocation would discard those records when a later table's failure
/// terminates the hop under -EnableException (the DEF-001 class).
///
/// INTERRUPT CARRY. The source's process opens with "if (Test-FunctionInterrupt) { return }":
/// a prior record's direct Stop-Function halts later records. Across separate hop invocations
/// the module interrupt flag does not survive, so each hop reads it at Get-Variable -Scope 0
/// after the dot-sourced body and carries it; C# skips the hop when a prior record carried
/// true. Only DIRECT body Stop-Functions set it - one buried in a nested helper does not,
/// exactly as the function-scope Test-FunctionInterrupt behaved. Several body Stop-Functions
/// have neither -Continue nor a following return; the current record keeps executing after
/// them and only the NEXT record short-circuits - preserved verbatim.
///
/// CROSS-RECORD STATE. These function-scope locals are branch-assigned and read on paths that
/// can run before any assignment in the current record, so in the function world they carried
/// values across pipeline records: identityColumn (only assigned on the non-WhatIf branch;
/// read under -WhatIf), convertedValue and lookupResult and maskingErrorFlag (read in the
/// unique-index section before the standard-column section assigns them), charstring/min/max
/// and columnobject (read in the composites/unique-index sections from a previous loop's
/// iteration), and dictionaryFileName (Replace'd before assignment on the non-Windows path);
/// plus Database (when unbound, record one derives it from its config file and later records
/// must keep that value, not re-derive from their own) and insertValue (its conversion catches
/// lack -Continue, so a failure falls through to a read of the prior iteration's value).
/// They ride a state sentinel with per-name Assigned flags, restored at the next hop's top,
/// so unset-vs-assigned semantics survive (an unset read walks the scope chain as the
/// function's did). The source also reads variables it NEVER assigns - $Force (begin),
/// $uniqueIndex, $columnValue, $faker - which ride verbatim as unset reads.
///
/// The begin block's "if ($Force) { $ConfirmPreference = 'none' }" effect is resolved ONCE in
/// the begin hop ($Force is undeclared and dynamic) and carried as a flag the process hop
/// applies to its own $ConfirmPreference, so a mid-pipeline change to an upstream $Force
/// cannot alter confirmation behavior between records - the function's run-once begin exactly.
///
/// ATTRIBUTION SHIM (the Get-PSCallStack class): Write-ProgressHelper derives its caller name
/// from (Get-PSCallStack)[1].Command; a bare hop call would read the generated scriptblock
/// frame. Both call sites route through a thin named wrapper function Invoke-DbaDbDataMasking
/// inside the hop, so the helper sees the real command name. The helper has no Stop-Function
/// latch, so the wrapper needs no dot-sourcing.
///
/// Source quirks preserved bug-for-bug: the KeepNull condition's unparenthesized -and/-or
/// precedence; $convertedValue.ErrorMessage checked where the assignment went to $insertValue;
/// $columnobject read inside the unique-index loop whose iterator is $columnMaskInfo; the
/// dictionary filename Replace on the prior record's value. The one ShouldProcess gate routes
/// to the real cmdlet via $__realCmdlet (ConfirmImpact High mirrored); Test-Bound never rides
/// a hop, so its three MaxValue probes read the carried $__boundMaxValue flag. In-hop
/// Stop-Function/Write-Message carry -FunctionName. Surface pinned by
/// migration/baselines/Invoke-DbaDbDataMasking.json (implicit positions 0-16 made explicit).
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbDataMasking", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed partial class InvokeDbaDbDataMaskingCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to mask; defaults to the database named in the config file.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The masking configuration file path (or URL), typically from
    /// New-DbaDbMaskingConfig; pipes from Get-ChildItem.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 3)]
    [Alias("Path", "FullName")]
    public object? FilePath { get; set; }

    /// <summary>The faker locale used for generated values.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string Locale { get; set; } = "en";

    /// <summary>The character set used for random string generation.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string CharacterString { get; set; } = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

    /// <summary>Mask only these tables.</summary>
    [Parameter(Position = 6)]
    [PsStringArrayCast]
    public string[]? Table { get; set; }

    /// <summary>Mask only these columns.</summary>
    [Parameter(Position = 7)]
    [PsStringArrayCast]
    public string[]? Column { get; set; }

    /// <summary>Skip these tables.</summary>
    [Parameter(Position = 8)]
    [PsStringArrayCast]
    public string[]? ExcludeTable { get; set; }

    /// <summary>Skip these columns.</summary>
    [Parameter(Position = 9)]
    [PsStringArrayCast]
    public string[]? ExcludeColumn { get; set; }

    /// <summary>Cap for generated numeric/string lengths; config-file values win below the cap.</summary>
    [Parameter(Position = 10)]
    public int MaxValue { get; set; }

    /// <summary>Modulus deciding how often nullable columns receive NULL (default 10, applied
    /// in the begin hop).</summary>
    [Parameter(Position = 11)]
    public int ModulusFactor { get; set; }

    /// <summary>Query timeout in seconds (default 300, applied in the begin hop).</summary>
    [Parameter(Position = 12)]
    public int CommandTimeout { get; set; }

    /// <summary>Rows per UPDATE batch (default 1000, applied in the begin hop).</summary>
    [Parameter(Position = 13)]
    public int BatchSize { get; set; }

    /// <summary>Unique-value generation retry cap (default 1000, applied in the begin hop).</summary>
    [Parameter(Position = 14)]
    public int Retry { get; set; }

    /// <summary>CSV dictionary files of deterministic value mappings to pre-load.</summary>
    [Parameter(Position = 15)]
    [PsStringArrayCast]
    public string[]? DictionaryFilePath { get; set; }

    /// <summary>Directory to export the deterministic value dictionary to.</summary>
    [Parameter(Position = 16)]
    [PsStringCast]
    public string? DictionaryExportPath { get; set; }

    /// <summary>Declared by the source but never read in its body; kept for surface parity.</summary>
    [Parameter]
    public SwitchParameter ExactLength { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Begin-hop results (supported type lists + defaulted ints), carried as an OPAQUE
    // hashtable: C# casts only the container, never the values (function-emitted values are
    // PSObject-wrapped and a C# "as" cast would silently null them).
    private Hashtable? _beginState;
    // The cross-record function-scope locals, carried with per-name Assigned flags.
    private Hashtable? _state;
    // A direct process Stop-Function on an earlier record halts the remaining records.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            ModulusFactor, CommandTimeout, BatchSize, Retry,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__invokeDbaDbDataMaskingBegin"))
            {
                _beginState = sentinel["__invokeDbaDbDataMaskingBegin"] as Hashtable;
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

        // Streaming, not buffered (DEF-001): per-table result objects are the audit trail of
        // destructive updates already executed; they must reach the caller before a later
        // table or record terminates the hop under -EnableException.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__invokeDbaDbDataMaskingProcess"))
            {
                if (sentinel["__invokeDbaDbDataMaskingProcess"] is Hashtable result)
                {
                    _state = result["State"] as Hashtable;
                    _interrupted = LanguagePrimitives.IsTrue(result["Interrupted"]);
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
            SqlInstance, SqlCredential, Database, FilePath, Locale, CharacterString, Table,
            Column, ExcludeTable, ExcludeColumn, MaxValue, DictionaryFilePath,
            DictionaryExportPath, EnableException.ToBool(), _beginState, _state, this,
            MyInvocation.BoundParameters.ContainsKey("MaxValue"),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
}
