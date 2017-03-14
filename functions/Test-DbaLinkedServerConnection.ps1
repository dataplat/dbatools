function Test-DbaLinkedServerConnection
{
<#
.SYNOPSIS
Test all linked servers from the sql servers passed

.DESCRIPTION
Test each linked server on the instance

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.NOTES
Author: Thomas LaRock ( https://thomaslarock.com )
	
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2017 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
	
.LINK
https://dbatools.io/Test-DbaLinkedServerConnection

.EXAMPLE
Test-DbaLinkedServerConnection -SqlInstance DEV01

Test all Linked Servers for the SQL Server instance DEV01

.EXAMPLE
Test-DbaLinkedServerConnection -SqlInstance sql2016 | Out-File C:\temp\results.txt

Test all Linked Servers for the SQL Server instance sql2016 and output results to file

.EXAMPLE
Test-DbaLinkedServerConnection -SqlInstance sql2016, sql2014, sql2012

Test all Linked Servers for the SQL Server instances sql2016, sql2014 and sql2012

.EXAMPLE
$servers = "sql2016","sql2014","sql2012"
$servers | Test-DbaLinkedServerConnection -SqlCredential (Get-Credential sqladmin)

Test all Linked Servers for the SQL Server instances sql2016, sql2014 and sql2012 using SQL login credentials
	
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	process
	{
		foreach ($Instance in $SqlInstance)
		{
			try
			{
				Write-Verbose "Connecting to $Instance"
				$server = Connect-SqlServer -SqlServer $Instance -SqlCredential $sqlcredential
			}
			catch
			{
				Write-Warning "Failed to connect to: $Instance"
				continue
			}
			
			foreach ($ls in $server.LinkedServers)
			{
				try
				{
					$null = $ls.TestConnection()
					$result = "Success"
					$connectivity = $true
				}
				catch
				{
					$result = $_.Exception.InnerException
					$connectivity = $false
				}
				
				[PSCustomObject]@{
					ComputerName = $server.NetName
					InstanceName = $server.ServiceName
					SqlInstance = $server.DomainInstanceName
					LinkedServerName = $ls.Name
					RemoteServer = $ls.DataSource
					Connectivity = $connectivity
					Result = $result
				} | Select-DefaultView -ExcludeProperty ComputerName, InstanceName
			}
		}
	}
}
