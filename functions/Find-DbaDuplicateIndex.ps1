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
                KeyColumns
                IncludedColumns
                IndexSizeMB
                IndexType
                CompressionDescription (When 2008+)
                [RowCount]
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

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER Force
            If this switch is enabled, the DROP statement(s) will be executed instead of being written to the output file.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Claudio Silva (@ClaudioESSilva)
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
        [switch]$EnableException
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
                                ), 1, 2, ''), '') AS KeyColumns
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
                                ), 1, 2, ''), '') AS IncludedColumns
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
                    ,SUM(p.[rows]) AS [RowCount]
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
                ,CI1.KeyColumns
                ,CI1.IncludedColumns
                ,CI1.IndexType
                ,CSPC.IndexSizeMB
                ,CSPC.[RowCount]
                ,CI1.IsDisabled
            FROM CTE_IndexCols AS CI1
            INNER JOIN CTE_IndexSpace AS CSPC ON CI1.[object_id] = CSPC.[object_id]
                AND CI1.index_id = CSPC.index_id
            WHERE EXISTS (
                    SELECT 1
                    FROM CTE_IndexCols CI2
                    WHERE CI1.SchemaName = CI2.SchemaName
                        AND CI1.TableName = CI2.TableName
                        AND CI1.KeyColumns = CI2.KeyColumns
                        AND CI1.IncludedColumns = CI2.IncludedColumns
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
                                ), 1, 2, ''), '') AS KeyColumns
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
                                ), 1, 2, ''), '') AS IncludedColumns
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
                    ,SUM(p.[rows]) AS [RowCount]
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
                ,CI1.KeyColumns
                ,CI1.IncludedColumns
                ,CI1.IndexType
                ,CSPC.IndexSizeMB
                ,CSPC.[RowCount]
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
                                CI1.KeyColumns LIKE CI2.KeyColumns + '%'
                                AND SUBSTRING(CI1.KeyColumns, LEN(CI2.KeyColumns) + 1, 1) = ' '
                                )
                            OR (
                                CI2.KeyColumns LIKE CI1.KeyColumns + '%'
                                AND SUBSTRING(CI2.KeyColumns, LEN(CI1.KeyColumns) + 1, 1) = ' '
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
                                ), 1, 2, ''), '') AS KeyColumns
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
                                ), 1, 2, ''), '') AS IncludedColumns
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
                    ,SUM(p.[rows]) AS [RowCount]
                    ,p.data_compression_desc AS CompressionDescription
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
                ,CI1.KeyColumns
                ,CI1.IncludedColumns
                ,CI1.IndexType
                ,CSPC.IndexSizeMB
                ,CSPC.CompressionDescription
                ,CSPC.[RowCount]
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
                        AND CI1.KeyColumns = CI2.KeyColumns
                        AND CI1.IncludedColumns = CI2.IncludedColumns
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
                        FOR XML PATH('')), 1, 2, ''), '') AS KeyColumns
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
                        FOR XML PATH('')), 1, 2, ''), '') AS IncludedColumns
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
                        ,SUM(p.[rows]) AS [RowCount]
                        ,p.data_compression_desc AS CompressionDescription
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
                    ,CI1.KeyColumns
                    ,CI1.IncludedColumns
                    ,CI1.IndexType
                    ,CSPC.IndexSizeMB
                    ,CSPC.CompressionDescription
                    ,CSPC.[RowCount]
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
                                        (CI1.KeyColumns like CI2.KeyColumns + '%' and SUBSTRING(CI1.KeyColumns,LEN(CI2.KeyColumns)+1,1) = ' ')
                                    OR (CI2.KeyColumns like CI1.KeyColumns + '%' and SUBSTRING(CI2.KeyColumns,LEN(CI1.KeyColumns)+1,1) = ' ')
                                )
                            AND CI1.IsFiltered = CI2.IsFiltered
                            AND CI1.IndexName <> CI2.IndexName
                        )"
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $sqlinstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($database) {
                $databases = $server.Databases | Where-Object Name -in $database
            }
            else {
                $databases = $server.Databases | Where-Object IsAccessible -eq $true
            }

            foreach ($db in $databases) {
                try {
                    Write-Message -Level Verbose -Message "Getting indexes from database '$db'."

                    $query = if ($server.versionMajor -eq 9) {
                        if ($IncludeOverlapping) { $overlappingQuery2005 }
                        else { $exactDuplicateQuery2005 }
                    }
                    else {
                        if ($IncludeOverlapping) { $overlappingQuery }
                        else { $exactDuplicateQuery }
                    }

                    $db.Query($query)

                }
                catch {
                    Stop-Function -Message "Query failure" -Target $db
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Get-SqlDuplicateIndex
    }
}