#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Finds files on disk under an instance's data/log paths that are not known to SQL Server (orphaned
/// mdf/ldf/ndf and user-specified types). Port of public/Find-DbaOrphanedFile.ps1; the workflow remains
/// a module-scoped PowerShell compatibility hop.
///
/// A 3-hop begin+process+end port (SqlInstance is ValueFromPipeline, so process fires per record). The
/// source begin block defines three nested helper functions (Get-SQLDirTreeQuery, Get-SqlFileStructure,
/// Format-Path) and builds one-time constants: the $systemfiles list, the $FileType += "mdf","ldf","ndf"
/// mutation, and $fileTypeComparison. The helpers take their inputs via parameters and close over NO
/// begin-only state, so they are RELOCATED into the process hop (redefined per record) since hop scopes
/// do not share function definitions across begin->process. This is behaviorally identical to the source:
/// PowerShell resolves free variables by dynamic (caller) scope, and both helper definitions are only ever
/// CALLED from process, where the relevant state lives. Note Get-SqlFileStructure has a source quirk - at
/// its full-text branch it reads the ambient $server.VersionMajor (line 297) rather than its own parameter
/// $smoserver; $server is the process-scope variable and is the same SMO object passed as $smoserver, so
/// the reference resolves the same whether the helper is defined in begin (source) or process (this port).
/// The one-time $FileType mutation and derived constants stay in BEGIN (recomputing per record would
/// re-append the extensions), carried begin->process one-way via the sentinel ($systemfiles, $fileTypeComparison).
///
/// The end block writes "No orphaned files found" when $result.count -eq 0. $result is a scalar reassigned
/// per matching file and is NOT in the per-record array reset, so in the source's shared scope it persists
/// across records ($result.count is 0 iff $result is $null iff no orphaned file was found across ALL
/// instances). So $result (or $null) is carried record-to-record and into end via the same sentinel state
/// (_state.Result), mirroring the source. Body edits: -FunctionName Find-DbaOrphanedFile on the process
/// block's Stop-Function and "Adding paths" Write-Message and the end block's Write-Message; the Write-Message
/// inside the Get-SQLDirTreeQuery helper keeps its own frame (not edited). No ShouldProcess, no early return
/// (the returns are all inside the helpers), no interrupt (the one Stop-Function is -Continue). Surface pinned
/// by migration/baselines/Find-DbaOrphanedFile.json (two parameter sets LocalOnly/RemoteOnly, no positions).
/// </summary>
[Cmdlet(VerbsCommon.Find, "DbaOrphanedFile", DefaultParameterSetName = "LocalOnly")]
public sealed class FindDbaOrphanedFileCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Additional path(s) to search for orphaned files.</summary>
    [Parameter]
    [PsStringArrayCast]
    public string[]? Path { get; set; }

    /// <summary>Additional file type(s) to consider orphaned (mdf/ldf/ndf are always included).</summary>
    [Parameter]
    [PsStringArrayCast]
    public string[]? FileType { get; set; }

    /// <summary>Return only the local file paths.</summary>
    [Parameter(ParameterSetName = "LocalOnly")]
    public SwitchParameter LocalOnly { get; set; }

    /// <summary>Return only the remote (admin UNC) file paths.</summary>
    [Parameter(ParameterSetName = "RemoteOnly")]
    public SwitchParameter RemoteOnly { get; set; }

    /// <summary>Recurse subdirectories when enumerating the filesystem.</summary>
    [Parameter]
    public SwitchParameter Recurse { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The one-time constants built in begin ($systemfiles, $fileTypeComparison) and the cross-record
    // $result, all carried in one sentinel Hashtable begin->process(xN)->end.
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__findDbaOrphanedFileBegin"))
            {
                _state = sentinel["__findDbaOrphanedFileBegin"] as Hashtable;
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
            FileType, EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__findDbaOrphanedFileProcess"))
            {
                if (sentinel["__findDbaOrphanedFileProcess"] is Hashtable state)
                {
                    _state = state["State"] as Hashtable ?? _state;
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Path, Recurse.ToBool(), LocalOnly.ToBool(), RemoteOnly.ToBool(),
            EnableException.ToBool(), _state, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
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
        }, EndScript,
            _state, EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
    // PS: the begin block's one-time constants (the $FileType += mutation and $fileTypeComparison,
    // plus $systemfiles), carried to the process hop via a sentinel. The three helper functions are
    // relocated to the process hop; begin has no Stop-Function/Write-Message.
    private const string BeginScript = """
param($FileType, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string[]]$FileType, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        $systemfiles = "distmdl.ldf", "distmdl.mdf", "mssqlsystemresource.ldf", "mssqlsystemresource.mdf", "model_msdbdata.mdf", "model_msdblog.ldf", "model_replicatedmaster.mdf", "model_replicatedmaster.ldf"

        $FileType += "mdf", "ldf", "ndf"
        $fileTypeComparison = $FileType | ForEach-Object { $_.ToLowerInvariant() } | Where-Object { $_ } | Sort-Object -Unique

    @{ __findDbaOrphanedFileBegin = @{ SystemFiles = $systemfiles; FileTypeComparison = $fileTypeComparison; Result = $null } }
} $FileType $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the three nested helper functions (relocated from begin, pure) followed by the process block.
    // Edits: -FunctionName on the direct Stop-Function and "Adding paths" Write-Message (the helper's own
    // Write-Message keeps its frame). The constants are restored from the carried state, and $result is
    // restored, updated, and re-emitted so it persists record-to-record and into end.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Path, $Recurse, $LocalOnly, $RemoteOnly, $EnableException, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Path, $Recurse, $LocalOnly, $RemoteOnly, $EnableException, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        function Get-SQLDirTreeQuery {
            param([object[]]$SqlPathList, [object[]]$UserPathList, $FileTypes, $SystemFiles, [Switch]$Recurse, $ServerMajorVersion)

            $q1 = "
                CREATE TABLE #enum (
                  id int IDENTITY
                , fs_filename nvarchar(512)
                , depth int
                , is_file int
                , parent nvarchar(512)
                , parent_id int
                );
                DECLARE @dir nvarchar(512);
                "

            $q2 = "
                SET @dir = 'dirname';

                INSERT INTO #enum( fs_filename, depth, is_file )
                EXEC xp_dirtree @dir, recurse, 1;

                UPDATE #enum
                SET parent = @dir,
                parent_id = (SELECT MAX(i.id) FROM #enum i WHERE i.id < e.id AND i.depth = e.depth-1 AND i.is_file = 0)
                FROM #enum e
                WHERE e.parent IS NULL;
                "

            if ($ServerMajorVersion -ge 9) {
                # CTEs added in SQL 2005
                $query_files_sql = "
                    ; WITH DistinctPath AS
                    (   -- paths to be used in the anchor for the recursive query below (FinalPath)
                        SELECT
                             DISTINCT
                             parent          AS parent
                        ,    0               AS depth
                        ,    NULL            AS parent_id
                        FROM
                            #enum
                    )
                    , BaseDir AS
                    (    -- dynamically assign an Id (using negative numbers to avoid any potential collision with the temp table)
                        SELECT
                            -ROW_NUMBER() OVER(ORDER BY parent)    AS Id
                        ,    parent
                        ,    depth
                        ,    parent_id
                        FROM
                            DistinctPath
                    )
                    , AdjustedBaseDir AS
                    (    -- Link the Ids for the constructed anchor rows
                        SELECT
                             e.id
                        ,    e.fs_filename
                        ,    e.depth
                        ,    e.is_file
                        ,    CASE WHEN e.parent_id IS NULL THEN b.Id ELSE e.parent_id END AS parent_id
                        FROM
                            #enum e
                        JOIN
                            BaseDir b
                                ON e.parent = b.parent
                    )
                    , Combined AS
                    (    -- combine anchor data and recursive data
                        SELECT
                             Id
                        ,    parent
                        ,    depth
                        ,    0          AS is_file
                        ,    parent_id
                        FROM
                            BaseDir
                        UNION ALL
                        SELECT
                             id
                        ,    fs_filename
                        ,    depth
                        ,    is_file
                        ,    parent_id
                        FROM
                            AdjustedBaseDir
                    )
                    , FinalPath AS
                    (    -- recursive CTE to construct the full file path
                        SELECT
                             Id
                        ,    parent                           AS fs_filename
                        ,    depth
                        ,    is_file
                        ,    parent_id
                        ,    CAST(parent AS NVARCHAR(MAX))    AS FullPath
                        FROM
                            Combined
                        WHERE
                            parent_id IS NULL
                        UNION ALL
                        SELECT
                             d.Id
                        ,    d.parent
                        ,    d.depth
                        ,    d.is_file
                        ,    d.parent_id
                        ,    FullPath + '\' + d.parent
                        FROM
                            Combined d
                        JOIN
                            FinalPath fp
                                ON d.parent_id = fp.Id
                    )
                    SELECT e.fs_filename AS filename, e.FullPath
                    FROM FinalPath AS e
                    WHERE e.fs_filename NOT IN( 'xtp', '5', '`$FSLOG', '`$HKv2', 'filestream.hdr', '" + $($SystemFiles -join "','") + "' )
                    AND CASE
                        WHEN e.fs_filename LIKE '%.%'
                        THEN REVERSE(LEFT(REVERSE(e.fs_filename), CHARINDEX('.', REVERSE(e.fs_filename)) - 1))
                        ELSE ''
                        END IN('" + $($FileTypes -join "','") + "')
                    AND e.is_file = 1
                    ;
                    "
            } else {
                $query_files_sql = "
                    SELECT e.fs_filename AS filename, e.parent
                    FROM #enum AS e
                    WHERE e.fs_filename NOT IN( 'xtp', '5', '`$FSLOG', '`$HKv2', 'filestream.hdr', '" + $($SystemFiles -join "','") + "' )
                    AND CASE
                        WHEN e.fs_filename LIKE '%.%'
                        THEN REVERSE(LEFT(REVERSE(e.fs_filename), CHARINDEX('.', REVERSE(e.fs_filename)) - 1))
                        ELSE ''
                        END IN('" + $($FileTypes -join "','") + "')
                    AND e.is_file = 1;
                    "
            }

            $recurseVal = If ($Recurse) { '0' } Else { '1' }
            # build the query string based on how many directories they want to enumerate
            $sql = $q1
            $sql += $($SqlPathList | Where-Object { $_ -ne '' } | ForEach-Object { "$([System.Environment]::Newline)$($q2.Replace('dirname',$_).Replace('recurse',$recurseVal))" } )
            If ($UserPathList) {
                $sql += $($UserPathList | Where-Object { $_ -ne '' } | ForEach-Object { "$([System.Environment]::Newline)$($q2.Replace('dirname',$_).Replace('recurse',$recurseVal))" } )
            }
            $sql += $query_files_sql
            Write-Message -Level Debug -Message $sql
            return $sql
        }

        function Get-SqlFileStructure {
            param
            (
                [Parameter(Mandatory, Position = 1)]
                [Microsoft.SqlServer.Management.Smo.SqlSmoObject]$smoserver
            )

            # use sysaltfiles in lower versions
            if ($smoserver.VersionMajor -eq 8) {
                $sql = "SELECT filename FROM sysaltfiles"
            } else {
                $sql = "SELECT physical_name AS filename FROM sys.master_files"
            }

            $dbfiletable = $smoserver.ConnectionContext.ExecuteWithResults($sql)
            $ftfiletable = $dbfiletable.Tables[0].Clone()
            $dbfiletable.Tables[0].TableName = "data"

            # Add support for Full Text Catalogs in Sql Server 2005 and below
            if ($server.VersionMajor -lt 10) {
                $databaselist = $smoserver.Databases | Select-Object -Property Name, IsFullTextEnabled
                foreach ($db in $databaselist | Where-Object IsFullTextEnabled) {
                    $database = $db.Name
                    $fttable = $null = $smoserver.Databases[$database].ExecuteWithResults('sp_help_fulltext_catalogs')
                    foreach ($ftc in $fttable.Tables[0].Rows) {
                        $null = $ftfiletable.Rows.Add($ftc.Path)
                    }
                }
            }
            $null = $dbfiletable.Tables.Add($ftfiletable)

            return $dbfiletable.Tables.Filename
        }

        function Format-Path {
            param ($path)

            $path = $path.Trim()
            #Thank you windows 2000
            $path = $path -replace '[^A-Za-z0-9 _\.\-\\:]', '__'
            return $path
        }

    $systemfiles = $__state.SystemFiles
    $fileTypeComparison = $__state.FileTypeComparison
    $result = $__state.Result

        foreach ($instance in $SqlInstance) {

            # Connect to the instance
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -FunctionName Find-DbaOrphanedFile -Continue
            }

            # Reset all the arrays
            $sqlpaths = $userpaths = $matching = $valid = @()
            $dirtreefiles = @{ }

            # Gather a list of files known to SQL Server
            $sqlfiles = Get-SqlFileStructure $server

            # Get the parent directories of those files
            $sqlfiles | ForEach-Object {
                $sqlpaths += Split-Path -Path $_ -Parent
            }

            # Include the default data and log directories from the instance
            Write-Message -Level Debug -Message "Adding paths" -FunctionName Find-DbaOrphanedFile -ModuleName "dbatools"
            $sqlpaths += "$($server.RootDirectory)\DATA"
            $sqlpaths += Get-SqlDefaultPaths $server data
            $sqlpaths += Get-SqlDefaultPaths $server log
            $sqlpaths += $server.MasterDBPath
            $sqlpaths += $server.MasterDBLogPath

            # Gather a list of files from the filesystem
            $sqlpaths = $sqlpaths | ForEach-Object { $_.TrimEnd("\") } | Sort-Object -Unique
            if ($Path) {
                $userpaths = $Path | ForEach-Object { $_.TrimEnd("\") } | Sort-Object -Unique
            }
            $sql = Get-SQLDirTreeQuery -SqlPathList $sqlpaths -UserPathList $userpaths -FileTypes $fileTypeComparison -SystemFiles $systemfiles -Recurse:$Recurse -ServerMajorVersion $server.VersionMajor
            $dirtreefiles = $server.Databases['master'].ExecuteWithResults($sql).Tables[0] | ForEach-Object {
                [PSCustomObject]@{
                    FullPath   = $_.Fullpath
                    Comparison = [IO.Path]::GetFullPath($(Format-Path $_.Fullpath))
                }
            }
            # Output files in the dirtree not known to SQL Server
            $dirtreefiles = $dirtreefiles | Where-Object { $_ } | Sort-Object Comparison -Unique

            foreach ($file in $sqlfiles) {
                $valid += [IO.Path]::GetFullPath($(Format-Path $file))
            }

            $valid = $valid | Sort-Object | Get-Unique

            foreach ($file in $dirtreefiles.Comparison) {
                foreach ($type in $FileTypeComparison) {
                    if ($file.ToLowerInvariant().EndsWith($type)) {
                        $matching += $file
                        break
                    }
                }
            }

            $dirtreematcher = @{ }
            foreach ($el in $dirtreefiles) {
                $dirtreematcher[$el.Comparison] = $el.FullPath
            }
            foreach ($file in $matching) {
                if ($file -notin $valid) {
                    $fullpath = $dirtreematcher[$file]

                    $filename = Split-Path $fullpath -Leaf
                    if ($IsLinux -or $IsMacOS) {
                        $filename = $filename.Replace('\', '/')
                    }

                    if ($filename -in $systemfiles) { continue }

                    $result = [PSCustomObject]@{
                        Server         = $server.name
                        ComputerName   = $server.ComputerName
                        InstanceName   = $server.ServiceName
                        SqlInstance    = $server.DomainInstanceName
                        Filename       = $fullpath
                        RemoteFilename = Join-AdminUnc -Servername $server.ComputerName -Filepath $fullpath
                    }

                    if ($LocalOnly -eq $true) {
                        ($result | Select-Object filename).filename
                        continue
                    }

                    if ($RemoteOnly -eq $true) {
                        ($result | Select-Object remotefilename).remotefilename
                        continue
                    }

                    $result | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Filename, RemoteFilename

                }
            }

        }

    $__state.Result = $result
    @{ __findDbaOrphanedFileProcess = @{ State = $__state } }
} $SqlInstance $SqlCredential $Path $Recurse $LocalOnly $RemoteOnly $EnableException $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the end block. Edit: -FunctionName on the Write-Message. $result is restored from the carried
    // state so its cross-record value drives the "no orphaned files" message exactly as the source scope.
    private const string EndScript = """
param($__state, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__state, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $result = $__state.Result

        if ($result.count -eq 0) {
            Write-Message -Level Verbose -Message "No orphaned files found" -FunctionName Find-DbaOrphanedFile -ModuleName "dbatools"
        }
} $__state $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
