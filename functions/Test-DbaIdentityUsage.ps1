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
        [switch]$NoSystemDb
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

        $sql = "Select DB_NAME(), Object_Name(id.object_id) As [table_name]
        , id.name As [column_name]
        , t.name As [data_type]
        , Cast(id.last_value As bigint) As [last_value]
        , Case 
            When t.name = 'tinyint'   Then 255 
            When t.name = 'smallint'  Then 32767 
            When t.name = 'int'       Then 2147483647 
            When t.name = 'bigint'    Then 9223372036854775807
          End As [max_value]
		, convert(bigint,id.last_value) / Case 
            When t.name = 'tinyint'   Then 255 
            When t.name = 'smallint'  Then 32767 
            When t.name = 'int'       Then 2147483647 
            When t.name = 'bigint'    Then 9223372036854775807
          End * 100 As [percentUsed]
    From sys.identity_columns As id
    Join sys.types As t
        On id.system_type_id = t.system_type_id
    Where id.last_value Is Not Null
    Order by PercentUsed DESC"

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
                

                foreach ($row in $resultTable)
                {

                    if ($row.percentUsed -ge $threshold)
                        {
                        $percentUsed = [Math]::Round($row.percentUsed,2)

				        $null = $collection.Add(
                        [PSCustomObject]@{
					        Server = $server.name
					        Database = $db.name
					        Table = $row.table_name
					        Column = $row.column_name
					        DataType = $row.data_type
					        Last_Value = $row.last_value
					        Max_Value = $row.max_value
					        PercentUsed = $percentUsed
                        })
                        }
                }
			}
	}

   return ($collection | Format-Table)
}
}