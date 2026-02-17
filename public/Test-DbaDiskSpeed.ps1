function Test-DbaDiskSpeed {
    <#
    .SYNOPSIS
        Analyzes database file I/O performance and identifies storage bottlenecks using SQL Server DMV statistics

    .DESCRIPTION
        Queries sys.dm_io_virtual_file_stats to measure read/write latency, throughput, and overall I/O performance for database files. Returns performance ratings from "Very Good" to "Serious I/O Bottleneck" based on average stall times, helping you quickly identify storage issues that impact SQL Server performance. Can aggregate results by individual file, database, or disk level to pinpoint exactly where I/O problems exist. Essential for troubleshooting slow queries, validating storage upgrades, and proactive performance monitoring.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to include in the I/O performance analysis. Accepts database names as strings or arrays.
        Use this when you need to focus on specific databases instead of analyzing all databases on the instance.
        Commonly used to isolate performance issues in production databases or exclude system databases from analysis.

    .PARAMETER ExcludeDatabase
        Specifies which databases to exclude from the I/O performance analysis. Accepts database names as strings or arrays.
        Use this when you want to analyze most databases but skip specific ones like development databases or those with known issues.
        Helpful for excluding system databases (master, model, msdb) when focusing on user database performance.

    .PARAMETER AggregateBy
        Controls how I/O statistics are grouped and summarized in the results. Options are 'File' (default), 'Database', or 'Disk'.
        Use 'File' for detailed analysis of individual data and log files, 'Database' to compare performance across databases, or 'Disk' to identify storage-level bottlenecks.
        File-level analysis helps pinpoint specific problematic files, while disk-level aggregation is useful for storage capacity planning and identifying hardware issues.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Performance
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        System.Data.DataRow

        Returns I/O performance statistics aggregated at the file, database, or disk level based on the -AggregateBy parameter. Properties vary by aggregation level.

        Default properties (all aggregation levels):
        - ComputerName: The computer name
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL instance name (computer\instance)
        - Reads: Number of read operations (summed across files at database/disk level)
        - AverageReadStall: Average read latency in milliseconds
        - ReadPerformance: Performance rating based on read latency - "Very Good" (< 10ms), "OK" (< 20ms), "Slow, Needs Attention" (< 50ms), or "Serious I/O Bottleneck" (>= 50ms)
        - Writes: Number of write operations (summed across files at database/disk level)
        - AverageWriteStall: Average write latency in milliseconds
        - WritePerformance: Performance rating based on write latency - "Very Good", "OK", "Slow, Needs Attention", or "Serious I/O Bottleneck"
        - Avg Overall Latency: Average combined read/write latency in milliseconds
        - Avg Bytes/Read: Average bytes per read operation
        - Avg Bytes/Write: Average bytes per write operation
        - Avg Bytes/Transfer: Average bytes per I/O transfer operation

        Additional properties by aggregation level:

        When -AggregateBy 'File' (default):
        - Database: Database name
        - SizeGB: File size in gigabytes
        - FileName: File name (Windows: letter+name like "C:\...\file.mdf", Linux: full path)
        - FileID: File ID within the database
        - FileType: Type of file - "Log" for transaction log, "Data" for data files

        When -AggregateBy 'Database':
        - Database: Database name (aggregated across all files in the database)

        When -AggregateBy 'Disk':
        - DiskLocation: Disk identifier - Windows letter like "C", "D"; Linux path prefix like "/var/opt/mssql"

    .LINK
        https://dbatools.io/Test-DbaDiskSpeed

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008, sqlserver2012

        Tests how disks are performing on sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008 -Database tempdb

        Tests how disks storing tempdb files on sql2008 are performing.

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008 -AggregateBy "File" -Database tempdb

        Returns the statistics aggregated to the file level. This is the default aggregation level if the -AggregateBy param is omitted. The -Database or -ExcludeDatabase params can be used to filter for specific databases.

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008 -AggregateBy "Database"

        Returns the statistics aggregated to the database/disk level. The -Database or -ExcludeDatabase params can be used to filter for specific databases.

    .EXAMPLE
        PS C:\> Test-DbaDiskSpeed -SqlInstance sql2008 -AggregateBy "Disk"

        Returns the statistics aggregated to the disk level. The -Database or -ExcludeDatabase params can be used to filter for specific databases.

    .EXAMPLE
        PS C:\> $results = @(instance1, instance2) | Test-DbaDiskSpeed

        Returns the statistics for instance1 and instance2 as part of a pipeline command

    .EXAMPLE
        PS C:\> $databases = @('master', 'model')
        $results = Test-DbaDiskSpeed -SqlInstance sql2019 -Database $databases

        Returns the statistics for more than one database specified.

    .EXAMPLE
        PS C:\> $excludedDatabases = @('master', 'model')
        $results = Test-DbaDiskSpeed -SqlInstance sql2019 -ExcludeDatabase $excludedDatabases

        Returns the statistics for databases other than the exclusions specified.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [ValidateSet('Database', 'Disk', 'File')]
        [string]$AggregateBy = 'File',
        [switch]$EnableException
    )

    begin {

        $sql = $null

        # Consolidating the common SQL to hopefully make the maintenance easier. The various scenarios are enabled by uncommenting specific lines at runtime.
        $selectList =
        "SELECT
            SERVERPROPERTY('MachineName')                                                                               AS ComputerName
        ,   ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER')                                                       AS InstanceName
        ,   SERVERPROPERTY('ServerName')                                                                                AS SqlInstance
        --DATABASE-SELECT,  DB_NAME(a.database_id)                                                                      AS [Database]
        --FILE-ALL,   CAST(((a.size_on_disk_bytes/1024)/1024.0)/1024 AS DECIMAL(10,2))                                  AS [SizeGB]
        --FILE-WINDOWS, RIGHT(b.physical_name, CHARINDEX('\', REVERSE(b.physical_name)) -1)                             AS [FileName]
        --FILE-LINUX, RIGHT(b.physical_name, CHARINDEX('/', REVERSE(b.physical_name)) -1)                               AS [FileName]
        --FILE-ALL,   a.file_id                                                                                         AS [FileID]
        --FILE-ALL,   CASE WHEN a.file_id = 2 THEN 'Log' ELSE 'Data' END                                                AS [FileType]
        --DATABASE-OR-DISK, a.DiskLocation                                                                              AS DiskLocation
        --FILE-WINDOWS,   UPPER(SUBSTRING(b.physical_name, 1, 2))                                                       AS DiskLocation
        --FILE-LINUX, SUBSTRING(physical_name, 1, CHARINDEX('/', physical_name, CHARINDEX('/', physical_name) + 1) - 1) AS DiskLocation
        ,   a.num_of_reads                                                                                              AS [Reads]
        ,   CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END            AS [AverageReadStall]
        ,   CASE
                WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END < 10 THEN 'Very Good'
                WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END < 20 THEN 'OK'
                WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END < 50 THEN 'Slow, Needs Attention'
                WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END >= 50 THEN 'Serious I/O Bottleneck'
            END                                                                                                         AS [ReadPerformance]
        ,   a.num_of_writes                                                                                             AS [Writes]
        ,   CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/a.num_of_writes AS INT) END           AS [AverageWriteStall]
        ,   CASE
                WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END < 10 THEN 'Very Good'
                WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END < 20 THEN 'OK'
                WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END < 50 THEN 'Slow, Needs Attention'
                WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END >= 50 THEN 'Serious I/O Bottleneck'
            END                                                                                                         AS [WritePerformance]
        ,   CASE
                WHEN (a.num_of_reads = 0 AND a.num_of_writes = 0) THEN NULL
                ELSE (a.io_stall/(a.num_of_reads + a.num_of_writes))
            END                                                                                                         AS [Avg Overall Latency]
        ,   CASE
                WHEN a.num_of_reads = 0 THEN NULL
                ELSE (a.num_of_bytes_read/a.num_of_reads)
            END                                                                                                         AS [Avg Bytes/Read]
        ,   CASE
                WHEN a.num_of_writes = 0 THEN NULL
                ELSE (a.num_of_bytes_written/a.num_of_writes)
            END                                                                                                         AS [Avg Bytes/Write]
        ,   CASE
                WHEN (a.num_of_reads = 0 AND a.num_of_writes = 0) THEN NULL
                ELSE ((a.num_of_bytes_read + a.num_of_bytes_written)/(a.num_of_reads + a.num_of_writes))
            END                                                                                                         AS [Avg Bytes/Transfer]"

        if ($AggregateBy -eq 'File') {
            $sql = "$selectList
                    FROM sys.dm_io_virtual_file_stats (NULL, NULL) a
                    JOIN sys.master_files b
                        ON a.file_id = b.file_id
                        AND a.database_id = b.database_id"

        } elseif ($AggregateBy -in ('Database', 'Disk')) {
            $sql = "$selectList
                    FROM
                    (
                        SELECT
                        --WINDOWS UPPER(SUBSTRING(b.physical_name, 1, 2))                                                           AS DiskLocation
                        --LINUX SUBSTRING(physical_name, 1, CHARINDEX('/', physical_name, CHARINDEX('/', physical_name) + 1) - 1)   AS DiskLocation
                        ,   SUM(a.num_of_reads)                                                                                     AS num_of_reads
                        ,   SUM(a.io_stall_read_ms)                                                                                 AS io_stall_read_ms
                        ,   SUM(a.num_of_writes)                                                                                    AS num_of_writes
                        ,   SUM(a.io_stall_write_ms)                                                                                AS io_stall_write_ms
                        ,   SUM(a.num_of_bytes_read)                                                                                AS num_of_bytes_read
                        ,   SUM(a.num_of_bytes_written)                                                                             AS num_of_bytes_written
                        ,   SUM(a.io_stall)                                                                                         AS io_stall
                        --DATABASE-GROUPBY, a.database_id                                                                           AS database_id
                        FROM sys.dm_io_virtual_file_stats (NULL, NULL) a
                        JOIN sys.master_files b
                            ON a.file_id = b.file_id
                            AND a.database_id = b.database_id
                        GROUP BY
                            --DATABASE-GROUPBYa.database_id,
                            --WINDOWS UPPER(SUBSTRING(b.physical_name, 1, 2))
                            --LINUX SUBSTRING(physical_name, 1, CHARINDEX('/', physical_name, CHARINDEX('/', physical_name) + 1) - 1)
                    ) AS a"
        }

        if ($Database -or $ExcludeDatabase) {
            if ($Database) {
                $where = " WHERE DB_NAME(a.database_id) IN ('$($Database -join "','")') "
            }
            if ($ExcludeDatabase) {
                $where = " WHERE DB_NAME(a.database_id) NOT IN ('$($ExcludeDatabase -join "','")') "
            }
            $sql += $where
        }

        $sql += " ORDER BY (a.num_of_reads + a.num_of_writes) DESC"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $sqlToRun = $sql

            # At runtime uncomment the relevant pieces in the SQL
            if ($AggregateBy -eq 'File') {

                $sqlToRun = $sqlToRun.replace("--DATABASE-SELECT", "").replace("--FILE-ALL", "")

                if ($server.HostPlatform -eq "Linux") {
                    $sqlToRun = $sqlToRun.replace("--FILE-LINUX", "")
                } else {
                    $sqlToRun = $sqlToRun.replace("--FILE-WINDOWS", "")
                }

            } elseif ($AggregateBy -in ('Database', 'Disk')) {

                $sqlToRun = $sqlToRun.replace("--DATABASE-OR-DISK", "")

                if ($server.HostPlatform -eq "Linux") {
                    $sqlToRun = $sqlToRun.replace("--LINUX", "")
                } else {
                    $sqlToRun = $sqlToRun.replace("--WINDOWS", "")
                }

                if ($AggregateBy -eq 'Database') {
                    $sqlToRun = $sqlToRun.replace("--DATABASE-SELECT", "").replace("--DATABASE-GROUPBY", "")
                }
            }

            Write-Message -Level Debug -Message "Executing $sqlToRun"
            $server.Query("$sqlToRun")
        }
    }
}