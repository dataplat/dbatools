#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbMemoryUsage.ps1 at refs/pins/dbatools-2026-10-22: the buffer pool read from sys.dm_os_buffer_descriptors,
// filtered by database in the client, one object per database and page type.
/// <summary>Retrieves detailed buffer pool memory consumption by database and page type for performance analysis.</summary>
/// <para>
/// Analyzes SQL Server buffer pool memory usage by querying sys.dm_os_buffer_descriptors to show exactly how much memory each database consumes, broken down by page type (data pages, index pages, etc.). This helps DBAs identify memory-hungry databases that may be impacting instance performance and guides decisions about memory allocation, database optimization, or server capacity planning.
/// </para>
/// <para>
/// The results include both raw page counts and percentage of total buffer pool consumed, making it easy to spot databases that are taking disproportionate memory resources. Use this when troubleshooting memory pressure, planning database migrations, or optimizing buffer pool utilization across multiple databases.
/// </para>
/// <para>
/// This command is based on query provided by Aaron Bertrand.
/// Reference: https://www.mssqltips.com/sqlservertip/2393/determine-sql-server-memory-use-by-database-and-object/
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMemoryUsage -SqlInstance sqlserver2014a
/// </code>
/// <para>
/// Returns the buffer pool consumption for all user databases
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMemoryUsage -SqlInstance sqlserver2014a -IncludeSystemDb
/// </code>
/// <para>
/// Returns the buffer pool consumption for all user databases and system databases
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMemoryUsage -SqlInstance sql1 -IncludeSystemDb -Database tempdb
/// </code>
/// <para>
/// Returns the buffer pool consumption for tempdb database only
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMemoryUsage -SqlInstance sql2 -IncludeSystemDb -Exclude 'master','model','msdb','ResourceDb'
/// </code>
/// <para>
/// Returns the buffer pool consumption for all user databases and tempdb database
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Memory, Database
/// Author: Shawn Melton (@wsmelton), wsmelton.github.io
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbMemoryUsage" />
[Cmdlet(VerbsCommon.Get, "DbaDbMemoryUsage")]
public sealed class GetDbaDbMemoryUsageCommand : DbaInstanceCmdlet
{
    // A buffer pool page, the unit of sys.dm_os_buffer_descriptors.
    private const long PageBytes = 8192;

    // PS: the begin block's query.
    private const string MemoryUsageQuery = @"DECLARE @total_buffer INT;
            SELECT @total_buffer = cntr_value
            FROM sys.dm_os_performance_counters
            WHERE RTRIM([object_name]) LIKE '%Buffer Manager'
                AND counter_name = 'Database Pages';

            ;WITH src AS (
                SELECT database_id, page_type, db_buffer_pages = COUNT_BIG(*)
                FROM sys.dm_os_buffer_descriptors
                GROUP BY database_id, page_type
            )
            SELECT [DatabaseName] = CASE [database_id] WHEN 32767 THEN 'ResourceDb' ELSE DB_NAME([database_id]) END,
                page_type AS 'PageType',
                db_buffer_pages AS 'PageCount',
                CAST(db_buffer_pages * 100.0 / @total_buffer AS FLOAT) AS 'PercentUsed'
            FROM src
            ORDER BY [DatabaseName];";

    private static readonly string[] SystemDatabases = { "master", "model", "msdb", "tempdb", "ResourceDb" };

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
    /// For MFA support, please use Connect-DbaInstance..
    /// </para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Restricts analysis to specific databases by name. Accepts multiple database names or wildcard patterns.
    /// Use this when investigating memory usage for particular databases rather than analyzing the entire instance.
    /// </para>
    [Parameter(Position = 2, ValueFromPipelineByPropertyName = true)]
    public object[]? Database { get; set; }

    /// <para>
    /// Excludes specific databases from the memory analysis by name. Accepts multiple database names.
    /// Useful for filtering out known databases that aren't relevant to your current investigation or capacity planning.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <para>
    /// Includes system databases (master, model, msdb, tempdb, ResourceDb) in the memory consumption analysis.
    /// Use this when troubleshooting overall instance memory pressure or when tempdb memory usage is a concern.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeSystemDb { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance -MinimumVersion 9 } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 9);
            if (server is null)
                continue;

            ErrorRecord? fault = ReadRows(server, out DataTable? rows);
            if (fault is not null)
            {
                // Upstream correction (wrong data): the pinned Stop-Function has no -Continue, so the rows of the instance
                // before this one were written again, under this instance's name.
                StopFunction("Issue collecting data", target: instance, errorRecord: fault, continueLoop: true);
                continue;
            }

            if (rows is not null)
                WriteRows(server, rows);
        }
    }

    // PS: the foreach over $results. Test-Bound decides the first two filters, so a bound null or empty -Database selects nothing.
    private void WriteRows(Server server, DataTable rows)
    {
        // Upstream correction (dead parameter): the pinned help documents wildcards for -Database, which the literal -notin never
        // honoured. The rows hold the names this filter can reach, so they decide which pattern values are real names and stay literal.
        List<string> names = new();
        foreach (DataRow row in rows.Rows)
        {
            if (row["DatabaseName"] is string name)
                names.Add(name);
        }
        WildcardNameMatcher included = WildcardNameFilter.CreateMatcher(Database, true, (value, name) => PsOps.In(name, new[] { value }), names);

        foreach (DataRow row in rows.Rows)
        {
            object databaseName = row["DatabaseName"];
            // PS: $row.DatabaseName -notin $Database. A hidden name stays DBNull for that comparison: no null value or pattern selects it, '' does.
            if (TestBound("Database") && !(databaseName is string rowName ? included.Matches(rowName) : PsOps.In(databaseName, Database)))
                continue;
            if (TestBound("ExcludeDatabase") && PsOps.In(databaseName, ExcludeDatabase))
                continue;
            // Upstream correction (dead parameter): the pinned Test-Bound took -IncludeSystemDb:$false for the switch itself.
            if (!IncludeSystemDb.IsPresent && PsOps.In(databaseName, SystemDatabases))
                continue;

            long pages = (long)row["PageCount"];
            int pageCount;
            try
            {
                // PS: PageCount = [int]$row.PageCount, inside the statement that builds the row: past Int32, 16 TiB of one page type
                // in one database, that statement faults and the next row is read.
                pageCount = (int)LanguagePrimitives.ConvertTo(pages, typeof(int), CultureInfo.InvariantCulture);
            }
            catch (PSInvalidCastException failure)
            {
                ReportRowFault(StatementFault.Record(failure, "InvalidCastIConvertible"));
                continue;
            }

            // PS: DBNull, a counter the instance does not have, reads as 0; otherwise [Math]::Round($row.PercentUsed).
            object percent = row["PercentUsed"];
            object percentUsed = percent is DBNull ? (object)0 : Math.Round((double)percent);

            PSObject output = new();
            OutputHelper.AddInstanceProperties(output, server);
            output.Properties.Add(new PSNoteProperty("Database", databaseName));
            output.Properties.Add(new PSNoteProperty("PageType", row["PageType"]));
            output.Properties.Add(new PSNoteProperty("PageCount", pageCount));
            // Upstream correction (wrong data): [DbaSize]$row.SizeMb * 1024 multiplied a megabyte count once where it takes twice,
            // and from a count already rounded down, so the size read 1024 times too small. The size is the pages themselves.
            output.Properties.Add(new PSNoteProperty("Size", new Size(pages * PageBytes)));
            output.Properties.Add(new PSNoteProperty("PercentUsed", percentUsed));
            OutputHelper.SetDefaultDisplayPropertySetExcluding(output, new[] { "PageCount" });
            WriteObject(output);
        }
    }

    // The pinned row statement's fault: it stops the command only inside a caller try, or under -EnableException by the operator's rule.
    private void ReportRowFault(ErrorRecord record)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(record); // style-ok: cs-raw-streams pinned statement fault outside Stop-Function
        }
        StatementFault.Surface(this, record);
    }

    // PS: $server.Query($sql), the dbatools Server.Query script method without a database: ExecuteWithResults on the connection and
    // its first table. Its catch joins the messages of the exception chain and throws that text, which the script-method call
    // reports as "Exception calling "Query" ...". Returns the record the source's catch block saw, or null.
    private static ErrorRecord? ReadRows(Server server, out DataTable? rows)
    {
        rows = null;
        try
        {
            DataSet results = server.ConnectionContext.ExecuteWithResults(MemoryUsageQuery);
            if (results.Tables.Count > 0)
                rows = results.Tables[0];
            return null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
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
}
