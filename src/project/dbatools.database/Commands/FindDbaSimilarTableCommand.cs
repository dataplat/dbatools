#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Finds tables that share column names across databases (schema-similarity search), with a match
/// percentage. Port of public/Find-DbaSimilarTable.ps1; the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// A 3-hop begin+process+end port (SqlInstance is ValueFromPipeline, so process fires per record). begin
/// builds the constant INFORMATION_SCHEMA self-join query $sql (the SELECT plus WHERE/GROUP BY/HAVING/
/// ORDER BY, assembled from ExcludeViews/SchemaName/TableName/MatchPercentThreshold with single-quote
/// escaping) and initializes the counter $everyServerVwCount = 0. process, per instance, connects
/// (MinimumVersion 9), filters databases, runs $db.Query($sql) per database, emits a PSCustomObject per
/// match row, and accumulates counters. end writes the grand total.
///
/// CROSS-RECORD ACCUMULATOR CARRY: two counters are never reset and accumulate across ALL records and
/// databases - $everyServerVwCount (initialized 0 in begin, read in END) and $vwCount (never initialized,
/// used only in a per-database verbose message - the source shows the running total there). $totalCount is
/// per-record and stays local. Because hop scope dies per record, the constant $sql and both never-reset
/// counters ride a sentinel Hashtable (_state) carried begin->process(xN)->end: begin seeds
/// { Sql; EveryServerVwCount = 0; VwCount = $null }, each process record restores them, accumulates the two
/// counters, and re-emits, and end restores $everyServerVwCount for the final message. Body edits:
/// -FunctionName Find-DbaSimilarTable on begin's one Write-Message, process's Stop-Function and three
/// Write-Message, and end's Write-Message. No ShouldProcess, no early return, no interrupt (the one
/// Stop-Function is -Continue). Surface pinned by migration/baselines/Find-DbaSimilarTable.json (positions
/// 0-6, no parameter sets, no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Find, "DbaSimilarTable")]
public sealed class FindDbaSimilarTableCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to search.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Restrict the search to a schema.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? SchemaName { get; set; }

    /// <summary>Restrict the search to a table.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string? TableName { get; set; }

    /// <summary>Exclude views from the comparison.</summary>
    [Parameter]
    public SwitchParameter ExcludeViews { get; set; }

    /// <summary>Include system databases in the search.</summary>
    [Parameter]
    public SwitchParameter IncludeSystemDatabases { get; set; }

    /// <summary>The minimum match percentage to return.</summary>
    [Parameter(Position = 6)]
    [PsIntCast]
    public int MatchPercentThreshold { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The constant query $sql plus the two never-reset counters, carried begin->process(xN)->end.
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__findDbaSimilarTableBegin"))
            {
                _state = sentinel["__findDbaSimilarTableBegin"] as Hashtable;
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
            ExcludeViews.ToBool(), SchemaName, TableName, MatchPercentThreshold, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__findDbaSimilarTableProcess"))
            {
                if (sentinel["__findDbaSimilarTableProcess"] is Hashtable state)
                {
                    _state = state["State"] as Hashtable ?? _state;
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, IncludeSystemDatabases.ToBool(),
            EnableException.ToBool(), _state, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
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
        }, EndScript,
            _state, EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
    // PS: the begin block VERBATIM (builds $sql and seeds the counter) plus a sentinel carrying the
    // constant query and the two never-reset counters to the process hop. Edit: -FunctionName on the one
    // Write-Message.
    private const string BeginScript ="""
param($ExcludeViews, $SchemaName, $TableName, $MatchPercentThreshold, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($ExcludeViews, [string]$SchemaName, [string]$TableName, [int]$MatchPercentThreshold, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        $everyServerVwCount = 0

        $sqlSelect = "WITH ColCountsByTable
                AS
                (
                      SELECT
                            c.TABLE_CATALOG,
                            c.TABLE_SCHEMA,
                            c.TABLE_NAME,
                            COUNT(1) AS Column_Count
                      FROM INFORMATION_SCHEMA.COLUMNS c
                      GROUP BY
                            c.TABLE_CATALOG,
                            c.TABLE_SCHEMA,
                            c.TABLE_NAME
                )
                SELECT
                      100 * COUNT(c2.COLUMN_NAME) /*Matching_Column_Count*/ / MIN(ColCountsByTable.Column_Count) /*Column_Count*/ AS MatchPercent,
                      DENSE_RANK() OVER(ORDER BY c.TABLE_CATALOG, c.TABLE_SCHEMA, c.TABLE_NAME) TableNameRankInDB,
                      c.TABLE_CATALOG AS DatabaseName,
                      (SELECT database_id FROM sys.databases WHERE name = c.TABLE_CATALOG) AS DatabaseId,
                      c.TABLE_SCHEMA AS SchemaName,
                      c.TABLE_NAME AS TableName,
                      t.TABLE_TYPE AS TableType,
                      MIN(ColCountsByTable.Column_Count) AS ColumnCount,
                      c2.TABLE_CATALOG AS MatchingDatabaseName,
                      (SELECT database_id FROM sys.databases WHERE name = c2.TABLE_CATALOG) AS MatchingDatabaseId,
                      c2.TABLE_SCHEMA AS MatchingSchemaName,
                      c2.TABLE_NAME AS MatchingTableName,
                      t2.TABLE_TYPE AS MatchingTableType,
                      COUNT(c2.COLUMN_NAME) AS MatchingColumnCount
                FROM INFORMATION_SCHEMA.TABLES t
                      INNER JOIN INFORMATION_SCHEMA.COLUMNS c
                            ON t.TABLE_CATALOG = c.TABLE_CATALOG
                                  AND t.TABLE_SCHEMA = c.TABLE_SCHEMA
                                  AND t.TABLE_NAME = c.TABLE_NAME
                      INNER JOIN ColCountsByTable
                            ON t.TABLE_CATALOG = ColCountsByTable.TABLE_CATALOG
                                  AND t.TABLE_SCHEMA = ColCountsByTable.TABLE_SCHEMA
                                  AND t.TABLE_NAME = ColCountsByTable.TABLE_NAME
                      LEFT OUTER JOIN INFORMATION_SCHEMA.COLUMNS c2
                            ON t.TABLE_NAME != c2.TABLE_NAME
                                  AND c.COLUMN_NAME = c2.COLUMN_NAME
                      LEFT JOIN INFORMATION_SCHEMA.TABLES t2
                            ON c2.TABLE_NAME = t2.TABLE_NAME"

        $sqlWhere = "
                WHERE "

        $sqlGroupBy = "
                GROUP BY
                      c.TABLE_CATALOG,
                      c.TABLE_SCHEMA,
                      c.TABLE_NAME,
                      t.TABLE_TYPE,
                      c2.TABLE_CATALOG,
                      c2.TABLE_SCHEMA,
                      c2.TABLE_NAME,
                      t2.TABLE_TYPE "

        $sqlHaving = "
                HAVING
                    /*Match_Percent should be greater than 0 at minimum!*/
                    "

        $sqlOrderBy = "
                ORDER BY
                      MatchPercent DESC"


        $sql = ''
        $wherearray = @()

        if ($ExcludeViews) {
            $wherearray += " (t.TABLE_TYPE <> 'VIEW' AND t2.TABLE_TYPE <> 'VIEW') "
        }

        if ($SchemaName) {
            $wherearray += (" (c.TABLE_SCHEMA = '{0}') " -f $SchemaName.Replace("'", "''")) #Replace single quotes with two single quotes!
        }

        if ($TableName) {
            $wherearray += (" (c.TABLE_NAME = '{0}') " -f $TableName.Replace("'", "''")) #Replace single quotes with two single quotes!

        }

        if ($wherearray.length -gt 0) {
            $sqlWhere = "$sqlWhere " + ($wherearray -join " AND ")
        } else {
            $sqlWhere = ""
        }


        $matchThreshold = 0
        if ($MatchPercentThreshold) {
            $matchThreshold = $MatchPercentThreshold
        } else {
            $matchThreshold = 0
        }

        $sqlHaving += (" (100 * COUNT(c2.COLUMN_NAME) / MIN(ColCountsByTable.Column_Count) >= {0}) " -f $matchThreshold)



        $sql = "$sqlSelect $sqlWhere $sqlGroupBy $sqlHaving $sqlOrderBy"

        Write-Message -Level Debug -Message $sql -FunctionName Find-DbaSimilarTable -ModuleName "dbatools"


    @{ __findDbaSimilarTableBegin = @{ Sql = $sql; EveryServerVwCount = $everyServerVwCount; VwCount = $null } }
} $ExcludeViews $SchemaName $TableName $MatchPercentThreshold $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM. Edits: -FunctionName on the Stop-Function and three Write-Message.
    // $sql and the two never-reset counters are restored from the carried state; the counters are
    // accumulated and re-emitted so they persist record-to-record and into end.
    private const string ProcessScript ="""
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $IncludeSystemDatabases, $EnableException, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, $IncludeSystemDatabases, $EnableException, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $sql = $__state.Sql
    $everyServerVwCount = $__state.EveryServerVwCount
    $vwCount = $__state.VwCount

        foreach ($Instance in $SqlInstance) {

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -FunctionName Find-DbaSimilarTable -Continue
            }


            #Use IsAccessible instead of Status -eq 'normal' because databases that are on readable secondaries for AG or mirroring replicas will cause errors to be thrown
            if ($IncludeSystemDatabases) {
                $dbs = $server.Databases | Where-Object { $_.IsAccessible -eq $true }
            } else {
                $dbs = $server.Databases | Where-Object { $_.IsAccessible -eq $true -and $_.IsSystemObject -eq $false }
            }

            if ($Database) {
                $dbs = $server.Databases | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }


            $totalCount = 0
            $dbCount = $dbs.count
            foreach ($db in $dbs) {

                Write-Message -Level Verbose -Message "Searching on database $db" -FunctionName Find-DbaSimilarTable -ModuleName "dbatools"
                $rows = $db.Query($sql)

                foreach ($row in $rows) {
                    [PSCustomObject]@{
                        ComputerName              = $server.ComputerName
                        InstanceName              = $server.ServiceName
                        SqlInstance               = $server.DomainInstanceName
                        Table                     = "$($row.DatabaseName).$($row.SchemaName).$($row.TableName)"
                        MatchingTable             = "$($row.MatchingDatabaseName).$($row.MatchingSchemaName).$($row.MatchingTableName)"
                        MatchPercent              = $row.MatchPercent
                        OriginalDatabaseName      = $row.DatabaseName
                        OriginalDatabaseId        = $row.DatabaseId
                        OriginalSchemaName        = $row.SchemaName
                        OriginalTableName         = $row.TableName
                        OriginalTableNameRankInDB = $row.TableNameRankInDB
                        OriginalTableType         = $row.TableType
                        OriginalColumnCount       = $row.ColumnCount
                        MatchingDatabaseName      = $row.MatchingDatabaseName
                        MatchingDatabaseId        = $row.MatchingDatabaseId
                        MatchingSchemaName        = $row.MatchingSchemaName
                        MatchingTableName         = $row.MatchingTableName
                        MatchingTableType         = $row.MatchingTableType
                        MatchingColumnCount       = $row.MatchingColumnCount
                    }
                }

                $vwCount = $vwCount + $rows.Count
                $totalCount = $totalCount + $rows.Count
                $everyServerVwCount = $everyServerVwCount + $rows.Count

                Write-Message -Level Verbose -Message "Found $vwCount tables/views in $db" -FunctionName Find-DbaSimilarTable -ModuleName "dbatools"
            }

            Write-Message -Level Verbose -Message "Found $totalCount total tables/views in $dbCount databases" -FunctionName Find-DbaSimilarTable -ModuleName "dbatools"
        }

    $__state.EveryServerVwCount = $everyServerVwCount
    $__state.VwCount = $vwCount
    @{ __findDbaSimilarTableProcess = @{ State = $__state } }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $IncludeSystemDatabases $EnableException $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the end block VERBATIM. Edit: -FunctionName on the Write-Message. $everyServerVwCount is
    // restored from the carried state so the grand total reflects all records.
    private const string EndScript ="""
param($__state, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__state, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $everyServerVwCount = $__state.EveryServerVwCount

        Write-Message -Level Verbose -Message "Found $everyServerVwCount total tables/views" -FunctionName Find-DbaSimilarTable -ModuleName "dbatools"
} $__state $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
