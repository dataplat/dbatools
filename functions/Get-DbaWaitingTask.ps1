function Get-DbaWaitingTask {
    <#
    .SYNOPSIS
        Displays waiting task.

    .DESCRIPTION
        This command is based on waiting task T-SQL script published by Paul Randal.
        Reference: https://www.sqlskills.com/blogs/paul/updated-sys-dm_os_waiting_tasks-script-2/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version XXXX or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Spid
        Find the waiting task of one or more specific process ids

    .PARAMETER IncludeSystemSpid
        If this switch is enabled, the output will include the system sessions.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Waits,Task,WaitTask
        Author: Shawn Melton (@wsmelton), https://wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaWaitingTask

    .EXAMPLE
        PS C:\> Get-DbaWaitingTask -SqlInstance sqlserver2014a

        Returns the waiting task for all sessions on sqlserver2014a

    .EXAMPLE
        PS C:\> Get-DbaWaitingTask -SqlInstance sqlserver2014a -IncludeSystemSpid

        Returns the waiting task for all sessions (user and system) on sqlserver2014a

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipelineByPropertyName)]
        [object[]]$Spid,
        [switch]$IncludeSystemSpid,
        [switch]$EnableException
    )

    begin {
        $sql = "
            SELECT
                [owt].[session_id] AS [Spid],
                [owt].[exec_context_id] AS [Thread],
                [ot].[scheduler_id] AS [Scheduler],
                [owt].[wait_duration_ms] AS [WaitMs],
                [owt].[wait_type] AS [WaitType],
                [owt].[blocking_session_id] AS [BlockingSpid],
                [owt].[resource_description] AS [ResourceDesc],
                CASE [owt].[wait_type]
                    WHEN N'CXPACKET' THEN
                        RIGHT ([owt].[resource_description],
                            CHARINDEX (N'=', REVERSE ([owt].[resource_description])) - 1)
                    ELSE NULL
                END AS [NodeId],
                [eqmg].[dop] AS [Dop],
                [er].[database_id] AS [DbId],
                [est].text AS [SqlText],
                [eqp].[query_plan] AS [QueryPlan],
                CAST ('https://www.sqlskills.com/help/waits/' + [owt].[wait_type] as XML) AS [URL]
            FROM sys.dm_os_waiting_tasks [owt]
            INNER JOIN sys.dm_os_tasks [ot] ON
                [owt].[waiting_task_address] = [ot].[task_address]
            INNER JOIN sys.dm_exec_sessions [es] ON
                [owt].[session_id] = [es].[session_id]
            INNER JOIN sys.dm_exec_requests [er] ON
                [es].[session_id] = [er].[session_id]
            FULL JOIN sys.dm_exec_query_memory_grants [eqmg] ON
                [owt].[session_id] = [eqmg].[session_id]
            OUTER APPLY sys.dm_exec_sql_text ([er].[sql_handle]) [est]
            OUTER APPLY sys.dm_exec_query_plan ([er].[plan_handle]) [eqp]
            WHERE
                [es].[is_user_process] = $(if (Test-Bound 'IncludeSystemSpid') {0} else {1})
            ORDER BY
                [owt].[session_id],
                [owt].[exec_context_id]
            OPTION(RECOMPILE);"
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $results = $server.Query($sql)
            foreach ($row in $results) {
                if (Test-Bound 'Spid') {
                    if ($row.Spid -notin $Spid) { continue }
                }

                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Spid         = $row.Spid
                    Thread       = $row.Thread
                    Scheduler    = $row.Scheduler
                    WaitMs       = $row.WaitMs
                    WaitType     = $row.WaitType
                    BlockingSpid = $row.BlockingSpid
                    ResourceDesc = $row.ResourceDesc
                    NodeId       = $row.NodeId
                    Dop          = $row.Dop
                    DbId         = $row.DbId
                    SqlText      = $row.SqlText
                    QueryPlan    = $row.QueryPlan
                    InfoUrl      = $row.InfoUrl
                } | Select-DefaultView -ExcludeProperty 'SqlText', 'QueryPlan', 'InfoUrl'
            }
        }
    }
}