function Get-DbaMemoryCondition {
    <#
    .SYNOPSIS
        Determine the memory conditions from SQL Server ring buffers.

    .DESCRIPTION
        The information from SQL Server ring buffers can be used to determine the memory conditions on the server when paging occurs.

        This command is based on a query provided by Microsoft support.
        Reference KB article: https://support.microsoft.com/en-us/help/918483/how-to-reduce-paging-of-buffer-pool-memory-in-the-64-bit-version-of-sq

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
        Tags: Memory
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
        CONVERT (varchar(30), GETDATE(), 121) as Runtime,
        DATEADD (MILLISECOND, -1 * Convert(INT, (sys.ms_ticks - sys.s_ticks*1000) - (a.[RecordTime] - a.[RecordTime_S]*1000)), DATEADD (SECOND, -1 * (sys.s_ticks - a.[RecordTime_S]), GETDATE())) AS NotificationTime,
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
            x.value('(//Record/ResourceMonitor/Notification)[1]', 'varchar(30)') AS [NotificationType],
            x.value('(//Record/MemoryRecord/MemoryUtilization)[1]', 'bigint') AS [MemoryUtilizationPercent],
            x.value('(//Record/MemoryRecord/TotalPhysicalMemory)[1]', 'bigint') AS [TotalPhysicalMemoryKB],
            x.value('(//Record/MemoryRecord/AvailablePhysicalMemory)[1]', 'bigint') AS [AvailablePhysicalMemoryKB],
            x.value('(//Record/MemoryRecord/TotalPageFile)[1]', 'bigint') AS [TotalPageFileKB],
            x.value('(//Record/MemoryRecord/AvailablePageFile)[1]', 'bigint') AS [AvailablePageFileKB],
            x.value('(//Record/MemoryRecord/TotalVirtualAddressSpace)[1]', 'bigint') AS [TotalVirtualAddressSpaceKB],
            x.value('(//Record/MemoryRecord/AvailableVirtualAddressSpace)[1]', 'bigint') AS [AvailableVirtualAddressSpaceKB],
            x.value('(//Record/MemoryNode/@id)[1]', 'bigint') AS [NodeId],
            x.value('(//Record/MemoryNode/ReservedMemory)[1]', 'bigint') AS [SQLReservedMemoryKB],
            x.value('(//Record/MemoryNode/CommittedMemory)[1]', 'bigint') AS [SQLCommittedMemoryKB],
            x.value('(//Record/@id)[1]', 'bigint') AS [RecordId],
            x.value('(//Record/@type)[1]', 'varchar(30)') AS [Type],
            x.value('(//Record/ResourceMonitor/Indicators)[1]', 'bigint') AS [Indicators],
            x.value('(//Record/@time)[1]', 'bigint') AS [RecordTime],
            Convert(int, x.value('(//Record/@time)[1]', 'bigint')/1000) AS [RecordTime_S]
        FROM
        (
            SELECT CAST (record as xml) FROM sys.dm_os_ring_buffers
            WHERE ring_buffer_type = 'RING_BUFFER_RESOURCE_MONITOR'
        ) AS R(x)
    ) a
    CROSS JOIN
    (
        SELECT
            ms_ticks,
            convert(bigint, ms_ticks/1000) as s_ticks
        FROM sys.dm_os_sys_info
    ) sys
    ORDER BY a.[RecordTime] ASC"
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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