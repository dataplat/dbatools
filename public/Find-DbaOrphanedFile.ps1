function Find-DbaOrphanedFile {
    <#
    .SYNOPSIS
        Identifies database files on disk that are not attached to any SQL Server database instance

    .DESCRIPTION
        Scans filesystem directories for database files (.mdf, .ldf, .ndf) that exist on disk but are not currently attached to the SQL Server instance. This is essential for cleanup operations after database drops, detaches, or failed restores that leave behind orphaned files consuming disk space.

        The command compares files found via xp_dirtree against sys.master_files to identify true orphans. By default, it searches the root\data directory, default data and log paths, system paths, and any directory currently used by attached databases.

        Perfect for storage cleanup scenarios where you need to reclaim disk space by identifying leftover database files that can be safely removed. You can specify additional file types using -FileType and additional search paths using -Path parameter.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Specifies additional directories to search beyond the default SQL Server data and log paths. Use this when databases were stored in non-standard locations or when you suspect orphaned files exist in custom backup/restore directories. Accepts multiple paths and searches them alongside the automatically detected SQL Server directories.

    .PARAMETER FileType
        Specifies additional file extensions to search for beyond the default database file types (mdf, ldf, ndf). Use this to find orphaned Full-Text catalog files (ftcat), backup files (bak, trn), or other SQL Server-related files. Do not include the dot when specifying extensions (use "bak" not ".bak").

    .PARAMETER LocalOnly
        Returns only the local file paths without server or UNC information. Use this when you need simple file paths for scripting file removal operations or when working with a single server. Not recommended for multi-server environments since it omits which server the file belongs to.

    .PARAMETER RemoteOnly
        Returns only the UNC network paths to orphaned files. Use this when you need to access files remotely for cleanup operations or when building scripts that run from a central management server. Provides the \\server\share\path format needed for remote file operations.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Recurse
        Searches all subdirectories within the specified paths in addition to the root directories. Use this when database files may be organized in nested folder structures or when conducting comprehensive cleanup of complex directory hierarchies. Without this switch, only the immediate directories are searched.

    .NOTES
        Tags: Orphan, Database, DatabaseFile, Lookup
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

        Thanks to Paul Randal's notes on FILESTREAM which can be found at http://www.sqlskills.com/blogs/paul/filestream-directory-structure/

    .LINK
        https://dbatools.io/Find-DbaOrphanedFile

    .OUTPUTS
        System.String (when -LocalOnly is specified)

        Returns the local file path to each orphaned file.

        System.String (when -RemoteOnly is specified)

        Returns the UNC path to each orphaned file.

        PSCustomObject (default)

        Returns one object per orphaned file found with the following properties:

        - ComputerName: The name of the computer where the SQL Server instance is running
        - InstanceName: The name of the SQL Server instance
        - SqlInstance: The full SQL Server instance name in the format ComputerName\InstanceName
        - Server: The server name (same as ComputerName for most instances)
        - Filename: The local file path to the orphaned file
        - RemoteFilename: The UNC network path to the orphaned file (\\ComputerName\share\path format)

    .EXAMPLE
        PS C:\> Find-DbaOrphanedFile -SqlInstance sqlserver2014a

        Connects to sqlserver2014a, authenticating with Windows credentials, and searches for orphaned files. Returns server name, local filename, and unc path to file.

    .EXAMPLE
        PS C:\> Find-DbaOrphanedFile -SqlInstance sqlserver2014a -SqlCredential $cred

        Connects to sqlserver2014a, authenticating with SQL Server authentication, and searches for orphaned files. Returns server name, local filename, and unc path to file.

    .EXAMPLE
        PS C:\> Find-DbaOrphanedFile -SqlInstance sql2014 -Path 'E:\Dir1', 'E:\Dir2'

        Finds the orphaned files in "E:\Dir1" and "E:Dir2" in addition to the default directories.

    .EXAMPLE
        PS C:\> Find-DbaOrphanedFile -SqlInstance sql2014 -Path 'E:\Dir1' -Recurse

        Finds the orphaned files in "E:\Dir1" and any of its subdirectories in addition to the default directories.

    .EXAMPLE
        PS C:\> Find-DbaOrphanedFile -SqlInstance sql2014 -LocalOnly

        Returns only the local file paths for orphaned files.

    .EXAMPLE
        PS C:\> Find-DbaOrphanedFile -SqlInstance sql2014 -RemoteOnly

        Returns only the remote file path for orphaned files.

    .EXAMPLE
        PS C:\> Find-DbaOrphanedFile -SqlInstance sql2014, sql2016 -FileType fsf, mld

        Finds the orphaned ending with ".fsf" and ".mld" in addition to the default filetypes ".mdf", ".ldf", ".ndf" for both the servers sql2014 and sql2016.
    #>

    [CmdletBinding(DefaultParameterSetName = 'LocalOnly')]

    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Path,
        [string[]]$FileType,
        [Parameter(ParameterSetName = 'LocalOnly')][switch]$LocalOnly,
        [Parameter(ParameterSetName = 'RemoteOnly')][switch]$RemoteOnly,
        [switch]$EnableException,
        [switch]$Recurse
    )

    begin {
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

        $systemfiles = "distmdl.ldf", "distmdl.mdf", "mssqlsystemresource.ldf", "mssqlsystemresource.mdf", "model_msdbdata.mdf", "model_msdblog.ldf", "model_replicatedmaster.mdf", "model_replicatedmaster.ldf"

        $FileType += "mdf", "ldf", "ndf"
        $fileTypeComparison = $FileType | ForEach-Object { $_.ToLowerInvariant() } | Where-Object { $_ } | Sort-Object -Unique
    }

    process {
        foreach ($instance in $SqlInstance) {

            # Connect to the instance
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
            Write-Message -Level Debug -Message "Adding paths"
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
    }
    end {
        if ($result.count -eq 0) {
            Write-Message -Level Verbose -Message "No orphaned files found"
        }
    }
}