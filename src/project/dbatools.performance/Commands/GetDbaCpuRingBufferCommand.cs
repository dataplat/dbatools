#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Reads CPU statistics from the scheduler-monitor ring buffer. Port of
/// public/Get-DbaCpuRingBuffer.ps1 (W1-059). Quirks preserved: the version-split timestamp
/// read indexes the Query result with [0] - a single-row result is a scalar DataRow whose
/// [0] is the FIRST COLUMN VALUE (multi-row would take the first ROW and interpolate its
/// type name); both verbose messages keep their TYPOS ("timestampe", "Staement"); the SQL
/// interpolates the timestamp and -CollectionMinutes invariantly. The queries ride the
/// Server.Query ETS hop; rows project to PSCustomObjects with raw DataRow column reads.
/// Surface pinned by migration/baselines/Get-DbaCpuRingBuffer.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaCpuRingBuffer")]
public sealed class GetDbaCpuRingBufferCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>How many minutes of history to return.</summary>
    [Parameter(Position = 2)]
    public int CollectionMinutes { get; set; } = 60;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Hashtable connectParams = new Hashtable();
            connectParams["SqlInstance"] = instance;
            connectParams["SqlCredential"] = SqlCredential;
            connectParams["MinimumVersion"] = 9;
            NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
            if (!connection.Ok)
            {
                StopFunction("Failure", target: instance, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }
            Server server = connection.Server!;

            // PS: ($server.Query(<ticks query>))[0] - OUTSIDE any try; statement faults are
            // conditional; single-row results index into the ROW (first column value).
            string ticksQuery = server.VersionMajor > 9
                ? "SELECT cpu_ticks / CONVERT(FLOAT, (cpu_ticks / ms_ticks)) AS TimeStamp FROM sys.dm_os_sys_info"
                : "SELECT cpu_ticks / CONVERT(FLOAT, cpu_ticks_in_ms) AS TimeStamp FROM sys.dm_os_sys_info";
            object? currentTimestamp = null;
            try
            {
                Collection<PSObject> ticksRows = NestedCommand.InvokeScoped(this, ServerQueryScript, server, ticksQuery);
                if (ticksRows.Count == 1 && ticksRows[0]?.BaseObject is DataRow onlyRow)
                    currentTimestamp = onlyRow[0];
                else if (ticksRows.Count > 0)
                    currentTimestamp = ticksRows[0];
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StatementFault.Surface(this, ex, "Get-DbaCpuRingBuffer");
            }
            WriteMessage(MessageLevel.Verbose, "Using current timestampe of " + PsText(currentTimestamp));

            string sql = RingBufferSqlPart1 + PsText(currentTimestamp) + RingBufferSqlPart2 + CollectionMinutes.ToString(CultureInfo.InvariantCulture) + RingBufferSqlPart3;
            WriteMessage(MessageLevel.Verbose, "Executing Sql Staement: " + sql);

            // PS: foreach ($row in $server.Query($sql)) { [PSCustomObject]@{...} } - the
            // Query statement sits OUTSIDE any try in the function.
            Collection<PSObject>? rows = null;
            try
            {
                rows = NestedCommand.InvokeScoped(this, ServerQueryScript, server, sql);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StatementFault.Surface(this, ex, "Get-DbaCpuRingBuffer");
            }
            if (rows is null)
                continue;
            foreach (PSObject? item in rows)
            {
                if (item?.BaseObject is not DataRow row)
                    continue;
                PSObject result = new PSObject();
                result.Properties.Add(new PSNoteProperty("ComputerName", SmoServerExtensions.GetComputerName(server)));
                result.Properties.Add(new PSNoteProperty("InstanceName", server.ServiceName));
                result.Properties.Add(new PSNoteProperty("SqlInstance", SmoServerExtensions.GetDomainInstanceName(server)));
                result.Properties.Add(new PSNoteProperty("RecordId", row["record_id"]));
                result.Properties.Add(new PSNoteProperty("EventTime", row["EventTime"]));
                result.Properties.Add(new PSNoteProperty("SQLProcessUtilization", row["SQLProcessUtilization"]));
                result.Properties.Add(new PSNoteProperty("OtherProcessUtilization", row["OtherProcessUtilization"]));
                result.Properties.Add(new PSNoteProperty("SystemIdle", row["SystemIdle"]));
                WriteObject(result);
            }
        }
    }

    /// <summary>PS string interpolation via LanguagePrimitives (invariant).</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
    }

    // PS: $server.Query($query) on the engine (the W1-046 seam).
    private const string ServerQueryScript = """
param($server, $query)
$server.Query($query)
""";

    private const string RingBufferSqlPart1 = """
WITH RingBufferSchedulerMonitor AS
                (
                    SELECT
                        timestamp,
                        CONVERT(XML, record) AS record
                    FROM sys.dm_os_ring_buffers
                    WHERE (ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR')
                    AND (record LIKE '%%')
                ), RingBufferSchedulerMonitorValues AS
                (
                    SELECT
                        record.value('(./Record/@id)[1]', 'int') AS record_id,
                        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
                        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization,
                        timestamp,
                        DATEADD(ss, (-1 * (
""";

    private const string RingBufferSqlPart2 = """
 - [timestamp]))/1000, GETDATE()) AS EventTime
                    FROM RingBufferSchedulerMonitor
                )
                SELECT
                    SERVERPROPERTY('ServerName') AS ServerName,
                    record_id,
                    EventTime,
                    SQLProcessUtilization,
                    SystemIdle,
                    100 - SystemIdle - SQLProcessUtilization AS OtherProcessUtilization
                FROM RingBufferSchedulerMonitorValues
                WHERE EventTime > DATEADD(MINUTE, -
""";

    private const string RingBufferSqlPart3 = """
, GETDATE());
""";
}
