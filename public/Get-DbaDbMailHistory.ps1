function Get-DbaDbMailHistory {
    <#
    .SYNOPSIS
        Retrieves Database Mail history from SQL Server's msdb database for troubleshooting and compliance

    .DESCRIPTION
        Retrieves comprehensive Database Mail history from the msdb.dbo.sysmail_allitems table, including delivery status, recipients, subject lines, and timestamps. This function helps DBAs troubleshoot email delivery issues, audit mail activity for compliance reporting, and monitor Database Mail performance. You can filter results by send date or delivery status (Sent, Failed, Unsent, Retrying) to focus on specific timeframes or problem emails.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Since
        Filters mail history to only include emails sent after the specified date and time.
        Use this when troubleshooting recent delivery issues or generating reports for specific time periods.
        Accepts standard PowerShell DateTime objects like (Get-Date).AddDays(-7) for the past week.

    .PARAMETER Status
        Filters results to only show emails with the specified delivery status.
        Use 'Failed' to identify delivery problems, 'Unsent' for queued messages, or 'Retrying' for current retry attempts.
        Accepts multiple values: Unsent, Sent, Failed, and Retrying.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per Database Mail message from the MSDB sysmail_allitems table.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Profile: The Database Mail profile name associated with this message
        - Recipients: Email addresses of the primary recipients
        - CopyRecipients: Email addresses of the CC recipients
        - BlindCopyRecipients: Email addresses of the BCC recipients
        - Subject: The subject line of the email message
        - Importance: The importance level (Low, Normal, High)
        - Sensitivity: The sensitivity level (Normal, Personal, Private, Confidential)
        - FileAttachments: File attachments included with the message
        - AttachmentEncoding: Character encoding used for attachments
        - SendRequestDate: DateTime when the message was requested to be sent
        - SendRequestUser: Windows or SQL login that initiated the email
        - SentStatus: The delivery status (Unsent, Sent, Failed, Retrying)
        - SentDate: DateTime when the message was actually sent (or failed)

        Additional properties available (via Select-Object *):
        - MailItemId: Unique identifier for this mail message in the sysmail_allitems table
        - ProfileId: Unique identifier of the Database Mail profile
        - Body: The message body text
        - BodyFormat: The body format (HTML or TEXT)
        - Query: T-SQL query that generated query results attached to the message
        - ExecuteQueryDatabase: Database where the query was executed
        - AttachQueryResultAsFile: Whether query results were attached as a file
        - QueryResultHeader: Whether query result headers were included in the attachment
        - QueryResultWidth: Width of the query result output
        - QueryResultSeparator: Character used to separate columns in query results
        - ExcludeQueryOutput: Whether to exclude the query execution output
        - AppendQueryError: Whether to append query errors to the output
        - SentAccountId: Account ID used to send the message
        - LastModDate: DateTime when this mail item record was last modified
        - LastModUser: Login that last modified this mail item record

    .NOTES
        Tags: Mail, DbMail, Email
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbMailHistory

    .EXAMPLE
        PS C:\> Get-DbaDbMailHistory -SqlInstance sql01\sharepoint

        Returns the entire DBMail history on sql01\sharepoint

    .EXAMPLE
        PS C:\> Get-DbaDbMailHistory -SqlInstance sql01\sharepoint | Select-Object *

        Returns the entire DBMail history on sql01\sharepoint then return a bunch more columns

    .EXAMPLE
        PS C:\> $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
        PS C:\> $servers | Get-DbaDbMailHistory

        Returns the all DBMail history for "sql2014","sql2016" and "sqlcluster\sharepoint"

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [DateTime]$Since,
        [ValidateSet('Unsent', 'Sent', 'Failed', 'Retrying')]
        [string]$Status,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $sql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
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
                    JOIN msdb.dbo.sysmail_profile p
                    ON a.profile_id = p.profile_id"

            if ($Since -or $Status) {
                $wherearray = @()

                if ($Since) {
                    $wherearray += "send_request_date >= CONVERT(datetime,'$($Since.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126)"
                }

                if ($Status) {
                    $Status = $Status -join "', '"
                    $wherearray += "sent_status IN ('$Status')"
                }

                $wherearray = $wherearray -join ' AND '
                $where = "WHERE $wherearray"
                $sql = "$sql $where"
            }

            Write-Message -Level Debug -Message $sql

            try {
                $server.Query($sql) | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Profile, Recipients, CopyRecipients, BlindCopyRecipients, Subject, Importance, Sensitivity, FileAttachments, AttachmentEncoding, SendRequestDate, SendRequestUser, SentStatus, SentDate
            } catch {
                Stop-Function -Message "Query failure" -ErrorRecord $_ -Continue
            }
        }
    }
}