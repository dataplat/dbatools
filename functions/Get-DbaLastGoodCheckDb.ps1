Function Get-DbaLastGoodCheckDb
{
<#
.SYNOPSIS
Get date/time for last known good DBCC CHECKDB

.DESCRIPTION
Retrieves and compares the date/time for the last known good DBCC CHECKDB, as well as the creation date/time for the database.

Please note that this script uses the DBCC DBINFO() WITH TABLERESULTS. DBCC DBINFO has several known weak point, such as:
 - DBCC DBINFO is an undocumented feature/command.
 - The LastKnowGood timestamp is resat when a DBCC CHECKFILEGROUP is performed.
 - The LastKnowGood timestamp does not get updated when a database in READ_ONLY.

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
Copyright (C) 2016 Jakob Bindslet (jakob@bindslet.dk)

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
Data Purity:
		http://www.sqlskills.com/blogs/paul/checkdb-from-every-angle-how-to-tell-if-data-purity-checks-will-be-run/
		https://www.mssqltips.com/sqlservertip/1988/ensure-sql-server-data-purity-checks-are-performed/

.EXAMPLE
Get-DbaLastGoodCheckDb -SqlServer ServerA\sql987

Server         Database      LastGoodCheckDb
------         --------      ---------------
ServerA\sql987 badDB         11-06-2014 20:17:29
ServerA\sql987 databaselist  11-06-2014 20:17:42
...

.EXAMPLE
Get-DbaLastGoodCheckDb -SqlServer ServerA\sql987 -Detailed | Format-Table -AutoSize

Server         Database      DatabaseCreated     LastGoodCheckDb     DaysSinceDbCreated DaysSinceLastGoodCheckDb Status                      DataPurityEnabled
------         --------      ---------------     ---------------     ------------------ ------------------------ ------                      -----------------
ServerA\sql987 badDB         14-10-2013 09:21:49 11-06-2014 20:17:29               1078                      838 CheckDB should be performed False
ServerA\sql987 databaselist  23-10-2013 17:31:35 11-06-2014 20:17:42               1069                      838 CheckDB should be performed True
...

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

		$collection = New-Object System.Collections.ArrayList
	}

	PROCESS
	{
		foreach ($servername in $SqlServer)
		{
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
				Write-Verbose "Processing $($db.name) on $servername"

				$sql = "DBCC DBINFO ([$($db.name)]) WITH TABLERESULTS"
				Write-Verbose "T-SQL: $sql"

				$resultTable = $db.ExecuteWithResults($sql).Tables[0]
				[datetime]$lastKnownGood = ($resultTable | Where-Object Field -eq 'dbi_dbccLastKnownGood').Value
				[int]$createVersion = ($resultTable | Where-Object Field -eq 'dbi_createVersion').Value
				[int]$dbccFlags = ($resultTable | Where-Object Field -eq 'dbi_dbccFlags').Value

				if (($createVersion -lt 611) -and ($dbccFlags -eq 0))
				{
					$dataPurityEnabled = $false
				}
				else {
					$dataPurityEnabled = $true
				}

				$daysSinceCheckDb = (New-TimeSpan -Start $lastKnownGood -End (Get-Date)).Days
				$daysSinceDbCreated = (New-TimeSpan -Start $db.createDate -End (Get-Date)).Days

				if ($daysSinceCheckDb -lt 7) {
						$Status = 'Ok'
				}
				elseif ($daysSinceDbCreated -lt 7)
 				{
					$Status = 'New database, not checked yet'
 				}
 				else
 				{
					$Status = 'CheckDB should be performed'
 				}

				$null = $collection.Add([PSCustomObject]@{
					Server = $server.name
					Database = $db.name
                    DatabaseCreated = $db.createDate
					LastGoodCheckDb = $lastKnownGood
					DaysSinceDbCreated = $daysSinceDbCreated
					DaysSinceLastGoodCheckDb = $daysSinceCheckDb
					Status = $status
					DataPurityEnabled = $dataPurityEnabled
#					CreateVersion = $createVersion
#					DbccFlags = $dbccFlags

				})
			}
		}
	}

	END
	{
		if ($detailed)
		{
			return $collection
		}
		else
		{
			return ($collection | Select-Object Server, Database, LastGoodCheckDb)
		}
	}
}