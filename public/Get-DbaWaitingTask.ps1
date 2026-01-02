function Get-DbaWaitingTask {
    <#
    .SYNOPSIS
        Retrieves detailed information about currently waiting sessions and their wait types from SQL Server dynamic management views.

    .DESCRIPTION
        Queries sys.dm_os_waiting_tasks and related DMVs to identify sessions that are currently waiting, along with comprehensive diagnostic information including wait types, durations, blocking sessions, SQL text, and query plans. This function helps DBAs quickly identify performance bottlenecks, troubleshoot blocking issues, and analyze what's causing slowdowns in real-time. The output includes helpful context like degree of parallelism for CXPACKET waits, resource descriptions, and direct links to SQLSkills wait type documentation for further analysis.

        This command is based on the waiting task T-SQL script published by Paul Randal.
        Reference: https://www.sqlskills.com/blogs/paul/updated-sys-dm_os_waiting_tasks-script-2/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version XXXX or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Spid
        Filters results to show waiting tasks for specific session IDs only. Accepts one or more SPIDs as an array.
        Use this when troubleshooting known problematic sessions or when you want to focus on specific user connections instead of scanning all active sessions.

    .PARAMETER IncludeSystemSpid
        Includes system sessions (SPIDs) in the results along with user sessions. By default, only user sessions are returned.
        Enable this when diagnosing system-level performance issues or when system processes might be causing blocking or resource contention.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Waits, Task
        Author: Shawn Melton (@wsmelton), wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaWaitingTask

    .OUTPUTS
        PSCustomObject

        Returns one object per waiting session found on the SQL Server instance, with the following default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Spid: The session ID (SPID) of the waiting session
        - Thread: The execution context ID (thread number within the session)
        - Scheduler: The scheduler ID managing this task
        - WaitMs: The duration of the wait in milliseconds
        - WaitType: The type of wait (e.g., CXPACKET, LCK_M_IX, PAGEIOLATCH_SH, etc.)
        - BlockingSpid: The session ID (SPID) blocking this session, or 0 if no blocking

        Additional properties available with Select-Object *:
        - ResourceDesc: Detailed resource description from the wait (e.g., database:file:page IDs for page waits)
        - NodeId: For CXPACKET waits, the parallel exchange node ID from ResourceDesc
        - Dop: Degree of Parallelism for parallel execution waits; null for serial execution
        - DbId: Database ID where the wait is occurring
        - SqlText: The SQL text being executed in the waiting session (excluded from default display)
        - QueryPlan: The query execution plan as XML (excluded from default display)
        - InfoUrl: URL to SQLSkills wait type documentation for this specific wait type (excluded from default display)

        When -Spid is specified, only waiting tasks for those session IDs are returned. When -IncludeSystemSpid is specified, system sessions are included in results along with user sessions.

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
                [est].[text] AS [SqlText],
                [eqp].[query_plan] AS [QueryPlan],
                CAST ('https://www.sqlskills.com/help/waits/' + [owt].[wait_type] AS XML) AS [URL]
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
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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