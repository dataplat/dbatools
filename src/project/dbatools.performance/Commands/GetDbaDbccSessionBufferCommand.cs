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

// Port of public/Get-DbaDbccSessionBuffer.ps1 at refs/pins/dbatools-2026-10-22: DBCC INPUTBUFFER or OUTPUTBUFFER per session, on the connection of each instance.
// Expected values as the pin measured on both editions: evidence/pin-sessionbuffer-20261103.txt.
/// <summary>Retrieves session input or output buffer contents using DBCC INPUTBUFFER or DBCC OUTPUTBUFFER</summary>
/// <para>
/// Executes DBCC INPUTBUFFER or DBCC OUTPUTBUFFER to examine what SQL statements a session is executing or what data is being returned to a client. InputBuffer shows the last SQL batch sent by a client session, which is essential for troubleshooting blocking, investigating suspicious activity, or understanding what commands are causing performance issues. OutputBuffer reveals the actual data being transmitted back to the client, useful for debugging connectivity problems or examining result sets. This replaces the need to manually run DBCC commands and parse their output, especially when investigating multiple sessions simultaneously.
/// </para>
/// <para>
/// Read more:
/// - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-inputbuffer-transact-sql
/// - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-outputbuffer-transact-sql
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbccSessionBuffer -SqlInstance Server1 -Operation InputBuffer -SessionId 51
/// </code>
/// <para>
/// Get results of DBCC INPUTBUFFER(51) for Instance Server1
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbccSessionBuffer -SqlInstance Server1 -Operation OutputBuffer -SessionId 51, 52
/// </code>
/// <para>
/// Get results of DBCC OUTPUTBUFFER for SessionId's 51 and 52 for Instance Server1
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbccSessionBuffer -SqlInstance Server1 -Operation InputBuffer -SessionId 51 -RequestId 0
/// </code>
/// <para>
/// Get results of DBCC INPUTBUFFER(51,0) for Instance Server1
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbccSessionBuffer -SqlInstance Server1 -Operation OutputBuffer -SessionId 51 -RequestId 0
/// </code>
/// <para>
/// Get results of DBCC OUTPUTBUFFER(51,0) for Instance Server1
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'Sql1','Sql2/sqlexpress' | Get-DbaDbccSessionBuffer -Operation InputBuffer -All
/// </code>
/// <para>
/// Get results of DBCC INPUTBUFFER for all user sessions for the instances Sql1 and Sql2/sqlexpress
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'Sql1','Sql2/sqlexpress' | Get-DbaDbccSessionBuffer -Operation OutputBuffer -All
/// </code>
/// <para>
/// Get results of DBCC OUTPUTBUFFER for all user sessions for the instances Sql1 and Sql2/sqlexpress
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential sqladmin
/// PS C:\&gt; Get-DbaDbccSessionBuffer -SqlInstance Server1 -SqlCredential $cred -Operation InputBuffer -SessionId 51 -RequestId 0
/// </code>
/// <para>
/// Connects using sqladmin credential and gets results of DBCC INPUTBUFFER(51,0) for Instance Server1
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential sqladmin
/// PS C:\&gt; Get-DbaDbccSessionBuffer -SqlInstance Server1 -SqlCredential $cred -Operation OutputBuffer -SessionId 51 -RequestId 0
/// </code>
/// <para>
/// Connects using sqladmin credential and gets results of DBCC OUTPUTBUFFER(51,0) for Instance Server1
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
/// <seealso href="https://dbatools.io/Get-DbaDbccSessionBuffer" />
[Cmdlet(VerbsCommon.Get, "DbaDbccSessionBuffer")]
public sealed class GetDbaDbccSessionBufferCommand : DbaInstanceCmdlet
{
    private const string Placeholder = "#Operation#";
    private const string SessionListQuery = "SELECT session_id FROM sys.dm_exec_connections";

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
    /// Specifies which DBCC operation to execute: InputBuffer shows the last SQL statement sent by a client, while OutputBuffer shows data being returned to the client.
    /// Use InputBuffer when troubleshooting blocking sessions, investigating suspicious activity, or identifying problematic queries.
    /// Use OutputBuffer when debugging client connectivity issues or examining what data is being transmitted to applications.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringCast]
    [ValidateSet("InputBuffer", "OutputBuffer")]
    public string Operation { get; set; } = "InputBuffer";

    /// <para>
    /// Specifies one or more session IDs to examine for buffer contents. Session IDs can be found in sys.dm_exec_sessions or sys.dm_exec_requests.
    /// Use this when you need to investigate specific sessions that are causing blocking, consuming resources, or exhibiting unusual behavior.
    /// Cannot be used together with the -All parameter.
    /// </para>
    [Parameter(Position = 3)]
    public int[]? SessionId { get; set; }

    /// <para>
    /// Specifies the exact request (batch) to examine within a session when multiple requests are active. Optional parameter that defaults to the current request.
    /// Use this when a session has multiple concurrent requests and you need to examine a specific batch rather than the most recent one.
    /// Find request IDs by querying sys.dm_exec_requests for the target session_id.
    /// </para>
    [Parameter(Position = 4)]
    public int RequestId { get; set; }

    /// <para>
    /// Retrieves buffer information for all active user sessions instead of specific session IDs. Excludes system sessions to focus on user activity.
    /// Use this when performing broad troubleshooting to identify which sessions are running problematic queries or consuming resources.
    /// This parameter overrides any SessionId or RequestId values and may return large result sets on busy servers.
    /// </para>
    [Parameter]
    public SwitchParameter All { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private string _template = "";

    // PS: $sessionList lives across instances and pipeline records, so an instance whose list fails walks the list of the instance before it, or nothing when there is none
    // (good-then-low-all, low-then-good-all). Each row it then writes is true of the instance and session it names, and every session that instance refuses gives a warning.
    private DataTable? _sessionList;

    protected override void BeginProcessing()
    {
        // Correction all-false: the pin's Test-Bound reads -All:$false as -All (all-false-session, all-false-alone).
        if (!All.IsPresent && !TestBound("SessionId"))
        {
            StopFunction("You must specify either a SessionId or use the -All switch.");
            return;
        }

        // PS: only an -Operation the caller gave is upper-cased (low-own: DBCC InputBuffer(65) WITH NO_INFOMSGS).
        string operation = TestBound("Operation") ? Operation.ToUpper() : Operation;
        _template = String.Format(CultureInfo.InvariantCulture, "DBCC {0}({1}) WITH NO_INFOMSGS", operation, Placeholder);
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            if (All.IsPresent)
                ReadAllSessions(server);
            else
                ReadNamedSessions(server);
        }
    }

    private void ReadNamedSessions(Server server)
    {
        foreach (int sessionId in SessionId ?? Array.Empty<int>())
        {
            // PS: the template is written first, with its placeholder still in it.
            WriteMessage(MessageLevel.Verbose, "Query to run: " + _template);
            string argument = TestBound("RequestId")
                ? String.Format(CultureInfo.InvariantCulture, "{0}, {1}", sessionId, RequestId)
                : sessionId.ToString(CultureInfo.InvariantCulture);
            ReadSession(server, sessionId, _template.Replace(Placeholder, argument), true);
        }
    }

    // PS: the -All path ignores -RequestId and writes neither the template nor "Output Buffer" (all-request-ignored).
    private void ReadAllSessions(Server server)
    {
        // PS: outside any try. The list reads VIEW SERVER STATE, or VIEW SERVER PERFORMANCE STATE on SQL Server 2022 (low-all and its forms).
        try
        {
            _sessionList = RunQuery(server, SessionListQuery);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            SurfaceFault(QueryRecord(failure));
        }

        if (_sessionList is null)
            return;

        foreach (DataRow session in _sessionList.Rows)
        {
            object sessionId = session["session_id"];
            string argument = Convert.ToString(sessionId, CultureInfo.InvariantCulture) ?? String.Empty;
            ReadSession(server, sessionId, _template.Replace(Placeholder, argument), false);
        }
    }

    private void ReadSession(Server server, object sessionId, string query, bool writeOutputLine)
    {
        DataTable? results;
        try
        {
            WriteMessage(MessageLevel.Verbose, "Query to run: " + query);
            results = RunQuery(server, query);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StopFunction("Failure", target: server, errorRecord: QueryRecord(failure), continueLoop: true);
            return;
        }

        // PS: $Operation -eq 'INPUTBUFFER', which ignores case, and the default keeps its mixed case.
        if (String.Equals(Operation, "INPUTBUFFER", StringComparison.OrdinalIgnoreCase))
        {
            WriteInputBuffer(server, sessionId, results);
            return;
        }

        if (writeOutputLine)
            WriteMessage(MessageLevel.Verbose, "Output Buffer");
        WriteOutputBuffer(server, sessionId, results);
    }

    private static DataTable? RunQuery(Server server, string query)
    {
        DataSet tables = server.ConnectionContext.ExecuteWithResults(query);
        return tables.Tables.Count > 0 ? tables.Tables[0] : null;
    }

    private void WriteInputBuffer(Server server, object sessionId, DataTable? results)
    {
        if (results is null)
            return;

        foreach (DataRow row in results.Rows)
        {
            PSObject output = new();
            OutputHelper.AddInstanceProperties(output, server);
            output.Properties.Add(new PSNoteProperty("SessionId", sessionId));
            output.Properties.Add(new PSNoteProperty("EventType", Cell(row, 0)));
            output.Properties.Add(new PSNoteProperty("Parameters", Cell(row, 1)));
            output.Properties.Add(new PSNoteProperty("EventInfo", Cell(row, 2)));
            WriteObject(output);
        }
    }

    // PS: one object per session, with empty buffers for a session whose dump has no rows (system-output-session).
    private void WriteOutputBuffer(Server server, object sessionId, DataTable? results)
    {
        StringBuilder hexBuilder = new();
        StringBuilder textBuilder = new();

        if (results is not null)
        {
            foreach (DataRow row in results.Rows)
            {
                string line = row[0].ToString() ?? String.Empty;
                string? hex = DumpPiece(line, 11, 48);
                string? text = DumpPiece(line, 61, 16);
                if (hex is not null)
                    hexBuilder.Append(hex);
                if (text is not null)
                    AppendText(textBuilder, text, hex);
            }
        }

        PSObject output = new();
        OutputHelper.AddInstanceProperties(output, server);
        output.Properties.Add(new PSNoteProperty("SessionId", sessionId));
        output.Properties.Add(new PSNoteProperty("Buffer", textBuilder.ToString().TrimEnd()));
        output.Properties.Add(new PSNoteProperty("HexBuffer", hexBuilder.Replace(" ", String.Empty).ToString()));
        OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "InstanceName", "SqlInstance", "SessionId", "Buffer");
        WriteObject(output);
    }

    // PS: $str.Substring(11, 48) and $str.Substring(61, 16), statements outside any try. Every row of the dump measured 77 wide (dump-own: 256 rows of random bytes), so neither faulted.
    private string? DumpPiece(string line, int start, int length)
    {
        try
        {
            return line.Substring(start, length);
        }
        catch (ArgumentOutOfRangeException failure)
        {
            MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Substring\" with \"2\" argument(s): \"{0}\"", failure.Message), failure);
            SurfaceFault(new ErrorRecord(call, failure.GetType().Name, ErrorCategory.NotSpecified, null));
            return null;
        }
    }

    // Correction buffer-dots: the dump prints a dot for each byte it cannot print and for a real dot, and the pin's Replace('.', '') drops both. The hex column tells them apart,
    // so a dot over byte 2e stays, as .OUTPUTS says that only non-printable characters are removed.
    private static void AppendText(StringBuilder builder, string text, string? hex)
    {
        for (int position = 0; position < text.Length; position++)
        {
            bool realDot = hex is not null && String.CompareOrdinal(hex, position * 3, "2e", 0, 2) == 0;
            if (text[position] != '.' || realDot)
                builder.Append(text[position]);
        }
    }

    // Accepted differences from the pin at these statements (harness-edits.md, keep-going and StatementFault sections; "Script-scope preferences and the one-line connect warning", point 1).
    // -EnableException stops here with the record; the pin ignores the switch at them and goes on (low-all-ee). $ErrorActionPreference = "Stop" set in the caller's scope or at a
    // script's top stops at this WriteError, and "SilentlyContinue" there silences the record, as for any compiled command; the pin ignores both there.
    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        // A plain call writes the record and goes on, as the pin does; under a caller's try the record stops the command, as the fault stops the pin's statement.
        StatementFault.Surface(this, fault);
    }

    // PS: $row[n]; an ordinal past the last column reads $null.
    private static object? Cell(DataRow row, int ordinal)
    {
        return ordinal < row.Table.Columns.Count ? row[ordinal] : null;
    }

    // PS: $_ for a failed $server.Query: the script method's catch joins the messages of the exception chain and throws that text, which the method call reports as
    // "Exception calling "Query" ...". As the pin measured, invalid-session-ee and low-all.
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
