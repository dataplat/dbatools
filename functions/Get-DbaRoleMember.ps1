Function Get-DbaRoleMember
{
<#
.SYNOPSIS
Get members of all roles on a Sql instance.

.DESCRIPTION
Get members of all roles on a Sql instance.

Default output includes columns SQLServer, Database, Role, Member.

.PARAMETER SQLInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER IncludeServerLevel
Shows also information on Server Level Permissions.

.PARAMETER NoFixedRole
Excludes all members of fixed roles.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user.

.NOTES
Author: Klaas Vandenberghe ( @PowerDBAKlaas )

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Get-DbaRoleMember

.EXAMPLE
Get-DbaRoleMember -SqlServer ServerA

Returns a custom object displaying SQLServer, Database, Role, Member for all DatabaseRoles.

.EXAMPLE
Get-DbaRoleMember -SqlServer sql2016 | Out-Gridview

Returns a gridview displaying SQLServer, Database, Role, Member for all DatabaseRoles.

.EXAMPLE
Get-DbaRoleMember -SqlServer ServerA\sql987 -IncludeServerLevel

Returns a gridview displaying SQLServer, Database, Role, Member for both ServerRoles and DatabaseRoles.

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("SqlServer", "Server", "Instance")]
		[string[]]$SqlInstance,
		[PsCredential]$SqlCredential,
		[switch]$IncludeServerLevel,
		[switch]$NoFixedRole
	)
	
	DynamicParam
	{
		if ($SqlInstance)
		{
			Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $Credential
		}
	}
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
	}
	
	PROCESS
	{
		foreach ($instance in $sqlinstance)
		{
			Write-Verbose "Connecting to $Instance"
			try
			{
				$server = Connect-SqlServer -SqlServer $Instance -SqlCredential $sqlcredential
			}
			catch
			{
				Write-Warning "Failed to connect to $Instance"
				continue
			}
			
			if ($IncludeServerLevel)
			{
				Write-Verbose "Server Role Members included"
				$instroles = $null
				Write-Verbose "Getting Server Roles on $instance"
				$instroles = $server.roles
				if ($NoFixedRole)
				{
					$instroles = $instroles | Where-Object { $_.isfixedrole -eq $false }
				}
				ForEach ($instrole in $instroles)
				{
					Write-Verbose "Getting Server Role Members for $instrole on $instance"
					$irmembers = $null
					$irmembers = $instrole.enumserverrolemembers()
					ForEach ($irmem in $irmembers)
					{
						[PSCustomObject]@{
							SQLInstance = $instance
							Database = $null
							Role = $instrole.name
							Member = $irmem.tostring()
						}
					}
				}
			}
			
			$dbs = $server.Databases
			
			if ($databases.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $databases -contains $_.Name }
			}
			
			foreach ($db in $dbs)
			{
				Write-Verbose "Checking accessibility of $db on $instance"
				
				if ($db.IsAccessible -ne $true)
				{
					Write-Warning "Database $db on $instance is not accessible"
					continue
				}
				
				$dbroles = $db.roles
				Write-Verbose "Getting Database Roles for $db on $instance"
				
				if ($NoFixedRole)
				{
					$dbroles = $dbroles | Where-Object { $_.isfixedrole -eq $false }
				}
				
				foreach ($dbrole in $dbroles)
				{
					Write-Verbose "Getting Database Role Members for $dbrole in $db on $instance"
					$dbmembers = $dbrole.enummembers()
					ForEach ($dbmem in $dbmembers)
					{
						[PSCustomObject]@{
							SqlInstance = $instance
							Database = $db.name
							Role = $dbrole.name
							Member = $dbmem.tostring()
						}
					}
				}
			}
		}
	}
}
