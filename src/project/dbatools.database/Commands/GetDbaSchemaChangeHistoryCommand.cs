#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Retrieves DDL schema-change history from the default trace, directly through SMO and SqlClient (port of
// public/Get-DbaSchemaChangeHistory.ps1). Earlier Claude work consulted: dbatools.library dace2ee2 and
// refs/fleet/imported/native-batch2 (see the item notes).
/// <summary>Retrieves DDL change history from the SQL Server default system trace</summary>
[Cmdlet(VerbsCommon.Get, "DbaSchemaChangeHistory")]
public sealed class GetDbaSchemaChangeHistoryCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances (SQL 2005+).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Only return schema changes since this datetime.</summary>
    [Parameter(Position = 4)]
    public DbaDateTime? Since { get; set; }

    /// <summary>Only return schema changes for the specified object(s).</summary>
    [Parameter(Position = 5)]
    public string[]? Object { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private const string TraceFileQuery = "SELECT path FROM sys.traces WHERE is_default = 1";

    // The pinned statement, with the trace path as @tracePath instead of an unescaped string literal.
    private const string ChangeQuery = @"SELECT  SERVERPROPERTY('MachineName') ComputerName
                      , ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') InstanceName
                      , SERVERPROPERTY('ServerName') SqlInstance
                      , tt.DatabaseName DatabaseName
                      , tt.StartTime DateModified
                      , tt.SessionLoginName LoginName
                      , tt.NTUserName UserName
                      , tt.ApplicationName ApplicationName
                      , CASE tt.EventClass
                             WHEN '46' THEN 'Create'
                             WHEN '47' THEN 'Drop'
                             WHEN '164' THEN 'Alter'
                        END DDLOperation
                      , tt.ObjectName Object
                      , ISNULL(tsv.subclass_name, 'Unknown') ObjectType
                FROM    ::fn_trace_gettable(@tracePath,DEFAULT) tt
                        LEFT JOIN sys.trace_subclass_values tsv ON
                            tsv.trace_event_id = tt.EventClass
                            AND tsv.subclass_value = tt.ObjectType
                            AND tsv.trace_column_id = 28
                WHERE   tt.ObjectType NOT IN ( 21587 )
                        AND tt.DatabaseID = DB_ID()
                        AND tt.EventSubClass = 0";

    /// <summary>SMO's ExceptionTemplates.ExecuteWithResults operation text.</summary>
    private const string ExecuteWithResultsOperation = "Execute with results";

    /// <summary>SMO's ConnectionInfo ExecutionFailure text.</summary>
    private const string ExecutionFailureMessage = "An exception occurred while executing a Transact-SQL statement or batch.";

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;

            // PS: try { Connect-DbaInstance -MinimumVersion 9 } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-unsupported: Azure SQL Database has no SQL Trace (sys.traces is SQL Server and Managed
            // Instance only), so it is refused as Connect-DbaInstance -AzureUnsupported does.
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 9, azureUnsupported: true);
            if (server is null)
                continue;

            List<object?> tracePaths = ReadTracePaths(server);
            // PS: if (!$TraceFile -or !$TraceFile.Path), where one row reads as its own path.
            object? tracePath = tracePaths.Count == 1 ? tracePaths[0] : tracePaths.ToArray();
            if (tracePaths.Count == 0 || !LanguagePrimitives.IsTrue(tracePath))
            {
                WriteMessage(MessageLevel.Warning, String.Format(
                    "No default trace file found on {0}. Schema change tracking requires the default trace to be enabled.", instance));
                continue;
            }
            // PS: '$($TraceFile.path)' joins several paths with spaces.
            string traceText = tracePaths.Count == 1
                ? Convert.ToString(tracePaths[0], CultureInfo.InvariantCulture) ?? ""
                : String.Join(" ", tracePaths.ConvertAll(path => Convert.ToString(path, CultureInfo.InvariantCulture) ?? ""));

            // Upstream correction (dead parameter): the pinned help documents wildcards for -Database, which
            // the pinned literal -in never honoured. A value equal to a real database name of this instance
            // stays literal; -ExcludeDatabase documents no wildcards and stays literal.
            WildcardNameMatcher databaseMatcher = NativeDatabaseSelection.CreateInOperandMatcher(Database, true,
                NativeDatabaseSelection.DatabaseNames(server));
            List<SmoDatabase> databases = new();
            foreach (SmoDatabase candidate in server.Databases)
            {
                // PS: if ($Database) { Where-Object Name -in $database }; if ($ExcludeDatabase) { Where-Object Name -notin $ExcludeDatabase }
                if (LanguagePrimitives.IsTrue(Database) && !databaseMatcher.Matches(candidate.Name))
                    continue;
                if (LanguagePrimitives.IsTrue(ExcludeDatabase) && NativeDatabaseSelection.ContainsInOperand(ExcludeDatabase, candidate.Name))
                    continue;
                databases.Add(candidate);
            }

            foreach (SmoDatabase database in databases)
            {
                if (Interrupted)
                    return;
                // The pinned function reports an inaccessible database but still queries it.
                if (!database.IsAccessible)
                    WriteMessage(MessageLevel.Verbose, String.Format("{0} is not accessible, skipping", database.Name));

                string sql = BuildSql();
                WriteMessage(MessageLevel.Verbose, String.Format("Querying Database {0} on {1}", database, instance));
                // The statement text with its parameter names; the values travel as SqlParameter.
                WriteMessage(MessageLevel.Debug, String.Format("SQL: {0}", sql));

                DataTable results;
                try
                {
                    // PS: $db.Query($sql) - the Database.Query script method returns ExecuteWithResults(...).Tables[0].
                    results = QueryDatabase(database, sql, BuildParameters(traceText));
                }
                catch (Exception ex)
                {
                    // No try encloses $db.Query in the pinned function, so the fault only ends this statement.
                    // caller-try: continue -- an unqueryable database (often offline) is reported as an error and no row is emitted for it; later databases are still read correctly
                    WriteError(DatabaseQueryFaultRecord(ex)); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
                    continue;
                }

                foreach (DataRow row in results.Rows)
                {
                    // PS: | Select-DefaultView -Property ComputerName, ..., ObjectType
                    PSObject output = PSObject.AsPSObject(row);
                    OutputHelper.SetDefaultDisplayPropertySet(output,
                        "ComputerName", "InstanceName", "SqlInstance", "DatabaseName", "DateModified", "LoginName",
                        "UserName", "ApplicationName", "DDLOperation", "Object", "ObjectType");
                    WriteObject(output);
                }
            }
        }
    }

    /// <summary>PS: $server.Query($TraceFileQuery) | Select-Object Path, then $TraceFile.Path.</summary>
    private List<object?> ReadTracePaths(Server server)
    {
        DataTable table;
        try
        {
            table = server.ConnectionContext.ExecuteWithResults(TraceFileQuery).Tables[0];
        }
        catch (Exception ex)
        {
            // No try encloses this Query call in the pinned function; a cmdlet cannot observe the caller's try/trap.
            // caller-try: terminate -- continuing would report a missing default trace or read the previous instance's trace path
            ThrowTerminatingError(ServerQueryFaultRecord(ex)); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
            return new List<object?>();
        }
        List<object?> paths = new();
        foreach (DataRow row in table.Rows)
            paths.Add(row["path"]);
        return paths;
    }

    /// <summary>
    /// The pinned statement text. Upstream correction (unsafe change): the pinned function places the trace path,
    /// -Since and every -Object value into string literals unescaped, so a quote in a value breaks the statement or
    /// runs as SQL. Here they are @tracePath, @Since and @object0..@objectN.
    /// </summary>
    private string BuildSql()
    {
        string sql = ChangeQuery;
        // PS: if ($null -ne $since) { AND tt.StartTime>'$Since' }. The same text travels as the nvarchar @Since,
        // which the server converts to datetime by the same implicit rules as the pinned literal.
        if (Since is not null)
            sql = sql + " AND tt.StartTime>@Since ";
        // PS: $null -ne $object is a scalar test with $null on the left, so an empty array still applies; its
        // empty join is IN (''), kept as one empty-string parameter.
        if (Object is not null)
        {
            int count = Math.Max(1, Object.Length);
            string[] names = new string[count];
            for (int index = 0; index < count; index++)
                names[index] = "@object" + index.ToString(CultureInfo.InvariantCulture);
            sql = sql + " AND tt.ObjectName IN (" + String.Join(",", names) + ") ";
        }
        sql = sql + " ORDER BY tt.StartTime ASC";
        return sql;
    }

    /// <summary>
    /// The values BuildSql refers to, each nvarchar. -Since is its DbaDateTime text, as PowerShell expands it
    /// (DbaDateTime is not IFormattable, so its ToString()); a null -Object element joins as an empty string.
    /// </summary>
    private List<SqlParameter> BuildParameters(string tracePath)
    {
        List<SqlParameter> parameters = new();
        parameters.Add(new SqlParameter("@tracePath", SqlDbType.NVarChar, 4000) { Value = tracePath });
        if (Since is not null)
            parameters.Add(new SqlParameter("@Since", SqlDbType.NVarChar, -1) { Value = Since.ToString() });
        if (Object is not null)
        {
            if (Object.Length == 0)
                parameters.Add(new SqlParameter("@object0", SqlDbType.NVarChar, -1) { Value = "" });
            for (int index = 0; index < Object.Length; index++)
            {
                parameters.Add(new SqlParameter("@object" + index.ToString(CultureInfo.InvariantCulture), SqlDbType.NVarChar, -1)
                {
                    Value = Object[index] ?? ""
                });
            }
        }
        return parameters;
    }

    /// <summary>
    /// Database.ExecuteWithResults with parameters, first table: the batch runs on the shared server connection as
    /// USE of the database followed by the statement. A parameterized command runs through sp_executesql, so the
    /// USE lasts for the batch only. A failure is wrapped as SMO wraps it (FailedOperationException around
    /// ExecutionFailureException around the provider error).
    /// </summary>
    private static DataTable QueryDatabase(SmoDatabase database, string query, List<SqlParameter> parameters)
    {
        ServerConnection connection = database.Parent.ConnectionContext;
        bool connected = false;
        try
        {
            if (!connection.IsOpen)
            {
                connection.Connect();
                connected = true;
            }
        }
        catch (Exception failure)
        {
            throw new FailedOperationException(ExecuteWithResultsOperation, database, failure);
        }
        try
        {
            string useDatabase = "USE [" + database.Name.Replace("]", "]]") + "];" + Environment.NewLine;
            using SqlCommand command = connection.SqlConnectionObject.CreateCommand();
            command.CommandText = useDatabase + query;
            command.CommandTimeout = connection.StatementTimeout;
            foreach (SqlParameter parameter in parameters)
                command.Parameters.Add(parameter);
            DataSet results = new() { Locale = CultureInfo.InvariantCulture };
            using (SqlDataAdapter adapter = new(command))
                adapter.Fill(results);
            return results.Tables[0];
        }
        catch (Exception failure)
        {
            throw new FailedOperationException(ExecuteWithResultsOperation, database,
                new ExecutionFailureException(ExecutionFailureMessage, failure));
        }
        finally
        {
            // SMO disconnects a pooled connection it opened for the call (AutoDisconnectMode.DisconnectIfPooled).
            if (connected && !connection.NonPooledConnection && connection.AutoDisconnectMode == AutoDisconnectMode.DisconnectIfPooled)
                connection.Disconnect();
        }
    }

    /// <summary>
    /// The record a failed Database.Query call raises: the script method has no try, so the
    /// ExecuteWithResults method fault surfaces inside the ScriptMethodRuntimeException of "Query".
    /// </summary>
    private static ErrorRecord DatabaseQueryFaultRecord(Exception failure)
    {
        MethodInvocationException call = new(String.Format(
            "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
        MethodInvocationException fault = new(String.Format(
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", call.Message), call);
        return new ErrorRecord(fault, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }

    /// <summary>
    /// The record a failed Server.Query call raises: its catch concatenates the messages of the failure's
    /// exception chain without separators and throws that string, which the method binder reports as the
    /// ScriptMethodRuntimeException of 'Exception calling "Query" with "1" argument(s)'.
    /// </summary>
    private static ErrorRecord ServerQueryFaultRecord(Exception failure)
    {
        string message = String.Empty;
        Exception current = failure;
        while (current.InnerException != null)
        {
            message += current.Message;
            current = current.InnerException;
        }
        message += current.Message;
        MethodInvocationException call = new(String.Format(
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message, failure));
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }
}
