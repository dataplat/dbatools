function Find-DbaOrphanedFile {
    <#
    .SYNOPSIS
        Find-DbaOrphanedFile finds orphaned database files. Orphaned database files are files not associated with any attached database.

    .DESCRIPTION
        This command searches all directories associated with SQL database files for database files that are not currently in use by the SQL Server instance.

        By default, it looks for orphaned .mdf, .ldf and .ndf files in the root\data directory, the default data path, the default log path, the system paths and any directory in use by any attached directory.

        You can specify additional filetypes using the -FileType parameter, and additional paths to search using the -Path parameter.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Specifies one or more directories to search in addition to the default data and log directories.

    .PARAMETER FileType
        Specifies file extensions other than mdf, ldf and ndf to search for. Do not include the dot (".") when specifying the extension.

    .PARAMETER LocalOnly
        If this switch is enabled, only local filenames will be returned. Using this switch with multiple servers is not recommended since it does not return the associated server name.

    .PARAMETER RemoteOnly
        If this switch is enabled, only remote filenames will be returned.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Recurse
        If this switch is enabled, the command will search subdirectories of the Path parameter.

    .NOTES
        Tags: Orphan, Database, DatabaseFile
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

        Thanks to Paul Randal's notes on FILESTREAM which can be found at http://www.sqlskills.com/blogs/paul/filestream-directory-structure/

    .LINK
        https://dbatools.io/Find-DbaOrphanedFile

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
        [pscredential]$SqlCredential,
        [string[]]$Path,
        [string[]]$FileType,
        [Parameter(ParameterSetName = 'LocalOnly')][switch]$LocalOnly,
        [Parameter(ParameterSetName = 'RemoteOnly')][switch]$RemoteOnly,
        [switch]$EnableException,
        [switch]$Recurse
    )

    begin {
        function Get-SQLDirTreeQuery {
            param([object[]]$SqlPathList, [object[]]$UserPathList, $FileTypes, $SystemFiles, [Switch]$Recurse)

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
                fs_filename = ltrim(rtrim(e.fs_filename)),
                parent_id = (SELECT MAX(i.id) FROM #enum i WHERE i.id < e.id AND i.depth = e.depth-1 AND i.is_file = 0)
                FROM #enum e
                WHERE e.parent IS NULL;
                "

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

            # build the query string based on how many directories they want to enumerate
            $sql = $q1
            $sql += $($SqlPathList | Where-Object { $_ -ne '' } | ForEach-Object { "$([System.Environment]::Newline)$($q2.Replace('dirname',$_).Replace('recurse','1'))" } )
            If ($UserPathList) {
                $recurseVal = If ($Recurse) { '0' } Else { '1' }
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
                $sql = "select filename from sysaltfiles"
            } else {
                $sql = "select physical_name as filename from sys.master_files"
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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
            $sql = Get-SQLDirTreeQuery -SqlPathList $sqlpaths -UserPathList $userpaths -FileTypes $fileTypeComparison -SystemFiles $systemfiles -Recurse:$Recurse
            $dirtreefiles = $server.Databases['master'].ExecuteWithResults($sql).Tables[0] | ForEach-Object {
                $fullpath = [IO.Path]::combine($_.parent, $_.filename)
                [PSCustomObject]@{
                    FullPath   = $fullpath
                    Comparison = [IO.Path]::GetFullPath($(Format-Path $fullpath))
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

                    if ($filename -in $systemfiles) { continue }

                    $result = [pscustomobject]@{
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