#ValidationTags#FlowControl,Pipeline#
function Find-DbaOrphanedFile {
    <#
        .SYNOPSIS
            Find-DbaOrphanedFile finds orphaned database files. Orphaned database files are files not associated with any attached database.

        .DESCRIPTION
            This command searches all directories associated with SQL database files for database files that are not currently in use by the SQL Server instance.

            By default, it looks for orphaned .mdf, .ldf and .ndf files in the root\data directory, the default data path, the default log path, the system paths and any directory in use by any attached directory.

            You can specify additional filetypes using the -FileType parameter, and additional paths to search using the -Path parameter.

        .PARAMETER SqlInstance
            The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $cred = Get-Credential, then pass this $cred to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

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

        .NOTES
            Tags: DisasterRecovery, Orphan
            Author: Sander Stad (@sqlstad), sqlstad.nl
            Requires: sysadmin access on SQL Servers

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

            Thanks to Paul Randal's notes on FILESTREAM which can be found at http://www.sqlskills.com/blogs/paul/filestream-directory-structure/

        .LINK
            https://dbatools.io/Find-DbaOrphanedFile

        .EXAMPLE
            Find-DbaOrphanedFile -SqlInstance sqlserver2014a

            Connects to sqlserver2014a, authenticating with Windows credentials, and searches for orphaned files. Returns server name, local filename, and unc path to file.

        .EXAMPLE
            Find-DbaOrphanedFile -SqlInstance sqlserver2014a -SqlCredential $cred

            Connects to sqlserver2014a, authenticating with SQL Server authentication, and searches for orphaned files. Returns server name, local filename, and unc path to file.

        .EXAMPLE
            Find-DbaOrphanedFile -SqlInstance sql2014 -Path 'E:\Dir1', 'E:\Dir2'

            Finds the orphaned files in "E:\Dir1" and "E:Dir2" in addition to the default directories.

        .EXAMPLE
            Find-DbaOrphanedFile -SqlInstance sql2014 -LocalOnly

            Returns only the local filepaths for orphaned files.

        .EXAMPLE
            Find-DbaOrphanedFile -SqlInstance sql2014 -RemoteOnly

            Returns only the remote filepath for orphaned files.

        .EXAMPLE
            Find-DbaOrphanedFile -SqlInstance sql2014, sql2016 -FileType fsf, mld

            Finds the orphaned ending with ".fsf" and ".mld" in addition to the default filetypes ".mdf", ".ldf", ".ndf" for both the servers sql2014 and sql2016.

    #>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [parameter(Mandatory = $false)]
        [object]$SqlCredential,
        [parameter(Mandatory = $false)]
        [string[]]$Path,
        [string[]]$FileType,
        [switch]$LocalOnly,
        [switch]$RemoteOnly,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        function Get-SQLDirTreeQuery {
            param($PathList)
            # use sysaltfiles in lower versions

            $q1 = "CREATE TABLE #enum ( id int IDENTITY, fs_filename nvarchar(512), depth int, is_file int, parent nvarchar(512) ); DECLARE @dir nvarchar(512);"
            $q2 = "SET @dir = 'dirname';

                INSERT INTO #enum( fs_filename, depth, is_file )
                EXEC xp_dirtree @dir, 1, 1;

                UPDATE #enum
                SET parent = @dir,
                fs_filename = ltrim(rtrim(fs_filename))
                WHERE parent IS NULL;"

            $query_files_sql = "SELECT e.fs_filename AS filename, e.parent
                    FROM #enum AS e
                    WHERE e.fs_filename NOT IN( 'xtp', '5', '`$FSLOG', '`$HKv2', 'filestream.hdr' )
                    AND is_file = 1;"

            # build the query string based on how many directories they want to enumerate
            $sql = $q1
            $sql += $($PathList | Where-Object { $_ -ne '' } | ForEach-Object { "$([System.Environment]::Newline)$($q2 -Replace 'dirname', $_)" })
            $sql += $query_files_sql
            Write-Message -Level Debug -Message $sql
            return $sql
        }
        function Get-SqlFileStructure {
            param
            (
                [Parameter(Mandatory = $true, Position = 1)]
                [Microsoft.SqlServer.Management.Smo.SqlSmoObject]$smoserver
            )
            if ($smoserver.versionMajor -eq 8) {
                $sql = "select filename from sysaltfiles"
            }
            else {
                $sql = "select physical_name as filename from sys.master_files"
            }

            $dbfiletable = $smoserver.ConnectionContext.ExecuteWithResults($sql)
            $ftfiletable = $dbfiletable.Tables[0].Clone()
            $dbfiletable.Tables[0].TableName = "data"

            # Add support for Full Text Catalogs in Sql Server 2005 and below
            if ($server.VersionMajor -lt 10) {
                $databaselist = $smoserver.Databases | Select-Object -property  Name, IsFullTextEnabled
                foreach ($db in $databaselist) {
                    if ($db.IsFullTextEnabled -eq $false) {
                        continue
                    }
                    $database = $db.name
                    $fttable = $null = $smoserver.Databases[$database].ExecuteWithResults('sp_help_fulltext_catalogs')
                    foreach ($ftc in $fttable.Tables[0].rows) {
                        $null = $ftfiletable.Rows.add($ftc.Path)
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

        $FileType += "mdf", "ldf", "ndf"
        $systemfiles = "distmdl.ldf", "distmdl.mdf", "mssqlsystemresource.ldf", "mssqlsystemresource.mdf"

        $FileTypeComparison = $FileType | ForEach-Object {$_.ToLower()} | Where-Object { $_ } | Sort-Object | Get-Unique
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            # Reset all the arrays
            $dirtreefiles = $valid = $paths = $matching = @()

            $filestructure = Get-SqlFileStructure $server

            # Get any paths associated with current data and log files
            foreach ($file in $filestructure) {
                $paths += Split-Path -Path $file -Parent
            }

            # Get the default data and log directories from the instance
            Write-Message -Level Debug -Message "Adding paths"
            $paths += $server.RootDirectory + "\DATA"
            $paths += Get-SqlDefaultPaths $server data
            $paths += Get-SqlDefaultPaths $server log
            $paths += $server.MasterDBPath
            $paths += $server.MasterDBLogPath
            $paths += $Path
            $paths = $paths | ForEach-Object { "$_".TrimEnd("\") } | Sort-Object | Get-Unique
            $sql = Get-SQLDirTreeQuery $paths
            $datatable = $server.Databases['master'].ExecuteWithResults($sql).Tables[0]

            foreach ($row in $datatable) {
                $fullpath = [IO.Path]::combine($row.parent, $row.filename)
                $dirtreefiles += [pscustomobject]@{
                    FullPath   = $fullpath
                    Comparison = [IO.Path]::GetFullPath($(Format-Path $fullpath))
                }
            }
            $dirtreefiles = $dirtreefiles | Where-Object { $_ } | Sort-Object Comparison -Unique

            foreach ($file in $filestructure) {
                $valid += [IO.Path]::GetFullPath($(Format-Path $file))
            }

            $valid = $valid | Sort-Object | Get-Unique

            foreach ($file in $dirtreefiles.Comparison) {
                foreach ($type in $FileTypeComparison) {
                    if ($file.ToLower().EndsWith($type)) {
                        $matching += $file
                        break
                    }
                }
            }

            $dirtreematcher = @{}
            foreach ($el in $dirtreefiles) {
                $dirtreematcher[$el.Comparison] = $el.Fullpath
            }

            foreach ($file in $matching) {
                if ($file -notin $valid) {
                    $fullpath = $dirtreematcher[$file]

                    $filename = Split-Path $fullpath -Leaf

                    if ($filename -in $systemfiles) { continue }

                    $result = [pscustomobject]@{
                        Server         = $server.name
                        ComputerName   = $server.NetName
                        InstanceName   = $server.ServiceName
                        SqlInstance    = $server.DomainInstanceName
                        Filename       = $fullpath
                        RemoteFilename = Join-AdminUnc -Servername $server.netname -Filepath $fullpath
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
