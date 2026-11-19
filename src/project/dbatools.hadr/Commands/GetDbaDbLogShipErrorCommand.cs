#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbLogShipError.ps1 at refs/pins/dbatools-2026-10-22.
/// <summary>Retrieves log shipping error details from msdb to troubleshoot failed backup, copy, and restore operations</summary>
/// <para>Queries the log shipping monitor error detail table in msdb to return comprehensive error information when log shipping operations fail.</para>
/// <para>Identifies which specific action failed (backup on primary, copy, or restore on secondary) along with session details and error messages.</para>
/// <para>Saves time by consolidating error details from both primary and secondary instances into a single view, so you don't have to manually query multiple system tables.</para>
/// <para>Essential for troubleshooting log shipping failures and determining whether issues occurred during backup, file copy, or database restore phases.</para>
/// <list type="alertSet">
///   <item>
///     <term></term>
///     <description>
///       <para>Tags: LogShipping</para>
///       <para>Author: Sander Stad (@sqlstad), sqlstad.nl</para>
///       <para>Website: https://dbatools.io</para>
///       <para>Copyright: (c) 2018 by dbatools, licensed under MIT</para>
///       <para>License: MIT https://opensource.org/licenses/MIT</para>
///     </description>
///   </item>
/// </list>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbLogShipError -SqlInstance sql1</code>
///   <para>Get all the log shipping errors that occurred</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbLogShipError -SqlInstance sql1 -Action Backup</code>
///   <para>Get the errors that have something to do with the backup of the databases</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbLogShipError -SqlInstance sql1 -Secondary</code>
///   <para>Get the errors that occurred on the secondary instance.</para>
///   <para>This will return the copy of the restore actions because those only occur on the secondary instance</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbLogShipError -SqlInstance sql1 -DateTimeFrom "01/05/2018"</code>
///   <para>Get the errors that have occurred from "01/05/2018". This can also be of format "yyyy-MM-dd"</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbLogShipError -SqlInstance sql1 -Secondary -DateTimeFrom "01/05/2018" -DateTimeTo "2018-01-07"</code>
///   <para>Get the errors that have occurred between "01/05/2018" and "01/07/2018".</para>
///   <para>See that is doesn't matter how the date is represented.</para>
/// </example>
/// <seealso href="https://dbatools.io/Get-DbaDbLogShipError"/>
[Cmdlet(VerbsCommon.Get, "DbaDbLogShipError")]
public sealed class GetDbaDbLogShipErrorCommand : DbaInstanceCmdlet
{
    /// <para>The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.</para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>Specifies which databases to include when retrieving log shipping errors. Requires exact database names, not wildcards.</para>
    /// <para>Use this when troubleshooting specific databases rather than reviewing all log shipped databases on the instance.</para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <para>Excludes specific databases from the log shipping error results. Requires exact database names, not wildcards.</para>
    /// <para>Useful when you want to see errors for all databases except certain ones, like excluding test databases from production error reviews.</para>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ExcludeDatabase { get; set; }

    /// <para>Filters errors by log shipping operation type: Backup (primary), Copy (between servers), or Restore (secondary).</para>
    /// <para>Use this to isolate which phase of log shipping is failing when troubleshooting multi-step log shipping workflows.</para>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    [ValidateSet("Backup", "Copy", "Restore")]
    public string[]? Action { get; set; }

    /// <para>Sets the earliest date and time for error records to include in results.</para>
    /// <para>Essential for focusing on recent failures or analyzing errors that occurred after a specific event or change.</para>
    [Parameter(Position = 5)]
    [PsDateTimeCast]
    public DateTime DateTimeFrom { get; set; }

    /// <para>Sets the latest date and time for error records to include in results.</para>
    /// <para>Combined with DateTimeFrom, this creates a specific time window for analyzing log shipping failures during maintenance windows or incidents.</para>
    [Parameter(Position = 6)]
    [PsDateTimeCast]
    public DateTime DateTimeTo { get; set; }

    /// <para>Returns only errors from backup operations that occur on the primary server.</para>
    /// <para>Use this when troubleshooting backup failures or primary-side log shipping issues like insufficient disk space or backup device problems.</para>
    [Parameter]
    public SwitchParameter Primary { get; set; }

    /// <para>Returns only errors from copy and restore operations that occur on secondary servers.</para>
    /// <para>Use this when troubleshooting file transfer failures or restore issues on the destination server, such as network connectivity or disk space problems.</para>
    [Parameter]
    public SwitchParameter Secondary { get; set; }

    // PS: the query string of the process block. Corrections: database names stay NVARCHAR (unicode-database-name), and an error that
    // names one database of a shared secondary id belongs to that database alone (shared-secondary-restore).
    private const string LogShipErrorQuery = @"
        CREATE TABLE #DatabaseID
        (
            DatabaseName NVARCHAR(128),
            DatabaseID UNIQUEIDENTIFIER,
            Instance VARCHAR(20)
        );

        INSERT INTO #DatabaseID
        (
            DatabaseName,
            DatabaseID,
            Instance
        )
        SELECT secondary_database,
               secondary_id,
               'Secondary'
        FROM msdb.dbo.log_shipping_secondary_databases;

        INSERT INTO #DatabaseID
        (
            DatabaseName,
            DatabaseID,
            Instance
        )
        SELECT primary_database,
               primary_id,
               'Primary'
        FROM msdb.dbo.log_shipping_primary_databases;

        SELECT di.DatabaseName,
               di.Instance,
               CASE lsmed.[agent_type]
                   WHEN 0 THEN
                       'Backup'
                   WHEN 1 THEN
                       'Copy'
                   WHEN 2 THEN
                       'Restore'
                   ELSE
                       ''
               END AS [Action],
               lsmed.[session_id] AS SessionID,
               lsmed.[sequence_number] AS SequenceNumber,
               lsmed.[log_time] AS LogTime,
               lsmed.[message] AS [Message]
        FROM msdb.dbo.log_shipping_monitor_error_detail AS lsmed
            INNER JOIN #DatabaseID AS di
                ON di.DatabaseID = lsmed.agent_id
                   AND (
                           di.DatabaseName = lsmed.[database_name] COLLATE DATABASE_DEFAULT
                           OR NOT EXISTS
        (
            SELECT 1
            FROM #DatabaseID AS named
            WHERE named.DatabaseID = lsmed.agent_id
                  AND named.DatabaseName = lsmed.[database_name] COLLATE DATABASE_DEFAULT
        )
                       )
        ORDER BY lsmed.[log_time],
                 lsmed.[database_name],
                 lsmed.[agent_type],
                 lsmed.[session_id],
                 lsmed.[sequence_number];

        DROP TABLE #DatabaseID;
        ";

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // Correction azure-refusal: Azure SQL Database has no log shipping tables, so it is refused the way -AzureUnsupported does.
            Server? server = ConnectInstance(instance, minimumVersion: 9, azureUnsupported: true);
            if (server is null)
                continue;

            // PS: $server.EngineEdition -match "Express"; no other member of the Edition enum holds that word.
            if (server.EngineEdition == Edition.Express)
            {
                WriteMessage(MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture, "{0} is Express Edition which does not support Log Shipping", instance));
                continue;
            }

            DataTable? results;
            try
            {
                // PS: $server.Query($query), the dbatools Server.Query script method: ExecuteWithResults, then the first table.
                DataSet data = server.ConnectionContext.ExecuteWithResults(LogShipErrorQuery);
                results = data.Tables.Count > 0 ? data.Tables[0] : null;
            }
            catch (Exception failure)
            {
                // No try encloses $server.Query in the pinned function, so the fault ends this statement only.
                // Correction stale-rows-after-failed-read: the failed instance writes nothing more, where the source writes its last rows again.
                // caller-try: continue -- the probe's denied-then-good-bare case reads the next instance after the error; no row is written for this one
                WriteError(QueryRecord(failure)); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
                continue;
            }

            if (results is null || results.Rows.Count == 0)
            {
                WriteMessage(MessageLevel.Verbose, "No log shipping errors found");
                continue;
            }

            foreach (DataRow row in results.Rows)
            {
                if (!Selected(row))
                    continue;
                PSObject output = new();
                OutputHelper.AddInstanceProperties(output, server);
                output.Properties.Add(new PSNoteProperty("Database", row["DatabaseName"]));
                output.Properties.Add(new PSNoteProperty("Instance", row["Instance"]));
                output.Properties.Add(new PSNoteProperty("Action", row["Action"]));
                output.Properties.Add(new PSNoteProperty("SessionID", row["SessionID"]));
                output.Properties.Add(new PSNoteProperty("SequenceNumber", row["SequenceNumber"]));
                output.Properties.Add(new PSNoteProperty("LogTime", row["LogTime"]));
                output.Properties.Add(new PSNoteProperty("Message", row["Message"]));
                WriteObject(output);
            }
        }
    }

    // PS: the Where-Object chain. An array parameter filters only when it is true in PowerShell, so -Database "" filters nothing and
    // -Database "", "" keeps nothing; a date filters whenever it was bound, even at DateTime.MinValue.
    private bool Selected(DataRow row)
    {
        string database = (string)row["DatabaseName"];
        string role = (string)row["Instance"];
        DateTime logTime = (DateTime)row["LogTime"];

        if (LanguagePrimitives.IsTrue(Database) && !IsIn(database, Database!))
            return false;
        if (LanguagePrimitives.IsTrue(ExcludeDatabase) && IsIn(database, ExcludeDatabase!))
            return false;
        if (LanguagePrimitives.IsTrue(Action) && !IsIn((string)row["Action"], Action!))
            return false;
        if (TestBound(nameof(DateTimeFrom)) && logTime < DateTimeFrom)
            return false;
        if (TestBound(nameof(DateTimeTo)) && logTime > DateTimeTo)
            return false;
        if (Primary.ToBool() && role != "Primary")
            return false;
        if (Secondary.ToBool() && role != "Secondary")
            return false;
        return true;
    }

    // PS: -in, which compares strings without regard to case.
    private static bool IsIn(string value, string[] candidates)
    {
        foreach (string candidate in candidates)
        {
            if (LanguagePrimitives.Equals(value, candidate, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    // PS: $_ for a failed $server.Query: the script method's catch joins the messages of the exception chain and throws that text,
    // which the method call reports as "Exception calling "Query" ..." over the two runtime exceptions of the throw.
    private static ErrorRecord QueryRecord(Exception failure)
    {
        StringBuilder text = new();
        for (Exception? current = failure; current is not null; current = current.InnerException)
            text.Append(current.Message);
        string message = text.ToString();
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message, new RuntimeException(message)));
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }
}
