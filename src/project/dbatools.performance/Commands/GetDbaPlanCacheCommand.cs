#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaPlanCache.ps1 at refs/pins/dbatools-2026-10-22: one aggregate row of sys.dm_exec_cached_plans per
// instance, the query's own DataRow with a Size note property and the pinned default view.
/// <summary>
/// Retrieves single-use plan cache usage to identify memory waste from adhoc and prepared statements
/// </summary>
/// <para>
/// Analyzes the plan cache to identify memory consumed by single-use adhoc and prepared statements that are unlikely to be reused. These plans accumulate over time and can consume significant memory without providing performance benefits.
/// </para>
/// <para>
/// When applications generate dynamic SQL without proper parameterization, each unique statement creates its own execution plan. These single-use plans waste memory and can cause plan cache pressure, leading to performance issues and increased compilation overhead.
/// </para>
/// <para>
/// The function queries sys.dm_exec_cached_plans to calculate the total size and count of single-use plans. If the results show over 100 MB of single-use plans, consider enabling "optimize for adhoc workloads" (SQL Server 2008+) or use Remove-DbaQueryPlan to clear the cache during maintenance windows.
/// </para>
/// <para>
/// References: https://www.sqlskills.com/blogs/kimberly/plan-cache-adhoc-workloads-and-clearing-the-single-use-plan-cache-bloat/
/// </para>
/// <para>
/// Note: This command returns results from all SQL server instances on the destination server but the process column is specific to -SqlInstance passed.
/// </para>
/// <example>
/// <code>PS C:\&gt; Get-DbaPlanCache -SqlInstance sql2017</code>
/// <para>Returns the single use plan cache usage information for SQL Server instance 2017</para>
/// </example>
/// <example>
/// <code>PS C:\&gt; Get-DbaPlanCache -SqlInstance sql2017 -SqlCredential sqladmin</code>
/// <para>Returns the single use plan cache usage information for SQL Server instance 2017 using login 'sqladmin'</para>
/// </example>
/// <seealso href="https://dbatools.io/Get-DbaPlanCache" />
/// <list type="alertSet">
/// <item><term /><description>
/// <para>Tags: Diagnostic, Cache, Memory</para>
/// <para>Author: Tracy Boggiano, databasesuperhero.com</para>
/// <para>Website: https://dbatools.io</para>
/// <para>Copyright: (c) 2018 by dbatools, licensed under MIT</para>
/// <para>License: MIT https://opensource.org/licenses/MIT</para>
/// </description></item>
/// </list>
[Cmdlet(VerbsCommon.Get, "DbaPlanCache")]
public sealed class GetDbaPlanCacheCommand : DbaInstanceCmdlet
{
    /// <para>The target SQL Server instance or instances.</para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
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

    // PS: $Sql, the pinned query.
    private const string Sql = @"SELECT SERVERPROPERTY('MachineName') AS ComputerName,
    ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
    SERVERPROPERTY('ServerName') AS SqlInstance, MB = SUM(CAST((CASE WHEN usecounts = 1 AND objtype IN ('Adhoc', 'Prepared') THEN size_in_bytes ELSE 0 END) AS DECIMAL(12, 2))) / 1024 / 1024,
    UseCount = SUM(CASE WHEN usecounts = 1 AND objtype IN ('Adhoc', 'Prepared') THEN 1 ELSE 0 END)
    FROM sys.dm_exec_cached_plans;";

    // PS: Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Size, UseCount
    private static readonly string[] DefaultView = { "ComputerName", "InstanceName", "SqlInstance", "Size", "UseCount" };

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            // PS: $results = $server.Query($sql): no try, so a failed query is a statement fault of the process block.
            DataTable? rows;
            try
            {
                DataSet data = server.ConnectionContext.ExecuteWithResults(Sql);
                rows = data.Tables.Count > 0 ? data.Tables[0] : null;
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                ReportFault(QueryRecord(failure));
                // Correction stale-results: the pin's next statements run with $results still holding the previous instance's
                // (or pipeline record's) row and emit that row again; the port goes on to the next instance instead. With no
                // previous row the pin's Add-Member -InputObject $null writes a parameter binding record; the port makes no
                // Add-Member call, so it writes no record for it (keep-going section, point 2).
                continue;
            }

            if (rows is null)
                continue;

            foreach (DataRow row in rows.Rows)
            {
                // PS: $size = [dbasize]($results.MB * 1024 * 1024): decimal arithmetic, then the cast's conversion. A SUM over no
                // cached plan is NULL, which means no single-use plan bytes; the query's own plan is cached, so that row never comes.
                object megabytes = row["MB"];
                decimal bytes = megabytes is DBNull ? 0m : Convert.ToDecimal(megabytes, CultureInfo.InvariantCulture) * 1024m * 1024m;
                Size size = (Size)LanguagePrimitives.ConvertTo(bytes, typeof(Size), CultureInfo.InvariantCulture);

                // PS: Add-Member -Force -InputObject $results -MemberType NoteProperty -Name Size -Value $size
                PSObject result = PSObject.AsPSObject(row);
                result.Properties.Add(new PSNoteProperty("Size", size));

                // PS: Select-DefaultView -InputObject $results -Property ComputerName, InstanceName, SqlInstance, Size, UseCount
                OutputHelper.SetDefaultDisplayPropertySet(result, DefaultView);
                WriteObject(result);
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
