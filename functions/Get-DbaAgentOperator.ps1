FUNCTION Get-DbaAgentOperator
{
<#
.SYNOPSIS
Returns all SQL Agent operators on a SQL Server Agent.

.DESCRIPTION
This function returns SQL Agent operators.

.PARAMETER SqlInstance
SQLServer name or SMO object representing the SQL Server to connect to.
This can be a collection and receive pipeline input.

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, currend Windows login will be used.

.NOTES 
Author: Klaas Vandenberghe ( @PowerDBAKlaas )
Date: 2017-01-16

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Get-DbaAgentOperator

.EXAMPLE
Get-DbaAgentOperator -SqlInstance ServerA,ServerB\instanceB
Returns any SQL Agent operators on serverA and serverB\instanceB

.EXAMPLE
'serverA','serverB\instanceB' | Get-DbaAgentOperator
Returns all SQL Agent operators  on serverA and serverB\instanceB

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
            Write-Warning "There is no SQL Agent on $server , it's a $($server.Edition)"
            continue
			}
			
			$operators = $server.Jobserver.operators
			
			if ( $operators.count -lt 1 )
			{
				Write-Verbose "No operators on $server"
			}
			else
			{
				foreach ( $operator in $operators )
				{
					$jobs = $server.JobServer.jobs | Where-Object { $_.OperatorToEmail, $_.OperatorToNetSend, $_.OperatorToPage -contains $operator.Name }
					$lastemail = $operator.LastEmailDate
					
					if (((Get-Date) - $lastemail).TotalDays -gt 36500)
					{
						$lastemail = $null
					}
					
					[pscustomobject]@{
						ComputerName = $server.NetName
						SqlInstance = $server.Name
						InstanceName = $server.ServiceName
						OperatorName = $operator.Name
                        OperatorID = $operator.ID
                        IsEnabled = $operator.Enabled
                        EmailAddress = $operator.EmailAddress
						LastEmailDate = $lastemail
						RelatedJobs = $jobs
						Operator = $operator
					} | Select-DefaultView -ExcludeProperty Operator
				}
			}
		}
	}
}
