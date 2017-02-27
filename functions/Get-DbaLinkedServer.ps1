function Get-DbaLinkedServer
{
<#
.SYNOPSIS
Gets all linked servers and summary of information from the sql servers listed

.DESCRIPTION
Retrieves information about each linked server on the instance

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

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
Get-DbaLinkedServer -SqlServer DEV01

Returns all Linked Servers for the SQL Server instance DEV01

#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[string[]]$SqlInstance,
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

                    $output = [PSCustomObject]@{
                        ComputerName = $server.NetName
                        SqlInstance = $server.InstanceName
		                LinkedServerName = $ls.Name
                        RemoteServer = $ls.DataSource
                        ProductName = $ls.ProductName 
                        Impersonate = $ls.LinkedServerLogins.Impersonate
                        RemoteUser = $ls.LinkedServerLogins.remoteuser
                        Rpc = $ls.Rpc
                        RpcOut = $ls.RpcOut
                        LinkedServer = $ls
                        }
     
                    Select-DefaultView -InputObject $output -Property ComputerName, SqlInstance, LinkedServerName, RemoteServer, ProductName, Impersonate, RemoteUser, Rpc, RpcOut
            } 
        } 
    } 
} 
