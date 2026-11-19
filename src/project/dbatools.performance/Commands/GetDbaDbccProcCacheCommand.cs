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

// Port of public/Get-DbaDbccProcCache.ps1 at refs/pins/dbatools-2026-10-22: DBCC PROCCACHE on the connection of each instance, and one object per row.
/// <summary>Retrieves plan cache memory usage statistics from SQL Server instances</summary>
/// <para>
/// Executes DBCC PROCCACHE against SQL Server instances and returns structured information about plan cache memory utilization. This command reveals how much memory is allocated for storing compiled execution plans, how much is currently being used, and how many plan entries are active. Essential for diagnosing memory pressure issues, understanding plan cache efficiency, and monitoring whether the plan cache is consuming excessive memory or experiencing frequent evictions that could impact query performance.
/// </para>
/// <para>
/// Read more:
/// - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-proccache-transact-sql
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbccProcCache -SqlInstance Server1
/// </code>
/// <para>
/// Get results of DBCC PROCCACHE for Instance Server1
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'Sql1','Sql2/sqlexpress' | Get-DbaDbccProcCache
/// </code>
/// <para>
/// Get results of DBCC PROCCACHE for Instances Sql1 and Sql2/sqlexpress
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential sqladmin
/// PS C:\&gt; Get-DbaDbccProcCache -SqlInstance Server1 -SqlCredential $cred
/// </code>
/// <para>
/// Connects using sqladmin credential and gets results of DBCC PROCCACHE for Instance Server1
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: DBCC
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
/// <seealso href="https://dbatools.io/Get-DbaDbccProcCache" />
[Cmdlet(VerbsCommon.Get, "DbaDbccProcCache")]
public sealed class GetDbaDbccProcCacheCommand : DbaInstanceCmdlet
{
    private const string Query = "DBCC PROCCACHE WITH NO_INFOMSGS";

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

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            DataTable? results;
            try
            {
                WriteMessage(MessageLevel.Verbose, "Query to run: " + Query);
                DataSet tables = server.ConnectionContext.ExecuteWithResults(Query);
                results = tables.Tables.Count > 0 ? tables.Tables[0] : null;
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                StopFunction("Failure", target: server, errorRecord: QueryRecord(failure), continueLoop: true);
                continue;
            }

            if (results is null)
                continue;

            foreach (DataRow row in results.Rows)
            {
                PSObject output = new();
                OutputHelper.AddInstanceProperties(output, server);
                output.Properties.Add(new PSNoteProperty("Count", Cell(row, 0)));
                output.Properties.Add(new PSNoteProperty("Used", Cell(row, 1)));
                output.Properties.Add(new PSNoteProperty("Active", Cell(row, 2)));
                output.Properties.Add(new PSNoteProperty("CacheSize", Cell(row, 3)));
                output.Properties.Add(new PSNoteProperty("CacheUsed", Cell(row, 4)));
                output.Properties.Add(new PSNoteProperty("CacheActive", Cell(row, 5)));
                WriteObject(output);
            }
        }
    }

    // PS: $row[n]; an ordinal past the last column reads $null.
    private static object? Cell(DataRow row, int ordinal)
    {
        return ordinal < row.Table.Columns.Count ? row[ordinal] : null;
    }

    // PS: $_ for a failed $server.Query: the script method's catch joins the messages of the exception chain and throws that
    // text, which the method call reports as "Exception calling "Query" ...". As the pin measured, evidence/pin-proccache-20261103.txt, no-permission-ee.
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
