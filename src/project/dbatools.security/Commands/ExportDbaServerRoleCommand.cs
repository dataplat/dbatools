#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports server-level role definitions from a SQL Server instance as T-SQL scripts.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that role enumeration, the
/// generated T-SQL, permission scripting, file output, and dbatools stream and error handling stay
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// The script has begin, process, and end blocks and produces all of its output from the end block,
/// which walks a collection the process block fills. The port collects the piped InputObject records
/// across ProcessRecord and then, in EndProcessing, runs ONE hop that executes the begin body, the
/// process body over the collected records, and the end body in a single scope - so the accumulators
/// persist naturally. The process body is only run when a record was actually processed, matching the
/// script (an empty pipeline runs begin and end but not process); it is dot-sourced so its early
/// returns leave only that block and the end body still emits.
/// </para>
/// <para>
/// The two config-value parameter defaults (Path, BatchSeparator) are reproduced inside the hop,
/// applied only when the caller did not bind them, and the begin block's default ScriptingOptions is
/// created only when ScriptingOptionsObject was not bound. The end block's Get-ExportFilePath call
/// reads the caller's bound Path and FilePath, which a hop cannot see, so those bound values are
/// carried in explicitly. Every switch parameter is carried as a plain bool and received untyped,
/// because a switch in the inner CmdletBinding scriptblock is excluded from positional binding.
/// </para>
/// </remarks>
[Cmdlet(VerbsData.Export, "DbaServerRole")]
public sealed partial class ExportDbaServerRoleCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Server or server-role objects to export, typically piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 2)]
    public object[]? InputObject { get; set; }

    /// <summary>Scripting options applied when generating the role definitions.</summary>
    [Parameter(Position = 3)]
    public Microsoft.SqlServer.Management.Smo.ScriptingOptions? ScriptingOptionsObject { get; set; }

    /// <summary>The server role or roles to export.</summary>
    [Parameter(Position = 4)]
    public string[]? ServerRole { get; set; }

    /// <summary>Server roles to exclude.</summary>
    [Parameter(Position = 5)]
    public string[]? ExcludeServerRole { get; set; }

    /// <summary>The directory the exported script is written to.</summary>
    [Parameter(Position = 6)]
    public string? Path { get; set; }

    /// <summary>An explicit output file path.</summary>
    [Parameter(Position = 7)]
    [Alias("OutFile", "FileName")]
    public string? FilePath { get; set; }

    /// <summary>The batch separator placed between statements.</summary>
    [Parameter(Position = 8)]
    public string? BatchSeparator { get; set; }

    /// <summary>The file encoding of the exported script.</summary>
    [Parameter(Position = 9)]
    [PsStringCast]
    [ValidateSet("ASCII", "BigEndianUnicode", "Byte", "String", "Unicode", "UTF7", "UTF8", "Unknown")]
    public string Encoding { get; set; } = "UTF8";

    /// <summary>Excludes fixed (built-in) server roles from the export.</summary>
    [Parameter]
    public SwitchParameter ExcludeFixedRole { get; set; }

    /// <summary>Includes role membership (ALTER SERVER ROLE ADD MEMBER) statements.</summary>
    [Parameter]
    public SwitchParameter IncludeRoleMember { get; set; }

    /// <summary>Returns the generated SQL to the pipeline instead of writing a file.</summary>
    [Parameter]
    public SwitchParameter Passthru { get; set; }

    /// <summary>Prevents overwriting an existing output file.</summary>
    [Parameter]
    public SwitchParameter NoClobber { get; set; }

    /// <summary>Appends to the output file instead of replacing it.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    /// <summary>Omits the descriptive comment prefix from the script.</summary>
    [Parameter]
    public SwitchParameter NoPrefix { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private readonly List<object?[]?> _batches = new List<object?[]?>();

    /// <summary>Records each pipeline record's input as a batch; the work runs once in EndProcessing.</summary>
    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // One batch per ProcessRecord call, preserving the boundaries the script's process block saw
        // (an empty pipeline never calls ProcessRecord, so there are no batches and process never runs).
        _batches.Add(InputObject);
    }

    /// <summary>Runs the begin, process, and end logic in one hop against the collected input.</summary>
    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

        // [DEF-001] streamed via InvokeScopedStreaming: the hop body loops emitting per-item and
        // carries reachable terminating throws (-Continue Stop-Function under -EnableException), so a
        // buffered InvokeScoped would lose an earlier item's emit when a later item throws. Streaming
        // yields each record as produced; no state carry on this row.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, _batches.ToArray(), ScriptingOptionsObject, ServerRole, ExcludeServerRole,
            Path, FilePath, BatchSeparator, Encoding,
            ExcludeFixedRole.ToBool(), IncludeRoleMember.ToBool(), Passthru.ToBool(), NoClobber.ToBool(),
            Append.ToBool(), NoPrefix.ToBool(), EnableException.ToBool(),
            TestBound(nameof(Path)), TestBound(nameof(BatchSeparator)), TestBound(nameof(ScriptingOptionsObject)),
            BoundValue("Path"), BoundValue("FilePath"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private object? BoundValue(string name)
    {
        return MyInvocation.BoundParameters.TryGetValue(name, out object? value) ? value : null;
    }
}
