Function Test-DbaConnectionAuthScheme
{
<#
.SYNOPSIS
Returns the transport protocol and authentication scheme of the connection. This is useful to determine if your connection is using Kerberos.
	
.DESCRIPTION
By default, this command will return the ConnectName, ServerName, Transport and AuthScheme of the current connection.
	
ConnectName is the name you used to connect. ServerName is the name that the SQL Server reports as its @@SERVERNAME which is used to register its SPN. If you were expecting a Kerberos connection and got NTLM instead, ensure ConnectName and ServerName match. 

If -Kerberos or -Ntlm is specified, the $true/$false results of the test will be returned. Returns $true or $false by default for one server. Returns Server name and Results for more than one server.
	
.PARAMETER SqlInstance
The SQL Server that you're connecting to.
	
.PARAMETER Kerberos
Returns $true if the connection is using Kerberos, $false if other

.PARAMETER Ntlm
Returns $true if the connection is using NTLM, $false if other
	
.PARAMETER Detailed
Show a detailed list (SELECT * from sys.dm_exec_connections WHERE session_id = @@SPID)

.PARAMETER SqlCredential 
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
  
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.  
 
Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user. 

.NOTES
Tags: SPN
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-DbaConnectionAuthScheme

.EXAMPLE
Test-DbaConnectionAuthScheme -SqlInstance sqlserver2014a, sql2016

Returns ConnectName, ServerName, Transport and AuthScheme for sqlserver2014a and sql2016.

.EXAMPLE   
Test-DbaConnectionAuthScheme -SqlInstance sqlserver2014a -Kerberos

Returns $true or $false depending on if the connection is Kerberos or not.
	
.EXAMPLE   
Test-DbaConnectionAuthScheme -SqlInstance sqlserver2014a -Detailed

Returns the results of "SELECT * from sys.dm_exec_connections WHERE session_id = @@SPID"
	
#>
	[CmdletBinding()]
	[OutputType("System.Collections.ArrayList")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential", "Cred")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential = [System.Management.Automation.PSCredential]::Empty,
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
		foreach ($servername in $SqlInstance)
		{
			try
			{
				Write-Verbose "Connecting to $servername"
				$server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $SqlCredential
				
				if ($server.versionMajor -lt 9)
				{
					Write-Warning "This command only supports SQL Server 2005 and above. Skipping $servername and moving on."
					continue
				}
				
				if ($detailed -eq $true)
				{
					$sql = "SELECT @@SERVERNAME AS ServerName, * from sys.dm_exec_connections WHERE session_id = @@SPID"
				}
				else
				{
					$sql = "SELECT @@SERVERNAME AS ServerName, net_transport, auth_scheme from sys.dm_exec_connections WHERE session_id = @@SPID"
				}
				
				Write-Verbose "Getting results for the following query: $sql"
				$results = $server.ConnectionContext.ExecuteWithResults($sql).Tables
			}
			catch
			{
				Write-Warning "$_ `nMoving on"
				continue
			}
			
			if ($detailed -eq $true)
			{
				$null = $collection.Add($results.rows)
			}
			else
			{
				$null = $collection.Add([PSCustomObject]@{
					ConnectName = $servername
					ServerName = $results.ServerName
					Transport = $results.net_transport
					AuthScheme = $results.auth_scheme
				})
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
							Server = $server.ConnectName
							Result = ($server.AuthScheme -eq $auth)
						}
					}
					return $newcollection
				}
			}
		}
	}
}
