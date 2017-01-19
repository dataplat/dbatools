FUNCTION Get-DbaAgentOperator
{
<#
.SYNOPSIS
Returns all SQL Agent operators on a SQL Server Agent.

.DESCRIPTION
This function returns SQL Agent operators.

.PARAMETER SqlServer
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
Get-DbaAgentOperator -SqlServer ServerA,ServerB\instanceB
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
		foreach ($Instance in $SqlInstance)
		{
			try
			{
				$Instance = Connect-SqlServer -SqlServer $Instance -SqlCredential $sqlcredential
			}
			catch
			{
				Write-Warning "Failed to connect to $Instance"
				continue
			}
			
			$operators = $Instance.jobserver.operators
			
			if (!$operators)
			{
				Write-Verbose "No operators on $Instance"
			}
			else
			{
				foreach ($operator in $operators)
				{
					[pscustomobject]@{
                        ComputerName = $Instance.NetName
						InstanceName = $Instance.ServiceName
                        SqlInstance = $Instance.Name
                        OperatorID = $operator.ID
                        IsEnabled = $operator.Enabled
                        EmailAddress = $operator.EmailAddress
                        LastEmailDate = $operator.LastEmailDate
					}
				}
			}
		}
	}
	END	{}
}