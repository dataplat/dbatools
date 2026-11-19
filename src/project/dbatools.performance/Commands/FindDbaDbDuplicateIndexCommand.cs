#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
// the sibling namespace Dataplat.Dbatools.Database shadows Smo.Database inside
// Dataplat.Dbatools.Commands (the W1-020 namespace trap) - alias the SMO type
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Find-DbaDbDuplicateIndex.ps1: connect (MinimumVersion 9), pick the databases, run the exact or the
// overlapping query in each through Database.ExecuteWithResults with the Database.Query script method's restore of the
// caller's database, and write each row. The pinned SQL Server 2005 queries are not ported: SQL Server 2005 is
// withdrawn and the connection layer refuses it. The catch's Stop-Function has no -ErrorRecord and no -Continue: the
// plain "Query failure" warning arms the interrupt (later pipeline input returns) while the database loop proceeds.
/// <summary>Identifies duplicate and overlapping indexes that waste storage space and degrade insert performance</summary>
[Cmdlet(VerbsCommon.Find, "DbaDbDuplicateIndex")]
public sealed class FindDbaDbDuplicateIndexCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Includes overlapping (partial duplicate) indexes.</summary>
    [Parameter]
    public SwitchParameter IncludeOverlapping { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance -MinimumVersion 9 } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 9);
            if (server is null)
                continue;

            // PS: $server.Databases | Where-Object Name -in $database. Correction (database-wildcards): the pinned help
            // documents wildcards for -Database, which the literal -in never honoured; a real database name of this
            // instance stays literal.
            WildcardNameMatcher databaseMatcher = WildcardNameFilter.CreateMatcher(Database, true, InOperandEquals, DatabaseNames(server));
            List<SmoDatabase> databases = new List<SmoDatabase>();
            foreach (SmoDatabase candidate in server.Databases)
            {
                if (LanguagePrimitives.IsTrue(Database))
                {
                    if (databaseMatcher.Matches(candidate.Name))
                        databases.Add(candidate);
                }
                else if (candidate.IsAccessible)
                {
                    databases.Add(candidate);
                }
            }

            foreach (SmoDatabase db in databases)
            {
                try
                {
                    // PS: "$db" interpolates the SMO Database object ("[name]").
                    WriteMessage(MessageLevel.Verbose, "Getting indexes from database '" + db.ToString() + "'.");

                    string query = IncludeOverlapping.ToBool() ? OverlappingQuery : ExactDuplicateQuery;

                    // PS: $db.Query($query) - the script method returns ExecuteWithResults($query).Tables[0], whose rows
                    // the pipeline enumerates.
                    DataTable table = QueryDatabase(db, query);
                    foreach (DataRow row in table.Rows)
                        WriteObject(row);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception)
                {
                    // PS: Stop-Function -Message "Query failure" -Target $db - no record,
                    // no -Continue: plain warning, interrupt armed, loop proceeds.
                    StopFunction("Query failure", target: db);
                }
            }
        }
    }

    /// <summary>PS: $name -in $values for one value. -in compares the value with the name, the value on the left, so
    /// the name converts to the value's type (a database named 01 is -in @(1)).</summary>
    private static bool InOperandEquals(object value, string name)
    {
        return LanguagePrimitives.Equals(value is PSObject wrapped ? wrapped.BaseObject : value, name, true, CultureInfo.InvariantCulture);
    }

    /// <summary>PS: the Database.Query script method. ExecuteWithResults issues a USE on the caller's own server
    /// connection and never switches back, so the script method's finally puts the previous database back (#10555); a
    /// failed USE only warns, through plain Write-Warning, with a Stop or Inquire preference raised to Continue.</summary>
    private DataTable QueryDatabase(SmoDatabase db, string query)
    {
        ServerConnection connection = db.Parent.ConnectionContext;
        string callerDatabase = connection.CurrentDatabase;
        try
        {
            return db.ExecuteWithResults(query).Tables[0];
        }
        finally
        {
            // -cne in the script method: database names follow the instance collation.
            if (!String.IsNullOrEmpty(callerDatabase) && !String.Equals(callerDatabase, connection.CurrentDatabase, StringComparison.Ordinal))
            {
                try
                {
                    connection.ExecuteNonQuery("USE [" + callerDatabase.Replace("]", "]]") + "]");
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    string text = String.Format(CultureInfo.InvariantCulture,
                        "The database context could not be restored to [{0}]: Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{1}\"",
                        callerDatabase, failure.Message);
                    try
                    {
                        WriteWarning(text); // style-ok: cs-raw-streams the Database.Query script method calls plain Write-Warning, not Write-Message
                    }
                    catch (ActionPreferenceStopException stopped)
                    {
                        // The script method raises Stop to Continue for this one warning, so it never ends the command.
                        WriteMessage(MessageLevel.Debug, stopped.Message);
                    }
                }
            }
        }
    }

    /// <summary>Every database name of the instance: the scope that keeps a real name literal.</summary>
    private static IEnumerable<string> DatabaseNames(Server server)
    {
        foreach (SmoDatabase database in server.Databases)
            yield return database.Name;
    }

    // The pinned exact and overlapping queries differ only in the CI2 predicate of their final EXISTS; the two column
    // lists of CTE_IndexCols differ only in is_included_column. Both are composed here from fixed text.
    private static readonly string ExactDuplicateQuery = Compose(ExactDuplicatePredicate);

    private static readonly string OverlappingQuery = Compose(OverlappingPredicate);

    private static string Compose(string predicate)
    {
        return String.Format(CultureInfo.InvariantCulture, QueryTemplate,
            String.Format(CultureInfo.InvariantCulture, ColumnListTemplate, "0"),
            String.Format(CultureInfo.InvariantCulture, ColumnListTemplate, "1"),
            predicate);
    }

    // {0}: is_included_column. Correction (xml-escaped-column-names): TYPE with value() returns the list as text,
    // where the pinned FOR XML PATH('') entitized &, < and > in column names.
    private const string ColumnListTemplate = @"
ISNULL(STUFF((
                                SELECT ', ' + col.NAME + ' ' + CASE
                                        WHEN idxCol.is_descending_key = 1
                                            THEN 'DESC'
                                        ELSE 'ASC'
                                        END -- Include column order (ASC / DESC)
                                FROM sys.index_columns idxCol
                                INNER JOIN sys.columns col ON idxCol.[object_id] = col.[object_id]
                                    AND idxCol.column_id = col.column_id
                                WHERE i.[object_id] = idxCol.[object_id]
                                    AND i.index_id = idxCol.index_id
                                    AND idxCol.is_included_column = {0}
                                ORDER BY idxCol.key_ordinal
                                FOR XML PATH(''), TYPE
                                ).value(N'.', N'nvarchar(max)'), 1, 2, ''), '')
";

    // {0}: the key column list, {1}: the included column list, {2}: the CI2 predicate. Correction
    // (filter-definitions): both searches also compare sys.indexes.filter_definition, which the output does not carry,
    // where the pin compared only IsFiltered and so reported filtered indexes with different filters as duplicates.
    // Correction (filter-definition-collation): the definitions compare in a binary collation, since metadata takes the database's
    // collation and a case-insensitive one made 'open' and 'OPEN' equal on a case-sensitive column.
    private const string QueryTemplate = @"

            WITH CTE_IndexCols
            AS (
                SELECT i.[object_id]
                    ,i.index_id
                    ,OBJECT_SCHEMA_NAME(i.[object_id]) AS SchemaName
                    ,OBJECT_NAME(i.[object_id]) AS TableName
                    ,NAME AS IndexName
                    ,{0} AS KeyColumns
                    ,{1} AS IncludedColumns
                    ,i.[type_desc] AS IndexType
                    ,i.is_disabled AS IsDisabled
                    ,i.has_filter AS IsFiltered
                    ,i.filter_definition AS FilterDefinition
                    ,i.is_unique AS IsUnique
                FROM sys.indexes AS i
                WHERE i.index_id > 0 -- Exclude HEAPS
                    AND i.[type_desc] IN (
                        'CLUSTERED'
                        ,'NONCLUSTERED'
                        )
                    AND OBJECT_SCHEMA_NAME(i.[object_id]) <> 'sys'
                )
                ,CTE_IndexSpace
            AS (
                SELECT s.[object_id]
                    ,s.index_id
                    ,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
                    ,SUM(p.[rows]) AS [RowCount]
                    ,p.data_compression_desc AS CompressionDescription
                FROM sys.dm_db_partition_stats AS s
                INNER JOIN sys.partitions p WITH (NOLOCK) ON s.[partition_id] = p.[partition_id] -- style-ok: sql-nolock the pinned hint on a catalog view, kept as upstream runs it
                    AND s.[object_id] = p.[object_id]
                    AND s.index_id = p.index_id
                WHERE s.index_id > 0 -- Exclude HEAPS
                    AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
                GROUP BY s.[object_id]
                    ,s.index_id
                    ,p.data_compression_desc
                )
            SELECT DB_NAME() AS DatabaseName
                ,CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
                ,CI1.IndexName
                ,CI1.KeyColumns
                ,CI1.IncludedColumns
                ,CI1.IndexType
                ,COALESCE(CSPC.IndexSizeMB,0) AS 'IndexSizeMB'
                ,COALESCE(CSPC.CompressionDescription, 'NONE') AS 'CompressionDescription'
                ,COALESCE(CSPC.[RowCount],0) AS 'RowCount'
                ,CI1.IsDisabled
                ,CI1.IsFiltered
                ,CI1.IsUnique
            FROM CTE_IndexCols AS CI1
            LEFT JOIN CTE_IndexSpace AS CSPC ON CI1.[object_id] = CSPC.[object_id]
                AND CI1.index_id = CSPC.index_id
            WHERE EXISTS (
                    SELECT 1
                    FROM CTE_IndexCols CI2
                    WHERE CI1.SchemaName = CI2.SchemaName
                        AND CI1.TableName = CI2.TableName
                        {2}
                        AND CI1.IsFiltered = CI2.IsFiltered
                        AND ISNULL(CI1.FilterDefinition, N'') COLLATE Latin1_General_BIN2 = ISNULL(CI2.FilterDefinition, N'') COLLATE Latin1_General_BIN2
                        AND CI1.IndexName <> CI2.IndexName
                    )
";

    private const string ExactDuplicatePredicate = @"
AND CI1.KeyColumns = CI2.KeyColumns
                        AND CI1.IncludedColumns = CI2.IncludedColumns
";

    // Correction (overlapping-key-prefix): equal key lists, or one key list followed by ',' at the start of the other.
    // The pinned LIKE + '%' and SUBSTRING(...) = ' ' matched only equal lists, and read _ % [ ] in names as wildcards.
    private const string OverlappingPredicate = @"
AND (
                                CI1.KeyColumns = CI2.KeyColumns
                            OR LEFT(CI1.KeyColumns, LEN(CI2.KeyColumns) + 1) = CI2.KeyColumns + ','
                            OR LEFT(CI2.KeyColumns, LEN(CI1.KeyColumns) + 1) = CI1.KeyColumns + ','
                        )
";
}
