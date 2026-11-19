#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Returns database file information (per file: filegroup, sizes, growth, physical path, etc.) across
/// databases. Port of public/Get-DbaDbFile.ps1; the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// A begin+process port. Both SqlInstance and InputObject are ValueFromPipeline (pipe either instances or
/// databases; process fires per record). The begin block is pure SQL-string building - it builds five
/// constant query fragments ($sql, $sqlfrom, $sql2008, $sql2008from, $sql2000) with no parameter
/// interpolation. process, per database, picks the query by compatibility level, runs it, optionally filters
/// by FileGroup, and emits a PSCustomObject per file. The five constants are the only begin-to-process
/// dependency; process reads them read-only, so this is a one-way constant carry via a sentinel (no process
/// re-emit). No accumulator, no interrupt (the one Stop-Function is -Continue), no early return (the "return"
/// words are all in the comment-based help). The one Test-Bound read (FileGroup) becomes the carried flag
/// $__boundFileGroup (C# TestBound(nameof(FileGroup))); body edits also add -FunctionName Get-DbaDbFile to the
/// process block's Stop-Function and three Write-Message. Surface pinned by migration/baselines/Get-DbaDbFile.json
/// (positions 0-5, both SqlInstance and InputObject VFP, no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDbFile")]
public sealed class GetDbaDbFileCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Filter the results to the specified filegroup(s).</summary>
    [Parameter(Position = 4)]
    public object[]? FileGroup { get; set; }

    /// <summary>Database object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The five constant query strings built in begin, carried one-way begin->process.
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__getDbaDbFileBegin"))
            {
                _state = sentinel["__getDbaDbFileBegin"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BeginScript,
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, FileGroup, InputObject, EnableException.ToBool(),
            _state, TestBound(nameof(FileGroup)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
    // PS: the begin block VERBATIM (pure SQL-string building) plus a sentinel carrying the five constant
    // query strings to the process hop. begin has no Stop-Function/Write-Message.
    private const string BeginScript = """
param($EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        #region Sql Query Generation
        $sql = "SELECT
            fg.name AS FileGroupName,
            df.file_id AS 'ID',
            df.Type,
            df.type_desc AS TypeDescription,
            df.name AS LogicalName,
            mf.physical_name AS PhysicalName,
            df.state_desc AS State,
            df.max_size AS MaxSize,
            CASE mf.is_percent_growth WHEN 1 THEN df.growth ELSE df.Growth*8 END AS Growth,
            COALESCE(FILEPROPERTY(df.name, 'spaceused'), 0) AS UsedSpace,
            df.size AS Size,
            COALESCE(vfs.size_on_disk_bytes, 0) AS size_on_disk_bytes,
            CASE df.state_desc WHEN 'OFFLINE' THEN 'True' ELSE 'False' END AS IsOffline,
            CASE mf.is_read_only WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnly,
            CASE mf.is_media_read_only WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnlyMedia,
            CASE mf.is_sparse WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsSparse,
            CASE mf.is_percent_growth WHEN 1 THEN 'Percent' WHEN 0 THEN 'kb' END AS GrowthType,
            COALESCE(vfs.num_of_writes, 0) AS NumberOfDiskWrites,
            COALESCE(vfs.num_of_reads, 0) AS NumberOfDiskReads,
            COALESCE(vfs.num_of_bytes_read, 0) AS BytesReadFromDisk,
            COALESCE(vfs.num_of_bytes_written, 0) AS BytesWrittenToDisk,
            fg.data_space_id AS FileGroupDataSpaceId,
            fg.Type AS FileGroupType,
            fg.type_desc AS FileGroupTypeDescription,
            CASE fg.is_default WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS FileGroupDefault,
            fg.is_read_only AS FileGroupReadOnly"

        $sqlfrom = "FROM sys.database_files df
            LEFT OUTER JOIN  sys.filegroups fg ON df.data_space_id=fg.data_space_id
            LEFT JOIN sys.dm_io_virtual_file_stats(DB_ID(),NULL) vfs ON df.file_id=vfs.file_id
            INNER JOIN sys.master_files mf ON df.file_id = mf.file_id
            AND mf.database_id = DB_ID()"

        $sql2008 = ",vs.available_bytes AS 'VolumeFreeSpace'"
        $sql2008from = "CROSS APPLY sys.dm_os_volume_stats(DB_ID(),df.file_id) vs"

        $sql2000 = "SELECT
            fg.groupname AS FileGroupName,
            df.fileid AS ID,
            CONVERT(INT,df.status & 0x40) / 64 AS Type,
            CASE CONVERT(INT,df.status & 0x40) / 64 WHEN 1 THEN 'LOG' ELSE 'ROWS' END AS TypeDescription,
            df.name AS LogicalName,
            df.filename AS PhysicalName,
            'Existing' AS State,
            df.maxsize AS MaxSize,
            CASE CONVERT(INT,df.status & 0x100000) / 1048576 WHEN 1 THEN df.growth WHEN 0 THEN df.growth*8 END AS Growth,
            FILEPROPERTY(df.name, 'spaceused') AS UsedSpace,
            df.size AS Size,
            CASE CONVERT(INT,df.status & 0x20000000) / 536870912 WHEN 1 THEN 'True' ELSE 'False' END AS IsOffline,
            CASE CONVERT(INT,df.status & 0x1000) / 4096 WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnlyMedia,
            CASE CONVERT(INT,df.status & 0x10000000) / 268435456 WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsSparse,
            CASE CONVERT(INT,df.status & 0x100000) / 1048576 WHEN 1 THEN 'Percent' WHEN 0 THEN 'kb' END AS GrowthType,
            CASE CONVERT(INT,df.status & 0x1000) / 4096 WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnly,
            fg.groupid AS FileGroupDataSpaceId,
            NULL AS FileGroupType,
            NULL AS FileGroupTypeDescription,
            CAST(fg.status & 0x10 AS BIT) AS FileGroupDefault,
            CAST(fg.status & 0x8 AS BIT) AS FileGroupReadOnly
            FROM sysfiles df
            LEFT OUTER JOIN  sysfilegroups fg ON df.groupid=fg.groupid"
        #endregion Sql Query Generation

    @{ __getDbaDbFileBegin = @{ Sql = $sql; SqlFrom = $sqlfrom; Sql2008 = $sql2008; Sql2008From = $sql2008from; Sql2000 = $sql2000 } }
} $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM. Edits: Test-Bound -ParameterName FileGroup -> the carried
    // $__boundFileGroup flag, and -FunctionName Get-DbaDbFile on the Stop-Function and three Write-Message.
    // The five constant query strings are restored read-only from the carried state.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $FileGroup, $InputObject, $EnableException, $__state, $__boundFileGroup, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, [object[]]$FileGroup, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__state, $__boundFileGroup, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $sql = $__state.Sql
    $sqlfrom = $__state.SqlFrom
    $sql2008 = $__state.Sql2008
    $sql2008from = $__state.Sql2008From
    $sql2000 = $__state.Sql2000

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            Write-Message -Level Verbose -Message "Querying database $db" -FunctionName Get-DbaDbFile -ModuleName "dbatools"

            try {
                $version = $server.Query("SELECT compatibility_level FROM sys.databases WHERE name = '$($db.Name)'")
                $version = [int]($version.compatibility_level / 10)
            } catch {
                $version = 8
            }

            if ($version -ge 11) {
                $query = ($sql, $sql2008, $sqlfrom, $sql2008from) -Join "`n"
            } elseif ($version -ge 9) {
                $query = ($sql, $sqlfrom) -Join "`n"
            } else {
                $query = $sql2000
            }

            Write-Message -Level Debug -Message "SQL Statement: $query" -FunctionName Get-DbaDbFile -ModuleName "dbatools"

            try {
                $results = $server.Query($query, $db.Name)
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Get-DbaDbFile
            }

            if ($__boundFileGroup) {
                Write-Message -Message "Results will be filtered to FileGroup specified" -Level Verbose -FunctionName Get-DbaDbFile -ModuleName "dbatools"
                $results = $results | Where-Object { $_.FileGroupName -eq $FileGroup }
            }

            foreach ($result in $results) {
                $size = [dbasize]($result.Size * 8192)
                $usedspace = [dbasize]($result.UsedSpace * 8192)
                $maxsize = $result.MaxSize
                # calculation is done here because for snapshots or sparse files size is not the "virtual" size
                # (master_files.Size) but the currently allocated one (dm_io_virtual_file_stats.size_on_disk_bytes)
                $AvailableSpace = $size - $usedspace
                if ($result.size_on_disk_bytes) {
                    $size = [dbasize]($result.size_on_disk_bytes)
                }
                if ($maxsize -gt -1) {
                    $maxsize = [dbasize]($result.MaxSize * 8192)
                } else {
                    $maxsize = [dbasize]($result.MaxSize)
                }

                if ($result.VolumeFreeSpace) {
                    $VolumeFreeSpace = [dbasize]$result.VolumeFreeSpace
                } else {
                    # to get drive free space for each drive that a database has files on
                    # when database compatibility lower than 110. Lets do this with query2
                    $query2 = @'
-- to get drive free space for each drive that a database has files on
DECLARE @FixedDrives TABLE(Drive CHAR(1), MB_Free BIGINT);
INSERT @FixedDrives EXEC sys.xp_fixeddrives;

SELECT DISTINCT fd.MB_Free, LEFT(df.physical_name, 1) AS [Drive]
FROM @FixedDrives AS fd
INNER JOIN sys.database_files AS df
ON fd.Drive = LEFT(df.physical_name, 1);
'@
                    # if the server has one drive xp_fixeddrives returns one row, but we still need $disks to be an array.
                    if ($server.VersionMajor -gt 8) {
                        $disks = @($server.Query($query2, $db.Name))
                        $MbFreeColName = $disks[0].psobject.Properties.Name
                        # get the free MB value for the drive in question
                        $free = $disks | Where-Object {
                            $_.drive -eq $result.PhysicalName.Substring(0, 1)
                        } | Select-Object $MbFreeColName

                    $VolumeFreeSpace = [dbasize](($free.MB_Free) * 1024 * 1024)
                }
            }
            if ($result.GrowthType -eq "Percent") {
                $nextgrowtheventadd = [dbasize]($result.size * 8 * ($result.Growth * 0.01) * 1024)
            } else {
                $nextgrowtheventadd = [dbasize]($result.Growth * 1024)
            }
            if (($nextgrowtheventadd.Byte -gt ($MaxSize.Byte - $size.Byte)) -and $maxsize -gt 0) {
                [dbasize]$nextgrowtheventadd = 0
            }

            [PSCustomObject]@{
                ComputerName             = $server.ComputerName
                InstanceName             = $server.ServiceName
                SqlInstance              = $server.DomainInstanceName
                Database                 = $db.name
                DatabaseID               = $db.ID
                FileGroupName            = $result.FileGroupName
                ID                       = $result.ID
                Type                     = $result.Type
                TypeDescription          = $result.TypeDescription
                LogicalName              = $result.LogicalName.Trim()
                PhysicalName             = $result.PhysicalName.Trim()
                State                    = $result.State
                MaxSize                  = $maxsize
                Growth                   = $result.Growth
                GrowthType               = $result.GrowthType
                NextGrowthEventSize      = $nextgrowtheventadd
                Size                     = $size
                UsedSpace                = $usedspace
                AvailableSpace           = $AvailableSpace
                IsOffline                = $result.IsOffline
                IsReadOnly               = $result.IsReadOnly
                IsReadOnlyMedia          = $result.IsReadOnlyMedia
                IsSparse                 = $result.IsSparse
                NumberOfDiskWrites       = $result.NumberOfDiskWrites
                NumberOfDiskReads        = $result.NumberOfDiskReads
                ReadFromDisk             = [dbasize]$result.BytesReadFromDisk
                WrittenToDisk            = [dbasize]$result.BytesWrittenToDisk
                VolumeFreeSpace          = $VolumeFreeSpace
                FileGroupDataSpaceId     = $result.FileGroupDataSpaceId
                FileGroupType            = $result.FileGroupType
                FileGroupTypeDescription = $result.FileGroupTypeDescription
                FileGroupDefault         = $result.FileGroupDefault
                FileGroupReadOnly        = $result.FileGroupReadOnly
            }
        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $FileGroup $InputObject $EnableException $__state $__boundFileGroup $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
