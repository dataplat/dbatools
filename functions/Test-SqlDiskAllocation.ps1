Function Test-SqlDiskAllocation
{
<#
.SYNOPSIS
Checks if disk are formatted to 64k
	
.DESCRIPTION
	
.PARAMETER ComputerName
The SQL Server (or server in general) that you're connecting to. The -SqlServer parameter also works.

.PARAMETER CheckForSql

.PARAMETER SqlCredential
	
.PARAMETER Detailed

.NOTES 
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
			try
			{
				$alldisks = @()
				$query = "Select Label, BlockSize, Name from Win32_Volume WHERE FileSystem='NTFS'"
				$ipaddr = (Test-Connection $server -count 1).Ipv4Address | Select-Object -First 1
				$disks = Get-WmiObject -ComputerName $ipaddr -Query $query | Sort-Object -Property Name
			}
			catch
			{
				throw "Can't connect to $server"
			}
			
			if ($CheckForSql -eq $true)
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
				if (!$disk.name.StartsWith("\\"))
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
								Write-Verbose "Can't connect to $sqlserver"
								continue
							}
						}
					}
					
					if ($CheckForSql -eq $true)
					{
						$alldisks += [PSCustomObject]@{
							Server = $server
							Name = $diskname
							Label = $disk.Label
							BlockSize = $disk.BlockSize
							SqlDisk = $sqldisk
						}
					}
					else
					{
						$alldisks += [PSCustomObject]@{
							Server = $server
							Name = $diskname
							Label = $disk.Label
							BlockSize = $disk.BlockSize
						}
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
		if ($Detailed -eq $true)
		{
			return $collection
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