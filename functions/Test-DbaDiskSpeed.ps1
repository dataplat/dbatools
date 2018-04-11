function Test-DbaDiskSpeed {
    <#
    .SYNOPSIS
        Tests how disks are performing.

    .DESCRIPTION
        Tests how disks are performing.

        This command uses a query from Rich Benner which was adapted from David Pless's article:
        https://blogs.msdn.microsoft.com/dpless/2010/12/01/leveraging-sys-dm_io_virtual_file_stats/
        https://github.com/RichBenner/PersonalCode/blob/master/Disk_Speed_Check.sql

    .PARAMETER SqlInstance
        Allows you to specify a comma separated list of servers to query.

    .PARAMETER SqlCredential
       Allows you to login to the SQL Server using alternative credentials.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Author: Chrissy LeMaire
        Tags: Performance

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaDiskSpeed

    .EXAMPLE
        Test-DbaDiskSpeed -SqlInstance sql2008, sqlserver2012
        Tests how disks are performing on sql2008 and sqlserver2012.

    .EXAMPLE
        Test-DbaDiskSpeed -SqlInstance sql2008 -Database tempdb
        Tests how disks storing tempdb files on sql2008 are performing.
    #>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )

    begin {

        $sql = "SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, db_name(a.database_id) AS [Database]
        , CAST(((a.size_on_disk_bytes/1024)/1024.0)/1024 AS DECIMAL(10,2)) AS [SizeGB]
        , b.name AS [FileName]
        , a.file_id AS [FileID]
        , CASE WHEN a.file_id = 2 THEN 'Log' ELSE 'Data' END AS [FileType]
        , UPPER(SUBSTRING(b.physical_name, 1, 2)) AS [DiskLocation]
        , a.num_of_reads AS [Reads]
        , CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END AS [AverageReadStall]
        , CASE
            WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END < 10 THEN 'Very Good'
            WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END < 20 THEN 'OK'
            WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END < 50 THEN 'Slow, Needs Attention'
            WHEN CASE WHEN a.num_of_reads < 1 THEN NULL ELSE CAST(a.io_stall_read_ms/(a.num_of_reads) AS INT) END >= 50 THEN 'Serious I/O Bottleneck'
            END AS [ReadPerformance]
        , a.num_of_writes AS [Writes]
        , CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/a.num_of_writes AS INT) END AS [AverageWriteStall]
        , CASE
            WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END < 10 THEN 'Very Good'
            WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END < 20 THEN 'OK'
            WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END < 50 THEN 'Slow, Needs Attention'
            WHEN CASE WHEN a.num_of_writes < 1 THEN NULL ELSE CAST(a.io_stall_write_ms/(a.num_of_writes) AS INT) END >= 50 THEN 'Serious I/O Bottleneck'
            END AS [WritePerformance]
        FROM sys.dm_io_virtual_file_stats (NULL, NULL) a
        JOIN sys.master_files b
            ON a.file_id = b.file_id
            AND a.database_id = b.database_id"

        if ($Database -or $ExcludeDatabase) {
            if ($database) {
                $where = " where db_name(a.database_id) in ('$($Database -join "'")') "
            }
            if ($ExcludeDatabase) {
                $where = " where db_name(a.database_id) not in ('$($ExcludeDatabase -join "'")') "
            }
            $sql += $where
        }

        $sql += " ORDER BY (a.num_of_reads + a.num_of_writes) DESC"
    }

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Debug -Message "Executing $sql"
            $server.Query("$sql")
        }
    }
}