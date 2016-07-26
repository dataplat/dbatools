Function Find-SqlDuplicateIndex
{
<#
.SYNOPSIS
Find duplicate and overlapping indexes

.DESCRIPTION
This command will help you to find duplicate and overlapping indexes on a database or a list of databases

When 2008+ filtered property also come to comparison
Also tells how much space you can save by dropping the index.
We show the type of compression so you can make a more considered decision.
For now only supported for CLUSTERED and NONCLUSTERED indexes

You can select the indexes you want to drop on the gridview and by click OK the drop statement will be generated.

Output:
    TableName
    IndexName
    KeyCols
    IncludedCols
    IndexSizeMB
    IndexType
    CompressionDesc (When 2008+)
    NumberRows
    IsDisabled
    IsFiltered (When 2008+)
	
.PARAMETER SqlServer
The SQL Server instance.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER IncludeOverlapping
Allows to see indexes partial duplicate. 
Example: If first key column is the same but one index has included columns and the other not, this will be shown.

.PARAMETER FilePath
The file to write to.

.PARAMETER NoClobber
Do not overwrite file
	
.PARAMETER Append
Append to file

.PARAMETER Force
Instead of export or output the script, it runs performing the drop instruction

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
Find-SqlDuplicateIndex -SqlServer sql2005 -FilePath C:\temp\sql2005-DuplicateIndexes.sql

Exports SQL for the duplicate indexes in server "sql2005" choosen on grid-view and writes them to the file "C:\temp\sql2005-DuplicateIndexes.sql"

.EXAMPLE
Find-SqlDuplicateIndex -SqlServer sql2005 -FilePath C:\temp\sql2005-DuplicateIndexes.sql -Append

Exports SQL for the duplicate indexes in server "sql2005" choosen on grid-view and writes/appends them to the file "C:\temp\sql2005-DuplicateIndexes.sql"
	
.EXAMPLE   
Find-SqlDuplicateIndex -SqlServer sqlserver2014a -SqlCredential $cred
	
Will find exact duplicate indexes on all user databases present on sqlserver2014a will be verified using SQL credentials. 
	
.EXAMPLE   
Find-SqlDuplicateIndex -SqlServer sqlserver2014a -Databases db1, db2

Will find exact duplicate indexes on both db1 and db2 databases

.EXAMPLE   
Find-SqlDuplicateIndex -SqlServer sqlserver2014a -IncludeOverlapping

Will find exact duplicate or overlapping indexes on all user databases 
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
        [object]$SqlCredential,
        [switch]$IncludeOverlapping,
        [Alias("OutFile", "Path")]
		[string]$FilePath,
        [switch]$NoClobber,
		[switch]$Append,
        [switch]$Force
	)
    DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer -SqlCredential $SqlCredential } }
	
	BEGIN
	{
        $exactDuplicateQuery2005 = "WITH CTE_IndexCols AS
(
	SELECT 
			 i.[object_id]
			,i.index_id
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
	  FROM sys.indexes AS i
	 WHERE i.index_id > 0 -- Exclude HEAPS
	   AND i.[type_desc] IN ('CLUSTERED', 'NONCLUSTERED')
	   AND OBJECT_SCHEMA_NAME(i.[object_id]) <> 'sys'
),
CTE_IndexSpace AS
(
SELECT
			 s.[object_id]
			,s.index_id
			,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
			,SUM(p.[rows]) AS NumberRows
	  FROM sys.dm_db_partition_stats AS s
		INNER JOIN sys.partitions p WITH (NOLOCK) 
		   ON s.[partition_id] = p.[partition_id]
		  AND s.[object_id] = p.[object_id] 
		  AND s.index_id = p.index_id	
	  WHERE s.index_id > 0 -- Exclude HEAPS
	    AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
	GROUP BY s.[object_id], s.index_id
)
SELECT 
         DB_NAME() AS DatabaseName
		,CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
		,CI1.IndexName
		,CI1.KeyCols
		,CI1.IncludedCols
        ,CI1.IndexType
		,CSPC.IndexSizeMB
		,CSPC.NumberRows
		,CI1.IsDisabled
FROM CTE_IndexCols AS CI1
	INNER JOIN CTE_IndexSpace AS CSPC
	   ON CI1.[object_id] = CSPC.[object_id]
	  AND CI1.index_id = CSPC.index_id
WHERE EXISTS (SELECT 1 
				FROM CTE_IndexCols CI2
			   WHERE CI1.SchemaName = CI2.SchemaName
				 AND CI1.TableName = CI2.TableName
				 AND CI1.KeyCols = CI2.KeyCols
				 AND CI1.IncludedCols = CI2.IncludedCols
				 AND CI1.IndexName <> CI2.IndexName
			 )"

        $overlappingQuery2005 = "WITH CTE_IndexCols AS
(
	SELECT 
			 i.[object_id]
			,i.index_id
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
	  FROM sys.indexes AS i
	 WHERE i.index_id > 0 -- Exclude HEAPS
	   AND i.[type_desc] IN ('CLUSTERED', 'NONCLUSTERED')
	   AND OBJECT_SCHEMA_NAME(i.[object_id]) <> 'sys'
),
CTE_IndexSpace AS
(
SELECT
			 s.[object_id]
			,s.index_id
			,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
			,SUM(p.[rows]) AS NumberRows
	  FROM sys.dm_db_partition_stats AS s
		INNER JOIN sys.partitions p WITH (NOLOCK) 
		   ON s.[partition_id] = p.[partition_id]
		  AND s.[object_id] = p.[object_id] 
		  AND s.index_id = p.index_id	
	  WHERE s.index_id > 0 -- Exclude HEAPS
	    AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
	GROUP BY s.[object_id], s.index_id
)
SELECT 
         DB_NAME() AS DatabaseName
		,CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
		,CI1.IndexName
		,CI1.KeyCols
		,CI1.IncludedCols
        ,CI1.IndexType
		,CSPC.IndexSizeMB
		,CSPC.NumberRows
		,CI1.IsDisabled
FROM CTE_IndexCols AS CI1
	INNER JOIN CTE_IndexSpace AS CSPC
	   ON CI1.[object_id] = CSPC.[object_id]
	  AND CI1.index_id = CSPC.index_id
WHERE EXISTS (SELECT 1 
				FROM CTE_IndexCols CI2
			   WHERE CI1.SchemaName = CI2.SchemaName
				 AND CI1.TableName = CI2.TableName
				 AND (
							(CI1.KeyCols like CI2.KeyCols + '%' and SUBSTRING(CI1.KeyCols,LEN(CI2.KeyCols)+1,1) = ' ')
						 OR (CI2.KeyCols like CI1.KeyCols + '%' and SUBSTRING(CI2.KeyCols,LEN(CI1.KeyCols)+1,1) = ' ')
					 )
				 AND CI1.IndexName <> CI2.IndexName
			 )"

        # Support Compression 2008+
		$exactDuplicateQuery = "WITH CTE_IndexCols AS
(
	SELECT 
			 i.[object_id]
			,i.index_id
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
			,i.has_filter AS IsFiltered
	  FROM sys.indexes AS i
	 WHERE i.index_id > 0 -- Exclude HEAPS
	   AND i.[type_desc] IN ('CLUSTERED', 'NONCLUSTERED')
	   AND OBJECT_SCHEMA_NAME(i.[object_id]) <> 'sys'
),
CTE_IndexSpace AS
(
SELECT
			 s.[object_id]
			,s.index_id
			,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
			,SUM(p.[rows]) AS NumberRows
			,p.data_compression_desc AS CompressionDesc
	  FROM sys.dm_db_partition_stats AS s
		INNER JOIN sys.partitions p WITH (NOLOCK) 
		   ON s.[partition_id] = p.[partition_id]
		  AND s.[object_id] = p.[object_id] 
		  AND s.index_id = p.index_id	
	  WHERE s.index_id > 0 -- Exclude HEAPS
	    AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
	GROUP BY s.[object_id], s.index_id, p.data_compression_desc
)
SELECT 
         DB_NAME() AS DatabaseName
		,CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
		,CI1.IndexName
		,CI1.KeyCols
		,CI1.IncludedCols
        ,CI1.IndexType
		,CSPC.IndexSizeMB
		,CSPC.CompressionDesc
		,CSPC.NumberRows
		,CI1.IsDisabled
		,CI1.IsFiltered
FROM CTE_IndexCols AS CI1
	INNER JOIN CTE_IndexSpace AS CSPC
	   ON CI1.[object_id] = CSPC.[object_id]
	  AND CI1.index_id = CSPC.index_id
WHERE EXISTS (SELECT 1 
				FROM CTE_IndexCols CI2
			   WHERE CI1.SchemaName = CI2.SchemaName
				 AND CI1.TableName = CI2.TableName
				 AND CI1.KeyCols = CI2.KeyCols
				 AND CI1.IncludedCols = CI2.IncludedCols
				 AND CI1.IsFiltered = CI2.IsFiltered
				 AND CI1.IndexName <> CI2.IndexName
			 )"

        $overlappingQuery = "WITH CTE_IndexCols AS
(
	SELECT 
			 i.[object_id]
			,i.index_id
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
			,i.has_filter AS IsFiltered
	  FROM sys.indexes AS i
	 WHERE i.index_id > 0 -- Exclude HEAPS
	   AND i.[type_desc] IN ('CLUSTERED', 'NONCLUSTERED')
	   AND OBJECT_SCHEMA_NAME(i.[object_id]) <> 'sys'
),
CTE_IndexSpace AS
(
SELECT
			 s.[object_id]
			,s.index_id
			,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
			,SUM(p.[rows]) AS NumberRows
			,p.data_compression_desc AS CompressionDesc
	  FROM sys.dm_db_partition_stats AS s
		INNER JOIN sys.partitions p WITH (NOLOCK) 
		   ON s.[partition_id] = p.[partition_id]
		  AND s.[object_id] = p.[object_id] 
		  AND s.index_id = p.index_id	
	  WHERE s.index_id > 0 -- Exclude HEAPS
	    AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
	GROUP BY s.[object_id], s.index_id, p.data_compression_desc
)
SELECT 
         DB_NAME() AS DatabaseName
		,CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
		,CI1.IndexName
		,CI1.KeyCols
		,CI1.IncludedCols
        ,CI1.IndexType
		,CSPC.IndexSizeMB
		,CSPC.CompressionDesc
		,CSPC.NumberRows
		,CI1.IsDisabled
		,CI1.IsFiltered
FROM CTE_IndexCols AS CI1
	INNER JOIN CTE_IndexSpace AS CSPC
	   ON CI1.[object_id] = CSPC.[object_id]
	  AND CI1.index_id = CSPC.index_id
WHERE EXISTS (SELECT 1 
				FROM CTE_IndexCols CI2
			   WHERE CI1.SchemaName = CI2.SchemaName
				 AND CI1.TableName = CI2.TableName
				 AND (
							(CI1.KeyCols like CI2.KeyCols + '%' and SUBSTRING(CI1.KeyCols,LEN(CI2.KeyCols)+1,1) = ' ')
						 OR (CI2.KeyCols like CI1.KeyCols + '%' and SUBSTRING(CI2.KeyCols,LEN(CI1.KeyCols)+1,1) = ' ')
					 )
				 AND CI1.IsFiltered = CI2.IsFiltered
				 AND CI1.IndexName <> CI2.IndexName
			 )"

        $sqlGO = "GO`r`n"
        $sqlFinalGO = "GO`r`n`r`n"
        $sqlUSE = ""

        if ($FilePath.Length -gt 0)
		{
			$directory = Split-Path $FilePath
			$exists = Test-Path $directory
			
			if ($exists -eq $false)
			{
				throw "Parent directory $directory does not exist"
			}
		}

        Write-Output "Attempting to connect to Sql Server.."
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	}
	
	PROCESS
	{
        if ($server.versionMajor -lt 9)
		{
			throw "This function does not support versions lower than SQL Server 2005 (v9)"
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
            $databases = ($server.Databases | Where-Object {$_.isSystemObject -eq 0 -and $_.Status -ne "Offline"}).Name
        }

        if ($databases.Count -gt 0)
        {
            foreach ($db in $databases)
            {
                try
                {
                    Write-Output "Getting indexes from database '$db'"

                    $query = if ($server.versionMajor -eq 9)
                             {
                                if ($IncludeOverlapping){$overlappingQuery2005} else {$exactDuplicateQuery2005}
                             }
                             else 
                             {
                                if ($IncludeOverlapping) {$overlappingQuery} else {$exactDuplicateQuery}
                             }

                    $duplicatedindex = $server.Databases[$db].ExecuteWithResults($query)

                    $scriptGenerated = $false

                    if ($duplicatedindex.Tables[0].Rows.Count -gt 0)
                    {
                        if ($Force)
                        {
                            $indexesToDrop = $duplicatedindex.Tables[0] | Out-GridView -Title "Duplicate Indexes on $($db) database - Choose indexes to DROP! (-Force was specified)" -PassThru
                        }
                        else
                        {
                            $indexesToDrop = $duplicatedindex.Tables[0] | Out-GridView -Title "Duplicate Indexes on $($db) database - Choose indexes to generate DROP script" -PassThru
                        }

                        #When only 1 line selected, the count does not work
                        if ($indexesToDrop.Count -gt 0 -or !([string]::IsNullOrEmpty($indexesToDrop)))
                        {
                            #reset to #Yes
                            $result = 0

                            if ($duplicatedindex.Tables[0].Rows.Count -eq $indexesToDrop.Count)
                            {
                                $title = "Indexes to drop on databases '$db':"
                                $message = "You will generate drop statements to all indexes.`r`nPerhaps you want to keep at least one.`r`nDo you wish to generate the script anyway? (Y/N)"
                                $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
                                $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
                                $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                                $result = $host.ui.PromptForChoice($title, $message, $options, 0)
                            }

                            if ($result -eq 0) #default OR answer = YES
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
                                    if ($FilePath.Length -gt 0)
				                    {
					                    Write-Output "Exporting $($index.TableName).$($index.IndexName)"
				                    }

                                    if ($Force)
                                    {
                                        $sqlDropScript += "USE [$($index.DatabaseName)]`r`n"
                                        $sqlDropScript += "IF EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('$($index.TableName)') AND name = '$($index.IndexName)')`r`n"
                                        $sqlDropScript += "    DROP INDEX $($index.TableName).$($index.IndexName)`r`n`r`n"

                                        if ($Pscmdlet.ShouldProcess($db, "Dropping index '$($index.IndexName)' on table '$($index.TableName)' using -Force"))
				                        {
                                            $server.Databases[$db].ExecuteNonQuery($sqlDropScript) | Out-Null
                                            Write-Output "Index '$($index.IndexName)' on table '$($index.TableName)' dropped"
                                        }
                                    }
                                    else
                                    {
                                        $sqlDropScript += "USE [$($index.DatabaseName)]`r`n"
                                        $sqlDropScript += $sqlGO
                                        $sqlDropScript += "IF EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('$($index.TableName)') AND name = '$($index.IndexName)')`r`n"
                                        $sqlDropScript += "    DROP INDEX $($index.TableName).$($index.IndexName)`r`n"
                                        $sqlDropScript += $sqlFinalGO
                                    }
                                }

                                if (!$Force)
                                {
                                    if ($FilePath.Length -gt 0)
		                            {
			                            $sqlDropScript | Out-File -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
		                            }
                                    else
                                    {
                                        Write-Output $sqlDropScript
                                    }
                                    $scriptGenerated = $true
                                }

                                
                            }
                            else #answer = no
                            {
                                Write-Warning "Script will not be generated for database '$db'"
                            }
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

            if ($scriptGenerated)
            {
                Write-Warning "Confirm the generated script before execute!"
            }
            if ($FilePath.Length -gt 0)
            {
                Write-Output "Script generated to $FilePath"
            }
        }
        else
        {
            Write-Output "There are no databases to analyse."
        }
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
	}
}