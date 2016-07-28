Function Test-SqlDiskAllocation
{
<#
.SYNOPSIS
Displays Disk information for all local drives on a server
	
.DESCRIPTION
Returns a custom object with Server name, name of disk, label of disk, total size, free size and percent free.
	
.PARAMETER ComputerName
The SQL Server (or server in general) that you're connecting to. The -SqlServer parameter also works.

.PARAMETER Unit
Display the disk space information in a specific unit. Valid values incldue 'KB', 'MB', 'GB', 'TB', and 'PB'. Default is GB.
	
.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DiskSpace

.EXAMPLE
Get-DiskSpace -ComputerName sqlserver2014a

Shows disk space for sqlserver2014a in GB

.EXAMPLE   
Get-DiskSpace -ComputerName sqlserver2014a -Unit TB

Shows disk space for sqlserver2014a in TB

.EXAMPLE   
Get-DiskSpace -ComputerName server1, server2, server3 -Unit MB

Returns a custom object filled with information for server1, server2 and server3, in MB
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance", "SqlServer")]
		[string[]]$ComputerName
	)
	
	BEGIN
	{
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
		
		Function Get-AllDiskAllocation
		{
			
			$query = "Select Label, BlockSize, Name from Win32_Volume WHERE FileSystem='NTFS'"
			
			$alldisks = @()
			
			try
			{
				$ipaddr = (Test-Connection $server -count 1).Ipv4Address | Select-Object -First 1
				$disks = Get-WmiObject -ComputerName $ipaddr -Query $query | Sort-Object -Property Name
			}
			catch
			{
				throw "Can't connect to $server"
			}
			
			foreach ($disk in $disks)
			{
				
				if (!$disk.name.StartsWith("\\"))
				{
					$diskname = $disk.Name
					$sqldisk = "Select count(*) as Count from sys.master_files where physical_name like '$diskname%'"
					$sourceserver.Databases['master'].ExecuteWithResults($sqldisk).Tables[0].Count
					if ($sqlcount -gt 0) { $hasql = 1 } else { $hasql = 0 }
					
					$alldisks += [PSCustomObject]@{
						Server = $server
						Name = $diskname
						Label = $disk.Label
						BlockSize = $disk.BlockSize
						HasSql = $sqldisk
					}
				}
			}
			return $alldisks
		}
		
		$collection = New-Object System.Collections.ArrayList
	}
	
	PROCESS
	{
		foreach ($server in $ComputerName)
		{
			$data = Get-AllDiskAllocation $server
			
			if ($data.Count -gt 1)
			{
				$data.GetEnumerator() | ForEach-Object { $null = $collection.Add($_) }
			}
			else
			{
				$null = $collection.Add($data)
			}
		}
	}
	
	END
	{
		return $collection
	}
}