Function Find-DbaStoredProcedure
{
<#
.SYNOPSIS
Returns all stored procedures that contain a specific case-insensitive string or regex pattern.

.DESCRIPTION
This function can either run against specific databases or all databases searching all user or user and system stored procedures.
	
.PARAMETER SqlInstance
SQLServer name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, currend Windows login will be used.

.PARAMETER Databases
Set the specific database/s that you wish to search in.

.PARAMETER Pattern
String pattern that you want to search for in the stored procedure textbody

.PARAMETER IncludeSystemObjects
By default, system stored proceures are ignored but you can include them within the search using this parameter.
	
Warning - this will likely make it super slow if you run it on all databases.

.PARAMETER IncludeSystemDatabases
By default system databases are ignored but you can include them within the search using this parameter

.NOTES 
Original Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Find-DbaStoredProcedure

.EXAMPLE
Find-DbaStoredProcedure -SqlInstance DEV01 -Pattern whatever

Searches all user databases stored procedures for "whatever" in the textbody
	
.EXAMPLE
Find-DbaStoredProcedure -SqlInstance sql2016 -Pattern '\w+@\w+\.\w+'

Searches all databases for all stored procedures that contain a valid email pattern in the textbody

.EXAMPLE
Find-DbaStoredProcedure -SqlInstance DEV01 -Databases MyDB -Pattern 'some string' -Verbose

Searches in "mydb" database stored procedures for "some string" in the textbody

.EXAMPLE
Find-DbaStoredProcedure -SqlInstance sql2016 -Databases MyDB -Pattern RUNTIME -IncludeSystemObjects

Searches in "mydb" database stored procedures for "runtime" in the textbody

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer", "SqlServers")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[parameter(Mandatory = $true)]
		[string]$Pattern,
		[switch]$IncludeSystemObjects,
		[switch]$IncludeSystemDatabases
	)
	DynamicParam
	{
		if ($SqlInstance)
		{
			Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $SqlCredential
		}
	}
	begin
	{
		$databases = $psboundparameters.Databases
		$sql = "SELECT p.name, m.definition as TextBody FROM sys.sql_modules m, sys.procedures p WHERE m.object_id = p.object_id"
		if (!$IncludeSystemObjects) { $sql = "$sql AND p.is_ms_shipped = 0" }
		$everyserverspcount = 0
	}
	process
	{
		foreach ($Instance in $SqlInstance)
		{
			try
			{
				Write-Verbose "Connecting to $Instance"
				$server = Connect-SqlServer -SqlServer $Instance -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Failed to connect to: $Instance"
				continue
			}
			
			if ($server.versionMajor -lt 9)
			{
				Write-Warning "This command only supports SQL Server 2005 and above."
				Continue
			}
			
			if ($IncludeSystemDatabases)
			{
				$dbs = $server.Databases | Where-Object { $_.Status -eq "normal" }
			}
			else
			{
				$dbs = $server.Databases | Where-Object { $_.Status -eq "normal" -and $_.IsSystemObject -eq $false }
			}
			
			if ($databases.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $databases -contains $_.Name }
			}
			
			$totalcount = 0
			$dbcount = $dbs.count
			foreach ($db in $dbs)
			{
				Write-Verbose "Searching database $db"

				# If system objects aren't needed, find stored procedure text using SQL
				# This prevents SMO from having to enumerate
				
				if (!$IncludeSystemObjects)
				{
					Write-Debug $sql
					$rows = $db.ExecuteWithResults($sql).Tables.Rows
					$sproccount = 0
					
					foreach ($row in $rows)
					{
						$totalcount++; $sproccount++; $everyserverspcount++
						
						$proc = $row.name
						
						Write-Debug "Looking in StoredProcedure: $proc TextBody for $pattern"
						if ($row.TextBody -match $Pattern)
						{
							$sp = $db.StoredProcedures | Where-Object name -eq $row.name

                            $StoredProcedureText = $sp.TextBody.split("`n")
                            $spTextFound = $StoredProcedureText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

							[PSCustomObject]@{
								ComputerName = $server.NetName
								SqlInstance = $server.ServiceName
								Database = $db.name
								Name = $sp.Name
								Owner = $sp.Owner
								IsSystemObject = $sp.IsSystemObject
								CreateDate = $sp.CreateDate
								LastModified = $sp.DateLastModified
								StoredProcedureTextFound = $spTextFound -join "`n"
								StoredProcedure = $sp
								StoredProcedureFullText = $sp.TextBody
							} | Select-DefaultView -ExcludeProperty StoredProcedure, StoredProcedureFullText
						}
					}
				}
				else
				{
					$storedprocedures = $db.StoredProcedures
					
					foreach ($sp in $storedprocedures)
					{
						$totalcount++; $sproccount++;  $everyserverspcount++
						$proc = $sp.Name
						
						Write-Debug "Looking in StoredProcedure: $proc TextBody for $pattern"
						if ($sp.TextBody -match $Pattern)
						{

                            $StoredProcedureText = $sp.TextBody.split("`n")
                            $spTextFound = $StoredProcedureText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }
    
							[PSCustomObject]@{
								ComputerName = $server.NetName
								SqlInstance = $server.ServiceName
								Database = $db.name
								Name = $sp.Name
								Owner = $sp.Owner
								IsSystemObject = $sp.IsSystemObject
								CreateDate = $sp.CreateDate
								LastModified = $sp.DateLastModified
								StoredProcedureTextFound = $spTextFound -join "`n"
								StoredProcedure = $sp
								StoredProcedureFullText = $sp.TextBody
							} | Select-DefaultView -ExcludeProperty StoredProcedure, StoredProcedureFullText
						}
					}
				}
				Write-Verbose "Evaluated $sproccount stored procedures in $db"
			}
			Write-Verbose "Evaluated $totalcount total stored procedures in $dbcount databases"
		}
	}
	end
	{
		Write-Verbose "Evaluated $everyserverspcount total stored procedures"
	}
}
