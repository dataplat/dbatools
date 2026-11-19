#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaIoLatency.ps1 at refs/pins/dbatools-2026-10-22: the rows of sys.dm_io_virtual_file_stats joined to sys.master_files on the
// connection of each instance, one object per database file.
/// <summary>Retrieves I/O latency metrics for all database files to identify storage performance bottlenecks</summary>
/// <para>
/// Queries sys.dm_io_virtual_file_stats to collect detailed I/O performance statistics for every database file on the SQL Server instance. Returns calculated latency metrics including read latency, write latency, and overall latency in milliseconds, plus throughput statistics like average bytes per read and write operation. Essential for diagnosing slow database performance caused by storage bottlenecks, helping you identify which specific database files are experiencing high I/O wait times. Based on Paul Randal's SQL Server performance tuning methodology.
/// </para>
/// <para>
/// Reference:  https://www.sqlskills.com/blogs/paul/how-to-examine-io-subsystem-latencies-from-within-sql-server/
///             https://www.sqlskills.com/blogs/paul/capturing-io-latencies-period-time/
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaIoLatency -SqlInstance sql2008, sqlserver2012
/// </code>
/// <para>
/// Get IO subsystem latency statistics for servers sql2008 and sqlserver2012.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $output = Get-DbaIoLatency -SqlInstance sql2008 | Select-Object * | ConvertTo-DbaDataTable
/// </code>
/// <para>
/// Collects all IO subsystem latency statistics on server sql2008 into a Data Table.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'sql2008','sqlserver2012' | Get-DbaIoLatency
/// </code>
/// <para>
/// Get IO subsystem latency statistics for servers sql2008 and sqlserver2012 via pipline
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential sqladmin
/// PS C:\&gt; Get-DbaIoLatency -SqlInstance sql2008 -SqlCredential $cred
/// </code>
/// <para>
/// Connects using sqladmin credential and returns IO subsystem latency statistics from sql2008
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Diagnostic, IOLatency
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
/// <seealso href="https://dbatools.io/Get-DbaIoLatency" />
[Cmdlet(VerbsCommon.Get, "DbaIoLatency")]
public sealed class GetDbaIoLatencyCommand : DbaInstanceCmdlet
{
    // PS: the select list of the pinned $sql.
    private const string SelectList = @"SELECT
            [vfs].[database_id],
            DB_NAME ([vfs].[database_id]) AS [DatabaseName],
            [vfs].[file_id],
            [mf].[physical_name],
            [num_of_reads],
            [io_stall_read_ms],
            [num_of_writes],
            [io_stall_write_ms],
            [io_stall],
            [num_of_bytes_read],
            [num_of_bytes_written],
            [sample_ms],
            [size_on_disk_bytes],
            [file_handle],
            [ReadLatency] =
            CASE WHEN [num_of_reads] = 0
                THEN 0
                ELSE ([io_stall_read_ms] / [num_of_reads])
            END,
            [WriteLatency] =
                CASE WHEN [num_of_writes] = 0
                    THEN 0
                    ELSE ([io_stall_write_ms] / [num_of_writes])
                END,
            [Latency] =
                CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
                    THEN 0
                    ELSE ([io_stall] / ([num_of_reads] + [num_of_writes]))
                END,
            [AvgBPerRead] =
                CASE WHEN [num_of_reads] = 0
                    THEN 0
                    ELSE ([num_of_bytes_read] / [num_of_reads])
                END,
            [AvgBPerWrite] =
                CASE WHEN [num_of_writes] = 0
                    THEN 0
                    ELSE ([num_of_bytes_written] / [num_of_writes])
                END,
            [AvgBPerTransfer] =
                CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
                    THEN 0
                    ELSE
                        (([num_of_bytes_read] + [num_of_bytes_written]) /
                        ([num_of_reads] + [num_of_writes]))
                    END";

    // PS: $sql, the pinned query over every database's files.
    private const string Sql = SelectList + @"
        FROM sys.dm_io_virtual_file_stats (NULL,NULL) AS [vfs]
        INNER JOIN sys.master_files AS [mf]
            ON [vfs].[database_id] = [mf].[database_id]
            AND [vfs].[file_id] = [mf].[file_id];";

    // Correction azure-files: the pinned select list over the database's own files, for Azure SQL Database, where sys.master_files does not
    // exist and sys.dm_io_virtual_file_stats and sys.database_files do (Microsoft Learn).
    private const string AzureSql = SelectList + @"
        FROM sys.dm_io_virtual_file_stats (DB_ID(), NULL) AS [vfs]
        INNER JOIN sys.database_files AS [mf]
            ON [vfs].[file_id] = [mf].[file_id];";

    // PS: $excludeColumns, the Select-DefaultView -ExcludeProperty list.
    private static readonly string[] ExcludeColumns = { "FileHandle", "ReadLatency", "WriteLatency", "Latency", "AvgBPerRead", "AvgBPerWrite", "AvgBPerTransfer" };

    /// <para>
    /// The SQL Server instance. Server version must be SQL Server version 2008 or higher.
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

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void BeginProcessing()
    {
        // PS: Write-Message -Level Debug -Message $sql
        WriteMessage(MessageLevel.Debug, Sql);
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9 }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 9);
            if (server is null)
                continue;

            // PS: foreach ($row in $server.Query($sql)): the query sits in no try, so a failed query is the engine's statement fault of the foreach.
            // Correction azure-files: on Azure SQL Database the pinned join names sys.master_files, which does not exist there, so the
            // pin reported a failed query and no file; the database's own files are read from sys.database_files instead.
            string sql = server.DatabaseEngineEdition == DatabaseEngineEdition.SqlDatabase ? AzureSql : Sql;

            DataTable? rows;
            try
            {
                DataSet results = server.ConnectionContext.ExecuteWithResults(sql);
                rows = results.Tables.Count > 0 ? results.Tables[0] : null;
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                ReportFault(QueryRecord(failure));
                continue;
            }

            if (rows is null)
                continue;

            foreach (DataRow row in rows.Rows)
            {
                PSObject output = new();
                OutputHelper.AddInstanceProperties(output, server);
                output.Properties.Add(new PSNoteProperty("DatabaseId", row["database_id"]));
                output.Properties.Add(new PSNoteProperty("DatabaseName", row["DatabaseName"]));
                output.Properties.Add(new PSNoteProperty("FileId", row["file_id"]));
                output.Properties.Add(new PSNoteProperty("PhysicalName", row["physical_name"]));
                output.Properties.Add(new PSNoteProperty("NumberOfReads", row["num_of_reads"]));
                output.Properties.Add(new PSNoteProperty("IoStallRead", row["io_stall_read_ms"]));
                output.Properties.Add(new PSNoteProperty("NumberOfwrites", row["num_of_writes"]));
                output.Properties.Add(new PSNoteProperty("IoStallWrite", row["io_stall_write_ms"]));
                output.Properties.Add(new PSNoteProperty("IoStall", row["io_stall"]));
                output.Properties.Add(new PSNoteProperty("NumberOfBytesRead", row["num_of_bytes_read"]));
                output.Properties.Add(new PSNoteProperty("NumberOfBytesWritten", row["num_of_bytes_written"]));
                output.Properties.Add(new PSNoteProperty("SampleMilliseconds", row["sample_ms"]));
                output.Properties.Add(new PSNoteProperty("SizeOnDiskBytes", row["size_on_disk_bytes"]));
                output.Properties.Add(new PSNoteProperty("FileHandle", row["file_handle"]));
                output.Properties.Add(new PSNoteProperty("ReadLatency", row["ReadLatency"]));
                output.Properties.Add(new PSNoteProperty("WriteLatency", row["WriteLatency"]));
                output.Properties.Add(new PSNoteProperty("Latency", row["Latency"]));
                output.Properties.Add(new PSNoteProperty("AvgBPerRead", row["AvgBPerRead"]));
                output.Properties.Add(new PSNoteProperty("AvgBPerWrite", row["AvgBPerWrite"]));
                output.Properties.Add(new PSNoteProperty("AvgBPerTransfer", row["AvgBPerTransfer"]));

                // PS: | Select-DefaultView -ExcludeProperty $excludeColumns
                OutputHelper.SetDefaultDisplayPropertySetExcluding(output, ExcludeColumns);
                WriteObject(output);
            }
        }
    }

    // A statement of the pin's body with no try around it: a plain call writes the record and goes on, a caller's try
    // catches it, -EnableException stops here (the keep-going section's accepted difference).
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        StatementFault.Surface(this, fault);
    }

    // PS: the record of a failed $server.Query($sql): the script method's catch joins the messages of the exception chain
    // and throws that text, which the method call reports as "Exception calling "Query" with "1" argument(s)".
    private static ErrorRecord QueryRecord(Exception failure)
    {
        StringBuilder joined = new();
        for (Exception? current = failure; current is not null; current = current.InnerException)
            joined.Append(current.Message);
        string message = joined.ToString();
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message, new RuntimeException(message)));
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }
}
