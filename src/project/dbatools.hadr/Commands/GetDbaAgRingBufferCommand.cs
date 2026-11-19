#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaAgRingBuffer.ps1 at refs/pins/dbatools-2026-10-22: per instance the connect (SQL Server 2012
// or later), the scalar CPU-tick timestamp, the HADR ring buffer query with the pinned text and the output rows run
// here in C#; both queries and the row output share the pinned try, whose catch is the "Failed to query" Stop-Function.
/// <summary>Retrieves Always On availability group diagnostic data from SQL Server's internal HADR ring buffers.</summary>
/// <para>
/// This command queries sys.dm_os_ring_buffers for HADR-specific ring buffer types to provide diagnostic
/// information about Always On availability groups. These ring buffers record state transitions, role changes,
/// commit activity, and transport state events useful for troubleshooting AG health and failover issues.
/// </para>
/// <para>
/// As noted in Microsoft's documentation, the ring buffers are not officially supported, but they provide
/// valuable post-mortem diagnostic data, especially when SQL Server stops responding or has crashed.
/// </para>
/// <para>
/// Reference: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-ring-buffers
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgRingBuffer -SqlInstance sql2019
/// </code>
/// <para>
/// Returns HADR ring buffer records from the last 60 minutes from the sql2019 instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgRingBuffer -SqlInstance sql2019 -CollectionMinutes 240
/// </code>
/// <para>
/// Returns HADR ring buffer records from the last 240 minutes from the sql2019 instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgRingBuffer -SqlInstance sql2019 -RingBufferType RING_BUFFER_HADRDBMGR_API
/// </code>
/// <para>
/// Returns only RING_BUFFER_HADRDBMGR_API records from the last 60 minutes from the sql2019 instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgRingBuffer -SqlInstance sql2019 -RingBufferType RING_BUFFER_HADRDBMGR_API, RING_BUFFER_HADR_TRANSPORT_STATE
/// </code>
/// <para>
/// Returns API and transport state records from sql2019.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'sql2019', 'sql2022' | Get-DbaAgRingBuffer
/// </code>
/// <para>
/// Returns all HADR ring buffer records from sql2019 and sql2022.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Diagnostic, Buffer, HADR, AvailabilityGroup, AG, AlwaysOn
/// Author: the dbatools team + Claude
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaAgRingBuffer" />
[Cmdlet(VerbsCommon.Get, "DbaAgRingBuffer")]
public sealed class GetDbaAgRingBufferCommand : DbaInstanceCmdlet
{
    // Positions follow the pinned function's automatic positional binding: every non-switch parameter in order.

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
    /// For MFA support, please use Connect-DbaInstance. To use:
    /// $cred = Get-Credential, this pass this $cred to the param.
    /// </para>
    /// <para>
    /// Windows Authentication will be used if SqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.
    /// </para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies which HADR ring buffer types to query. Defaults to all four HADR ring buffer types.
    /// </para>
    /// <para>
    /// Valid values:
    /// - RING_BUFFER_HADRDBMGR_API       : State transitions at the API level
    /// - RING_BUFFER_HADRDBMGR_STATE     : Database manager state change records
    /// - RING_BUFFER_HADRDBMGR_COMMIT    : Commit-level activity records
    /// - RING_BUFFER_HADR_TRANSPORT_STATE: Connection and transport state transitions
    /// </para>
    [Parameter(Position = 2)]
    [ValidateSet("RING_BUFFER_HADRDBMGR_API", "RING_BUFFER_HADRDBMGR_STATE", "RING_BUFFER_HADRDBMGR_COMMIT", "RING_BUFFER_HADR_TRANSPORT_STATE")]
    public string[]? RingBufferType { get; set; }

    /// <para>
    /// Specifies how many minutes of historical data to retrieve from the ring buffer. Defaults to 60 minutes.
    /// Use this to extend the analysis window when investigating longer-term AG issues or to focus on recent activity with shorter periods.
    /// </para>
    [Parameter(Position = 3)]
    public int CollectionMinutes { get; set; } = 60;

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private const string TimestampQuery = "SELECT cpu_ticks / CONVERT(FLOAT, (cpu_ticks / ms_ticks)) AS TimeStamp FROM sys.dm_os_sys_info";

    private const string AllRingBufferTypes = "N'RING_BUFFER_HADRDBMGR_API', N'RING_BUFFER_HADRDBMGR_STATE', N'RING_BUFFER_HADRDBMGR_COMMIT', N'RING_BUFFER_HADR_TRANSPORT_STATE'";

    // The pinned query text, line breaks and indentation included (the verbose message shows it). {0} is the type list
    // ($typeList: ValidateSet values only), {1} the [long] timestamp and {2} the [int] -CollectionMinutes: no caller text.
    private const string RingBufferQueryFormat = @"WITH HadrRingBuffer AS
                    (
                        SELECT
                            ring_buffer_type,
                            timestamp,
                            CONVERT(XML, record) AS record
                        FROM sys.dm_os_ring_buffers
                        WHERE ring_buffer_type IN ({0})
                    )
                    SELECT
                        SERVERPROPERTY('ServerName') AS ServerName,
                        ring_buffer_type,
                        record.value('(./Record/@id)[1]', 'int') AS record_id,
                        DATEADD(ms, -1 * ({1} - [timestamp]), GETDATE()) AS EventTime,
                        record
                    FROM HadrRingBuffer
                    WHERE DATEADD(ms, -1 * ({1} - [timestamp]), GETDATE()) > DATEADD(MINUTE, -{2}, GETDATE())
                    ORDER BY EventTime DESC;";

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance -MinimumVersion 11 } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 11);
            if (server is null)
            {
                continue;
            }

            try
            {
                // PS: [long]$currentTimestamp = ($server.Query("SELECT ... FROM sys.dm_os_sys_info")).TimeStamp
                long currentTimestamp = (long)LanguagePrimitives.ConvertTo(ReadTimestamp(Query(server, TimestampQuery)), typeof(long), CultureInfo.InvariantCulture);
                WriteMessage(MessageLevel.Verbose, string.Format(CultureInfo.InvariantCulture, "Using current timestamp of {0}", currentTimestamp));

                // PS: ($RingBufferType | ForEach-Object { "N'$_'" }) -join ", "; the values are ValidateSet members, and
                // doubling quotes as for any N'' literal leaves them unchanged.
                string typeList = LanguagePrimitives.IsTrue(RingBufferType)
                    ? string.Join(", ", Array.ConvertAll(RingBufferType!, type => "N'" + type.Replace("'", "''") + "'"))
                    : AllRingBufferTypes;

                string sql = string.Format(CultureInfo.InvariantCulture, RingBufferQueryFormat, typeList, currentTimestamp, CollectionMinutes);
                WriteMessage(MessageLevel.Verbose, "Executing SQL Statement: " + sql);
                foreach (DataRow row in Query(server, sql).Rows)
                {
                    PSObject output = new();
                    OutputHelper.AddInstanceProperties(output, server);
                    output.Properties.Add(new PSNoteProperty("RingBufferType", row["ring_buffer_type"]));
                    output.Properties.Add(new PSNoteProperty("RecordId", row["record_id"]));
                    output.Properties.Add(new PSNoteProperty("EventTime", row["EventTime"]));
                    output.Properties.Add(new PSNoteProperty("Record", row["record"]));
                    WriteObject(output);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                // PS: Stop-Function -Message "Failed to query HADR ring buffer data." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                ErrorRecord record = ex is QueryFailure failure ? failure.Record : new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.NotSpecified, null);
                StopFunction("Failed to query HADR ring buffer data.", target: instance, errorRecord: record, category: ErrorCategory.InvalidOperation, continueLoop: true);
            }
        }
    }

    // PS: (...).TimeStamp - member enumeration over the table's rows: one row gives its value, none gives $null.
    private static object? ReadTimestamp(DataTable table)
    {
        if (table.Rows.Count == 0)
        {
            return null;
        }
        if (table.Rows.Count == 1)
        {
            return table.Rows[0]["TimeStamp"];
        }
        object[] values = new object[table.Rows.Count];
        for (int index = 0; index < values.Length; index++)
        {
            values[index] = table.Rows[index]["TimeStamp"];
        }
        return values;
    }

    // PS: $server.Query($sql), the dbatools Server.Query script method: ConnectionContext.ExecuteWithResults, first table.
    // Its catch throws the concatenated exception chain, which reaches the caller's catch as the method call's
    // ScriptMethodRuntimeException record.
    private static DataTable Query(Server server, string sql)
    {
        try
        {
            return server.ConnectionContext.ExecuteWithResults(sql).Tables[0];
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            string message = string.Empty;
            for (Exception? error = ex; error is not null; error = error.InnerException)
            {
                message += error.Message;
            }
            MethodInvocationException call = new(string.Format("Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message));
            throw new QueryFailure(new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null));
        }
    }

    // Carries the Query failure's record to the pinned catch.
    private sealed class QueryFailure : Exception
    {
        internal QueryFailure(ErrorRecord record) : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        internal ErrorRecord Record { get; }
    }
}
