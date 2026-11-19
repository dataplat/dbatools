#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Generates a data-generator configuration file describing the tables and columns to populate.
/// Port of public/New-DbaDbDataGeneratorConfig.ps1; the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// BEGIN+PROCESS, two hops. NO parameter is ValueFromPipeline, so process fires exactly once and the
/// cross-record carry axis does not exist for this row - stated rather than skipped, since a
/// parameter-only check is what let a destructive-path carry through on Move-DbaDbFile.
///
/// BEGIN CARRIES ONE VALUE. Begin loads the column-type catalogue from
/// $script:PSModuleRoot\bin\datamasking\columntypes.json into $columnTypes, which process reads once
/// when classifying a column; that single value rides the begin sentinel. Begin also creates or
/// validates -Path, which is a side effect rather than carried state.
///
/// INTERRUPT CARRY IS LIVE. The -Path guards are Stop-Function WITHOUT -Continue, so they set the
/// module interrupt, and process opens with "if (Test-FunctionInterrupt) { return }" - a begin
/// failure therefore produces no output. The column-types load uses -Continue instead, so a missing
/// catalogue does NOT interrupt; process runs on with $columnTypes unset, exactly as the source
/// does. Across separate hop invocations the flag does not survive, so the begin hop reads it at
/// Get-Variable -Scope 0 after its dot-sourced body and carries it, and C# skips process when begin
/// set it.
///
/// $InputObject is NOT a parameter of this command - the body does "$InputObject += Get-DbaDatabase
/// ..." against an undeclared variable, which PowerShell creates on first use. It rides verbatim;
/// because process runs once there is no record boundary for it to leak across (contrast
/// New-DbaDacProfile, where the same append pattern targets a real non-pipeline PARAMETER and does
/// carry).
///
/// The one $Pscmdlet.ShouldProcess gate, which wraps writing the JSON, routes to the real cmdlet via
/// $__realCmdlet. In-hop Stop-Function/Write-Message carry -FunctionName. Implicit positions are
/// made explicit; the four switches carry none.
///
/// GATE NOTE: this command reads its column-type catalogue from $script:PSModuleRoot\bin\datamasking,
/// so it belongs to the randomizer/datamasking CSV-path cluster whose gate is deferred until the
/// $script:PSModuleRoot-under-ManualPester product fix. Surface pinned by
/// migration/baselines/New-DbaDbDataGeneratorConfig.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDbDataGeneratorConfig", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaDbDataGeneratorConfigCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to describe.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Limit the configuration to these tables.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Table { get; set; }

    /// <summary>Reset identity columns when the generator runs.</summary>
    [Parameter]
    public SwitchParameter ResetIdentity { get; set; }

    /// <summary>Truncate the table before generating.</summary>
    [Parameter]
    public SwitchParameter TruncateTable { get; set; }

    /// <summary>Rows to generate per table.</summary>
    [Parameter(Position = 4)]
    public int Rows { get; set; } = 1000;

    /// <summary>Directory the configuration file is written to.</summary>
    [Parameter(Mandatory = true, Position = 5)]
    [PsStringCast]
    public string Path { get; set; } = null!;

    /// <summary>Create the output directory if it does not exist.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The column-type catalogue loaded once in begin (opaque to C#).
    private Hashtable? _beginState;
    // A failed -Path guard silences process.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaDbDataGeneratorConfigBegin"))
            {
                if (sentinel["__newDbaDbDataGeneratorConfigBegin"] is Hashtable state)
                {
                    _beginState = state;
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
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
        }, BeginScript,
            Path, Force.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _interrupted)
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
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, Table, ResetIdentity.ToBool(),
            TruncateTable.ToBool(), Rows, Path, Force.ToBool(), EnableException.ToBool(),
            _beginState, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM, dot-sourced. Edits: -FunctionName on the three calls. The
    // sentinel carries the column-type catalogue and the interrupt. Note the catalogue load uses
    // -Continue, so a missing file does NOT interrupt and $columnTypes is simply left unset - the
    // Assigned flag preserves that.
    private const string BeginScript = """
param($Path, $Force, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$Path, $Force, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {

        # Get all the different column types
        try {
            $columnTypes = Get-Content -Path "$script:PSModuleRoot\bin\datamasking\columntypes.json" | ConvertFrom-Json
        } catch {
            Stop-Function -Message "Something went wrong importing the column types" -Continue -FunctionName New-DbaDbDataGeneratorConfig
        }

        # Check if the Path is accessible
        if (-not (Test-Path -Path $Path)) {
            try {
                $null = New-Item -Path $Path -ItemType Directory -Force:$Force
            } catch {
                Stop-Function -Message "Could not create Path directory" -ErrorRecord $_ -Target $Path -FunctionName New-DbaDbDataGeneratorConfig
            }
        } else {
            if ((Get-Item $path) -isnot [System.IO.DirectoryInfo]) {
                Stop-Function -Message "$Path is not a directory" -FunctionName New-DbaDbDataGeneratorConfig
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    $__ct = Get-Variable -Name columnTypes -Scope 0 -ErrorAction Ignore
    @{ __newDbaDbDataGeneratorConfigBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value); ColumnTypesAssigned = [bool]$__ct; ColumnTypes = $(if ($__ct) { $__ct.Value }) } }
} $Path $Force $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM, dot-sourced so its early returns exit only the body. Edits:
    // the one $Pscmdlet gate routes to $__realCmdlet and -FunctionName is stamped on the 12 direct
    // Stop-Function/Write-Message calls. $columnTypes restores from the begin sentinel only when
    // begin actually assigned it, so a failed catalogue load leaves it unset here too.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Table, $ResetIdentity, $TruncateTable, $Rows, $Path, $Force, $EnableException, $__beginState, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Table, $ResetIdentity, $TruncateTable, [int]$Rows, [string]$Path, $Force, $EnableException, $__beginState, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # the column-type catalogue begin loaded (unset if its -Continue load failed, as in the source)
    if ($__beginState.ColumnTypesAssigned) { $columnTypes = $__beginState.ColumnTypes }

    . {
        if (Test-FunctionInterrupt) {
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        $results = @()

        if ($InputObject.Count -lt 1) {
            Stop-Function -Message "No databases found" -Target $Database -FunctionName New-DbaDbDataGeneratorConfig
            return
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            $tables = @()

            # Get the tables
            if ($Table) {
                $tablecollection = $db | Get-DbaDbTable -Table $Table
            } else {
                $tablecollection = $db.Tables
            }

            if ($tablecollection.Count -lt 1) {
                Stop-Function -Message "The database does not contain any tables" -Target $db -Continue -FunctionName New-DbaDbDataGeneratorConfig
            }

            # Loop through the tables
            foreach ($tableobject in $tablecollection) {
                Write-Message -Message "Processing table $($tableobject.Name)" -Level Verbose -FunctionName New-DbaDbDataGeneratorConfig -ModuleName "dbatools"

                $hasUniqueIndex = $false

                if ($tableobject.Indexes.IsUnique) {
                    $hasUniqueIndex = $true
                }

                $columns = @()

                # Get the columns
                [array]$columncollection = $tableobject.Columns

                foreach ($columnobject in $columncollection) {
                    if ($columnobject.Computed) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a computed column" -FunctionName New-DbaDbDataGeneratorConfig -ModuleName "dbatools"
                        continue
                    }
                    if ($columnobject.DataType.Name -eq 'hierarchyid') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a hierarchyid column" -FunctionName New-DbaDbDataGeneratorConfig -ModuleName "dbatools"
                        continue
                    }
                    if ($columnobject.DataType.Name -eq 'geography') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a geography column" -FunctionName New-DbaDbDataGeneratorConfig -ModuleName "dbatools"
                        continue
                    }
                    if ($columnobject.DataType.Name -eq 'geometry') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a geometry column" -FunctionName New-DbaDbDataGeneratorConfig -ModuleName "dbatools"
                        continue
                    }
                    if ($columnobject.DataType.SqlDataType.ToString().ToLowerInvariant() -eq 'xml') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a xml column" -FunctionName New-DbaDbDataGeneratorConfig -ModuleName "dbatools"
                        continue
                    }

                    $dataGenType = $min = $null
                    $columnLength = $columnobject.Datatype.MaximumLength
                    $columnType = $columnobject.DataType.SqlDataType.ToString().ToLowerInvariant()

                    if (-not $columnType) {
                        $columnType = $columnobject.DataType.Name.ToLowerInvariant()
                    }

                    # Get the masking type with the synonym
                    $dataGenType = $columnTypes | Where-Object {
                        $columnobject.Name -in $_.Synonym
                    }

                    if ($dataGenType) {
                        $columns += [PSCustomObject]@{
                            Name            = $columnobject.Name
                            ColumnType      = $columnType
                            CharacterString = $null
                            MinValue        = $min
                            MaxValue        = $columnLength
                            MaskingType     = $dataGenType.MaskingType
                            SubType         = $dataGenType.SubType
                            Identity        = $columnobject.Identity
                            ForeignKey      = $columnobject.IsForeignKey
                            Composite       = $false
                            Nullable        = $columnobject.Nullable
                        }

                    } else {
                        $type = "Random"

                        switch ($columnType) {
                            { $_ -in "bit", "bool" } {
                                $subType = "Bool"
                                $MaxValue = $null
                            }
                            "bigint" {
                                $subType = "Number"
                                $MaxValue = 9223372036854775807
                            }
                            "int" {
                                $subType = "Number"
                                $MaxValue = 2147483647
                            }
                            "date" {
                                $type = "Date"
                                $subType = "Past"
                                $MaxValue = $null
                            }
                            "datetime" {
                                $type = "Date"
                                $subType = "Past"
                                $MaxValue = $null
                            }
                            "datetime2" {
                                $type = "Date"
                                $subType = "Past"
                                $MaxValue = $null
                            }
                            "float" {
                                $subType = "Float"
                                $MaxValue = $null
                            }
                            "smallint" {
                                $subType = "Number"
                                $MaxValue = 32767
                            }
                            "smalldatetime" {
                                $subType = "Date"
                                $MaxValue = $null
                            }
                            "tinyint" {
                                $subType = "Number"
                                $MaxValue = 255
                            }
                            "varbinary" {
                                $subType = "Byte"
                                $MaxValue = $columnLength
                            }
                            "varbinary" {
                                $subType = "Byte"
                                $MaxValue = $columnLength
                            }
                            "userdefineddatatype" {
                                if ($columnLength -eq 1) {
                                    $subType = "Bool"
                                    $MaxValue = $columnLength
                                } else {
                                    $subType = "String"
                                    $MaxValue = $columnLength
                                }
                            }
                            default {
                                $subType = "String"
                                $MaxValue = $columnLength
                            }
                        }

                        $columns += [PSCustomObject]@{
                            Name            = $columnobject.Name
                            ColumnType      = $columnType
                            CharacterString = $null
                            MinValue        = $min
                            MaxValue        = $MaxValue
                            MaskingType     = $type
                            SubType         = $subType
                            Identity        = $columnobject.Identity
                            ForeignKey      = $columnobject.IsForeignKey
                            Composite       = $false
                            Nullable        = $columnobject.Nullable
                        }
                    }
                }


                # Check if something needs to be generated
                if ($columns) {
                    $tables += [PSCustomObject]@{
                        Name           = $tableobject.Name
                        Schema         = $tableobject.Schema
                        Columns        = $columns
                        ResetIdentity  = [bool]$ResetIdentity
                        TruncateTable  = [bool]$TruncateTable
                        HasUniqueIndex = [bool]$hasUniqueIndex
                        Rows           = $Rows
                    }
                } else {
                    Write-Message -Message "No columns match for data generation in table $($tableobject.Name)" -Level Verbose -FunctionName New-DbaDbDataGeneratorConfig -ModuleName "dbatools"
                }
            }

            # Check if something needs to be generated
            if ($tables) {
                $results += [PSCustomObject]@{
                    Name   = $db.Name
                    Type   = "DataGenerationConfiguration"
                    Tables = $tables
                }
            } else {
                Write-Message -Message "No columns match for data generation in table $($tableobject.Name)" -Level Verbose -FunctionName New-DbaDbDataGeneratorConfig -ModuleName "dbatools"
            }
        }

        # Write the data to the Path
        if ($results) {
            try {
                $temppath = "$Path\$($server.Name.Replace('\', '$')).$($db.Name).DataGeneratorConfig.json"
                if (-not $script:isWindows) {
                    $temppath = $temppath.Replace("\", "/")
                }
                if ($__realCmdlet.ShouldProcess("$temppath", "Saving results to json")) {
                    Set-Content -Path $temppath -Value ($results | ConvertTo-Json -Depth 5)
                    Get-ChildItem -Path $temppath
                }
            } catch {
                Stop-Function -Message "Something went wrong writing the results to the Path" -Target $Path -Continue -ErrorRecord $_ -FunctionName New-DbaDbDataGeneratorConfig
            }
        } else {
            Write-Message -Message "No tables to save for database $($db.Name) on $($server.Name)" -Level Verbose -FunctionName New-DbaDbDataGeneratorConfig -ModuleName "dbatools"
        }
    }
} $SqlInstance $SqlCredential $Database $Table $ResetIdentity $TruncateTable $Rows $Path $Force $EnableException $__beginState $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
