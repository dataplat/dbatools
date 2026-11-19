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

// Port of public/Get-DbaDbMailHistory.ps1 at refs/pins/dbatools-2026-10-22.
/// <summary>Retrieves Database Mail history from SQL Server's msdb database for troubleshooting and compliance</summary>
/// <para>Retrieves comprehensive Database Mail history from the msdb.dbo.sysmail_allitems table, including delivery status, recipients, subject lines, and timestamps. This function helps DBAs troubleshoot email delivery issues, audit mail activity for compliance reporting, and monitor Database Mail performance. You can filter results by send date or delivery status (Sent, Failed, Unsent, Retrying) to focus on specific timeframes or problem emails.</para>
/// <list type="alertSet">
///   <item>
///     <term></term>
///     <description>
///       <para>Tags: Mail, DbMail, Email</para>
///       <para>Author: Chrissy LeMaire (@cl), netnerds.net</para>
///       <para>Website: https://dbatools.io</para>
///       <para>Copyright: (c) 2018 by dbatools, licensed under MIT</para>
///       <para>License: MIT https://opensource.org/licenses/MIT</para>
///     </description>
///   </item>
/// </list>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbMailHistory -SqlInstance sql01\sharepoint</code>
///   <para>Returns the entire DBMail history on sql01\sharepoint</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbaDbMailHistory -SqlInstance sql01\sharepoint | Select-Object *</code>
///   <para>Returns the entire DBMail history on sql01\sharepoint then return a bunch more columns</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>$servers = "sql2014","sql2016", "sqlcluster\sharepoint"
/// PS C:\&gt; $servers | Get-DbaDbMailHistory</code>
///   <para>Returns the all DBMail history for "sql2014","sql2016" and "sqlcluster\sharepoint"</para>
/// </example>
/// <seealso href="https://dbatools.io/Get-DbaDbMailHistory"/>
[Cmdlet(VerbsCommon.Get, "DbaDbMailHistory")]
public sealed class GetDbaDbMailHistoryCommand : DbaInstanceCmdlet
{
    /// <para>The target SQL Server instance or instances.</para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>Filters mail history to only include emails sent after the specified date and time.</para>
    /// <para>Use this when troubleshooting recent delivery issues or generating reports for specific time periods.</para>
    /// <para>Accepts standard PowerShell DateTime objects like (Get-Date).AddDays(-7) for the past week.</para>
    [Parameter(Position = 2)]
    [PsDateTimeCast]
    public DateTime Since { get; set; }

    /// <para>Filters results to only show emails with the specified delivery status.</para>
    /// <para>Use 'Failed' to identify delivery problems, 'Unsent' for queued messages, or 'Retrying' for current retry attempts.</para>
    /// <para>Accepts multiple values: Unsent, Sent, Failed, and Retrying.</para>
    [Parameter(Position = 3)]
    [ValidateSet("Unsent", "Sent", "Failed", "Retrying")]
    public string? Status { get; set; }

    // PS: the $sql string of the process block, laid out as there. Correction removed-profile-mail: LEFT JOIN, so the mail of a removed profile stays.
    private const string SelectMail = @"SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                    ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                    SERVERPROPERTY('ServerName') AS SqlInstance,
                    mailitem_id AS MailItemId,
                    a.profile_id AS ProfileId,
                    p.name AS Profile,
                    recipients AS Recipients,
                    copy_recipients AS CopyRecipients,
                    blind_copy_recipients AS BlindCopyRecipients,
                    subject AS Subject,
                    body AS Body,
                    body_format AS BodyFormat,
                    importance AS Importance,
                    sensitivity AS Sensitivity,
                    file_attachments AS FileAttachments,
                    attachment_encoding AS AttachmentEncoding,
                    query AS Query,
                    execute_query_database AS ExecuteQueryDatabase,
                    attach_query_result_as_file AS AttachQueryResultAsFile,
                    query_result_header AS QueryResultHeader,
                    query_result_width AS QueryResultWidth,
                    query_result_separator AS QueryResultSeparator,
                    exclude_query_output AS ExcludeQueryOutput,
                    append_query_error AS AppendQueryError,
                    send_request_date AS SendRequestDate,
                    send_request_user AS SendRequestUser,
                    sent_account_id AS SentAccountId,
                    CASE sent_status
                    WHEN 'unsent' THEN 'Unsent'
                    WHEN 'sent' THEN 'Sent'
                    WHEN 'failed' THEN 'Failed'
                    WHEN 'retrying' THEN 'Retrying'
                    END AS SentStatus,
                    sent_date AS SentDate,
                    last_mod_date AS LastModDate,
                    a.last_mod_user AS LastModUser
                    FROM msdb.dbo.sysmail_allitems a
                    LEFT JOIN msdb.dbo.sysmail_profile p
                    ON a.profile_id = p.profile_id";

    private static readonly string[] DisplayProperties =
    {
        "ComputerName", "InstanceName", "SqlInstance", "Profile", "Recipients", "CopyRecipients", "BlindCopyRecipients", "Subject",
        "Importance", "Sensitivity", "FileAttachments", "AttachmentEncoding", "SendRequestDate", "SendRequestUser", "SentStatus", "SentDate"
    };

    protected override void ProcessRecord()
    {
        if (Interrupted || SqlInstance is null)
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

            // Correction azure-refusal: Azure SQL Database has no Database Mail, so it is refused the way -AzureUnsupported does.
            Server? server = ConnectInstance(instance, azureUnsupported: true);
            if (server is null)
                continue;

            string sql = BuildQuery();
            WriteMessage(MessageLevel.Debug, sql);

            DataTable? results;
            try
            {
                // PS: $server.Query($sql), the dbatools Server.Query script method: ExecuteWithResults, then the first table.
                DataSet data = server.ConnectionContext.ExecuteWithResults(sql);
                results = data.Tables.Count > 0 ? data.Tables[0] : null;
            }
            catch (Exception failure)
            {
                StopFunction("Query failure", errorRecord: QueryRecord(failure), continueLoop: true);
                continue;
            }

            if (results is null)
                continue;

            foreach (DataRow row in results.Rows)
            {
                // PS: | Select-DefaultView -Property ...
                PSObject output = PSObject.AsPSObject(row);
                OutputHelper.SetDefaultDisplayPropertySet(output, DisplayProperties);
                WriteObject(output);
            }
        }
    }

    // A bound -Since filters even at DateTime.MinValue, which is true in PowerShell. sysmail_allitems emits sent_status in lowercase, so it is
    // compared lowercased, and invariantly: a culture-sensitive lowercase turns the I of FAILED into a dotless i under Turkish rules.
    private string BuildQuery()
    {
        // The pinned source has LF line ends, which reach the debug stream however this file is checked out.
        string sql = SelectMail.Replace("\r\n", "\n");

        List<string> where = new();
        if (TestBound(nameof(Since)))
        {
            where.Add(String.Format(CultureInfo.InvariantCulture, "send_request_date >= CONVERT(datetime,'{0}',126)",
                Since.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture)));
        }
        if (!String.IsNullOrEmpty(Status))
            where.Add(String.Format(CultureInfo.InvariantCulture, "LOWER(sent_status) IN ('{0}')", Status!.ToLowerInvariant()));

        return where.Count == 0 ? sql : String.Format(CultureInfo.InvariantCulture, "{0} WHERE {1}", sql, String.Join(" AND ", where));
    }

    // PS: $_ for a failed $server.Query: the script method's catch joins the messages of the exception chain and throws that text,
    // which the method call reports as "Exception calling "Query" ..." over the two runtime exceptions of the throw.
    private static ErrorRecord QueryRecord(Exception failure)
    {
        StringBuilder text = new();
        for (Exception? current = failure; current is not null; current = current.InnerException)
            text.Append(current.Message);
        string message = text.ToString();
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message, new RuntimeException(message)));
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }
}
