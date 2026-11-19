#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaConnection.ps1 at refs/pins/dbatools-2026-10-22: the connect, the begin-block query over
// sys.dm_exec_connections and its rows, as the DataRows the dbatools Server.Query script method returns.
/// <summary>Returns a bunch of information from dm_exec_connections.</summary>
/// <para>
/// Returns a bunch of information from dm_exec_connections which, according to Microsoft:
/// "Returns information about the connections established to this instance of SQL Server and the details of each connection. Returns server wide connection information for SQL Server. Returns current database connection information for SQL Database."
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaConnection -SqlInstance sql2016, sql2017
/// </code>
/// <para>
/// Returns client connection information from sql2016 and sql2017
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Connection
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaConnection" />
[Cmdlet(VerbsCommon.Get, "DbaConnection")]
public sealed class GetDbaConnectionCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances. Server(s) must be SQL Server 2005 or higher.
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
    [Alias("Credential", "Cred")]
    public override PSCredential? SqlCredential { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    // PS: the begin-block $sql literal verbatim.
    private const string ConnectionSql = @"SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
                            ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                            SERVERPROPERTY('ServerName') AS SqlInstance,
                            session_id AS SessionId, most_recent_session_id AS MostRecentSessionId, connect_time AS ConnectTime,
                            net_transport AS Transport, protocol_type AS ProtocolType, protocol_version AS ProtocolVersion,
                            endpoint_id AS EndpointId, encrypt_option AS EncryptOption, auth_scheme AS AuthScheme, node_affinity AS NodeAffinity,
                            num_reads AS Reads, num_writes AS Writes, last_read AS LastRead, last_write AS LastWrite,
                            net_packet_size AS PacketSize, client_net_address AS ClientNetworkAddress, client_tcp_port AS ClientTcpPort,
                            local_net_address AS ServerNetworkAddress, local_tcp_port AS ServerTcpPort, connection_id AS ConnectionId,
                            parent_connection_id AS ParentConnectionId, most_recent_sql_handle AS MostRecentSqlHandle
                            FROM sys.dm_exec_connections";

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance -MinimumVersion 9 } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 9);
            if (server is null)
                continue;

            WriteMessage(MessageLevel.Debug, "Getting results for the following query: " + ConnectionSql + ".");
            try
            {
                // PS: $server.Query($sql) - the DataTable it returns enumerates its DataRows into the output.
                DataTable? connections = ServerQuery(server);
                if (connections is not null)
                {
                    foreach (DataRow connection in connections.Rows)
                        WriteObject(connection);
                }
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                ReportQueryFailure(server, failure is QueryFault fault ? fault.Record : CaughtRecord(failure));
                continue;
            }
        }
    }

    // PS: catch { Stop-Function -Message "Failure" -Target $server -Exception $_ -Continue }
    // Correction query-failure-stop-function: $_ is an ErrorRecord, which the pinned [System.Exception] parameter cannot
    // take, so Stop-Function never ran (a binding error instead, and -EnableException ignored). The record is passed as
    // the connect catch above passes its own.
    private void ReportQueryFailure(Server server, ErrorRecord caught)
    {
        StopFunction("Failure", target: server, errorRecord: caught, continueLoop: true);
    }

    // PS: $_ for an exception that did not come from the Query script method (a failing downstream command).
    private static ErrorRecord CaughtRecord(Exception failure)
    {
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            return new ErrorRecord(container.ErrorRecord, failure);
        return new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    // PS: $server.Query($sql), the dbatools Server.Query script method without a database: ExecuteWithResults on the
    // connection and its first table. Its catch joins the messages of the exception chain below the method call and
    // throws that text, which the script-method call reports as "Exception calling "Query" ...".
    private static DataTable? ServerQuery(Server server)
    {
        DataSet results;
        try
        {
            results = server.ConnectionContext.ExecuteWithResults(ConnectionSql);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StringBuilder text = new StringBuilder();
            for (Exception? current = failure; current is not null; current = current.InnerException)
                text.Append(current.Message);
            string message = text.ToString();
            MethodInvocationException call = new MethodInvocationException(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message));
            throw new QueryFault(new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null));
        }
        return results.Tables.Count > 0 ? results.Tables[0] : null;
    }

    // Carries the Query script method's fault to the catch that reports it.
    private sealed class QueryFault : Exception
    {
        public QueryFault(ErrorRecord record)
            : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        public ErrorRecord Record { get; }
    }
}
