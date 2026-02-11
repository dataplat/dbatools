function Get-DbaFile {
    <#
    .SYNOPSIS
        Enumerates files and directories on remote SQL Server instances using xp_dirtree

    .DESCRIPTION
        Searches directories on SQL Server machines remotely without requiring direct file system access or RDP connections. Uses the xp_dirtree extended stored procedure to return file listings that can be filtered by extension and searched recursively to specified depths. Defaults to the instance's data directory but accepts additional paths for comprehensive file system exploration.

        Common use cases include locating orphaned database files, finding backup files for restores, auditing disk usage, and preparing for file migrations.

        You can filter by extension using the -FileType parameter. By default, the default data directory will be returned. You can provide and additional paths to search using the -Path parameter.

        Thanks to serg-52 for the query:  https://www.sqlservercentral.com/Forums/Topic1642213-391-1.aspx

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Allows you to login to servers using alternative credentials

    .PARAMETER Path
        Specifies additional directory paths to search beyond the instance's default data directory. Accepts multiple paths as an array.
        Use this when you need to scan specific locations for orphaned files, backup locations, or custom database file directories.
        Defaults to the instance's data directory if not specified.

    .PARAMETER FileType
        Filters results to only show files with specific extensions. Pass extensions without the dot (e.g., 'mdf', 'ldf', 'bak').
        Use this to find specific database files like data files (mdf, ndf), log files (ldf), or backup files (bak, trn).
        Accepts multiple extensions to search for different file types simultaneously.

    .PARAMETER Depth
        Controls how many subdirectory levels to search recursively. Default is 1 (current directory only).
        Increase this value when searching deep folder structures for scattered database files or backup archives.
        Higher values take more time but ensure comprehensive file discovery across complex directory trees.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, File, Path
        Author: Brandon Abshire, netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaFile

    .OUTPUTS
        PSCustomObject

        Returns one object per file found in the specified directories across all target instances.

        Default display properties (via Select-DefaultView -ExcludeProperty):
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Filename: The full path of the file on the target server (with path separators adapted for the host OS)

        Additional properties available (via Select-Object *):
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - RemoteFilename: The UNC path to the file for remote access (\\ComputerName\share\path)

    .EXAMPLE
        PS C:\> Get-DbaFile -SqlInstance sqlserver2014a -Path E:\Dir1

        Logs into the SQL Server "sqlserver2014a" using Windows credentials and searches E:\Dir for all files

    .EXAMPLE
        PS C:\> Get-DbaFile -SqlInstance sqlserver2014a -SqlCredential $cred -Path 'E:\sql files'

        Logs into the SQL Server "sqlserver2014a" using alternative credentials and returns all files in 'E:\sql files'

    .EXAMPLE
        PS C:\> $all = Get-DbaDefaultPath -SqlInstance sql2014
        PS C:\> Get-DbaFile -SqlInstance sql2014 -Path $all.Data, $all.Log, $all.Backup -Depth 3

        Returns the files in the default data, log and backup directories on sql2014, 3 directories deep (recursively).

    .EXAMPLE
        PS C:\> Get-DbaFile -SqlInstance sql2014 -Path 'E:\Dir1', 'E:\Dir2'

        Returns the files in "E:\Dir1" and "E:Dir2" on sql2014

    .EXAMPLE
        PS C:\> Get-DbaFile -SqlInstance sql2014, sql2016 -Path 'E:\Dir1' -FileType fsf, mld

        Finds files in E:\Dir1 ending with ".fsf" and ".mld" for both the servers sql2014 and sql2016.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Path,
        [string[]]$FileType,
        [int]$Depth = 1,
        [switch]$EnableException
    )
    begin {
        $sql = ""

        function Get-SQLDirTreeQuery {
            param
            (
                $PathList
            )

            $q1 += "DECLARE @myPath NVARCHAR(4000);
                    DECLARE @depth SMALLINT = $Depth;

                    IF OBJECT_ID('tempdb..#DirectoryTree') IS NOT NULL
                    DROP TABLE #DirectoryTree;

                    CREATE TABLE #DirectoryTree (
                       id INT IDENTITY(1,1)
                       ,subdirectory NVARCHAR(512)
                       ,depth INT
                       ,isfile BIT
                       , ParentDirectory INT
                       ,flag TINYINT DEFAULT(0));"

            $q2 = "SET @myPath = 'dirname'
                    -- top level directory
                    INSERT #DirectoryTree (subdirectory,depth,isfile)
                       VALUES (@myPath,0,0);
                    -- all the rest under top level
                    INSERT #DirectoryTree (subdirectory,depth,isfile)
                       EXEC master.sys.xp_dirtree @myPath,@depth,1;


                    UPDATE #DirectoryTree
                       SET ParentDirectory = (
                          SELECT MAX(id) FROM #DirectoryTree
                          WHERE depth = d.depth - 1 AND id < d.id   )
                    FROM #DirectoryTree d
                    WHERE ParentDirectory IS NULL;"

            $query_files_sql = "-- SEE all with full paths
                    WITH dirs AS (
                        SELECT
                           id,subdirectory,depth,isfile,ParentDirectory,flag
                           , CAST (NULL AS NVARCHAR(MAX)) AS container
                           , CAST([subdirectory] AS NVARCHAR(MAX)) AS dpath
                           FROM #DirectoryTree
                           WHERE ParentDirectory IS NULL
                        UNION ALL
                        SELECT
                           d.id,d.subdirectory,d.depth,d.isfile,d.ParentDirectory,d.flag
                           , dpath AS container
                           , dpath +'\'+d.[subdirectory]
                        FROM #DirectoryTree AS d
                        INNER JOIN dirs ON  d.ParentDirectory = dirs.id
                        WHERE dpath NOT LIKE '%RECYCLE.BIN%'
                    )
                    SELECT subdirectory AS filename, container AS filepath, isfile, dpath AS fullpath FROM dirs
                    WHERE container IS NOT NULL
                    -- Dir style ordering
                    ORDER BY container, isfile, subdirectory"

            # build the query string based on how many directories they want to enumerate
            $sql = $q1
            $sql += $($PathList | Where-Object { $_ -ne '' } | ForEach-Object { "$([System.Environment]::Newline)$($q2 -Replace 'dirname', $_)" })
            $sql += $query_files_sql
            #Write-Message -Level Debug -Message $sql
            return $sql
        }

        function Format-Path {
            param ($path)
            $path = $path.Trim()
            #Thank you windows 2000
            $path = $path -replace '[^A-Za-z0-9 _\.\-\\:]', '__'
            return $path
        }

        if ($FileType) {
            $FileTypeComparison = $FileType | ForEach-Object { $_.ToLowerInvariant() } | Where-Object { $_ } | Sort-Object | Get-Unique
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Get the default data and log directories from the instance
            if (-not (Test-Bound -ParameterName Path)) {
                $Path = (Get-DbaDefaultPath -SqlInstance $server).Data
            }
            if (Test-HostOSLinux -SqlInstance $server) {
                $separator = "/"
            } else {
                $separator = "\"
            }

            Write-Message -Level Verbose -Message "Adding paths"
            $sql = Get-SQLDirTreeQuery $Path
            Write-Message -Level Debug -Message $sql

            # This should remain as not .Query() to be compat with a PSProvider Chrissy was working on
            $datatable = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows

            Write-Message -Level Verbose -Message "$($datatable.Rows.Count) files found."
            if ($FileTypeComparison) {
                foreach ($row in $datatable) {
                    foreach ($type in $FileTypeComparison) {
                        if ($row.filename.ToLowerInvariant().EndsWith(".$type")) {
                            $fullpath = $row.fullpath.Replace("\", $separator)

                            # Replacing all instances of '\\' with single backslashes '\', and maintain the leading SMB share path represented by the initial '\\'.
                            $is_smb_share_path = $fullpath.SubString(0, 2) -eq "\\"
                            $fullpath = $fullpath.Replace("\\", "\")
                            if ($is_smb_share_path) {
                                $fullpath = $fullpath -replace "^\\", "\\"
                            }

                            $fullpath = $fullpath.Replace("//", "/")
                            [PSCustomObject]@{
                                ComputerName   = $server.ComputerName
                                InstanceName   = $server.ServiceName
                                SqlInstance    = $server.DomainInstanceName
                                Filename       = $fullpath
                                RemoteFilename = Join-AdminUnc -Servername $server.ComputerName -Filepath $fullpath
                            } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName, RemoteFilename
                        }
                    }
                }
            } else {
                foreach ($row in $datatable) {
                    $fullpath = $row.fullpath
                    $fullpath = $fullpath.Replace("\", $separator)
                    $fullpath = $fullpath.Replace("\\", "\")
                    $fullpath = $fullpath.Replace("//", "/")
                    [PSCustomObject]@{
                        ComputerName   = $server.ComputerName
                        InstanceName   = $server.ServiceName
                        SqlInstance    = $server.DomainInstanceName
                        Filename       = $fullpath
                        RemoteFilename = Join-AdminUnc -Servername $server.ComputerName -Filepath $fullpath
                    } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName, RemoteFilename
                }
            }
        }
    }
}