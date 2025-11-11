function Get-DbaMemoryCondition {
    <#
    .SYNOPSIS
        Retrieves memory pressure notifications and utilization metrics from SQL Server resource monitor ring buffers.

    .DESCRIPTION
        Analyzes SQL Server's internal resource monitor ring buffers to identify memory pressure events and track memory utilization over time. This helps DBAs diagnose performance issues caused by insufficient memory, excessive paging, or memory pressure conditions that trigger automatic memory adjustments.

        The function returns detailed memory statistics including physical memory usage, page file utilization, virtual address space consumption, and SQL Server-specific memory allocation metrics. Each record includes the exact timestamp when memory conditions were recorded, making it valuable for correlating memory pressure with performance degradation during specific time periods.

        This command is based on a query provided by Microsoft support and queries the sys.dm_os_ring_buffers DMV to extract resource monitor notifications.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Memory, General
        Author: IJeb Reitsma

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaMemoryCondition

    .EXAMPLE
        PS C:\> Get-DbaMemoryCondition -SqlInstance sqlserver2014a

        Returns the memory conditions for the selected instance

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a -Group GroupName | Get-DbaMemoryCondition | Out-GridView

        Returns the memory conditions for a group of servers from SQL Server Central Management Server (CMS). Send output to GridView.
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
    SELECT
        CONVERT(VARCHAR(30), GETDATE(), 121) AS Runtime,
        DATEADD(MILLISECOND, -1 * CONVERT(BIGINT, (sys.ms_ticks - sys.s_ticks*1000) - (a.[RecordTime] - a.[RecordTime_S]*1000)), DATEADD(SECOND, -1 * (sys.s_ticks - a.[RecordTime_S]), GETDATE())) AS NotificationTime,
        [NotificationType],
        [MemoryUtilizationPercent],
        [TotalPhysicalMemoryKB],
        [AvailablePhysicalMemoryKB],
        [TotalPageFileKB],
        [AvailablePageFileKB],
        [TotalVirtualAddressSpaceKB],
        [AvailableVirtualAddressSpaceKB],
        [NodeId],
        [SQLReservedMemoryKB],
        [SQLCommittedMemoryKB],
        [RecordId],
        [Type],
        [Indicators],
        [RecordTime],
        sys.ms_ticks AS [CurrentTime]
    FROM
    (
        SELECT
            x.value('(//Record/ResourceMonitor/Notification)[1]', 'VARCHAR(30)') AS [NotificationType],
            x.value('(//Record/MemoryRecord/MemoryUtilization)[1]', 'BIGINT') AS [MemoryUtilizationPercent],
            x.value('(//Record/MemoryRecord/TotalPhysicalMemory)[1]', 'BIGINT') AS [TotalPhysicalMemoryKB],
            x.value('(//Record/MemoryRecord/AvailablePhysicalMemory)[1]', 'BIGINT') AS [AvailablePhysicalMemoryKB],
            x.value('(//Record/MemoryRecord/TotalPageFile)[1]', 'BIGINT') AS [TotalPageFileKB],
            x.value('(//Record/MemoryRecord/AvailablePageFile)[1]', 'BIGINT') AS [AvailablePageFileKB],
            x.value('(//Record/MemoryRecord/TotalVirtualAddressSpace)[1]', 'BIGINT') AS [TotalVirtualAddressSpaceKB],
            x.value('(//Record/MemoryRecord/AvailableVirtualAddressSpace)[1]', 'BIGINT') AS [AvailableVirtualAddressSpaceKB],
            x.value('(//Record/MemoryNode/@id)[1]', 'BIGINT') AS [NodeId],
            x.value('(//Record/MemoryNode/ReservedMemory)[1]', 'BIGINT') AS [SQLReservedMemoryKB],
            x.value('(//Record/MemoryNode/CommittedMemory)[1]', 'BIGINT') AS [SQLCommittedMemoryKB],
            x.value('(//Record/@id)[1]', 'BIGINT') AS [RecordId],
            x.value('(//Record/@type)[1]', 'VARCHAR(30)') AS [Type],
            x.value('(//Record/ResourceMonitor/Indicators)[1]', 'BIGINT') AS [Indicators],
            x.value('(//Record/@time)[1]', 'BIGINT') AS [RecordTime],
            CONVERT(BIGINT, x.value('(//Record/@time)[1]', 'BIGINT')/1000) AS [RecordTime_S]
        FROM
        (
            SELECT CAST(record AS XML) FROM sys.dm_os_ring_buffers
            WHERE ring_buffer_type = 'RING_BUFFER_RESOURCE_MONITOR'
        ) AS R(x)
    ) a
    CROSS JOIN
    (
        SELECT
            ms_ticks,
            CONVERT(BIGINT, ms_ticks/1000) AS s_ticks
        FROM sys.dm_os_sys_info
    ) sys
    ORDER BY a.[RecordTime] ASC"
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $results = $server.Query($sql)
            } catch {
                Stop-Function -Message "Issue collecting data" -Target $instance -ErrorRecord $_
            }
            foreach ($row in $results) {
                [PSCustomObject]@{
                    ComputerName                 = $server.ComputerName
                    InstanceName                 = $server.ServiceName
                    SqlInstance                  = $server.DomainInstanceName
                    Runtime                      = $row.runtime
                    NotificationTime             = $row.NotificationTime
                    NotificationType             = $row.NotificationType
                    MemoryUtilizationPercent     = $row.MemoryUtilizationPercent
                    TotalPhysicalMemory          = [dbasize]$row.TotalPhysicalMemoryKB * 1024
                    AvailablePhysicalMemory      = [dbasize]$row.AvailablePhysicalMemoryKB * 1024
                    TotalPageFile                = [dbasize]$row.TotalPageFileKB * 1024
                    AvailablePageFile            = [dbasize]$row.AvailablePageFileKB * 1024
                    TotalVirtualAddressSpace     = [dbasize]$row.TotalVirtualAddressSpaceKB * 1024
                    AvailableVirtualAddressSpace = [dbasize]$row.AvailableVirtualAddressSpaceKB * 1024
                    NodeId                       = $row.NodeId
                    SQLReservedMemory            = [dbasize]$row.SQLReservedMemoryKB * 1024
                    SQLCommittedMemory           = [dbasize]$row.SQLCommittedMemoryKB * 1024
                    RecordId                     = $row.RecordId
                    Type                         = $row.Type
                    Indicators                   = $row.Indicators
                    RecordTime                   = $row.RecordTime
                    CurrentTime                  = $row.CurrentTime
                }
            }
        }
    }
}