#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbDbccOpenTran.ps1 at refs/pins/dbatools-2026-10-22: the connect, DBCC OPENTRAN per database and
// its rows, as the PSCustomObjects of the pin.
/// <summary>Identifies the oldest active transactions in database transaction logs using DBCC OPENTRAN</summary>
/// <para>
/// Executes DBCC OPENTRAN against specified databases to identify long-running or problematic transactions that may be causing blocking, transaction log growth, or replication delays.
/// </para>
/// <para>
/// This function helps DBAs troubleshoot performance issues by revealing the oldest active transaction and any distributed or replicated transactions within each database's transaction log. When transactions remain open for extended periods, they prevent log truncation and can cause cascading blocking issues throughout your SQL Server instance.
/// </para>
/// <para>
/// The output includes detailed transaction information in structured PowerShell objects, making it easy to identify which transactions need attention. If no active transactions are found, the function clearly indicates this status for each database checked.
/// </para>
/// <para>
/// This is particularly valuable when investigating sudden transaction log growth, diagnosing blocking chains, or troubleshooting replication latency issues where old transactions may be preventing log reader processes from advancing.
/// </para>
/// <para>
/// Read more:
/// - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-opentran-transact-sql
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbDbccOpenTran -SqlInstance SQLServer2017
/// </code>
/// <para>
/// Connects to instance SqlServer2017 using Windows Authentication and runs the command DBCC OPENTRAN WITH TABLERESULTS, NO_INFOMSGS against each database.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbDbccOpenTran -SqlInstance SQLServer2017 -Database CurrentDB
/// </code>
/// <para>
/// Connects to instance SqlServer2017 using Windows Authentication and runs the command DBCC OPENTRAN(CurrentDB) WITH TABLERESULTS, NO_INFOMSGS against the CurrentDB database.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential sqladmin
/// PS C:\&gt; 'Sql1','Sql2/sqlexpress' | Get-DbaDbDbccOpenTran -SqlCredential $cred
/// </code>
/// <para>
/// Connects to instances Sql1 and Sql2/sqlexpress using sqladmin credential and runs the command DBCC OPENTRAN WITH TABLERESULTS, NO_INFOMSGS against each database.
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
/// <seealso href="https://dbatools.io/Get-DbaDbDbccOpenTran" />
[Cmdlet(VerbsCommon.Get, "DbaDbDbccOpenTran")]
public sealed class GetDbaDbDbccOpenTranCommand : DbaInstanceCmdlet
{
    // PS begin block: $stringBuilder.Append(...), constant text.
    private const string Template = "DBCC OPENTRAN(#options#) WITH TABLERESULTS, NO_INFOMSGS";

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

    /// <para>
    /// Specifies which databases to check for open transactions. Accepts database names or database IDs.
    /// Use this when investigating transaction issues in specific databases rather than scanning all databases on the instance.
    /// If omitted, DBCC OPENTRAN runs against all accessible databases, which may take longer on instances with many databases.
    /// </para>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

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
            WriteMessage(MessageLevel.Verbose, String.Format("Attempting Connection to {0}", instance));
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            foreach (SmoDatabase db in SelectDatabases(server))
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Processing {0} on {1}", db, instance));

                if (!db.IsAccessible)
                {
                    StopFunction(String.Format("The database {0} is not accessible. Skipping.", db), continueLoop: true);
                    continue;
                }

                // Correction quoted-database-name: the name stays inside the literal, its quotes doubled.
                string query = Template.Replace("#options#", "'" + db.Name.Replace("'", "''") + "'");
                DataTable? results;
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Query to run: " + query);
                    results = RunQuery(server, db, query);
                    WriteMessage(MessageLevel.Verbose, "Finshed");
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    // PS: Stop-Function ... -ErrorRecord $_ -Exception $_.Exception -Continue; the explicit exception wins.
                    ErrorRecord record = QueryRecord(failure);
                    StopFunction(String.Format("Error capturing data on {0}", db), target: instance, errorRecord: record,
                        exception: record.Exception, continueLoop: true);
                    continue;
                }

                // PS: a table without rows reaches $results as $null through the Query script method's output.
                if (results is null || results.Rows.Count == 0)
                {
                    WriteResult(server, db, query, "No active open transactions.", null, null);
                    continue;
                }

                foreach (DataRow row in results.Rows)
                {
                    // PS: $row[0] and $row[1]; an ordinal past the last column reads $null.
                    int columns = row.Table.Columns.Count;
                    WriteResult(server, db, query, "Oldest active transaction", columns > 0 ? row[0] : null, columns > 1 ? row[1] : null);
                }
            }
        }
    }

    // PS: $dbs = $server.Databases, then under Test-Bound Database:
    // Where-Object { ($_.Name -In $Database) -or ($_.ID -In $Database) }
    private List<SmoDatabase> SelectDatabases(Server server)
    {
        string[] wanted = Database ?? Array.Empty<string>();
        List<SmoDatabase> selected = new();
        foreach (SmoDatabase db in server.Databases)
        {
            if (!TestBound(nameof(Database)) || PsString.In(db.Name, wanted) || PsOps.In(db.ID, wanted))
                selected.Add(db);
        }
        return selected;
    }

    // PS: $server.Query($query), the dbatools Server.Query script method: ExecuteWithResults, then the first table.
    // Correction azure-database-context: an Azure SQL database answers only on its own connection, so there the query runs
    // as $server.Query($query, $db.Name) does, through the database.
    private static DataTable? RunQuery(Server server, SmoDatabase db, string query)
    {
        DataSet results = server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase
            ? db.ExecuteWithResults(query)
            : server.ConnectionContext.ExecuteWithResults(query);
        return results.Tables.Count > 0 ? results.Tables[0] : null;
    }

    // PS: $_ for a failed $server.Query: the script method's catch joins the messages of the exception chain and throws that
    // text, which the method call reports as "Exception calling "Query" ...".
    private static ErrorRecord QueryRecord(Exception failure)
    {
        StringBuilder message = new();
        for (Exception? current = failure; current is not null; current = current.InnerException)
            message.Append(current.Message);
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message.ToString()));
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }

    // PS: the two [PSCustomObject] rows, which differ only in Output, Field and Data.
    private void WriteResult(Server server, SmoDatabase db, string query, string output, object? field, object? data)
    {
        PSObject result = new();
        OutputHelper.AddInstanceProperties(result, server);
        result.Properties.Add(new PSNoteProperty("Database", db.Name));
        result.Properties.Add(new PSNoteProperty("DatabaseId", db.ID));
        result.Properties.Add(new PSNoteProperty("Cmd", query));
        result.Properties.Add(new PSNoteProperty("Output", output));
        result.Properties.Add(new PSNoteProperty("Field", field));
        result.Properties.Add(new PSNoteProperty("Data", data));
        WriteObject(result);
    }
}
