function Get-DbaTempdbUsage {
    <#
    .SYNOPSIS
        Gets Tempdb usage for running queries.

    .DESCRIPTION
        This function queries DMVs for running sessions using tempdb and returns results if those sessions have user or internal space allocated or deallocated against them.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Tempdb
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaTempdbUsage

    .OUTPUTS
        PSCustomObject

        Returns one object per running session that has allocated or deallocated tempdb space. For sessions with no tempdb allocation activity, no object is returned.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Spid: Session ID of the running query (int)
        - StatementCommand: The SQL command being executed (SELECT, INSERT, UPDATE, DELETE, etc.)
        - QueryText: The actual T-SQL statement text being executed
        - ProcedureName: Schema-qualified name of the stored procedure if applicable
        - StartTime: DateTime when the request started executing
        - CurrentUserAllocatedKB: Current user object allocation in KB for this session (int)
        - TotalUserAllocatedKB: Total user object allocation in KB (int)
        - UserDeallocatedKB: User object deallocation in KB (int)
        - TotalUserDeallocatedKB: Total user object deallocation in KB (int)
        - InternalAllocatedKB: Internal object allocation in KB (int)
        - TotalInternalAllocatedKB: Total internal object allocation in KB (int)
        - InternalDeallocatedKB: Internal object deallocation in KB (int)
        - TotalInternalDeallocatedKB: Total internal object deallocation in KB (int)
        - RequestedReads: Number of physical read operations performed by the request (int)
        - RequestedWrites: Number of write operations performed by the request (int)
        - RequestedLogicalReads: Number of logical read operations performed by the request (int)
        - RequestedCPUTime: CPU time in milliseconds used by the request (int)
        - IsUserProcess: Boolean indicating if the session is a user process (true) or system process (false)
        - Status: Current status of the session (running, sleeping, dormant, etc.)
        - Database: Name of the database being accessed
        - LoginName: SQL Server login name
        - OriginalLoginName: Original login name before impersonation if applicable
        - NTDomain: Windows domain name if Windows authentication is used
        - NTUserName: Windows username if Windows authentication is used
        - HostName: Client computer hostname
        - ProgramName: Name of the client application (e.g., SQL Server Management Studio, SSMS)
        - LoginTime: DateTime when the session logged in
        - LastRequestedStartTime: DateTime when the last request started
        - LastRequestedEndTime: DateTime when the last request ended

    .EXAMPLE
        PS C:\> Get-DbaTempdbUsage -SqlInstance localhost\SQLDEV2K14

        Gets tempdb usage for localhost\SQLDEV2K14
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $sql = "SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance,
        t.session_id AS Spid,
        r.command AS StatementCommand,
        SUBSTRING(   est.[text], (r.statement_start_offset / 2) + 1,
            ((CASE r.statement_end_offset
                WHEN-1 THEN DATALENGTH(est.[text]) ELSE r.statement_end_offset
                END - r.statement_start_offset
            ) / 2 ) + 1 ) AS QueryText,
        QUOTENAME(DB_NAME(r.database_id)) + N'.' + QUOTENAME(OBJECT_SCHEMA_NAME(est.objectid, est.dbid)) + N'.'
        + QUOTENAME(OBJECT_NAME(est.objectid, est.dbid)) AS ProcedureName,
        r.start_time AS StartTime,
        tdb.UserObjectAllocated * 8 AS CurrentUserAllocatedKB,
        (t.user_objects_alloc_page_count + tdb.UserObjectAllocated) * 8 AS TotalUserAllocatedKB,
        tdb.UserObjectDeallocated * 8 AS UserDeallocatedKB,
        (t.user_objects_dealloc_page_count + tdb.UserObjectDeallocated) * 8 AS TotalUserDeallocatedKB,
        tdb.InternalObjectAllocated * 8 AS InternalAllocatedKB,
        (t.internal_objects_alloc_page_count + tdb.InternalObjectAllocated) * 8 AS TotalInternalAllocatedKB,
        tdb.InternalObjectDeallocated * 8 AS InternalDeallocatedKB,
        (t.internal_objects_dealloc_page_count + tdb.InternalObjectDeallocated) * 8 AS TotalInternalDeallocatedKB,
        r.reads AS RequestedReads,
        r.writes AS RequestedWrites,
        r.logical_reads AS RequestedLogicalReads,
        r.cpu_time AS RequestedCPUTime,
        s.is_user_process AS IsUserProcess,
        s.[status] AS [Status],
        DB_NAME(r.database_id) AS [Database],
        s.login_name AS LoginName,
        s.original_login_name AS OriginalLoginName,
        s.nt_domain AS NTDomain,
        s.nt_user_name AS NTUserName,
        s.[host_name] AS HostName,
        s.[program_name] AS ProgramName,
        s.login_time AS LoginTime,
        s.last_request_start_time AS LastRequestedStartTime,
        s.last_request_end_time AS LastRequestedEndTime
FROM    sys.dm_db_session_space_usage AS t
INNER JOIN sys.dm_exec_sessions AS s
    ON s.session_id = t.session_id
LEFT JOIN sys.dm_exec_requests AS r
    ON r.session_id = s.session_id
LEFT JOIN (
    SELECT _tsu.session_id,
        _tsu.request_id,
        SUM(_tsu.user_objects_alloc_page_count)       AS UserObjectAllocated,
        SUM(_tsu.user_objects_dealloc_page_count)     AS UserObjectDeallocated,
        SUM(_tsu.internal_objects_alloc_page_count)   AS InternalObjectAllocated,
        SUM(_tsu.internal_objects_dealloc_page_count) AS InternalObjectDeallocated
    FROM tempdb.sys.dm_db_task_space_usage AS _tsu
    GROUP BY _tsu.session_id, _tsu.request_id
) AS tdb ON  tdb.session_id = r.session_id AND  tdb.request_id = r.request_id
OUTER APPLY sys.dm_exec_sql_text(r.[sql_handle]) AS est
WHERE   t.session_id != @@SPID
AND   (tdb.UserObjectAllocated - tdb.UserObjectDeallocated + tdb.InternalObjectAllocated - tdb.InternalObjectDeallocated) != 0
OPTION (RECOMPILE);"

            $server.Query($sql)
        }
    }
}