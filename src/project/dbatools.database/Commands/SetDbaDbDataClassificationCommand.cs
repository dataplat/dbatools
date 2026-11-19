#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Adds or updates data classification extended properties on table columns. Port of
/// public/Set-DbaDbDataClassification.ps1; the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// A begin/process port. The begin block does three things, and only the first stays put:
///   1. Builds two static GUID maps ($informationTypeMap, $sensitivityLabelMap) - begin-local,
///      because their ONLY consumer is the resolution immediately below them.
///   2. Resolves $InformationTypeId / $SensitivityLabelId from those maps when the caller named a
///      well-known type/label but supplied no explicit GUID. Process reads both resolved values
///      (lines 244/264/311/etc of the source), so they ride a begin STATE SENTINEL into the
///      process script, per the NewDbaAgentJobCommand exemplar. Carrying them - rather than
///      re-resolving per record - preserves the source's once-only begin semantics exactly.
///   3. Defines the helper function Invoke-UpsertExtendedProperty. This one had to MOVE.
///
/// The helper relocation is the whole risk of this row, and it is the W2-189 Add-TreeItem trap
/// again: the hop invokes begin and process as SEPARATE scoped calls, so a function defined in
/// begin's scope simply does not exist by the time process runs. Invoke-UpsertExtendedProperty is
/// defined in begin but called EIGHT times from process (source lines 240, 249, 260, 269, 307,
/// 316, 327, 336) - every one of them a call site that would fail as CommandNotFound. It is
/// therefore carried verbatim at the top of the ProcessScript instead. The move is safe because
/// the helper closes over NOTHING from begin: it reads only its own six parameters, so relocating
/// it changes no binding. It is redefined per record, which costs a function-definition and
/// nothing else.
///
/// ShouldProcess is real (baseline: supportsShouldProcess true, confirmImpact Medium), so both
/// $Pscmdlet.ShouldProcess(...) gates become $__realCmdlet.ShouldProcess(...) with the target and
/// action strings byte-for-byte, keeping -WhatIf and -Confirm identical.
///
/// NO continue-guard wrapper is needed. The body has seven `continue` statements and every one of
/// them - including both ShouldProcess gates - sits inside a genuine enclosing foreach (over
/// $Database at source line 220, over $InputObject at 281), so each continue has a real loop to
/// continue. That is the opposite of the guard-with-no-loop case that forces the wrapper. The two
/// `return`s are plain process-block returns, which a return inside the hop scriptblock
/// reproduces; the second one is load-bearing, ending the -SqlInstance branch so the InputObject
/// foreach does not also run.
///
/// There are ZERO Test-Bound calls in this body, so no bound-flag substitution is carried at all -
/// unusual for this descent and worth stating so a reader does not assume an omission.
///
/// Only other body edit is -FunctionName Set-DbaDbDataClassification on the six direct
/// Stop-Function sites. Note the first of them keeps its explicit -EnableException $EnableException
/// argument, which is carried rather than dropped.
///
/// Surface pinned by migration/baselines/Set-DbaDbDataClassification.json: SqlInstance 0,
/// SqlCredential 1, Database 2, Schema 3 (default "dbo"), Table 4, Column 5, InformationType 6,
/// InformationTypeId 7, SensitivityLabel 8, SensitivityLabelId 9, InputObject 10 ValueFromPipeline;
/// no parameter sets; outputType empty.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbDataClassification", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SetDbaDbDataClassificationCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The schema containing the target table.</summary>
    [Parameter(Position = 3)]
    public string Schema { get; set; } = "dbo";

    /// <summary>The table containing the target column.</summary>
    [Parameter(Position = 4)]
    public string? Table { get; set; }

    /// <summary>The column to classify.</summary>
    [Parameter(Position = 5)]
    public string? Column { get; set; }

    /// <summary>The information type name to apply.</summary>
    [Parameter(Position = 6)]
    public string? InformationType { get; set; }

    /// <summary>The information type GUID; resolved from the built-in map when omitted.</summary>
    [Parameter(Position = 7)]
    public string? InformationTypeId { get; set; }

    /// <summary>The sensitivity label name to apply.</summary>
    [Parameter(Position = 8)]
    public string? SensitivityLabel { get; set; }

    /// <summary>The sensitivity label GUID; resolved from the built-in map when omitted.</summary>
    [Parameter(Position = 9)]
    public string? SensitivityLabelId { get; set; }

    /// <summary>Classification object(s) piped in from Get-DbaDbDataClassification.</summary>
    [Parameter(ValueFromPipeline = true, Position = 10)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Begin-resolved IDs carried into the process script via the state sentinel. These start as the
    // caller-supplied values and are replaced by the map lookup only when begin actually resolved one.
    private object? _informationTypeId;
    private object? _sensitivityLabelId;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        _informationTypeId = InformationTypeId;
        _sensitivityLabelId = SensitivityLabelId;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__setDbaDbDataClassificationBegin"))
            {
                if (sentinel["__setDbaDbDataClassificationBegin"] is Hashtable state)
                {
                    _informationTypeId = state["InformationTypeId"];
                    _sensitivityLabelId = state["SensitivityLabelId"];
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
            InformationType, InformationTypeId, SensitivityLabel, SensitivityLabelId,
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

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
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, Schema, Table, Column,
            InformationType, _informationTypeId, SensitivityLabel, _sensitivityLabelId,
            InputObject, EnableException.ToBool(),
            this, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block's maps and ID resolution verbatim. The helper definition that also lived
    // here has moved to ProcessScript (see the class remarks). Edit: the trailing sentinel emit,
    // which hands the resolved IDs to the process script.
    private const string BeginScript = """
param($InformationType, $InformationTypeId, $SensitivityLabel, $SensitivityLabelId, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$InformationType, [string]$InformationTypeId, [string]$SensitivityLabel, [string]$SensitivityLabelId, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # Built-in GUID mappings for Microsoft Information Protection types
    $informationTypeMap = @{
        "Networking"    = "B40AD280-0F6A-6CA8-11BA-2F1A08651FCF"
        "Contact Info"  = "5C503E21-22C6-81FA-620B-F369B8EC38D1"
        "Credentials"   = "C64ABA7B-3A3E-95B6-535D-3BC535DA5A59"
        "Credit Card"   = "D22FA6E9-5EE4-3BDE-4C2B-A409604C4646"
        "Banking"       = "8A462631-4130-0A31-9A52-C6A9CA125F92"
        "Financial"     = "C44193E1-0E58-4B2A-9001-F7D6E7BC1373"
        "Other"         = "9C5B4809-0CCC-0637-6547-91A6F8BB609D"
        "Name"          = "57845286-7598-22F5-9659-15B24AEB125E"
        "National ID"   = "6F5A11A7-08B1-19C3-59E5-8C89CF4F8444"
        "SSN"           = "D936EC2C-04A4-9CF7-44C2-378A96456C61"
        "Health"        = "6E2C5B18-97CF-3073-27AB-F12F87493DA7"
        "Date Of Birth" = "3DE7CC52-710D-4E96-7E20-4D5188D2590C"
    }

    # Built-in GUID mappings for Microsoft Information Protection sensitivity labels
    $sensitivityLabelMap = @{
        "Public"                     = "1866CA45-1973-4C28-9D12-04D407F147AD"
        "General"                    = "684A0DB2-D514-49D8-8C0C-DF84A7B083EB"
        "Confidential"               = "331F0B13-76B5-2F1B-A77B-DEF5A73C73C2"
        "Confidential - GDPR"        = "989ADC05-3F3F-0588-A635-F475B994915B"
        "Highly Confidential"        = "B82CE05B-60A9-4CF3-8A8A-D6A0BB76E903"
        "Highly Confidential - GDPR" = "3302AE7F-B8AC-46BC-97F8-378828781EFD"
    }

    # Resolve IDs from built-in mappings when not explicitly provided
    if ($InformationType -and -not $InformationTypeId -and $informationTypeMap.ContainsKey($InformationType)) {
        $InformationTypeId = $informationTypeMap[$InformationType]
    }

    if ($SensitivityLabel -and -not $SensitivityLabelId -and $sensitivityLabelMap.ContainsKey($SensitivityLabel)) {
        $SensitivityLabelId = $sensitivityLabelMap[$SensitivityLabel]
    }

    # Hop mechanism, not source: hand the resolved IDs to the process script.
    @{ __setDbaDbDataClassificationBegin = @{ InformationTypeId = $InformationTypeId; SensitivityLabelId = $SensitivityLabelId } }
} $InformationType $InformationTypeId $SensitivityLabel $SensitivityLabelId $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block verbatim, preceded by the Invoke-UpsertExtendedProperty definition
    // relocated from begin (its eight call sites are all below). Edits: $Pscmdlet -> $__realCmdlet
    // on both ShouldProcess gates, and -FunctionName Set-DbaDbDataClassification on the six direct
    // Stop-Function sites.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Schema, $Table, $Column, $InformationType, $InformationTypeId, $SensitivityLabel, $SensitivityLabelId, $InputObject, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string]$Schema, [string]$Table, [string]$Column, [string]$InformationType, [string]$InformationTypeId, [string]$SensitivityLabel, [string]$SensitivityLabelId, [psobject[]]$InputObject, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # Upsert a single extended property on a column
    function Invoke-UpsertExtendedProperty {
        param (
            [Microsoft.SqlServer.Management.Smo.Database]$Db,
            [string]$PropName,
            [string]$PropValue,
            [string]$SchemaName,
            [string]$TableName,
            [string]$ColumnName
        )
        $escapedSchema   = $SchemaName.Replace("'", "''")
        $escapedTable    = $TableName.Replace("'", "''")
        $escapedColumn   = $ColumnName.Replace("'", "''")
        $escapedPropName = $PropName.Replace("'", "''")
        $escapedValue    = $PropValue.Replace("'", "''")

        $checkSql = "
SELECT COUNT(1) AS PropExists
FROM sys.extended_properties ep
INNER JOIN sys.objects o ON ep.major_id = o.object_id
INNER JOIN sys.columns c ON o.object_id = c.object_id AND ep.minor_id = c.column_id
WHERE SCHEMA_NAME(o.schema_id) = '$escapedSchema'
  AND o.name = '$escapedTable'
  AND c.name = '$escapedColumn'
  AND ep.name = '$escapedPropName'
  AND ep.class = 1"

        $exists = $Db.Query($checkSql).PropExists

        if ($exists -gt 0) {
            $Db.Query("EXEC sys.sp_updateextendedproperty @name = N'$escapedPropName', @value = N'$escapedValue', @level0type = N'SCHEMA', @level0name = N'$escapedSchema', @level1type = N'TABLE', @level1name = N'$escapedTable', @level2type = N'COLUMN', @level2name = N'$escapedColumn'")
        } else {
            $Db.Query("EXEC sys.sp_addextendedproperty @name = N'$escapedPropName', @value = N'$escapedValue', @level0type = N'SCHEMA', @level0name = N'$escapedSchema', @level1type = N'TABLE', @level1name = N'$escapedTable', @level2type = N'COLUMN', @level2name = N'$escapedColumn'")
        }
    }

    if ($SqlInstance) {
        if (-not $Table -or -not $Column) {
            Stop-Function -Message "Table and Column must be specified when using SqlInstance" -EnableException $EnableException -FunctionName Set-DbaDbDataClassification
            return
        }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure connecting to $instance" -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaDbDataClassification
                continue
            }
            foreach ($dbName in $Database) {
                $db = $server.Databases[$dbName]
                if (-not $db) {
                    Stop-Function -Message "Database '$dbName' not found on $instance" -Target $instance -Continue -FunctionName Set-DbaDbDataClassification
                    continue
                }

                $target = "[$Schema].[$Table].[$Column] in $dbName on $instance"
                if (-not $__realCmdlet.ShouldProcess($target, "Setting data classification")) { continue }

                try {
                    if ($InformationType) {
                        $splatInfo = @{
                            Db         = $db
                            PropName   = "sys_information_type_name"
                            PropValue  = $InformationType
                            SchemaName = $Schema
                            TableName  = $Table
                            ColumnName = $Column
                        }
                        $null = Invoke-UpsertExtendedProperty @splatInfo
                        $splatInfoId = @{
                            Db         = $db
                            PropName   = "sys_information_type_id"
                            PropValue  = "$InformationTypeId"
                            SchemaName = $Schema
                            TableName  = $Table
                            ColumnName = $Column
                        }
                        $null = Invoke-UpsertExtendedProperty @splatInfoId
                    }
                    if ($SensitivityLabel) {
                        $splatLabel = @{
                            Db         = $db
                            PropName   = "sys_sensitivity_label_name"
                            PropValue  = $SensitivityLabel
                            SchemaName = $Schema
                            TableName  = $Table
                            ColumnName = $Column
                        }
                        $null = Invoke-UpsertExtendedProperty @splatLabel
                        $splatLabelId = @{
                            Db         = $db
                            PropName   = "sys_sensitivity_label_id"
                            PropValue  = "$SensitivityLabelId"
                            SchemaName = $Schema
                            TableName  = $Table
                            ColumnName = $Column
                        }
                        $null = Invoke-UpsertExtendedProperty @splatLabelId
                    }
                } catch {
                    Stop-Function -Message "Failure setting data classification on $target" -ErrorRecord $_ -Target $db -Continue -FunctionName Set-DbaDbDataClassification
                    continue
                }

                Get-DbaDbDataClassification -InputObject $db -Schema $Schema -Table $Table -Column $Column
            }
        }
        return
    }

    foreach ($classObj in $InputObject) {
        $db = $classObj.DatabaseObject
        if (-not $db) {
            Stop-Function -Message "No database object found in input. Pipe from Get-DbaDbDataClassification or use -SqlInstance/-Database/-Table/-Column parameters." -Continue -FunctionName Set-DbaDbDataClassification
            continue
        }

        $server = $db.Parent
        $schemaName = $classObj.Schema
        $tableName = $classObj.Table
        $columnName = $classObj.Column
        $target = "[$schemaName].[$tableName].[$columnName] in $($db.Name) on $server"

        if (-not $__realCmdlet.ShouldProcess($target, "Setting data classification")) { continue }

        try {
            if ($InformationType) {
                $splatInfo = @{
                    Db         = $db
                    PropName   = "sys_information_type_name"
                    PropValue  = $InformationType
                    SchemaName = $schemaName
                    TableName  = $tableName
                    ColumnName = $columnName
                }
                $null = Invoke-UpsertExtendedProperty @splatInfo
                $splatInfoId = @{
                    Db         = $db
                    PropName   = "sys_information_type_id"
                    PropValue  = "$InformationTypeId"
                    SchemaName = $schemaName
                    TableName  = $tableName
                    ColumnName = $columnName
                }
                $null = Invoke-UpsertExtendedProperty @splatInfoId
            }
            if ($SensitivityLabel) {
                $splatLabel = @{
                    Db         = $db
                    PropName   = "sys_sensitivity_label_name"
                    PropValue  = $SensitivityLabel
                    SchemaName = $schemaName
                    TableName  = $tableName
                    ColumnName = $columnName
                }
                $null = Invoke-UpsertExtendedProperty @splatLabel
                $splatLabelId = @{
                    Db         = $db
                    PropName   = "sys_sensitivity_label_id"
                    PropValue  = "$SensitivityLabelId"
                    SchemaName = $schemaName
                    TableName  = $tableName
                    ColumnName = $columnName
                }
                $null = Invoke-UpsertExtendedProperty @splatLabelId
            }
        } catch {
            Stop-Function -Message "Failure setting data classification on $target" -ErrorRecord $_ -Target $db -Continue -FunctionName Set-DbaDbDataClassification
            continue
        }

        Get-DbaDbDataClassification -InputObject $db -Schema $schemaName -Table $tableName -Column $columnName
    }
} $SqlInstance $SqlCredential $Database $Schema $Table $Column $InformationType $InformationTypeId $SensitivityLabel $SensitivityLabelId $InputObject $EnableException $__realCmdlet $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
