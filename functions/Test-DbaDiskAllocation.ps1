Function Test-DbaDiskAllocation
{
<#
.SYNOPSIS
Checks all disks on a computer to see if they are formatted to 64k. 
	
.DESCRIPTION
Returns $true or $false by default for one server. Returns Server name and IsBestPractice for more than one server.
	
Specify -Detailed for details.
	
References:
https://technet.microsoft.com/en-us/library/dd758814(v=sql.100).aspx - "The performance question here is usually not one of correlation per the formula, but whether the cluster size ..has been explicitly defined at 64 KB, which is a best practice for SQL Server."
http://tk.azurewebsites.net/2012/08/
	
.PARAMETER ComputerName
The SQL Server (or server in general) that you're connecting to. The -SqlServer parameter also works.

.PARAMETER NoSqlCheck
Check to skip the check for SQL Data or Log files existing on the disk. 
	
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
https://dbatools.io/Test-DbaDiskAllocation

.EXAMPLE
Test-DbaDiskAllocation -ComputerName sqlserver2014a

To return true or false for any disk not being formatted to 64k

.EXAMPLE   
Test-DbaDiskAllocation -ComputerName sqlserver2014 -Detailed
	
To return detailed information about disks containing SQL data from any instance being formatted to 64k
	
.EXAMPLE   
Test-DbaDiskAllocation -ComputerName sqlserver2014a -NoSqlCheck

To return true or false for ALL disks being formatted to 64k
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance", "SqlServer")]
		[string[]]$ComputerName,
		[switch]$NoSqlCheck,
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
					
					if ($NoSqlCheck -eq $false)
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
					
					$windowsdrive = "$env:SystemDrive\"
					
					if ($diskname -eq $windowsdrive) { $IsBestPractice = $false }
					
					if ($NoSqlCheck -eq $false)
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
			foreach ($server in $processed)
			{
				$disks = $collection | Where-Object { $_.Server -eq $Server }
				
				if ($NoSqlCheck -eq $true)
				{
					$falsecount = $disks | Where-Object { $_.IsBestPractice -eq $false }
				}
				else
				{
					$falsecount = $disks | Where-Object { $_.IsSqlDisk -eq $true -and $_.IsBestPractice -eq $false  }
				}
				
				$IsBestPractice = $true # Being optimistic ;)

				if ($falsecount.name.count -gt 0)
				{
					$IsBestPractice = $false # D'oh!
				}
				
				if ($processed.Count -eq 1) { return $IsBestPractice }
				
				$newcollection += [PSCustomObject]@{
					Server = $server
					IsBestPractice = $IsBestPractice
				}
			}
			return $newcollection
		}
	}
}