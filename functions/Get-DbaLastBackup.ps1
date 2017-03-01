Function Get-DbaLastBackup
{
<#
.SYNOPSIS
Get date/time for last known backups

.DESCRIPTION
Retrieves and compares the date/time for the last known backups, as well as the creation date/time for the database.

Default output includes columns Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated.

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Return information for only specific databases

.PARAMETER Exclude
Return information for all but these specific databases

.PARAMETER Simple
Shows concise information including Server name, Database name, and the date the last time backups were performed

.NOTES
Tags: DisasterRecovery, Backup
Author: Klaas Vandenberghe ( @PowerDBAKlaas )

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Get-DbaLastBackup

.EXAMPLE
Get-DbaLastBackup -SqlServer ServerA\sql987

Returns a custom object displaying Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated

.EXAMPLE
Get-DbaLastBackup -SqlServer ServerA\sql987 -Simple

Returns a custom object with Server name, Database name, and the date the last time backups were performed

.EXAMPLE
Get-DbaLastBackup -SqlServer ServerA\sql987 | Out-Gridview

Returns a gridview displaying Server, Database, RecoveryModel, LastFullBackup, LastDiffBackup, LastLogBackup, SinceFull, SinceDiff, SinceLog, Status, DatabaseCreated, DaysSinceDbCreated

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[PsCredential]$Credential,
		[switch]$Simple
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

			$dbs = $server.Databases | Where-Object { $_.name -ne 'TempDb' }

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
                $result = $null
				Write-Verbose "Processing $($db.name) on $servername"

				if ($db.IsAccessible -eq $false)
				{
					Write-Warning "The database $($db.name) on server $servername is not accessible. Skipping database."
					Continue
				}
                # To avoid complicated manipulations on datetimes depending on locale settings and culture,
                # dates are compared to 0, which represents 1/01/0001 0:00:00
				$SinceFull = if ($db.LastBackupdate -eq 0) {""} else {(New-TimeSpan -Start $db.LastBackupdate).Tostring()}
                $SinceFull = if ($db.LastBackupdate -eq 0) {""} else {$SinceFull.split('.')[0..($SinceFull.split('.').count - 2)] -join ' days ' }

				$SinceDiff = if ($db.LastDifferentialBackupDate -eq 0) {""} else {(New-TimeSpan -Start $db.LastDifferentialBackupDate).Tostring()}
                $SinceDiff = if ($db.LastDifferentialBackupDate -eq 0) {""} else {$SinceDiff.split('.')[0..($SinceDiff.split('.').count - 2)] -join ' days ' }

				$SinceLog = if ($db.LastLogBackupDate -eq 0) {""} else {(New-TimeSpan -Start $db.LastLogBackupDate).Tostring()}
                $SinceLog = if ($db.LastLogBackupDate -eq 0) {""} else {$SinceLog.split('.')[0..($SinceLog.split('.').count - 2)] -join ' days ' }

				$daysSinceDbCreated = (New-TimeSpan -Start $db.createDate).Days

                If ($daysSinceDbCreated -lt 1 -and $db.LastBackupDate -eq 0) { $Status = 'New database, not backed up yet' }
				elseif ((New-TimeSpan -Start $db.LastBackupDate).Days -gt 0 -and (New-TimeSpan -Start $db.LastDifferentialBackupDate).Days -gt 0){$Status = 'No Full or Diff Back Up in the last day'}
				elseif ($db.RecoveryModel -eq "Full" -and (New-TimeSpan -Start $db.LastLogBackupDate).Hours -gt 0){$Status = 'No Log Back Up in the last hour'}
				else { $Status = 'OK' }
				
				$result = [PSCustomObject]@{
					Server = $server.name
					Database = $db.name
                    RecoveryModel = $db.recoverymodel
					LastFullBackup = if ( $db.LastBackupdate -eq 0 ) { $null } else { $db.LastBackupdate.tostring() }
					LastDiffBackup = if ( $db.LastDifferentialBackupDate -eq 0 ) { $null } else { $db.LastDifferentialBackupDate.tostring() }
					LastLogBackup = if ( $db.LastLogBackupDate -eq 0 ) { $null } else { $db.LastLogBackupDate.tostring() }
                    SinceFull = $SinceFull
                    SinceDiff = $SinceDiff
					SinceLog = $SinceLog
					DatabaseCreated = $db.createDate
					DaysSinceDbCreated = $daysSinceDbCreated
					Status = $status

				}
		    if ($Simple) { $result | Select-Object Server, Database, LastFullBackup, LastDiffBackup, LastLogBackup }
		    else { $result }
			}
        }
    }
}
