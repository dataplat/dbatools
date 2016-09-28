Function Test-DbaMaxDop
{
<# 
.SYNOPSIS 
Displays information relating to SQL Server Max Degree of Paralellism setting.  Works on SQL Server 2005-2016.

.DESCRIPTION 
Inspired by Sakthivel Chidambaram's post about SQL Server MAXDOP Calculator (https://blogs.msdn.microsoft.com/sqlsakthi/p/maxdop-calculator-sqlserver/), 
this script displays a SQL Server's: max dop configured, and the calculated recommendation.

For SQL Server 2016 shows:
    - Instance max dop configured and the calculated recommendation
    - max dop configured per database (new feature)

More info: 
    https://support.microsoft.com/en-us/kb/2806535
    https://blogs.msdn.microsoft.com/sqlsakthi/2012/05/23/wow-we-have-maxdop-calculator-for-sql-server-it-makes-my-job-easier/


These are just general recommendations for SQL Server and are a good starting point for setting the 'max degree of parallelism' option.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER SqlServer
Allows you to specify a comma separated list of servers to query.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$cred = Get-Credential, this pass this $cred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.NOTES 
Author  : Cláudio Silva (@claudioessilva)
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Test-DbaMaxDop

.EXAMPLE   
Test-DbaMaxDop -SqlServer sqlcluster,sqlserver2012

Get Memory Settings for all servers within the SQL Server Central Management Server "sqlcluster"

.EXAMPLE 
Test-DbaMaxDop -SqlServer sqlcluster | Where-Object { $_.SqlMaxDop -gt $_.RecommendedMaxDop } | Set-SqlMaxMemory 

Find all servers in CMS that have Max dop set to higher than the recommended

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [Switch]$Detailed
	)
	
	PROCESS
	{
		$collection = @()
        $hasscopedconfiguration = $false

		foreach ($servername in $sqlserver)
		{
			Write-Verbose "Attempting to connect to $servername"
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Can't connect to $servername or access denied. Skipping."
				continue
			}

            if ($server.versionMajor -lt 9)
		    {
			    Write-Warning "This function does not support versions lower than SQL Server 2005 (v9)"
                Continue
		    }
			
			$maxdop = $server.Configuration.MaxDegreeOfParallelism.ConfigValue

			try 
            {
                #represents the Number of NUMA nodes 
                $sql = "SELECT COUNT(DISTINCT memory_node_id) AS NUMA_Nodes FROM sys.dm_os_memory_clerks WHERE memory_node_id!=64"
                $NUMAnodes = $server.ConnectionContext.ExecuteScalar($sql)
            }
			catch
			{
				$errormessage = $_.Exception.Message.ToString()
				Write-Warning "Failed to execute $sql.`n$errormessage"
                continue
			}
            
            try
			{
                #represents the Number of Processor Cores
                $sql = "SELECT COUNT(scheduler_id) FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE'"
                $numberofcores = $server.ConnectionContext.ExecuteScalar($sql)
            }
			catch
			{
                $errormessage = $_.Exception.Message.ToString()
				Write-Warning "Failed to execute $sql.`n$errormessage"
                continue
			}
			
            #Calculate Recommended Max Dop to instance
            #Server with single NUMA node	
            if ($NUMAnodes -eq 1)
            {
                if ($numberofcores -lt 8)
                {
                    #Less than 8 logical processors	- Keep MAXDOP at or below # of logical processors
                    $recommendedMaxDop = $numberofcores
                }
                else
                {
                    #Equal or greater than 8 logical processors - Keep MAXDOP at 8
                    $recommendedMaxDop = 8
                }
            }
            else #Server with multiple NUMA nodes
            {
                if (($numberofcores / $NUMAnodes) -lt 8)
                {
                    #Less than 8 logical processors per NUMA node - Keep MAXDOP at or below # of logical processors per NUMA node    
                    $recommendedMaxDop = [int]($numberofcores / $NUMAnodes)
                }
                else
                {
                    #Greater than 8 logical processors per NUMA node - Keep MAXDOP at 8
                    $recommendedMaxDop = 8
                }
            }

            #since SQL Server 2016, MaxDop can be set per database
            if ($server.versionMajor -ge 13)
		    {
                $hasscopedconfiguration = $true
			    Write-Verbose "Checking SQL Server 2016 version, will go though all databases"

                foreach ($database in $server.Databases | Where-Object {$_.IsSystemObject -eq $false -and $_.IsAccessible -eq $true})
                {
                    $object = New-Object PSObject -Property @{
				                Instance = $server.Name
                                InstanceVersion = $server.Version
                                InstanceMaxDop = $maxdop
                                Database = $database.Name
                                DatabaseMaxDop = if ($database.MaxDop -eq 0) {"$($database.MaxDop) (Will use InstanceMaxDop value)"} else {"$($database.MaxDop)"}
				                RecommendedMaxDop = $recommendedMaxDop
                                NUMANodes = $NUMAnodes
                                NumberOfCores = $numberofcores
            
			                }
                    $collection += $object
                }
		    }
			else
            {
			    $object = New-Object PSObject -Property @{
				            Instance = $server.Name
                            InstanceVersion = $server.Version
                            InstanceMaxDop = $maxdop
                            Database = "N/A"
                            DatabaseMaxDop = "N/A"
				            RecommendedMaxDop = $recommendedMaxDop
                            NUMANodes = $NUMAnodes
                            NumberOfCores = $numberofcores
            
			            }
                $collection += $object
            }
			$server.ConnectionContext.Disconnect()
			
		}
        if ($Detailed)
        {
            if ($hasscopedconfiguration)
            {
		        return ($collection | Sort-Object Instance | Select-Object Instance, InstanceVersion, InstanceMaxDop, Database, DatabaseMaxDop, RecommendedMaxDop, NUMANodes, NumberOfCores)
            }
            else
            {
                return ($collection | Sort-Object Instance | Select-Object Instance, InstanceMaxDop, RecommendedMaxDop, NUMANodes, NumberOfCores)
            }
        }
        else
        {
            if ($hasscopedconfiguration)
            {
                return ($collection | Sort-Object Instance | Select-Object Instance, InstanceVersion, InstanceMaxDop, Database, DatabaseMaxDop, RecommendedMaxDop)
            }
            else
            {
                return ($collection | Sort-Object Instance | Select-Object Instance, InstanceMaxDop, RecommendedMaxDop)
            }
        }
	}
}


