Function Test-SqlPartitionAlignment
{
<#
.SYNOPSIS 
Test-SqlPartitionAlignment migrates SQL Agent categories from one SQL Server to another. This is similar to sp_add_category.

https://msdn.microsoft.com/en-us/library/ms181597.aspx

.DESCRIPTION
By default, all SQL Agent categories for Jobs, Operators and Alerts are copied.  

.PARAMETER SqlServer
The SQL Server instance.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-SqlPartitionAlignment

.EXAMPLE
Test-SqlPartitionAlignment -SqlServer sqlserver2014a
Copies all policies and conditions from sqlserver2014a to sqlcluster, using Windows credentials. 

.EXAMPLE   
Test-SqlPartitionAlignment -SqlServer sqlserver2014a -SqlCredential $cred
Does this, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

.EXAMPLE   
Test-SqlPartitionAlignment -SqlServer sqlserver2014 -WhatIf
Shows what would happen if the command were executed.
	
.EXAMPLE   
Test-SqlPartitionAlignment -SqlServer sqlserver2014a
Does this 
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[switch]$Detailed
	)
	
	BEGIN
	{
		Function Get-SqlDisks
		{
			
		}
		
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
		$source = $sourceserver.DomainInstanceName
		
		$alldisks = @()
		
		Function Get-DiskAlignment
		{
			try
			{
				$ipaddr = (Test-Connection $server -count 1).Ipv4Address | Select-Object -First 1
				$disks = Get-WmiObject Win32_DiskPartition -ComputerName $ipaddr | Select-Object Name, Index, BlockSize, StartingOffset
				
			}
			catch
			{
				throw "Can't connect to $server"
			}
			
			foreach ($disk in $disks)
			{
				<#
				Connect-VIServer  myserver.fqdn.com
$Cluster = (Read-Host "Enter cluster name")
 
$myCol = @()
$vms = Get-Cluster $Cluster | get-vm | where {$_.PowerState -eq "PoweredOn" -and `
$_.Guest.OSFullName -match "Microsoft Windows*" } | Sort Name 
 
foreach($vm in $vms){
try {
$wmi = get-wmiobject -class "Win32_DiskPartition" `
-namespace "root\CIMV2" -ComputerName $vm           
    foreach ($objItem in $wmi){
        $Details = "" | Select-Object VMName, Partition, StartingOffset ,Status
        if ($objItem.StartingOffset) {
        $Details.StartingOffset = $objItem.StartingOffset
        $objItem.StartingOffset = $objItem.StartingOffset / 4096
#               Write $objItem.StartingOffset.gettype().name
            if ($objItem.StartingOffset.gettype().name -eq "UInt64"){
                $Details.VMName = $objItem.SystemName
                   $Details.Partition = $objItem.Name
                $Details.Status = "Partition aligned"
            }
            else{
                $Details.VMName = $objItem.SystemName
                   $Details.Partition = $objItem.Name
                $Details.Status = "Partition NOT aligned"
            }
    $myCol += $Details
    }
    }
				#>
				# StartingOffset / BlockSize / 128 look for decimals
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
				return $alldisks
			}
		}
		$collection = New-Object System.Collections.ArrayList
	}
	
	
	PROCESS
	{
		foreach ($server in $ComputerName)
		{
			$data = Get-DiskAlignment $server
			
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
		$sourceserver.ConnectionContext.Disconnect()
		return $collection
		
	}
}