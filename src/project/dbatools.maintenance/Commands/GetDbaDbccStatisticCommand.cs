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

// Port of public/Get-DbaDbccStatistic.ps1 at refs/pins/dbatools-2026-10-22: lists the statistics of each selected database, runs DBCC SHOW_STATISTICS for each and writes one object per row.
/// <summary>Retrieves statistics information from tables and indexed views for query performance analysis</summary>
/// <para>
/// Executes DBCC SHOW_STATISTICS to extract detailed information about statistics objects, including distribution histograms, density vectors, and header information. This helps DBAs diagnose query performance issues when the optimizer makes poor execution plan choices due to outdated or skewed statistics. You can analyze specific statistics objects or scan all statistics across databases to identify when UPDATE STATISTICS should be run. Returns different data sets based on the selected option: StatHeader shows when statistics were last updated and row counts, DensityVector reveals data uniqueness patterns, Histogram displays value distribution across column ranges, and StatsStream provides the raw binary statistics data.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbccStatistic -SqlInstance SQLServer2017
/// </code>
/// <para>
/// Will run the statement SHOW_STATISTICS WITH STAT_HEADER against all Statistics on all User Tables or views for every accessible database on instance SQLServer2017. Connects using Windows Authentication.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbccStatistic -SqlInstance SQLServer2017 -Database MyDb -Option DensityVector
/// </code>
/// <para>
/// Will run the statement SHOW_STATISTICS WITH DENSITY_VECTOR against all Statistics on all User Tables or views for database MyDb on instance SQLServer2017. Connects using Windows Authentication.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential sqladmin
/// PS C:\&gt; Get-DbaDbccStatistic -SqlInstance SQLServer2017 -SqlCredential $cred -Database MyDb -Object UserTable -Option Histogram
/// </code>
/// <para>
/// Will run the statement SHOW_STATISTICS WITH HISTOGRAM against all Statistics on table UserTable for database MyDb on instance SQLServer2017. Connects using sqladmin credential.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'Sql1','Sql2/sqlexpress' | Get-DbaDbccStatistic -SqlInstance SQLServer2017 -Database MyDb -Object 'dbo.UserTable' -Target MyStatistic -Option StatsStream
/// </code>
/// <para>
/// Runs the statement SHOW_STATISTICS('dbo.UserTable', 'MyStatistic') WITH STATS_STREAM against database MyDb on instances Sql1 and Sql2/sqlexpress. Connects using Windows Authentication.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: DBCC, Statistics
/// Author: Patrick Flynn (@sqllensman)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbccStatistic" />
[Cmdlet(VerbsCommon.Get, "DbaDbccStatistic")]
public sealed class GetDbaDbccStatisticCommand : DbaInstanceCmdlet
{
    // PS: the name the nested query's messages carry.
    private const string QueryRunner = "Invoke-DbaQuery";

    // PS: the name the nested connection's message carries.
    private const string ConnectRunner = "Connect-DbaInstance";

    // PS begin block: $stringBuilder.Append(...), constant text; the clause per -Option is in Clauses.
    private const string Template = "DBCC SHOW_STATISTICS(#options#) WITH NO_INFOMSGS";

    // PS begin block: $statList, the pinned text with its line breaks and indents, which -Verbose shows.
    private const string StatList =
        "SELECT Object, Target, name FROM\n" +
        "        (\n" +
        "            SELECT SCHEMA_NAME(o.schema_id) + '.' + o.name AS Object, st.name AS Target, o.name\n" +
        "            FROM sys.stats st\n" +
        "            INNER JOIN sys.objects o\n" +
        "                ON o.object_id = st.object_id\n" +
        "            WHERE o.type IN ('U', 'V')\n" +
        "        ) a\n" +
        "        ";

    // PS: $Option -eq compares without regard to case, and the binder's ValidateSet leaves the caller's case (option-lower).
    private static readonly Dictionary<string, string> Clauses = new(StringComparer.OrdinalIgnoreCase)
    {
        { "StatHeader", ", STAT_HEADER" },
        { "DensityVector", ", DENSITY_VECTOR" },
        { "Histogram", ", HISTOGRAM" },
        { "StatsStream", ", STATS_STREAM" }
    };

    // PS: the properties after Cmd per -Option, each $row[n] by its place.
    private static readonly Dictionary<string, string[]> RowProperties = new(StringComparer.OrdinalIgnoreCase)
    {
        { "StatHeader", new[] { "Name", "Updated", "Rows", "RowsSampled", "Steps", "Density", "AverageKeyLength", "StringIndex", "FilterExpression", "UnfilteredRows", "PersistedSamplePercent" } },
        { "DensityVector", new[] { "AllDensity", "AverageLength", "Columns" } },
        { "Histogram", new[] { "RangeHiKey", "RangeRows", "EqualRows", "DistinctRangeRows", "AverageRangeRows" } },
        { "StatsStream", new[] { "StatsStream", "Rows", "DataPages" } }
    };

    // The characters that make the server read a list's plain schema.name as something else.
    private static readonly char[] NameSplitters = { '.', '[', ']' };

    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies which databases to analyze for statistics information. Accepts multiple database names as an array.
    /// When omitted, the function processes all accessible databases on the instance, which is useful for instance-wide statistics analysis.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <para>
    /// Specifies the table or indexed view to analyze for statistics information. Use this to focus on a specific object rather than all tables in the database.
    /// Format two-part names as 'Schema.ObjectName' (e.g., 'dbo.Orders'). When specified without Target, all statistics on the object are analyzed.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? Object { get; set; }

    /// <para>
    /// Specifies the exact statistics object, index, or column name to analyze. Use this when you need to examine a specific statistic rather than all statistics on an object.
    /// Accepts statistics names (like '_WA_Sys_CustomerID'), index names (like 'IX_Orders_CustomerID'), or column names. Can be enclosed in brackets, quotes, or left unquoted.
    /// </para>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? Target { get; set; }

    /// <para>
    /// Controls which type of statistics data to return from DBCC SHOW_STATISTICS. Defaults to 'StatHeader' which shows when statistics were last updated and row counts.
    /// Use 'Histogram' to analyze data distribution patterns, 'DensityVector' to examine column uniqueness, or 'StatsStream' to get raw binary statistics data for advanced analysis.
    /// </para>
    [Parameter(Position = 5)]
    [PsStringCast]
    [ValidateSet("StatHeader", "DensityVector", "Histogram", "StatsStream")]
    public string Option { get; set; } = "StatHeader";

    // PS: declared and never read. The statement always says NO_INFOMSGS, so the suppression the help describes always holds (noinfo-true, noinfo-false).
    /// <para>
    /// Suppresses informational messages from DBCC SHOW_STATISTICS output, providing cleaner results focused only on the statistics data.
    /// Use this when running automated scripts or when you only need the statistics data without additional DBCC messaging.
    /// </para>
    [Parameter]
    public SwitchParameter NoInformationalMessages { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    /// <summary>Writes the statistics of each selected database of each instance.</summary>
    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            foreach (SmoDatabase db in SelectDatabases(server))
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Processing {0} on {1}", db, instance));

                if (!db.IsAccessible)
                {
                    StopFunction(String.Format("The database {0} is not accessible. Skipping.", db), continueLoop: true);
                    continue;
                }

                RunStatements(server, db, instance, ListStatements(server, db));
            }
        }
    }

    // PS: $dbs = $server.Databases, then under if ($Database): $dbs = $dbs | Where-Object Name -In $Database. A fault there leaves $dbs the whole collection, and the foreach walks that
    // again, so a connection that cannot read the list writes a record for each (denied-plain 2, denied-no-filter 1).
    private List<SmoDatabase> SelectDatabases(Server server)
    {
        if (LanguagePrimitives.IsTrue(Database) && TryWalkDatabases(server, true, out List<SmoDatabase> named))
            return named;
        TryWalkDatabases(server, false, out List<SmoDatabase> all);
        return all;
    }

    private bool TryWalkDatabases(Server server, bool byName, out List<SmoDatabase> selected)
    {
        selected = new List<SmoDatabase>();
        ErrorRecord fault;
        try
        {
            foreach (SmoDatabase db in server.Databases)
            {
                if (!byName || PsString.In(db.Name, Database!))
                    selected.Add(db);
            }
            return true;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            selected.Clear();
            string message = String.Format(CultureInfo.InvariantCulture,
                "The following exception occurred while trying to enumerate the collection: \"{0}\".", failure.Message);
            fault = new ErrorRecord(new ExtendedTypeSystemException(message, failure), "ExceptionInGetEnumerator", ErrorCategory.NotSpecified, null);
        }
        ReportFault(fault);
        return false;
    }

    // Accepted differences kept by the keep-going section's point 3: -EnableException stops here with this record, where the pin writes it and goes on (held-ee, denied-ee, object-tick-ee);
    // -ErrorAction Stop has the effect PowerShell gives WriteError (held-stop). $ErrorActionPreference set in the caller's scope acts on this WriteError as for any compiled command, where the
    // pin ignores it: harness-edits.md, "Script-scope preferences and the one-line connect warning", points 1 and 2.
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        // A plain call goes on; under a caller try the record stops the command, as the fault stops the pin's statement (held-try, denied-try).
        StatementFault.Surface(this, fault);
    }

    // PS: the three branches of the pin's foreach body. The first runs one statement on the caller's names with no list.
    private List<Statement> ListStatements(Server server, SmoDatabase db)
    {
        List<Statement> statements = new();
        if (TestBound(nameof(Object)) && TestBound(nameof(Target)))
        {
            string objectName = Object ?? String.Empty;
            string targetName = Target ?? String.Empty;
            statements.Add(new Statement(objectName, targetName, StatementText(objectName, UnenclosedTarget(targetName))));
            return statements;
        }

        string query = StatList;
        if (TestBound(nameof(Object)))
        {
            query += String.Format(" WHERE (Object = {0} or name = {0})", NameLiteral(Object ?? String.Empty));
            WriteMessage(MessageLevel.Verbose, "Query to execute: " + query);
        }
        else if (TestBound(nameof(Target)))
        {
            // Correction target-alone: the help has -Target pick a statistic, and only without -Object did the pin ignore it and read them all (target-alone).
            query += String.Format(" WHERE Target = {0}", NameLiteral(UnenclosedTarget(Target ?? String.Empty)));
            WriteMessage(MessageLevel.Verbose, "Query to execute: " + query);
        }

        // Correction stale-list: when the list query faults, the pin's assignment does not happen, so its foreach ran the list of the database before it against this one, under this
        // database's name (held-plain, held-object, held-silent). Here the record is written and this database has no statements.
        if (!TryReadList(server, db, query, out DataTable? list) || list is null)
            return statements;

        foreach (DataRow row in list.Rows)
        {
            // PS: "'$($statisticObj.Object)'": a value the engine leaves NULL reads as empty text, and the property keeps the cell.
            string objectName = Convert.ToString(row["Object"], CultureInfo.InvariantCulture) ?? String.Empty;
            string targetName = Convert.ToString(row["Target"], CultureInfo.InvariantCulture) ?? String.Empty;
            string tableName = Convert.ToString(row["name"], CultureInfo.InvariantCulture) ?? String.Empty;
            statements.Add(new Statement(row["Object"], row["Target"], StatementText(ListObjectText(objectName, tableName), targetName)));
        }
        return statements;
    }

    // Correction list-names-the-server-splits: the server reads the plain text of a listed table named with a dot as database.schema.table, and one holding a bracket as no table at all, so the
    // pin warned and read none of its statistics (dot-list, dot-object). Only those names change: every other statement stays the pin's text.
    private static string ListObjectText(string objectName, string tableName)
    {
        if (objectName.IndexOfAny(NameSplitters) == objectName.Length - tableName.Length - 1 && tableName.IndexOfAny(NameSplitters) < 0)
            return objectName;
        if (!objectName.EndsWith("." + tableName, StringComparison.Ordinal))
            return objectName;
        string schemaName = objectName.Substring(0, objectName.Length - tableName.Length - 1);
        return String.Format("[{0}].[{1}]", schemaName.Replace("]", "]]"), tableName.Replace("]", "]]"));
    }

    // Correction target-enclosed: the help and the DBCC page both have the target enclosed in brackets, single quotes, double quotes or no quotes, and inside the pin's literal only the last
    // named anything (pair-target-brackets, pair-target-double-quotes, pair-target-single-quotes). The closing character is doubled inside its own form, as the server writes it. A statistic
    // whose real name starts and ends with such a pair now needs that pair twice. The Target property keeps the caller's text.
    private static string UnenclosedTarget(string target)
    {
        if (target.Length < 2)
            return target;
        char first = target[0];
        char last = target[target.Length - 1];
        char closing = first == '[' ? ']' : first;
        if ((first != '[' && first != '"' && first != '\'') || last != closing)
            return target;
        string doubled = new(closing, 2);
        return target.Substring(1, target.Length - 2).Replace(doubled, closing.ToString());
    }

    private string StatementText(string objectName, string targetName)
    {
        string options = String.Format("{0}, {1}", NameLiteral(objectName), NameLiteral(targetName));
        return Template.Replace("#options#", options) + Clauses[Option];
    }

    // Correction quoted-names: a name stays one string literal whatever it holds, the caller's or the server's. The Cmd property shows the statement that ran.
    // Correction name-outside-code-page: N'' keeps a character the varchar literal loses (wide-list, wide-object, wide-pair); a name it cannot lose keeps the pinned statement.
    private static string NameLiteral(string name)
    {
        string literal = String.Format("'{0}'", name.Replace("'", "''"));
        foreach (char character in name)
        {
            if (character > 127)
                return "N" + literal;
        }
        return literal;
    }

    // PS: $db.Query($text), the Database script method of xml/dbatools.Types.ps1xml: it runs through the database object and puts the previous database back. Outside a try the fault ends
    // only that statement of the pin.
    private bool TryReadList(Server server, SmoDatabase db, string query, out DataTable? list)
    {
        list = null;
        ErrorRecord fault;
        ServerConnection connection = server.ConnectionContext;
        SetActiveConnection(connection);
        try
        {
            string previous = connection.CurrentDatabase;
            DataSet result;
            try
            {
                result = db.ExecuteWithResults(query);
            }
            finally
            {
                RestoreDatabaseContext(connection, previous);
            }
            list = result.Tables.Count > 0 ? result.Tables[0] : null;
            return true;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            string inner = String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message);
            string outer = String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", inner);
            fault = new ErrorRecord(new MethodInvocationException(outer, new MethodInvocationException(inner, failure)),
                "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
        }
        ReportFault(fault);
        return false;
    }

    // PS: the script method's finally: a comparison that keeps case on purpose, and a plain Write-Warning that never becomes the outcome of the call (denied-read-list, denied-read-ee).
    private void RestoreDatabaseContext(ServerConnection connection, string previous)
    {
        if (String.IsNullOrEmpty(previous) || String.Equals(connection.CurrentDatabase, previous, StringComparison.Ordinal))
            return;
        try
        {
            connection.ExecuteNonQuery("USE [" + previous.Replace("]", "]]") + "]");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            string text = String.Format(CultureInfo.InvariantCulture,
                "The database context could not be restored to [{0}]: Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{1}\"", previous, failure.Message);
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

    // PS: the foreach over $queryList in its try, whose catch ends this database.
    private void RunStatements(Server server, SmoDatabase db, DbaInstanceParameter instance, List<Statement> statements)
    {
        try
        {
            foreach (Statement statement in statements)
            {
                WriteMessage(MessageLevel.Verbose, "Running statement " + statement.Query);
                DataTable? results = RunStatement(server, db, statement.Query);
                if (results is null)
                    continue;
                foreach (DataRow row in results.Rows)
                    WriteObject(RowObject(server, db, statement, row));
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StopFunction(String.Format("Error capturing data on {0}", db), target: instance,
                errorRecord: new ErrorRecord(failure, "Get-DbaDbccStatistic", ErrorCategory.NotSpecified, null), exception: failure, continueLoop: true);
        }
    }

    private PSObject RowObject(Server server, SmoDatabase db, Statement statement, DataRow row)
    {
        PSObject output = new();
        OutputHelper.AddInstanceProperties(output, server);
        output.Properties.Add(new PSNoteProperty("Database", db.Name));
        output.Properties.Add(new PSNoteProperty("Object", statement.ObjectName));
        output.Properties.Add(new PSNoteProperty("Target", statement.TargetName));
        output.Properties.Add(new PSNoteProperty("Cmd", statement.Query));
        string[] names = RowProperties[Option];
        for (int ordinal = 0; ordinal < names.Length; ordinal++)
        {
            // PS: $row[n]; an ordinal past the last column reads $null. AllDensity is the pin's $row[0].ToString(), whose text differs by edition (shape-DensityVector).
            object? cell = ordinal < row.Table.Columns.Count ? row[ordinal] : null;
            output.Properties.Add(new PSNoteProperty(names[ordinal], names[ordinal] == "AllDensity" ? row[ordinal].ToString() : cell));
        }
        return output;
    }

    // PS: $server | Invoke-DbaQuery -Query $query -Database $db.Name -MessagesToOutput. It keeps a connection already in that database and otherwise opens its own there, non-pooled. Called
    // without -EnableException, so a failure stays its warning under this command's -EnableException and -ErrorAction Stop (pair-target-missing-ee, pair-target-missing-stop). With NO_INFOMSGS
    // the statement prints nothing: only an injected PRINT reached -MessagesToOutput (pair-injection-print), and correction quoted-names closes that, so no message becomes a row here.
    private DataTable? RunStatement(Server server, SmoDatabase db, string query)
    {
        DbaInstanceParameter source = new((object)server);
        ServerConnection serverConnection = server.ConnectionContext;
        ServerConnection connection = serverConnection;
        bool sameDatabase = false;
        bool opened = false;
        try
        {
            sameDatabase = IsOnDatabase(serverConnection, db.Name) && PsString.Eq(serverConnection.ConnectAsUserName, "");
            if (!sameDatabase)
            {
                connection = DatabaseConnection(serverConnection, db.Name);
                connection.StatementTimeout = serverConnection.StatementTimeout;
            }
            if (!connection.IsOpen)
            {
                connection.Connect();
                opened = true;
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // held-pair, held-silent: both nested lines, under -ErrorAction SilentlyContinue too.
            ErrorRecord record = new(failure, QueryRunner, ErrorCategory.ConnectionError, source);
            string connectLine = String.Format("Error connecting to [{0}]: {1}", source, MessageService.GetErrorMessage(record));
            WarnNestedStopFunction(ConnectRunner, "Failure", target: source,
                errorRecord: new ErrorRecord(new Exception(connectLine), "dbatools_" + ConnectRunner, ErrorCategory.ConnectionError, source), category: ErrorCategory.ConnectionError);
            WarnNestedStopFunction(QueryRunner, "Failure", target: source, errorRecord: record, category: ErrorCategory.ConnectionError);
            return null;
        }

        try
        {
            using SqlCommand command = connection.SqlConnectionObject.CreateCommand();
            command.CommandText = query;
            command.CommandTimeout = connection.StatementTimeout;
            SetActiveCommand(command);
            using SqlDataAdapter adapter = new(command);
            DataSet results = new() { Locale = CultureInfo.InvariantCulture };
            adapter.Fill(results);
            return results.Tables.Count > 0 ? results.Tables[0] : null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: Resolve-SqlError in the nested query drops the failure under the -ErrorAction this command was given.
            if (!QuietFailure())
            {
                WarnNestedStopFunction(QueryRunner, String.Format("[{0}] Failed during execution", source), target: source,
                    errorRecord: new ErrorRecord(failure, QueryRunner, ErrorCategory.NotSpecified, null));
            }
            return null;
        }
        finally
        {
            SetActiveCommand(null);
            if (!sameDatabase || opened)
                connection.Disconnect();
        }
    }

    // PS: Invoke-DbaQuery and Connect-DbaInstance test ConnectionContext.CurrentDatabase, which is empty on a closed connection, so they open it for the value and return it unless the caller
    // had it open.
    private static bool IsOnDatabase(ServerConnection connection, string databaseName)
    {
        string current = connection.CurrentDatabase;
        if (String.IsNullOrEmpty(current))
        {
            bool wasOpen = connection.IsOpen;
            connection.Connect();
            current = connection.CurrentDatabase;
            if (!wasOpen)
                connection.Disconnect();
        }
        return PsString.Eq(current, databaseName);
    }

    // PS: Connect-DbaInstance sets DatabaseName on a copy of the context rather than call GetDatabaseConnection, which connects the copy to the database the caller's connection opened in first:
    // a caller denied there still reaches this database (denied-read-plain). A context built from a SqlConnection refuses the assignment; the pin then rebuilds its connection string or switches
    // the database on the copy, and this port takes GetDatabaseConnection, by reading and with no test, disclosed in the corrections record, fixed-connection-string.
    private static ServerConnection DatabaseConnection(ServerConnection serverConnection, string databaseName)
    {
        ServerConnection copy = serverConnection.Copy();
        try
        {
            copy.NonPooledConnection = true;
            copy.DatabaseName = databaseName;
            return copy;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ServerConnection connection = copy.GetDatabaseConnection(databaseName, false);
            copy.Disconnect();
            return connection;
        }
    }

    private bool QuietFailure()
    {
        return MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? bound)
            && bound is ActionPreference.SilentlyContinue or ActionPreference.Ignore;
    }

    // PS: the objects of $queryList. Object and Target are the caller's text or the cells of the list.
    private sealed class Statement
    {
        internal Statement(object? objectName, object? targetName, string query)
        {
            ObjectName = objectName;
            TargetName = targetName;
            Query = query;
        }

        internal object? ObjectName { get; }

        internal object? TargetName { get; }

        internal string Query { get; }
    }
}
