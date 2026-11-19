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
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves active SQL Server processes and sessions with detailed connection and activity information.</summary>
/// <para>
/// Displays comprehensive information about SQL Server processes including session details, connection properties, timing data, and the last executed SQL statement. This function combines data from multiple system views to provide a complete picture of current database activity.
/// </para>
/// <para>
/// Use this to monitor active connections, identify blocking processes, track application connections, troubleshoot performance issues, or audit database access patterns. The output includes connection timing, network transport details, authentication schemes, client information, and recent query activity.
/// </para>
/// <para>
/// You can filter results by login name, hostname, program name, database, or specific session IDs to focus on particular processes of interest. This is especially useful for identifying connection leaks, monitoring specific applications, or investigating security concerns.
/// </para>
/// <para>
/// Thanks to Michael J Swart at https://sqlperformance.com/2017/07/sql-performance/find-database-connection-leaks for the query to get the last executed SQL statement, minutesasleep and host process ID.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaProcess -SqlInstance sqlserver2014a -Login base\ctrlb, sa
/// </code>
/// <para>
/// Shows information about the processes for base\ctrlb and sa on sqlserver2014a. Windows Authentication is used in connecting to sqlserver2014a.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaProcess -SqlInstance sqlserver2014a -SqlCredential $credential -Spid 56, 77
/// </code>
/// <para>
/// Shows information about the processes for spid 56 and 57. Uses alternative (SQL or Windows) credentials to authenticate to sqlserver2014a.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaProcess -SqlInstance sqlserver2014a -Program 'Microsoft SQL Server Management Studio'
/// </code>
/// <para>
/// Shows information about the processes that were created in Microsoft SQL Server Management Studio.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaProcess -SqlInstance sqlserver2014a -Host workstationx, server100
/// </code>
/// <para>
/// Shows information about the processes that were initiated by hosts (computers/clients) workstationx and server 1000.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item><term /><description>
/// <para>
/// Tags: Diagnostic, Process, Session, ActivityMonitor
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// 
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description></item>
/// <item><term>OUTPUTS</term><description>
/// <para>Microsoft.SqlServer.Management.Smo.Agent.Job (SMO Process object)</para>
/// <para>Returns one object per active SQL Server process/session matching the specified filter criteria.</para>
/// <para>Default display properties (via Select-DefaultView):</para>
/// <para>- ComputerName: The computer name of the SQL Server instance</para>
/// <para>- InstanceName: The SQL Server instance name</para>
/// <para>- SqlInstance: The full SQL Server instance name (computer\instance)</para>
/// <para>- Spid: Session ID number of the process</para>
/// <para>- Login: SQL Server login or Windows authentication account name</para>
/// <para>- LoginTime: DateTime when the session logged in</para>
/// <para>- Host: Client machine name/hostname</para>
/// <para>- Database: Database currently connected to the session</para>
/// <para>- BlockingSpid: Session ID of the process blocking this session (if blocked)</para>
/// <para>- Program: Client application name that initiated the session</para>
/// <para>- Status: Current status of the session (sleeping, running, etc.)</para>
/// <para>- Command: T-SQL command currently being executed</para>
/// <para>- Cpu: CPU time consumed in milliseconds</para>
/// <para>- MemUsage: Memory usage in pages (8 KB per page)</para>
/// <para>- LastRequestStartTime: DateTime when the last request started</para>
/// <para>- LastRequestEndTime: DateTime when the last request completed</para>
/// <para>- MinutesAsleep: Minutes elapsed since last request ended</para>
/// <para>- ClientNetAddress: Client IP address</para>
/// <para>- NetTransport: Network transport protocol (Named Pipes, TCP, Shared Memory)</para>
/// <para>- EncryptOption: Encryption setting (Off, On, Required, Login)</para>
/// <para>- AuthScheme: Authentication scheme used (NTLM, Kerberos, SQL, etc.)</para>
/// <para>- NetPacketSize: Network packet size in bytes</para>
/// <para>- ClientVersion: Client library version number</para>
/// <para>- HostProcessId: Operating system process ID on the client machine</para>
/// <para>- IsSystem: Boolean indicating if this is a system session</para>
/// <para>- EndpointName: Name of the endpoint the connection is using</para>
/// <para>- IsDac: Boolean indicating if this is a Dedicated Admin Connection (DAC)</para>
/// <para>- LastQuery: The last T-SQL statement executed in this session</para>
/// <para>Additional properties available (from SMO Process object):</para>
/// <para>- Parent: Reference to the parent Server object</para>
/// <para>- All other SMO process properties are accessible using Select-Object *</para>
/// </description></item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaProcess" />
[Cmdlet(VerbsCommon.Get, "DbaProcess")]
[OutputType(typeof(DataRow))]
public sealed class GetDbaProcessCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
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
    /// Filters results to specific process IDs (SPIDs) you want to monitor. Also includes any processes that are blocked by the specified SPIDs.
    /// Use this when investigating specific connections or troubleshooting blocking issues where you need to see both the blocker and blocked processes.
    /// </para>
    [Parameter(Position = 2)]
    public int[]? Spid { get; set; }

    /// <para>
    /// Excludes specific process IDs (SPIDs) from the results, even if they match other filter criteria.
    /// Use this to remove known processes like monitoring tools, maintenance jobs, or your own session from the output. This filter is applied last, overriding all other inclusion filters.
    /// </para>
    [Parameter(Position = 3)]
    public int[]? ExcludeSpid { get; set; }

    /// <para>
    /// Filters results to sessions currently connected to specific databases.
    /// Use this when monitoring activity on particular databases, investigating database-specific performance issues, or auditing access to sensitive databases.
    /// </para>
    [Parameter(Position = 4)]
    public string[]? Database { get; set; }

    /// <para>
    /// Filters results to sessions connected with specific SQL Server login names or Windows authentication accounts.
    /// Use this to monitor connections from specific applications, service accounts, or users when investigating security concerns or connection patterns.
    /// </para>
    [Parameter(Position = 5)]
    public string[]? Login { get; set; }

    /// <para>
    /// Filters results to sessions originating from specific client machines or server names.
    /// Use this when tracking connections from particular workstations, application servers, or investigating connection leaks from specific hosts.
    /// </para>
    [Parameter(Position = 6)]
    public string[]? Hostname { get; set; }

    /// <para>
    /// Filters results to sessions created by specific client applications such as 'Microsoft SQL Server Management Studio' or custom application names.
    /// Use this to monitor connections from particular applications, identify connection patterns, or troubleshoot application-specific database issues.
    /// </para>
    [Parameter(Position = 7)]
    public string[]? Program { get; set; }

    /// <para>
    /// Excludes system processes (SPIDs 1-50) from the results to focus only on user connections and application processes.
    /// Use this when you want to see only actual user sessions and application connections, filtering out SQL Server internal processes like checkpoints, log writers, and system tasks.
    /// </para>
    [Parameter]
    public SwitchParameter ExcludeSystemSpids { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    /// <para>
    /// If this switch is enabled, take the intersection of Spid, Login, Hostname, Program, and Database rather than the union.
    /// </para>
    [Parameter]
    public SwitchParameter Intersect { get; set; }


    private static readonly string[] DisplaySet = {
        "ComputerName", "InstanceName", "SqlInstance", "Spid", "Login", "LoginTime", "Host", "Database",
        "BlockingSpid", "Program", "Status", "Command", "Cpu", "MemUsage", "LastRequestStartTime", "LastRequestEndTime",
        "MinutesAsleep", "ClientNetAddress", "NetTransport", "EncryptOption", "AuthScheme", "NetPacketSize",
        "ClientVersion", "HostProcessId", "IsSystem", "EndpointName", "IsDac", "LastQuery"
    };

    private static readonly string[] DetailProperties = {
        "HostProcessId", "MinutesAsleep", "LoginTime", "ClientVersion", "LastRequestStartTime", "LastRequestEndTime",
        "NetTransport", "EncryptOption", "AuthScheme", "NetPacketSize", "ClientNetAddress", "LastQuery", "EndpointName", "IsDac"
    };

    private const string DetailSql = @"SELECT DATEDIFF(MINUTE, s.last_request_end_time, GETDATE()) AS MinutesAsleep,
            s.session_id AS spid,
            s.host_process_id AS HostProcessId,
            t.text AS Query,
            s.login_time AS LoginTime,
            s.client_version AS ClientVersion,
            s.last_request_start_time AS LastRequestStartTime,
            s.last_request_end_time AS LastRequestEndTime,
            c.net_transport AS NetTransport,
            c.encrypt_option AS EncryptOption,
            c.auth_scheme AS AuthScheme,
            c.net_packet_size AS NetPacketSize,
            c.client_net_address AS ClientNetAddress,
            e.name AS EndpointName,
            e.is_admin_endpoint AS IsDac
        FROM sys.dm_exec_connections c
        JOIN sys.dm_exec_sessions s ON c.session_id = s.session_id
        JOIN sys.endpoints e ON c.endpoint_id = e.endpoint_id
        OUTER APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) t
        ";

    // EnumProcesses rejects Azure. Its session DMV supplies the same process values without the
    // instance-only endpoint catalog and compatibility view. A missing visible request is not zero.
    private const string AzureSql = @"SELECT CONVERT(nvarchar(128), s.session_id) AS Name, s.session_id AS Spid,
            s.login_name AS Login, s.host_name AS Host,
            COALESCE(r.status, s.status) AS Status,
            CASE WHEN r.session_id IS NOT NULL THEN r.command
                WHEN s.status = N'sleeping' THEN N'AWAITING COMMAND' ELSE NULL END AS Command,
            DB_NAME(COALESCE(r.database_id, s.database_id)) AS [Database],
            s.cpu_time AS Cpu, s.memory_usage AS MemUsage,
            CASE WHEN r.session_id IS NOT NULL THEN r.blocking_session_id
                WHEN s.status = N'sleeping' THEN CONVERT(smallint, 0) ELSE NULL END AS BlockingSpid,
            CONVERT(bit, 1 - s.is_user_process) AS IsSystem, s.program_name AS Program,
            CONVERT(smallint, NULL) AS ExecutionContextID,
            DATEDIFF(MINUTE, s.last_request_end_time, GETDATE()) AS MinutesAsleep,
            s.host_process_id AS HostProcessId, t.text AS Query, s.login_time AS LoginTime,
            s.client_version AS ClientVersion, s.last_request_start_time AS LastRequestStartTime,
            s.last_request_end_time AS LastRequestEndTime, c.net_transport AS NetTransport,
            c.encrypt_option AS EncryptOption, c.auth_scheme AS AuthScheme, c.net_packet_size AS NetPacketSize,
            c.client_net_address AS ClientNetAddress, CONVERT(nvarchar(128), NULL) AS EndpointName,
            CONVERT(bit, NULL) AS IsDac
        FROM sys.dm_exec_sessions s
        LEFT JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
        LEFT JOIN sys.dm_exec_connections c ON c.session_id = s.session_id
        OUTER APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) t
        WHERE s.database_id = DB_ID()
        ORDER BY s.session_id
        ";

    protected override void ProcessRecord()
    {
        if (Interrupted) return;
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null) continue;

            bool azure = server.DatabaseEngineEdition.ToString() == "SqlDatabase";
            DataTable? details;
            DataTable? processes;
            if (azure)
            {
                WriteMessage(MessageLevel.Warning, "Azure SQL Database returns sessions for the current database. EndpointName, IsDac and ExecutionContextID are unavailable; Command and BlockingSpid are unknown when an active request is not visible.");
                details = ReadDetails(server, AzureSql);
                processes = details?.Copy();
                if (processes is not null)
                {
                    // Keep the enrichment fields as notes, as on the EnumProcesses path; Query is exposed as LastQuery.
                    foreach (string name in DetailProperties)
                        processes.Columns.Remove(name == "LastQuery" ? "Query" : name);
                    processes.Columns.Add("Urn", typeof(string));
                    foreach (DataRow row in processes.Rows)
                        row["Urn"] = String.Format(CultureInfo.InvariantCulture, "{0}/Process[@Spid='{1}']", server.Urn, row["Spid"]);
                }
            }
            else
            {
                details = server.VersionMajor > 8 ? ReadDetails(server, DetailSql) : null;
                processes = ReadProcesses(server);
            }
            if (processes is null) continue;
            foreach (DataRow session in SelectProcesses(processes))
                WriteObject(Decorate(session, details, server, azure));
        }
    }

    private List<DataRow> SelectProcesses(DataTable processes)
    {
        List<DataRow> selected = new();
        bool[] active = { FilterHelper.IsActive(Login!), FilterHelper.IsActive(Spid!), FilterHelper.IsActive(Hostname!),
            FilterHelper.IsActive(Program!), FilterHelper.IsActive(Database!) };
        bool boundAny = TestBound(nameof(Login)) || TestBound(nameof(Spid))
            || TestBound(nameof(Hostname)) || TestBound(nameof(Program)) || TestBound(nameof(Database));
        if (Intersect || !boundAny)
        {
            foreach (DataRow row in processes.Rows) selected.Add(row);
            if (Intersect)
                for (int filter = 0; filter < active.Length; filter++)
                    if (active[filter])
                    {
                        int current = filter;
                        selected.RemoveAll(row => !Matches(row, current));
                    }
        }
        else
        {
            // Each pinned union term sees the SPIDs from the earlier terms; their order is observable.
            for (int filter = 0; filter < active.Length; filter++)
            {
                if (!active[filter]) continue;
                HashSet<int> earlier = new();
                foreach (DataRow row in selected) earlier.Add(Convert.ToInt32(row["Spid"], CultureInfo.InvariantCulture));
                foreach (DataRow row in processes.Rows)
                    if (!earlier.Contains(Convert.ToInt32(row["Spid"], CultureInfo.InvariantCulture)) && Matches(row, filter))
                        selected.Add(row);
            }
        }
        if (ExcludeSystemSpids)
            selected.RemoveAll(row => Convert.ToInt32(row["Spid"], CultureInfo.InvariantCulture) <= 50);
        if (ExcludeSpid is { Length: > 0 }) selected.RemoveAll(row => HasValue(ExcludeSpid, row["Spid"]));
        return selected;
    }

    private bool Matches(DataRow row, int filter)
    {
        return filter switch
        {
            0 => HasValue(Login!, row["Login"]),
            1 => HasValue(Spid!, row["Spid"]) || HasValue(Spid!, row["BlockingSpid"]),
            2 => HasValue(Hostname!, row["Host"]),
            3 => HasValue(Program!, row["Program"]),
            _ => HasValue(Database!, row["Database"])
        };
    }

    // Both the name and numeric -contains operators convert the row value to each array element's type.
    private static bool HasValue<T>(T[] values, object value)
    {
        foreach (T candidate in values)
            if (LanguagePrimitives.Equals(candidate, value, true, CultureInfo.InvariantCulture)) return true;
        return false;
    }

    private DataTable? ReadDetails(Server server, string sql)
    {
        ErrorRecord fault;
        try
        {
            DataSet results = server.ConnectionContext.ExecuteWithResults(sql);
            return results.Tables.Count == 0 ? null : results.Tables[0];
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StringBuilder chain = new();
            for (Exception? current = failure; current is not null; current = current.InnerException)
                chain.Append(current.Message);
            string text = chain.ToString();
            // Server.Query's script method throws its concatenated message, discarding the SQL exception.
            RuntimeException inner = new(text, new RuntimeException(text));
            MethodInvocationException query = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", text), inner);
            fault = new ErrorRecord(query, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
        }
        SurfaceFault(fault);
        return null;
    }

    private DataTable? ReadProcesses(Server server)
    {
        ErrorRecord fault;
        try { return server.EnumProcesses(); }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"EnumProcesses\" with \"0\" argument(s): \"{0}\"", failure.Message), failure);
            fault = new ErrorRecord(call, failure.GetType().Name, ErrorCategory.NotSpecified, null);
        }
        SurfaceFault(fault);
        return null;
    }

    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException)
        {
            // caller-try: terminate -- the installed EnableException contract stops on the causal statement fault.
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams preserve the statement fault outside Stop-Function
        }
        StatementFault.Surface(this, fault);
    }

    private static PSObject Decorate(DataRow session, DataTable? details, Server server, bool azure)
    {
        PSObject output = PSObject.AsPSObject(session);
        output.Properties.Add(new PSNoteProperty("Parent", server));
        OutputHelper.AddInstanceProperties(output, server);
        object? status = session["Status"];
        object? command = session["Command"];
        if (azure)
        {
            if (status is DBNull) status = null;
            if (command is DBNull) command = null;
            foreach (string unavailable in new[] { "BlockingSpid", "ExecutionContextID" })
                if (session[unavailable] is DBNull) output.Properties.Add(new PSNoteProperty(unavailable, null));
        }
        output.Properties.Add(new PSNoteProperty("Status", LanguagePrimitives.Equals(status, "", true) ? "sleeping" : status));
        output.Properties.Add(new PSNoteProperty("Command", LanguagePrimitives.Equals(command, "", true) ? "AWAITING COMMAND" : command));

        List<DataRow> matching = new();
        if (details is not null)
            foreach (DataRow detail in details.Rows)
                if (LanguagePrimitives.Equals(detail["spid"], session["Spid"], true)) matching.Add(detail);
        foreach (string name in DetailProperties)
        {
            string source = name == "LastQuery" ? "Query" : name;
            object? value = null;
            if (matching.Count == 1) value = azure && matching[0][source] is DBNull ? null : matching[0][source];
            else if (matching.Count > 1)
            {
                object[] values = new object[matching.Count];
                for (int i = 0; i < matching.Count; i++) values[i] = matching[i][source];
                value = values;
            }
            output.Properties.Add(new PSNoteProperty(name, value));
        }
        OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
        return output;
    }
}
