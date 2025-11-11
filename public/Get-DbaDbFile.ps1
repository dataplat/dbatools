function Get-DbaDbFile {
    <#
    .SYNOPSIS
        Retrieves comprehensive database file information including size, growth, I/O statistics, and storage details.

    .DESCRIPTION
        Retrieves detailed information about database files (data and log files) from SQL Server instances using direct T-SQL queries for optimal performance. This function provides comprehensive file metadata including current size, used space, growth settings, I/O statistics, and volume free space information that DBAs need for capacity planning, performance analysis, and storage management. Unlike SMO-based approaches, this command avoids costly enumeration operations and provides faster results when analyzing file configurations across multiple databases.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for file information. Accepts wildcards for pattern matching.
        Use this when you need to focus on specific databases rather than scanning all databases on the instance.
        Particularly useful for capacity planning or troubleshooting file growth issues on targeted databases.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the file analysis. Accepts wildcards for pattern matching.
        Use this to skip system databases, test databases, or databases you don't need to analyze.
        Helpful when performing routine file space reviews while avoiding databases that don't require monitoring.

    .PARAMETER FileGroup
        Filters results to show only files within the specified filegroup name.
        Use this when analyzing specific filegroups for space utilization, I/O patterns, or growth planning.
        Particularly valuable when troubleshooting performance issues or planning filegroup-specific storage migrations.

    .PARAMETER InputObject
        Accepts database objects piped from other dbatools commands like Get-DbaDatabase.
        Use this for advanced filtering scenarios or when chaining multiple dbatools commands together.
        Allows you to pre-filter databases using complex criteria before analyzing their file information.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Data, File, Log
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbFile

    .EXAMPLE
        PS C:\> Get-DbaDbFile -SqlInstance sql2016

        Will return an object containing all file groups and their contained files for every database on the sql2016 SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaDbFile -SqlInstance sql2016 -Database Impromptu

        Will return an object containing all file groups and their contained files for the Impromptu Database on the sql2016 SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaDbFile -SqlInstance sql2016 -Database Impromptu, Trading

        Will return an object containing all file groups and their contained files for the Impromptu and Trading databases on the sql2016 SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database Impromptu, Trading | Get-DbaDbFile

        Will accept piped input from Get-DbaDatabase and return an object containing all file groups and their contained files for the Impromptu and Trading databases on the sql2016 SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaDbFile -SqlInstance sql2016 -Database AdventureWorks2017 -FileGroup Index

        Return any files that are in the Index filegroup of the AdventureWorks2017 database.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [object[]]$FileGroup,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
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
    }

    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            Write-Message -Level Verbose -Message "Querying database $db"

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

            Write-Message -Level Debug -Message "SQL Statement: $query"

            try {
                $results = $server.Query($query, $db.Name)
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }

            if (Test-Bound -ParameterName FileGroup) {
                Write-Message -Message "Results will be filtered to FileGroup specified" -Level Verbose
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
}
}