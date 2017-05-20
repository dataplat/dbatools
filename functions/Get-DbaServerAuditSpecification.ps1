FUNCTION Get-DbaServerAuditSpecification
{
<#
.SYNOPSIS
Gets SQL Security Audit Specification information for each instance(s) of SQL Server.

.DESCRIPTION
 The Get-DbaServerAuditSpecification command gets SQL Security Audit Specification information for each instance(s) of SQL Server.
	
.PARAMETER SqlInstance
SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input to allow the function
to be executed against multiple SQL Server instances.

.PARAMETER SqlCredential
SqlCredential object to connect as. If not specified, current Windows login will be used.

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
https://dbatools.io/Get-DbaServerAuditSpecification

.EXAMPLE
Get-DbaServerAuditSpecification -SqlInstance localhost
Returns all Security Audit Specifications on the local default SQL Server instance

.EXAMPLE
Get-DbaServerAuditSpecification -SqlInstance localhost, sql2016
Returns all Security Audit Specifications for the local and sql2016 SQL Server instances

#>
	[CmdletBinding()]
	param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	process
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
				Write-Warning "Can't connect to $instance or access denied. Skipping."
				continue
			}
			
			if ($server.versionMajor -lt 10)
			{
				Write-Warning "Server Audits are only supported in SQL Server 2008 and above. Quitting."
				continue
			}
			
			foreach ($auditSpecification in $server.ServerAuditSpecifications)
			{
				Add-Member -InputObject $auditSpecification -MemberType NoteProperty -Name ComputerName -value $server.NetName
				Add-Member -InputObject $auditSpecification -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
				Add-Member -InputObject $auditSpecification -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
				
				Select-DefaultView -InputObject $auditSpecification -Property ComputerName, InstanceName, SqlInstance, ID, Name, AuditName, Enabled, CreateDate, DateLastModified, Guid
			}
		}
	}
    end { 
            Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Get-SqlServerAuditSpecification 
	}
}
