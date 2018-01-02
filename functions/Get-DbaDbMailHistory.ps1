function Get-DbaDbMailHistory {
    <#
    .SYNOPSIS
        Gets the history of mail sent from a SQL instance

    .DESCRIPTION
        Gets the history of mail sent from a SQL instance

    .PARAMETER SqlInstance
        The SQL Server instance, or instances.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

    .PARAMETER Since
    Datetime object used to narrow the results to the send request date

    .PARAMETER Status
    Narrow the results by status. Valid values include Unsent, Sent, Failed and Retrying

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Logging
        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
        https://dbatools.io/Get-DbaDbMailHistory

    .EXAMPLE
        Get-DbaDbMailHistory -SqlInstance sql01\sharepoint

        Returns the entire dbmail history on sql01\sharepoint

    .EXAMPLE
        Get-DbaDbMailHistory -SqlInstance sql01\sharepoint | Select *

        Returns the entire dbmail history on sql01\sharepoint then return a bunch more columns

    .EXAMPLE
        $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
        $servers | Get-DbaDbMailHistory

        Returns the all dbmail history for "sql2014","sql2016" and "sqlcluster\sharepoint"

#>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [DateTime]$Since,
        [ValidateSet('Unsent', 'Sent', 'Failed', 'Retrying')]
        [string]$Status,
        [switch][Alias('Silent')]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category Connectiondbmail -dbmailRecord $_ -Target $instance -Continue
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
                    $wherearray += "send_request_date >= '$($Since.ToString("yyyy-MM-ddTHH:mm:ss"))'"
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
            }
            catch {
                Stop-Function -Message "Query failure" -ErrorRecord $_ -Continue
            }
        }
    }
}