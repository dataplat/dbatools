#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Data;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using System.Text;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Copy-DbaSystemDbUserObject.ps1. The private helpers it calls are ported in place: Test-SqlSa,
// Get-DbaModule's query (with its default -ModifiedSince and -ExcludeSystemObjects), Get-ErrorMessage and the dbatools
// Server.Query and Database.Query script methods.
/// <summary>Copies user-created objects from system databases (master, msdb, model) between SQL Server instances.</summary>
[Cmdlet(VerbsCommon.Copy, "DbaSystemDbUserObject", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaSystemDbUserObjectCommand : DbaBaseCmdlet
{
    // ValidateNotNullOrEmpty is load-bearing even under Mandatory, which already rejects null and
    // an empty array on its own: it changes WHICH rejection happens. Without it the binder raises
    // ParameterArgumentValidationErrorEmptyArrayNotAllowed / ...NullNotAllowed, with it the
    // FullyQualifiedErrorId is plain ParameterArgumentValidationError.
    /// <summary>The source SQL Server instance holding the user objects. Requires sysadmin.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instances. Requires sysadmin on each.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [ValidateNotNullOrEmpty]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for the destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Drop objects that already exist on the destination before recreating them. Ignored in Classic mode.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>Use the legacy bulk SMO Transfer path instead of the per-object default. Emits no output.</summary>
    [Parameter]
    public SwitchParameter Classic { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private static readonly string[] SystemDatabases = { "master", "model", "msdb" };

    // Get-DbaModule -ExcludeSystemObjects: its default -ModifiedSince "1900-01-01" expands invariantly in the string.
    private const string ModuleSql = @"SELECT  DB_NAME() AS DatabaseName,
        so.name AS ModuleName,
        so.object_id ,
        SCHEMA_NAME(so.schema_id) AS SchemaName ,
        so.parent_object_id ,
        so.type ,
        so.type_desc ,
        so.create_date ,
        so.modify_date ,
        so.is_ms_shipped ,
        sm.definition,
         OBJECTPROPERTY(so.object_id, 'ExecIsStartUp') AS startup
        FROM sys.sql_modules sm
        LEFT JOIN sys.objects so ON sm.object_id = so.object_id
        WHERE so.modify_date >= '01/01/1900 00:00:00'
 AND so.is_ms_shipped = 0
 ORDER BY so.modify_date";

    private Server? _sourceServer;

    protected override void ProcessRecord()
    {
        _sourceServer = Connect(Source, SourceSqlCredential, continueLoop: false);
        if (_sourceServer is null)
            return;

        if (!IsSysadmin(_sourceServer))
        {
            StopFunction(String.Format(CultureInfo.InvariantCulture, "Not a sysadmin on {0}. Quitting.", Source));
            return;
        }

        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter destinstance in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server? destServer = Connect(destinstance, DestinationSqlCredential, continueLoop: true);
            if (destServer is null)
                continue;

            if (!IsSysadmin(destServer))
            {
                StopFunction(String.Format(CultureInfo.InvariantCulture, "Not a sysadmin on {0}", destinstance), continueLoop: true);
                continue;
            }

            foreach (string systemDb in SystemDatabases)
            {
                CancellationToken.ThrowIfCancellationRequested();
                if (Classic)
                    CopyClassic(destServer, destinstance, systemDb);
                else
                    CopyObjects(destServer, destinstance, systemDb);
            }
        }
    }

    // The default mode for one system database: user schemas, user tables, then the user modules.
    private void CopyObjects(Server destServer, DbaInstanceParameter destinstance, string systemDb)
    {
        SmoDatabase? smodb = _sourceServer!.Databases[systemDb];
        SmoDatabase? destdb = destServer.Databases[systemDb];
        // master, model and msdb exist on every instance.
        if (smodb is null || destdb is null)
            return;

        // PS: $smodb.Tables | Where-Object IsSystemObject -ne $true, read before any schema is copied.
        List<Table> tables = new();
        foreach (Table table in smodb.Tables)
        {
            if (!table.IsSystemObject)
                tables.Add(table);
        }
        List<Schema> schemas = new();
        foreach (Schema schema in smodb.Schemas)
        {
            if (!schema.IsSystemObject)
                schemas.Add(schema);
        }

        foreach (Schema schema in schemas)
        {
            CancellationToken.ThrowIfCancellationRequested();
            CopySchema(destServer, destdb, smodb, destinstance, systemDb, schema);
        }

        foreach (Table table in tables)
        {
            CancellationToken.ThrowIfCancellationRequested();
            CopyTable(destServer, destdb, smodb, destinstance, systemDb, table);
        }

        List<ModuleRow> userobjects = SourceModules(systemDb);
        WriteMessage(MessageLevel.Verbose, "Copying from " + systemDb);
        foreach (ModuleRow userobject in userobjects)
        {
            CancellationToken.ThrowIfCancellationRequested();
            CopyModule(destServer, destdb, smodb, destinstance, systemDb, userobject);
        }
    }

    // One pass of the pinned schema loop; every return is its continue.
    private void CopySchema(Server destServer, SmoDatabase destdb, SmoDatabase smodb, DbaInstanceParameter destinstance, string systemDb, Schema schema)
    {
        DateTime timestamp = DateTime.Now;
        string type = "User schema in " + systemDb;

        // PS: $destdb.Schemas | Where-Object Name -eq $schema.Name
        List<Schema> destschema = new();
        foreach (Schema candidate in destdb.Schemas)
        {
            if (LanguagePrimitives.Equals(candidate.Name, schema.Name, true))
                destschema.Add(candidate);
        }

        if (destschema.Count > 0)
        {
            if (!Force)
            {
                if (Approve(destinstance, String.Format(CultureInfo.InvariantCulture,
                    "Skipping schema {0} because it already exists on the destination instance. Use -Force to drop and recreate", schema)))
                {
                    Emit(destServer, schema, type, timestamp, "Skipped", "Already exists on destination");
                }
                return;
            }

            if (Approve(destinstance, String.Format(CultureInfo.InvariantCulture, "Dropping schema {0} in {1}", schema, systemDb)))
            {
                try
                {
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Force specified. Dropping {0} in {1} on {2}", schema, destdb, destinstance));
                    foreach (Schema existing in destschema)
                        existing.Drop();
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    Emit(destServer, schema, type, timestamp, "Failed", DropNotes(failure));
                    return;
                }
            }
        }

        Transfer transfer = new(smodb);
        transfer.CopyAllObjects = false;
        transfer.Options.WithDependencies = true;
        transfer.Options.ScriptOwner = true;
        transfer.ObjectList.Add(schema);
        if (Approve(destinstance, String.Format(CultureInfo.InvariantCulture, "Attempting to add schema {0} to {1}", schema.Name, systemDb)))
        {
            try
            {
                string sql = ScriptTransfer(transfer);
                WriteMessage(MessageLevel.Debug, sql);
                ServerQuery(destServer, sql, systemDb);
                Emit(destServer, schema, type, timestamp, "Successful", "May have also created dependencies");
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                Emit(destServer, schema, type, timestamp, "Failed", MessageService.GetErrorMessage(Caught(failure)));
            }
        }
    }

    // One pass of the pinned table loop; every return is its continue.
    private void CopyTable(Server destServer, SmoDatabase destdb, SmoDatabase smodb, DbaInstanceParameter destinstance, string systemDb, Table table)
    {
        DateTime timestamp = DateTime.Now;
        string type = "User table in " + systemDb;

        Table? desttable = destdb.Tables[table.Name, table.Schema];
        if (desttable is not null)
        {
            if (!Force)
            {
                if (Approve(destinstance, String.Format(CultureInfo.InvariantCulture,
                    "Skipping table {0} because it already exists on the destination instance. Use -Force to drop and recreate", desttable)))
                {
                    Emit(destServer, table, type, timestamp, "Skipped", "Already exists on destination");
                }
                return;
            }

            if (Approve(destinstance, String.Format(CultureInfo.InvariantCulture, "Dropping table {0} in {1}", table, systemDb)))
            {
                try
                {
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Force specified. Dropping {0} in {1} on {2}", table, destdb, destinstance));
                    desttable.Drop();
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    Emit(destServer, table, type, timestamp, "Failed", DropNotes(failure));
                    return;
                }
            }
        }

        Transfer transfer = new(smodb);
        transfer.CopyAllObjects = false;
        transfer.Options.WithDependencies = true;
        transfer.Options.Indexes = true;
        if (Approve(destinstance, String.Format(CultureInfo.InvariantCulture, "Attempting to add table {0} to {1}", table, systemDb)))
        {
            try
            {
                transfer.ObjectList.Add(table);
                string sql = ScriptTransfer(transfer);
                WriteMessage(MessageLevel.Debug, sql);
                ServerQuery(destServer, sql, systemDb);
                Emit(destServer, table, type, timestamp, "Successful", "May have also created dependencies");
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                Emit(destServer, table, type, timestamp, "Failed", MessageService.GetErrorMessage(Caught(failure)));
            }
        }
    }

    // One pass of the pinned module loop; every return is its continue.
    private void CopyModule(Server destServer, SmoDatabase destdb, SmoDatabase smodb, DbaInstanceParameter destinstance, string systemDb, ModuleRow userobject)
    {
        string name = String.Format(CultureInfo.InvariantCulture, "[{0}].[{1}]", userobject.SchemaName, userobject.Name);
        string? db = userobject.Database;
        string type = SqlTypeName(userobject.Type);
        string sql = userobject.Definition ?? "";
        DateTime timestamp = DateTime.Now;
        string objectType = type + " in " + systemDb;

        WriteMessage(MessageLevel.Debug, sql);
        try
        {
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Searching for {0} in {1} on {2}", name, db, destinstance));
            // PS: Get-DbaModule -SqlInstance $destServer -ExcludeSystemObjects -Database $db | Where-Object Name and Type match.
            // Correction schema-aware-match: the schema must match too, or a same-name module in another schema hides a
            // missing one as "Already exists on destination".
            bool found = false;
            foreach (ModuleRow candidate in ReadModules(destServer, db))
            {
                if (LanguagePrimitives.Equals(candidate.Name, userobject.Name, true) && LanguagePrimitives.Equals(candidate.Type, userobject.Type, true) &&
                    LanguagePrimitives.Equals(candidate.SchemaName, userobject.SchemaName, true))
                    found = true;
            }

            if (found)
            {
                WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Found {0} in {1} on {2}", name, db, destinstance));
                if (!Force)
                {
                    if (Approve(destinstance, String.Format(CultureInfo.InvariantCulture, "Object {0} already exists, skipping", name)))
                        Emit(destServer, name, objectType, timestamp, "Skipped", "Already exists on destination");
                    return;
                }

                object? smobject = SourceObject(smodb, userobject, name, includeFunctions: true);
                if (smobject is not null)
                {
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Force specified. Dropping {0} on {1} on {2} using SMO", smobject, destdb, destinstance));
                    Transfer dropTransfer = new(smodb);
                    dropTransfer.CopyAllObjects = false;
                    dropTransfer.Options.WithDependencies = true;
                    dropTransfer.ObjectList.Add(smobject);
                    dropTransfer.Options.ScriptDrops = true;
                    string dropsql = ScriptTransfer(dropTransfer);
                    WriteMessage(MessageLevel.Debug, dropsql);
                    if (Approve(destinstance, String.Format(CultureInfo.InvariantCulture, "Attempting to drop {0} {1} from {2}", type, name, systemDb)))
                        DatabaseQuery(destdb, dropsql);
                }
                else
                {
                    // Upstream corrections: the pinned "DROP FUNCTION $($userobject.name)" placed the server-supplied name
                    // unquoted into the statement (drop-function-quote) and without its schema, so it dropped the
                    // default schema's function of that name (drop-function-schema); both parts are bracket-quoted.
                    if (Approve(destinstance, String.Format(CultureInfo.InvariantCulture, "Attempting to drop {0} {1} from {2} using T-SQL", type, name, systemDb)))
                        DatabaseQuery(destdb, "DROP FUNCTION [" + (userobject.SchemaName ?? "").Replace("]", "]]") + "].[" + (userobject.Name ?? "").Replace("]", "]]") + "]");
                }

                if (Approve(destinstance, String.Format(CultureInfo.InvariantCulture, "Attempting to add {0} {1} to {2}", type, name, systemDb)))
                {
                    DatabaseQuery(destdb, sql);
                    Emit(destServer, name, objectType, timestamp, "Successful", null);
                }
            }
            else
            {
                if (Approve(destinstance, String.Format(CultureInfo.InvariantCulture, "Attempting to add {0} {1} to {2}", type, name, systemDb)))
                {
                    DatabaseQuery(destdb, sql);
                    Emit(destServer, name, objectType, timestamp, "Successful", null);
                }
            }
        }
        catch (Exception outer) when (outer is not PipelineStoppedException)
        {
            ErrorRecord outerRecord = Caught(outer);
            try
            {
                object? smobject = SourceObject(smodb, userobject, name, includeFunctions: false);
                if (smobject is not null)
                {
                    Transfer transfer = new(smodb);
                    transfer.CopyAllObjects = false;
                    transfer.Options.WithDependencies = true;
                    transfer.ObjectList.Add(smobject);
                    string script = ScriptTransfer(transfer);
                    WriteMessage(MessageLevel.Debug, script);
                    // The pinned message names $smoobject, a variable that does not exist, so it expands to nothing.
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Adding  on {0} on {1}", destdb, destinstance));
                    if (Approve(destinstance, String.Format(CultureInfo.InvariantCulture, "Attempting to add {0} {1} to {2}", type, name, systemDb)))
                        DatabaseQuery(destdb, script);
                    Emit(destServer, name, objectType, timestamp, "Successful", "May have also installed dependencies");
                }
                else
                {
                    Emit(destServer, name, objectType, timestamp, "Failed", MessageService.GetErrorMessage(outerRecord));
                }
            }
            catch (Exception inner) when (inner is not PipelineStoppedException)
            {
                Emit(destServer, name, objectType, timestamp, "Failed", MessageService.GetErrorMessage(Caught(inner)));
            }
        }
    }

    // The legacy mode: one Transfer of everything per system database. The pinned function swallows every error here
    // ("Don't care - long story having to do with duplicate stuff") and emits nothing.
    private void CopyClassic(Server destServer, DbaInstanceParameter destinstance, string systemDb)
    {
        SmoDatabase? sysdb = _sourceServer!.Databases[systemDb];
        // master, model and msdb exist on every instance.
        if (sysdb is null)
            return;

        Transfer transfer = new(sysdb);
        transfer.CopyAllObjects = false;
        transfer.CopyAllDatabaseTriggers = true;
        transfer.CopyAllDefaults = true;
        transfer.CopyAllRoles = true;
        transfer.CopyAllRules = true;
        transfer.CopyAllSchemas = true;
        transfer.CopyAllSequences = true;
        transfer.CopyAllSqlAssemblies = true;
        transfer.CopyAllSynonyms = true;
        transfer.CopyAllTables = true;
        transfer.CopyAllViews = true;
        transfer.CopyAllStoredProcedures = true;
        transfer.CopyAllUserDefinedAggregates = true;
        transfer.CopyAllUserDefinedDataTypes = true;
        transfer.CopyAllUserDefinedTableTypes = true;
        transfer.CopyAllUserDefinedTypes = true;
        transfer.CopyAllUserDefinedFunctions = true;
        transfer.CopyAllUsers = true;
        transfer.PreserveDbo = true;
        transfer.Options.AllowSystemObjects = false;
        transfer.Options.ContinueScriptingOnError = true;
        transfer.Options.IncludeDatabaseRoleMemberships = true;
        transfer.Options.Indexes = true;
        transfer.Options.Permissions = true;
        transfer.Options.WithDependencies = false;

        WriteMessage(MessageLevel.Output, "Copying from " + systemDb + ".");
        try
        {
            StringCollection sqlQueries = transfer.ScriptTransfer();
            foreach (string? sql in sqlQueries)
            {
                CancellationToken.ThrowIfCancellationRequested();
                WriteMessage(MessageLevel.Debug, sql ?? "");
                if (Approve(destinstance, sql ?? ""))
                {
                    try
                    {
                        ServerQuery(destServer, sql ?? "", systemDb);
                    }
                    catch (CaughtFault)
                    {
                        // The pinned catch ignores it: objects the destination already has fail here by design.
                    }
                }
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException && failure is not OperationCanceledException)
        {
            // The pinned outer catch ignores a failing ScriptTransfer the same way and copies nothing more from this database.
        }
    }

    // PS: Get-DbaModule -SqlInstance $sourceserver -Database $systemDb -ExcludeSystemObjects | Sort-Object Type
    private List<ModuleRow> SourceModules(string systemDb)
    {
        List<ModuleRow> rows;
        try
        {
            rows = ReadModules(_sourceServer!, systemDb);
        }
        catch (CaughtFault fault)
        {
            // caller-try: terminate -- the failing Query is a statement fault inside Get-DbaModule; continuing would copy none of this database's modules and still report success
            ThrowTerminatingError(fault.Record); // style-ok: cs-raw-streams statement fault of the nested Get-DbaModule call, outside Stop-Function
            return new List<ModuleRow>();
        }
        return rows.OrderBy(row => row.Type ?? "", StringComparer.CurrentCultureIgnoreCase).ToList();
    }

    // Get-DbaModule's process block for one database: Get-DbaDatabase, the accessibility check, then $server.Query.
    private List<ModuleRow> ReadModules(Server server, string? database)
    {
        List<ModuleRow> rows = new();
        if (String.IsNullOrEmpty(database))
            return rows;
        SmoDatabase? db = server.Databases[database];
        if (db is null)
            return rows;
        if (!db.IsAccessible)
        {
            WriteAttributedMessage("Get-DbaModule", MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture, "Database {0} is not accessible. Skipping.", db));
            return rows;
        }

        DataTable? table = ServerQuery(server, ModuleSql, db.Name);
        if (table is null)
            return rows;
        foreach (DataRow row in table.Rows)
        {
            rows.Add(new ModuleRow(Text(row["DatabaseName"]), Text(row["ModuleName"]), Text(row["SchemaName"]),
                Text(row["type_desc"]), Text(row["definition"])));
        }
        return rows;
    }

    // PS: the switch on $userobject.Type over the source database's collections. The functions are looked up by the
    // bracketed "[schema].[name]" as the pin does, which the default-schema indexer never finds.
    private static object? SourceObject(SmoDatabase smodb, ModuleRow userobject, string name, bool includeFunctions)
    {
        string? schema = userobject.SchemaName;
        string? objectName = userobject.Name;
        if (objectName is null || schema is null)
            return null;
        switch (userobject.Type?.ToUpperInvariant())
        {
            case "VIEW":
                return smodb.Views[objectName, schema];
            case "SQL_STORED_PROCEDURE":
                return smodb.StoredProcedures[objectName, schema];
            case "RULE":
                return smodb.Rules[objectName, schema];
            case "SQL_TRIGGER":
                // Database.Triggers holds DDL triggers and has no Item(name, schema): the pinned call fails to bind.
                throw new CaughtFault(new ErrorRecord(
                    new MethodException("Cannot find an overload for \"Item\" and the argument count: \"2\"."),
                    "MethodCountCouldNotFindBest", ErrorCategory.NotSpecified, null));
            case "SQL_TABLE_VALUED_FUNCTION":
            case "SQL_INLINE_TABLE_VALUED_FUNCTION":
            case "SQL_SCALAR_FUNCTION":
                return includeFunctions ? smodb.UserDefinedFunctions[name] : null;
            default:
                return null;
        }
    }

    // PS private get-sqltypename.
    private static string SqlTypeName(string? type)
    {
        switch (type?.ToUpperInvariant())
        {
            case "VIEW":
                return "view";
            case "SQL_TABLE_VALUED_FUNCTION":
                return "User table valued function";
            case "DEFAULT_CONSTRAINT":
                return "User default constraint";
            case "SQL_STORED_PROCEDURE":
                return "User stored procedure";
            case "RULE":
                return "User rule";
            case "SQL_INLINE_TABLE_VALUED_FUNCTION":
                return "User inline table valued function";
            case "SQL_TRIGGER":
                return "User server trigger";
            case "SQL_SCALAR_FUNCTION":
                return "User scalar function";
            default:
                return type ?? "";
        }
    }

    // PS: $transfer.ScriptTransfer(), passed on as "$sql" or to a [string] parameter, which joins the lines with $OFS.
    private static string ScriptTransfer(Transfer transfer)
    {
        StringCollection script;
        try
        {
            script = transfer.ScriptTransfer();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            throw new CaughtFault(MethodRecord(failure, "ScriptTransfer", 0));
        }
        List<string?> lines = new();
        foreach (string? line in script)
            lines.Add(line);
        return String.Join(" ", lines);
    }

    // PS: $server.Query($sql, $database), the dbatools Server.Query script method: the query runs through the database,
    // the previous database is put back, and a failure is rethrown as the concatenated messages of its exception chain.
    private DataTable? ServerQuery(Server server, string sql, string database)
    {
        ServerConnection connection = server.ConnectionContext;
        DataSet result;
        try
        {
            string previous = connection.CurrentDatabase;
            try
            {
                SmoDatabase? db = server.Databases[database];
                if (db is null)
                    throw new RuntimeException("You cannot call a method on a null-valued expression.");
                result = db.ExecuteWithResults(sql);
            }
            finally
            {
                RestoreDatabaseContext(connection, previous);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StringBuilder message = new();
            Exception current = failure;
            while (current.InnerException is not null)
            {
                message.Append(current.Message);
                current = current.InnerException;
            }
            message.Append(current.Message);
            string text = message.ToString();
            MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"2\" argument(s): \"{0}\"", text), new RuntimeException(text));
            throw new CaughtFault(new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null));
        }
        return result.Tables.Count > 0 ? result.Tables[0] : null;
    }

    // PS: $destdb.Query($sql), the dbatools Database.Query script method, which has no catch: the engine reports the
    // ExecuteWithResults failure as the script method's own.
    private void DatabaseQuery(SmoDatabase db, string sql)
    {
        ServerConnection connection = db.Parent.ConnectionContext;
        string previous = connection.CurrentDatabase;
        try
        {
            db.ExecuteWithResults(sql);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
            MethodInvocationException query = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", call.Message), call);
            throw new CaughtFault(new ErrorRecord(query, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null));
        }
        finally
        {
            RestoreDatabaseContext(connection, previous);
        }
    }

    // The finally block of the Query script methods.
    private void RestoreDatabaseContext(ServerConnection connection, string previous)
    {
        // Case-sensitive on purpose: database names follow the instance collation.
        if (String.IsNullOrEmpty(previous) || String.Equals(connection.CurrentDatabase, previous, StringComparison.Ordinal))
            return;
        try
        {
            connection.ExecuteNonQuery("USE [" + previous.Replace("]", "]]") + "]");
        }
        catch (Exception error) when (error is not PipelineStoppedException)
        {
            // Restoring the context is housekeeping and never becomes the outcome of the query.
            string text = String.Format(CultureInfo.InvariantCulture,
                "The database context could not be restored to [{0}]: Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{1}\"",
                previous, error.Message);
            try
            {
                WriteWarning(text); // style-ok: cs-raw-streams the source script method calls plain Write-Warning, not Write-Message
            }
            catch (ActionPreferenceStopException)
            {
                // The source forces this one warning to Continue, so a Stop preference must not end the command here.
            }
        }
    }

    // PS: Connect-DbaInstance -SqlInstance $instance -SqlCredential $credential in a try whose catch is
    // Stop-Function -Message "Failure" -Category ConnectionError (-Continue for a destination).
    // Upstream correction (wrong data): the system database user objects this command copies do not exist in Azure SQL
    // Database (only master and tempdb apply, and master takes no user objects there), so both connects refuse it as
    // Connect-DbaInstance -AzureUnsupported does instead of reporting a missing sysadmin role.
    private Server? Connect(DbaInstanceParameter target, PSCredential? credential, bool continueLoop)
    {
        SmoConnectionRequest request = new SmoConnectionRequest
        {
            Instance = target,
            SqlCredential = credential,
            AzureUnsupported = true,
            BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
            MessageCallback = (level, text) => WriteAttributedMessage("Connect-DbaInstance", level, text)
        };
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            Server server = ConnectionService.GetServer(request);
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            ErrorRecord record = new ErrorRecord(ex, "dbatools_Copy-DbaSystemDbUserObject", ErrorCategory.ConnectionError, target);
            StopFunction("Failure", target: target, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    // PS private Test-SqlSa on a Server: ConnectionContext.FixedServerRoles -match "SysAdmin"; any failure is $false.
    private static bool IsSysadmin(Server server)
    {
        try
        {
            return Regex.IsMatch(server.ConnectionContext.FixedServerRoles.ToString(), "SysAdmin", RegexOptions.IgnoreCase);
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            // Test-SqlSa: catch { return $false }
            return false;
        }
    }

    // PS: if ($Force) { $ConfirmPreference = 'none' } in begin, so -Force never prompts.
    private bool Approve(DbaInstanceParameter target, string action)
    {
        if (!Force)
            return ShouldProcess(target.ToString(), action);
        // Binary cmdlets share the caller's preference scope, unlike advanced functions.
        object? previous = SessionState.PSVariable.GetValue("ConfirmPreference");
        try
        {
            SessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
            return ShouldProcess(target.ToString(), action);
        }
        finally
        {
            SessionState.PSVariable.Set("ConfirmPreference", previous);
        }
    }

    // PS: $copyobject | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes
    // -TypeName MigrationObject. Name is the SMO schema or table itself for those rows, as the pin builds it.
    private void Emit(Server destServer, object? name, string type, DateTime timestamp, string status, string? notes)
    {
        PSObject result = new PSObject();
        result.Properties.Add(new PSNoteProperty("SourceServer", _sourceServer!.Name));
        result.Properties.Add(new PSNoteProperty("DestinationServer", destServer.Name));
        result.Properties.Add(new PSNoteProperty("Name", name));
        result.Properties.Add(new PSNoteProperty("Type", type));
        result.Properties.Add(new PSNoteProperty("Status", status));
        result.Properties.Add(new PSNoteProperty("Notes", notes));
        result.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(timestamp)));
        OutputHelper.InsertTypeName(result, "MigrationObject");
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        WriteObject(result);
    }

    // PS: $_.Exception.InnerException.InnerException.InnerException.Message for a failed Drop(), where $_.Exception is the
    // engine's MethodInvocationException around the SMO failure.
    private static string? DropNotes(Exception failure)
    {
        return failure.InnerException?.InnerException?.Message;
    }

    // The record a script catch receives for a failed .NET method call.
    private static ErrorRecord MethodRecord(Exception failure, string method, int argumentCount)
    {
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, argumentCount, failure.Message), failure);
        return new ErrorRecord(call, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    // $_ in the pinned catch blocks.
    private static ErrorRecord Caught(Exception failure)
    {
        if (failure is CaughtFault fault)
            return fault.Record;
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            return container.ErrorRecord;
        return new ErrorRecord(failure, failure.GetType().FullName ?? "", ErrorCategory.NotSpecified, null);
    }

    private static string? Text(object? value)
    {
        return value is null || value is DBNull ? null : Convert.ToString(value, CultureInfo.InvariantCulture);
    }

    // One Get-DbaModule row, as the copy reads it.
    private sealed class ModuleRow
    {
        public ModuleRow(string? database, string? name, string? schemaName, string? type, string? definition)
        {
            Database = database;
            Name = name;
            SchemaName = schemaName;
            Type = type;
            Definition = definition;
        }

        public string? Database { get; }
        public string? Name { get; }
        public string? SchemaName { get; }
        public string? Type { get; }
        public string? Definition { get; }
    }

    // A failure carrying the record the pinned catch block reads as $_.
    private sealed class CaughtFault : Exception
    {
        public CaughtFault(ErrorRecord record)
            : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        public ErrorRecord Record { get; }
    }
}
