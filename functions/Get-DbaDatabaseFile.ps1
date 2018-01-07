function Get-DbaDatabaseFile {
    <#
    .SYNOPSIS
    Returns detailed information about database files.

    .DESCRIPTION
    Returns detailed information about database files. Does not use SMO - SMO causes enumeration and this command avoids that.

    .PARAMETER SqlInstance
    The target SQL Server instance(s)

    .PARAMETER SqlCredential
    Credentials to connect to the SQL Server instance if the calling user doesn't have permission

    .PARAMETER Database
    The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
    The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER DatabaseCollection
    Internal Variable

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Author: Stuart Moore (@napalmgram), stuart-moore.com
    Tags: Database
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .EXAMPLE
    Get-DbaDatabaseFile -SqlInstance sql2016

    Will return an object containing all filegroups and their contained files for every database on the sql2016 SQL Server instance

    .EXAMPLE
    Get-DbaDatabaseFile -SqlInstance sql2016 -Database Impromptu

    Will return an object containing all filegroups and their contained files for the Impromptu Database on the sql2016 SQL Server instance

    .EXAMPLE
    Get-DbaDatabaseFile -SqlInstance sql2016 -Database Impromptu, Trading

    Will return an object containing all filegroups and their contained files for the Impromptu and Trading databases on the sql2016 SQL Server instance

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(ParameterSetName = "Pipe", Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [object[]]$DatabaseCollection,
        [switch][Alias('Silent')]$EnableException

    )

    process {

        foreach ($instance in $sqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $sql = "select
            fg.name as FileGroupName,
            df.file_id as 'ID',
            df.Type,
            df.type_desc as TypeDescription,
            df.name as LogicalName,
            mf.physical_name as PhysicalName,
            df.state_desc as State,
            df.max_size as MaxSize,
            df.growth as Growth,
            fileproperty(df.name, 'spaceused') as UsedSpace,
            df.size as Size,
            vfs.size_on_disk_bytes as size_on_disk_bytes,
            case df.state_desc when 'OFFLINE' then 'True' else 'False' End as IsOffline,
            case mf.is_read_only when 1 then 'True' when 0 then 'False' End as IsReadOnly,
            case mf.is_media_read_only when 1 then 'True' when 0 then 'False' End as IsReadOnlyMedia,
            case mf.is_sparse when 1 then 'True' when 0 then 'False' End as IsSparse,
            case mf.is_percent_growth when 1 then 'Percent' when 0 then 'kb' End as GrowthType,
            case mf.is_read_only when 1 then 'True' when 0 then 'False' End as IsReadOnly,
            vfs.num_of_writes as NumberOfDiskWrites,
            vfs.num_of_reads as NumberOfDiskReads,
            vfs.num_of_bytes_read as BytesReadFromDisk,
            vfs.num_of_bytes_written as BytesWrittenToDisk,
             fg.data_space_id as FileGroupDataSpaceId,
            fg.Type as FileGroupType,
            fg.type_desc as FileGroupTypeDescription,
            case fg.is_default When 1 then 'True' when 0 then 'False' end as FileGroupDefault,
            fg.is_read_only as FileGroupReadOnly"

            $sqlfrom = "from sys.database_files df
            left outer join  sys.filegroups fg on df.data_space_id=fg.data_space_id
            inner join sys.dm_io_virtual_file_stats(db_id(),NULL) vfs on df.file_id=vfs.file_id
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
            df.growth as Growth,
            fileproperty(df.name, 'spaceused') as UsedSpace,
            df.size as Size,
            case CONVERT(INT,df.status & 0x20000000) / 536870912 when 1 then 'True' else 'False' End as IsOffline,
            case CONVERT(INT,df.status & 0x10) / 16 when 1 then 'True' when 0 then 'False' End as IsReadOnly,
            case CONVERT(INT,df.status & 0x1000) / 4096 when 1 then 'True' when 0 then 'False' End as IsReadOnlyMedia,
            case CONVERT(INT,df.status & 0x10000000) / 268435456 when 1 then 'True' when 0 then 'False' End as IsSparse,
            case CONVERT(INT,df.status & 0x100000) / 1048576 when 1 then 'Percent' when 0 then 'kb' End as GrowthType,
            case CONVERT(INT,df.status & 0x1000) / 4096 when 1 then 'True' when 0 then 'False' End as IsReadOnly,
            fg.groupid as FileGroupDataSpaceId,
            NULL as FileGroupType,
            NULL AS FileGroupTypeDescription,
            CAST(fg.Status & 0x10 as BIT) as FileGroupDefault,
            CAST(fg.Status & 0x8 as BIT) as FileGroupReadOnly
            from sysfiles df
            left outer join  sysfilegroups fg on df.groupid=fg.groupid"

            Write-Message -Level Verbose -Message "Databases provided"

            if ($Database) {
                $DatabaseCollection = $server.Databases | Where-Object Name -in $database
            }
            else {
                $DatabaseCollection = $server.Databases
            }

            if ($ExcludeDatabase) {
                $DatabaseCollection = $DatabaseCollection | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $DatabaseCollection) {
                if (!$db.IsAccessible) {
                    Write-Message -Level Warning -Message "Database $db is not accessible. Skipping"
                    continue
                }
                Write-Message -Level Verbose -Message "Querying database $db"

                $version = Test-DbaDatabaseCompatibility -SqlInstance $server -Database $db.Name | select DatabaseCompatibility
                $version = + ($version.DatabaseCompatibility.ToString().replace("Version", "")) / 10

                if ($version -ge 11) {
                    $query = ($sql, $sql2008, $sqlfrom, $sql2008from) -join "`n"
                }
                elseif ($version -ge 9) {
                    $query = ($sql, $sqlfrom) -join "`n"
                }
                else {
                    $query = $sql2000
                }

                $results = $server.Query($query, $db.name)

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
                    }
                    else {
                        $maxsize = [dbasize]($result.MaxSize)
                    }

                    if ($result.VolumeFreeSpace) {
                        $VolumeFreeSpace = [dbasize]$result.VolumeFreeSpace
                    }
                    else {
                        $disks = $server.Query("xp_fixeddrives", $db.name)
                        $free = $disks | Where-Object { $_.drive -eq $result.PhysicalName.Substring(0, 1) } | Select-Object 'MB Free' -ExpandProperty 'MB Free'
                        $VolumeFreeSpace = [dbasize]($free * 1024 * 1024)
                    }
                    if ($result.GrowthType -eq "Percent") {
                        $nextgrowtheventadd = [dbasize]($result.size * ($result.Growth * 0.01) * 1024)
                    }
                    else {
                        $nextgrowtheventadd = [dbasize]($result.Growth * 8 * 1024)
                    }
                    if ( ($nextgrowtheventadd.Byte -gt ($MaxSize.Byte - $size.Byte)) -and $maxsize -gt 0 ) { [dbasize]$nextgrowtheventadd = 0 }

                    [PSCustomObject]@{
                        ComputerName             = $server.NetName
                        InstanceName             = $server.ServiceName
                        SqlInstance              = $server.DomainInstanceName
                        Database                 = $db.name
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
}
