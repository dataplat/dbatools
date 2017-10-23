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
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias('SqlServer', 'Server', 'Instance')]
		[string[]]$SqlInstance,
		[PsCredential]$SqlCredential,
		[switch]$IncludeServerLevel,
		[switch]$NoFixedRole
	)
	
	DynamicParam
	{
		if ($SqlInstance)
		{
			Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $SqlCredential
		}
	}
	
	BEGIN
	{
    $functionName = (Get-PSCallstack)[0].Command
		$databases = $psboundparameters.Databases
	}
	
	PROCESS
	{
		foreach ($instance in $sqlinstance)
		{
			Write-Verbose "$functionName - Connecting to $Instance"
			try
			{
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Write-Warning "$functionName - Failed to connect to $instance"
				continue
			}
			
			if ($IncludeServerLevel)
			{
				Write-Verbose "$functionName - Server Role Members included"
				$instroles = $null
				Write-Verbose "$functionName - Getting Server Roles on $instance"
				$instroles = $server.roles
				if ($NoFixedRole)
				{
					$instroles = $instroles | Where-Object { $_.isfixedrole -eq $false }
				}
				ForEach ($instrole in $instroles)
				{
					Write-Verbose "$functionName - Getting Server Role Members for $instrole on $instance"
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
        Write-Verbose "$functionName - $($databases.count) databases on $instance"
        $dbs = $dbs | Where-Object { $databases -contains $_.Name }
      }
			
			foreach ($db in $dbs)
			{
				Write-Verbose "$functionName - Checking accessibility of $db on $instance"
				
				if ($db.IsAccessible -ne $true)
				{
					Write-Warning "$functionName - Database $db on $instance is not accessible"
					continue
				}
				
				$dbroles = $db.roles
				Write-Verbose "$functionName - Getting Database Roles for $db on $instance"
				
				if ($NoFixedRole)
				{
					$dbroles = $dbroles | Where-Object { $_.isfixedrole -eq $false }
				}
				
				foreach ($dbrole in $dbroles)
				{
					Write-Verbose "$functionName - Getting Database Role Members for $dbrole in $db on $instance"
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
