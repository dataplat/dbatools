Function Get-DbaDatabaseFile {
    <#
    .SYNOPSIS
    Backup one or more SQL Sever databases from a SQL Server SqlInstance

    .DESCRIPTION
    Performs a backup of a specified type of 1 or more databases on a SQL Server Instance.
    These backups may be Full, Differential or Transaction log backups

    .PARAMETER SqlInstance
    The SQL Server instance hosting the databases to be backed up

    .PARAMETER SqlCredential
    Credentials to connect to the SQL Server instance if the calling user doesn't have permission

    .PARAMETER Database
    Name of the Databases to be scanned for file details. If left blank, will return for all accesible databases on the specified instance

    .PARAMETER DataFilePath
    If you provide part of a DataFilePath, the owing database will be returned.
    If the file is not owned by the specified instance, the function returns False

    .PARAMETER DatabaseCollection
    Internal Variable
	.PARAMETER Silent 
	Use this switch to disable any kind of verbose messages
	
    .NOTES
    Tags: 
    Original Author: Stuart Moore (@napalmgram), stuart-moore.com

    dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
    Copyright (C) 2016 Chrissy LeMaire

    This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
    You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

    .EXAMPLE 
    Get-DbaDatabaseFile -SqlInstance sql2016

    Will return an object containing all filegroups and their contained files for every database on the sql2016 SQL Server instance

    .EXAMPLE
    Get-DbaDatabaseFile -SqlInstance sql2016 -Database Impromptu

    Will return an object containing all filegroups and their contained files for the Impromptu Database on the sql2016 SQL Server instance

    .EXAMPLE
    Get-DbaDatabaseFile -SqlInstance sql2016 -Database Impromptu, Trading

    Will return an object containing all filegroups and their contained files for the Impromptu and Trading databases on the sql2016 SQL Server instance

    .EXAMPLE 
    Get-DbaDataBaseFile -SqlInstance sql2016 -DataFilePath Impromptu

    Will return an object for every file that includes Impromptu in it's Physical File name
    If not exist on the specified instance it will return false.
    
    #>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	param (
		[parameter(ParameterSetName = "Pipe", Mandatory = $true)]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[object[]]$DatabaseCollection,
		[string]$DataFilePath = '#',
		[switch]$Silent
		
	)
	dynamicparam { if ($SqlInstance) { return Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $SqlCredential } }
	
	begin {
		$databases = $psboundparameters.Databases
	}
	process {
		foreach ($instance in $sqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failed to connect to $instance. Exception: $_" -Continue -Target $instance -InnerErrorRecord $_
			}
			
			if ($databases) {
				$DatabaseCollection = $server.Databases | Where-Object { $_.Name -in $databases }
			}
			else {
				$DatabaseCollection = $server.Databases
			}
			
			
			if ($DataFilePath -eq '#') {
				$oresults = @{ }
				Write-Message -Level Verbose -Message "Databases provided"
				$sql = "select 
                fg.name as fgname,
                fg.name as parent,
                fg.data_space_id,
                fg.type,
                fg.type_desc,
                case fg.is_default When 1 then 'True' when 0 then 'False' end as FGIsDefault,
                fg.is_read_only as FGIsReadOnly,
                df.file_id as 'ID',
                df.type,
                df.type_desc,
                df.name,
                df.physical_name as 'FileName',
                df.state_desc as 'State',
                df.max_size as 'MaxSize',
                df.growth as 'Growth',
                fileproperty(df.name, 'spaceused') as 'UsedSpace',
                df.size as 'Size',
                (df.size) - fileproperty(df.name, 'spaceused') as 'AvailableSpace',
                case df.state_desc when 'OFFLINE' then 'True' else 'False' End as IsOffline,
                case df.is_read_only when 1 then 'True' when 0 then 'False' End as 'IsReadOnly',
                case df.is_media_read_only when 1 then 'True' when 0 then 'False' End as 'IsReadOnlyMedia',
                case df.is_sparse when 1 then 'True' when 0 then 'False' End as 'IsSparse',
                case df.is_percent_growth when 1 then 'Percent' when 0 then 'kb' End as 'GrowthType',
                case df.is_read_only when 1 then 'True' when 0 then 'False' End as 'IsReadOnly',
                vfs.num_of_writes as 'NumberOfDiskWrites',
                vfs.num_of_reads as 'NumberOfDiskReads',
                vfs.num_of_bytes_read as 'BytesReadFromDisk',
                vfs.num_of_bytes_written as 'BytesWrittenToDisk'"
				$sqlfrom = "from sys.database_files df
                left outer join  sys.filegroups fg on df.data_space_id=fg.data_space_id
                inner join sys.dm_io_virtual_file_stats(db_id(),NULL) vfs on df.file_id=vfs.file_id"
				$sql2008 = ",vs.available_bytes as 'VolumeFreeSpace'"
				$sql2008from = "cross apply sys.dm_os_volume_stats(db_id(),df.file_id) vs"
				
				if ($server.VersionMajor -ge 11) {
					$sql = ($sql, $sql2008, $sqlfrom, $sql2008from) -join "`n"
				}
				elseif ($server.VersionMajor -ge 9) {
					$sql = ($sql, $sqlfrom) -join "`n"
				}
				else {
					$sql = "select 
                        fg.groupname as fgname,
                        fg.groupname as parent,
                        fg.groupid as 'data_space_id',
                        NULL as type,
                        NULL AS type_desc,
                        CAST(fg.Status & 0x10 as BIT) as FGIsDefault,
                        CAST(fg.Status & 0x8 as BIT) as FGIsReadOnly,
                        df.fileid as 'ID',
                        CONVERT(INT,df.status & 0x40) / 64 as 'type',
                        case CONVERT(INT,df.status & 0x40) / 64 when 1 then 'LOG' else 'ROWS' end as type_desc,
                        df.name,
                        df.filename as 'FileName',
                        'Existing' as 'State',
                        df.maxsize as 'MaxSize',
                        df.growth as 'Growth',
                        fileproperty(df.name, 'spaceused') as 'UsedSpace',
                        df.size as 'Size',
                        (df.size) - fileproperty(df.name, 'spaceused') as 'AvailableSpace',
                        case CONVERT(INT,df.status & 0x20000000) / 536870912 when 1 then 'True' else 'False' End as 'IsOffline',
                        case CONVERT(INT,df.status & 0x10) / 16 when 1 then 'True' when 0 then 'False' End as 'IsReadOnly',
                        case CONVERT(INT,df.status & 0x1000) / 4096 when 1 then 'True' when 0 then 'False' End as 'IsReadOnlyMedia',
                        case CONVERT(INT,df.status & 0x10000000) / 268435456 when 1 then 'True' when 0 then 'False' End as 'IsSparse',
                        case CONVERT(INT,df.status & 0x100000) / 1048576 when 1 then 'Percent' when 0 then 'kb' End as 'GrowthType',
                        case CONVERT(INT,df.status & 0x1000) / 4096 when 1 then 'True' when 0 then 'False' End as 'IsReadOnly'
                        from sysfiles df
                        left outer join  sysfilegroups fg on df.groupid=fg.groupid"
				}
				
				foreach ($db in $DatabaseCollection) {
					Write-Message -Level Verbose -Message "Querying database $($db.name)"
					$results = Invoke-SqlCmd2 -ServerInstance $server.name -Query $sql -Database $($db.name)
					
					$grouped = $results | Group-Object -Property fgname
					$filegroups = @()
					Foreach ($Name in $grouped) {
						$GroupName = $Name.Name
						if ($GroupName -eq '') {
							$GroupName = "LOGS"
						}
						
						$filegroups += [PSCustomObject]@{
							Name = $GroupName
							ID = $Name[0].group[0].data_space_id
							IsDefault = $Name.group[0].FGIsDefault
							IsReadonly = $Name.group[0].FGIsReadOnly
							Size = ($Name.group.Size | Measure-Object -sum).sum
							Files = $Name.group | Select-Object AvailableSpace, BytesReadFromDisk, BytesWrittenToDisk, FileName, Growth, GrowthType, ID, IsOffline, IsPrimaryFile, IsReadOnly, IsReadOnlyMedia, IsSparse, MaxSize, NumberOfDiskReads, NumberOfDiskWrites, Size, UsedSpace, VolumeFreeSpace, Name, State
						}
					}
					[PSCustomObject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						Database = $db.name
						FileGroups = $filegroups
					}
				}
			}
			else {
				Write-Message -Level Verbose -Message "Path Fragment passed in"
				$sql = "select db_name(database_id) as dbname, type_desc, name, physical_name from master.sys.master_files where physical_name like '%$DataFilePath%'"
				$results = Invoke-SqlCmd2 -ServerInstance $server -Query $sql -Database master
				
				if ($null -eq $results) {
					[PSCustomObject]@{
						Exists = $False
					}
				}
				else {
					ForEach ($result in $results) {
						[PSCustomObject]@{
							ComputerName = $server.NetName
							InstanceName = $server.ServiceName
							SqlInstance = $server.DomainInstanceName
							Database = $result.dbname
							Exists = $True
							FileType = $result.type_desc
							LogicalName = $result.name
							PhysicalName = $result.physical_name
						}
					}
				}
			}
		}
	}
}
