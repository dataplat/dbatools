function Get-DbaIoLatency {
    <#
    .SYNOPSIS
        Retrieves I/O latency metrics for all database files to identify storage performance bottlenecks

    .DESCRIPTION
        Queries sys.dm_io_virtual_file_stats to collect detailed I/O performance statistics for every database file on the SQL Server instance. Returns calculated latency metrics including read latency, write latency, and overall latency in milliseconds, plus throughput statistics like average bytes per read and write operation. Essential for diagnosing slow database performance caused by storage bottlenecks, helping you identify which specific database files are experiencing high I/O wait times. Based on Paul Randal's SQL Server performance tuning methodology.

        Reference:  https://www.sqlskills.com/blogs/paul/how-to-examine-io-subsystem-latencies-from-within-sql-server/
                    https://www.sqlskills.com/blogs/paul/capturing-io-latencies-period-time/

    .PARAMETER SqlInstance
        The SQL Server instance. Server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, IOLatency
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaIoLatency

    .OUTPUTS
        PSCustomObject

        Returns one object per database file on the SQL Server instance, providing detailed I/O performance metrics collected from sys.dm_io_virtual_file_stats.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - DatabaseId: Internal ID of the database containing the file
        - DatabaseName: Name of the database containing the file
        - FileId: Internal ID of the file within the database
        - PhysicalName: Operating system file path of the file
        - NumberOfReads: Total count of read operations since SQL Server instance startup
        - IoStallRead: Total wait time in milliseconds spent waiting for read operations to complete
        - NumberOfwrites: Total count of write operations since SQL Server instance startup
        - IoStallWrite: Total wait time in milliseconds spent waiting for write operations to complete
        - IoStall: Total cumulative I/O wait time in milliseconds (reads + writes)
        - NumberOfBytesRead: Total number of bytes read from this file since instance startup
        - NumberOfBytesWritten: Total number of bytes written to this file since instance startup
        - SampleMilliseconds: Time in milliseconds since the SQL Server instance started (used for duration calculations)
        - SizeOnDiskBytes: Current size of the file on disk in bytes

        Hidden properties (excluded from default display but available with Select-Object *):
        - FileHandle: Internal file handle reference
        - ReadLatency: Average read latency calculated as IoStallRead / NumberOfReads in milliseconds
        - WriteLatency: Average write latency calculated as IoStallWrite / NumberOfwrites in milliseconds
        - Latency: Average I/O latency for both reads and writes calculated as IoStall / (NumberOfReads + NumberOfwrites) in milliseconds
        - AvgBPerRead: Average bytes per read operation calculated as NumberOfBytesRead / NumberOfReads
        - AvgBPerWrite: Average bytes per write operation calculated as NumberOfBytesWritten / NumberOfwrites
        - AvgBPerTransfer: Average bytes per I/O operation (both reads and writes combined)

        All latency values are in milliseconds and are calculated to handle division by zero when no I/O has occurred (returns 0 in such cases).

    .EXAMPLE
        PS C:\> Get-DbaIoLatency -SqlInstance sql2008, sqlserver2012

        Get IO subsystem latency statistics for servers sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> $output = Get-DbaIoLatency -SqlInstance sql2008 | Select-Object * | ConvertTo-DbaDataTable

        Collects all IO subsystem latency statistics on server sql2008 into a Data Table.

    .EXAMPLE
        PS C:\> 'sql2008','sqlserver2012' | Get-DbaIoLatency

        Get IO subsystem latency statistics for servers sql2008 and sqlserver2012 via pipline

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Get-DbaIoLatency -SqlInstance sql2008 -SqlCredential $cred

        Connects using sqladmin credential and returns IO subsystem latency statistics from sql2008
    #>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    BEGIN {
        $sql = "SELECT
            [vfs].[database_id],
            DB_NAME ([vfs].[database_id]) AS [DatabaseName],
            [vfs].[file_id],
            [mf].[physical_name],
            [num_of_reads],
            [io_stall_read_ms],
            [num_of_writes],
            [io_stall_write_ms],
            [io_stall],
            [num_of_bytes_read],
            [num_of_bytes_written],
            [sample_ms],
            [size_on_disk_bytes],
            [file_handle],
            [ReadLatency] =
            CASE WHEN [num_of_reads] = 0
                THEN 0
                ELSE ([io_stall_read_ms] / [num_of_reads])
            END,
            [WriteLatency] =
                CASE WHEN [num_of_writes] = 0
                    THEN 0
                    ELSE ([io_stall_write_ms] / [num_of_writes])
                END,
            [Latency] =
                CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
                    THEN 0
                    ELSE ([io_stall] / ([num_of_reads] + [num_of_writes]))
                END,
            [AvgBPerRead] =
                CASE WHEN [num_of_reads] = 0
                    THEN 0
                    ELSE ([num_of_bytes_read] / [num_of_reads])
                END,
            [AvgBPerWrite] =
                CASE WHEN [num_of_writes] = 0
                    THEN 0
                    ELSE ([num_of_bytes_written] / [num_of_writes])
                END,
            [AvgBPerTransfer] =
                CASE WHEN ([num_of_reads] = 0 AND [num_of_writes] = 0)
                    THEN 0
                    ELSE
                        (([num_of_bytes_read] + [num_of_bytes_written]) /
                        ([num_of_reads] + [num_of_writes]))
                    END
        FROM sys.dm_io_virtual_file_stats (NULL,NULL) AS [vfs]
        INNER JOIN sys.master_files AS [mf]
            ON [vfs].[database_id] = [mf].[database_id]
            AND [vfs].[file_id] = [mf].[file_id];"

        Write-Message -Level Debug -Message $sql

        $excludeColumns = 'FileHandle', 'ReadLatency', 'WriteLatency', 'Latency', 'AvgBPerRead', 'AvgBPerWrite', 'AvgBPerTransfer'
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($row in $server.Query($sql)) {
                [PSCustomObject]@{
                    ComputerName         = $server.ComputerName
                    InstanceName         = $server.ServiceName
                    SqlInstance          = $server.DomainInstanceName
                    DatabaseId           = $row.database_id
                    DatabaseName         = $row.DatabaseName
                    FileId               = $row.file_id
                    PhysicalName         = $row.physical_name
                    NumberOfReads        = $row.num_of_reads
                    IoStallRead          = $row.io_stall_read_ms
                    NumberOfwrites       = $row.num_of_writes
                    IoStallWrite         = $row.io_stall_write_ms
                    IoStall              = $row.io_stall
                    NumberOfBytesRead    = $row.num_of_bytes_read
                    NumberOfBytesWritten = $row.num_of_bytes_written
                    SampleMilliseconds   = $row.sample_ms
                    SizeOnDiskBytes      = $row.size_on_disk_bytes
                    FileHandle           = $row.file_handle
                    ReadLatency          = $row.ReadLatency
                    WriteLatency         = $row.WriteLatency
                    Latency              = $row.Latency
                    AvgBPerRead          = $row.AvgBPerRead
                    AvgBPerWrite         = $row.AvgBPerWrite
                    AvgBPerTransfer      = $row.AvgBPerTransfer
                } | Select-DefaultView -ExcludeProperty $excludeColumns
            }
        }
    }
}