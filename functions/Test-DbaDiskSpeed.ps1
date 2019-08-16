function Test-DbaDiskSpeed {
    <#
    .SYNOPSIS
        Tests how disks are performing.

    .DESCRIPTION
        Tests how disks are performing.

        This command uses a query from Rich Benner
        https://github.com/RichBenner/PersonalCode/blob/master/Disk_Speed_Check.sql

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

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )

    begin {

        $sql = "SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, db_name(a.database_id) AS [Database]
        , CAST(((a.size_on_disk_bytes/1024)/1024.0)/1024 AS DECIMAL(10,2)) AS [SizeGB]
        , RIGHT(b.physical_name, CHARINDEX('\', REVERSE(b.physical_name)) -1) AS [FileName]
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

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Debug -Message "Executing $sql"
            $server.Query("$sql")
        }
    }
}