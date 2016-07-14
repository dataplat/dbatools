Function Find-SqlDuplicateIndex
{
<#
.SYNOPSIS
Find duplicate and overlapping indexes

.DESCRIPTION
This function will find exact duplicated and overlapping indexes on a database.
Also tells how much space you can sabe by dropping the index.
We take into account the COMPRESSION used.

You can select the indexes you want to drop on the gridview and by click OK the drop statement will be generated

For now only supported for CLUSTERED and NONCLUSTERED indexes

Output:
    TableName
    IndexName
    KeyCols
    IncludedCols
    IndexSizeMB
    IndexType
    CompressionDesc
    IsDisabled
	
.PARAMETER SqlServer
The SQL Server instance.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER IncludeOverlapping
Allows to see indexes partial duplicate. 
Example: If first key column is the same but one index has included columns and the other not, this will be shown.

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
        [object]$SqlCredential,
        [switch]$IncludeOverlapping
	)
    DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$exactDuplicateQuery = "WITH CTE_IndexCols AS
(
	SELECT 
			 i.[object_id] AS id
			,i.index_id AS indid
			,OBJECT_SCHEMA_NAME(i.[object_id]) AS SchemaName
			,OBJECT_NAME(i.[object_id]) AS TableName
			,Name AS IndexName
			,ISNULL(STUFF((SELECT ', ' + col.NAME + ' ' + CASE 
														WHEN idxCol.is_descending_key = 1 THEN 'DESC'
														ELSE 'ASC'
													END -- Include column order (ASC / DESC)
					FROM sys.index_columns idxCol 
						INNER JOIN sys.columns col 
						   ON idxCol.[object_id] = col.[object_id]
						  AND idxCol.column_id = col.column_id
					WHERE i.[object_id] = idxCol.[object_id]
					  AND i.index_id = idxCol.index_id
					  AND idxCol.is_included_column = 0
					ORDER BY idxCol.key_ordinal
			 FOR XML PATH('')), 1, 2, ''), '') AS KeyCols
			,ISNULL(STUFF((SELECT ', ' + col.NAME + ' ' + CASE 
														WHEN idxCol.is_descending_key = 1 THEN 'DESC'
														ELSE 'ASC'
													END -- Include column order (ASC / DESC)
					FROM sys.index_columns idxCol 
						INNER JOIN sys.columns col 
						   ON idxCol.[object_id] = col.[object_id]
						  AND idxCol.column_id = col.column_id
					WHERE i.[object_id] = idxCol.[object_id]
					  AND i.index_id = idxCol.index_id
					  AND idxCol.is_included_column = 1
					ORDER BY idxCol.key_ordinal
			 FOR XML PATH('')), 1, 2, ''), '') AS IncludedCols
			,i.[type_desc] AS IndexType
            ,i.is_disabled AS IsDisabled
			,p.data_compression_desc AS CompressionDesc
	  FROM sys.indexes AS i
		INNER JOIN sys.partitions p WITH (NOLOCK) 
		   ON i.[object_id] = p.[object_id] 
		  AND i.index_id = p.index_id		
	 WHERE i.[type_desc] IN ('CLUSTERED', 'NONCLUSTERED')
),
CTE_IndexSpace AS
(
	SELECT
			 OBJECT_SCHEMA_NAME(i.[object_id]) AS SchemaName 
			,OBJECT_NAME(i.[object_id]) AS TableName
			,i.name AS IndexName
			,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
	  FROM sys.dm_db_partition_stats AS s
		INNER JOIN sys.indexes AS i 
		   ON s.[object_id] = i.[object_id]
		  AND s.index_id = i.index_id
	GROUP BY i.[object_id], i.name
)
SELECT 
         DB_NAME() AS DatabaseName
		,CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
		,CI1.IndexName
		,CI1.KeyCols
		,CI1.IncludedCols
        ,CI1.IndexType
		,CSPC.IndexSizeMB
		,CI1.CompressionDesc
		,CI1.IsDisabled
FROM CTE_IndexCols AS CI1
	INNER JOIN CTE_IndexSpace AS CSPC
	   ON CI1.SchemaName = CSPC.SchemaName
	  AND CI1.TableName = CSPC.TableName
	  AND CI1.IndexName = CSPC.IndexName
WHERE EXISTS (SELECT 1 
				FROM CTE_IndexCols CI2
			   WHERE CI1.SchemaName = CI2.SchemaName
				 AND CI1.TableName = CI2.TableName
				 AND CI1.KeyCols = CI2.KeyCols
				 AND CI1.IncludedCols = CI2.IncludedCols
				 AND CI1.IndexName <> CI2.IndexName
			 )"

        $overlappingQuery = "WITH CTE_IndexCols AS
(
	SELECT 
			 i.[object_id] AS id
			,i.index_id AS indid
			,OBJECT_SCHEMA_NAME(i.[object_id]) AS SchemaName
			,OBJECT_NAME(i.[object_id]) AS TableName
			,Name AS IndexName
			,ISNULL(STUFF((SELECT ', ' + col.NAME + ' ' + CASE 
														WHEN idxCol.is_descending_key = 1 THEN 'DESC'
														ELSE 'ASC'
													END -- Include column order (ASC / DESC)
					FROM sys.index_columns idxCol 
						INNER JOIN sys.columns col 
						   ON idxCol.[object_id] = col.[object_id]
						  AND idxCol.column_id = col.column_id
					WHERE i.[object_id] = idxCol.[object_id]
					  AND i.index_id = idxCol.index_id
					  AND idxCol.is_included_column = 0
					ORDER BY idxCol.key_ordinal
			 FOR XML PATH('')), 1, 2, ''), '') AS KeyCols
			,ISNULL(STUFF((SELECT ', ' + col.NAME + ' ' + CASE 
														WHEN idxCol.is_descending_key = 1 THEN 'DESC'
														ELSE 'ASC'
													END -- Include column order (ASC / DESC)
					FROM sys.index_columns idxCol 
						INNER JOIN sys.columns col 
						   ON idxCol.[object_id] = col.[object_id]
						  AND idxCol.column_id = col.column_id
					WHERE i.[object_id] = idxCol.[object_id]
					  AND i.index_id = idxCol.index_id
					  AND idxCol.is_included_column = 1
					ORDER BY idxCol.key_ordinal
			 FOR XML PATH('')), 1, 2, ''), '') AS IncludedCols
			,i.[type_desc] AS IndexType
            ,i.is_disabled AS IsDisabled
			,p.data_compression_desc AS CompressionDesc
	  FROM sys.indexes AS i
		INNER JOIN sys.partitions p WITH (NOLOCK) 
		   ON i.[object_id] = p.[object_id] 
		  AND i.index_id = p.index_id		
	 WHERE i.[type_desc] IN ('CLUSTERED', 'NONCLUSTERED')
),
CTE_IndexSpace AS
(
	SELECT
			 OBJECT_SCHEMA_NAME(i.[object_id]) AS SchemaName 
			,OBJECT_NAME(i.[object_id]) AS TableName
			,i.name AS IndexName
			,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
	  FROM sys.dm_db_partition_stats AS s
		INNER JOIN sys.indexes AS i 
		   ON s.[object_id] = i.[object_id]
		  AND s.index_id = i.index_id
	GROUP BY i.[object_id], i.name
)
SELECT 
		 DB_NAME() AS DatabaseName
        ,CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
		,CI1.IndexName
		,CI1.KeyCols
		,CI1.IncludedCols
        ,CI1.IndexType
		,CSPC.IndexSizeMB
		,CI1.CompressionDesc
		,CI1.IsDisabled
FROM CTE_IndexCols AS CI1
	INNER JOIN CTE_IndexSpace AS CSPC
	   ON CI1.SchemaName = CSPC.SchemaName
	  AND CI1.TableName = CSPC.TableName
	  AND CI1.IndexName = CSPC.IndexName
WHERE EXISTS (SELECT 1
				FROM CTE_IndexCols AS CI2
			   WHERE  CI1.SchemaName = CI2.SchemaName
			AND CI1.TableName = CI2.TableName
			  AND (
						(CI1.KeyCols like CI2.KeyCols + '%' and SUBSTRING(CI1.KeyCols,LEN(CI2.KeyCols)+1,1) = ' ')
					 OR (CI2.KeyCols like CI1.KeyCols + '%' and SUBSTRING(CI2.KeyCols,LEN(CI1.KeyCols)+1,1) = ' ')
				  )
				AND CI1.IndexName <> CI2.IndexName
			)"

        Write-Output "Attempting to connect to Sql Server.."
		$sourceserver = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	}
	
	PROCESS
	{
        if ($sourceserver.versionMajor -lt 10)
		{
			throw "This function does not support versions lower than SQL Server 2008 (v10)"
		}

        # Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		
		if ($pipedatabase.Length -gt 0)
		{
			$Source = $pipedatabase[0].parent.name
			$databases = $pipedatabase.name
		}

        if ($databases.Count -eq 0)
        {
            $databases = ($sourceserver.Databases | Where-Object {$_.isSystemObject -eq 0 -and $_.Status -ne "Offline"}).Name
        }

        if ($databases.Count -gt 0)
        {
            foreach ($db in $databases)
            {
                try
                {
                    $query = if ($IncludeOverlapping) {$overlappingQuery} else {$exactDuplicateQuery}

                    $duplicatedindex = $sourceserver.Databases[$db].ExecuteWithResults($query)

                    $scriptGenerated = $false

                    if ($duplicatedindex.Tables.Count -gt 0)
                    {
                        $indexesToDrop = $duplicatedindex.Tables[0] | Out-GridView -Title "Duplicate Indexes on $($db) database - Choose indexes to generate DROP script" -PassThru

                        #When only 1 line selected, the count does not work
                        if ($indexesToDrop.Count -gt 0 -or !([string]::IsNullOrEmpty($indexesToDrop)))
                        {
                            $sqlDropScript = "/*`r`n"
                            $sqlDropScript += "`tScript generated @ $(Get-Date -format "yyyy-MM-dd HH:mm:ss.ms")`r`n"
                            $sqlDropScript += "`tDatabase: $($db)`r`n"
                            $sqlDropScript += if (!$IncludeOverlapping)
                                              {
                                                "`tConfirm that you have choosen the right indexes before execute the drop script`r`n"
                                              }
                                              else
                                              {
                                                "`tChoose wisely when dropping a partial duplicate index. You may want to check index usage before drop it.`r`n"
                                              }
                            $sqlDropScript += "*/`r`n"

                            foreach ($index in $indexesToDrop)
                            {
                                $sqlDropScript += "USE [$($index.DatabaseName)]`r`n"
                                $sqlDropScript += "GO`r`n"
                                $sqlDropScript += "IF EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('$($index.TableName)') AND name = '$($index.IndexName)')`r`n"
                                $sqlDropScript += "    DROP INDEX $($index.TableName).$($index.IndexName)`r`n"
                                $sqlDropScript += "GO`r`n`r`n"
                            }

                            Write-Output $sqlDropScript

                            $scriptGenerated = $true
                        }
                        if ($scriptGenerated)
                        {
                            Write-Warning "Confirm the generated script before execute!"
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