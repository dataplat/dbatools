#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves memory pressure notifications and utilization metrics from SQL Server resource monitor ring buffers.
/// </summary>
/// <para>
/// Analyzes SQL Server's internal resource monitor ring buffers to identify memory pressure events and track memory utilization over time. This helps DBAs diagnose performance issues caused by insufficient memory, excessive paging, or memory pressure conditions that trigger automatic memory adjustments.
/// </para>
/// <para>
/// The function returns detailed memory statistics including physical memory usage, page file utilization, virtual address space consumption, and SQL Server-specific memory allocation metrics. Each record includes the exact timestamp when memory conditions were recorded, making it valuable for correlating memory pressure with performance degradation during specific time periods.
/// </para>
/// <para>
/// This command is based on a query provided by Microsoft support and queries the sys.dm_os_ring_buffers DMV to extract resource monitor notifications.
/// </para>
/// <example>
/// <code>PS C:\&gt; Get-DbaMemoryCondition -SqlInstance sqlserver2014a</code>
/// <para>Returns the memory conditions for the selected instance</para>
/// </example>
/// <example>
/// <code>PS C:\&gt; Get-DbaRegServer -SqlInstance sqlserver2014a -Group GroupName | Get-DbaMemoryCondition | Out-GridView</code>
/// <para>Returns the memory conditions for a group of servers from SQL Server Central Management Server (CMS). Send output to GridView.</para>
/// </example>
/// <seealso href="https://dbatools.io/Get-DbaMemoryCondition" />
/// <list type="alertSet">
/// <item><term /><description>
/// <para>Tags: Memory, General</para>
/// <para>Author: IJeb Reitsma</para>
/// <para>Website: https://dbatools.io</para>
/// <para>Copyright: (c) 2018 by dbatools, licensed under MIT</para>
/// <para>License: MIT https://opensource.org/licenses/MIT</para>
/// </description></item>
/// <item><term>OUTPUTS</term><description>
/// <para>PSCustomObject</para>
/// <para>Returns one object per memory pressure notification record found in the SQL Server resource monitor ring buffers. Each object represents a single memory condition event with complete memory utilization metrics at that point in time.</para>
/// <para>Properties:</para>
/// <para>- ComputerName: The computer name of the SQL Server instance</para>
/// <para>- InstanceName: The SQL Server instance name</para>
/// <para>- SqlInstance: The full SQL Server instance name (computer\instance)</para>
/// <para>- Runtime: DateTime when the query was executed in the instance</para>
/// <para>- NotificationTime: Calculated DateTime of when the memory pressure event occurred</para>
/// <para>- NotificationType: Type of memory notification (e.g., Low Physical Memory, Low Page File, Low Virtual Address Space)</para>
/// <para>- MemoryUtilizationPercent: Current memory utilization as a percentage (0-100)</para>
/// <para>- TotalPhysicalMemory: Total physical RAM in bytes; dbasize object convertible to KB, MB, GB, TB</para>
/// <para>- AvailablePhysicalMemory: Free physical RAM in bytes; dbasize object convertible to KB, MB, GB, TB</para>
/// <para>- TotalPageFile: Total page file size in bytes; dbasize object convertible to KB, MB, GB, TB</para>
/// <para>- AvailablePageFile: Free page file size in bytes; dbasize object convertible to KB, MB, GB, TB</para>
/// <para>- TotalVirtualAddressSpace: Total virtual address space in bytes; dbasize object convertible to KB, MB, GB, TB</para>
/// <para>- AvailableVirtualAddressSpace: Free virtual address space in bytes; dbasize object convertible to KB, MB, GB, TB</para>
/// <para>- NodeId: NUMA node identifier (for systems with multiple memory nodes)</para>
/// <para>- SQLReservedMemory: SQL Server reserved memory in bytes; dbasize object convertible to KB, MB, GB, TB</para>
/// <para>- SQLCommittedMemory: SQL Server committed memory in bytes; dbasize object convertible to KB, MB, GB, TB</para>
/// <para>- RecordId: Unique identifier for this record in the ring buffer</para>
/// <para>- Type: Record type from the resource monitor ring buffer</para>
/// <para>- Indicators: Memory pressure indicators value (bit flags representing specific pressure conditions)</para>
/// <para>- RecordTime: Ring buffer record timestamp in milliseconds (raw tick count)</para>
/// <para>- CurrentTime: Current system time in milliseconds (sys.ms_ticks, for reference and time-based calculations)</para>
/// <para>Size properties return dbasize objects that automatically format as human-readable units (Bytes, KB, MB, GB, TB) when displayed or accessed via properties like .Kilobytes, .Megabytes, .Gigabytes, .Terabytes.</para>
/// </description></item>
/// </list>
[Cmdlet(VerbsCommon.Get, "DbaMemoryCondition")]
public sealed class GetDbaMemoryConditionCommand : DbaInstanceCmdlet
{
    /// <para>The target SQL Server instance or instances.</para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance..</para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private const string Sql = @"
    SELECT
        CONVERT(VARCHAR(30), GETDATE(), 121) AS Runtime,
        DATEADD(MILLISECOND, -1 * CONVERT(BIGINT, (sys.ms_ticks - sys.s_ticks*1000) - (a.[RecordTime] - a.[RecordTime_S]*1000)), DATEADD(SECOND, -1 * (sys.s_ticks - a.[RecordTime_S]), GETDATE())) AS NotificationTime,
        [NotificationType],
        [MemoryUtilizationPercent],
        [TotalPhysicalMemoryKB],
        [AvailablePhysicalMemoryKB],
        [TotalPageFileKB],
        [AvailablePageFileKB],
        [TotalVirtualAddressSpaceKB],
        [AvailableVirtualAddressSpaceKB],
        [NodeId],
        [SQLReservedMemoryKB],
        [SQLCommittedMemoryKB],
        [RecordId],
        [Type],
        [Indicators],
        [RecordTime],
        sys.ms_ticks AS [CurrentTime]
    FROM
    (
        SELECT
            x.value('(//Record/ResourceMonitor/Notification)[1]', 'VARCHAR(30)') AS [NotificationType],
            x.value('(//Record/MemoryRecord/MemoryUtilization)[1]', 'BIGINT') AS [MemoryUtilizationPercent],
            x.value('(//Record/MemoryRecord/TotalPhysicalMemory)[1]', 'BIGINT') AS [TotalPhysicalMemoryKB],
            x.value('(//Record/MemoryRecord/AvailablePhysicalMemory)[1]', 'BIGINT') AS [AvailablePhysicalMemoryKB],
            x.value('(//Record/MemoryRecord/TotalPageFile)[1]', 'BIGINT') AS [TotalPageFileKB],
            x.value('(//Record/MemoryRecord/AvailablePageFile)[1]', 'BIGINT') AS [AvailablePageFileKB],
            x.value('(//Record/MemoryRecord/TotalVirtualAddressSpace)[1]', 'BIGINT') AS [TotalVirtualAddressSpaceKB],
            x.value('(//Record/MemoryRecord/AvailableVirtualAddressSpace)[1]', 'BIGINT') AS [AvailableVirtualAddressSpaceKB],
            x.value('(//Record/MemoryNode/@id)[1]', 'BIGINT') AS [NodeId],
            x.value('(//Record/MemoryNode/ReservedMemory)[1]', 'BIGINT') AS [SQLReservedMemoryKB],
            x.value('(//Record/MemoryNode/CommittedMemory)[1]', 'BIGINT') AS [SQLCommittedMemoryKB],
            x.value('(//Record/@id)[1]', 'BIGINT') AS [RecordId],
            x.value('(//Record/@type)[1]', 'VARCHAR(30)') AS [Type],
            CASE WHEN x.exist('//Record/ResourceMonitor/Indicators') = 1
                THEN x.value('(//Record/ResourceMonitor/Indicators)[1]', 'BIGINT')
                ELSE COALESCE(
                    x.value('(//Record/ResourceMonitor/IndicatorsProcess)[1]', 'BIGINT') | x.value('(//Record/ResourceMonitor/IndicatorsSystem)[1]', 'BIGINT'),
                    x.value('(//Record/ResourceMonitor/IndicatorsProcess)[1]', 'BIGINT'),
                    x.value('(//Record/ResourceMonitor/IndicatorsSystem)[1]', 'BIGINT'))
            END AS [Indicators],
            x.value('(//Record/@time)[1]', 'BIGINT') AS [RecordTime],
            CONVERT(BIGINT, x.value('(//Record/@time)[1]', 'BIGINT')/1000) AS [RecordTime_S]
        FROM
        (
            SELECT CAST(record AS XML) FROM sys.dm_os_ring_buffers
            WHERE ring_buffer_type = 'RING_BUFFER_RESOURCE_MONITOR'
        ) AS R(x)
    ) a
    CROSS JOIN
    (
        SELECT
            ms_ticks,
            CONVERT(BIGINT, ms_ticks/1000) AS s_ticks
        FROM sys.dm_os_sys_info
    ) sys
    ORDER BY a.[RecordTime] ASC";

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, minimumVersion: 9);
            if (server is null) continue;

            DataTable? results;
            try
            {
                DataSet data = server.ConnectionContext.ExecuteWithResults(Sql);
                results = data.Tables.Count == 0 ? null : data.Tables[0];
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                string inner = String.Format(CultureInfo.InvariantCulture,
                    "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message);
                string outer = String.Format(CultureInfo.InvariantCulture,
                    "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", inner);
                MethodInvocationException call = new(outer, new MethodInvocationException(inner, failure));
                StopFunction("Issue collecting data", target: instance,
                    errorRecord: new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null));
                continue;
            }

            if (results is null) continue;
            foreach (DataRow row in results.Rows)
            {
                PSObject result;
                try
                {
                    result = new PSObject();
                    OutputHelper.AddInstanceProperties(result, server);
                    foreach (DataColumn column in results.Columns)
                    {
                        string name = column.ColumnName;
                        object value = row[column];
                        if (name.EndsWith("KB", StringComparison.Ordinal))
                        {
                            name = name.Substring(0, name.Length - 2);
                            value = (Size)LanguagePrimitives.ConvertTo(value, typeof(Size), CultureInfo.InvariantCulture) * 1024.0;
                        }
                        result.Properties.Add(new PSNoteProperty(name, value));
                    }
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    ErrorRecord record = StatementFault.Record(failure, "Get-DbaMemoryCondition");
                    if (EnableException)
                        // caller-try: terminate -- -EnableException requests termination on a row conversion fault.
                        ThrowTerminatingError(record); // style-ok: cs-raw-streams preserve statement fault semantics
                    StatementFault.Surface(this, record);
                    continue;
                }
                WriteObject(result);
            }
        }
    }
}
