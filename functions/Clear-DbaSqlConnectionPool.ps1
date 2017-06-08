Function Clear-DbaSqlConnectionPool
{
<#
.SYNOPSIS
Resets (or empties) the connection pool.

.DESCRIPTION

This command resets (or empties) the connection pool. 
	
If there are connections in use at the time of the call, they are marked appropriately and will be discarded (instead of being returned to the pool) when Close is called on them.

Ref: https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.clearallpools(v=vs.110).aspx

.PARAMETER ComputerName
A remote workstation or server name

.PARAMETER Credential
Credential for running the command remotely

.NOTES
Tags: WSMan
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Clear-DbaSqlConnectionPool

.EXAMPLE
Clear-DbaSqlConnectionPool

Clears all local connection pools

.EXAMPLE
Clear-DbaSqlConnectionPool -ComputerName workstation27

Clears all connection pools on workstation27

#>
	
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline = $true)]
		[Alias("cn", "host", "Server")]
		[string[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$Credential
	)
	
	process
	{
		# TODO: https://jamessdixon.wordpress.com/2013/01/22/ado-net-and-connection-pooling
		
		ForEach ($Computer in $Computername)
		{
			If ($Computer -ne $env:COMPUTERNAME -and $Computer -ne "localhost" -and $Computer -ne "." -and $Computer -ne "127.0.0.1")
			{
				Write-Verbose "Clearing all pools on remote computer $Computer"
				if ($credential)
				{
					Invoke-Command -ComputerName $computer -Credential $Credential -ScriptBlock { [System.Data.SqlClient.SqlConnection]::ClearAllPools() }
				}
				else
				{
					Invoke-Command -ComputerName $computer -ScriptBlock { [System.Data.SqlClient.SqlConnection]::ClearAllPools() }
				}
			}
			else
			{
				Write-Verbose "Clearing all local pools"
				if ($credential)
				{
					Invoke-Command -Credential $Credential -ScriptBlock { [System.Data.SqlClient.SqlConnection]::ClearAllPools() }
				}
				else
				{
					Invoke-Command -ScriptBlock { [System.Data.SqlClient.SqlConnection]::ClearAllPools() }
				}
			}
		}
	}
}
