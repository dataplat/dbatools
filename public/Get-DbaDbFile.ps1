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
        $sql = "select
            fg.name as FileGroupName,
            df.file_id as 'ID',
            df.Type,
            df.type_desc as TypeDescription,
            df.name as LogicalName,
            mf.physical_name as PhysicalName,
            df.state_desc as State,
            df.max_size as MaxSize,
            case mf.is_percent_growth when 1 then df.growth else df.Growth*8 end as Growth,
            COALESCE(fileproperty(df.name, 'spaceused'), 0) as UsedSpace,
            df.size as Size,
            COALESCE(vfs.size_on_disk_bytes, 0) as size_on_disk_bytes,
            case df.state_desc when 'OFFLINE' then 'True' else 'False' End as IsOffline,
            case mf.is_read_only when 1 then 'True' when 0 then 'False' End as IsReadOnly,
            case mf.is_media_read_only when 1 then 'True' when 0 then 'False' End as IsReadOnlyMedia,
            case mf.is_sparse when 1 then 'True' when 0 then 'False' End as IsSparse,
            case mf.is_percent_growth when 1 then 'Percent' when 0 then 'kb' End as GrowthType,
            COALESCE(vfs.num_of_writes, 0) as NumberOfDiskWrites,
            COALESCE(vfs.num_of_reads, 0) as NumberOfDiskReads,
            COALESCE(vfs.num_of_bytes_read, 0) as BytesReadFromDisk,
            COALESCE(vfs.num_of_bytes_written, 0) as BytesWrittenToDisk,
            fg.data_space_id as FileGroupDataSpaceId,
            fg.Type as FileGroupType,
            fg.type_desc as FileGroupTypeDescription,
            case fg.is_default When 1 then 'True' when 0 then 'False' end as FileGroupDefault,
            fg.is_read_only as FileGroupReadOnly"

        $sqlfrom = "from sys.database_files df
            left outer join  sys.filegroups fg on df.data_space_id=fg.data_space_id
            left join sys.dm_io_virtual_file_stats(db_id(),NULL) vfs on df.file_id=vfs.file_id
            inner join sys.master_files mf on df.file_id = mf.file_id
            and mf.database_id = db_id()"

        $sql2008 = ",vs.available_bytes as 'VolumeFreeSpace'"
        $sql2008from = "cross apply sys.dm_os_volume_stats(db_id(),df.file_id) vs"

        $sql2000 = "select
            fg.groupname as FileGroupName,
            df.fileid as ID,
            CONVERT(INT,df.status & 0x40) / 64 as Type,
            case CONVERT(INT,df.status & 0x40) / 64 when 1 then 'LOG' else 'ROWS' end as TypeDescription,
            df.name as LogicalName,
            df.filename as PhysicalName,
            'Existing' as State,
            df.maxsize as MaxSize,
            case CONVERT(INT,df.status & 0x100000) / 1048576 when 1 then df.growth when 0 then df.growth*8 End as Growth,
            fileproperty(df.name, 'spaceused') as UsedSpace,
            df.size as Size,
            case CONVERT(INT,df.status & 0x20000000) / 536870912 when 1 then 'True' else 'False' End as IsOffline,
            case CONVERT(INT,df.status & 0x1000) / 4096 when 1 then 'True' when 0 then 'False' End as IsReadOnlyMedia,
            case CONVERT(INT,df.status & 0x10000000) / 268435456 when 1 then 'True' when 0 then 'False' End as IsSparse,
            case CONVERT(INT,df.status & 0x100000) / 1048576 when 1 then 'Percent' when 0 then 'kb' End as GrowthType,
            case CONVERT(INT,df.status & 0x1000) / 4096 when 1 then 'True' when 0 then 'False' End as IsReadOnly,
            fg.groupid as FileGroupDataSpaceId,
            NULL as FileGroupType,
            NULL AS FileGroupTypeDescription,
            CAST(fg.status & 0x10 as BIT) as FileGroupDefault,
            CAST(fg.status & 0x8 as BIT) as FileGroupReadOnly
            from sysfiles df
            left outer join  sysfilegroups fg on df.groupid=fg.groupid"
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