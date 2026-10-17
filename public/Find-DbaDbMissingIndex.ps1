function Find-DbaDbMissingIndex {
    <#
    .SYNOPSIS
        Surfaces missing index suggestions from the missing-index DMVs, ranked by impact.

    .DESCRIPTION
        Reads sys.dm_db_missing_index_group_stats, sys.dm_db_missing_index_groups, and
        sys.dm_db_missing_index_details to surface indexes the optimizer wished existed for the
        workload it has seen, ranked by an impact score, with a generated CREATE INDEX statement
        for review.

        The score uses Microsoft's formula, avg_total_user_cost * avg_user_impact *
        (user_seeks + user_scans), so that a large percentage improvement on a cheap query does
        not outrank a smaller improvement on an expensive one. The three inputs
        (AvgTotalUserCost, AvgUserImpact, and the seek/scan counts) are returned as their own
        properties so you can rank differently if you prefer.

        Important caveats about this data, all surfaced per row and summarized here:
        - The missing-index DMVs are advisory and over-suggest. These are candidates for a human
          to evaluate, NOT recommendations to apply blindly. The generated CREATE INDEX statement
          is a starting point - review key order, included columns, and especially the write-cost
          impact before creating anything.
        - The counters are cleared on instance restart, failover, and when a database goes
          offline, and for a single table whenever its metadata changes or any ALTER INDEX runs
          against it. With nightly index maintenance, a table's numbers may only cover the time
          since its last rebuild. Each row returns the instance StartTime and the table's
          LastUserSeek / LastUserScan so you can judge how much history the numbers represent.
        - SQL Server stops collecting at 600 missing index groups per instance. When that ceiling
          is reached a warning is emitted, because suggestions past it are not recorded.

        When a suggestion overlaps an existing index, the overlapping index is named in the
        OverlappingIndex property rather than being filtered out - that is usually the case a
        human most wants to see (an existing index with the wrong key order or a missing include),
        and Microsoft's guidance is to widen the existing index rather than add a near-duplicate.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell
        credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and
        Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. If unspecified, all accessible user databases are processed.

        A system database is skipped unless it is named here explicitly, in which case it is
        processed and a warning is written noting that system databases are not included by default.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase.

    .PARAMETER MinimumImpact
        Minimum impact score (avg_total_user_cost * avg_user_impact * (user_seeks + user_scans))
        for a suggestion to be returned. Filters out low-value noise. Default: 50.

    .PARAMETER MinimumSeek
        Minimum number of seeks and scans (user_seeks + user_scans) for a suggestion to be
        returned. This matches the seek/scan term in the impact score, so scan-only suggestions
        are not silently dropped. Default: 1.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a
        friendly warning message. This avoids overwhelming you with "sea of red" exceptions, but
        is inconvenient because it basically disables advanced scripting.

        Using this switch turns this "nice by default" feature off and enables you to catch
        exceptions with your own try/catch.

    .NOTES
        Tags: Index, Performance, Diagnostic
        Author: Deepesh Dhake (@deepeshd87)

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        The missing-index DMVs are advisory and over-suggest; treat output as candidates to
        evaluate, not recommendations to apply. Glenn Berry's diagnostic queries, available via
        Invoke-DbaDiagnosticQuery -QueryName "Missing Indexes All Databases" (and "Missing
        Indexes" per database), return the same raw rows; this command adds impact filtering,
        CREATE INDEX generation, and overlap detection.

        Permissions: reading the missing-index DMVs requires VIEW SERVER STATE (SQL Server 2019
        and earlier) or VIEW SERVER PERFORMANCE STATE (SQL Server 2022+). Without it, the DMV
        query returns no rows.

    .LINK
        https://dbatools.io/Find-DbaDbMissingIndex

    .OUTPUTS
        PSCustomObject

    .EXAMPLE
        PS C:\> Find-DbaDbMissingIndex -SqlInstance sql2019 -Database AdventureWorks

        Returns missing index suggestions for AdventureWorks on sql2019, ranked by impact, with a
        generated CREATE INDEX statement for each.

    .EXAMPLE
        PS C:\> Find-DbaDbMissingIndex -SqlInstance sql2019 -MinimumImpact 1000

        Returns only high-impact missing index suggestions (score of 1000 or more) across all
        user databases on sql2019.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2019 -Database Sales | Find-DbaDbMissingIndex

        Pipes the Sales database in from Get-DbaDatabase and returns its missing index suggestions.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [double]$MinimumImpact = 50,
        [int]$MinimumSeek = 1,
        [switch]$EnableException
    )

    begin {
        # Per-database query. mid.database_id = DB_ID() keeps it correct on Azure SQL Database,
        # where these DMVs only ever return rows for the connected database.
        #
        # Overlap detection is done here rather than in SMO, and matches on real column IDs, not on
        # text. sys.dm_db_missing_index_columns(index_handle) returns the suggestion's candidate key
        # columns (column_usage EQUALITY or INEQUALITY) as column_ids; an existing index overlaps when
        # its leading key column (key_ordinal = 1, is_included_column = 0) is one of those column_ids.
        # Comparing column_ids avoids the identifier pitfalls of text matching entirely - a column
        # named [Order Date] or [Customer_Id] is compared by ID, so spaces and the LIKE metacharacters
        # _ and % can't cause a false overlap. Doing it in the query also removes the per-table SMO
        # Tables/Indexes load.
        #
        # Names come back already quoted with QUOTENAME(), so a ] in an object name can't break the
        # generated T-SQL. index_handle is returned so the suggested index name can be made unique
        # (the DMV frequently has several suggestions for one table with the same keys and different
        # include lists).
        #
        # The 2019+ query-text join (qt CTE) is spliced in from the process block via
        # $queryTextCte / $queryTextSelect / $queryTextJoin so pre-2019 instances get a clean query.
        # It uses ROW_NUMBER() rather than TOP (1) so a tie on last_user_seek (e.g. both NULL for a
        # scan-only group) can't return the same group twice.
        $sqlTemplate = @"
;WITH mig AS (
    SELECT
        migs.group_handle,
        migs.unique_compiles,
        migs.user_seeks,
        migs.user_scans,
        migs.last_user_seek,
        migs.last_user_scan,
        migs.avg_total_user_cost,
        migs.avg_user_impact
    FROM sys.dm_db_missing_index_group_stats AS migs
),
ix AS (
    SELECT
        i.object_id,
        ic.column_id AS leading_column_id,
        i.name       AS index_name
    FROM sys.indexes AS i
    INNER JOIN sys.index_columns AS ic
        ON ic.object_id = i.object_id
       AND ic.index_id  = i.index_id
       AND ic.key_ordinal = 1
       AND ic.is_included_column = 0
    WHERE i.index_id > 0
)
{0}
SELECT
    DB_NAME(mid.database_id)        AS DatabaseName,
    mid.database_id                 AS DatabaseId,
    OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id) AS SchemaName,
    OBJECT_NAME(mid.object_id, mid.database_id)        AS TableName,
    QUOTENAME(OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id)) AS SchemaNameQuoted,
    QUOTENAME(OBJECT_NAME(mid.object_id, mid.database_id))        AS TableNameQuoted,
    mid.object_id                   AS ObjectId,
    mid.index_handle                AS IndexHandle,
    mid.equality_columns            AS EqualityColumns,
    mid.inequality_columns          AS InequalityColumns,
    mid.included_columns            AS IncludedColumns,
    mig.user_seeks                  AS UserSeeks,
    mig.user_scans                  AS UserScans,
    mig.unique_compiles             AS UniqueCompiles,
    mig.last_user_seek              AS LastUserSeek,
    mig.last_user_scan              AS LastUserScan,
    CAST(mig.avg_total_user_cost AS decimal(18,4))  AS AvgTotalUserCost,
    CAST(mig.avg_user_impact AS decimal(9,2))       AS AvgUserImpact,
    CAST(mig.avg_total_user_cost * mig.avg_user_impact * (mig.user_seeks + mig.user_scans) AS decimal(28,4)) AS ImpactScore,
    STUFF((
        -- An existing index overlaps when its leading key column_id is one of this suggestion's
        -- candidate key column_ids (EQUALITY or INEQUALITY, from the missing-index columns DMV).
        -- Matching on column_id means identifiers with spaces, _ or % can't produce a false overlap.
        SELECT ', ' + ix.index_name
        FROM ix
        WHERE ix.object_id = mid.object_id
          AND ix.leading_column_id IN (
                SELECT mic.column_id
                FROM sys.dm_db_missing_index_columns(mid.index_handle) AS mic
                WHERE mic.column_usage IN ('EQUALITY', 'INEQUALITY')
              )
        FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, '') AS OverlappingIndex
    {1}
FROM mig
INNER JOIN sys.dm_db_missing_index_groups  AS mig_grp ON mig.group_handle = mig_grp.index_group_handle
INNER JOIN sys.dm_db_missing_index_details AS mid     ON mig_grp.index_handle = mid.index_handle
{2}
WHERE mid.database_id = DB_ID()
  AND (mig.user_seeks + mig.user_scans) >= {3}
  AND (mig.avg_total_user_cost * mig.avg_user_impact * (mig.user_seeks + mig.user_scans)) >= {4}
ORDER BY ImpactScore DESC;
"@
        # Note: the SMO Database.Query() method does not support parameterized queries, so the
        # two thresholds are formatted into the statement directly. Both are validated numeric
        # parameters ([int] MinimumSeek, [double] MinimumImpact), so there is no injection risk;
        # they are rendered with the invariant culture so a comma decimal separator can't break
        # the SQL on non-US locales.

        # Instances whose 600-group ceiling has already been checked, so the warning fires once per
        # instance rather than once per database.
        $checkedInstances = @{ }
    }

    process {
        $databases = @()

        foreach ($instance in $SqlInstance) {
            try {
                # SQL Server 2008 floor. The missing-index DMVs exist from 2005, but database
                # discovery here goes through SMO (Get-DbaDatabase, $server.Databases), which dbatools
                # documents as requiring SQL Server 2008+ - 2005 fails on the SMO collection query
                # rather than running. So the floor is 10, not 9.
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Skip system databases unless one is named explicitly. Get-DbaDatabase -ExcludeSystem
            # drops them silently, which reads as "no suggestions" for a deliberate -Database msdb;
            # so when a system database is named we include it and warn.
            $namedSystem = @($Database | Where-Object { $_ -in 'master', 'model', 'msdb', 'tempdb' })
            if ($namedSystem) {
                Write-Message -Level Warning -Message "System databases are not included by default; processing $($namedSystem -join ', ') because named explicitly."
                $databases += Get-DbaDatabase -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase -OnlyAccessible
            } else {
                $databases += Get-DbaDatabase -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase -ExcludeSystem -OnlyAccessible
            }
        }

        foreach ($db in $InputObject) {
            if (-not $db.IsAccessible) { continue }
            # A piped database object is an explicit selection - the caller already chose it with
            # Get-DbaDatabase, so honour it, including a system database. (The $Database parameter is
            # not set on the downstream command in a pipeline, so it can't be used to tell intent
            # here; the presence of the object IS the intent.) Warn for a system DB so the caller
            # knows it is not part of the default set, but do not silently drop it.
            if ($db.IsSystemObject) {
                Write-Message -Level Warning -Message "Processing system database $($db.Name) because it was piped in explicitly; system databases are not included by default."
            }
            $databases += $db
        }

        foreach ($db in $databases) {
            $server = $db.Parent
            Write-Message -Level Verbose -Message "Processing $($db.Name) on $($server.Name)"

            # Warn once per instance when the 600-group collection ceiling is reached - past it,
            # the DMVs stop recording new suggestions.
            if (-not $checkedInstances.ContainsKey($server.Name)) {
                $checkedInstances[$server.Name] = $true
                try {
                    $groupCount = ($server.Query("SELECT COUNT(*) AS cnt FROM sys.dm_db_missing_index_group_stats")).cnt
                    if ($groupCount -ge 600) {
                        Write-Message -Level Warning -Message "Instance $($server.Name) has reached the 600 missing-index-group collection limit; suggestions beyond it are not recorded."
                    }
                } catch {
                    # Non-fatal; carry on with the analysis.
                    Write-Message -Level Verbose -Message "Could not read missing-index group count on $($server.Name): $($_.Exception.Message)"
                }
            }

            # The 2019+/Azure query-text DMV (one row per query, so joined separately from
            # group_stats to avoid double-counting the seek/scan totals). ROW_NUMBER with a
            # query_hash tiebreaker is deterministic, so a group never comes back twice.
            # Gate by engine type as well as version: Azure SQL Database reports VersionMajor 12 but
            # still exposes sys.dm_db_missing_index_group_stats_query, so a version-only check would
            # wrongly exclude it.
            $hasQueryTextDmv = $server.VersionMajor -ge 15 -or $server.DatabaseEngineType -eq 'SqlAzureDatabase'
            if ($hasQueryTextDmv) {
                $queryTextCte = ", qt AS (
    SELECT group_handle, query_hash, last_sql_handle
    FROM (
        SELECT
            migsq.group_handle,
            migsq.query_hash,
            migsq.last_sql_handle,
            ROW_NUMBER() OVER (PARTITION BY migsq.group_handle ORDER BY migsq.last_user_seek DESC, migsq.query_hash) AS rn
        FROM sys.dm_db_missing_index_group_stats_query AS migsq
    ) AS ranked
    WHERE ranked.rn = 1
)"
                $queryTextSelect = ", qt.query_hash AS QueryHash, qt.last_sql_handle AS LastSqlHandle"
                $queryTextJoin = "LEFT JOIN qt ON mig.group_handle = qt.group_handle"
            } else {
                $queryTextCte = ""
                $queryTextSelect = ""
                $queryTextJoin = ""
            }

            # Render numeric thresholds with invariant culture so a locale comma separator can't
            # corrupt the SQL. Both are validated numeric parameters, so this is injection-safe.
            $ci = [System.Globalization.CultureInfo]::InvariantCulture
            $minSeekSql = $MinimumSeek.ToString($ci)
            $minImpactSql = $MinimumImpact.ToString($ci)

            $sql = $sqlTemplate -f $queryTextCte, $queryTextSelect, $queryTextJoin, $minSeekSql, $minImpactSql

            # On Azure SQL Database the shared connection can't switch databases: $db.Query() issues a
            # USE, which Azure rejects with error 40508. So for Azure, open a connection whose initial
            # catalog IS the target database (Connect-DbaInstance -Database) and run there - no context
            # switch, nothing to restore. On-prem keeps the shared-connection path, recording and
            # restoring CurrentDatabase so a caller who passed a server object isn't left in the wrong
            # database.
            $currentDatabase = $null
            try {
                if ($server.DatabaseEngineType -eq 'SqlAzureDatabase') {
                    try {
                        $dbConn = Connect-DbaInstance -SqlInstance $server -SqlCredential $SqlCredential -Database $db.Name
                        $results = $dbConn.Query($sql)
                    } catch {
                        Stop-Function -Message "Failure executing missing-index analysis against $($db.Name) on $($server.Name)" -ErrorRecord $_ -Target $db -Continue
                        continue
                    }
                } else {
                    $currentDatabase = $server.ConnectionContext.CurrentDatabase
                    try {
                        $results = $db.Query($sql)
                    } catch {
                        Stop-Function -Message "Failure executing missing-index analysis against $($db.Name) on $($server.Name)" -ErrorRecord $_ -Target $db -Continue
                        continue
                    }
                }

                foreach ($row in $results) {
                    # Build the CREATE INDEX key list: equality columns, then inequality columns.
                    # .Query() returns a NULL column as [DBNull]::Value, which PowerShell treats as
                    # truthy, so test the type, not truthiness, or an absent column adds an empty
                    # entry (a trailing comma in the key, or INCLUDE ()).
                    $keyCols = @()
                    if ($row.EqualityColumns -isnot [System.DBNull] -and $row.EqualityColumns) { $keyCols += $row.EqualityColumns }
                    if ($row.InequalityColumns -isnot [System.DBNull] -and $row.InequalityColumns) { $keyCols += $row.InequalityColumns }
                    $keyColText = ($keyCols -join ', ')

                    $indexNameParts = @()
                    foreach ($c in ($keyColText -split ',')) {
                        $clean = ($c -replace '[\[\]]', '').Trim()
                        if ($clean) { $indexNameParts += $clean }
                    }
                    # index_handle keeps the name unique when one table has several suggestions with
                    # the same keys and different includes - otherwise running the CREATE statements
                    # in sequence fails from the second one on. The handle is the unique part, so when
                    # the whole name would exceed 128 chars the DESCRIPTIVE prefix is trimmed and the
                    # "_<handle>" suffix is always kept - truncating the suffix away would let two
                    # suggestions with different handles collide on the same name.
                    $handleSuffix = "_$($row.IndexHandle)"
                    $prefix = "IX_$($row.TableName)_" + ($indexNameParts -join '_')
                    $maxPrefix = 128 - $handleSuffix.Length
                    if ($prefix.Length -gt $maxPrefix) { $prefix = $prefix.Substring(0, $maxPrefix) }
                    $suggestedName = $prefix + $handleSuffix
                    $suggestedNameQuoted = "[" + ($suggestedName -replace ']', ']]') + "]"

                    # OBJECT_NAME / OBJECT_SCHEMA_NAME (and so their QUOTENAME results) return NULL when
                    # the login can read the missing-index DMV but has no metadata permission on the
                    # object. Emitting a CREATE INDEX ... ON .(...) in that case would be invalid T-SQL
                    # that looks runnable, so suppress the statement and warn instead. The row is still
                    # returned (impact, columns, handle) - only the generated DDL is withheld.
                    if ($row.SchemaNameQuoted -is [System.DBNull] -or $row.TableNameQuoted -is [System.DBNull] -or
                        [string]::IsNullOrEmpty($row.SchemaNameQuoted) -or [string]::IsNullOrEmpty($row.TableNameQuoted)) {
                        Write-Message -Level Warning -Message "Object metadata for object_id $($row.ObjectId) in $($row.DatabaseName) is not visible to this login; returning the suggestion without a CREATE statement. Grant metadata access to the object to generate DDL."
                        $createStatement = $null
                    } else {
                        # SchemaNameQuoted / TableNameQuoted come back from QUOTENAME(), so a ] in an
                        # object name is already escaped.
                        $createStatement = "CREATE NONCLUSTERED INDEX $suggestedNameQuoted ON $($row.SchemaNameQuoted).$($row.TableNameQuoted) ($keyColText)"
                        if ($row.IncludedColumns -isnot [System.DBNull] -and $row.IncludedColumns) {
                            $createStatement += " INCLUDE ($($row.IncludedColumns))"
                        }
                        $createStatement += ";"
                    }

                    $overlapping = if ($row.OverlappingIndex -is [System.DBNull]) { $null } else { $row.OverlappingIndex }

                    [PSCustomObject]@{
                        ComputerName      = $server.ComputerName
                        InstanceName      = $server.ServiceName
                        SqlInstance       = $server.DomainInstanceName
                        Database          = $row.DatabaseName
                        Schema            = $row.SchemaName
                        Table             = $row.TableName
                        EqualityColumns   = if ($row.EqualityColumns -is [System.DBNull]) { $null } else { $row.EqualityColumns }
                        InequalityColumns = if ($row.InequalityColumns -is [System.DBNull]) { $null } else { $row.InequalityColumns }
                        IncludedColumns   = if ($row.IncludedColumns -is [System.DBNull]) { $null } else { $row.IncludedColumns }
                        ImpactScore       = $row.ImpactScore
                        AvgTotalUserCost  = $row.AvgTotalUserCost
                        AvgUserImpact     = $row.AvgUserImpact
                        UserSeeks         = $row.UserSeeks
                        UserScans         = $row.UserScans
                        UniqueCompiles    = $row.UniqueCompiles
                        LastUserSeek      = $row.LastUserSeek
                        LastUserScan      = $row.LastUserScan
                        StartTime         = if ($server.DatabaseEngineType -eq 'SqlAzureDatabase') { $null } else { $server.Databases['tempdb'].CreateDate }
                        QueryHash         = if ($row.PSObject.Properties.Name -contains 'QueryHash') { $row.QueryHash } else { $null }
                        LastSqlHandle     = if ($row.PSObject.Properties.Name -contains 'LastSqlHandle') { $row.LastSqlHandle } else { $null }
                        OverlappingIndex  = $overlapping
                        CreateStatement   = $createStatement
                    } | Select-DefaultView -Property SqlInstance, Database, Schema, Table, ImpactScore, UserSeeks, AvgUserImpact, OverlappingIndex, CreateStatement
                }
            } finally {
                # Put the shared connection back where the caller had it, using the same internal
                # helper Find-DbaDbDisabledIndex uses (see #10555). Only on the on-prem path, where we
                # recorded a starting database; the Azure path used a dedicated database-scoped
                # connection and never moved the caller's context, so there is nothing to restore.
                if ($null -ne $currentDatabase) {
                    Restore-DatabaseContext -Server $server -Database $currentDatabase
                }
            }
        }
    }
}
