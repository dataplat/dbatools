function Find-DbaDbUnusedIndex {
    <#
    .SYNOPSIS
        Find unused indexes

    .DESCRIPTION
        This command will help you to find Unused indexes on a database or a list of databases

        For now only supported for CLUSTERED and NONCLUSTERED indexes

    .PARAMETER SqlInstance
        The SQL Server you want to check for unused indexes.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

    .PARAMETER IgnoreUptime
        Less than 7 days uptime can mean that analysis of unused indexes is unreliable, and normally no results will be returned. By setting this option results will be returned even if the Instance has been running for less than 7 days.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Seeks
        Specify a custom threshold for user seeks. The default for this parameter is 1.
        The valid values are between 1 and 1000000 to provide flexibility on the definition of 'unused' indexes.
        Note: The resulting WHERE clause uses the AND operator:
        user_seeks < $Seeks
        AND user_scans < $Scans
        AND user_lookups < $Lookups

    .PARAMETER Scans
        Specify a custom threshold for user scans. The default for this parameter is 1.
        The valid values are between 1 and 1000000 to provide flexibility on the definition of 'unused' indexes.
        Note: The resulting WHERE clause uses the AND operator:
        user_seeks < $Seeks
        AND user_scans < $Scans
        AND user_lookups < $Lookups

    .PARAMETER Lookups
        Specify a custom threshold for user lookups. The default for this parameter is 1.
        The valid values are between 1 and 1000000 to provide flexibility on the definition of 'unused' indexes.
        Note: The resulting WHERE clause uses the AND operator:
        user_seeks < $Seeks
        AND user_scans < $Scans
        AND user_lookups < $Lookups

    .NOTES
        Tags: Index
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
        SERVERPROPERTY('ServerName') AS SqlInstance, DB_NAME(database_id) AS 'Database'
        ,s.name AS 'Schema'
        ,t.name AS 'Table'
        ,i.object_id AS ObjectId
        ,i.name AS 'IndexName'
        ,i.index_id as 'IndexId'
        ,i.type_desc as 'TypeDesc'
        ,user_seeks as 'UserSeeks'
        ,user_scans as 'UserScans'
        ,user_lookups  as 'UserLookups'
        ,user_updates  as 'UserUpdates'
        ,last_user_seek  as 'LastUserSeek'
        ,last_user_scan  as 'LastUserScan'
        ,last_user_lookup  as 'LastUserLookup'
        ,last_user_update  as 'LastUserUpdate'
        ,system_seeks  as 'SystemSeeks'
        ,system_scans  as 'SystemScans'
        ,system_lookups  as 'SystemLookup'
        ,system_updates  as 'SystemUpdates'
        ,last_system_seek  as 'LastSystemSeek'
        ,last_system_scan  as 'LastSystemScan'
        ,last_system_lookup  as 'LastSystemLookup'
        ,last_system_update as 'LastSystemUpdate'
        ,COALESCE(indexSpace.IndexSizeMB, 0) AS 'IndexSizeMB'
        ,COALESCE(indexSpace.[RowCount], 0) AS 'RowCount'
        --REPLACEPARAMSELECT
        FROM sys.tables t
        JOIN sys.schemas s
            ON t.schema_id = s.schema_id
        JOIN sys.indexes i
            ON i.object_id = t.object_id
        LEFT OUTER JOIN sys.dm_db_index_usage_stats iu
            ON iu.object_id = i.object_id
                AND iu.index_id = i.index_id
        JOIN CTE_IndexSpace indexSpace
            ON indexSpace.index_id = i.index_id
                AND indexSpace.object_id = i.object_id
        WHERE iu.database_id = DB_ID()
                AND OBJECTPROPERTY(i.[object_id], 'IsMSShipped') = 0
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