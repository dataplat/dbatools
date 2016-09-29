Function Get-DbaDiskSpace
{
<#
.SYNOPSIS
Displays Disk information for all local drives on a server

.DESCRIPTION
Returns a custom object with Server name, name of disk, label of disk, total size, free size, percent free, block size and filesystem.

Requires: Windows administrator access on SQL Servers

.PARAMETER ComputerName
The SQL Server (or server in general) that you're connecting to. The -SqlServer parameter also works.

.PARAMETER Unit
Display the disk space information in a specific unit. Valid values include 'Bytes', 'KB', 'MB', 'GB', 'TB', and 'PB'. Default is GB.

.PARAMETER CheckForSql
Check to see if any SQL Data or Log files exists on the disk. Uses Windows authentication to connect by default.

.PARAMETER SqlCredential
If you want to use SQL Server Authentication to connect.

.PARAMETER FileSystem
Displays the filesystem (ie. NTFS, FAT32, etc.)

.PARAMETER CheckFragmentation
Includes a check for fragmentation in all filesystems. This will increase the runtime of the function.

.PARAMETER Detailed
Includes the same information as -FileSystem -CheckForSql, as well as including Volumes ("\\?\Volume").

.NOTES
Author: Chrissy LeMaire (clemaire@gmail.com) & Jakob Bindslet (jakob@bindslet.dk)

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaDiskSpace

.EXAMPLE
Get-DbaDiskSpace -ComputerName sqlserver2014a

Shows disk space for sqlserver2014a in GB

.EXAMPLE
Get-DbaDiskSpace -ComputerName sqlserver2014a -Unit TB

Shows disk space for sqlserver2014a in TB

.EXAMPLE
Get-DbaDiskSpace -ComputerName server1, server2, server3 -Unit MB

Returns a custom object filled with information for server1, server2 and server3, in MB

.EXAMPLE
Get-DbaDiskSpace -ComputerName Odin1 -Detailed | Format-Table -AutoSize

Server Name                                              Label SizeInGB FreeInGB PercentFree BlockSize IsSqlDisk FileSystem
------ ----                                              ----- -------- -------- ----------- --------- --------- ----------
Odin1  \\?\Volume{2ec825ee-4f4a-4608-8a79-ee6d09f10340}\ Spare   931,37     48,3        5,19      4096 False     NTFS
Odin1  C:\                                               System  232,54    14,97        6,44      4096 False     NTFS
Odin1  D:\                                               Disk1  3724,87   193,82         5,2     65536 True      NTFS
Odin1  F:\                                               Disk2  2792,87    77,76        2,78      4096 False     NTFS

#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance", "SqlServer")]
		[String[]]$ComputerName,
		[ValidateSet('Bytes', 'KB', 'MB', 'GB', 'TB', 'PB')]
		[String]$Unit = "GB",
		[Switch]$CheckForSql,
		[Object]$SqlCredential,
        [Switch]$Detailed,
        [Switch]$Filesystem,
        [Switch]$CheckFragmentation
	)

	BEGIN
	{
		Function Get-AllDiskSpace
		{
			if ($Unit -eq 'Bytes')
			{
				$measure = "1"
			}
			else
			{
				$measure = "1$unit"
			}
			$alldisks = @()

			try
			{
				$ipaddr = (Test-Connection $server -Count 1 -ErrorAction SilentlyContinue).Ipv4Address | Select-Object -First 1

			}
			catch
			{
				Write-Warning "Can't connect to $server"
				return
			}

			try
			{
				if ($CheckFragmentation)
				{
					$disks = Get-WmiObject -Class Win32_Volume -Namespace 'root\CIMV2' -ComputerName $ipaddr | Where-Object DriveType -in (2,3)
					$disks = $disks | Select-Object SystemName, Name, DriveType, FileSystem, FreeSpace, Capacity, Label, BlockSize, @{Name="FilePercentFragmentation"; Expression={"$($_.defraganalysis().defraganalysis.FilePercentFragmentation)"}}
				}
				else
				{
					$query = "Select SystemName, Name, DriveType, FileSystem, FreeSpace, Capacity, Label, BlockSize from Win32_Volume where DriveType = 2 or DriveType = 3"
					$disks = Get-WmiObject -ComputerName $ipaddr -Query $query | Sort-Object -Property Name
				}
			}
			catch
			{
				Write-Warning "Can't connect to WMI on $server"
				return
			}

			if ($CheckForSql -or $Detailed)
			{
				$sqlservers = @()
				$sqlservices = Get-Service -ComputerName $ipaddr | Where-Object { $_.DisplayName -like 'SQL Server (*' }
				foreach ($service in $sqlservices)
				{
					$instance = $service.DisplayName.Replace('SQL Server (', '')
					$instance = $instance.TrimEnd(')')

					if ($instance -eq 'MSSQLSERVER')
					{
						$sqlservers += $ipaddr
					}
					else
					{
						$sqlservers += "$ipaddr\$instance"
					}
				}
			}

			foreach ($disk in $disks)
			{
				$diskname = $disk.Name
				if ($CheckForSql -eq $true)
				{
					$sqldisk = $false
					foreach ($sqlserver in $sqlservers)
					{
						try
						{
							$smoserver = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
							$sql = "Select count(*) as Count from sys.master_files where physical_name like '$diskname%'"
							$sqlcount = $smoserver.Databases['master'].ExecuteWithResults($sql).Tables[0].Count
							if ($sqlcount -gt 0)
							{
								$sqldisk = $true
								break
							}
						}
						catch
						{
							Write-Warning "Can't connect to $server ($sqlserver)"
							continue
						}
					}
				}

				if (!$diskname.StartsWith("\\") -or $Detailed)
				{
					$total = [math]::round($disk.Capacity / $measure, 2)
					$free = [math]::round($disk.Freespace/$measure, 2)
					$percentfree = [math]::round(($disk.Freespace / $disk.Capacity) * 100, 2)

					$diskinfo = [PSCustomObject]@{
						Server = $server
						Name = $diskname
						Label = $disk.Label
						"SizeIn$unit" = $total
						"FreeIn$unit" = $free
						PercentFree = $percentfree
						BlockSize = $disk.BlockSize
                    }

                    if ($CheckForSql -or $Detailed)
                    {
                        Add-Member -InputObject $diskinfo -MemberType Noteproperty IsSqlDisk -value $sqldisk
                    }

                    if ($FileSystem -or $Detailed)
                    {
                        Add-Member -InputObject $diskinfo -MemberType Noteproperty FileSystem -value $disk.FileSystem
                    }

                    if ($CheckFragmentation)
                    {
                        Add-Member -InputObject $diskinfo -MemberType Noteproperty FileSystem -value $disk.FileSystem
                    }
                    $alldisks += $diskinfo
				}
			}
			return $alldisks
		}

		$collection = New-Object System.Collections.ArrayList
		$processed = New-Object System.Collections.ArrayList
	}

	PROCESS
	{

		foreach ($server in $ComputerName)
		{
			if ($server -match '\\')
			{
				$server = $server.Split('\')[0]
			}

			if ($server -notin $processed)
			{
				$null = $processed.Add($server)
				Write-Verbose "Connecting to $server"
			}
			else
			{
				continue
			}

			$data = Get-AllDiskSpace $server

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