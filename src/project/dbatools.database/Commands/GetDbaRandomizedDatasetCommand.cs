#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Generates randomized datasets from templates. Port of public/Get-DbaRandomizedDataset.ps1;
/// the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port (InputObject is ValueFromPipeline). THE KEY POINT: the process block OPENS with
/// if (Test-FunctionInterrupt) { return } and its template-parse catch fires Stop-Function (NO -Continue) + return
/// (source ~147/148), which sets the function-terminating interrupt. In the source (shared function scope) that
/// interrupt persists ACROSS pipeline records, so a parse failure on one record stops all subsequent records. The
/// hop runs each record in a fresh scope, so the process interrupt is CARRIED ACROSS RECORDS: the process body is
/// DOT-SOURCED, then the module interrupt variable is captured (Get-Variable -Scope 0) and emitted; the C# field
/// _processInterrupted (which PERSISTS across ProcessRecord calls) gates ProcessRecord (replicating line 120). The
/// verbatim Test-FunctionInterrupt line stays in the body but is inert in the fresh per-record scope - the real
/// cross-record gate is _processInterrupted. The other three Stop-Function carry -Continue (which do NOT set the
/// interrupt). The neither-input guard is truthiness (no Test-Bound). Rows (int, default 100) and Locale (string,
/// default 'en') are reproduced via compiled property initializers. No value-passed switch, no ShouldProcess. Edits:
/// -FunctionName Get-DbaRandomizedDataset on the four Stop-Function. Surface pinned by
/// migration/baselines/Get-DbaRandomizedDataset.json (positions 0-4, InputObject VFP pos4, no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaRandomizedDataset")]
public sealed class GetDbaRandomizedDatasetCommand : DbaBaseCmdlet
{
    /// <summary>The randomized dataset template name(s).</summary>
    [Parameter(Position = 0)]
    public string[]? Template { get; set; }

    /// <summary>The path(s) to template file(s).</summary>
    [Parameter(Position = 1)]
    public string[]? TemplateFile { get; set; }

    /// <summary>How many rows to generate (default 100).</summary>
    [Parameter(Position = 2)]
    public int Rows { get; set; } = 100;

    /// <summary>The locale used for value generation (default 'en').</summary>
    [Parameter(Position = 3)]
    public string Locale { get; set; } = "en";

    /// <summary>Template object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Carried ACROSS records: the process interrupt (a Stop-Function without -Continue stops subsequent records).
    private bool _processInterrupted;

    protected override void ProcessRecord()
    {
        // Replicates the source process block's opening if (Test-FunctionInterrupt) { return } across records.
        if (Interrupted || _processInterrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__rdsProcess"))
            {
                if (sentinel["__rdsProcess"] is Hashtable state)
                {
                    _processInterrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
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
            Template, TemplateFile, Rows, Locale, InputObject, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
    // PS: the process block VERBATIM (DOT-SOURCED so the parse-failure Stop-Function+return still lets the interrupt
    // sentinel emit). Captures the process interrupt (Get-Variable -Scope 0) and carries it across records via the C#
    // _processInterrupted field. Edits: -FunctionName Get-DbaRandomizedDataset on the four Stop-Function.
    private const string ProcessScript = """
param($Template, $TemplateFile, $Rows, $Locale, $InputObject, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string[]]$Template, [string[]]$TemplateFile, [int]$Rows, [string]$Locale, [object[]]$InputObject, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    . {
        foreach ($__continueGuard in @(1)) {
        if (Test-FunctionInterrupt) { return }

        $supportedDataTypes = 'bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'float', 'guid', 'money', 'numeric', 'nchar', 'ntext', 'nvarchar', 'real', 'smalldatetime', 'smallint', 'text', 'time', 'tinyint', 'uniqueidentifier', 'userdefineddatatype', 'varchar'

        # Check variables
        if (-not $InputObject -and -not $Template -and -not $TemplateFile) {
            Stop-Function -Message "Please enter a template or assign a template file" -Continue -FunctionName Get-DbaRandomizedDataset
        }

        $templates = @()

        # Get all thee templates
        if ($Template) {
            $templates += Get-DbaRandomizedDatasetTemplate -Template $Template

            if ($templates.Count -lt 1) {
                Stop-Function -Message "Could not find any templates" -Continue -FunctionName Get-DbaRandomizedDataset
            }

            $InputObject += $templates
        }

        foreach ($file in $InputObject) {
            # Get all the items that should be processed
            try {
                $templateSet = Get-Content -Path $file.FullName -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Could not parse template file" -ErrorRecord $_ -Target $TemplateFile -FunctionName Get-DbaRandomizedDataset
                return
            }

            # Generate the rows
            for ($i = 1; $i -le $Rows; $i++) {
                $row = New-Object PSCustomObject

                foreach ($column in $templateSet.Columns) {
                    try {
                        if ($column.SubType -in $supportedDataTypes) {
                            $value = Get-DbaRandomizedValue -DataType $column.SubType -Locale $Locale -EnableException
                        } else {
                            $value = Get-DbaRandomizedValue -RandomizerType $column.Type -RandomizerSubtype $column.SubType -Locale $Locale -EnableException
                        }

                        $row | Add-Member -Name $column.Name -Type NoteProperty -Value $value
                    } catch {
                        Stop-Function -Message "Could not generate a randomized value.`n$_" -ErrorRecord $_ -Continue -FunctionName Get-DbaRandomizedDataset
                    }
                }

                $row

            }
        }

        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __rdsProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $Template $TemplateFile $Rows $Locale $InputObject $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
