Function Get-DbaLastBackup
{
<#
.SYNOPSIS
Get date/time for last known backups

.DESCRIPTION
Retrieves and compares the date/time for the last known backups, as well as the creation date/time for the database.


.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Return information for only specific databases

.PARAMETER Exclude
Return information for all but these specific databases

.PARAMETER Detailed
Shows detailed information

.NOTES
Copyright (C) 2016 Klaas Vandenberghe (@powerdbaklaas)

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK


.EXAMPLE
Get-DbaLastBackup -SqlServer ServerA\sql987

Returns a custom object with Server name, Database name, and the date the last time backups were performed

.EXAMPLE
Get-DbaLastBackup -SqlServer ServerA\sql987 -Detailed | Out-Gridview

Returns a gridview displaying Server, Database, LastFullBU, TimeSinceFullBU, LastDiffBU, TimeSinceDiffBU, LastLogBU, TimeSinceLastLogBU, RecoveryModel, Status, DatabaseCreated, DaysSinceDbCreated

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[PsCredential]$Credential,
		[switch]$Detailed
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
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $Credential
                # setting defaultinitfields for performance, tip from WSMelton?, if this is in the connect-sqlserver function, it can be removed here
                $server.SetDefaultInitFields($true)
                $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.DataFile], $false)
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

			$dbs = $server.Databases

			if ($databases.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $databases -contains $_.Name }
			}

			if ($exclude.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
			}


			foreach ($db in $dbs)
			{
                $obj = $null
				Write-Verbose "Processing $($db.name) on $servername"

				if ($db.IsAccessible -eq $false)
				{
					Write-Warning "The database $($db.name) on server $servername is not accessible. Skipping database."
					Continue
				}

				$TimeSinceFullBU = if ($db.LastBackupdate -lt 1) {""} else {(New-TimeSpan -Start $db.LastBackupdate).Tostring()}
                $TimeSinceFullBU = if ($db.LastBackupdate -eq 0) {""} else {$TimeSinceFullBU.split('.')[0..($TimeSinceFullBU.split('.').count - 2)] -join ' days ' }
				$TimeSinceDiffBU = if ($db.LastDifferentialBackupDate -eq 0) {""} else {(New-TimeSpan -Start $db.LastDifferentialBackupDate).Tostring()}
                $TimeSinceDiffBU = if ($db.LastDifferentialBackupDate -eq 0) {""} else {$TimeSinceDiffBU.split('.')[0..($TimeSinceDiffBU.split('.').count - 2)] -join ' days ' }
				$TimeSinceLogBU = if ($db.LastLogBackupDate -eq 0) {""} else {(New-TimeSpan -Start $db.LastLogBackupDate).Tostring()}
                $TimeSinceLogBU = if ($db.LastLogBackupDate -eq 0) {""} else {$TimeSinceLogBU.split('.')[0..($TimeSinceLogBU.split('.').count - 2)] -join ' days ' }
				$daysSinceDbCreated = (New-TimeSpan -Start $db.createDate).Days

                If ($daysSinceDbCreated -lt 1 -and $db.LastBackupDate -eq 0) { $Status = 'New database, not backed up yet' }
				elseif ((New-TimeSpan -Start $db.LastBackupDate).Days -gt 0){$Status = 'Full Back Up should be taken'}
				elseif ($db.RecoveryModel -eq "Full" -and (New-TimeSpan -Start $db.LastLogBackupDate).Hours -gt 0){$Status = 'Log Back Up should be taken'}
				else { $Status = 'Ok' }
				
				$obj = [PSCustomObject]@{
					Server = $server.name
					Database = $db.name
					LastFullBU = if ( $db.LastBackupdate -eq 0 ) { "never" } else { $db.LastBackupdate.tostring() }
                    TimeSinceFullBU = $TimeSinceFullBU
					LastDiffBU = if ( $db.LastDifferentialBackupDate -eq 0 ) { "never" } else { $db.LastDifferentialBackupDate.tostring() }
                    TimeSinceDiffBU = $TimeSinceDiffBU
					LastLogBU = if ( $db.LastLogBackupDate -eq 0 ) { "never" } else { $db.LastLogBackupDate.tostring() }
					TimeSinceLogBU = $TimeSinceLogBU
                    RecoveryModel = $db.recoverymodel
					Status = $status
					DatabaseCreated = $db.createDate
					DaysSinceDbCreated = $daysSinceDbCreated

				}
		    if ($detailed) { $obj }
		    else { $obj | Select-Object Server, Database, LastFullBU, LastLogBU }
			}
        }
    }
	END
	{}
}