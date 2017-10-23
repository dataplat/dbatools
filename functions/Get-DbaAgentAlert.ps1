FUNCTION Get-DbaAgentAlert
{
<#
.SYNOPSIS
Returns all SQL Agent alerts on a SQL Server Agent.

.DESCRIPTION
This function returns SQL Agent alerts.

.PARAMETER SqlInstance
SqlInstance name or SMO object representing the SQL Server to connect to.
This can be a collection and receive pipeline input.

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, currend Windows login will be used.

.NOTES 
Author: Klaas Vandenberghe ( @PowerDBAKlaas )
Date: 2017-01-19

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Get-DbaAgentAlert

.EXAMPLE
Get-DbaAgentAlert -SqlInstance ServerA,ServerB\instanceB
Returns all SQL Agent alerts on serverA and serverB\instanceB

.EXAMPLE
'serverA','serverB\instanceB' | Get-DbaAgentAlert
Returns all SQL Agent alerts  on serverA and serverB\instanceB

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "Instance", "SqlServer")]
		[string[]]$SqlInstance,
		[PSCredential] [System.Management.Automation.CredentialAttribute()]$SqlCredential
	)
BEGIN {}
PROCESS
	{
		foreach ($instance in $SqlInstance)
		{
			try
			{
				Write-Verbose "Connecting to $instance"
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Write-Warning "Failed to connect to $instance"
				continue
			}
			
			Write-Verbose "Getting Edition from $server"
            Write-Verbose "$server is a $($server.Edition)"
			if ( $server.Edition -like 'Express*' )
            {
            Write-Warning "There is no SQL Agent on $server, it's a $($server.Edition)"
            continue
            }
			$alerts = $server.Jobserver.Alerts
			
			if ( $alerts.count -lt 1)
			{
				Write-Verbose "No alerts on $server"
			}
			else
			{
                Write-Verbose "Getting SQL Agent Alerts on $server"
				foreach ($alert in $alerts)
				{
					$LastOccurenceDate = $alert.LastOccurrenceDate
					
					if (((Get-Date) - $LastOccurenceDate).TotalDays -gt 36500)
					{
						$LastOccurenceDate = $null
					}
					
					[pscustomobject]@{
                        ComputerName = $server.NetName
						SqlInstance = $server.Name
						InstanceName = $server.ServiceName
                        AlertName = $alert.Name
                        AlertID = $alert.ID
                        JobName = $alert.JobName
                        AlertType = $alert.AlertType
                        CategoryName = $alert.CategoryName
                        Severity = $alert.Severity
                        IsEnabled = $alert.IsEnabled
                        Notifications = $alert.EnumNotifications()
                        DelayBetweenResponses = $alert.delaybetweenresponses
                        LastOccurenceDate = $alert.LastOccurrenceDate
						OccurrenceCount = $alert.OccurrenceCount
					}
				}
			}
		}
	}
END	{}
}
