function Find-DbaDuplicateIndex {
	<#
		.SYNOPSIS
			Find duplicate and overlapping indexes.

		.DESCRIPTION
			This command will help you to find duplicate and overlapping indexes on a database or a list of databases.

			On SQL Server 2008 and higher, the IsFiltered property will also be checked

			Also tells how much space you can save by dropping the index.

			We show the type of compression so you can make a more considered decision.

			For now only supports CLUSTERED and NONCLUSTERED indexes.

			You can select the indexes you want to drop on the gridview and when clicking OK, the DROP statement will be generated.

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
			
        .PARAMETER SqlInstance
			The SQL Server you want to check for duplicate indexes.
        
        .PARAMETER SqlCredential
 			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$cred = Get-Credential, then pass $cred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Database
			The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

		.PARAMETER IncludeOverlapping
			If this switch is enabled, indexes which are partially duplicated will be returned. 

			Example: If the first key column is the same between two indexes, but one has included columns and the other not, this will be shown.

		.PARAMETER FilePath
			Specifies the path of a file to write the DROP statements to.

		.PARAMETER NoClobber
			If this switch is enabled, the output file will not be overwritten.
			
		.PARAMETER Append
			If this switch is enabled, content will be appended to the output file.

		.PARAMETER WhatIf
			If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

		.PARAMETER Confirm
			If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

		.PARAMETER Force
			If this switch is enabled, the DROP statement(s) will be executed instead of being written to the output file.

		.PARAMETER Silent
			If this switch is enabled, the internal messaging functions will be silenced.

		.NOTES 
			Original Author: Claudio Silva (@ClaudioESSilva)
			dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
			Copyright (C) 2016 Chrissy LeMaire
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Find-DbaDuplicateIndex

		.EXAMPLE
			Find-DbaDuplicateIndex -SqlInstance sql2005 -FilePath C:\temp\sql2005-DuplicateIndexes.sql

			Generates SQL statements to drop the selected duplicate indexes in server "sql2005" and writes them to the file "C:\temp\sql2005-DuplicateIndexes.sql"

		.EXAMPLE
			Find-DbaDuplicateIndex -SqlInstance sql2005 -FilePath C:\temp\sql2005-DuplicateIndexes.sql -Append

			Generates SQL statements to drop the selected duplicate indexes and writes/appends them to the file "C:\temp\sql2005-DuplicateIndexes.sql"
			
		.EXAMPLE   
			Find-DbaDuplicateIndex -SqlInstance sqlserver2014a -SqlCredential $cred
				
			Finds exact duplicate indexes on all user databases present on sqlserver2014a, using SQL authentication.
			
		.EXAMPLE   
			Find-DbaDuplicateIndex -SqlInstance sqlserver2014a -Database db1, db2

			Finds exact duplicate indexes on the db1 and db2 databases.

		.EXAMPLE   
			Find-DbaDuplicateIndex -SqlInstance sqlserver2014a -IncludeOverlapping

			Finds both duplicate and overlapping indexes on all user databases.
			
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[switch]$IncludeOverlapping,
		[Alias("OutFile", "Path")]
		[string]$FilePath,
		[switch]$NoClobber,
		[switch]$Append,
		[switch]$Force
	)

	begin {
		$exactDuplicateQuery2005 = "
			WITH CTE_IndexCols
			AS (
				SELECT i.[object_id]
					,i.index_id
					,OBJECT_SCHEMA_NAME(i.[object_id]) AS SchemaName
					,OBJECT_NAME(i.[object_id]) AS TableName
					,NAME AS IndexName
					,ISNULL(STUFF((
								SELECT ', ' + col.NAME + ' ' + CASE 
										WHEN idxCol.is_descending_key = 1
											THEN 'DESC'
										ELSE 'ASC'
										END -- Include column order (ASC / DESC)
								FROM sys.index_columns idxCol
								INNER JOIN sys.columns col ON idxCol.[object_id] = col.[object_id]
									AND idxCol.column_id = col.column_id
								WHERE i.[object_id] = idxCol.[object_id]
									AND i.index_id = idxCol.index_id
									AND idxCol.is_included_column = 0
								ORDER BY idxCol.key_ordinal
								FOR XML PATH('')
								), 1, 2, ''), '') AS KeyCols
					,ISNULL(STUFF((
								SELECT ', ' + col.NAME + ' ' + CASE 
										WHEN idxCol.is_descending_key = 1
											THEN 'DESC'
										ELSE 'ASC'
										END -- Include column order (ASC / DESC)
								FROM sys.index_columns idxCol
								INNER JOIN sys.columns col ON idxCol.[object_id] = col.[object_id]
									AND idxCol.column_id = col.column_id
								WHERE i.[object_id] = idxCol.[object_id]
									AND i.index_id = idxCol.index_id
									AND idxCol.is_included_column = 1
								ORDER BY idxCol.key_ordinal
								FOR XML PATH('')
								), 1, 2, ''), '') AS IncludedCols
					,i.[type_desc] AS IndexType
					,i.is_disabled AS IsDisabled
				FROM sys.indexes AS i
				WHERE i.index_id > 0 -- Exclude HEAPS
					AND i.[type_desc] IN (
						'CLUSTERED'
						,'NONCLUSTERED'
						)
					AND OBJECT_SCHEMA_NAME(i.[object_id]) <> 'sys'
				)
				,CTE_IndexSpace
			AS (
				SELECT s.[object_id]
					,s.index_id
					,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
					,SUM(p.[rows]) AS NumberRows
				FROM sys.dm_db_partition_stats AS s
				INNER JOIN sys.partitions p WITH (NOLOCK) ON s.[partition_id] = p.[partition_id]
					AND s.[object_id] = p.[object_id]
					AND s.index_id = p.index_id
				WHERE s.index_id > 0 -- Exclude HEAPS
					AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
				GROUP BY s.[object_id]
					,s.index_id
				)
			SELECT DB_NAME() AS DatabaseName
				,CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
				,CI1.IndexName
				,CI1.KeyCols
				,CI1.IncludedCols
				,CI1.IndexType
				,CSPC.IndexSizeMB
				,CSPC.NumberRows
				,CI1.IsDisabled
			FROM CTE_IndexCols AS CI1
			INNER JOIN CTE_IndexSpace AS CSPC ON CI1.[object_id] = CSPC.[object_id]
				AND CI1.index_id = CSPC.index_id
			WHERE EXISTS (
					SELECT 1
					FROM CTE_IndexCols CI2
					WHERE CI1.SchemaName = CI2.SchemaName
						AND CI1.TableName = CI2.TableName
						AND CI1.KeyCols = CI2.KeyCols
						AND CI1.IncludedCols = CI2.IncludedCols
						AND CI1.IndexName <> CI2.IndexName
					)"

		$overlappingQuery2005 = "
			WITH CTE_IndexCols
			AS (
				SELECT i.[object_id]
					,i.index_id
					,OBJECT_SCHEMA_NAME(i.[object_id]) AS SchemaName
					,OBJECT_NAME(i.[object_id]) AS TableName
					,NAME AS IndexName
					,ISNULL(STUFF((
								SELECT ', ' + col.NAME + ' ' + CASE 
										WHEN idxCol.is_descending_key = 1
											THEN 'DESC'
										ELSE 'ASC'
										END -- Include column order (ASC / DESC)
								FROM sys.index_columns idxCol
								INNER JOIN sys.columns col ON idxCol.[object_id] = col.[object_id]
									AND idxCol.column_id = col.column_id
								WHERE i.[object_id] = idxCol.[object_id]
									AND i.index_id = idxCol.index_id
									AND idxCol.is_included_column = 0
								ORDER BY idxCol.key_ordinal
								FOR XML PATH('')
								), 1, 2, ''), '') AS KeyCols
					,ISNULL(STUFF((
								SELECT ', ' + col.NAME + ' ' + CASE 
										WHEN idxCol.is_descending_key = 1
											THEN 'DESC'
										ELSE 'ASC'
										END -- Include column order (ASC / DESC)
								FROM sys.index_columns idxCol
								INNER JOIN sys.columns col ON idxCol.[object_id] = col.[object_id]
									AND idxCol.column_id = col.column_id
								WHERE i.[object_id] = idxCol.[object_id]
									AND i.index_id = idxCol.index_id
									AND idxCol.is_included_column = 1
								ORDER BY idxCol.key_ordinal
								FOR XML PATH('')
								), 1, 2, ''), '') AS IncludedCols
					,i.[type_desc] AS IndexType
					,i.is_disabled AS IsDisabled
				FROM sys.indexes AS i
				WHERE i.index_id > 0 -- Exclude HEAPS
					AND i.[type_desc] IN (
						'CLUSTERED'
						,'NONCLUSTERED'
						)
					AND OBJECT_SCHEMA_NAME(i.[object_id]) <> 'sys'
				)
				,CTE_IndexSpace
			AS (
				SELECT s.[object_id]
					,s.index_id
					,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
					,SUM(p.[rows]) AS NumberRows
				FROM sys.dm_db_partition_stats AS s
				INNER JOIN sys.partitions p WITH (NOLOCK) ON s.[partition_id] = p.[partition_id]
					AND s.[object_id] = p.[object_id]
					AND s.index_id = p.index_id
				WHERE s.index_id > 0 -- Exclude HEAPS
					AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
				GROUP BY s.[object_id]
					,s.index_id
				)
			SELECT DB_NAME() AS DatabaseName
				,CI1.SchemaName + '.' + CI1.TableName AS 'TableName'
				,CI1.IndexName
				,CI1.KeyCols
				,CI1.IncludedCols
				,CI1.IndexType
				,CSPC.IndexSizeMB
				,CSPC.NumberRows
				,CI1.IsDisabled
			FROM CTE_IndexCols AS CI1
			INNER JOIN CTE_IndexSpace AS CSPC ON CI1.[object_id] = CSPC.[object_id]
				AND CI1.index_id = CSPC.index_id
			WHERE EXISTS (
					SELECT 1
					FROM CTE_IndexCols CI2
					WHERE CI1.SchemaName = CI2.SchemaName
						AND CI1.TableName = CI2.TableName
						AND (
							(
								CI1.KeyCols LIKE CI2.KeyCols + '%'
								AND SUBSTRING(CI1.KeyCols, LEN(CI2.KeyCols) + 1, 1) = ' '
								)
							OR (
								CI2.KeyCols LIKE CI1.KeyCols + '%'
								AND SUBSTRING(CI2.KeyCols, LEN(CI1.KeyCols) + 1, 1) = ' '
								)
							)
						AND CI1.IndexName <> CI2.IndexName
					)"

		# Support Compression 2008+
		$exactDuplicateQuery = "
			WITH CTE_IndexCols
			AS (
				SELECT i.[object_id]
					,i.index_id
					,OBJECT_SCHEMA_NAME(i.[object_id]) AS SchemaName
					,OBJECT_NAME(i.[object_id]) AS TableName
					,NAME AS IndexName
					,ISNULL(STUFF((
								SELECT ', ' + col.NAME + ' ' + CASE 
										WHEN idxCol.is_descending_key = 1
											THEN 'DESC'
										ELSE 'ASC'
										END -- Include column order (ASC / DESC)
								FROM sys.index_columns idxCol
								INNER JOIN sys.columns col ON idxCol.[object_id] = col.[object_id]
									AND idxCol.column_id = col.column_id
								WHERE i.[object_id] = idxCol.[object_id]
									AND i.index_id = idxCol.index_id
									AND idxCol.is_included_column = 0
								ORDER BY idxCol.key_ordinal
								FOR XML PATH('')
								), 1, 2, ''), '') AS KeyCols
					,ISNULL(STUFF((
								SELECT ', ' + col.NAME + ' ' + CASE 
										WHEN idxCol.is_descending_key = 1
											THEN 'DESC'
										ELSE 'ASC'
										END -- Include column order (ASC / DESC)
								FROM sys.index_columns idxCol
								INNER JOIN sys.columns col ON idxCol.[object_id] = col.[object_id]
									AND idxCol.column_id = col.column_id
								WHERE i.[object_id] = idxCol.[object_id]
									AND i.index_id = idxCol.index_id
									AND idxCol.is_included_column = 1
								ORDER BY idxCol.key_ordinal
								FOR XML PATH('')
								), 1, 2, ''), '') AS IncludedCols
					,i.[type_desc] AS IndexType
					,i.is_disabled AS IsDisabled
					,i.has_filter AS IsFiltered
				FROM sys.indexes AS i
				WHERE i.index_id > 0 -- Exclude HEAPS
					AND i.[type_desc] IN (
						'CLUSTERED'
						,'NONCLUSTERED'
						)
					AND OBJECT_SCHEMA_NAME(i.[object_id]) <> 'sys'
				)
				,CTE_IndexSpace
			AS (
				SELECT s.[object_id]
					,s.index_id
					,SUM(s.[used_page_count]) * 8 / 1024.0 AS IndexSizeMB
					,SUM(p.[rows]) AS NumberRows
					,p.data_compression_desc AS CompressionDesc
				FROM sys.dm_db_partition_stats AS s
				INNER JOIN sys.partitions p WITH (NOLOCK) ON s.[partition_id] = p.[partition_id]
					AND s.[object_id] = p.[object_id]
					AND s.index_id = p.index_id
				WHERE s.index_id > 0 -- Exclude HEAPS
					AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
				GROUP BY s.[object_id]
					,s.index_id
					,p.data_compression_desc
				)
			SELECT DB_NAME() AS DatabaseName
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
			INNER JOIN CTE_IndexSpace AS CSPC ON CI1.[object_id] = CSPC.[object_id]
				AND CI1.index_id = CSPC.index_id
			WHERE EXISTS (
					SELECT 1
					FROM CTE_IndexCols CI2
					WHERE CI1.SchemaName = CI2.SchemaName
						AND CI1.TableName = CI2.TableName
						AND CI1.KeyCols = CI2.KeyCols
						AND CI1.IncludedCols = CI2.IncludedCols
						AND CI1.IsFiltered = CI2.IsFiltered
						AND CI1.IndexName <> CI2.IndexName
					)"

		$overlappingQuery = "
			WITH CTE_IndexCols AS
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

		if ($FilePath.Length -gt 0) {
			$directory = Split-Path $FilePath
			$exists = Test-Path $directory
			
			if ($exists -eq $false) {
				throw "Parent directory $directory does not exist."
			}
		}

		Write-Output "Attempting to connect to Sql Server."
		$server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
	}
	process {
		if ($server.versionMajor -lt 9) {
			throw "This function does not support versions lower than SQL Server 2005 (v9)."
		}

		if ($pipedatabase.Length -gt 0) {
			$Source = $pipedatabase[0].parent.name
			$database = $pipedatabase.name
		}

		if ($database.Count -eq 0) {
			$database = ($server.Databases | Where-Object {$_.isSystemObject -eq 0 -and $_.Status -ne "Offline"}).Name
		}

		if ($database.Count -gt 0) {
			foreach ($db in $database) {
				try {
					Write-Output "Getting indexes from database '$db'."

					$query = if ($server.versionMajor -eq 9) {
						if ($IncludeOverlapping) {$overlappingQuery2005} else {$exactDuplicateQuery2005}
					}
					else {
						if ($IncludeOverlapping) {$overlappingQuery} else {$exactDuplicateQuery}
					}

					$duplicatedindex = $server.Databases[$db].ExecuteWithResults($query)

					$scriptGenerated = $false

					if ($duplicatedindex.Tables[0].Rows.Count -gt 0) {
						if ($Force) {
							$indexesToDrop = $duplicatedindex.Tables[0] | Out-GridView -Title "Duplicate Indexes on $($db) database - Choose indexes to DROP! (-Force was specified)" -PassThru
						}
						else {
							$indexesToDrop = $duplicatedindex.Tables[0] | Out-GridView -Title "Duplicate Indexes on $($db) database - Choose indexes to generate DROP script" -PassThru
						}

						#When only 1 line selected, the count does not work
						if ($indexesToDrop.Count -gt 0 -or !([string]::IsNullOrEmpty($indexesToDrop))) {
							#reset to #Yes
							$result = 0

							if ($duplicatedindex.Tables[0].Rows.Count -eq $indexesToDrop.Count) {
								$title = "Indexes to drop on databases '$db':"
								$message = "You will generate drop statements to all indexes.`r`nPerhaps you want to keep at least one.`r`nDo you wish to generate the script anyway? (Y/N)"
								$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
								$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
								$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
								$result = $host.ui.PromptForChoice($title, $message, $options, 0)
							}

							if ($result -eq 0) {
								#default OR answer = YES
								$sqlDropScript = "/*`r`n"
								$sqlDropScript += "`tScript generated @ $(Get-Date -format "yyyy-MM-dd HH:mm:ss.ms")`r`n"
								$sqlDropScript += "`tDatabase: $($db)`r`n"
								$sqlDropScript += if (!$IncludeOverlapping) {
									"`tConfirm that you have chosen the right indexes before execute the drop script`r`n"
								}
								else {
									"`tChoose wisely when dropping a partial duplicate index. You may want to check index usage before drop it.`r`n"
								}
								$sqlDropScript += "*/`r`n"

								foreach ($index in $indexesToDrop) {
									if ($FilePath.Length -gt 0) {
										Write-Output "Exporting $($index.TableName).$($index.IndexName)"
									}

									if ($Force) {
										$sqlDropScript += "USE [$($index.DatabaseName)]`r`n"
										$sqlDropScript += "IF EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('$($index.TableName)') AND name = '$($index.IndexName)')`r`n"
										$sqlDropScript += "    DROP INDEX $($index.TableName).$($index.IndexName)`r`n`r`n"

										if ($Pscmdlet.ShouldProcess($db, "Dropping index '$($index.IndexName)' on table '$($index.TableName)' using -Force")) {
											$server.Databases[$db].ExecuteNonQuery($sqlDropScript) | Out-Null
											Write-Output "Index '$($index.IndexName)' on table '$($index.TableName)' dropped"
										}
									}
									else {
										$sqlDropScript += "USE [$($index.DatabaseName)]`r`n"
										$sqlDropScript += $sqlGO
										$sqlDropScript += "IF EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('$($index.TableName)') AND name = '$($index.IndexName)')`r`n"
										$sqlDropScript += "    DROP INDEX $($index.TableName).$($index.IndexName)`r`n"
										$sqlDropScript += $sqlFinalGO
									}
								}

								if (!$Force) {
									if ($FilePath.Length -gt 0) {
										$sqlDropScript | Out-File -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
									}
									else {
										Write-Output $sqlDropScript
									}
									$scriptGenerated = $true
								}

								
							}
							else {
								#answer = no
								Write-Warning "Script will not be generated for database '$db'."
							}
						}
					}
					else {
						Write-Output "No duplicate indexes found!"
					}
				}
				catch {
					throw $_
				}
			}

			if ($scriptGenerated) {
				Write-Warning "Confirm the generated script before execute!"
			}
			if ($FilePath.Length -gt 0) {
				Write-Output "Script generated to $FilePath."
			}
		}
		else {
			Write-Output "There are no databases to analyse."
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Get-SqlDuplicateIndex
	}
}
