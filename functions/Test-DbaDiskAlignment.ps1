Function Test-DbaDiskAlignment
{
<#
.SYNOPSIS
Verifies that your non-dynamic disks are aligned according to physical constraints. 
  
.DESCRIPTION
Returns $true or $false by default for one server. Returns Server name and IsBestPractice for more than one server.
  
Specify -Detailed for additional information which returns some additional optional "best practice" columns, which may show false even though you pass the alignment test.
This is because your offset is not one of the "expected" values that Windows uses, but your disk is still physically aligned.

Please refer to your storage vendor best practices before following any advice below. 
  By default issues with disk alignment should be resolved by a new installation of Windows Server 2008, Windows Vista, or later operating systems, but verifying disk alignment continues to be recommended as a best practice.
  While some versions of Windows use different starting alignments, if you are starting anew 1MB is generally the best practice offset for current operating systems (because it ensures that the partition offset % common stripe unit sizes == 0 ) 

Caveats:  
  Dynamic drives (or those provisioned via third party software) may or may not have accurate results when polled by any of the built in tools, see your vendor for details.
  Windows does not have a reliable way to determine stripe unit Sizes. These values are obtained from vendor disk management software or from your SAN administrator.
  System drives in versions previous to Windows Server 2008 cannot be aligned, but it is generally not recommended to place SQL Server databases on system drives.
  
.PARAMETER ComputerName
The SQL Server(s) you would like to connect to and check disk alignment.

.PARAMETER Detailed
Show additional disk details such as offset calculations and IsOffsetBestPractice, which returns false if you do not have one of the offsets described by Microsoft. Returning false does not mean you are not phyiscally aligned.

.PARAMETER Credential
An alternate domain/username when enumerating the drives on the SQL Server(s), if needed password will be requested when queries run. May require Administrator privileges.

.PARAMETER SQLCredential
An alternate SqlCredential object when connecting to and verifying the location of the SQL Server databases on the target SQL Server(s).

.PARAMETER NoSqlCheck
Skip checking for the presence of SQL Server and simply check all disks for alignment. This can be useful if SQL Server is not yet installed or is dormant.

.NOTES
The preferred way to determine if your disks are aligned (or not) is to calculate:
  1. Partition offset ÷ stripe unit size
  2. Stripe unit size ÷ File allocation unit size

References:
    Disk Partition Alignment Best Practices for SQL Server - https://technet.microsoft.com/en-us/library/dd758814(v=sql.100).aspx
    A great article and behind most of this code.
     
  Getting Partition Offset information with Powershell - http://sqlblog.com/blogs/jonathan_kehayias/archive/2010/03/01/getting-partition-Offset-information-with-powershell.aspx 
    Thanks to Jonathan Kehayias!

    Decree: Set your partition Offset and block Size – make SQL Server faster - http://www.midnightdba.com/Jen/2014/04/decree-set-your-partition-Offset-and-block-Size-make-sql-server-faster/
    Thanks to Jen McCown!

  Disk Performance Hands On - http://www.kendalvandyke.com/2009/02/disk-performance-hands-on-series-recap.html
    Thanks to Kendal Van Dyke!

  Get WMI Disk Information - http://powershell.com/cs/media/p/7937.aspx
    Thanks to jbruns2010!

Original Author: Constantine Kokkinos (https://constantinekokkinos.com, @mobileck)

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com,)
Copyright (C) 2016 Chrissy Lemaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-DbaDiskAlignment

.EXAMPLE   
Test-DbaDiskAlignment -ComputerName sqlserver2014a 
	
Tests the disk alignment of a single server named sqlserver2014a
	
.EXAMPLE   
Test-DbaDiskAlignment -ComputerName sqlserver2014a, sqlserver2014b, sqlserver2014c

Tests the disk alignment of mulitiple servers
	
.EXAMPLE   
Test-DbaDiskAlignment -ComputerName sqlserver2014a, sqlserver2014b, sqlserver2014c -Detailed

Displays details about the disk alignmenet calcualtions from multiple servers

#>	
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance", "SqlServer")]
		[string[]]$ComputerName,
		[switch]$Detailed,
		[string]$Credential,
		[System.Data.SqlClient.SqlCredential]$SqlCredential,
		[switch]$NoSqlCheck
	)
	BEGIN
	{
		Function Get-DiskAlignment
		{
			$sqlservers = @()
			$offsets = @()
			
			try
			{
				Write-Verbose "Testing connection to $server and resolving IP address."
				$ipaddr = (Test-Connection $server -Count 1 -ErrorAction SilentlyContinue).Ipv4Address | Select-Object -First 1
				Write-Verbose "Found $server at $ipaddr on network."
			}
			catch
			{
				Write-Warning "Can't connect to $server"
				return
			}
			
			try
			{
				Write-Verbose "Gathering information about first partition on each disk for $server"
				$partitions = Get-WmiObject -computerName $ipaddr Win32_DiskPartition
				$disks = @()
				$disks += $($partitions | ForEach-Object {
						Get-WmiObject -computerName $ipaddr -query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID=""$($_.DeviceID.Replace("\", "\\"))""} WHERE AssocClass = Win32_LogicalDiskToPartition" |
						add-member -membertype noteproperty BlockSize $_.BlockSize -passthru -force |
						add-member -membertype noteproperty BootPartition $_.BootPartition -passthru |
						add-member -membertype noteproperty DiskIndex $_.DiskIndex -passthru |
						add-member -membertype noteproperty Index $_.Index -passthru |
						add-member -membertype noteproperty NumberOfBlocks $_.NumberOfBlocks -passthru -force |
						add-member -membertype noteproperty StartingOffset $_.StartingOffset -passthru |
						add-member -membertype noteproperty Type $_.Type -passthru
					} |
					Select-Object BlockSize, BootPartition, Description, DiskIndex, Index, Name, NumberOfBlocks, Size, StartingOffset, Type
				)
				Write-Verbose "Gathered WMI information."
			}
			catch
			{
				Write-Warning "Can't connect to WMI on $server"
				return
			}
			
			if ($NoSqlCheck -eq $false)
			{
				Write-Verbose "Checking for SQL Services"
				$sqlservices = Get-Service -ComputerName $ipaddr | Where-Object { $_.DisplayName -like 'SQL Server (*' }
				foreach ($service in $sqlservices)
				{
					$instance = $service.DisplayName.Replace('SQL Server (', '')
					$instance = $instance.TrimEnd(')')
					
					$instancename = $instance.Replace("MSSQLSERVER", "Default")
					Write-Verbose "Found instance $instancename"
					if ($instance -eq 'MSSQLSERVER')
					{
						# problems with localhost vs ip, hopefully temporary fix.
						if ($ipaddr.ToString() -ne '127.0.0.1')
						{
							$sqlservers += $ipaddr
						}
						else
						{
							$sqlservers += "localhost"
						}
					}
					else
					{
						$sqlservers += "$ipaddr\$instance"
					}
				}
				$sqlcount = $sqlservers.Count
				Write-Verbose "$sqlcount instance(s) found"
			}
			
			$offsets = @()
			foreach ($disk in $disks)
			{
				if (!$disk.name.StartsWith("\\"))
				{
					$diskname = $disk.Name
					if ($NoSqlCheck -eq $false)
					{
						$sqldisk = $false
						foreach ($sqlserver in $sqlservers)
						{
							Write-Verbose "Connecting to SQL instance ($sqlserver)"
							try
							{
								if ($SqlCredential -ne $null)
								{
									$smoserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
								}
								else
								{
									$smoserver = Connect-SqlServer -SqlServer $sqlserver # win auth
								}
								$sql = "Select count(*) as Count from sys.master_files where physical_name like '$diskname%'"
								Write-Verbose "Query is: $sql"
								Write-Verbose "SQL Server is: $SqlServer"
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
					
					if ($NoSqlCheck -eq $false)
					{
						if ($sqldisk -eq $true)
						{
							$offsets += $disk
						}
					}
					else
					{
						$offsets += $disk
					}
				}
			}
			
			Write-Verbose "Checking $($offsets.count) partitions."
			$allpartitions = @()
			foreach ($partition in $offsets)
			{
				# Unfortunately "Windows does not have a reliable way to determine stripe unit Sizes. These values are obtained from vendor disk management software or from your SAN administrator."
				# And this is the #1 most impactful issue with disk alignment :D
				# What we can do is test common stripe unit Sizes against the Offset we have and give advice if the Offset they chose would work in those scenarios               
				$offset = $partition.StartingOffset/1kb
				$type = $partition.Type
				$stripe_units = @(64, 128, 256, 512, 1024) # still wish I had a better way to verify this or someone to pat my back and say its alright.            
				
				# testing dynamic disks, everyone states that info from dynamic disks is not to be trusted, so throw a warning.
				Write-Verbose "Testing for dynamic disks"
				if ($type -eq "Logical Disk Manager")
				{
					$IsDynamicDisk = $true
					Write-Warning "Disk is dynamic, all Offset calculations should be suspect, please refer to your vendor to determine actuall Offset calculations."
				}
				else
				{
					$IsDynamicDisk = $false
				}
				
				Write-Verbose "Checking for best practices offsets"
				if ($offset -ne 64 -and $offset -ne 128 -and $offset -ne 256 -and $offset -ne 512 -and $offset -ne 1024)
				{
					$IsOffsetBestPractice = $false
				}
				else
				{
					$IsOffsetBestPractice = $true
				}
				
				# as we cant tell the actual size of the file strip unit, just check all the sizes I know about                       
				foreach ($size in $stripe_units)
				{
					if ($offset % $size -eq 0) # for proper alignment we really only need to know that your offset divided by your stripe unit size has a remainer of 0 
					{
						$OffsetModuloKB = "$($offset % $size)"
						$isBestPractice = $true
					}
					else
					{
						$OffsetModuloKB = "$($offset % $size)"
						$isBestPractice = $false
					}
					
					$output = [PSCustomObject]@{
						Server = $server
						Name = "$($partition.Name)"
						PartitonSizeInMB = $($partition.Size/ 1MB)
						PartitionType = $partition.Type
						TestingStripeSizeKB = $size
						OffsetModuluCalculationKB = $OffsetModuloKB
						StartingOffsetKB = $offset
						IsOffsetBestPractice = $IsOffsetBestPractice
						IsBestPractice = $isBestPractice
						NumberOfBlocks = $partition.NumberOfBlocks
						BootPartition = $partition.BootPartition
						PartitionBlockSize = $partition.BlockSize
						IsDynamicDisk = $IsDynamicDisk
					}
					$allpartitions += $output
				}
			}
			return $allpartitions
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
				$server = $server.Split('\\')[0]
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
			
			$data = Get-DiskAlignment $server
			if ($data.Server -eq $null)
			{
				Write-Verbose "Server query failed. Removing from processed collection"
				$null = $processed.Remove($server)
				continue
			}
			
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
		if ($Detailed -eq $true)
		{
			return $collection
		}
		else
		{
			$newcollection = @()
			
			$serverlist = @{ }
			foreach ($alloc in $collection) # probably a better way to roll this up so you get one t/f per server
			{
				if (-not $serverlist.ContainsKey($alloc.server))
				{
					$serverlist.Add($alloc.server, $true)
				}
				
				if ($alloc.IsBestPractice -eq $false)
				{
					$serverlist[$alloc.server] = $false
				}
			}
			
			$serverlist.GetEnumerator() | ForEach-Object {
				$newcollection += [PSCustomObject]@{
					Server = $_.Key
					IsBestPractice = $_.Value
				}
			}
			
			if ($serverlist.count -eq 1)
			{
				return $newcollection.IsBestPractice
			}
			else
			{
				return $newcollection
			}
		}
	}
}
