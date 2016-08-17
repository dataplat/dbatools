function Set-DbaDatabaseOwner
{
<#
.SYNOPSIS
Sets database owners with a desired login if databases do not match that owner.

.DESCRIPTION
This function will alter database ownershipt to match a specified login if their current owner does not match the target login. By default, the target login will be 'sa', but the fuction will allow the user to specify a different login for  ownership. The user can also apply this to all databases or only to a select list of databases (passed as either a comma separated list or a string array).

Best Practice reference: http://weblogs.sqlteam.com/dang/archive/2008/01/13/Database-Owner-Troubles.aspx

.NOTES 
Original Author: Michael Fal (@Mike_Fal), http://mikefal.net

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.PARAMETER SqlServer
SQLServer name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect under. If not specified, currend Windows login will be used.

.PARAMETER Datbases
List of databases to apply changes to. Will accept a comma separated list or a string array.
	
.PARAMETER Exclude
List of databases to exclude

.PARAMETER TargetLogin
Specific login that you wish to check for ownership. This defaults to 'sa' or the sysadmin name if sa was renamed.

.LINK
https://dbatools.io/Set-DbaDatabaseOwner

.EXAMPLE
Set-DbaDatabaseOwner -SqlServer localhost

Sets database owner to 'sa' on all databases where the owner does not match 'sa'.

.EXAMPLE
Set-DbaDatabaseOwner -SqlServer localhost -TargetLogin DOMAIN\account

To set the database owner to DOMAIN\account on all databases where the owner does not match DOMAIN\account. Note that TargetLogin must be a valid security principal that exists on the target server.

.EXAMPLE
Set-DbaDatabaseOwner -SqlServer sqlserver -Databases db1, db2

Sets database owner to 'sa' on the db1 and db2 databases if their current owner does not match 'sa'.
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[object]$SqlCredential,
		[string]$TargetLogin
	)
	
	DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $SourceSqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
	}
	
	PROCESS
	{
		foreach ($servername in $SqlServer)
		{
			
			#connect to the instance
			Write-Verbose "Connecting to $servername"
			$server = Connect-SqlServer $servername -SqlCredential $SqlCredential
			
			# dynamic sa name for orgs who have changed their sa name
			if ($psboundparameters.TargetLogin.length -eq 0)
			{
				$TargetLogin = ($server.logins | Where-Object { $_.id -eq 1 }).Name
			}
			
			#Validate login
			if (($server.Logins.Name) -notcontains $TargetLogin)
			{
				if ($sqlserver.count -eq 1)
				{
					throw "Invalid login: $TargetLogin"
				}
				else
				{
					Write-Warning "$TargetLogin is not a valid login on $servername. Moving on."
					Continue
				}
			}
			
			#Get database list. If value for -Databases is passed, massage to make it a string array.
			#Otherwise, use all databases on the instance where owner not equal to -TargetLogin
			Write-Verbose "Gathering databases to update"
			
			if ($Databases.Length -gt 0)
			{
				$dbs = $server.Databases | Where-Object { $_.Owner -ne $TargetLogin -and $databases -contains $_.Name }
			}
			else
			{
				$dbs = $server.Databases | Where-Object { $_.Owner -ne $TargetLogin }
			}
			
			if ($Exclude.Length -gt 0)
			{
				$dbs = $dbs | Where-Object { $Exclude -notcontains $_.Name }
			}
			
			# system stuff can't be modified. Well, msdb can, but let's add it anyway.
			$dbs = $dbs | Where-Object { 'master', 'model', 'msdb', 'tempdb', 'distribution' -notcontains $_.Name }
			
			
			Write-Verbose "Updating $($dbs.Count) database(s)."
			foreach ($db in $dbs)
			{
				$dbname = $db.name
				If ($PSCmdlet.ShouldProcess($servername, "Setting database owner for $dbname to $TargetLogin"))
				{					
					try
					{
						Write-Output "Setting database owner for $dbname to $TargetLogin on $servername"
						# Set database owner to $TargetLogin (default 'sa')
						$db.SetOwner($TargetLogin)
					}
					catch
					{
						# write-exception writes the full exception to file
						Write-Exception $_
						throw $_
					}
				}
			}
		}
	}
	
	END
	{
		if ($dbs.count -eq 0)
		{
			Write-Output "Lookin' good! Nothing to do."
		}
		
		Write-Verbose "Closing connection"
		$server.ConnectionContext.Disconnect()
	}
}