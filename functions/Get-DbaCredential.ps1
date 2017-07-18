FUNCTION Get-DbaCredential
{
<#
.SYNOPSIS
Gets SQL Credential information for each instance(s) of SQL Server.

.DESCRIPTION
 The Get-DbaCredential command gets SQL Credential information for each instance(s) of SQL Server.
	
.PARAMETER SqlInstance
SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
to be executed against multiple SQL Server instances.

.PARAMETER SqlCredential
SqlCredential object to connect as. If not specified, current Windows login will be used.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages.

.NOTES
Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Get-DbaCredential

.EXAMPLE
Get-DbaCredential -SqlInstance localhost
Returns all SQL Credentials on the local default SQL Server instance

.EXAMPLE
Get-DbaCredential -SqlInstance localhost, sql2016
Returns all SQL Credentials for the local and sql2016 SQL Server instances

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[DbaInstanceParameter]$SqlInstance,
		[PSCredential]$SqlCredential,
		[switch]$Silent
	)
	
	PROCESS
	{
		foreach ($instance in $SqlInstance)
		{
			Write-Verbose "Attempting to connect to $instance"
			try
			{
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch
			{
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			
			foreach ($credential in $server.Credentials)
			{
				Add-Member -Force -InputObject $credential -MemberType NoteProperty -Name ComputerName -value $credential.Parent.NetName
				Add-Member -Force -InputObject $credential -MemberType NoteProperty -Name InstanceName -value $credential.Parent.ServiceName
				Add-Member -Force -InputObject $credential -MemberType NoteProperty -Name SqlInstance -value $credential.Parent.DomainInstanceName
				
				Select-DefaultView -InputObject $credential -Property ComputerName, InstanceName, SqlInstance, ID, Name, Identity, MappedClassType, ProviderName
			}
		}
	}
}
