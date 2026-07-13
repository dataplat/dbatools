function Find-DbaDbUnusedIndex {
    <#
    .SYNOPSIS
        Identifies database indexes with low usage statistics that may be candidates for removal

    .DESCRIPTION
        Analyzes index usage statistics from sys.dm_db_index_usage_stats to identify indexes with minimal activity that consume storage space and slow down data modifications without providing query performance benefits.

        This function helps DBAs optimize database performance by finding indexes that are rarely or never used, so you can safely remove them to reduce maintenance overhead, speed up INSERT/UPDATE/DELETE operations, and free up disk space. The function uses customizable thresholds for seeks, scans, and lookups to define what constitutes "unused," with safety checks to ensure SQL Server has been running long enough (7+ days) for reliable statistics.

        Supports clustered and non-clustered indexes on SQL Server 2005 and higher, with additional data compression information available on SQL Server 2008+. Results include index size, row count, and detailed usage patterns to help prioritize which indexes to drop first.

    .PARAMETER SqlInstance
        The SQL Server you want to check for unused indexes.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for unused indexes. Accepts wildcards for pattern matching.
        Use this when you want to focus on specific databases rather than scanning the entire instance, which is helpful for large environments or targeted maintenance windows.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the unused index analysis. Accepts wildcards for pattern matching.
        Commonly used to skip system databases, read-only databases, or databases undergoing maintenance that shouldn't be modified.

    .PARAMETER IgnoreUptime
        Bypasses the 7-day uptime check that normally prevents analysis on recently restarted instances.
        Use this when you need results from a server with recent restarts, but be aware that usage statistics may not reflect normal workload patterns.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase for pipeline operations.
        This allows you to chain commands and apply complex database filtering logic before analyzing unused indexes.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Seeks
        Sets the threshold for user seeks below which an index is considered unused. Default is 1.
        User seeks occur when the query optimizer uses the index to efficiently locate specific rows. Increase this value to find indexes with very low seek activity rather than completely unused ones.

    .PARAMETER Scans
        Sets the threshold for user scans below which an index is considered unused. Default is 1.
        User scans happen when queries read multiple rows through the index, often for range queries or aggregations. Higher values help identify indexes with minimal scan activity.

    .PARAMETER Lookups
        Sets the threshold for user lookups below which an index is considered unused. Default is 1.
        User lookups occur when a nonclustered index is used to locate rows that are then retrieved from the clustered index. This typically indicates bookmark lookup operations.

    .OUTPUTS
        PSCustomObject

        Returns one object per unused index found. Each object contains comprehensive index usage statistics and metadata.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The name of the database containing the index
        - DatabaseId: Numeric ID of the database
        - Schema: The schema name containing the table
        - Table: The name of the table containing the index
        - ObjectId: Numeric ID of the table object
        - IndexName: The name of the index
        - IndexId: Numeric ID of the index within the table
        - TypeDesc: Type description of the index (CLUSTERED, NONCLUSTERED, etc.)
        - UserSeeks: Number of seek operations by user queries since last SQL Server restart
        - UserScans: Number of scan operations by user queries since last SQL Server restart
        - UserLookups: Number of lookup operations by user queries since last SQL Server restart
        - UserUpdates: Number of update operations on the index by user queries since last SQL Server restart
        - LastUserSeek: Timestamp of the last seek operation by user queries
        - LastUserScan: Timestamp of the last scan operation by user queries
        - LastUserLookup: Timestamp of the last lookup operation by user queries
        - LastUserUpdate: Timestamp of the last update operation by user queries
        - SystemSeeks: Number of seek operations by system queries since last SQL Server restart
        - SystemScans: Number of scan operations by system queries since last SQL Server restart
        - SystemLookup: Number of lookup operations by system queries since last SQL Server restart
        - SystemUpdates: Number of update operations on the index by system queries since last SQL Server restart
        - LastSystemSeek: Timestamp of the last seek operation by system queries
        - LastSystemScan: Timestamp of the last scan operation by system queries
        - LastSystemLookup: Timestamp of the last lookup operation by system queries
        - LastSystemUpdate: Timestamp of the last update operation by system queries
        - IndexSizeMB: Size of the index in megabytes
        - RowCount: Number of rows in the index
        - CompressionDescription: Data compression type (SQL Server 2008+ only). Values include None, Row, Page, ColumnStore, or ColumnStoreArchive

        Indexes are identified as "unused" when their usage statistics fall below the specified thresholds (default: UserSeeks < 1, UserScans < 1, UserLookups < 1).

    .NOTES
        Tags: Index, Lookup
        Author: Aaron Nelson (@SQLvariant), SQLvariant.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaDbUnusedIndex

    .EXAMPLE
        PS C:\> Find-DbaDbUnusedIndex -SqlInstance sql2016 -Database db1, db2

        Finds unused indexes on db1 and db2 on sql2016

    .EXAMPLE
        PS C:\> Find-DbaDbUnusedIndex -SqlInstance sql2016 -SqlCredential $cred

        Finds unused indexes on db1 and db2 on sql2016 using SQL Authentication to connect to the server

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 | Find-DbaDbUnusedIndex

        Finds unused indexes on all databases on sql2016

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2019 | Find-DbaDbUnusedIndex -Seeks 10 -Scans 100 -Lookups 1000

        Finds 'unused' indexes with user_seeks < 10, user_scans < 100, and user_lookups < 1000 on all databases on sql2019.
        Note that these additional parameters provide flexibility to define what is considered an 'unused' index.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IgnoreUptime,
        [ValidateRange(1, 1000000)][int]$Seeks = 1,
        [ValidateRange(1, 1000000)][int]$Scans = 1,
        [ValidateRange(1, 1000000)][int]$Lookups = 1,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        # Support Compression 2008+
        $sql = "
        ;WITH
            CTE_IndexSpace
        AS
        (
            SELECT
                s.object_id                         AS object_id
            ,   s.index_id                          AS index_id
            ,   SUM(s.used_page_count) * 8 / 1024.0 AS IndexSizeMB
            ,   SUM(p.[rows])                       AS [RowCount]
            --REPLACEPARAMCTE
            FROM
                sys.dm_db_partition_stats AS s
            INNER JOIN
                sys.partitions p WITH (NOLOCK)
                    ON s.[partition_id] = p.[partition_id]
                    AND s.[object_id] = p.[object_id]
                    AND s.index_id = p.index_id
            WHERE
                s.index_id > 0 -- Exclude HEAPS
                AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
            GROUP BY
                s.[object_id]
            ,   s.index_id
            --REPLACEPARAMCTE
        )
        SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, DB_NAME(d.database_id) AS 'Database'
        ,d.database_id AS DatabaseId
        ,s.name AS 'Schema'
        ,t.name AS 'Table'
        ,i.object_id AS ObjectId
        ,i.name AS 'IndexName'
        ,i.index_id AS 'IndexId'
        ,i.type_desc AS 'TypeDesc'
        ,user_seeks AS 'UserSeeks'
        ,user_scans AS 'UserScans'
        ,user_lookups  AS 'UserLookups'
        ,user_updates  AS 'UserUpdates'
        ,last_user_seek  AS 'LastUserSeek'
        ,last_user_scan  AS 'LastUserScan'
        ,last_user_lookup  AS 'LastUserLookup'
        ,last_user_update  AS 'LastUserUpdate'
        ,system_seeks  AS 'SystemSeeks'
        ,system_scans  AS 'SystemScans'
        ,system_lookups  AS 'SystemLookup'
        ,system_updates  AS 'SystemUpdates'
        ,last_system_seek  AS 'LastSystemSeek'
        ,last_system_scan  AS 'LastSystemScan'
        ,last_system_lookup  AS 'LastSystemLookup'
        ,last_system_update AS 'LastSystemUpdate'
        ,COALESCE(indexSpace.IndexSizeMB, 0) AS 'IndexSizeMB'
        ,COALESCE(indexSpace.[RowCount], 0) AS 'RowCount'
        --REPLACEPARAMSELECT
        FROM sys.tables t
        JOIN sys.schemas s
            ON t.schema_id = s.schema_id
        JOIN sys.indexes i
            ON i.object_id = t.object_id
        JOIN sys.databases d
            ON d.name = DB_NAME()
        LEFT OUTER JOIN sys.dm_db_index_usage_stats iu
            ON iu.object_id = i.object_id
                AND iu.index_id = i.index_id
                AND iu.database_id = d.database_id
        JOIN CTE_IndexSpace indexSpace
            ON indexSpace.index_id = i.index_id
                AND indexSpace.object_id = i.object_id
        WHERE
            OBJECTPROPERTY(i.[object_id], 'IsMSShipped') = 0
            AND user_seeks < $Seeks
            AND user_scans < $Scans
            AND user_lookups < $Lookups
            AND i.type_desc NOT IN ('HEAP', 'CLUSTERED COLUMNSTORE')"

        # Replacement values for the SQL above
        $replaceParamCTE = "--REPLACEPARAMCTE"
        $replaceValueCTE = ", p.data_compression_desc"
        $replaceParamSelect = "--REPLACEPARAMSELECT"
        $replaceValueSelect = ", indexSpace.data_compression_desc AS CompressionDescription"
    }

    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        # Return a warning if the database specified was not found
        if ($null -eq $InputObject -or $InputObject.Count -eq 0) {
            Write-Message -Level Warning -Message "Database [$Database] was not found on [$SqlInstance]."
            continue
        }

        foreach ($db in $InputObject) {
            if ($db.Parent.Databases[$db].IsAccessible -eq $false) {
                Write-Message -Level Warning -Message "Database [$db] is not accessible."
                continue
            }

            $server = $db.Parent
            $instance = $server.Name

            if ($server.VersionMajor -lt 9) {
                Stop-Function -Message "This function does not support versions lower than SQL Server 2005 (v9)." -Continue
            }

            $lastRestart = $server.Databases['tempdb'].CreateDate
            $endDate = Get-Date -Date $lastRestart
            $diffDays = (New-TimeSpan -Start $endDate -End (Get-Date)).Days

            if ($diffDays -le 6) {
                if ($IgnoreUptime) {
                    Write-Message -Level Verbose -Message "The SQL Service was restarted on $lastRestart, which is not long enough for a solid evaluation."
                } else {
                    Stop-Function -Message "The SQL Service on $instance was restarted on $lastRestart, which is not long enough for a solid evaluation." -Continue
                }
            }

            <#
                Validate if server version is:
                    - sql 2012 and if have SP3 CU3 (Build 6537) or higher
                    - sql 2014 and if have SP2 (Build 5000) or higher
                If the major version is the same but the build is lower, throws the message
            #>

            if (($server.VersionMajor -eq 11 -and $server.BuildNumber -lt 6537) -or ($server.VersionMajor -eq 12 -and $server.BuildNumber -lt 5000)) {
                Stop-Function -Message "This SQL version has a known issue. Rebuilding an index clears any existing row entry from sys.dm_db_index_usage_stats for that index.`r`nPlease refer to connect item: https://support.microsoft.com/en-us/help/3160407/fix-sys-dm-db-index-usage-stats-missing-information-after-index-rebuil" -Continue
            }

            if ($diffDays -le 33) {
                Write-Message -Level Verbose -Message "The SQL Service on $instance was restarted on $lastRestart, which may not be long enough for a solid evaluation."
            }

            <#
                Data compression was added in SQL 2008, so add in the additional compression description column for versions 2008 or higher.
            #>
            $sqlToRun = $sql

            if ($server.VersionMajor -gt 9) {
                $sqlToRun = $sqlToRun.Replace($replaceParamCTE, $replaceValueCTE).Replace($replaceParamSelect, $replaceValueSelect)
            }

            try {
                $db.Query($sqlToRun)
            } catch {
                Stop-Function -Message "Issue gathering indexes" -Category InvalidOperation -ErrorRecord $_ -Target $db
            }
        }
    }
}