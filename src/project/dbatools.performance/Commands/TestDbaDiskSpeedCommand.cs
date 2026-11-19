#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Analyzes SQL Server virtual-file I/O performance. Port of
/// public/Test-DbaDiskSpeed.ps1 (W1-129). BeginProcessing constructs the source SQL
/// text once and carries it across pipeline records. The per-record body rides one
/// module-scoped PowerShell hop so connection handling, host-platform SQL rewriting,
/// Stop-Function flow, SMO Query ETS invocation, and DataRow output retain the
/// advanced function's observable engine semantics. Surface pinned by
/// migration/baselines/Test-DbaDiskSpeed.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaDiskSpeed")]
public sealed class TestDbaDiskSpeedCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Databases to include.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Databases to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Aggregate I/O statistics by database, disk, or file.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    [ValidateSet("Database", "Disk", "File")]
    public string AggregateBy { get; set; } = "File";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _sql;

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Database, ExcludeDatabase, AggregateBy))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                _sql = item?.BaseObject;
            }
        }
    }

    protected override void ProcessRecord()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, AggregateBy, EnableException.ToBool(),
            _sql, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BeginScript = """
param($Database, $ExcludeDatabase, $AggregateBy)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($Database, $ExcludeDatabase, $AggregateBy)

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

    $sql
} $Database $ExcludeDatabase $AggregateBy 3>&1 2>&1
""";

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AggregateBy, $EnableException, $sql, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($SqlInstance, $SqlCredential, $AggregateBy, $EnableException, $sql)

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaDiskSpeed
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

            Write-Message -Level Debug -Message "Executing $sqlToRun" -FunctionName Test-DbaDiskSpeed -ModuleName "dbatools"
            $server.Query("$sqlToRun")
        }

} $SqlInstance $SqlCredential $AggregateBy $EnableException $sql @__commonParameters 3>&1 2>&1
""";
}
