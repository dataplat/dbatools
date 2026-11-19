#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Validates a JSON data-generation configuration file. Port of
/// public/Test-DbaDbDataGeneratorConfig.ps1; the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// The source's begin and process blocks are folded into ONE hop invocation rather than two.
/// -FilePath is not a pipeline parameter and there is no other pipeline input, so the process
/// block runs exactly once per invocation; running begin and process together in a single
/// scriptblock is therefore indistinguishable from running them as separate blocks, and it keeps
/// the four begin-block locals the process body reads ($json, $supportedDataTypes,
/// $randomizerTypes, $requiredColumnProperties) alive without a state sentinel.
///
/// Folding also preserves the source's early-exit behaviour. Two of the three begin-block
/// Stop-Function calls are followed by "return"; a bare return exits the folded scriptblock, which
/// matches the function world, where begin returned and the process block then bailed out at its
/// Test-FunctionInterrupt guard. Either way nothing is emitted. The third Stop-Function - the
/// "Could not parse masking config file" one - deliberately has NO return, so the body falls
/// through to the "-not $json.Type" check with $json unset and stops there; that sequence ships
/// verbatim and behaves identically folded.
///
/// No local needs a cross-record carry: every process-block local ($table, $column,
/// $columnProperties, $compareResult) is assigned and read inside the same loop iteration.
///
/// The hop streams rather than buffers. The validation loop emits one object per problem found,
/// and a caller can legitimately stop early (piping to Select-Object -First 1 to ask only whether
/// the file has any error at all); a buffered invocation would run the whole file before the first
/// object reached the pipeline.
///
/// $EnableException is passed into the hop because Stop-Function's own parameter block defaults it
/// from the caller's scope ($EnableException = $EnableException), so it has to be resolvable there
/// for the "nice by default" warning-vs-throw behaviour to survive the hop. Every in-hop
/// Stop-Function carries -FunctionName because Stop-Function derives the reporting command from
/// Get-PSCallStack, which yields a scriptblock rather than a command name inside a hop.
///
/// The source declares plain [cmdletbinding()], so this cmdlet does NOT declare
/// SupportsShouldProcess. The .PARAMETER WhatIf and .PARAMETER Confirm blocks in the source's
/// comment-based help are vestigial - the function never gated anything and never accepted those
/// switches, and adding them here would widen the parameter surface.
///
/// Get-DbaRandomizedType is itself already a satellite cmdlet rather than a script function; it
/// resolves from inside the module scope hop, which is where the source called it.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaDbDataGeneratorConfig")]
public sealed class TestDbaDbDataGeneratorConfigCommand : DbaBaseCmdlet
{
    /// <summary>Path to the JSON configuration file to validate.</summary>
    // Position = 0 is required for parity, not decoration: a PowerShell advanced function gets
    // implicit positional binding, so the script function bound -FilePath positionally. A compiled
    // cmdlet infers no position, so omitting this would reject the documented
    // "Test-DbaDbDataGeneratorConfig C:\temp\db1.json" call the .EXAMPLE shows.
    [Parameter(Mandatory = true, Position = 0)]
    [PsStringCast]
    public string? FilePath { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BodyScript,
            FilePath, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source's begin and process bodies VERBATIM, in that order. Substitutions only:
    // -FunctionName Test-DbaDbDataGeneratorConfig on every Stop-Function.
    private const string BodyScript = """
param($FilePath, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$FilePath, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not (Test-Path -Path $FilePath)) {
        Stop-Function -Message "Could not find masking config file $FilePath" -Target $FilePath -FunctionName Test-DbaDbDataGeneratorConfig
        return
    }

    # Get all the items that should be processed
    try {
        $json = Get-Content -Path $FilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Stop-Function -Message "Could not parse masking config file" -ErrorRecord $_ -Target $FilePath -FunctionName Test-DbaDbDataGeneratorConfig
    }

    if (-not $json.Type) {
        Stop-Function -Message "Configuration file does not contain a type. This is either an older configuration or an invalid one. Please make sure that the json file contains '`"Type`": `"DataGenerationConfiguration`", '" -Target $json.Type -FunctionName Test-DbaDbDataGeneratorConfig
        return
    }

    if ($json.Type -ne "DataGenerationConfiguration") {
        Stop-Function -Message "Configuration file is not a valid data generation configuration. Type found '$($json.Type)'" -Target $json.Type -FunctionName Test-DbaDbDataGeneratorConfig
        return
    }

    $supportedDataTypes = 'bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'money', 'nchar', 'ntext', 'nvarchar', 'smalldatetime', 'text', 'time', 'uniqueidentifier', 'userdefineddatatype', 'varchar'

    $randomizerTypes = Get-DbaRandomizedType

    $requiredColumnProperties = 'CharacterString', 'ColumnType', 'Composite', 'ForeignKey', 'Identity', 'MaskingType', 'MaxValue', 'MinValue', 'Name', 'Nullable', 'SubType'

    if (Test-FunctionInterrupt) { return }

    foreach ($table in $json.Tables) {

        foreach ($column in $table.Columns) {

            # Test the column properties
            $columnProperties = $column | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object Name -ExpandProperty Name
            $compareResult = Compare-Object -ReferenceObject $requiredColumnProperties -DifferenceObject $columnProperties

            if ($null -ne $compareResult) {
                if ($compareResult.SideIndicator -contains "<=") {
                    [PSCustomObject]@{
                        Table  = $table.Name
                        Column = $column.Name
                        Value  = ($compareResult | Where-Object SideIndicator -eq "<=").InputObject -join ","
                        Error  = "The column does not contain all the required properties. Please check the column "
                    }

                }

                if ($compareResult.SideIndicator -contains "=>") {
                    [PSCustomObject]@{
                        Table  = $table.Name
                        Column = $column.Name
                        Value  = ($compareResult | Where-Object SideIndicator -eq "=>").InputObject -join ","
                        Error  = "The column contains a property that is not in the required properties. Please check the column"
                    }
                }
            }

            # Test column type
            if ($column.ColumnType -notin $supportedDataTypes) {
                [PSCustomObject]@{
                    Table  = $table.Name
                    Column = $column.Name
                    Value  = $column.ColumnType
                    Error  = "ColumnType is not a supported data type "
                }
            }

            # Test masking type
            if ($column.MaskingType -notin $randomizerTypes.Type) {
                [PSCustomObject]@{
                    Table  = $table.Name
                    Column = $column.Name
                    Value  = $column.MaskingType
                    Error  = "MaskingType is not valid"
                }
            }

            # Test masking sub type
            if ($null -ne $column.SubType -and $column.SubType -notin $randomizerTypes.SubType) {
                [PSCustomObject]@{
                    Table  = $table.Name
                    Column = $column.Name
                    Value  = $column.SubType
                    Error  = "SubType is not valid"
                }
            }
        }
    }

} $FilePath $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
