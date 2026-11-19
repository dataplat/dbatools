#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Builds a DACPAC from a directory of SQL script files using the DacFx model API. Port of
/// public/New-DbaDacPackage.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// BEGIN+PROCESS, two hops. NO parameter is ValueFromPipeline, so process fires exactly once - the
/// cross-record carry axis does not exist for this row. Stated explicitly rather than skipped,
/// because a parameter-only check is what let a destructive-path carry through on Move-DbaDbFile.
///
/// BEGIN CARRIES ONE VALUE. Begin verifies the DacFx model types are loadable and resolves -Path to
/// a full filesystem path, leaving $resolvedPath, which process reads five times (Get-Item, the
/// Get-ChildItem enumeration, and three messages). That single value rides the begin sentinel; the
/// only other begin statement is a discard.
///
/// INTERRUPT CARRY IS LIVE. Both begin guards - DacFx types unavailable, and -Path not found - are
/// Stop-Function WITHOUT -Continue followed by return, so each sets the module interrupt flag, and
/// the source's process opens with "if (Test-FunctionInterrupt) { return }". Within one function
/// scope that means a begin failure produces no output at all. Across separate hop invocations the
/// flag does not survive, so the begin hop reads it at Get-Variable -Scope 0 after its dot-sourced
/// body and carries it, and C# skips process when begin set it. The body keeps its own verbatim
/// Test-FunctionInterrupt line. Every one of the ten Stop-Function calls in this command omits
/// -Continue, so any failure ends the run rather than skipping an item.
///
/// The two $PSCmdlet.ShouldProcess gates - creating the output directory, and creating the DACPAC
/// itself - route to the real cmdlet via $__realCmdlet (SupportsShouldProcess, ConfirmImpact Low
/// mirrored). Both bodies are dot-sourced so every "Stop-Function; return" exits the body only
/// while the sentinel still emits. In-hop Stop-Function/Write-Message carry -FunctionName. Implicit
/// positions 0-6 are made explicit (Path 0 Mandatory, OutputPath 1, DacVersion 2, DacDescription 3,
/// DatabaseName 4, SqlServerVersion 5, Filter 6); the two switches correctly carry none. Surface
/// pinned by migration/baselines/New-DbaDacPackage.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDacPackage", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed partial class NewDbaDacPackageCommand : DbaBaseCmdlet
{
    /// <summary>Directory containing the SQL script files.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [PsStringCast]
    public string Path { get; set; } = null!;

    /// <summary>Where the resulting DACPAC is written.</summary>
    [Parameter(Position = 1)]
    [PsStringCast]
    public string? OutputPath { get; set; }

    /// <summary>Version stamped into the package.</summary>
    [Parameter(Position = 2)]
    public Version DacVersion { get; set; } = new Version("1.0.0.0");

    /// <summary>Description stamped into the package.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? DacDescription { get; set; }

    /// <summary>Database name recorded in the package.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? DatabaseName { get; set; }

    /// <summary>Target SQL Server version for the model.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("Sql90", "Sql100", "Sql110", "Sql120", "Sql130", "Sql140", "Sql150", "Sql160", "SqlAzure")]
    [PsStringCast]
    public string SqlServerVersion { get; set; } = "Sql160";

    /// <summary>File filter applied when enumerating scripts.</summary>
    [Parameter(Position = 6)]
    [PsStringCast]
    public string Filter { get; set; } = "*.sql";

    /// <summary>Recurse into subdirectories when enumerating scripts.</summary>
    [Parameter]
    public SwitchParameter Recursive { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The resolved -Path, computed once in begin and read throughout process (opaque to C#).
    private Hashtable? _beginState;
    // A begin guard failure silences process entirely.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Path, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaDacPackageBegin"))
            {
                if (sentinel["__newDbaDacPackageBegin"] is Hashtable state)
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

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            Path, OutputPath, DacVersion, DacDescription, DatabaseName, SqlServerVersion, Filter,
            Recursive.ToBool(), EnableException.ToBool(), _beginState, this,
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
}
