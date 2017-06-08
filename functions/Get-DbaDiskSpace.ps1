Function Get-DbaDiskSpace
{
<#
.SYNOPSIS
Displays Disk information for all local drives on a server

.DESCRIPTION
Returns a custom object with Server name, name of disk, label of disk, total size, free size, percent free, block size and filesystem.

By default, this funtion only shows drives of type 2 and 3 (removable disk and local disk).

Requires: Windows administrator access on SQL Servers

.PARAMETER ComputerName
The SQL Server (or server in general) that you're connecting to. The -SqlServer parameter also works.

.PARAMETER Unit
Display the disk space information in a specific unit. Valid values include 'Bytes', 'KB', 'MB', 'GB', 'TB', and 'PB'. Default is GB.

.PARAMETER CheckForSql
Check to see if any SQL Data or Log files exists on the disk. Uses Windows authentication to connect by default.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

.PARAMETER CheckFragmentation
Includes a check for fragmentation in all filesystems. This will increase the runtime of the function, as a fragmentation check can take seconds or even minutes for a single volume.

.PARAMETER AllDrives
Without this switch, the function will only return information about drivetype 2 and 3 (removable disk and local disk).
When this switch is used, data from all types of disks are returned:

 Value  Type of disk
   0    Unknown
   1    No Root Directory
   2    Removable Disk
   3    Local Disk
   4    Network Drive
   5    Compact Disk
   6    RAM Disk

https://msdn.microsoft.com/en-us/library/aa394515.aspx

.PARAMETER Detailed
Includes information about filesystem (FAT32, NTFS, ReFS, etc.), as well as the information provided by -CheckForSql and -AllDrives.
Also includes volumes normally excluded, such as '\\?\Volume*' volumes.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.NOTES
Tags: Storage
Author: Chrissy LeMaire (clemaire@gmail.com) & Jakob Bindslet (jakob@bindslet.dk)

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaDiskSpace

.EXAMPLE
Get-DbaDiskSpace -ComputerName srv0042 | Format-Table -AutoSize

Get diskspace for the server srv0042

Server  Name Label  SizeInGB FreeInGB PercentFree BlockSize
------  ---- -----  -------- -------- ----------- ---------
srv0042 C:\  System   126,45   114,12       90,25      4096
srv0042 E:\  Data1     97,62    96,33       98,67      4096
srv0042 F:\  DATA2      29,2     29,2         100     16384


.EXAMPLE
Get-DbaDiskSpace -ComputerName srv0042 -Unit MB | Format-Table -AutoSize

Get diskspace for the server srv0042, display in MB

Server  Name Label  SizeInMB  FreeInMB PercentFree BlockSize
------  ---- -----  --------  -------- ----------- ---------
srv0042 C:\  System   129481 116856,11       90,25      4096
srv0042 E:\  Data1     99968  98637,56       98,67      4096
srv0042 F:\  DATA2     29901  29900,92         100     16384


.EXAMPLE
Get-DbaDiskSpace -ComputerName srv0042, srv0007 -Unit TB | Format-Table -AutoSize

Get diskspace from two servers, display in TB

Server  Name Label  SizeInTB FreeInTB PercentFree BlockSize
------  ---- -----  -------- -------- ----------- ---------
srv0042 C:\  System     0,12     0,11       90,25      4096
srv0042 E:\  Data1       0,1     0,09       98,67      4096
srv0042 F:\  DATA2      0,03     0,03         100     16384
srv0007 C:\  System     0,07     0,01       11,92      4096


.EXAMPLE
Get-DbaDiskSpace -ComputerName srv0042 -Detailed | Format-Table -AutoSize

Get detailed diskspace information

Server  Name                                              Label    SizeInGB FreeInGB PercentFree BlockSize IsSqlDisk FileSystem DriveType
------  ----                                              -----    -------- -------- ----------- --------- --------- ---------- ---------
srv0042 C:\                                               System     126,45   114,12       90,25      4096     False NTFS       Local Disk
srv0042 E:\                                               Data1       97,62    96,33       98,67      4096     False ReFS       Local Disk
srv0042 F:\                                               DATA2        29,2     29,2         100     16384     False FAT32      Local Disk
srv0042 \\?\Volume{7a31be94-b842-42f5-af71-e0464a1a9803}\ Recovery     0,44     0,13       30,01      4096     False NTFS       Local Disk
srv0042 D:\                                                               0        0           0               False            Compact Disk

#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias('ServerInstance', 'SqlInstance', 'SqlServer')]
		[String[]]$ComputerName,
		[ValidateSet('Bytes', 'KB', 'MB', 'GB', 'TB', 'PB')]
		[String]$Unit = 'GB',
		[Switch]$CheckForSql,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[Switch]$Detailed,
		[Switch]$CheckFragmentation,
		[Switch]$AllDrives
	)
	
	BEGIN
	{
    $FunctionName = (Get-PSCallstack)[0].Command
		Function Get-AllDiskSpace
		{
			$alldisks = @()
			$driveTypeName = @{
				'0' = 'Unknown';
				'1' = 'No Root Directory';
				'2' = 'Removable Disk';
				'3' = 'Local Disk';
				'4' = 'Network Drive';
				'5' = 'Compact Disk';
				'6' = 'RAM Disk'
			}
			
			if ($Detailed -or $AllDrives)
			{
				$driveTypes = 0 .. 6
			}
			else
			{
				$driveTypes = 2, 3
			}
			
			if ($Unit -eq 'Bytes')
			{
				$measure = '1'
			}
			else
			{
				$measure = "1$unit"
			}
			
      try
      {
      	$disks = Get-WmiObject -Class Win32_Volume -Namespace 'root\CIMV2' -ComputerName $ipaddr | Where-Object DriveType -in ($driveTypes)
        if ($CheckFragmentation)
        {
          ##					$disks = Get-CimInstance -Class Win32_Volume -Namespace 'root\CIMV2' -ComputerName $ipaddr | Where-Object DriveType -in (2,3)
          $disks = $disks | Select-Object SystemName, Name, DriveType, FileSystem, FreeSpace, Capacity, Label, BlockSize, @{ Name = 'FilePercentFragmentation'; Expression = { "$($_.defraganalysis().defraganalysis.FilePercentFragmentation)" } }
        }
        else
        {
          #$query = "Select SystemName, Name, DriveType, FileSystem, FreeSpace, Capacity, Label, BlockSize from Win32_Volume where DriveType = 2 or DriveType = 3"
          ##					$disks = Get-CimInstance -ComputerName $ipaddr -Query $query | Sort-Object -Property Name
          $disks = $disks | Select-Object SystemName, Name, DriveType, FileSystem, FreeSpace, Capacity, Label, BlockSize
        }
      }
      catch
      {
        Write-Warning "$FunctionName - Cannot connect to WMI on $server"
        return
      }
			
			if ($CheckForSql -or $Detailed)
			{
				$sqlservers = @()
				$FailedToGetServiceInformation = $false
				try
				{
					$sqlservices = Get-Service -ComputerName $ipaddr | Where-Object { $_.DisplayName -like 'SQL Server (*' }
				}
				catch
				{
					Write-Verbose "$FunctionName - Cannot retrieve service information from $server using Get-Service. Trying WMI"
					try
					{
						$sqlservices = Get-WmiObject Win32_Service -ComputerName $ipaddr | Where-Object { $_.DisplayName -like 'SQL Server (*' }
					}
					catch
					{
						Write-Warning "$FunctionName - Cannot retrieve service information from $server using Get-Service or WMI."
						$FailedToGetServiceInformation = $true
					}
				}
				
        foreach ($service in $sqlservices)
        {
          $instance = $service.DisplayName.Replace('SQL Server (', '')
          $instance = $instance.TrimEnd(')')
					
          if ($instance -eq 'MSSQLSERVER')
          {
            $sqlservers += $server
            Write-Verbose "$FunctionName - Instance resolved as $server"
          }
          else
          {
            $sqlservers += "$server\$instance"
            Write-Verbose "$FunctionName - Instance resolved as $server\$instance"
          }
        }
			}
			
			foreach ($disk in $disks)
			{
				$diskname = $disk.Name
				if ($CheckForSql -or $Detailed)
				{
					$sqldisk = $false
					if ($FailedToGetServiceInformation)
					{
						$sqldisk = 'unknown'
					}
					else
					{
						foreach ($sqlserver in $sqlservers)
						{
							try
							{
								Write-Verbose "$FunctionName - Checking disk $diskname on $SqlServer"
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
								Write-Warning "$FunctionName - Can't connect to $server ($sqlserver)"
								continue
							}
						}
					}
				}
				
				if (!$diskname.StartsWith('\\') -or $Detailed)
				{
					if ($disk.capacity -eq 0 -or [string]::IsNullOrEmpty($disk.capacity))
					{
						$total = 0
						$free = 0
						$percentfree = 0
					}
					else
					{
						$total = [math]::round($disk.Capacity / $measure, 2)
						$free = [math]::round($disk.Freespace/$measure, 2)
						$percentfree = [math]::round(($disk.Freespace / $disk.Capacity) * 100, 2)
					}
					
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
					
					if ($Detailed)
					{
						Add-Member -InputObject $diskinfo -MemberType Noteproperty FileSystem -value $disk.FileSystem
						Add-Member -InputObject $diskinfo -MemberType Noteproperty DriveType -value $driveTypeName["$($disk.DriveType)"]
					}
					
					if ($CheckFragmentation)
					{
						Add-Member -InputObject $diskinfo -MemberType Noteproperty PercentFragmented -value $disk.FilePercentFragmentation
					}
					$alldisks += $diskinfo
				}
			}
			return $alldisks
		}
		
		
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
				Write-Verbose "$FunctionName - Connecting to $server"
			}
			else
			{
				continue
			}
			
			Write-Verbose "$FunctionName - Resolving computername"
			try
			{
				$ipaddr = ((Test-Connection -ComputerName $server -Count 1 -ErrorAction SilentlyContinue).Ipv4Address).IPAddressToString
			}
			catch
			{
				Write-Warning "$FunctionName - Can't resolve $server address"
				return
			}
			
			$data = Get-AllDiskSpace $server
			
			if ($data.Count -gt 1)
			{
				$data.GetEnumerator() | ForEach-Object { $_ }
			}
			else
			{
				$data
			}
		}
	}
}