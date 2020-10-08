function Get-DbaDbMailLog {
    <#
    .SYNOPSIS
        Gets the DBMail log from a SQL instance

    .DESCRIPTION
        Gets the DBMail log from a SQL instance

    .PARAMETER SqlInstance
        TThe target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Since
        Datetime object used to narrow the results to the send request date

    .PARAMETER Type
        Narrow the results by type. Valid values include Error, Warning, Success, Information, Internal

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DatabaseMail, DBMail, Mail
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbMailLog

    .EXAMPLE
        PS C:\> Get-DbaDbMailLog -SqlInstance sql01\sharepoint

        Returns the entire DBMail log on sql01\sharepoint

    .EXAMPLE
        PS C:\> Get-DbaDbMailLog -SqlInstance sql01\sharepoint | Select-Object *

        Returns the entire DBMail log on sql01\sharepoint, includes all returned information.

    .EXAMPLE
        PS C:\> $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
        PS C:\> $servers | Get-DbaDbMailLog -Type Error, Information

        Returns only the Error and Information DBMail log for "sql2014","sql2016" and "sqlcluster\sharepoint"

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [DateTime]$Since,
        [ValidateSet('Error', 'Warning', 'Success', 'Information', 'Internal')]
        [string[]]$Type,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category Connectiondbmail -dbmailRecord $_ -Target $instance -Continue
            }

            $sql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
            ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
            SERVERPROPERTY('ServerName') AS SqlInstance,
            log_id as LogId,
            CASE event_type
            WHEN 'error' THEN 'Error'
            WHEN 'warning' THEN 'Warning'
            WHEN 'information' THEN 'Information'
            WHEN 'success' THEN 'Success'
            WHEN 'internal' THEN 'Internal'
            ELSE event_type
            END as EventType,
            log_date as LogDate,
            REPLACE(description, CHAR(10)+')', '') as Description,
            process_id as ProcessId,
            mailitem_id as MailItemId,
            account_id as AccountId,
            last_mod_date as LastModDate,
            last_mod_user as LastModUser,
            last_mod_user as [Login]
            FROM msdb.dbo.sysmail_event_log"

            if ($Since -or $Type) {
                $wherearray = @()

                if ($Since) {
                    $wherearray += "log_date >= CONVERT(datetime,'$($Since.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126)"
                }

                if ($Type) {
                    $combinedtype = $Type -join "', '"
                    $wherearray += "event_type in ('$combinedtype')"
                }

                $wherearray = $wherearray -join ' and '
                $where = "where $wherearray"
                $sql = "$sql $where"
            }

            Write-Message -Level Debug -Message $sql

            try {
                $server.Query($sql) | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, LogDate, EventType, Description, Login
            } catch {
                Stop-Function -Message "Failure" -InnerErrorRecord $_ -Continue
            }
        }
    }
}