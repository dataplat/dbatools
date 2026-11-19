#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbMirrorMonitor.ps1 at refs/pins/dbatools-2026-10-22.
/// <summary>Retrieves database mirroring performance metrics and monitoring history from SQL Server instances</summary>
/// <para>
/// Retrieves detailed database mirroring performance statistics from the msdb monitoring tables, helping you track mirroring health and identify performance bottlenecks. This function executes sp_dbmmonitorresults to pull metrics like log generation rates, send rates, transaction delays, and recovery progress from both principal and mirror databases.
/// </para>
/// <para>
/// Use this when troubleshooting mirroring performance issues, monitoring replication lag, or generating compliance reports for high availability configurations. You can optionally refresh the monitoring data before retrieval and filter results by time periods or row counts to focus on specific timeframes.
/// </para>
/// <para>
/// The function returns comprehensive metrics including unsent log size, recovery rates, average delays, and witness status - all the key indicators DBAs need to assess mirroring health without manually querying system tables.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMirrorMonitor -SqlInstance sql2008, sql2012
/// </code>
/// <para>
/// Returns last two hours' worth of status rows for a monitored database from the status table on sql2008 and sql2012.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMirrorMonitor -SqlInstance sql2005 -LimitResults LastDay -Update
/// </code>
/// <para>
/// Updates monitor stats then returns the last 24 hours worth of status rows for a monitored database from the status table on sql2008 and sql2012.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Mirroring, Mirror, HA
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbMirrorMonitor" />
[Cmdlet(VerbsCommon.Get, "DbaDbMirrorMonitor")]
public sealed class GetDbaDbMirrorMonitorCommand : DbaInstanceCmdlet
{
    // Positions follow the pinned function's automatic positional binding: every non-switch parameter in order.

    /// <para>
    /// The target SQL Server instance
    /// </para>
    [Parameter(Position = 0)]
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
    /// Specifies which mirrored databases to monitor. Only databases configured for mirroring will return results.
    /// Use this to focus monitoring on specific databases instead of checking all mirrored databases on the instance.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <para>
    /// Accepts database objects from Get-DbaDatabase pipeline input.
    /// Use this when you want to filter databases first before checking their mirroring status.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public SmoDatabase[]? InputObject { get; set; }

    /// <para>
    /// Forces a refresh of mirroring statistics before retrieving results by calling sp_dbmmonitorupdate.
    /// Use this when you need the most current metrics, though SQL Server automatically limits updates to once every 15 seconds and requires sysadmin privileges.
    /// </para>
    [Parameter]
    public SwitchParameter Update { get; set; }

    /// <para>
    /// Controls how much historical monitoring data to retrieve from the msdb.dbo.dbm_monitor_data table.
    /// Choose shorter time periods for recent performance analysis or longer periods for trend analysis. Row-based options return the most recent entries regardless of time.
    /// </para>
    /// <para>
    /// Options include:
    /// LastRow
    /// LastTwoHours
    /// LastFourHours
    /// LastEightHours
    /// LastDay
    /// LastTwoDays
    /// Last100Rows
    /// Last500Rows
    /// Last1000Rows
    /// Last1000000Rows
    /// </para>
    [Parameter(Position = 4)]
    [ValidateSet("LastRow", "LastTwoHours", "LastFourHours", "LastEightHours", "LastDay", "LastTwoDays", "Last100Rows", "Last500Rows", "Last1000Rows", "Last1000000Rows")]
    [PsStringCast]
    public string LimitResults { get; set; } = "LastTwoHours";

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    // Get-DbaDatabase's default -Status, any overlap sufficient.
    private const DatabaseStatus DefaultStatus = DatabaseStatus.Normal | DatabaseStatus.Restoring |
        DatabaseStatus.RecoveryPending | DatabaseStatus.Recovering | DatabaseStatus.Suspect |
        DatabaseStatus.Offline | DatabaseStatus.Standby | DatabaseStatus.EmergencyMode;

    private const string ExecutionFailureMessage = "An exception occurred while executing a Transact-SQL statement or batch.";

    // PS: the $sql text. Correction interpolated-database-name: the database name goes in as a parameter.
    private const string ResultsStatement = "EXEC msdb.dbo.sp_dbmmonitorresults @database_name = @database_name, @mode = @mode, @update_table = @update_table";

    // PS: the begin block's switch ($LimitResults), which ignores case as the switch does.
    // Correction thousand-row-limits: Last1000Rows has a mode, and Last1000000Rows the procedure's own.
    private static readonly Dictionary<string, int> Modes = new(StringComparer.OrdinalIgnoreCase)
    {
        ["LastRow"] = 0,
        ["LastTwoHours"] = 1,
        ["LastFourHours"] = 2,
        ["LastEightHours"] = 3,
        ["LastDay"] = 4,
        ["LastTwoDays"] = 5,
        ["Last100Rows"] = 6,
        ["Last500Rows"] = 7,
        ["Last1000Rows"] = 8,
        ["Last1000000Rows"] = 9
    };

    private bool _instancesRead;

    /// <summary>Reads the monitor rows of the record's piped databases, then those of -SqlInstance.</summary>
    protected override void ProcessRecord()
    {
        // PS: foreach ($instance in $SqlInstance) { $InputObject += Get-DbaDatabase ... }, built before the first row is read.
        // Correction sqlinstance-read-once: a command-line -SqlInstance is read after the first record's piped databases and not
        // again, where the pin reads it for every piped record and repeats its rows.
        List<SmoDatabase?> databases = new(InputObject ?? Array.Empty<SmoDatabase>());
        if (!_instancesRead)
        {
            _instancesRead = true;
            databases.AddRange(GatherDatabases());
        }

        foreach (SmoDatabase? database in databases)
        {
            if (database is null)
            {
                WriteNullDatabaseFault();
                continue;
            }

            Server server = database.Parent;
            if (server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase)
            {
                RefuseAzure(database);
                continue;
            }

            bool tableFound = false;
            DataTable? results = null;
            try
            {
                // PS: -not ($db.Parent.Databases['msdb'].Tables['dbm_monitor_data'].Name). A failed SMO read here goes on to the pinned
                // try, whose Query fails the same way, so it is reported there.
                tableFound = LanguagePrimitives.IsTrue(server.Databases["msdb"]?.Tables["dbm_monitor_data"]?.Name);
                if (tableFound)
                    results = ReadResults(database);
            }
            catch (Exception failure)
            {
                // PS: Stop-Function -Message "Failure" -ErrorRecord $_, whose stop flag nothing reads: the next database is read.
                StopFunction("Failure", errorRecord: QueryRecord(failure), continueLoop: true);
                continue;
            }

            if (!tableFound)
            {
                StopFunction("msdb.dbo.dbm_monitor_data not found. Please run Add-DbaDbMirrorMonitor then you can get monitor stats.", continueLoop: true);
                continue;
            }

            if (results is null)
                continue;
            foreach (DataRow row in results.Rows)
            {
                PSObject output = new();
                OutputHelper.AddInstanceProperties(output, server);
                output.Properties.Add(new PSNoteProperty("DatabaseName", row["database_name"]));
                output.Properties.Add(new PSNoteProperty("Role", row["role"]));
                output.Properties.Add(new PSNoteProperty("MirroringState", row["mirroring_state"]));
                output.Properties.Add(new PSNoteProperty("WitnessStatus", row["witness_status"]));
                output.Properties.Add(new PSNoteProperty("LogGenerationRate", row["log_generation_rate"]));
                output.Properties.Add(new PSNoteProperty("UnsentLog", row["unsent_log"]));
                output.Properties.Add(new PSNoteProperty("SendRate", row["send_rate"]));
                output.Properties.Add(new PSNoteProperty("UnrestoredLog", row["unrestored_log"]));
                output.Properties.Add(new PSNoteProperty("RecoveryRate", row["recovery_rate"]));
                output.Properties.Add(new PSNoteProperty("TransactionDelay", row["transaction_delay"]));
                output.Properties.Add(new PSNoteProperty("TransactionsPerSecond", row["transactions_per_sec"]));
                output.Properties.Add(new PSNoteProperty("AverageDelay", row["average_delay"]));
                output.Properties.Add(new PSNoteProperty("TimeRecorded", row["time_recorded"]));
                output.Properties.Add(new PSNoteProperty("TimeBehind", row["time_behind"]));
                output.Properties.Add(new PSNoteProperty("LocalTime", row["local_time"]));
                WriteObject(output);
            }
        }
    }

    // PS: a null element of -InputObject, where $db.Parent.Databases['msdb'] indexes nothing outside the pinned try. The function's next
    // statement is that try, whose Query call fails on the same null.
    private void WriteNullDatabaseFault()
    {
        ErrorRecord fault = new(new RuntimeException("Cannot index into a null array."), "NullArray", ErrorCategory.InvalidOperation, null);
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException stops at this raw fault; the probe's null-enable-exception case stops at the next statement
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams the record of a raw fault, which Stop-Function does not raise
        }

        // The probe's null-first and null-last cases read the other databases after this record; a caller's try catches it here, as it does the pin's raw fault.
        StatementFault.Surface(this, fault);
        ErrorRecord nullCall = new(new RuntimeException("You cannot call a method on a null-valued expression."), "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null);
        StopFunction("Failure", errorRecord: nullCall, continueLoop: true);
    }

    // Correction azure-refusal: Azure SQL Database has neither msdb nor database mirroring, so it is refused the way -AzureUnsupported
    // does, under this command's name because the pinned call that reaches it is its own.
    private void RefuseAzure(object target)
    {
        ConnectionResolutionException refusal = new(ConnectionResolutionFailure.AzureUnsupported, "Azure SQL Database not supported", null);
        ErrorRecord record = new(refusal, "dbatools_Get-DbaDbMirrorMonitor", ErrorCategory.ConnectionError, target);
        StopFunction("Failure", target: target, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: true);
    }

    // PS: Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database, instance by instance.
    // -EnableException never reaches that call, so its Stop-Function warns and the next instance is read.
    private List<SmoDatabase> GatherDatabases()
    {
        List<SmoDatabase> gathered = new();
        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            Server? server = ConnectNested(instance);
            if (server is null)
                continue;
            if (server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase)
            {
                RefuseAzure(instance);
                continue;
            }

            // PS: Get-DbaDatabase walks sys.databases, which lists by id. -in ignores case, and an empty -Database keeps them all.
            List<SmoDatabase> selected = new();
            foreach (SmoDatabase database in server.Databases)
            {
                if ((database.Status & DefaultStatus) != 0 && (!LanguagePrimitives.IsTrue(Database) || IsRequested(database.Name)))
                    selected.Add(database);
            }
            selected.Sort((left, right) => left.ID.CompareTo(right.ID));
            gathered.AddRange(selected);
        }
        return gathered;
    }

    private Server? ConnectNested(DbaInstanceParameter instance)
    {
        void Report(MessageLevel level, string message) => WriteAttributedMessage("Connect-DbaInstance", level, message);

        Server server;
        Report(MessageLevel.Debug, "Starting process block");
        try
        {
            server = ConnectionService.GetServer(new SmoConnectionRequest
            {
                MessageCallback = Report,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                SqlCredential = SqlCredential,
                Instance = instance
            });
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WarnNestedStopFunction("Get-DbaDatabase", "Failure", instance,
                new ErrorRecord(failure, "dbatools_Get-DbaDatabase", ErrorCategory.ConnectionError, instance), ErrorCategory.ConnectionError);
            return null;
        }
        Report(MessageLevel.Debug, "We are finished with this instance");
        SetActiveConnection(server.ConnectionContext);
        return server;
    }

    private bool IsRequested(string name)
    {
        foreach (string value in Database!)
        {
            if (LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    // PS: $db.Parent.Query($sql), the Server.Query script method: ExecuteWithResults on the server's own connection, first table.
    private DataTable? ReadResults(SmoDatabase database)
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

            using SqlCommand command = connection.SqlConnectionObject.CreateCommand();
            command.CommandText = ResultsStatement;
            command.CommandTimeout = connection.StatementTimeout;
            command.Parameters.Add("@database_name", SqlDbType.NVarChar, 128).Value = database.Name;
            command.Parameters.Add("@mode", SqlDbType.Int).Value = Modes[LimitResults];
            command.Parameters.Add("@update_table", SqlDbType.Int).Value = Update.ToBool() ? 1 : 0;
            DataSet results = new() { Locale = CultureInfo.InvariantCulture };
            SetActiveCommand(command);
            using (SqlDataAdapter adapter = new(command))
                adapter.Fill(results);
            return results.Tables.Count > 0 ? results.Tables[0] : null;
        }
        catch (Exception failure)
        {
            throw new ExecutionFailureException(ExecutionFailureMessage, failure);
        }
        finally
        {
            SetActiveCommand(null);
            // SMO disconnects a pooled connection it opened for the call (AutoDisconnectMode.DisconnectIfPooled).
            if (connected && !connection.NonPooledConnection && connection.AutoDisconnectMode == AutoDisconnectMode.DisconnectIfPooled)
                connection.Disconnect();
        }
    }

    // PS: $_ for a failed $db.Parent.Query: the script method joins the messages of the exception chain and throws that text, which the
    // method call reports as "Exception calling "Query" ..." over the two runtime exceptions of the throw.
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
