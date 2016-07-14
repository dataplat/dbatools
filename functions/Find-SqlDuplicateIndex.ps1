Function Find-SqlDuplicateIndex
{
<#
.SYNOPSIS
Find duplicated indexes

.DESCRIPTION
This function will find exactly duplicated indexes on a database and tell how much space you can recover by dropping the index.

For now only support CLUSTERED and NONCLUSTERED indexes

Server
Databases
SchemaName
TableName
IndexName
KeyColumnList
IncludeColumnList
IsDisabled
IndexSizeMB
	
.PARAMETER SqlServer
The SQL Server instance.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.
	
.NOTES 
Original Author: Cláudio Silva (@ClaudioESSilva)
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Find-SqlDuplicateIndex

.EXAMPLE
Find-SqlDuplicateIndex -SqlServer sqlserver2014a 

All user databases present on sqlserver2014a will be verified

.EXAMPLE   
Find-SqlDuplicateIndex -SqlServer sqlserver2014a -SqlCredential $cred
	
All user databases present on sqlserver2014a will be verified using SQL credentials. 
	
.EXAMPLE   
Find-SqlDuplicateIndex -SqlServer sqlserver2014a -Databases db1, db2

Will find duplicate indexes on both db1 and db2 databases
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[object]$SqlCredential
	)
    DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer -SqlCredential $SqlCredential } }
	
	BEGIN
	{
        #$DSduplicatedindex = New-Object System.Data.DataSet
        #$DTduplicatedindex = New-Object System.Data.DataTable

        #$duplicatedindex = New-Object System.Data.DataTable

		$findDuplicateIndexQuery = "WITH CTE_IndexCols AS
(
	SELECT 
				[object_id] AS id
			,index_id AS indid
			,OBJECT_SCHEMA_NAME([object_id]) AS SchemaName
			,OBJECT_NAME([object_id]) AS TableName
			,Name AS IndexName
			,(
				SELECT 
						CASE keyno
							WHEN 0 THEN NULL
							ELSE colid
						END AS [data()]
					FROM sys.sysindexkeys AS k
					WHERE k.id = i.object_id
					AND k.indid = i.index_id
				ORDER BY keyno, colid
				FOR XML path('')
			) AS KeyCols
			,(
				SELECT CASE keyno
							WHEN 0 THEN colid
							ELSE NULL
						END AS [data()]
					FROM sys.sysindexkeys AS k
					WHERE k.id = i.object_id
					AND k.indid = i.index_id
				ORDER BY colid
				FOR XML path('')
			) AS IncCols
	  FROM sys.indexes AS i
),
CTE_IndexSpace AS
(
	SELECT
			 OBJECT_SCHEMA_NAME(i.[object_id]) AS SchemaName 
			,OBJECT_NAME(i.[object_id]) AS TableName
			,i.name AS IndexName
			,i.is_disabled AS IsDisabled
			,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
	  FROM sys.dm_db_partition_stats AS s
		INNER JOIN sys.indexes AS i 
		   ON s.[object_id] = i.[object_id]
		  AND s.index_id = i.index_id
	GROUP BY i.[object_id], i.name, i.is_disabled
)
SELECT 
		 CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
		,CI1.IndexName AS 'Index'
		,CI2.IndexName AS 'ExactDuplicate'
		,CSPC.IndexSizeMB
		,CSPC.IsDisabled
FROM CTE_IndexCols AS CI1
	INNER JOIN CTE_IndexCols AS CI2
	   ON CI1.id = CI2.id
	  AND CI1.indid < CI2.indid
	  AND CI1.KeyCols = CI2.KeyCols
	  AND CI1.IncCols = CI2.IncCols
	INNER JOIN CTE_IndexSpace AS CSPC
	   ON CI1.SchemaName = CSPC.SchemaName
	  AND CI1.TableName = CSPC.TableName
	  AND CI1.IndexName = CSPC.IndexName

                                    "

        Write-Output "Attempting to connect to Sql Server.."
		$sourceserver = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	}
	
	PROCESS
	{
        # Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		
		if ($pipedatabase.Length -gt 0)
		{
			$Source = $pipedatabase[0].parent.name
			$databases = $pipedatabase.name
		}

        if ($databases.Count -eq 0)
        {
            $databases = $sourceserver.Databases | Where-Object {$_.isSystemObject -eq 0 -and $_.Status -ne "Offline"}
        }

        if ($databases.Count -gt 0)
        {
            foreach ($db in $databases)
            {
                try
                {
                    
                    $duplicatedindex = $sourceserver.Databases[$db].ExecuteWithResults($findDuplicateIndexQuery)

                    if ($duplicatedindex.Tables.Count -gt 0)
                    {
                        $indexesToDrop = $duplicatedindex.Tables[0] | Out-GridView -Title "Duplicate Indexes" -PassThru

                        foreach ($index in $indexesToDrop)
                        {
                            Write-Verbose $index.IndexName
                        }
                    }
                    else
                    {
                        Write-Output "No duplicate indexes found!"
                    }
                }
                catch
                {
                    throw $_
                }
            }
        }
        else
        {
            Write-Output "There are no databases to analyse."
        }
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
	}
}