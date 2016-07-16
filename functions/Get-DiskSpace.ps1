Function Get-DiskSpace
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
		[string[]]$ComputerName,
		[ValidateSet('KB', 'MB', 'GB', 'TB', 'PB')]
		[String]$Unit = "GB"
	)
	
	BEGIN
	{
		Function Get-AllDiskSpace
		{
			
			$measure = "1$unit"
			$query = "Select SystemName, Name, DriveType, FileSystem, FreeSpace, Capacity, Label from Win32_Volume where DriveType = 2 or DriveType = 3"
			
			$alldisks = @()
			
			try
			{
				$ipaddr = (Test-Connection $computername -count 1).Ipv4Address
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
					$total = "{0:n2}" -f ($disk.Capacity/$measure)
					$free = "{0:n2}" -f ($disk.Freespace/$measure)
					$percentfree = "{0:n2}" -f (($disk.Freespace / $disk.Capacity) * 100)
					
					$alldisks += [PSCustomObject]@{
						Server = $server
						Name = $disk.Name
						Label = $disk.Label
						"SizeIn$unit" = $total
						"FreeIn$unit" = $free
						PercentFree = $percentfree
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
			$null = $collection.Add((Get-AllDiskSpace $server))
		}
	}
	
	END
	{
		return $collection
	}
}