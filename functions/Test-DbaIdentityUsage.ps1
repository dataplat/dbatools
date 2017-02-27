Function Test-DbaIdentityUsage
{
<# 
.SYNOPSIS 
Displays information relating to IDENTITY seed usage.  Works on SQL Server 2008-2016.

.DESCRIPTION 
IDENTITY seeds have max values based off of their data type.  This module will locate identity columns and report the seed usage.


.PARAMETER SqlServer
Allows you to specify a comma separated list of servers to query.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$cred = Get-Credential, this pass this $cred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER Threshold
Allows you to specify a minimum % of the seed range being utilized.  This can be used to ignore seeds that have only utilized a small fraction of the range.

.PARAMETER NoSystemDb
Allows you to suppress output on system databases

.PARAMETER Detailed
Shows detailed information about the server and database collations

.NOTES 
Author: Brandon Abshire, netnerds.net

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Test-DbaIdentityUsage

.EXAMPLE   
Test-DbaIdentityUsage -SqlServer sql2008, sqlserver2012
Check identity seeds for servers sql2008 and sqlserver2012.

.EXAMPLE   
Test-DbaIdentityUsage -SqlServer sql2008 -Database TestDB
Check identity seeds on server sql2008 for only the TestDB database

.EXAMPLE   
Test-DbaIdentityUsage -SqlServer sql2008 -Database TestDB -Threshold 20
Check identity seeds on server sql2008 for only the TestDB database, limiting results to 20% utilization of seed range or higher


#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
        [string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [parameter(Position = 1, Mandatory = $false)]
		[int]$Threshold,
        [parameter(Position = 2, Mandatory = $false)]
        [switch]$NoSystemDb,
        [parameter(Position = 3, Mandatory = $false)]
        [switch]$Detailed
	)
	
	DynamicParam {
		if ($SqlServer) {
			return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $Credential
		}
	}

	BEGIN
	{

        $databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
        
        $threshold = 0
        $threshold = $psboundparameters.Threshold

        $collection = New-Object System.Collections.ArrayList

        $sql = "	;WITH CTE_1
		AS
		(
		  SELECT SCHEMA_NAME(o.schema_id) AS SchemaName,
				 OBJECT_NAME(a.Object_id) as TableName,
				 a.Name as ColumnName,
				 seed_value AS SeedValue,
				 CONVERT(bigint, increment_value) as IncrementValue,

				 CONVERT(bigint, ISNULL(a.last_value, seed_value)) AS LastValue,

				 CONVERT(bigint,
								(
									CONVERT(bigint, ISNULL(last_value, seed_value)) 
									- CONVERT(bigint, seed_value) 
									+ (CASE WHEN CONVERT(bigint, seed_value) <> 0 THEN 1 ELSE 0 END) 
								)
								/
								CONVERT(bigint, increment_value)
						) AS NumberOfUses,

				 -- Divide by increment_value to shows the max number of values that can be used
				 -- E.g: smallint identity column that starts on the lower possible value (-32768) and have an increment of 2 will only accept ABS(32768 - 32767 - 1) / 2 = 32768 rows
				 CAST( 
						ABS(
						CONVERT(bigint, seed_value) 
						- 
						Case
							When b.name = 'tinyint'   Then 255
							When b.name = 'smallint'  Then 32767
							When b.name = 'int'       Then 2147483647
							When b.name = 'bigint'    Then 9223372036854775807
						End 
						-
						-- When less than 0 the 0 counts too
						CASE 
							WHEN CONVERT(bigint, seed_value) <= 0 THEN 1
							ELSE 0
							END
						) / CONVERT(bigint, increment_value) 
					AS Numeric(20, 0)) AS MaxNumberRows
			FROM sys.identity_columns a
				INNER JOIN sys.objects o
				   ON a.object_id = o.object_id
				INNER JOIN sys.types As b
				   ON a.system_type_id = b.system_type_id
		  WHERE a.seed_value is not null
		),
		CTE_2
		AS
		(
		SELECT SchemaName, TableName, ColumnName, CONVERT(BIGINT, SeedValue) AS SeedValue, CONVERT(BIGINT, IncrementValue) AS IncrementValue, LastValue, MaxNumberRows, NumberOfUses, 
			   CONVERT(Numeric(18,2), ((CONVERT(Float, NumberOfUses) / CONVERT(Float, (MaxNumberRows)) * 100))) AS [PercentUsed]
		  FROM CTE_1
		)
		SELECT DB_NAME() as DatabaseName, SchemaName, TableName, ColumnName, SeedValue, IncrementValue, LastValue, MaxNumberRows, NumberOfUses, [PercentUsed]
		  FROM CTE_2
	--	 WHERE [PercentUsed] > 80
		ORDER BY [PercentUsed] DESC"

	}
	
	PROCESS
	{
		
		foreach ($servername in $sqlserver)
		{
			Write-Verbose "Attempting to connect to $servername"
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Can't connect to $servername or access denied. Skipping."
				continue
			}
			
			if ($server.versionMajor -lt 10)
			{
				Write-Warning "This function does not support versions lower than SQL Server 2008 (v10). Skipping server $servername."
				
				Continue
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

            if ($NoSystemDb)
            {
                $dbs = $dbs | Where-Object { $_.IsSystemObject -eq $false }
            }


            foreach ($db in $dbs)
			{
				Write-Verbose "Processing $($db.name) on $servername"

				if ($db.IsAccessible -eq $false)
				{
					Write-Warning "The database $($db.name) is not accessible. Skipping database."
					Continue
				}

                $resultTable = $db.ExecuteWithResults($sql).Tables[0]
                #$resultTable


                foreach ($row in $resultTable)
                {

                    if ($row.PercentUsed -ge $threshold)
                        {
				        $null = $collection.Add(
                        [PSCustomObject]@{
					        Server = $server.name
					        Database = $row.DatabaseName
					        Schema = $row.SchemaName
                            Table = $row.TableName
					        Column = $row.ColumnName
					        SeedValue = $row.SeedValue
                            IncrementValue = $row.IncrementValue
					        LastValue = $row.LastValue
					        MaxNumberRows = $row.MaxNumberRows
                            NumberOfUses = $row.NumberOfUses
					        PercentUsed = $row.PercentUsed
                        })
                        }
                }
			}
	}

   If ($detailed) 
    {    
        return ($collection) 
    }
   Else 
    { 
        return ($collection | Format-Table -Property *) 
    }
}
}