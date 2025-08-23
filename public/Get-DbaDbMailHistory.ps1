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
                    mailitem_id as MailItemId,
                    a.profile_id as ProfileId,
                    p.name as Profile,
                    recipients as Recipients,
                    copy_recipients as CopyRecipients,
                    blind_copy_recipients as BlindCopyRecipients,
                    subject as Subject,
                    body as Body,
                    body_format as BodyFormat,
                    importance as Importance,
                    sensitivity as Sensitivity,
                    file_attachments as FileAttachments,
                    attachment_encoding as AttachmentEncoding,
                    query as Query,
                    execute_query_database as ExecuteQueryDatabase,
                    attach_query_result_as_file as AttachQueryResultAsFile,
                    query_result_header as QueryResultHeader,
                    query_result_width as QueryResultWidth,
                    query_result_separator as QueryResultSeparator,
                    exclude_query_output as ExcludeQueryOutput,
                    append_query_error as AppendQueryError,
                    send_request_date as SendRequestDate,
                    send_request_user as SendRequestUser,
                    sent_account_id as SentAccountId,
                    CASE sent_status
                    WHEN 'unsent' THEN 'Unsent'
                    WHEN 'sent' THEN 'Sent'
                    WHEN 'failed' THEN 'Failed'
                    WHEN 'retrying' THEN 'Retrying'
                    END AS SentStatus,
                    sent_date as SentDate,
                    last_mod_date as LastModDate,
                    a.last_mod_user as LastModUser
                    from msdb.dbo.sysmail_allitems a
                    join msdb.dbo.sysmail_profile p
                    on a.profile_id = p.profile_id"

            if ($Since -or $Status) {
                $wherearray = @()

                if ($Since) {
                    $wherearray += "send_request_date >= CONVERT(datetime,'$($Since.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126)"
                }

                if ($Status) {
                    $Status = $Status -join "', '"
                    $wherearray += "sent_status in ('$Status')"
                }

                $wherearray = $wherearray -join ' and '
                $where = "where $wherearray"
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