#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbMailLog.ps1 at refs/pins/dbatools-2026-10-22: the query of msdb.dbo.sysmail_event_log, its
// -Since and -Type filters, and the default view of the rows.
/// <summary>Retrieves Database Mail event logs from msdb for troubleshooting email delivery issues</summary>
/// <para>
/// Retrieves Database Mail event logs from the msdb.dbo.sysmail_event_log table, providing detailed information about email send attempts, failures, and system events. This function is essential for diagnosing Database Mail problems, monitoring email delivery status, and identifying configuration issues. You can filter results by date range and event type (Error, Warning, Success, Information, Internal) to focus on specific troubleshooting scenarios rather than manually querying the mail log tables.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMailLog -SqlInstance sql01\sharepoint
/// </code>
/// <para>
/// Returns the entire DBMail log on sql01\sharepoint
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMailLog -SqlInstance sql01\sharepoint | Select-Object *
/// </code>
/// <para>
/// Returns the entire DBMail log on sql01\sharepoint, includes all returned information.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
/// PS C:\&gt; $servers | Get-DbaDbMailLog -Type Error, Information
/// </code>
/// <para>
/// Returns only the Error and Information DBMail log for "sql2014","sql2016" and "sqlcluster\sharepoint"
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Mail, DbMail, Email
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
/// <seealso href="https://dbatools.io/Get-DbaDbMailLog" />
[Cmdlet(VerbsCommon.Get, "DbaDbMailLog")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaDbMailLogCommand : DbaInstanceCmdlet
{
    // PS: the $sql string of the process block, laid out as there.
    private const string SelectLog = @"SELECT SERVERPROPERTY('MachineName') AS ComputerName,
            ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
            SERVERPROPERTY('ServerName') AS SqlInstance,
            log_id AS LogId,
            CASE event_type
            WHEN 'error' THEN 'Error'
            WHEN 'warning' THEN 'Warning'
            WHEN 'information' THEN 'Information'
            WHEN 'success' THEN 'Success'
            WHEN 'internal' THEN 'Internal'
            ELSE event_type
            END AS EventType,
            log_date AS LogDate,
            REPLACE(description, CHAR(10)+')', '') AS Description,
            process_id AS ProcessId,
            mailitem_id AS MailItemId,
            account_id AS AccountId,
            last_mod_date AS LastModDate,
            last_mod_user AS LastModUser,
            last_mod_user AS [Login]
            FROM msdb.dbo.sysmail_event_log";

    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
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
    /// Filters log entries to only include events that occurred on or after the specified date and time.
    /// Use this when troubleshooting recent mail delivery issues or investigating problems within a specific timeframe.
    /// </para>
    [Parameter(Position = 2)]
    [PsDateTimeCast]
    public DateTime Since { get; set; }

    /// <para>
    /// Filters log entries by event type to focus troubleshooting on specific mail system behaviors.
    /// Use 'Error' to identify failed deliveries, 'Warning' for potential issues, 'Success' to verify deliveries, 'Information' for general events, or 'Internal' for system-level Database Mail operations.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    [ValidateSet("Error", "Warning", "Success", "Information", "Internal")]
    public string[]? Type { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    /// <summary>Reports the Database Mail event log of each instance.</summary>
    protected override void ProcessRecord()
    {
        if (SqlInstance is null)
            return;

        foreach (DbaInstanceParameter? instance in SqlInstance)
        {
            // PS: Connect-DbaInstance declares -SqlInstance mandatory, so a null element faults inside the pinned try.
            if (instance is null)
            {
                ParameterBindingException refused = new("Cannot bind argument to parameter 'SqlInstance' because it is null.");
                StopFunction("Failure", errorRecord: new ErrorRecord(refused, "ParameterArgumentValidationErrorNullNotAllowed", ErrorCategory.InvalidData, null),
                    category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            // Fleet.md step 4 refuses Azure SQL Database, which has no msdb or Database Mail, where the pinned connect lacks the switch.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            string sql = BuildQuery();
            WriteMessage(MessageLevel.Debug, sql);

            DataTable? rows;
            try
            {
                // PS: $server.Query($sql), the dbatools Server.Query script method: ExecuteWithResults, then the first table.
                DataSet data = server.ConnectionContext.ExecuteWithResults(sql);
                rows = data.Tables.Count > 0 ? data.Tables[0] : null;
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                StopFunction("Failure", errorRecord: QueryFaultRecord(failure), continueLoop: true);
                continue;
            }

            if (rows is null)
                continue;

            foreach (DataRow row in rows.Rows)
            {
                // PS: | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, LogDate, EventType, Description, Login
                PSObject output = PSObject.AsPSObject(row);
                OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "InstanceName", "SqlInstance", "LogDate", "EventType", "Description", "Login");
                WriteObject(output);
            }
        }
    }

    // A bound -Since filters even at DateTime.MinValue, which is true in PowerShell. sysmail_event_log emits event_type in lowercase, so it is
    // compared lowercased, and invariantly: a culture-sensitive lowercase turns the I of Information into a dotless i under Turkish rules.
    // -Type is held to its ValidateSet, so the text below cannot carry anything else.
    private string BuildQuery()
    {
        // The pinned source has LF line ends, which reach the debug stream however this file is checked out.
        string sql = SelectLog.Replace("\r\n", "\n");

        List<string> where = new();
        if (TestBound(nameof(Since)))
        {
            where.Add(String.Format(CultureInfo.InvariantCulture, "log_date >= CONVERT(datetime,'{0}',126)",
                Since.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture)));
        }
        if (LanguagePrimitives.IsTrue(Type))
            where.Add(String.Format(CultureInfo.InvariantCulture, "LOWER(event_type) IN ('{0}')", String.Join("', '", Type!).ToLowerInvariant()));

        return where.Count == 0 ? sql : String.Format(CultureInfo.InvariantCulture, "{0} WHERE {1}", sql, String.Join(" AND ", where));
    }

    // The record the source catch receives from $server.Query: the script method joins the messages of the failure chain and
    // throws that text, which the engine reports as the ScriptMethodRuntimeException method fault of "Query".
    private static ErrorRecord QueryFaultRecord(Exception failure)
    {
        string message = "";
        for (Exception? current = failure; current is not null; current = current.InnerException)
            message += current.Message;
        MethodInvocationException fault = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message, new RuntimeException(message)));
        return new ErrorRecord(fault, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }
}
