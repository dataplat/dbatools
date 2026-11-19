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
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbLogSpace.ps1 at refs/pins/dbatools-2026-10-22: the database selection, the warning for each
// database it cannot open, and the two reads, sys.dm_db_log_space_usage per database or DBCC SQLPERF(LOGSPACE) once.
/// <summary>Retrieves transaction log space usage and capacity information from SQL Server databases.</summary>
/// <para>
/// Collects detailed transaction log metrics including total size, used space percentage, and used space in bytes for databases across SQL Server instances. Uses the sys.dm_db_log_space_usage DMV on SQL Server 2012+ or DBCC SQLPERF(logspace) on older versions.
/// </para>
/// <para>
/// Essential for proactive log space monitoring to prevent unexpected transaction log growth, identify databases approaching log capacity limits, and plan log file sizing. Helps DBAs avoid transaction failures caused by full transaction logs and optimize log file allocation strategies.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbLogSpace -SqlInstance Server1
/// </code>
/// <para>
/// Returns the transaction log usage information for all databases on Server1
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbLogSpace -SqlInstance Server1 -Database Database1, Database2
/// </code>
/// <para>
/// Returns the transaction log usage information for both Database1 and Database 2 on Server1
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbLogSpace -SqlInstance Server1 -ExcludeDatabase Database3
/// </code>
/// <para>
/// Returns the transaction log usage information for all databases on Server1, except Database3
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbLogSpace -SqlInstance Server1 -ExcludeSystemDatabase
/// </code>
/// <para>
/// Returns the transaction log usage information for all databases on Server1, except the system databases
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRegisteredServer -SqlInstance cmsServer | Get-DbaDbLogSpace -Database Database1
/// </code>
/// <para>
/// Returns the transaction log usage information for Database1 for a group of servers from SQL Server Central Management Server (CMS).
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Storage, Space, Log, File
/// Author: Jess Pomfret, JessPomfret.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2019 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbLogSpace" />
[Cmdlet(VerbsCommon.Get, "DbaDbLogSpace")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaDbLogSpaceCommand : DbaInstanceCmdlet
{
    private const string UsageQuery = "SELECT * FROM sys.dm_db_log_space_usage";
    private const string UsageQueryOlder = "DBCC SQLPERF(LOGSPACE)";

    /// <para>
    /// SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
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
    /// Specifies which databases to check for transaction log space usage. Accepts wildcards for pattern matching.
    /// Use this when you need to monitor specific databases instead of checking all databases on the instance, particularly useful for focusing on high-growth or critical databases.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <para>
    /// Specifies databases to skip when checking transaction log space usage. Accepts wildcards for pattern matching.
    /// Use this to exclude databases you don't need to monitor regularly, such as test databases, read-only databases, or databases with known stable log usage patterns.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ExcludeDatabase { get; set; }

    /// <para>
    /// Excludes system databases (master, model, msdb, tempdb) from the transaction log space report.
    /// Use this when focusing on user databases only, as system database log usage is typically managed differently and may not require the same monitoring attention.
    /// </para>
    [Parameter]
    public SwitchParameter ExcludeSystemDatabase { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    /// <summary>Reports the log space of the selected databases of each instance.</summary>
    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            List<SmoDatabase> accessible = new();
            foreach (SmoDatabase database in SelectDatabases(server))
            {
                // The name filters run first, so a named database is reported as skipped and an excluded one is never mentioned.
                if (database.IsAccessible)
                {
                    accessible.Add(database);
                    continue;
                }
                WriteMessage(MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture,
                    "Skipping {0} on {1} because it is not accessible, so its log space cannot be read", database, instance), database);
            }

            // PS: $server.versionMajor -ge 11. The connection's version is the same number, and the one a native test can
            // set before a connection opens, which proves the older path on a lab with no such instance.
            if (server.ServerVersion.Major >= 11)
                ReportFromView(server, instance, accessible);
            else
                ReportFromDbcc(server, instance, accessible);
        }
    }

    // PS: if ($Database) and if ($ExcludeDatabase) read truthiness, so a lone empty string filters nothing.
    private List<SmoDatabase> SelectDatabases(Server server)
    {
        bool include = LanguagePrimitives.IsTrue(Database);
        bool exclude = LanguagePrimitives.IsTrue(ExcludeDatabase);
        List<string> scope = new();
        foreach (SmoDatabase database in server.Databases)
            scope.Add(database.Name);
        // The help documents wildcards here, and -in and -NotIn alone would ignore them.
        WildcardNameMatcher included = NameMatcher(Database, scope);
        WildcardNameMatcher excluded = NameMatcher(ExcludeDatabase, scope);

        List<SmoDatabase> selected = new();
        foreach (SmoDatabase database in server.Databases)
        {
            if (include && !included.Matches(database.Name))
                continue;
            if (exclude && excluded.Matches(database.Name))
                continue;
            if (ExcludeSystemDatabase.IsPresent && database.IsSystemObject)
                continue;
            selected.Add(database);
        }
        return selected;
    }

    private static WildcardNameMatcher NameMatcher(string[]? values, List<string> scope)
    {
        return WildcardNameFilter.CreateMatcher(values, true, (value, name) => PsOps.In(name, new[] { value }), scope);
    }

    private void ReportFromView(Server server, DbaInstanceParameter instance, List<SmoDatabase> databases)
    {
        foreach (SmoDatabase database in databases)
        {
            DataTable usage;
            try
            {
                usage = ReadView(server, database);
            }
            catch (Exception error) when (error is not PipelineStoppedException)
            {
                StopFunction(String.Format(CultureInfo.InvariantCulture, "Unable to collect log space data on {0}.", instance),
                    target: database, errorRecord: QueryFaultRecord(error, 2), continueLoop: true);
                continue;
            }

            // A database snapshot has no log, so the view returns no row and the values stay empty, as in the pin.
            DataRow? row = usage.Rows.Count > 0 ? usage.Rows[0] : null;
            WriteUsage(server, database.Name, ToSize(row?["total_log_size_in_bytes"]), row?["used_log_space_in_percent"],
                ToSize(row?["used_log_space_in_bytes"]));
        }
    }

    // PS: $server.Query($sql, $db.Name) leaves the caller's connection in that database, so the method puts the previous one back.
    private DataTable ReadView(Server server, SmoDatabase database)
    {
        ServerConnection connection = server.ConnectionContext;
        string previous = connection.CurrentDatabase;
        try
        {
            return database.ExecuteWithResults(UsageQuery).Tables[0];
        }
        finally
        {
            RestoreContext(connection, previous);
        }
    }

    private void RestoreContext(ServerConnection connection, string previous)
    {
        // Case-sensitive on purpose: database names follow the instance collation.
        if (String.IsNullOrEmpty(previous) || String.Equals(connection.CurrentDatabase, previous, StringComparison.Ordinal))
            return;
        try
        {
            connection.ExecuteNonQuery(String.Format(CultureInfo.InvariantCulture, "USE [{0}]", previous.Replace("]", "]]")));
        }
        catch (Exception error) when (error is not PipelineStoppedException)
        {
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

    // The instance has no sys.dm_db_log_space_usage: one DBCC reports every database, and the selection filters its rows.
    private void ReportFromDbcc(Server server, DbaInstanceParameter instance, List<SmoDatabase> databases)
    {
        DataTable usage;
        try
        {
            usage = server.ConnectionContext.ExecuteWithResults(UsageQueryOlder).Tables[0];
        }
        catch (Exception error) when (error is not PipelineStoppedException)
        {
            // PS: -Target $db, a variable this path has not set yet.
            StopFunction(String.Format(CultureInfo.InvariantCulture, "Unable to collect log space data on {0}.", instance),
                errorRecord: QueryFaultRecord(error, 1), continueLoop: true);
            return;
        }

        foreach (DataRow row in usage.Rows)
        {
            object name = row["Database Name"];
            if (!databases.Exists(database => PsOps.Eq((object)database.Name, name)))
                continue;
            object percent = row["Log Space Used (%)"];
            double sizeInMegabytes = Convert.ToDouble(row["Log Size (MB)"], CultureInfo.InvariantCulture);
            double usedShare = Convert.ToDouble(percent, CultureInfo.InvariantCulture) / 100;
            WriteUsage(server, name, ToSize(sizeInMegabytes * 1048576), percent, ToSize(sizeInMegabytes * usedShare * 1048576));
        }
    }

    private void WriteUsage(Server server, object databaseName, Size? logSize, object? percent, Size? used)
    {
        PSObject output = new();
        OutputHelper.AddInstanceProperties(output, server);
        output.Properties.Add(new PSNoteProperty("Database", databaseName));
        output.Properties.Add(new PSNoteProperty("LogSize", logSize));
        output.Properties.Add(new PSNoteProperty("LogSpaceUsedPercent", percent));
        output.Properties.Add(new PSNoteProperty("LogSpaceUsed", used));
        WriteObject(output);
    }

    // PS: [dbasize]$value, through the language's conversion; [dbasize]$null stays null.
    private static Size? ToSize(object? value)
    {
        return value is null ? null : (Size)LanguagePrimitives.ConvertTo(value, typeof(Size), CultureInfo.InvariantCulture);
    }

    /// <summary>
    /// The record the source catch receives from $server.Query: the script method joins the messages of the failure chain
    /// and throws that text, which the engine reports as the ScriptMethodRuntimeException method fault of "Query".
    /// </summary>
    private static ErrorRecord QueryFaultRecord(Exception error, int argumentCount)
    {
        string message = "";
        Exception inner = error;
        while (inner.InnerException is not null)
        {
            message += inner.Message;
            inner = inner.InnerException;
        }
        message += inner.Message;
        MethodInvocationException fault = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"{0}\" argument(s): \"{1}\"", argumentCount, message), new RuntimeException(message));
        return new ErrorRecord(fault, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }
}
