#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Validates a JSON data-masking configuration file. Port of
/// public/Test-DbaDbDataMaskingConfig.ps1; the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// The source's begin and process blocks are folded into ONE hop invocation rather than two.
/// -FilePath is not a pipeline parameter and there is no other pipeline input, so the process
/// block runs exactly once per invocation; running begin and process together in a single
/// scriptblock is therefore indistinguishable from running them as separate blocks, and it keeps
/// the eleven begin-block collections the process body reads alive without a state sentinel.
///
/// Folding also preserves the source's early-exit behaviour. Three of the four begin-block
/// Stop-Function calls are followed by "return"; a bare return exits the folded scriptblock, which
/// matches the function world, where begin returned and the process block then bailed out at its
/// Test-FunctionInterrupt guard. The fourth - the ConvertFrom-Json catch - deliberately has NO
/// return, so the body falls through to the "-not $json.Type" check with $json unset and stops
/// there; that sequence ships verbatim and behaves identically folded.
///
/// The interrupt guard survives folding: Stop-Function signals a graceful stop by writing its
/// interrupt variable with Set-Variable -Scope 1 and Test-FunctionInterrupt reads it with
/// Get-Variable -Scope 1, so in a folded block both address the same scriptblock scope.
///
/// No local needs a cross-record carry: every process-block local ($table, $column,
/// $columnProperties, $compareResultRequired, $compareResultAllowed, $actionProperties,
/// $compareResult) is assigned and read inside the same loop iteration.
///
/// The hop streams rather than buffers. The validation loop emits one object per problem found,
/// and a caller can legitimately stop early (piping to Select-Object -First 1 to ask only whether
/// the file has any error at all); a buffered invocation would validate the whole file before the
/// first object reached the pipeline.
///
/// $EnableException is passed into the hop because Stop-Function's own parameter block defaults it
/// from the caller's scope ($EnableException = $EnableException), so it has to be resolvable there
/// for the "nice by default" warning-vs-throw behaviour to survive the hop. Every in-hop
/// Stop-Function carries -FunctionName because Stop-Function derives the reporting command from
/// Get-PSCallStack, which yields a scriptblock rather than a command name inside a hop.
///
/// The source declares plain [CmdletBinding()], so this cmdlet does NOT declare
/// SupportsShouldProcess. The .PARAMETER WhatIf and .PARAMETER Confirm blocks in the source's
/// comment-based help are vestigial - the function never gated anything and never accepted those
/// switches, and adding them here would widen the parameter surface.
///
/// Two source quirks ship unchanged rather than tidied, because parity is the contract: the
/// "between" sub-type checks call [datetime]::TryParse with a string literal in the [ref]
/// position, and one branch reads $Column.SubType with different casing than its neighbours
/// (harmless in PowerShell, which is case-insensitive).
///
/// Get-DbaRandomizedType is itself already a satellite cmdlet rather than a script function; it
/// resolves from inside the module scope hop, which is where the source called it.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaDbDataMaskingConfig")]
[OutputType(typeof(PSObject))]
public sealed class TestDbaDbDataMaskingConfigCommand : DbaBaseCmdlet
{
    /// <summary>Path to the JSON masking configuration file to validate.</summary>
    // Position = 0 is required for parity, not decoration: a PowerShell advanced function gets
    // implicit positional binding, so the script function bound -FilePath positionally. A compiled
    // cmdlet infers no position, so omitting this would reject the documented
    // "Test-DbaDbDataMaskingConfig C:\temp\db1.json" call the .EXAMPLE shows.
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
    // -FunctionName Test-DbaDbDataMaskingConfig on every Stop-Function.
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
            Stop-Function -Message "Could not find masking config file $FilePath" -Target $FilePath -FunctionName Test-DbaDbDataMaskingConfig
            return
        }

        # Get all the items that should be processed
        try {
            $json = Get-Content -Path $FilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Stop-Function -Message "Could not parse masking config file" -ErrorRecord $_ -Target $FilePath -FunctionName Test-DbaDbDataMaskingConfig
        }

        if (-not $json.Type) {
            Stop-Function -Message "Configuration file does not contain a type. This is either an older configuration or an invalid one. Please make sure that the json file contains '`"Type`": `"DataMaskingConfiguration`", '" -Target $json.Type -FunctionName Test-DbaDbDataMaskingConfig
            return
        }

        if ($json.Type -ne "DataMaskingConfiguration") {
            Stop-Function -Message "Configuration file is not a valid masking configuration. Type found '$($json.Type)'" -Target $json.Type -FunctionName Test-DbaDbDataMaskingConfig
            return
        }

        $supportedDataTypes = @('bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'float', 'int', 'money', 'nchar', 'ntext', 'nvarchar', 'smalldatetime', 'smallint', 'text', 'time', 'tinyint', 'uniqueidentifier', 'userdefineddatatype', 'varchar')

        $randomizerTypes = Get-DbaRandomizedType

        $requiredColumnProperties = @('Action', 'CharacterString', 'ColumnType', 'Composite', 'Deterministic', 'Format', 'MaskingType', 'MaxValue', 'MinValue', 'Name', 'Nullable', 'KeepNull', 'SubType')
        $allowedColumnProperties = @('Action', 'CharacterString', 'ColumnType', 'Composite', 'Deterministic', 'Format', 'MaskingType', 'MaxValue', 'MinValue', 'Name', 'Nullable', 'KeepNull', 'Separator', 'SubType', 'StaticValue')

        $allowedActionCategories = @('datetime', 'number', 'column')
        $allowedActionSubCategories = @('year', 'quarter', 'month', 'dayofyear', 'day', 'week', 'weekday', 'hour', 'minute', 'second', 'millisecond', 'microsecond', 'nanosecond')
        $allowedActionTypes = @('Add', 'Divide', 'Multiply', 'Nullify', 'Set', 'Subtract')

        $allowedDateTimeTypes = @('date', 'datetime', 'datetime2', 'smalldatetime', 'time')
        $allowedNumberTypes = @('bigint', 'bit', 'decimal', 'float', 'int', 'money', 'numeric', 'smallint')

        $requiredDateTimeActionProperties = @('Category', 'Subcategory', 'Type', 'Value')
        $requiredNumberActionProperties = @('Category', 'Type', 'Value')

        if (Test-FunctionInterrupt) { return }

        foreach ($table in $json.Tables) {

            foreach ($column in $table.Columns) {

                # Test the column properties
                $columnProperties = $column | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object Name -ExpandProperty Name
                $compareResultRequired = Compare-Object -ReferenceObject $requiredColumnProperties -DifferenceObject $columnProperties
                $compareResultAllowed = Compare-Object -ReferenceObject $allowedColumnProperties -DifferenceObject $columnProperties

                if ($null -ne $compareResultRequired) {
                    if ($compareResultRequired.SideIndicator -contains "<=") {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = ($compareResultRequired | Where-Object SideIndicator -eq "<=").InputObject -join ","
                            Error  = "The column does not contain all the required properties. Please check the column "
                        }
                    }
                }

                if ($null -ne $compareResultAllowed) {
                    if ($compareResultAllowed.SideIndicator -contains "=>") {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = ($compareResultAllowed | Where-Object SideIndicator -eq "=>").InputObject -join ","
                            Error  = "The column contains a property that is not in the allowed properties. Please check the column"
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

                # Test date types
                if ($column.ColumnType.ToLower() -eq 'date') {

                    if ($column.MaskingType -ne 'Date' -and ($column.SubType -ne 'DateOfBirth' -and $null -ne $column.Subtype)) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.MaskingType
                            Error  = "MaskingType should be date when ColumnType is 'date'"
                        }
                    }

                    if ($null -ne $Column.SubType -and $Column.SubType.ToLower() -eq 'between') {

                        if (-not ($null -eq $column.MinValue) -and -not ([datetime]::TryParse($column.MinValue, [ref]"2002-12-31"))) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.MinValue
                                Error  = "The value for MinValue is not a valid date"
                            }
                        }

                        if (-not ($null -eq $column.MaxValue) -and -not ([datetime]::TryParse($column.MaxValue, [ref]"2002-12-31"))) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.MaxValue
                                Error  = "The value for MaxValue is not a valid date"
                            }
                        }

                        if ($null -eq $column.MinValue) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = 'null'
                                Error  = "The value for MinValue cannot be 'null' when using sub type 'Between'"
                            }
                        }

                        if ($null -eq $column.MaxValue) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = 'null'
                                Error  = "The value for MaxValue cannot be 'null' when using sub type 'Between'"
                            }
                        }
                    }
                }

                # Test actions
                if ($column.Action) {
                    # General checks

                    if ($null -ne $column.Action.Category -and $column.Action.Category -notin $allowedActionCategories) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.Action.Category
                            Error  = "The action category '$($column.Action.Category)' is not allowed"
                        }
                    }

                    if ($null -ne $column.Action.Category -and $column.Action.Type -notin $allowedActionTypes) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.Action.Category
                            Error  = "The action type '$($column.Action.Type)' is not allowed"
                        }
                    }

                    if ($column.Action.Category -ne 'Column' -and $column.Action.Type -ne 'Nullify' -and $null -eq $column.Action.Value -and $column.Action.Type -in $allowedActionTypes) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.Action.Category
                            Error  = "The action value cannot be empty"
                        }
                    }

                    if (-not $null -eq $column.Action.SubCategory -and $column.Action.SubCategory -notin $allowedActionSubCategories) {
                        [PSCustomObject]@{
                            Table  = $table.Name
                            Column = $column.Name
                            Value  = $column.Action.Category
                            Error  = "The action subcategory cannot be empty"
                        }
                    }

                    $actionProperties = $column.Action | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object Name -ExpandProperty Name

                    # Date checks
                    if ($column.Action.Category -eq 'datetime' ) {

                        $compareResult = Compare-Object -ReferenceObject $requiredDateTimeActionProperties -DifferenceObject $actionProperties

                        if ($null -ne $compareResult) {
                            if ($compareResult.SideIndicator -contains "<=") {
                                [PSCustomObject]@{
                                    Table  = $table.Name
                                    Column = $column.Name
                                    Value  = ($compareResult | Where-Object SideIndicator -eq "<=").InputObject -join ","
                                    Error  = "The action does not contain all the required properties. Please check the action "
                                }
                            }

                            if ($compareResult.SideIndicator -contains "=>") {
                                [PSCustomObject]@{
                                    Table  = $table.Name
                                    Column = $column.Name
                                    Value  = ($compareResult | Where-Object SideIndicator -eq "=>").InputObject -join ","
                                    Error  = "The action contains a property that is not in the required properties. Please check the column"
                                }
                            }
                        }

                        if ($column.ColumnType -notin $allowedDateTimeTypes) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.Action.Category
                                Error  = "The category is not valid with data type $($column.ColumnType)"
                            }
                        }
                    }

                    # Number checks
                    if ($column.Action.Category -eq 'number' ) {
                        $compareResult = Compare-Object -ReferenceObject $requiredNumberActionProperties -DifferenceObject $actionProperties

                        if ($null -ne $compareResult) {
                            if ($compareResult.SideIndicator -contains "<=") {
                                [PSCustomObject]@{
                                    Table  = $table.Name
                                    Column = $column.Name
                                    Value  = ($compareResult | Where-Object SideIndicator -eq "<=").InputObject -join ","
                                    Error  = "The action does not contain all the required properties. Please check the action "
                                }
                            }
                        }

                        if ($column.ColumnType -notin $allowedNumberTypes) {
                            [PSCustomObject]@{
                                Table  = $table.Name
                                Column = $column.Name
                                Value  = $column.Action.Category
                                Error  = "The category is not valid with data type $($column.ColumnType)"
                            }
                        }
                    }
                } # End column action
            } # End for each column
        } # End for each table

} $FilePath $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
