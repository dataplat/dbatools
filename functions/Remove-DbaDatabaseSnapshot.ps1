Function Remove-DbaDatabaseSnapshot
{
<#
.SYNOPSIS
Removes database snapshots

.DESCRIPTION
Removes database snapshot (dropping them). This means that nobody will be able to restore to the snapshotted state the base db

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Removes snapshots for only specific base dbs

.PARAMETER Exclude
Removes snapshots for all but these specific base dbs

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.NOTES
Author: niphlod

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Remove-DbaDatabaseSnapshot

.EXAMPLE
Remove-DbaDatabaseSnapshot -SqlServer sqlserver2014a

Removes all database snapshots from sqlserver2014a

.EXAMPLE
Remove-DbaDatabaseSnapshot -SqlServer sqlserver2014a -Databases HR, Accounting

Removes all database snapshots having HR and Accounting as base dbs

.EXAMPLE
Remove-DbaDatabaseSnapshot -SqlServer sqlserver2014a -Exclude HR

Removes all database snapshots excluding ones that have HR as base dbs


#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[PsCredential]$Credential
	)

	DynamicParam {
		if ($SqlServer) {
			return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $Credential
		}
	}

	BEGIN
	{
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
	}

	PROCESS
	{
		foreach ($servername in $SqlServer)
		{
			Write-Verbose "Connecting to $servername"
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $Credential

			}
			catch
			{
				if ($SqlServer.count -eq 1)
				{
					throw $_
				}
				else
				{
					Write-Warning "Can't connect to $servername. Moving on."
					Continue
				}
			}

			$dbs = $server.Databases | Where-Object IsDatabaseSnapshot -eq $true | Sort-Object DatabaseSnapshotBaseName, Name

			if ($databases.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $databases -contains $_.DatabaseSnapshotBaseName }
			}

			if ($exclude.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $exclude -notcontains $_.DatabaseSnapshotBaseName }
			}

			foreach ($db in $dbs)
			{
				If ($Pscmdlet.ShouldProcess( $server.name, "Remove db snapshot '$($db.Name)'")) {
					try
					{
						Remove-SqlDatabase -SqlServer $SqlServer -DBName $db.Name -SqlCredential $Credential
					}
					catch
					{
						return $_
					}
				}
			}
		}
	}
}
