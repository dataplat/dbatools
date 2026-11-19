#nullable enable

using System;
using System.Collections;
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

// Port of public/Find-DbaDbDisabledIndex.ps1: the database selection, the query and the context restore run here in C#.
// Quirks kept: -NoClobber and -Append exist on the surface but the body never reads them; the catch's Stop-Function has
// no -Continue, so the database loop simply proceeds (the function never tests its interrupt flag).
/// <summary>Identifies disabled indexes across SQL Server databases</summary>
[Cmdlet(VerbsCommon.Find, "DbaDbDisabledIndex", SupportsShouldProcess = true)]
public sealed class FindDbaDbDisabledIndexCommand : DbaInstanceCmdlet
{
    private const string RestoreWarning = "The database context could not be restored to [{0}]: {1}";

    /// <summary>The target SQL Server instance or instances.</summary>
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

    /// <summary>Surface-only in the function: the body never reads it.</summary>
    [Parameter]
    public SwitchParameter NoClobber { get; set; }

    /// <summary>Surface-only in the function: the body never reads it.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    // PS: the begin-block $sql literal verbatim.
    private const string DisabledIndexSql = @"
        SELECT DB_NAME() AS DatabaseName
        ,d.database_id AS DatabaseId
        ,s.name AS SchemaName
        ,t.name AS TableName
        ,i.object_id AS ObjectId
        ,i.name AS IndexName
        ,i.index_id AS IndexId
        ,i.type_desc AS TypeDesc
        FROM sys.tables t
        JOIN sys.schemas s
            ON t.schema_id = s.schema_id
        JOIN sys.indexes i
            ON i.object_id = t.object_id
        JOIN sys.databases d
            ON d.name = DB_NAME()
        WHERE i.is_disabled = 1";

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance -MinimumVersion 9 } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 9);
            if (server is null)
                continue;

            List<string> names = DatabaseNames(server);
            if (names.Count == 0)
            {
                WriteMessage(MessageLevel.Verbose, "There are no databases to analyse.");
                continue;
            }

            // Working through a Database object moves the connection into that database and never moves it back, so
            // the caller's database is put back when the work is done (#10555).
            string callerDatabase = server.ConnectionContext.CurrentDatabase;
            try
            {
                foreach (string db in names)
                    SearchDatabase(server, db);
            }
            finally
            {
                RestoreDatabaseContext(server.ConnectionContext, callerDatabase);
            }
        }
    }

    // PS: $databases = $server.Databases | Where-Object Name -in $database (bound), otherwise
    //     $server.Databases | Where-Object IsAccessible -eq $true; then foreach ($db in $databases.name).
    // Correction database-wildcards: the help documents wildcards for -Database, which -in never honoured; the shared
    // WildcardNameFilter matcher keeps each value's -in comparison and adds the documented pattern (rule E+).
    private List<string> DatabaseNames(Server server)
    {
        List<string> names = new();
        bool named = PsOps.IsTrue(Database);
        IEnumerator? enumerator = null;
        try
        {
            List<SmoDatabase> candidates = new();
            enumerator = LanguagePrimitives.GetEnumerator(server.Databases);
            while (enumerator is not null && enumerator.MoveNext())
                candidates.Add((SmoDatabase)enumerator.Current!);

            WildcardNameMatcher? matcher = null;
            if (named)
            {
                List<string> scope = new();
                foreach (SmoDatabase candidate in candidates)
                {
                    if (Read(() => candidate.Name) is string scopeName)
                        scope.Add(scopeName);
                }
                matcher = WildcardNameFilter.CreateMatcher(Database, true, (value, name) => PsOps.In(name, new[] { value }), scope);
            }

            foreach (SmoDatabase candidate in candidates)
            {
                bool selected = matcher is not null
                    ? Read(() => candidate.Name) is string candidateName && matcher.Matches(candidateName)
                    : PsOps.Eq(Read(() => candidate.IsAccessible), true);
                if (selected)
                    names.Add(candidate.Name);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // caller-try: terminate -- continuing would reuse $databases from the previous instance and search its names here
            ThrowTerminatingError(EnumerationFault(failure, enumerator)); // style-ok: cs-raw-streams pipeline statement fault outside Stop-Function, as in the source
        }
        return names;
    }

    private void SearchDatabase(Server server, string db)
    {
        // PS: if ($ExcludeDatabase -contains $db -or $null -eq $server.Databases[$db]) { continue }
        if (PsOps.In(db, ExcludeDatabase) || server.Databases[db] is null)
            return;

        try
        {
            if (!ShouldProcess(db, "Getting disabled indexes"))
                return;
            WriteMessage(MessageLevel.Verbose, "Getting indexes from database '" + db + "'.");
            WriteMessage(MessageLevel.Debug, "SQL Statement: " + DisabledIndexSql);
            DataTable? disabledIndex = DatabaseQuery(server.Databases[db]);

            // PS: if (@($disabledIndex).Count -gt 0) { foreach ($index in $results) { $index } } - a DataTable enumerates
            // its rows.
            if (disabledIndex is not null && disabledIndex.Rows.Count > 0)
            {
                foreach (DataRow index in disabledIndex.Rows)
                    WriteObject(index);
            }
            else
            {
                WriteMessage(MessageLevel.Verbose, "No Disabled indexes found");
            }
        }
        catch (QueryFault fault)
        {
            // PS: Stop-Function -Message "Issue gathering indexes" -Category InvalidOperation -InnerErrorRecord $_ -Target $db
            StopFunction("Issue gathering indexes", target: db, errorRecord: fault.Record, category: ErrorCategory.InvalidOperation);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException && failure is not QueryFault)
        {
            ErrorRecord caught = failure is IContainsErrorRecord container && container.ErrorRecord is not null
                ? new ErrorRecord(container.ErrorRecord, failure)
                : new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null);
            StopFunction("Issue gathering indexes", target: db, errorRecord: caught, category: ErrorCategory.InvalidOperation);
        }
    }

    // PS: $server.Databases[$db].Query($sql), the dbatools Database.Query script method: ExecuteWithResults on the
    // server's own connection, first table, and the previous database put back in its finally.
    private DataTable? DatabaseQuery(SmoDatabase database)
    {
        ServerConnection connection = database.Parent.ConnectionContext;
        string previous = connection.CurrentDatabase;
        try
        {
            DataSet results = database.ExecuteWithResults(DisabledIndexSql);
            return results.Tables.Count > 0 ? results.Tables[0] : null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
            MethodInvocationException query = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", call.Message), call);
            throw new QueryFault(new ErrorRecord(query, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null));
        }
        finally
        {
            if (!String.IsNullOrEmpty(previous) && !String.Equals(connection.CurrentDatabase, previous, StringComparison.Ordinal))
            {
                string? failed = UseDatabase(connection, previous);
                if (failed is not null)
                    ScriptMethodWarning(String.Format(CultureInfo.InvariantCulture, RestoreWarning, previous, failed));
            }
        }
    }

    // PS: Restore-DatabaseContext -Server $server -Database $callerDatabase
    private void RestoreDatabaseContext(ServerConnection connection, string callerDatabase)
    {
        // -ceq on purpose: database names follow the instance collation.
        if (String.IsNullOrEmpty(callerDatabase) || String.Equals(connection.CurrentDatabase, callerDatabase, StringComparison.Ordinal))
            return;
        string? failed = UseDatabase(connection, callerDatabase);
        if (failed is not null)
            WriteMessage(MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture, RestoreWarning, callerDatabase, failed));
    }

    // $null = $connection.ExecuteNonQuery("USE [...]"); the method fault's message when it fails, null when it worked.
    private static string? UseDatabase(ServerConnection connection, string database)
    {
        try
        {
            connection.ExecuteNonQuery("USE [" + database.Replace("]", "]]") + "]");
            return null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{0}\"", failure.Message);
        }
    }

    // The script method warns through plain Write-Warning and raises a Stop or Inquire preference to Continue for it.
    private void ScriptMethodWarning(string text)
    {
        try
        {
            WriteWarning(text); // style-ok: cs-raw-streams the Database.Query script method calls plain Write-Warning, not Write-Message
        }
        catch (ActionPreferenceStopException stopped)
        {
            // The preference the script method raises to Continue must not end the command here.
            WriteMessage(MessageLevel.Debug, stopped.Message);
        }
    }

    // A property read through the member binder: a failing getter is $null.
    private static object? Read(Func<object?> getter)
    {
        try
        {
            return getter();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // Reported nowhere, as the binder reports nothing.
            return null;
        }
    }

    // The engine's record when the failure carries one (ExceptionInGetEnumerator); otherwise the record a failing
    // MoveNext gives (BadEnumeration, InvalidOperation, the enumerator as target).
    private static ErrorRecord EnumerationFault(Exception failure, IEnumerator? enumerator)
    {
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            return new ErrorRecord(container.ErrorRecord, failure);
        RuntimeException fault = new(String.Format(CultureInfo.InvariantCulture,
            "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
        return new ErrorRecord(fault, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
    }

    // Carries the Query script method's fault to the catch that Stop-Function reports it from.
    private sealed class QueryFault : Exception
    {
        public QueryFault(ErrorRecord record)
            : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        public ErrorRecord Record { get; }
    }
}
