function Get-DbaFile {
    <#
    .SYNOPSIS
        Get-DbaFile finds files in any directory specified on a remote SQL Server

    .DESCRIPTION
        This command searches all specified directories, allowing a DBA to see file information on a server without direct access

        You can filter by extension using the -FileType parameter. By default, the default data directory will be returned. You can provide and additional paths to search using the -Path parameter.

        Thanks to serg-52 for the query:  https://www.sqlservercentral.com/Forums/Topic1642213-391-1.aspx

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Allows you to login to servers using alternative credentials

    .PARAMETER Path
        Used to specify extra directories to search in addition to the default data directory.

    .PARAMETER FileType
        Used to specify filter by filetype. No dot required, just pass the extension.

    .PARAMETER Depth
        Used to specify recursive folder depth.  Default is 1, non-recursive.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Discovery
        Author: Brandon Abshire, netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaFile

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

            $q1 += "DECLARE @myPath nvarchar(4000);
                    DECLARE @depth SMALLINT = $Depth;

                    IF OBJECT_ID('tempdb..#DirectoryTree') IS NOT NULL
                    DROP TABLE #DirectoryTree;

                    CREATE TABLE #DirectoryTree (
                       id int IDENTITY(1,1)
                       ,subdirectory nvarchar(512)
                       ,depth int
                       ,isfile bit
                       , ParentDirectory int
                       ,flag tinyint default(0));"

            $q2 = "SET @myPath = 'dirname'
                    -- top level directory
                    INSERT #DirectoryTree (subdirectory,depth,isfile)
                       VALUES (@myPath,0,0);
                    -- all the rest under top level
                    INSERT #DirectoryTree (subdirectory,depth,isfile)
                       EXEC master.sys.xp_dirtree @myPath,@depth,1;


                    UPDATE #DirectoryTree
                       SET ParentDirectory = (
                          SELECT MAX(Id) FROM #DirectoryTree
                          WHERE Depth = d.Depth - 1 AND Id < d.Id   )
                    FROM #DirectoryTree d
                    WHERE ParentDirectory is NULL;"

            $query_files_sql = "-- SEE all with full paths
                    WITH dirs AS (
                        SELECT
                           Id,subdirectory,depth,isfile,ParentDirectory,flag
                           , CAST (null AS NVARCHAR(MAX)) AS container
                           , CAST([subdirectory] AS NVARCHAR(MAX)) AS dpath
                           FROM #DirectoryTree
                           WHERE ParentDirectory IS NULL
                        UNION ALL
                        SELECT
                           d.Id,d.subdirectory,d.depth,d.isfile,d.ParentDirectory,d.flag
                           , dpath as container
                           , dpath +'\'+d.[subdirectory]
                        FROM #DirectoryTree AS d
                        INNER JOIN dirs ON  d.ParentDirectory = dirs.id
                        WHERE dpath NOT LIKE '%RECYCLE.BIN%'
                    )
                    SELECT subdirectory as filename, container as filepath, isfile, dpath as fullpath FROM dirs
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

            #Variable marked as unused by PSScriptAnalyzer
            #$paths = @()
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Get the default data and log directories from the instance
            if (-not (Test-Bound -ParameterName Path)) { $Path = (Get-DbaDefaultPath -SqlInstance $server).Data }

            Write-Message -Level Verbose -Message "Adding paths"
            $sql = Get-SQLDirTreeQuery $Path
            Write-Message -Level Debug -Message $sql

            # This should remain as not .Query() to be compat with a PSProvider Chrissy is working on
            $datatable = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows

            Write-Message -Level Verbose -Message "$($datatable.Rows.Count) files found."
            if ($FileTypeComparison) {
                foreach ($row in $datatable) {
                    foreach ($type in $FileTypeComparison) {
                        if ($row.filename.ToLowerInvariant().EndsWith(".$type")) {
                            [pscustomobject]@{
                                ComputerName   = $server.ComputerName
                                InstanceName   = $server.ServiceName
                                SqlInstance    = $server.DomainInstanceName
                                Filename       = $row.fullpath
                                RemoteFilename = Join-AdminUnc -Servername $server.ComputerName -Filepath $row.fullpath
                            } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName, RemoteFilename
                        }
                    }
                }
            } else {
                foreach ($row in $datatable) {
                    [pscustomobject]@{
                        ComputerName   = $server.ComputerName
                        InstanceName   = $server.ServiceName
                        SqlInstance    = $server.DomainInstanceName
                        Filename       = $row.fullpath
                        RemoteFilename = Join-AdminUnc -Servername $server.ComputerName -Filepath $row.fullpath
                    } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName, RemoteFilename
                }
            }
        }
    }
}