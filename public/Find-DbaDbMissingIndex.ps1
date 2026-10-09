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

    .PARAMETER ExcludeDatabase
        The database(s) to exclude.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase.

    .PARAMETER MinimumImpact
        Minimum impact score (avg_total_user_cost * avg_user_impact * (user_seeks + user_scans))
        for a suggestion to be returned. Filters out low-value noise. Default: 50.

    .PARAMETER MinimumSeek
        Minimum number of seeks (user_seeks) for a suggestion to be returned. Default: 1.

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
        # where these DMVs only ever return rows for the connected database. The 2019+ query-text
        # join is spliced in from the process block via $queryTextCte / $queryTextSelect /
        # $queryTextJoin so pre-2019 instances get a clean query.
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
)
{0}
SELECT
    DB_NAME(mid.database_id)        AS DatabaseName,
    mid.database_id                 AS DatabaseId,
    OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id) AS SchemaName,
    OBJECT_NAME(mid.object_id, mid.database_id)        AS TableName,
    mid.object_id                   AS ObjectId,
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
    CAST(mig.avg_total_user_cost * mig.avg_user_impact * (mig.user_seeks + mig.user_scans) AS decimal(28,4)) AS ImpactScore
    {1}
FROM mig
INNER JOIN sys.dm_db_missing_index_groups  AS mig_grp ON mig.group_handle = mig_grp.index_group_handle
INNER JOIN sys.dm_db_missing_index_details AS mid     ON mig_grp.index_handle = mid.index_handle
{2}
WHERE mid.database_id = DB_ID()
  AND mig.user_seeks >= {3}
  AND (mig.avg_total_user_cost * mig.avg_user_impact * (mig.user_seeks + mig.user_scans)) >= {4}
ORDER BY ImpactScore DESC;
"@
        # Note: the SMO Database.Query() method does not support parameterized queries, so the
        # two thresholds are formatted into the statement directly. Both are validated numeric
        # parameters ([int] MinimumSeek, [double] MinimumImpact), so there is no injection risk;
        # they are rendered with the invariant culture so a comma decimal separator can't break
        # the SQL on non-US locales.
    }

    process {
        $databases = @()

        foreach ($instance in $SqlInstance) {
            try {
                # Missing-index DMVs exist since SQL Server 2005; 2000 is skipped cleanly.
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $databases += Get-DbaDatabase -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase -ExcludeSystem -OnlyAccessible
        }

        foreach ($db in $InputObject) {
            if ($db.IsSystemObject -or -not $db.IsAccessible) { continue }
            $databases += $db
        }

        foreach ($db in $databases) {
            $server = $db.Parent
            Write-Message -Level Verbose -Message "Processing $($db.Name) on $($server.Name)"

            # Warn once per instance when the 600-group collection ceiling is reached - past it,
            # the DMVs stop recording new suggestions.
            try {
                $groupCount = ($server.Query("SELECT COUNT(*) AS cnt FROM sys.dm_db_missing_index_group_stats")).cnt
                if ($groupCount -ge 600) {
                    Write-Message -Level Warning -Message "Instance $($server.Name) has reached the 600 missing-index-group collection limit; suggestions beyond it are not recorded."
                }
            } catch {
                # Non-fatal; carry on with the analysis.
                Write-Message -Level Verbose -Message "Could not read missing-index group count on $($server.Name): $($_.Exception.Message)"
            }

            # The 2019+/Azure query-text DMV (one row per query, so joined separately from
            # group_stats to avoid double-counting the seek/scan totals).
            if ($server.VersionMajor -ge 15) {
                $queryTextCte = ", qt AS (
    SELECT
        migsq.group_handle,
        qs.query_hash,
        qs.last_sql_handle
    FROM sys.dm_db_missing_index_group_stats_query AS migsq
    CROSS APPLY (
        SELECT TOP (1) query_hash, last_sql_handle
        FROM sys.dm_db_missing_index_group_stats_query AS inner_q
        WHERE inner_q.group_handle = migsq.group_handle
        ORDER BY inner_q.last_user_seek DESC
    ) AS qs
    GROUP BY migsq.group_handle, qs.query_hash, qs.last_sql_handle
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

            try {
                $results = $db.Query($sql)
            } catch {
                Stop-Function -Message "Failure executing missing-index analysis against $($db.Name) on $($server.Name)" -ErrorRecord $_ -Target $db -Continue
            }

            # Existing indexes on the table, used to flag (not filter) overlapping suggestions.
            # Keyed by object_id so we only pull each table's indexes once.
            $existingIndexCache = @{ }

            foreach ($row in $results) {
                # Build the CREATE INDEX statement: equality columns, then inequality columns in
                # the key, then the remainder as INCLUDE. No edition-specific options (ONLINE etc.).
                $keyCols = @()
                if ($row.EqualityColumns) { $keyCols += $row.EqualityColumns }
                if ($row.InequalityColumns) { $keyCols += $row.InequalityColumns }
                $keyColText = ($keyCols -join ', ')

                $indexNameParts = @()
                foreach ($c in ($keyColText -split ',')) {
                    $clean = ($c -replace '[\[\]]', '').Trim()
                    if ($clean) { $indexNameParts += $clean }
                }
                $suggestedName = "IX_$($row.TableName)_" + ($indexNameParts -join '_')
                if ($suggestedName.Length -gt 128) { $suggestedName = $suggestedName.Substring(0, 128) }

                $createStatement = "CREATE NONCLUSTERED INDEX [$suggestedName] ON [$($row.SchemaName)].[$($row.TableName)] ($keyColText)"
                if ($row.IncludedColumns) {
                    $createStatement += " INCLUDE ($($row.IncludedColumns))"
                }
                $createStatement += ";"

                # Overlap detection: name any existing index whose leading key column matches this
                # suggestion's first key column. Flagged, never filtered - a near-duplicate is
                # exactly the case a human most wants to review.
                $overlapping = $null
                if ($keyColText) {
                    $firstKey = (($keyColText -split ',')[0] -replace '[\[\]]', '').Trim()
                    if (-not $existingIndexCache.ContainsKey($row.ObjectId)) {
                        try {
                            $smoTable = $db.Tables | Where-Object { $_.ID -eq $row.ObjectId }
                            $existingIndexCache[$row.ObjectId] = $smoTable
                        } catch {
                            $existingIndexCache[$row.ObjectId] = $null
                        }
                    }
                    $smoTable = $existingIndexCache[$row.ObjectId]
                    if ($smoTable) {
                        foreach ($idx in $smoTable.Indexes) {
                            $leadingCol = ($idx.IndexedColumns | Where-Object { -not $_.IsIncluded } | Sort-Object ID | Select-Object -First 1).Name
                            if ($leadingCol -and $leadingCol -eq $firstKey) {
                                $overlapping = $idx.Name
                                break
                            }
                        }
                    }
                }

                [PSCustomObject]@{
                    ComputerName      = $server.ComputerName
                    InstanceName      = $server.ServiceName
                    SqlInstance       = $server.DomainInstanceName
                    Database          = $row.DatabaseName
                    Schema            = $row.SchemaName
                    Table             = $row.TableName
                    EqualityColumns   = $row.EqualityColumns
                    InequalityColumns = $row.InequalityColumns
                    IncludedColumns   = $row.IncludedColumns
                    ImpactScore       = $row.ImpactScore
                    AvgTotalUserCost  = $row.AvgTotalUserCost
                    AvgUserImpact     = $row.AvgUserImpact
                    UserSeeks         = $row.UserSeeks
                    UserScans         = $row.UserScans
                    UniqueCompiles    = $row.UniqueCompiles
                    LastUserSeek      = $row.LastUserSeek
                    LastUserScan      = $row.LastUserScan
                    StartTime         = $server.Databases['tempdb'].CreateDate
                    QueryHash         = if ($row.PSObject.Properties.Name -contains 'QueryHash') { $row.QueryHash } else { $null }
                    LastSqlHandle     = if ($row.PSObject.Properties.Name -contains 'LastSqlHandle') { $row.LastSqlHandle } else { $null }
                    OverlappingIndex  = $overlapping
                    CreateStatement   = $createStatement
                } | Select-DefaultView -Property SqlInstance, Database, Schema, Table, ImpactScore, UserSeeks, AvgUserImpact, OverlappingIndex, CreateStatement
            }
        }
    }
}