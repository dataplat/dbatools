#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Finds database tables containing binary columns (binary/varbinary/image) and annotates each with
/// BinaryColumn and FileNameColumn note-properties for downstream file extraction. Port of
/// public/Get-DbaBinaryFileTable.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port (InputObject is ValueFromPipeline, so process fires per record; when called with
/// -SqlInstance and nothing piped, process fires once with a null InputObject and gathers tables via
/// Get-DbaDbTable). There is no begin/end and no accumulator - the only cross-record state is the
/// Stop-Function interrupt. The source process body opens with `if (Test-FunctionInterrupt) { return }`
/// and, when it cannot gather tables, runs `Stop-Function ...; return` (no -Continue), which sets the
/// function-scope interrupt latch. A hop scope cannot carry that latch across records, so the body is
/// DOT-SOURCED (its two early returns exit only the body while the sentinel still emits), after which
/// Get-Variable -Scope 0 detects whether this record set the latch and the hop re-emits it; C# stores
/// _processInterrupted and gates ProcessRecord on it, so a failed record silences later records exactly as
/// the source's Test-FunctionInterrupt guard does. Body edits: -FunctionName Get-DbaBinaryFileTable on the
/// one Stop-Function and three Write-Message; Test-FunctionInterrupt is left verbatim. No ShouldProcess.
/// Surface pinned by migration/baselines/Get-DbaBinaryFileTable.json (positions 0-5, no sets, no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaBinaryFileTable")]
public sealed class GetDbaBinaryFileTableCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to search.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The table(s) to search.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Table { get; set; }

    /// <summary>The schema(s) to search.</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Schema { get; set; }

    /// <summary>Table object(s) to annotate, piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.Smo.Table[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Whether a process record's Stop-Function (no -Continue) set the interrupt latch, which silences
    // later records - carried record-to-record via the process sentinel.
    private bool _processInterrupted;

    protected override void ProcessRecord()
    {
        if (Interrupted || _processInterrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, SqlCredential, Database, Table, Schema, InputObject, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__getDbaBinaryFileTableProcess"))
            {
                if (sentinel["__getDbaBinaryFileTableProcess"] is Hashtable state)
                {
                    _processInterrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
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
    // PS: the process block, DOT-SOURCED so its two early returns (the Test-FunctionInterrupt guard and
    // the Stop-Function+return) exit only the body while the sentinel still emits. Edits: -FunctionName on
    // the one Stop-Function and three Write-Message. After the body, Get-Variable -Scope 0 detects whether
    // this record set the interrupt latch and the hop re-emits it for the C# _processInterrupted gate.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Table, $Schema, $InputObject, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Table, [string[]]$Schema, [Microsoft.SqlServer.Management.Smo.Table[]]$InputObject, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject) {
            try {
                $InputObject = Get-DbaDbTable -SqlInstance $SqlInstance -Database $Database -Table $Table -Schema $Schema -SqlCredential $SqlCredential -EnableException
            } catch {
                Stop-Function -Message "Failed to get tables" -ErrorRecord $PSItem -FunctionName Get-DbaBinaryFileTable
                return
            }
        }

        Write-Message -Level Verbose -Message "Found $($InputObject.count) tables" -FunctionName Get-DbaBinaryFileTable -ModuleName "dbatools"
        foreach ($tbl in $InputObject) {
            $server = $tbl.Parent.Parent
            $BinaryColumn = ($tbl.Columns | Where-Object { $PSItem.DataType.Name -match "binary" -or $PSItem.DataType.Name -eq "image" }).Name
            $FileNameColumn = ($tbl.Columns | Where-Object Name -Match Name).Name
            if ($FileNameColumn.Count -gt 1) {
                Write-Message -Level Verbose -Message "Multiple column names match the phrase 'name' in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name). Please specify the column to use with -FileNameColumn" -FunctionName Get-DbaBinaryFileTable -ModuleName "dbatools"
            }
            if ($BinaryColumn.Count -gt 1) {
                Write-Message -Level Verbose -Message "Multiple columns have a binary datatype in $($tbl.Name) in $($tbl.Parent.Name) on $($server.Name)." -FunctionName Get-DbaBinaryFileTable -ModuleName "dbatools"
            }
            if ($BinaryColumn) {
                $tbl | Add-Member -NotePropertyName BinaryColumn -NotePropertyValue $BinaryColumn
                $tbl | Add-Member -NotePropertyName FileNameColumn -NotePropertyValue $FileNameColumn -PassThru | Select-DefaultView -Property "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "BinaryColumn", "FileNameColumn"
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __getDbaBinaryFileTableProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $SqlCredential $Database $Table $Schema $InputObject $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
