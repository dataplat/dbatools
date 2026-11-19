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

// Port of public/Get-DbaLatchStatistic.ps1 at refs/pins/dbatools-2026-10-22: the latch classes of sys.dm_os_latch_stats that make up the
// threshold's share of the latch wait time, read on the connection of each instance, one object per latch class.
/// <summary>Retrieves latch contention statistics from SQL Server to identify performance bottlenecks</summary>
/// <para>
/// Analyzes latch wait statistics from sys.dm_os_latch_stats to help identify latch contention issues that may be causing performance problems. This function implements Paul Randal's methodology for latch troubleshooting by returning the most significant latch classes based on cumulative wait time percentage. Each result includes direct links to SQLSkills documentation explaining what each latch class means and how to resolve related issues, making it easier to diagnose and fix latch-related performance bottlenecks without manually querying system DMVs.
/// </para>
/// <para>
/// Returns:
///         LatchClass
///         WaitSeconds
///         WaitCount
///         Percentage
///         AverageWaitSeconds
///         URL
/// </para>
/// <para>
/// Reference:  https://www.sqlskills.com/blogs/paul/advanced-performance-troubleshooting-waits-latches-spinlocks/
///             https://www.sqlskills.com/blogs/paul/most-common-latch-classes-and-what-they-mean/
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaLatchStatistic -SqlInstance sql2008, sqlserver2012
/// </code>
/// <para>
/// Check latch statistics for servers sql2008 and sqlserver2012
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaLatchStatistic -SqlInstance sql2008 -Threshold 98
/// </code>
/// <para>
/// Check latch statistics on server sql2008 for thresholds above 98%
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $output = Get-DbaLatchStatistic -SqlInstance sql2008 -Threshold 100 | Select-Object * | ConvertTo-DbaDataTable
/// </code>
/// <para>
/// Collects all latch statistics on server sql2008 into a Data Table.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'sql2008','sqlserver2012' | Get-DbaLatchStatistic
/// </code>
/// <para>
/// Get latch statistics for servers sql2008 and sqlserver2012 via pipline
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential sqladmin
/// PS C:\&gt; Get-DbaLatchStatistic -SqlInstance sql2008 -SqlCredential $cred
/// </code>
/// <para>
/// Connects using sqladmin credential and returns latch statistics from sql2008
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $output = Get-DbaLatchStatistic -SqlInstance sql2008
/// PS C:\&gt; $output
/// PS C:\&gt; foreach ($row in ($output | Sort-Object -Unique Url)) { Start-Process ($row).Url }
/// </code>
/// <para>
/// Displays the output then loads the associated sqlskills website for each result. Opens one tab per unique URL.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: LatchStatistics, Waits
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
/// <seealso href="https://dbatools.io/Get-DbaLatchStatistic" />
[Cmdlet(VerbsCommon.Get, "DbaLatchStatistic")]
public sealed class GetDbaLatchStatisticCommand : DbaInstanceCmdlet
{
    // PS: $sql of the begin block, up to the -Threshold it ends with.
    private const string SqlBeforeThreshold = @"WITH [Latches] AS
               (
                   SELECT
                       [latch_class],
                       [wait_time_ms] / 1000.0 AS [WaitS],
                       [waiting_requests_count] AS [WaitCount],
                       CASE WHEN SUM([wait_time_ms]) OVER() > 0 THEN 100.0 * [wait_time_ms] / SUM([wait_time_ms]) OVER() END AS [Percentage],
                       ROW_NUMBER() OVER(ORDER BY [wait_time_ms] DESC) AS [RowNum]
                   FROM sys.dm_os_latch_stats
                   WHERE [latch_class] NOT IN (N'BUFFER')
               )
               SELECT
                   MAX ([W1].[latch_class]) AS [LatchClass],
                   CAST (MAX ([W1].[WaitS]) AS DECIMAL(14, 2)) AS [WaitSeconds],
                   MAX ([W1].[WaitCount]) AS [WaitCount],
                   CAST (MAX ([W1].[Percentage]) AS DECIMAL(14, 2)) AS [Percentage],
                   CAST (CASE WHEN MAX([W1].[WaitCount]) > 0 THEN MAX([W1].[WaitS]) / MAX([W1].[WaitCount]) END AS DECIMAL (14, 4)) AS [AvgWaitSeconds],
                   CAST ('https://www.sqlskills.com/help/latches/' + MAX ([W1].[latch_class]) AS XML) AS [URL]
               FROM [Latches] AS [W1]
               INNER JOIN [Latches] AS [W2]
                   ON [W2].[RowNum] <= [W1].[RowNum]
               GROUP BY [W1].[RowNum]
               HAVING SUM ([W2].[Percentage]) - MAX ([W1].[Percentage]) < ";

    private string _sql = String.Empty;

    /// <para>
    /// The SQL Server instance. Server version must be SQL Server version 2005 or higher.
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
    /// Specifies the cumulative percentage threshold for filtering which latch classes to return. Only returns latch classes that contribute to the specified percentage of total wait time.
    /// Use this to focus on the most significant latch contention issues by excluding less impactful latch classes from the results. Default is 95% per Paul Randal's methodology.
    /// </para>
    [Parameter(Position = 2)]
    public int Threshold { get; set; } = 95;

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
        // PS: "... < $Threshold;": an [int] in the string, written as PowerShell writes an integer, so no caller text reaches the batch.
        _sql = SqlBeforeThreshold + Threshold.ToString(CultureInfo.InvariantCulture) + ";";

        // PS: Write-Message -Level Debug -Message $sql
        WriteMessage(MessageLevel.Debug, _sql);
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
            DataTable? rows;
            try
            {
                DataSet results = server.ConnectionContext.ExecuteWithResults(_sql);
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
                output.Properties.Add(new PSNoteProperty("WaitType", row["LatchClass"]));
                output.Properties.Add(new PSNoteProperty("WaitSeconds", row["WaitSeconds"]));
                output.Properties.Add(new PSNoteProperty("WaitCount", row["WaitCount"]));
                output.Properties.Add(new PSNoteProperty("Percentage", row["Percentage"]));
                output.Properties.Add(new PSNoteProperty("AverageWaitSeconds", row["AvgWaitSeconds"]));
                output.Properties.Add(new PSNoteProperty("URL", row["URL"]));
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
