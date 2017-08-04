function Test-DbaDiskAllocation
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
The SQL Server (or server in general) that you're connecting to. The -SqlInstance parameter also works.

.PARAMETER NoSqlCheck
Check to skip the check for SQL Data or Log files existing on the disk. 
	
.PARAMETER SqlCredential
If you want to use SQL Server Authentication to connect.

.PARAMETER Detailed
Show a detailed list.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages
	
.NOTES
Tags: CIM, Storage
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
	[OutputType("System.Collections.ArrayList", "System.Boolean")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer", "SqlInstance")]
		[DbaInstanceParameter[]]$ComputerName,
		[switch]$NoSqlCheck,
		[object]$SqlCredential,
		[switch]$Detailed,
		[switch]$Silent
	)
	
	BEGIN
	{
		if ($Detailed)
		{
			Write-Message -Level Warning -Message "Detailed is deprecated and will be removed in dbatools 1.0"
		}
		
		$sessionoptions = New-CimSessionOption -Protocol DCOM
		
		Function Get-AllDiskAllocation
		{
			$alldisks = @()
			$SqlInstances = @()
			
			try
			{
				Write-Message -Level Verbose -Message "Getting disk information from $computer"
				
				# $query = "Select Label, BlockSize, Name from Win32_Volume WHERE FileSystem='NTFS'"
				# $disks = Get-WmiObject -ComputerName $ipaddr -Query $query | Sort-Object -Property Name
				$disks = Get-CimInstance -CimSession $CIMsession -ClassName win32_volume -Filter "FileSystem='NTFS'" -ErrorAction Stop | Sort-Object -Property Name
			}
			catch
			{
				Stop-Function -Message "Can't connect to WMI on $computer"
				return
			}
			
			if ($NoSqlCheck -eq $false)
			{
				Write-Message -Level Verbose -Message "Checking for SQL Services"
				$sqlservices = Get-Service -ComputerName $ipaddr | Where-Object { $_.DisplayName -like 'SQL Server (*' }
				foreach ($service in $sqlservices)
				{
					$instance = $service.DisplayName.Replace('SQL Server (', '')
					$instance = $instance.TrimEnd(')')
					
					$instancename = $instance.Replace("MSSQLSERVER", "Default")
					Write-Message -Level Verbose -Message "Found instance $instancename"
					
					if ($instance -eq 'MSSQLSERVER')
					{
						$SqlInstances += $ipaddr
					}
					else
					{
						$SqlInstances += "$ipaddr\$instance"
					}
				}
				$sqlcount = $SqlInstances.Count
				
				Write-Message -Level Verbose -Message "$sqlcount instance(s) found"
			}
			
			foreach ($disk in $disks)
			{
				if (!$disk.name.StartsWith("\\"))
				{
					$diskname = $disk.Name
					
					if ($NoSqlCheck -eq $false)
					{
						$sqldisk = $false
						
						foreach ($SqlInstance in $SqlInstances)
						{
							Write-Message -Level Verbose -Message "Connecting to SQL instance ($SqlInstance)"
							try
							{
								$smoserver = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
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
								Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
							Server = $computer
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
							Server = $computer
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
	}
	
	PROCESS
	{
		foreach ($computer in $ComputerName)
		{
			
			$computer = Resolve-DbaNetworkName -ComputerName $computer -Credential $credential
			$ipaddr = $computer.IpAddress
			$Computer = $computer.ComputerName
			
			if (!$Computer)
			{
				Stop-Function -Message "Couldn't resolve hostname. Skipping." -Continue
			}
			
			Write-Message -Level Verbose -Message "Creating CimSession on $computer over WSMan"
			
			if (!$Credential)
			{
				$cimsession = New-CimSession -ComputerName $Computer -ErrorAction SilentlyContinue
			}
			else
			{
				$cimsession = New-CimSession -ComputerName $Computer -ErrorAction SilentlyContinue -Credential $Credential
			}
			
			if ($null -eq $cimsession.id)
			{
				Write-Message -Level Verbose -Message "Creating CimSession on $computer over WSMan failed. Creating CimSession on $computer over DCom"
				
				if (!$Credential)
				{
					$cimsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
				}
				else
				{
					$cimsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue
				}
			}
			
			if ($null -eq $cimsession.id)
			{
				Stop-Function -Message "Can't create CimSession on $computer" -Target $Computer
			}
			
			Write-Message -Level Verbose -Message "Getting Power Plan information from $Computer"
			
			$data = Get-AllDiskAllocation $computer
						
			if ($data.Count -gt 1)
			{
				$data.GetEnumerator()
			}
			else
			{
				$data
			}
		}
	}
}
