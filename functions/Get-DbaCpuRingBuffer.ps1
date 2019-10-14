function Get-DbaCpuRingBuffer {
    <#
    .SYNOPSIS
        Collects CPU data from sys.dm_os_ring_buffers.  Works on SQL Server 2005 and above.

    .DESCRIPTION
        This command is based off of Glen Berry's diagnostic query for average CPU

        The sys.dm_os_ring_buffers stores the average CPU utilization history
        by the current instance of SQL Server, plus the summed average CPU utilization
        by all other processes on your machine are captured in one minute increments
        for the past 256 minutes.

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
        Allows you to specify a Collection Period in Minutes. Default is 60 minutes

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: CPU
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
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.VersionMajor -gt 9) {
                $currentTimestamp = ($server.Query("SELECT cpu_ticks / CONVERT (float, ( cpu_ticks / ms_ticks )) as TimeStamp FROM sys.dm_os_sys_info"))[0]
            } else {
                $currentTimestamp = ($server.Query("SELECT cpu_ticks / CONVERT(FLOAT, cpu_ticks_in_ms) as TimeStamp FROM sys.dm_os_sys_info"))[0]
            }
            Write-Message -Level Verbose -Message "Using current timestampe of $currentTimestamp"

            $sql = "With RingBufferSchedulerMonitor as
                (
                    SELECT
                        timestamp,
                        CONVERT(xml, record) AS record
                    FROM sys.dm_os_ring_buffers
                    WHERE (ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR')
                    AND (record LIKE '%%')
                ), RingBufferSchedulerMonitorValues as
                (
                    SELECT
                        record.value('(./Record/@id)[1]', 'int') AS record_id,
                        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
                        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization,
                        timestamp,
                        DATEADD(ss, (-1 * ($currentTimestamp - [timestamp]))/1000, GETDATE()) AS EventTime
                    FROM RingBufferSchedulerMonitor
                )
                Select
                    SERVERPROPERTY('ServerName') as ServerName,
                    record_id,
                    EventTime,
                    SQLProcessUtilization,
                    SystemIdle,
                    100 - SystemIdle - SQLProcessUtilization AS OtherProcessUtilization
                From RingBufferSchedulerMonitorValues
                WHERE EventTime> DATEADD(MINUTE, -$CollectionMinutes, GETDATE()) ;"

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