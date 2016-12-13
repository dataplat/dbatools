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
Get-DbaRoleMember -SqlServer ServerA\sql987 | Out-Gridview

Returns a gridview displaying SQLServer, Database, Role, Member for all DatabaseRoles.

.EXAMPLE
Get-DbaRoleMember -SqlServer ServerA\sql987 -IncludeServerLevel

Returns a gridview displaying SQLServer, Database, Role, Member for both ServerRoles and DatabaseRoles.

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("sqlserver", "server", "instance")]
		[string[]]$sqlinstance,
		[PsCredential]$sqlCredential,
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
			$server = $null
			$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlCredential
			if ($Server.count -eq 1)
			{
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
				$dbs = $null
				$dbs = $server.Databases
				
				if ($databases.count -gt 0)
				{
					$dbs = $dbs | Where-Object { $databases -contains $_.Name  }
				}
				
				foreach ($db in $dbs)
				{
					$dbroles = $null
					Write-Verbose "Getting Database Roles for $($db.name) on $instance"
					$dbroles = $db.roles
					if ($NoFixedRole)
					{
						$dbroles = $dbroles | Where-Object { $_.isfixedrole -eq $false }
					}
					foreach ($dbrole in $dbroles)
					{
						$dbmembers = $null
						Write-Verbose "Getting Database Role Members for $dbrole in $($db.name) on $instance"
						$dbmembers = $dbrole.enummembers()
						ForEach ($dbmem in $dbmembers)
						{
							[PSCustomObject]@{
								'SQLInstance' = $instance
								'Database' = $db.name
								'Role' = $dbrole.name
								'member' = $dbmem.tostring()
							}
						}
					}
				}
			}
			else
			{
				Write-Warning "Can't connect to $instance. Moving on."
				Continue
			}
		}
	}
}