Function Get-DbaLastGoodCheckDb {
<#
.SYNOPSIS
Get date/time for last known good DBCC CHECKDB

.DESCRIPTION
Retrieves and compares the date/time for the last known good DBCC CHECKDB, as well as the creation date/time for the database.

This function supports SQL Server 2005+

Please note that this script uses the DBCC DBINFO() WITH TABLERESULTS. DBCC DBINFO has several known weak points, such as:
 - DBCC DBINFO is an undocumented feature/command.
 - The LastKnowGood timestamp is updated when a DBCC CHECKFILEGROUP is performed.
 - The LastKnowGood timestamp is updated when a DBCC CHECKDB WITH PHYSICAL_ONLY is performed.
 - The LastKnowGood timestamp does not get updated when a database in READ_ONLY.

An empty ($null) LastGoodCheckDb result indicates that a good DBCC CHECKDB has never been performed.

SQL Server 2008R2 has a "bug" that causes each databases to possess two dbi_dbccLastKnownGood fields, instead of the normal one.
This script will only displaythis function to only display the newest timestamp. If -Verbose is specified, the function will announce every time more than one dbi_dbccLastKnownGood fields is encountered.

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Database
The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

.PARAMETER Exclude
The database(s) to exclude - this list is autopopulated from the server
	
.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Author: Jakob Bindslet (jakob@bindslet.dk)
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
	
.LINK
DBCC CHECKDB:
	https://msdn.microsoft.com/en-us/library/ms176064.aspx
	http://www.sqlcopilot.com/dbcc-checkdb.html
Data Purity:
	http://www.sqlskills.com/blogs/paul/checkdb-from-every-angle-how-to-tell-if-data-purity-checks-will-be-run/
	https://www.mssqltips.com/sqlservertip/1988/ensure-sql-server-data-purity-checks-are-performed/

.EXAMPLE
Get-DbaLastGoodCheckDb -SqlInstance ServerA\sql987

Returns a custom object displaying Server, Database, DatabaseCreated, LastGoodCheckDb, DaysSinceDbCreated, DaysSinceLastGoodCheckDb, Status and DataPurityEnabled

.EXAMPLE
Get-DbaLastGoodCheckDb -SqlInstance ServerA\sql987 -SqlCredential (Get-Credential sqladmin) | Format-Table -AutoSize

Returns a formatted table displaying Server, Database, DatabaseCreated, LastGoodCheckDb, DaysSinceDbCreated, DaysSinceLastGoodCheckDb, Status and DataPurityEnabled.
Authenticates with SQL Server using alternative credentials.

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$Exclude,
		[switch]$Silent
	)
	process {
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failed to connect to: $instance" -Continue -Target $instance
			}
			
			if ($server.versionMajor -lt 9) {
				Stop-Function -Message "Get-DbaLastGoodCheckDb is only supported on SQL Server 2005 and above. Skipping Instance." -Continue -Target $instance
			}
			
			$dbs = $server.Databases
			
			if ($database) {
				$dbs = $dbs | Where-Object { $database -contains $_.Name }
			}
			
			if ($exclude) {
				$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
			}
			
			# $dbs = $dbs | Where-Object {$_.IsAccessible}
			
			foreach ($db in $dbs) {
				Write-Message -Level Verbose -Message "Processing $($db.name) on $instances"
				
				if ($db.IsAccessible -eq $false) {
					Stop-Function "The database $($db.name) is not accessible. Skipping database." -Continue -Target $db
				}
				
				$sql = "DBCC DBINFO ([$($db.name)]) WITH TABLERESULTS"
				Write-Message -Level Debug -Message "T-SQL: $sql"
				
				$resultTable = $db.ExecuteWithResults($sql).Tables[0]
				[datetime[]]$lastKnownGoodArray = $resultTable | Where-Object Field -eq 'dbi_dbccLastKnownGood' | Select-Object -ExpandProperty Value
				
				## look for databases with two or more occurrences of the field dbi_dbccLastKnownGood
				if ($lastKnownGoodArray.count -ge 2) {
					Write-Message -Level Verbose -Message "The database $($db.name) has $($lastKnownGoodArray.count) dbi_dbccLastKnownGood fields. This script will only use the newest!"
				}
				[datetime]$lastKnownGood = $lastKnownGoodArray | Sort-Object -Descending | Select-Object -First 1
				
				[int]$createVersion = ($resultTable | Where-Object Field -eq 'dbi_createVersion').Value
				[int]$dbccFlags = ($resultTable | Where-Object Field -eq 'dbi_dbccFlags').Value
				
				if (($createVersion -lt 611) -and ($dbccFlags -eq 0)) {
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
				elseif ($daysSinceDbCreated -lt 7) {
					$Status = 'New database, not checked yet'
				}
				else {
					$Status = 'CheckDB should be performed'
				}
				
				if ($lastKnownGood -eq '1/1/1900 12:00:00 AM') { Remove-Variable -Name lastKnownGood, daysSinceCheckDb }
				
				[PSCustomObject]@{
					ComputerName = $server.NetName
					InstanceName = $server.ServiceName
					SqlInstance = $server.DomainInstanceName
					Database = $db.name
					DatabaseCreated = $db.createDate
					LastGoodCheckDb = $lastKnownGood
					DaysSinceDbCreated = $daysSinceDbCreated
					DaysSinceLastGoodCheckDb = $daysSinceCheckDb
					Status = $status
					DataPurityEnabled = $dataPurityEnabled
					CreateVersion = $createVersion
					DbccFlags = $dbccFlags
				}
			}
		}
	}
}
