#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Retrieves suspect-page records from msdb.dbo.suspect_pages. Port of public/Get-DbaSuspectPage.ps1;
// surface pinned by migration/baselines/Get-DbaSuspectPage.json (SqlInstance Mandatory VFP pos0,
// Database object pos1, SqlCredential pos2, no ShouldProcess).
//
// Gate-1 correction (quality/corrections/Get-DbaSuspectPage.json): the source emits its rows after the
// foreach ($instance) loop from the last assigned $results/$server, which the function scope keeps across
// pipeline records. That drops every -SqlInstance value but the last, repeats an earlier record's rows
// when a later piped instance fails to connect, and labels an earlier instance's rows with the current
// server when its query fails. Rows are emitted per instance instead.
/// <summary>Retrieves suspect page records from msdb database for corruption detection and analysis</summary>
[Cmdlet(VerbsCommon.Get, "DbaSuspectPage")]
public sealed class GetDbaSuspectPageCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances (SQL 2005+).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Filter to suspect pages in the specified database.</summary>
    [Parameter(Position = 1)]
    public object? Database { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 2)]
    public override PSCredential? SqlCredential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private const string SuspectPageQuery = @"SELECT
            DB_NAME(database_id) AS DBName,
            file_id,
            page_id,
            CASE event_type
            WHEN 1 THEN '823 or 824'
            WHEN 2 THEN 'Bad Checksum'
            WHEN 3 THEN 'Torn Page'
            WHEN 4 THEN 'Restored'
            WHEN 5 THEN 'Repaired (DBCC)'
            WHEN 7 THEN 'Deallocated (DBCC)'
            END AS EventType,
            error_count,
            last_update_date
            FROM msdb.dbo.suspect_pages";

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;

            // PS: try { Connect-DbaInstance -MinimumVersion 9 } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 9);
            if (server is null)
                continue;

            DataTable results;
            try
            {
                // PS: $server.Query($sql) - the Server.Query script method without -Database runs
                // ConnectionContext.ExecuteWithResults and returns its first table.
                results = server.ConnectionContext.ExecuteWithResults(SuspectPageQuery).Tables[0];
            }
            catch (Exception ex)
            {
                // PS: Stop-Function -Message "Issue collecting data on $server" -Target $server -ErrorRecord $_ -Continue
                StopFunction(String.Format("Issue collecting data on {0}", server), target: server, errorRecord: QueryFaultRecord(ex), continueLoop: true);
                continue;
            }

            // PS: if ($Database) { $results = $results | Where-Object DBName -EQ $Database }
            bool filterDatabase = LanguagePrimitives.IsTrue(Database);
            foreach (DataRow row in results.Rows)
            {
                if (filterDatabase && !MatchesDatabase(row["DBName"]))
                    continue;

                PSObject result = new();
                OutputHelper.AddInstanceProperties(result, server);
                result.Properties.Add(new PSNoteProperty("Database", row["DBName"]));
                result.Properties.Add(new PSNoteProperty("FileId", row["file_id"]));
                result.Properties.Add(new PSNoteProperty("PageId", row["page_id"]));
                result.Properties.Add(new PSNoteProperty("EventType", row["EventType"]));
                result.Properties.Add(new PSNoteProperty("ErrorCount", row["error_count"]));
                result.Properties.Add(new PSNoteProperty("LastUpdateDate", row["last_update_date"]));
                WriteObject(result);
            }
        }
    }

    /// <summary>
    /// Where-Object DBName -EQ $Database: the row value is the left operand, so the filter value converts
    /// to its type and strings compare case-insensitively. A NULL DB_NAME never equals a truthy filter.
    /// </summary>
    private bool MatchesDatabase(object name)
    {
        if (name is null || name is DBNull)
            return false;
        object? value = Database is PSObject wrapped ? wrapped.BaseObject : Database;
        return LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture);
    }

    /// <summary>
    /// The error record the source catch receives from $server.Query: the script method concatenates the
    /// messages of the ExecuteWithResults failure chain and throws that text, which the engine reports as
    /// the ScriptMethodRuntimeException method fault of "Query" called with one argument.
    /// </summary>
    private static ErrorRecord QueryFaultRecord(Exception exception)
    {
        string message = "";
        Exception inner = exception;
        while (inner.InnerException is not null)
        {
            message += inner.Message;
            inner = inner.InnerException;
        }
        message += inner.Message;
        MethodInvocationException fault = new(
            String.Format("Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message));
        return new ErrorRecord(fault, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }
}
