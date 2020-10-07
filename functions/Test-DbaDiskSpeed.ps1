function Test-DbaDiskSpeed {
    <#
    .SYNOPSIS
        Obtains I/O statistics based on the DMV sys.dm_io_virtual_file_stats:

        https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-io-virtual-file-stats-transact-sql

    .DESCRIPTION
        Obtains I/O statistics based on the DMV sys.dm_io_virtual_file_stats:

        https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-io-virtual-file-stats-transact-sql

        This command uses a query from Rich Benner
        https://github.com/RichBenner/PersonalCode/blob/master/Disk_Speed_Check.sql

        ...and also based on further adaptations referenced at https://github.com/sqlcollaborative/dbatools/issues/6551#issue-623216718

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER AggregateBy
        Specify the level of aggregation for the statistics. The available options are 'File' (the default), 'Database', and 'Disk'.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Performance
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

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
                $where = " where db_name(a.database_id) in ('$($Database -join "','")') "
            }
            if ($ExcludeDatabase) {
                $where = " where db_name(a.database_id) not in ('$($ExcludeDatabase -join "','")') "
            }
            $sql += $where
        }

        $sql += " ORDER BY (a.num_of_reads + a.num_of_writes) DESC"
    }

    process {
        foreach ($instance in $SqlInstance) {

            $sqlToRun = $sql

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9

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
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Debug -Message "Executing $sqlToRun"
            $server.Query("$sqlToRun")
        }
    }
}