function Get-DbaOpenTransaction {
    <#
    .SYNOPSIS
        Displays all open transactions.

    .DESCRIPTION
        This command is based on open transaction script published by Paul Randal.
        Reference: https://www.sqlskills.com/blogs/paul/script-open-transactions-with-text-and-plans/

    .PARAMETER SqlInstance
        The SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Process, Session, ActivityMonitor
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaOpenTransaction

    .EXAMPLE
        PS C:\> Get-DbaOpenTransaction -SqlInstance sqlserver2014a

        Returns open transactions for sqlserver2014a

    .EXAMPLE
        PS C:\> Get-DbaOpenTransaction -SqlInstance sqlserver2014a -SqlCredential sqladmin

        Logs into sqlserver2014a using the login "sqladmin"

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    begin {
        $sql = "
            SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
            ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
            SERVERPROPERTY('ServerName') AS SqlInstance,
            [s_tst].[session_id] as Spid,
            [s_es].[login_name] as Login,
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
                sys.[dm_exec_sessions] [s_es]
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
                [BeginTime] ASC"
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $server.Query($sql)
        }
    }
}