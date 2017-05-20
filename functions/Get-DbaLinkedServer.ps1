function Get-DbaLinkedServer
{
<#
	.SYNOPSIS
	Gets all linked servers and summary of information from the sql servers listed

	.DESCRIPTION
	Retrieves information about each linked server on the instance

	.PARAMETER SqlInstance
	SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input to allow the function
	to be executed against multiple SQL Server instances.

	.PARAMETER SqlCredential
	SqlCredential object to connect as. If not specified, current Windows login will be used.

	.PARAMETER Silent 
	Use this switch to disable any kind of verbose messages

	.NOTES
	Author: Stephen Bennett ( https://sqlnotesfromtheunderground.wordpress.com/ )
		
	dbatools PowerShell module (https://dbatools.io)
	Copyright (C) 2016 Chrissy LeMaire
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
		
	.LINK
	https://dbatools.io/Get-DbaLinkedServer

	.EXAMPLE
	Get-DbaLinkedServer -SqlInstance DEV01

	Returns all Linked Servers for the SQL Server instance DEV01

#>
	[CmdletBinding(DefaultParameterSetName = 'Default')]
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$Silent
	)
	

	
	begin {
		$linkedservers = $psboundparameters.LinkedServers
	}
	
	process
    {
        foreach ($Instance in $SqlInstance)
        {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failed to connect to: $instance" -Continue -Target $instance
			}
			
			$lservers = $server.LinkedServers
			
			if ($linkedservers) {
				$lservers = $lservers | Where-Object { $_.Name -in $linkedservers }
			}
			
			foreach ($ls in $lservers)
            {               
				Add-Member -InputObject $ls -MemberType NoteProperty -Name ComputerName -value $server.NetName
				Add-Member -InputObject $ls -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
				Add-Member -InputObject $ls -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
				Add-Member -InputObject $ls -MemberType NoteProperty -Name Impersonate -value $ls.LinkedServerLogins.Impersonate
				Add-Member -InputObject $ls -MemberType NoteProperty -Name RemoteUser -value $ls.LinkedServerLogins.RemoteUser
				
				Select-DefaultView -InputObject $ls -Property ComputerName, InstanceName, SqlInstance, Name, 'DataSource as RemoteServer', ProductName, Impersonate, RemoteUser, 'DistPublisher as Publisher', Distributor, DateLastModified
            } 
        } 
    } 
} 
