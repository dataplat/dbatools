Function Test-DbaConnectionAuthScheme
{
<#
.SYNOPSIS
Returns the transport protocol and authentication scheme of the connection. This is useful to determine if your connection is using Kerberos.
	
.DESCRIPTION
By default, this command will return the server name, transport protocol, and authentication scheme of the current connection.

If -Kerberos or -Ntlm is specified, the $true/$false results of the test will be returned. Returns $true or $false by default for one server. Returns Server name and Results for more than one server.
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.
	
.PARAMETER Kerberos
Returns $true if the connection is using Kerberos, $false if other

.PARAMETER Ntlm
Returns $true if the connection is using NTLM, $false if other
	
.PARAMETER Detailed
Show a detailed list (SELECT * from sys.dm_exec_connections WHERE session_id = @@SPID)

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-DbaConnectionAuthScheme

.EXAMPLE
Test-DbaConnectionAuthScheme -SqlServer sqlserver2014a, sql2016

Returns server name, transport and auth scheme for sqlserver2014a and sql2016.

.EXAMPLE   
Test-DbaConnectionAuthScheme -SqlServer sqlserver2014a -Kerberos

Returns $true or $false depending on if the connection is Kerberos or not.
	
.EXAMPLE   
Test-DbaConnectionAuthScheme -SqlServer sqlserver2014a -Detailed

Returns the results of "SELECT * from sys.dm_exec_connections WHERE session_id = @@SPID"
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[PsCredential]$Credential,
		[switch]$Kerberos,
		[switch]$Ntlm,
		[switch]$Detailed
	)
	
	BEGIN
	{
		$collection = New-Object System.Collections.ArrayList
	}
	
	PROCESS
	{
		foreach ($server in $SqlServer)
		{
			try
			{
				$sourceserver = Connect-SqlServer -SqlServer $server -SqlCredential $Credential
				
				if ($sourceserver.versionMajor -lt 9)
				{
					Write-Warning "This command only supports SQL Server 2005 and above. Moving on."
					continue
				}
				
				if ($detailed -eq $true)
				{
					$sql = "SELECT * from sys.dm_exec_connections WHERE session_id = @@SPID"
				}
				else
				{
					$sql = "SELECT net_transport, auth_scheme from sys.dm_exec_connections WHERE session_id = @@SPID"
				}
				
				$results = $sourceserver.ConnectionContext.ExecuteWithResults($sql).Tables
			}
			catch
			{
				Write-Warning "$_ `nMoving on"
				continue
			}
			
			if ($detailed -eq $true)
			{
				$collection += $results
			}
			else
			{
				$collection += [PSCustomObject]@{
					Server = $server
					ServerNameInSettings = $sourceserver
					Transport = $results.net_transport
					AuthScheme = $results.auth_scheme
				}
			}
		}
	}
	
	END
	{
		
		if ($Detailed -eq $true -or ($Kerberos -eq $false -and $Ntlm -eq $false))
		{
			return $collection
		}
		
		# Check if they specified auths
		$auths = 'Kerberos', 'NTLM'
		foreach ($auth in $auths)
		{
			$value = (Get-Variable -Name $auth).Value
			
			if ($value -eq $true)
			{
				if ($collection.Count -eq 1)
				{
					return ($collection.AuthScheme -eq $auth)
				}
				else
				{
					$newcollection = @()
					foreach ($server in $collection)
					{
						$newcollection += [PSCustomObject]@{
							Server = $server.Server
							Result = ($server.AuthScheme -eq $auth)
						}
					}
					return $newcollection
				}
			}
		}
	}
}