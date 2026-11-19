#nullable enable
using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves detailed information about open database transactions across SQL Server instances.
/// </summary>
/// <para>
/// Queries SQL Server dynamic management views to identify open transactions that may be causing blocking, consuming transaction log space, or impacting performance. Returns comprehensive details including session information, database context, transaction duration, log space usage, and the last executed query with its execution plan.
///
/// This is particularly useful when troubleshooting blocking issues, investigating long-running transactions, or monitoring transaction log growth. The function helps DBAs quickly identify which sessions are holding transactions open and assess their potential impact on system performance.
///
/// This command is based on the open transaction monitoring script published by Paul Randal.
/// Reference: https://www.sqlskills.com/blogs/paul/script-open-transactions-with-text-and-plans/
/// </para>
/// <para>
/// Tags: Diagnostic, Process, Session, ActivityMonitor
/// Author: Chrissy LeMaire (@cl), netnerds.net
///
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// <para>
/// System.Management.Automation.PSCustomObject
///
/// Returns one object per open transaction found on the specified instance(s). If no open transactions exist, nothing is returned.
///
/// Properties:
/// - ComputerName: The name of the computer hosting the SQL Server instance
/// - InstanceName: The SQL Server instance name (defaults to 'MSSQLSERVER' for default instances)
/// - SqlInstance: The full SQL Server instance name as registered on the server
/// - Spid: The session ID (process ID) of the session holding the open transaction
/// - Login: The login name associated with the session
/// - Database: The name of the database in which the transaction is open
/// - BeginTime: DateTime when the transaction began
/// - LogBytesUsed: Number of bytes of transaction log space currently used by this transaction
/// - LogBytesReserved: Number of bytes of transaction log space reserved by this transaction
/// - LastQuery: The text of the most recently executed SQL command in the session
/// - LastPlan: The execution plan XML for the most recently executed query (can be NULL if not available)
/// </para>
/// <para>
/// https://dbatools.io/Get-DbaOpenTransaction
/// </para>
/// <example>
/// PS C:\&gt; Get-DbaOpenTransaction -SqlInstance sqlserver2014a
///
/// Returns open transactions for sqlserver2014a
/// </example>
/// <example>
/// PS C:\&gt; Get-DbaOpenTransaction -SqlInstance sqlserver2014a -SqlCredential sqladmin
///
/// Logs into sqlserver2014a using the login "sqladmin"
/// </example>
[Cmdlet(VerbsCommon.Get, "DbaOpenTransaction")]
public sealed class GetDbaOpenTransactionCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The SQL Server instance
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = Array.Empty<DbaInstanceParameter>();

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    ///
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    ///
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
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
            SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
            ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
            SERVERPROPERTY('ServerName') AS SqlInstance,
            [s_tst].[session_id] AS Spid,
            [s_es].[login_name] AS Login,
            DB_NAME (s_tdt.database_id) AS [Database],
            [s_tdt].[database_transaction_begin_time] AS [BeginTime],
            [s_tdt].[database_transaction_log_bytes_used] AS [LogBytesUsed],
            [s_tdt].[database_transaction_log_bytes_reserved] AS [LogBytesReserved],
            [s_est].text AS [LastQuery],
            [s_eqp].[query_plan] AS [LastPlan]
            FROM
                sys.dm_tran_database_transactions [s_tdt]
            JOIN
                sys.dm_tran_session_transactions [s_tst]
            ON
                [s_tst].[transaction_id] = [s_tdt].[transaction_id]
            JOIN
                sys.dm_exec_sessions [s_es]
            ON
                [s_es].[session_id] = [s_tst].[session_id]
            JOIN
                sys.dm_exec_connections [s_ec]
            ON
                [s_ec].[session_id] = [s_tst].[session_id]
            LEFT OUTER JOIN
                sys.dm_exec_requests [s_er]
            ON
                [s_er].[session_id] = [s_tst].[session_id]
            CROSS APPLY
                sys.dm_exec_sql_text ([s_ec].[most_recent_sql_handle]) AS [s_est]
            OUTER APPLY
                sys.dm_exec_query_plan ([s_er].[plan_handle]) AS [s_eqp]
            ORDER BY
                [BeginTime] ASC";

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, minimumVersion: 9);
            if (server is null) continue;
            DataSet data;
            try { data = server.ConnectionContext.ExecuteWithResults(Sql); }
            catch (PipelineStoppedException) { throw; }
            catch (Exception failure)
            {
                // Server.Query in the pin flattens the SMO exception chain, throws that text,
                // and the one-argument script method invocation supplies the causal wrapper.
                StringBuilder message = new();
                for (Exception? cause = failure; cause is not null; cause = cause.InnerException) message.Append(cause.Message);
                string text = message.ToString();
                MethodInvocationException call = new(string.Format(CultureInfo.InvariantCulture,
                    "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", text),
                    new RuntimeException(text, new RuntimeException(text)));
                ErrorRecord record = new(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
                if (EnableException) base.ThrowTerminatingError(record); // caller-try: terminate -- explicit EnableException.
                StatementFault.Surface(this, record);
                continue;
            }
            if (data.Tables.Count > 0)
                foreach (DataRow row in data.Tables[0].Rows) WriteObject(row);
        }
    }
}
