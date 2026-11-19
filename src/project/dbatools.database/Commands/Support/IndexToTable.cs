#nullable enable

using System;
using System.Collections.Generic;
using Dataplat.Dbatools.Message;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>One table's statement bundle - the helper's PSCustomObject, property for property.</summary>
public sealed class IndexToTableStatement
{
    /// <summary>The source table's schema.</summary>
    public string? Schema { get; set; }
    /// <summary>The source table's name.</summary>
    public string? Table { get; set; }
    /// <summary>Indexed non-identity column names plus the trailing RowNr.</summary>
    public string[]? Columns { get; set; }
    /// <summary>schema_table, the masking work table name.</summary>
    public string? TempTableName { get; set; }
    /// <summary>CREATE TABLE statement for the work table.</summary>
    public string? CreateStatement { get; set; }
    /// <summary>UIX_schema_table.</summary>
    public string? UniqueIndexName { get; set; }
    /// <summary>CREATE UNIQUE NONCLUSTERED INDEX statement over all columns.</summary>
    public string? UniqueIndexStatement { get; set; }
}

/// <summary>A qualifying column reduced to what the statement builder needs.</summary>
public sealed class IndexToTableColumn
{
    /// <summary>Column name.</summary>
    public string? Name { get; set; }
    /// <summary>Lowercased resolved data type (UDTs already resolved to their system type).</summary>
    public string? DataType { get; set; }
    /// <summary>Maximum length (UDT length for user-defined types).</summary>
    public int Length { get; set; }
}

/// <summary>
/// private/functions/Convert-DbaIndexToTable.ps1 parity, split into an OFFLINE-testable
/// statement core (BuildStatement/BuildColumnStatement/MatchesPsIn) and a thin SMO adapter
/// (Convert) whose live traversal - db.Tables/Indexes/Columns and UDT resolution through
/// db.UserDefinedDataTypes - rides the future Invoke-DbaDbDataMasking lab gate (sole caller,
/// database family, hence this satellite per the caller-list ownership rule; the tracker
/// Module column said dbatools.library - discrepancy recorded in Evidence). SMO columns
/// cannot be constructed without a live server (Set DataType connects), so the adapter has
/// no offline test by design - the same live/offline honesty split as TB-007. Faithful
/// details preserved in the core: the helper's datatype branch order including the
/// *varcharmax -> (max) rewrite and the fixed no-length list; RowNr [bigint] appended to
/// both names and statements; tables with zero qualifying columns emit nothing (helper line
/// 96); Schema/Table filters use PS -in semantics (case-insensitive invariant); identity
/// columns are excluded by the adapter; Select-Object -Unique over the column objects is a
/// no-op for real inputs (a table's Columns collection cannot repeat a name) and is not
/// reproduced; the helper's prologue (Get-DbaDatabase, Stop-Function guard,
/// Test-FunctionInterrupt) is caller plumbing in compiled form - NOTE for that caller:
/// PS $null.Tables silently yields nothing when the database is not found, so the compiled
/// caller must treat not-found as empty rather than let this class's null guard surface
/// (carry into the Invoke-DbaDbDataMasking lab gate). Documented divergence: datatype
/// lowercasing uses ToLowerInvariant where the helper's ToLower() is CURRENT-culture -
/// under tr-TR the helper's dotless-i would miss the fixed list and fall to default. Only
/// the branch formatting coincides (both share a format string); the emitted datatype text
/// itself diverges - PS writes the culture-lowercased dotless-i string into the SQL while
/// this port always writes the invariant form, which is the intended behavior going
/// forward.
/// </summary>
public static class IndexToTable
{
    /// <summary>The helper's process block over one database (live SMO adapter).</summary>
    public static List<IndexToTableStatement> Convert(Microsoft.SqlServer.Management.Smo.Database db, string[]? schema, string[]? table, bool unique, Action<MessageLevel, string?>? messageCallback)
    {
        if (db == null)
            throw new ArgumentNullException("db");

        List<IndexToTableStatement> tableStatements = new List<IndexToTableStatement>();
        foreach (Table tableObject in db.Tables)
        {
            // Helper lines 32-41: `if ($Schema)` is PS array truthiness - a singleton
            // empty string unwraps to falsy and disables the filter entirely.
            if (IsPsTruthy(schema) && !MatchesPsIn(schema!, tableObject.Schema))
                continue;
            if (IsPsTruthy(table) && !MatchesPsIn(table!, tableObject.Name))
                continue;

            if (messageCallback != null)
                messageCallback(MessageLevel.Verbose, String.Format("Processing table [{0}].[{1}]", tableObject.Schema, tableObject.Name));

            // Helper lines 48-55: flatten the (optionally unique-only) indexes' columns.
            List<string> indexedColumns = new List<string>();
            foreach (Microsoft.SqlServer.Management.Smo.Index index in tableObject.Indexes)
            {
                if (unique && !index.IsUnique)
                    continue;
                foreach (IndexedColumn indexedColumn in index.IndexedColumns)
                    indexedColumns.Add(indexedColumn.Name);
            }

            // Helper lines 58-72: indexed, non-identity columns with UDTs resolved.
            List<IndexToTableColumn> columns = new List<IndexToTableColumn>();
            foreach (Column columnObject in tableObject.Columns)
            {
                if (columnObject.Identity)
                    continue;
                if (!MatchesPsIn(indexedColumns.ToArray(), columnObject.Name))
                    continue;

                IndexToTableColumn reduced = new IndexToTableColumn();
                reduced.Name = columnObject.Name;
                if (columnObject.DataType.SqlDataType == SqlDataType.UserDefinedDataType)
                {
                    UserDefinedDataType uddt = db.UserDefinedDataTypes[columnObject.DataType.Name];
                    reduced.DataType = uddt.SystemType.ToLowerInvariant().Trim();
                    reduced.Length = uddt.Length;
                }
                else
                {
                    reduced.DataType = columnObject.DataType.SqlDataType.ToString().ToLowerInvariant();
                    reduced.Length = columnObject.DataType.MaximumLength;
                }
                columns.Add(reduced);
            }

            IndexToTableStatement? statement = BuildStatement(tableObject.Schema, tableObject.Name, columns);
            if (statement != null)
                tableStatements.Add(statement);
        }
        return tableStatements;
    }

    /// <summary>
    /// Helper lines 60-109 for one table: builds the statement bundle from the qualifying
    /// columns, appending RowNr; returns null when no column qualifies (helper line 96).
    /// </summary>
    public static IndexToTableStatement? BuildStatement(string? schema, string? table, IList<IndexToTableColumn> columns)
    {
        if (columns == null)
            throw new ArgumentNullException("columns");

        List<string> columnStatements = new List<string>();
        foreach (IndexToTableColumn column in columns)
            columnStatements.Add(BuildColumnStatement(column.Name, column.DataType ?? "", column.Length));

        // Helper line 93.
        columnStatements.Add("[RowNr] [bigint]");

        if (columns.Count < 1)
            return null;

        List<string> columnNames = new List<string>();
        foreach (IndexToTableColumn column in columns)
            columnNames.Add(column.Name ?? "");
        columnNames.Add("RowNr");

        IndexToTableStatement statement = new IndexToTableStatement();
        statement.Schema = schema;
        statement.Table = table;
        statement.Columns = columnNames.ToArray();
        statement.TempTableName = String.Format("{0}_{1}", schema, table);
        statement.CreateStatement = String.Format("CREATE TABLE {0}_{1}({2});", schema, table, String.Join(",", columnStatements));
        statement.UniqueIndexName = String.Format("UIX_{0}_{1}", schema, table);
        statement.UniqueIndexStatement = String.Format("CREATE UNIQUE NONCLUSTERED INDEX [UIX_{0}_{1}] ON {0}_{1}([{2}] ASC);", schema, table, String.Join("],[", columnNames));
        return statement;
    }

    /// <summary>Helper lines 75-89: one column's CREATE fragment, branch order preserved.</summary>
    public static string BuildColumnStatement(string? name, string dataType, int length)
    {
        if (dataType == "bigint" || dataType == "date" || dataType == "datetime" || dataType == "datetime2" || dataType == "smallint" || dataType == "time" || dataType == "tinyint")
            return String.Format("[{0}] [{1}]", name, dataType);
        if (dataType.EndsWith("varcharmax", StringComparison.Ordinal))
            return String.Format("[{0}] [{1}](max)", name, dataType.Replace("max", ""));
        if (dataType.Contains("char"))
            return String.Format("[{0}] [{1}]({2})", name, dataType, length);
        return String.Format("[{0}] [{1}]", name, dataType);
    }

    /// <summary>PS `if ($array)` truthiness: null/empty arrays are falsy; a SINGLETON
    /// unwraps to its element's truthiness (so @("") is falsy and disables the filter);
    /// two or more elements are always truthy.</summary>
    public static bool IsPsTruthy(string[]? value)
    {
        if (value == null || value.Length == 0)
            return false;
        if (value.Length == 1)
            return !String.IsNullOrEmpty(value[0]);
        return true;
    }

    /// <summary>PS -in for strings: case-insensitive invariant comparison.</summary>
    public static bool MatchesPsIn(string[] set, string? candidate)
    {
        if (set == null)
            throw new ArgumentNullException("set");
        foreach (string item in set)
        {
            if (String.Equals(item, candidate, StringComparison.InvariantCultureIgnoreCase))
                return true;
        }
        return false;
    }
}
