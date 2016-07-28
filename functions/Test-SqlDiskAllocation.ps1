Function Test-SqlDiskAllocation
{
<#
.SYNOPSIS
Checks all disks on a computer to see if they are formatted to 64k. 
	
.DESCRIPTION
Returns $true or $false by default for one server. Returns Server name and IsBestPractice for more than one server.
	
Specify -Detailed for details.
	
.PARAMETER ComputerName
The SQL Server (or server in general) that you're connecting to. The -SqlServer parameter also works.

.PARAMETER CheckForSql
Check to see if any SQL Data or Log files exists on the disk. Uses Windows authentication to connect by default.

.PARAMETER SqlCredential
If you want to use SQL Server Authentication to connect.

.PARAMETER Detailed
Show a detailed list.

.NOTES 
Requires: Windows sysadmin access on SQL Servers
	
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-SqlDiskAllocation

.EXAMPLE
Test-SqlDiskAllocation -ComputerName sqlserver2014a

.EXAMPLE   
Test-SqlDiskAllocation -ComputerName sqlserver2014a -CheckForSql

.EXAMPLE   
Test-SqlDiskAllocation -ComputerName sqlserver2014a -CheckForSql -Detailed
	
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance", "SqlServer")]
		[string[]]$ComputerName,
		[switch]$CheckForSql,
		[object]$SqlCredential,
		[switch]$Detailed
	)
	
	BEGIN
	{
		Function Get-AllDiskAllocation
		{
			$alldisks = @()
			$sqlservers = @()
			try
			{
				Write-Verbose "Testing connection to $server and resolving IP address"
				$ipaddr = (Test-Connection $server -Count 1 -ErrorAction SilentlyContinue).Ipv4Address | Select-Object -First 1
				
			}
			catch
			{
				Write-Warning "Can't connect to $server"
				return
			}
			
			try
			{
				Write-Verbose "Getting disk information from $server"
				$query = "Select Label, BlockSize, Name from Win32_Volume WHERE FileSystem='NTFS'"
				$disks = Get-WmiObject -ComputerName $ipaddr -Query $query | Sort-Object -Property Name
			}
			catch
			{
				Write-Warning "Can't connect to WMI on $server"
				return
			}
			
			if ($CheckForSql -eq $true)
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
						$sqlservers += $ipaddr
					}
					else
					{
						$sqlservers += "$ipaddr\$instance"
					}
				}
				$sqlcount = $sqlservers.Count
				Write-Verbose "$sqlcount instance(s) found"
			}
			
			foreach ($disk in $disks)
			{
				if (!$disk.name.StartsWith("\\"))
				{
					$diskname = $disk.Name
					
					if ($CheckForSql -eq $true)
					{
						$sqldisk = $false
						
						foreach ($sqlserver in $sqlservers)
						{
							Write-Verbose "Connecting to SQL instance ($sqlserver)"
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
					
					if ($disk.BlockSize -eq 65536)
					{
						$IsBestPractice = $true
					}
					else
					{
						$IsBestPractice = $false
					}
					
					if ($CheckForSql -eq $true)
					{
						$alldisks += [PSCustomObject]@{
							Server = $server
							Name = $diskname
							Label = $disk.Label
							BlockSize = $disk.BlockSize
							IsSqlDisk = $sqldisk
							IsBestPractice = $IsBestPractice
						}
					}
					else
					{
						$alldisks += [PSCustomObject]@{
							Server = $server
							Name = $diskname
							Label = $disk.Label
							BlockSize = $disk.BlockSize
							IsBestPractice = $IsBestPractice
						}
					}
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
		
		if ($Detailed -eq $true)
		{
			return $collection
		}
		elseif ($processed.Count -gt 1)
		{
			$newcollection = @()
			# brain melt, this is ugly
			foreach ($computer in $collection)
			{
				if ($newcollection.Server -contains $computer.Server) { continue }
				
				if ($CheckForSql -eq $true)
				{
					$falsecount = $computer | Where-Object { $_.IsBestPractice -eq $false -and $_.IsSqlDisk -eq $true}
				}
				else
				{
					$falsecount = $computer | Where-Object { $_.IsBestPractice -eq $false }
				}
				
				if ($falsecount -eq $null)
				{
					$IsBestPractice = $true
					
				}
				else
				{
					$IsBestPractice = $false
				}
				
				$newcollection += [PSCustomObject]@{
					Server = $computer.Server
					IsBestPractice = $IsBestPractice
				}
			}
			return $newcollection
		}
		else
		{
			foreach ($computer in $collection)
			{
				if ($CheckForSql -eq $true)
				{
					if ($computer.BlockSize -ne 65536 -and $computer.SqlDisk -eq $true)
					{
						return $false
					}
				}
				else
				{
					if ($computer.BlockSize -ne 65536)
					{
						return $false
					}
				}
			}
			return $true
		}
	}
	}