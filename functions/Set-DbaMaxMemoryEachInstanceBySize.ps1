Function Set-DbaMaxMemoryEachInstanceBySize {
<#
.SYNOPSIS
This function was developed out of the necessity to set max server memory when a failover has occurred,
and the node now has 2 or more instances on it. 

.DESCRIPTION
Determines which SQL Server instances are on the server, gets the RAM total on the server,
connects to each instance to get the size of the data files, uses Jonathan Kehayias' calculation to figure out
how much memory all SQL Server instances will use and then sets max server memory on each instance
based on the size of the databases. As the max server memory minimum is 2GB, it gives at least 2GB to each instance.
If any instance got 2GB, then it adjusts the calculation to accomodate an instance getting more than would have
been calculated.

Jonathan's max server memory recommenation: 
https://www.sqlskills.com/blogs/jonathan/how-much-memory-does-my-sql-server-actually-need/

.PARAMETER Server
Server or collection of servers, not a SQL Server instance but rather hostname

.PARAMETER SqlCredential
Use SqlCredential to connect to each instance found on Server with SQL authentication. 
If SqlCredential is not specified, Windows authentication will be used.

Note that as the function looks at services to determine which SQL Server instances are on the server, 
the account running the function needs admin access to Windows.

.NOTES 
Original author: Tara Kizer, Brent Ozar Unlimited (https://www.brentozar.com/)
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
https://dbatools.io/Set-DbaMaxMemoryeachInstanceBySize

.EXAMPLE
Set-DbaMaxMemoryeachInstanceBySize -Server server1

Connects to server1, connects to each SQL Server instance on server1 with Windows authentication
and then sets max server memory for each instance found based on size of databases

.EXAMPLE
Set-DbaMaxMemoryeachInstanceBySize -Server server1 -SqlCredential $cred

Connects to server1, connects to each SQL Server instance on server1 with SQL authentication
and then sets max server memory for each instance found based on size of databases

#>
	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $True, ValueFromPipeline = $True)]
		[object]$Server,
        [object]$SqlCredential
	)
	
	BEGIN { }

    PROCESS {

		$Services = Get-DbaSqlService -ComputerName $Server -Type Engine | Out-DbaDataTable

		$Instances = @() # list of instances
		$InstanceSizes = @() # list of instance name, instance size
		$i = 0
		$TotalServerSize = 0

		# Get the SQL Server service names, convert them to ServerName or ServerName\InstanceName
		foreach ($Service in $Services | Where-Object {$_.State -eq "Running"}) {
			$Instance = $Server + "\" + $Service[1]
			$Instance = $Instance.replace("\MSSQLSERVER", "").replace("MSSQL$","")

			$Instances += ,@($Instance)
		}

		foreach ($Instance in $Instances) {
			$Connection = Connect-DbaSqlServer -SqlServer $Instance

			# Get memory on one server, no need to query it on each instance
			if ($i -eq 0) {
				$ServerMemoryMB = Get-DbaMaxMemory -SqlServer $Server

				$ServerMemory = $ServerMemoryMB.TotalMB/1024

				$i = 1
			}

			# Get total size of the user database data files
			$Sql = "
				SELECT SUM(CASE WHEN type = 0 THEN MF.size * 8 / 1024.0 /1024.0 ELSE 0 END)
				FROM sys.master_files MF
				JOIN sys.databases DB ON DB.database_id = MF.database_id
				WHERE MF.database_id > 4 -- exclude system databases
				  AND DB.source_database_id is null -- exclude snapshots;"
    
			$ServerSize = $Connection.ConnectionContext.ExecuteScalar($Sql)

			$InstanceSizes += ,@($Instance, $ServerSize)
		}

		# Get the total size of all instances
		foreach ($InstanceSize in $InstanceSizes) {
			$TotalServerSize = $TotalServerSize + $InstanceSize[1]
		}

		# Jonathan Kehayias recommends to configure Max Server Memory based on the system configuration:
		# Reserve 1 GB of RAM for the OS, 1 GB for each 4 GB of RAM installed from 4–16 GB, 
		# and then 1 GB for every 8 GB RAM installed above 16 GB RAM. 
		# Give what's left to SQL Server.
		$Reserved = 1

		if ($ServerMemory -ge 4) {
			$Memory = $ServerMemory
    
			while ($Memory -gt 0) {
				if ($Memory -ge 24) {
					$Reserved += 1
					$Memory = $Memory - 8
				}
				# Skip down to the 4GB-16GB calculation when between 17-23
				elseif ($Memory -gt 16 -And $Memory -lt 24) {
					$Memory = 16
				}
				else { #if ($Memory -le 16) 
					$Reserved += 1
					$Memory = $Memory - 4
				}
			}
		}
		else {
			$Reserved = ($ServerMemory/2)
		}

		$TotalMaxMemorySize = $ServerMemory - $Reserved

		# Sort the array by the instance sizes, smallest first
		$InstanceSizes = $InstanceSizes | Sort-Object @{Expression={$_[1]}; Ascending=$True}

		foreach ($InstanceSize in $InstanceSizes) {
			# Give minimum of 2GB to each instance
			if ($TotalMaxMemorySize * ($InstanceSize[1] / $TotalServerSize) -lt 2) {
				$MaxMemorySize = 2

				# Instance got more memory than it would have calculated to, so need to remove
				# them from the totals
				$TotalServerSize -= $InstanceSize[1]

				$TotalMaxMemorySize -= 2
        
			}
			# Get a percentage of the remaining memory based on instance size
			else {
				$MaxMemorySize = $TotalMaxMemorySize * ($InstanceSize[1] / $TotalServerSize)
			}

			$TotalMaxMemorySizeLeft = $TotalMaxMemorySizeLeft - $MaxMemorySize

			# Max Server Memory is stored in megabytes
			$MaxMemorySizeMb = $MaxMemorySize * 1024

			Set-DbaMaxMemory -SqlServer $InstanceSize[0] -MaxMb $MaxMemorySizeMb
        }
    }
}
