function Get-DbaCpuRingBuffer {
    <#
    .SYNOPSIS
        Retrieves historical CPU utilization data from SQL Server's internal ring buffer for performance analysis

    .DESCRIPTION
        This command queries sys.dm_os_ring_buffers to extract detailed CPU utilization history for performance troubleshooting and capacity planning. Based on Glen Berry's diagnostic query, it provides minute-by-minute CPU usage breakdowns that help identify performance patterns and resource contention.

        The ring buffer stores CPU utilization data in one-minute increments for up to 256 minutes, tracking three key metrics: SQL Server process utilization, other processes utilization, and system idle time. This historical data is invaluable when investigating performance issues, establishing baselines, or determining if high CPU usage originates from SQL Server or other system processes.

        Use this function to analyze CPU trends during specific time periods, correlate CPU spikes with application events, or gather evidence for capacity planning decisions without requiring external monitoring tools.

        Reference: https://www.sqlskills.com/blogs/glenn/sql-server-diagnostic-information-queries-detailed-day-16//

    .PARAMETER SqlInstance
        Allows you to specify a comma separated list of servers to query.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance. To use:
        $cred = Get-Credential, this pass this $cred to the param.

        Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.

    .PARAMETER CollectionMinutes
        Specifies how many minutes of historical CPU data to retrieve from the ring buffer. Defaults to 60 minutes.
        Use this to extend the analysis window when investigating longer-term CPU trends or to focus on recent activity with shorter periods. Maximum available history is typically 256 minutes depending on system activity.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per minute of CPU ring buffer data retrieved from the SQL Server instance.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - RecordId: The unique record identifier from the ring buffer entry
        - EventTime: DateTime of the CPU sample (in local server time)
        - SQLProcessUtilization: Percentage of CPU used by the SQL Server process (0-100)
        - SystemIdle: Percentage of CPU that is idle (0-100)
        - OtherProcessUtilization: Percentage of CPU used by other processes (0-100), calculated as 100 - SystemIdle - SQLProcessUtilization

    .NOTES
        Tags: Diagnostic, Buffer, CPU
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaCpuRingBuffer

    .EXAMPLE
        PS C:\> Get-DbaCpuRingBuffer -SqlInstance sql2008, sqlserver2012

        Gets CPU Statistics from sys.dm_os_ring_buffers for servers sql2008 and sqlserver2012 for last 60 minutes.

    .EXAMPLE
        PS C:\> Get-DbaCpuRingBuffer -SqlInstance sql2008 -CollectionMinutes 240

        Gets CPU Statistics from sys.dm_os_ring_buffers for server sql2008 for last 240 minutes

    .EXAMPLE
        PS C:\> $output = Get-DbaCpuRingBuffer -SqlInstance sql2008 -CollectionMinutes 240 | Select-Object * | ConvertTo-DbaDataTable

        Gets CPU Statistics from sys.dm_os_ring_buffers for server sql2008 for last 240 minutes into a Data Table.

    .EXAMPLE
        PS C:\> 'sql2008','sql2012' | Get-DbaCpuRingBuffer

        Gets CPU Statistics from sys.dm_os_ring_buffers for servers sql2008 and sqlserver2012

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Get-DbaCpuRingBuffer -SqlInstance sql2008 -SqlCredential $cred

        Connects using sqladmin credential and returns CPU Statistics from sys.dm_os_ring_buffers from sql2008
    #>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$CollectionMinutes = 60,
        [switch]$EnableException
    )

    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.VersionMajor -gt 9) {
                $currentTimestamp = ($server.Query("SELECT cpu_ticks / CONVERT(FLOAT, (cpu_ticks / ms_ticks)) AS TimeStamp FROM sys.dm_os_sys_info"))[0]
            } else {
                $currentTimestamp = ($server.Query("SELECT cpu_ticks / CONVERT(FLOAT, cpu_ticks_in_ms) AS TimeStamp FROM sys.dm_os_sys_info"))[0]
            }
            Write-Message -Level Verbose -Message "Using current timestampe of $currentTimestamp"

            $sql = "WITH RingBufferSchedulerMonitor AS
                (
                    SELECT
                        timestamp,
                        CONVERT(XML, record) AS record
                    FROM sys.dm_os_ring_buffers
                    WHERE (ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR')
                    AND (record LIKE '%%')
                ), RingBufferSchedulerMonitorValues AS
                (
                    SELECT
                        record.value('(./Record/@id)[1]', 'int') AS record_id,
                        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
                        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization,
                        timestamp,
                        DATEADD(ss, (-1 * ($currentTimestamp - [timestamp]))/1000, GETDATE()) AS EventTime
                    FROM RingBufferSchedulerMonitor
                )
                SELECT
                    SERVERPROPERTY('ServerName') AS ServerName,
                    record_id,
                    EventTime,
                    SQLProcessUtilization,
                    SystemIdle,
                    100 - SystemIdle - SQLProcessUtilization AS OtherProcessUtilization
                FROM RingBufferSchedulerMonitorValues
                WHERE EventTime > DATEADD(MINUTE, -$CollectionMinutes, GETDATE());"

            Write-Message -Level Verbose -Message "Executing Sql Staement: $sql"
            foreach ($row in $server.Query($sql)) {
                [PSCustomObject]@{
                    ComputerName            = $server.ComputerName
                    InstanceName            = $server.ServiceName
                    SqlInstance             = $server.DomainInstanceName
                    RecordId                = $row.record_id
                    EventTime               = $row.EventTime
                    SQLProcessUtilization   = $row.SQLProcessUtilization
                    OtherProcessUtilization = $row.OtherProcessUtilization
                    SystemIdle              = $row.SystemIdle
                }
            }
        }
    }
}