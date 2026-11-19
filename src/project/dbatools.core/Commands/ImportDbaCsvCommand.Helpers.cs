#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Reflection;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Csv.Reader;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

public sealed partial class ImportDbaCsvCommand
{
    /// <summary>Result shape of the absorbed private/functions/Get-ObjectNameParts.ps1.</summary>
    internal sealed class ObjectNameParts
    {
        public string? Database;
        public string? Schema;
        public string? Name;
        public bool Parsed;
    }

    /// <summary>Result shape of the absorbed Get-TableDefinitionFromInfoSchema begin-block helper.</summary>
    private sealed class TableColumnDef
    {
        public string Name = "";
        public string DataType = "";
        public int Index;
    }

    /// <summary>PS string interpolation of an arbitrary token.</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }

    /// <summary>PS interpolates a Type through the ETS ToString code method, rendering
    /// accelerated names ("int", "bool"), not FullName.</summary>
    private static string PsTypeName(Type type)
    {
        return Microsoft.PowerShell.ToStringCodeMethods.Type(PSObject.AsPSObject(type));
    }

    /// <summary>The catch-block $_ equivalent for a .NET-thrown exception.</summary>
    private static ErrorRecord RecordFrom(Exception ex)
    {
        IContainsErrorRecord? carrier = ex as IContainsErrorRecord;
        if (carrier?.ErrorRecord is not null)
            return carrier.ErrorRecord;
        return new ErrorRecord(ex, ex.GetType().FullName, ErrorCategory.NotSpecified, null);
    }

    /// <summary>PS renders a .NET method failure as 'Exception calling "X" with "N" argument(s): "msg"';
    /// call sites that surface $_.Exception.Message need that composed wrapper text.</summary>
    private static string MethodCallMessage(string methodName, int argumentCount, Exception ex)
    {
        return "Exception calling \"" + methodName + "\" with \"" + argumentCount + "\" argument(s): \"" + ex.Message + "\"";
    }

    /// <summary>
    /// PS: $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
    /// -Database $Database -MinimumVersion 9. The REAL command runs nested (local scope,
    /// PSDefaultParameterValues shielded to the global table, explicit -WarningVariable) so a
    /// connect failure surfaces its display-suppressed warning to the caller's
    /// -WarningVariable exactly like the function's nested call did. Returns null and assigns
    /// _server on success, or the caught ErrorRecord on failure.
    /// </summary>
    private ErrorRecord? ConnectViaCommand(DbaInstanceParameter instance)
    {
        Hashtable connectParams = new();
        connectParams["SqlInstance"] = instance;
        connectParams["SqlCredential"] = SqlCredential;
        connectParams["Database"] = Database;
        connectParams["MinimumVersion"] = 9;
        // PS: a bound -WarningAction on the outer command sets the preference the nested
        // call inherits (display suppression; -WarningVariable still captures).
        ScriptBlock script = ScriptBlock.Create(
            "param($__connectParams, $__wp) if ($null -ne $__wp) { $WarningPreference = $__wp } try { $__server = Connect-DbaInstance @__connectParams -WarningVariable __nestedWarnings; @{ ok = $true; server = $__server; warnings = $__nestedWarnings } } catch { @{ ok = $false; record = $_; warnings = $__nestedWarnings } }");
        object? boundWarningAction;
        MyInvocation.BoundParameters.TryGetValue("WarningAction", out boundWarningAction);

        Collection<PSObject> results;
        // Empty-table shield: module-internal calls never saw caller-local OR global
        // defaults (lab-proven via the PassThru-injection probe).
        object? effectiveDefaults = SessionState.PSVariable.GetValue("PSDefaultParameterValues");
        bool shielded = effectiveDefaults is not null;
        if (shielded)
            SessionState.PSVariable.Set("PSDefaultParameterValues", new DefaultParameterDictionary());
        try
        {
            results = InvokeCommand.InvokeScript(true, script, null, connectParams, boundWarningAction);
        }
        finally
        {
            if (shielded)
                SessionState.PSVariable.Set("PSDefaultParameterValues", effectiveDefaults);
        }

        Hashtable outcome = (Hashtable)results[0].BaseObject;

        // The nested warnings already displayed (or were suppressed) inside the nested
        // runtime; the re-emit below only restores caller -WarningVariable capture, so it
        // always writes display-suppressed (the MessageService WarningPreference-swap trick).
        object? warnings = outcome["warnings"];
        if (warnings is not null)
        {
            IEnumerable? enumerable = LanguagePrimitives.GetEnumerable(warnings);
            if (enumerable is not null)
            {
                foreach (object? warningItem in enumerable)
                {
                    object? unwrapped = warningItem is PSObject wrappedWarning ? wrappedWarning.BaseObject : warningItem;
                    string text = unwrapped is WarningRecord warningRecord ? warningRecord.Message : PsText(unwrapped);
                    object? oldPreference = SessionState.PSVariable.GetValue("WarningPreference");
                    try
                    {
                        SessionState.PSVariable.Set("WarningPreference", ActionPreference.SilentlyContinue);
                        WriteWarning(text);
                    }
                    finally
                    {
                        SessionState.PSVariable.Set("WarningPreference", oldPreference);
                    }
                }
            }
        }

        if (!LanguagePrimitives.IsTrue(outcome["ok"]))
        {
            object? record = outcome["record"];
            if (record is PSObject wrappedRecord)
                record = wrappedRecord.BaseObject;
            return (ErrorRecord)record!;
        }

        object? serverValue = outcome["server"];
        if (serverValue is PSObject wrappedServer)
            serverValue = wrappedServer.BaseObject;
        // PS: $server takes whatever the nested call emitted; the caller's dynamic reads
        // null-propagate for null/foreign values (codex r2 F2).
        _server = serverValue as Server;
        return null;
    }

    /// <summary>Runs the real Get-Content through the caller's runspace (edition-faithful
    /// encoding detection) with -ErrorAction Stop, like the PS source.</summary>
    private List<string?> GetContentLines(object path, long totalCount)
    {
        Hashtable parameters = new();
        parameters["Path"] = path;
        parameters["TotalCount"] = totalCount;
        parameters["ErrorAction"] = "Stop";
        Collection<PSObject> raw = NestedCommand.Invoke(this, "Get-Content", parameters);
        List<string?> lines = new();
        foreach (PSObject item in raw)
            lines.Add(item?.BaseObject as string);
        return lines;
    }

    /// <summary>PS: (Get-Content -Path $file -TotalCount 1 -ErrorAction Stop).ToString() -
    /// an empty file yields $null and the method call on it is statement-terminating.</summary>
    private string GetFirstLineToString(object path)
    {
        List<string?> lines = GetContentLines(path, 1);
        string? firstline = lines.Count > 0 ? lines[0] : null;
        if (firstline is null)
            throw new RuntimeException("You cannot call a method on a null-valued expression.");
        return firstline.ToString();
    }

    /// <summary>Sort-Object over hashtable keys: stable ascending LanguagePrimitives comparison.</summary>
    private static List<object> SortKeys(ICollection keys)
    {
        List<object> list = new();
        foreach (object key in keys)
            list.Add(key);
        // Insertion sort keeps Sort-Object's stability without LINQ.
        for (int i = 1; i < list.Count; i++)
        {
            object current = list[i];
            int j = i - 1;
            while (j >= 0 && PsOps.Compare(list[j], current) > 0)
            {
                list[j + 1] = list[j];
                j--;
            }
            list[j + 1] = current;
        }
        return list;
    }

    /// <summary>Replicates the PS method binder's ColumnMappings.Add overload selection:
    /// integral keys/values that implicitly widen to int (byte/sbyte/short/ushort/int -
    /// codex r1 F2) pick the ordinal overloads, everything else converts to string.</summary>
    private static void AddColumnMapping(SqlBulkCopy bulkcopy, object? key, object? value)
    {
        object? unwrappedKey = key is PSObject wrappedKey ? wrappedKey.BaseObject : key;
        object? unwrappedValue = value is PSObject wrappedValue ? wrappedValue.BaseObject : value;
        if (TryWidenToInt(unwrappedKey, out int keyOrdinal))
        {
            if (TryWidenToInt(unwrappedValue, out int valueOrdinal))
                bulkcopy.ColumnMappings.Add(keyOrdinal, valueOrdinal);
            else
                bulkcopy.ColumnMappings.Add(keyOrdinal, (string)LanguagePrimitives.ConvertTo(unwrappedValue, typeof(string), CultureInfo.InvariantCulture));
        }
        else
        {
            string keyName = (string)LanguagePrimitives.ConvertTo(unwrappedKey, typeof(string), CultureInfo.InvariantCulture);
            if (TryWidenToInt(unwrappedValue, out int valueOrdinal))
                bulkcopy.ColumnMappings.Add(keyName, valueOrdinal);
            else
                bulkcopy.ColumnMappings.Add(keyName, (string)LanguagePrimitives.ConvertTo(unwrappedValue, typeof(string), CultureInfo.InvariantCulture));
        }
    }

    /// <summary>The implicit-widening set the PS binder routes to the Add(int, ...) overloads.</summary>
    private static bool TryWidenToInt(object? value, out int ordinal)
    {
        switch (value)
        {
            case int i:
                ordinal = i;
                return true;
            case byte b:
                ordinal = b;
                return true;
            case sbyte sb:
                ordinal = sb;
                return true;
            case short s:
                ordinal = s;
                return true;
            case ushort us:
                ordinal = us;
                return true;
            case bool flag:
                // PS binder: bool/char/enum also pick the ordinal overloads (lab-proven).
                ordinal = flag ? 1 : 0;
                return true;
            case char character:
                ordinal = character;
                return true;
            default:
                if (value is Enum)
                {
                    ordinal = Convert.ToInt32(value, CultureInfo.InvariantCulture);
                    return true;
                }
                ordinal = 0;
                return false;
        }
    }

    /// <summary>PS: [System.Text.Encoding]::$Encoding - a case-insensitive static property
    /// lookup; Byte/String/Unknown have no matching property and read as $null.</summary>
    private static System.Text.Encoding? MapEncoding(string name)
    {
        switch (name?.ToLowerInvariant())
        {
            case "ascii":
                return System.Text.Encoding.ASCII;
            case "bigendianunicode":
                return System.Text.Encoding.BigEndianUnicode;
            case "unicode":
                return System.Text.Encoding.Unicode;
#pragma warning disable SYSLIB0001
            case "utf7":
                return System.Text.Encoding.UTF7;
#pragma warning restore SYSLIB0001
            case "utf8":
                return System.Text.Encoding.UTF8;
            default:
                return null;
        }
    }

    /// <summary>Absorbed private/functions/Get-ObjectNameParts.ps1 (only the members the
    /// caller reads); preserves the fix-char substitution quirks verbatim.</summary>
    internal static ObjectNameParts GetObjectNameParts(string objectName)
    {
        //Object names with a ']' charcter in the name need to be handeled
        //Require charcter to be escaped by being duplicated as per T-SQL QuoteName function
        //These need to be temporarily replaced to allow the object name to be parsed.
        string t = objectName ?? "";
        string? fixChar = null;
        if (t.Contains("]]"))
        {
            for (int i = 0; i <= 65535; i++)
            {
                string candidate = ((char)i).ToString();
                if (!t.Contains(candidate))
                {
                    fixChar = candidate;
                    t = t.Replace("]]", candidate);
                    break;
                }
            }
        }
        //If the dbo schema is empty as in database..table, it has to filled temorarily to let the regex work.
        string? fixSchema = null;
        if (t.Contains(".."))
        {
            for (int i = 0; i <= 65535; i++)
            {
                string candidate = ((char)i).ToString();
                if (!t.Contains(candidate))
                {
                    fixSchema = candidate;
                    t = t.Replace("..", "." + candidate + ".");
                    break;
                }
            }
        }
        MatchCollection splitName = Regex.Matches(t, "(\\[.+?\\])|([^\\.]+)");
        int dotcount = splitName.Count;

        string? dbName = null;
        string? schema = null;
        string? name = null;
        bool parsed;

        switch (dotcount)
        {
            case 1:
                name = t;
                parsed = true;
                break;
            case 2:
                schema = splitName[0].Value;
                name = splitName[1].Value;
                parsed = true;
                break;
            case 3:
                dbName = splitName[0].Value;
                schema = splitName[1].Value;
                name = splitName[2].Value;
                parsed = true;
                break;
            default:
                parsed = false;
                break;
        }

        if (IsBracketed(dbName))
        {
            dbName = dbName!.Substring(1, dbName.Length - 2);
            if (fixChar is not null)
                dbName = dbName.Replace(fixChar, "]");
        }
        if (IsBracketed(schema))
        {
            schema = schema!.Substring(1, schema.Length - 2);
            if (fixChar is not null)
                schema = schema.Replace(fixChar, "]");
        }
        if (IsBracketed(name))
        {
            name = name!.Substring(1, name.Length - 2);
            if (fixChar is not null)
                name = name.Replace(fixChar, "]");
        }

        if (fixSchema is not null)
        {
            if (!string.IsNullOrEmpty(dbName))
                dbName = dbName!.Replace(fixSchema, "");
            if (schema == fixSchema)
                schema = null;
            else if (!string.IsNullOrEmpty(schema))
                schema = schema!.Replace(fixSchema, "");
            if (!string.IsNullOrEmpty(name))
                name = name!.Replace(fixSchema, "");
        }

        return new ObjectNameParts { Database = dbName, Schema = schema, Name = name, Parsed = parsed };
    }

    /// <summary>PS: $value -like "[[]*[]]".</summary>
    private static bool IsBracketed(string? value)
    {
        return value is not null && value.Length >= 2 && value[0] == '[' && value[value.Length - 1] == ']';
    }

    /// <summary>Absorbed New-SqlTable begin-block helper: creates the table with
    /// nvarchar(MAX) columns. Returns false when its internal Stop-Function -Continue ran
    /// (the PS continue unwound dynamically to the caller's instance loop).</summary>
    private bool CreateSqlTable(string path, string delimiter, bool firstRowHeader)
    {
        CsvReaderOptions options = new();
        options.HasHeaderRow = firstRowHeader;
        options.Delimiter = delimiter;
        options.Quote = Quote;
        options.Escape = Escape;
        options.Comment = Comment;
        options.TrimmingOptions = (Csv.ValueTrimmingOptions)Enum.Parse(typeof(Csv.ValueTrimmingOptions), TrimmingOption, true);
        options.BufferSize = BufferSize;
        options.Encoding = MapEncoding(Encoding);
        if (LanguagePrimitives.IsTrue(NullValue))
            options.NullValue = NullValue;
        options.MaxDecompressedSize = MaxDecompressedSize;
        options.SkipRows = SkipRows;
        options.DuplicateHeaderBehavior = (DuplicateHeaderBehavior)Enum.Parse(typeof(DuplicateHeaderBehavior), DuplicateHeaderBehavior, true);
        options.AllowMultilineFields = _allowMultilineFields;

        string[] columns;
        CsvDataReader? reader = null;
        try
        {
            reader = new CsvDataReader(path, options);
            columns = reader.GetFieldHeaders();
        }
        finally
        {
            // PS: the finally calls $reader.Close() unconditionally. When the constructor
            // threw, dynamic scoping resolves $reader from the FUNCTION scope: a previous
            // iteration's disposed import reader (harmless double-close, the constructor
            // exception propagates), or - first iteration - $null, where the null-valued
            // call replaces the original exception (codex r1 F4).
            if (reader is not null)
            {
                reader.Close();
                reader.Dispose();
            }
            else if (_reader is not null)
            {
                _reader.Close();
                _reader.Dispose();
            }
            else
            {
                throw new RuntimeException("You cannot call a method on a null-valued expression.");
            }
        }

        List<string> sqldatatypes = new();
        foreach (string column in columns)
            sqldatatypes.Add("[" + column + "] nvarchar(MAX)");

        string sql = "BEGIN CREATE TABLE [" + _schema + "].[" + _table + "] (" + string.Join(" NULL,", sqldatatypes) + ") END";
        SqlCommand sqlcmd = new(sql, _sqlconn, _transaction);

        try
        {
            sqlcmd.ExecuteNonQuery();
        }
        catch (Exception ex)
        {
            string errormessage = MethodCallMessage("ExecuteNonQuery", 0, ex);
            StopFunction("Failed to execute " + sql + ". \nDid you specify the proper delimiter? \n" + errormessage, continueLoop: true);
            return false;
        }

        WriteMessage(MessageLevel.Verbose, "Successfully created table " + _schema + "." + _table + " with the following column definitions:\n " + string.Join("\n ", sqldatatypes));
        WriteMessage(MessageLevel.Verbose, "This is inefficient but allows the script to import without issues.");
        WriteMessage(MessageLevel.Verbose, "Consider creating the table first using best practices if the data will be used in production.");
        return true;
    }

    /// <summary>Absorbed New-SqlTableWithInferredSchema begin-block helper. Returns false
    /// when its internal Stop-Function -Continue ran.</summary>
    private bool CreateSqlTableWithInferredSchema(List<InferredColumn> inferredColumns)
    {
        string sql = CsvSchemaInference.GenerateCreateTableStatement(inferredColumns, _table, _schema);

        WriteMessage(MessageLevel.Debug, sql);

        SqlCommand sqlcmd = new(sql, _sqlconn, _transaction);

        try
        {
            sqlcmd.ExecuteNonQuery();
        }
        catch (Exception ex)
        {
            string errormessage = MethodCallMessage("ExecuteNonQuery", 0, ex);
            StopFunction("Failed to execute " + sql + ". \nDid you specify the proper delimiter? \n" + errormessage, continueLoop: true);
            return false;
        }

        List<string> typeParts = new();
        foreach (InferredColumn column in inferredColumns)
            typeParts.Add("[" + column.ColumnName + "] " + column.SqlDataType + " " + (column.IsNullable ? "NULL" : "NOT NULL"));
        WriteMessage(MessageLevel.Verbose, "Successfully created table " + _schema + "." + _table + " with inferred column types:\n  " + string.Join("\n  ", typeParts));
        return true;
    }

    /// <summary>Absorbed Get-InferredSchema begin-block helper.</summary>
    private List<InferredColumn> GetInferredSchema(string path, CsvReaderOptions csvOptions, int sampleRows, bool fullScan)
    {
        List<InferredColumn> inferredColumns;
        if (fullScan)
        {
            // Full scan with progress callback
            Action<double> progressCallback = progress =>
            {
                int percent = Convert.ToInt32(progress * 100);
                ProgressBridge.Write(this, 2, "Analyzing column types", percent + "% complete", percentComplete: percent);
            };

            inferredColumns = CsvSchemaInference.InferSchema(path, csvOptions, progressCallback);

            ProgressBridge.Write(this, 2, "Analyzing column types", "Complete", completed: true);
        }
        else
        {
            // Sample-based inference
            WriteMessage(MessageLevel.Verbose, "Sampling first " + sampleRows + " rows for type inference...");
            inferredColumns = CsvSchemaInference.InferSchemaFromSample(path, csvOptions, sampleRows);
        }

        return inferredColumns;
    }

    /// <summary>Absorbed Optimize-ColumnSize begin-block helper: shrinks nvarchar(MAX)/varchar(MAX)
    /// columns to padded sizes after an AutoCreateTable import.</summary>
    private void OptimizeColumnSize(SqlConnection sqlConn, string schema, string table)
    {
        WriteMessage(MessageLevel.Verbose, "Optimizing column sizes for " + schema + "." + table + "...");

        // Get column names and their current types from the table
        string getColumnsSql = "SELECT c.name AS ColumnName, t.name AS TypeName\n"
            + "FROM sys.columns c\n"
            + "INNER JOIN sys.types t ON c.user_type_id = t.user_type_id\n"
            + "WHERE c.object_id = OBJECT_ID(@tableName)\n"
            + "  AND t.name IN ('nvarchar', 'varchar')\n"
            + "  AND c.max_length = -1";
        SqlCommand sqlcmd = new(getColumnsSql, sqlConn);
        sqlcmd.Parameters.AddWithValue("tableName", "[" + schema + "].[" + table + "]");

        // PS @{} literal: case-insensitive hashtable, bucket enumeration order.
        Hashtable columns = PsHashtable.Literal(0);
        SqlDataReader reader;
        try
        {
            reader = sqlcmd.ExecuteReader();
        }
        catch (Exception ex)
        {
            throw new RuntimeException(MethodCallMessage("ExecuteReader", 0, ex), ex);
        }
        while (reader.Read())
            columns[reader["ColumnName"]] = reader["TypeName"];
        reader.Close();

        if (columns.Count == 0)
        {
            WriteMessage(MessageLevel.Verbose, "No nvarchar(MAX)/varchar(MAX) columns to optimize.");
            return;
        }

        // Build MAX(LEN()) query for all columns
        List<object> columnNames = new();
        foreach (object columnKey in columns.Keys)
            columnNames.Add(columnKey);
        List<string> maxLenSelects = new();
        foreach (object columnKey in columnNames)
            maxLenSelects.Add("MAX(LEN([" + columnKey + "])) AS [" + columnKey + "]");
        string maxLenSql = "SELECT " + string.Join(", ", maxLenSelects) + " FROM [" + schema + "].[" + table + "]";

        sqlcmd = new SqlCommand(maxLenSql, sqlConn);
        try
        {
            reader = sqlcmd.ExecuteReader();
        }
        catch (Exception ex)
        {
            throw new RuntimeException(MethodCallMessage("ExecuteReader", 0, ex), ex);
        }

        Hashtable maxLengths = PsHashtable.Literal(0);
        if (reader.Read())
        {
            foreach (object columnKey in columnNames)
            {
                string col = (string)columnKey;
                object val = reader[col];
                if (val is DBNull || val is null)
                    maxLengths[col] = 1;
                else
                    maxLengths[col] = Convert.ToInt32(val);
            }
        }
        reader.Close();

        // ALTER each column to appropriate size, preserving original type
        foreach (object columnKey in columnNames)
        {
            string col = (string)columnKey;
            int maxLen = (int)maxLengths[col]!;
            if (maxLen == 0)
                maxLen = 1;

            // Preserve the original column type (nvarchar stays nvarchar, varchar stays varchar)
            // This is safer than trying to detect Unicode - no risk of data loss
            string baseType = (string)columns[col]!;
            int maxAllowed = PsString.Eq(baseType, "nvarchar") ? 4000 : 8000;

            if (maxLen > maxAllowed)
            {
                // Keep as MAX if truly needed
                WriteMessage(MessageLevel.Verbose, "Column [" + col + "] requires " + baseType + "(MAX) - max length is " + maxLen);
                continue;
            }

            // Add padding to the length to allow for future data that may be slightly longer
            // This prevents issues when re-importing to the same table with -Truncate
            // Round up to common sizes: 16, 32, 64, 128, 256, 512, 1024, 2048, 4000/8000
            int paddedLen;
            if (maxLen <= 16)
                paddedLen = 16;
            else if (maxLen <= 32)
                paddedLen = 32;
            else if (maxLen <= 64)
                paddedLen = 64;
            else if (maxLen <= 128)
                paddedLen = 128;
            else if (maxLen <= 256)
                paddedLen = 256;
            else if (maxLen <= 512)
                paddedLen = 512;
            else if (maxLen <= 1024)
                paddedLen = 1024;
            else if (maxLen <= 2048)
                paddedLen = 2048;
            else
                paddedLen = maxAllowed;
            // Ensure we don't exceed the max allowed
            if (paddedLen > maxAllowed)
                paddedLen = maxAllowed;

            string newType = baseType + "(" + paddedLen + ")";
            // SQL Server 2008 R2 and earlier require NULL/NOT NULL in ALTER COLUMN
            // Original columns were nvarchar(MAX) NULL, so we preserve NULL
            string alterSql = "ALTER TABLE [" + schema + "].[" + table + "] ALTER COLUMN [" + col + "] " + newType + " NULL";

            WriteMessage(MessageLevel.Verbose, "Optimizing [" + col + "]: nvarchar(MAX) -> " + newType + " (max data length: " + maxLen + ", padded to: " + paddedLen + ")");

            try
            {
                sqlcmd = new SqlCommand(alterSql, sqlConn);
                sqlcmd.ExecuteNonQuery();
            }
            catch (Exception ex)
            {
                WriteMessage(MessageLevel.Warning, "Failed to optimize column [" + col + "]: " + MethodCallMessage("ExecuteNonQuery", 0, ex));
            }
        }

        WriteMessage(MessageLevel.Verbose, "Column size optimization complete.");
    }

    /// <summary>Absorbed ConvertTo-DotnetType begin-block helper (PS switch is case-insensitive;
    /// INFORMATION_SCHEMA reports lowercase names).</summary>
    private static Type ConvertToDotnetType(string dataType)
    {
        switch (dataType?.ToLowerInvariant())
        {
            case "bigint":
                return typeof(long);
            case "binary":
            case "varbinary":
                return typeof(byte[]);
            case "bit":
                return typeof(bool);
            case "char":
            case "varchar":
            case "nchar":
            case "nvarchar":
                return typeof(string);
            case "datetime":
            case "smalldatetime":
            case "date":
            case "time":
            case "datetime2":
                return typeof(DateTime);
            case "decimal":
            case "numeric":
            case "money":
            case "smallmoney":
                return typeof(decimal);
            case "float":
                return typeof(double);
            case "int":
                return typeof(int);
            case "real":
                return typeof(float);
            case "uniqueidentifier":
                return typeof(Guid);
            case "smallint":
                return typeof(short);
            case "tinyint":
                return typeof(byte);
            case "xml":
                return typeof(string);
            default:
                // PS: throw "Unsupported SMO DataType: $($DataType)"
                throw new RuntimeException("Unsupported SMO DataType: " + dataType);
        }
    }

    /// <summary>Absorbed Get-TableDefinitionFromInfoSchema begin-block helper. A failure
    /// yields an empty (or partial) result - callers report back the error if it is empty;
    /// like the PS source there is no finally, so a mid-enumeration failure leaves the
    /// data reader open.</summary>
    private List<TableColumnDef> GetTableDefinitionFromInfoSchema(string table, string schema, SqlConnection sqlconn, SqlTransaction? transaction)
    {
        string query = "SELECT c.COLUMN_NAME, c.DATA_TYPE, c.ORDINAL_POSITION - 1 FROM INFORMATION_SCHEMA.COLUMNS AS c WHERE TABLE_SCHEMA = @schema AND TABLE_NAME = @table;";
        SqlCommand sqlcmd = new(query, sqlconn, transaction);
        sqlcmd.Parameters.AddWithValue("schema", schema);
        sqlcmd.Parameters.AddWithValue("table", table);

        List<TableColumnDef> result = new();
        try
        {
            SqlDataReader reader = sqlcmd.ExecuteReader();
            while (reader.Read())
            {
                result.Add(new TableColumnDef
                {
                    Name = Convert.ToString(reader[0], CultureInfo.InvariantCulture) ?? "",
                    DataType = Convert.ToString(reader[1], CultureInfo.InvariantCulture) ?? "",
                    Index = Convert.ToInt32(reader[2])
                });
            }
            reader.Close();
        }
        catch
        {
            // callers report back the error if $result is empty
        }

        return result;
    }

    /// <summary>Absorbed private/functions/Get-AdjustedTotalRowsCopied.ps1: adjusts for the
    /// legacy 4-byte rows-copied counter wrapping (dataplat/dbatools#6927).</summary>
    internal static long GetAdjustedTotalRowsCopied(long reportedRowsCopied, long previousRowsCopied)
    {
        long newRowCountAdded = 0;

        if (reportedRowsCopied > 0)
        {
            if (previousRowsCopied >= 0)
            {
                newRowCountAdded = reportedRowsCopied - previousRowsCopied;
            }
            else
            {
                // integer wrap just changed from negative to positive
                newRowCountAdded = Math.Abs(previousRowsCopied) + reportedRowsCopied;
            }
        }
        else if (reportedRowsCopied < 0)
        {
            if (previousRowsCopied >= 0)
            {
                // integer wrap just changed from positive to negative
                newRowCountAdded = (int.MaxValue - previousRowsCopied) + Math.Abs(int.MinValue - reportedRowsCopied) + 1;
            }
            else
            {
                newRowCountAdded = Math.Abs(previousRowsCopied) - Math.Abs(reportedRowsCopied);
            }
        }

        return newRowCountAdded;
    }

    /// <summary>Absorbed private/functions/Get-BulkRowsCopiedCount.ps1: reflection read of
    /// SqlBulkCopy's private _rowsCopied field, -1 on any failure - including a null
    /// instance, which the source treats the same as any other reflection failure.</summary>
    internal static int GetBulkRowsCopiedCount(SqlBulkCopy? bulkCopy)
    {
        FieldInfo? rowsCopiedField = typeof(SqlBulkCopy).GetField("_rowsCopied", BindingFlags.NonPublic | BindingFlags.GetField | BindingFlags.Instance);
        try
        {
            return (int)LanguagePrimitives.ConvertTo(rowsCopiedField!.GetValue(bulkCopy), typeof(int), CultureInfo.InvariantCulture);
        }
        catch
        {
            return -1;
        }
    }
}
