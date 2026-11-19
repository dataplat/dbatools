#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbccMemoryStatus.ps1 at refs/pins/dbatools-2026-10-22: DBCC MEMORYSTATUS through the master database, with the caller's database put back, and one
// object per row of every result set.
/// <summary>Executes DBCC MEMORYSTATUS and returns memory usage details in a structured format</summary>
/// <para>
/// Runs DBCC MEMORYSTATUS against SQL Server instances and parses the output into a structured PowerShell object for analysis. This replaces the need to manually execute DBCC MEMORYSTATUS and interpret its raw text output, making memory troubleshooting and monitoring much easier. The function organizes memory statistics by type (like Memory Manager, Buffer Manager, Resource Pool, etc.) and provides both the metric names and values in a consistent format across multiple instances. Useful for diagnosing memory pressure, understanding memory allocation patterns, and comparing memory usage across environments.
/// </para>
/// <para>
/// Reference:
/// - https://blogs.msdn.microsoft.com/timchapman/2012/08/16/how-to-parse-dbcc-memorystatus-via-powershell/
/// - https://support.microsoft.com/en-us/help/907877/how-to-use-the-dbcc-memorystatus-command-to-monitor-memory-usage-on-sq
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbccMemoryStatus -SqlInstance sqlcluster, sqlserver2012
/// </code>
/// <para>
/// Get output of DBCC MEMORYSTATUS for instances "sqlcluster" and "sqlserver2012". Returns results in a single recordset.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRegServer -SqlInstance sqlcluster | Get-DbaDbccMemoryStatus
/// </code>
/// <para>
/// Get output of DBCC MEMORYSTATUS for all servers in Server Central Management Server
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: DBCC, Memory
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
/// <seealso href="https://dbatools.io/Get-DbaDbccMemoryStatus" />
[Cmdlet(VerbsCommon.Get, "DbaDbccMemoryStatus")]
public sealed class GetDbaDbccMemoryStatusCommand : DbaInstanceCmdlet
{
    private const string Query = "DBCC MEMORYSTATUS";

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

    /// <summary>Reports DBCC MEMORYSTATUS of each instance.</summary>
    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Collecting {0} data from server: {1}", Query, instance));
            ErrorRecord? fault = ReportInstance(server);
            if (fault is not null)
                StopFunction("Failure Executing " + Query, target: instance, errorRecord: fault, continueLoop: true);
        }
    }

    // The source's try: the read and the objects written from it. Returns the record its catch block saw, or null.
    private ErrorRecord? ReportInstance(Server server)
    {
        ErrorRecord? fault = ReadTables(server, out DataTableCollection? tables);
        if (fault is not null)
            return fault;

        try
        {
            int recordSet = 0;
            int rowId = 0;
            foreach (DataTable table in tables!)
            {
                string? type = table.Columns.Count > 0 ? table.Columns[0].ColumnName : null;
                string? valueType = table.Columns.Count > 1 ? table.Columns[1].ColumnName : null;
                recordSet++;
                int recordSetId = 0;
                foreach (DataRow row in table.Rows)
                {
                    rowId++;
                    recordSetId++;
                    PSObject output = new();
                    OutputHelper.AddInstanceProperties(output, server);
                    output.Properties.Add(new PSNoteProperty("RecordSet", recordSet));
                    output.Properties.Add(new PSNoteProperty("RowId", rowId));
                    output.Properties.Add(new PSNoteProperty("RecordSetId", recordSetId));
                    output.Properties.Add(new PSNoteProperty("Type", type));
                    output.Properties.Add(new PSNoteProperty("Name", table.Columns.Count > 0 ? row[0] : null));
                    output.Properties.Add(new PSNoteProperty("Value", table.Columns.Count > 1 ? row[1] : null));
                    output.Properties.Add(new PSNoteProperty("ValueType", valueType));
                    WriteObject(output);
                }
            }
            return null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return StatementFault.Record(failure, "Get-DbaDbccMemoryStatus");
        }
    }

    // PS: $server.query($query, 'master', $true), the pinned Server.Query script method: ExecuteWithResults through the database, every table, and in its finally the connection
    // put back. Returns the record the source's catch block saw, or null.
    private ErrorRecord? ReadTables(Server server, out DataTableCollection? tables)
    {
        tables = null;
        ServerConnection connection = server.ConnectionContext;
        SetActiveConnection(connection);
        string? previous = ContextDatabase(connection);
        try
        {
            // A connection that cannot read the master object leaves the script method's catch nothing to join, so it throws an empty message: as the pin measured on both
            // editions, evidence/pin-memorystatus-20261103.txt, caller-denied.
            SmoDatabase? master = ReadMaster(server);
            if (master is null)
                return QueryRecord("");
            tables = master.ExecuteWithResults(Query).Tables;
            return null;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return QueryRecord(JoinedMessages(failure));
        }
        finally
        {
            PutDatabaseBack(connection, previous);
        }
    }

    private static SmoDatabase? ReadMaster(Server server)
    {
        try
        {
            return server.Databases["master"];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return null;
        }
    }

    // PS: the script method's catch joins the messages of the failure's chain.
    private static string JoinedMessages(Exception failure)
    {
        string message = "";
        Exception current = failure;
        while (current.InnerException is not null)
        {
            message += current.Message;
            current = current.InnerException;
        }
        return message + current.Message;
    }

    // PS: the script method throws the joined text, which the engine reports as the ScriptMethodRuntimeException fault of the method call.
    private static ErrorRecord QueryRecord(string message)
    {
        MethodInvocationException fault = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"query\" with \"3\" argument(s): \"{0}\"", message), new RuntimeException(message, new RuntimeException(message)));
        return new ErrorRecord(fault, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }

    // PS: $connectionContext.CurrentDatabase, which reads $null when its getter throws.
    private static string? ContextDatabase(ServerConnection connection)
    {
        try
        {
            return connection.CurrentDatabase;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return null;
        }
    }

    // PS: the script method's finally. -cne on purpose, because database names follow the instance collation. A failed USE only warns, through the cmdlet's own WriteWarning, so
    // the engine applies the caller's warning preference as for any compiled cmdlet: harness-edits.md, "Database-context restore warning: ports follow the compiled cmdlet's
    // warning preference (operator, 2026-11-15)", point 1; the differences from the script method are its point 3, recorded as restore-warning-engine-preference.
    private void PutDatabaseBack(ServerConnection connection, string? target)
    {
        if (String.IsNullOrEmpty(target) || String.Equals(ContextDatabase(connection), target, StringComparison.Ordinal))
            return;
        try
        {
            connection.ExecuteNonQuery("USE [" + target!.Replace("]", "]]") + "]");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WriteWarning(String.Format(CultureInfo.InvariantCulture, // style-ok: cs-raw-streams the Server.Query script method calls plain Write-Warning, not Write-Message
                "The database context could not be restored to [{0}]: Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{1}\"", target, failure.Message));
        }
    }
}
