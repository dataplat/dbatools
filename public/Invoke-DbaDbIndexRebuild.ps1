function Invoke-DbaDbIndexRebuild {
    <#
    .SYNOPSIS
        Rebuilds or reorganizes indexes and heaps across one or more databases.

    .DESCRIPTION
        Performs index maintenance against a collection of databases, tables, indexed views and indexes, exposing the full ALTER INDEX option set through SMO. Runs in three modes: Rebuild, Reorganize, or Auto, where Auto picks the operation per index from measured fragmentation the way Ola Hallengren's IndexOptimize does.

        Fragmentation is measured once per database with a LIMITED scan of sys.dm_db_index_physical_stats, averaged across partitions by page count and read from the IN_ROW_DATA allocation units only. That scan drives the Auto decision, the MinimumFragmentation and MinimumPageCount filters, and the reported before and after numbers.

        Columnstore indexes are the exception: that DMV only sees their rowstore parts, so their fragmentation and page counts are reported as null and they are skipped in Auto mode or under either filter. Maintain them with an explicit Mode instead.

        Heaps are included with IncludeHeap. Heaps cannot be reorganized, and the popular maintenance solutions leave them alone entirely, so this is the only way to defragment one without hand-writing ALTER TABLE ... REBUILD. Rebuilding a heap also rebuilds the table's nonclustered indexes, so those are not rebuilt a second time in the same run.

        Objects that cannot be processed are skipped with a warning rather than failing the run, so a single unsupported index does not stop maintenance across the rest of the instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Requires SQL Server 2005 or later, because ALTER INDEX and sys.dm_db_index_physical_stats do not exist on SQL Server 2000.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to maintain on the target instance. Accepts multiple database names.
        Use this when you want index maintenance on a known set of databases rather than the whole instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from index maintenance, including databases that arrived through the pipeline.
        Useful when maintaining every user database but skipping ones that have their own maintenance window.

    .PARAMETER AllDatabases
        Targets every accessible database on the instance, including the system databases master, model and msdb.
        Requiring this switch means an unqualified call never silently rebuilds every index on the instance.

    .PARAMETER AllUserDatabases
        Targets all user databases on the instance, excluding the system databases.
        Use this for routine maintenance across an instance while leaving system databases alone.

    .PARAMETER Table
        Limits maintenance to specific tables. Accepts schema-qualified names such as dbo.Orders, and bracketed names for objects with special characters.
        When omitted, every non-system table in the selected databases is processed along with any indexed views.

    .PARAMETER Index
        Limits maintenance to specific index names within the selected tables.
        Use this to rebuild one known problem index rather than everything on the table. Heaps have no index name, so no heap is returned when this is specified.

    .PARAMETER Mode
        Controls which operation is performed. Rebuild issues ALTER INDEX ... REBUILD, Reorganize issues ALTER INDEX ... REORGANIZE, and Auto decides per index from measured fragmentation. Defaults to Rebuild.
        Reorganize is skipped with a warning for heaps, disabled indexes, and indexes with ALLOW_PAGE_LOCKS = OFF, none of which SQL Server will reorganize.
        Auto is the Ola Hallengren approach: below ReorganizeThreshold the index is left alone, between the two thresholds it is reorganized, and at or above RebuildThreshold it is rebuilt.
        Reorganize takes none of the rebuild options, so under Reorganize they are listed in a warning and skipped rather than refused. Auto still refuses an invalid rebuild combination, because Auto can decide to rebuild.

    .PARAMETER ReorganizeThreshold
        Sets the fragmentation percentage at which Auto mode starts reorganizing an index. Defaults to 5.
        Indexes below this level are skipped entirely because the cost of maintenance outweighs the benefit.

    .PARAMETER RebuildThreshold
        Sets the fragmentation percentage at which Auto mode switches from reorganize to rebuild. Defaults to 30.
        Only applies when Mode is Auto.

    .PARAMETER MinimumFragmentation
        Skips any index whose measured fragmentation is below this percentage, in every mode.
        Use this to make an explicit Rebuild or Reorganize run skip indexes that are already healthy. Columnstore indexes cannot be measured this way and are skipped with a warning when this is specified.

    .PARAMETER MinimumPageCount
        Skips any index or heap smaller than this many pages. Defaults to 0, which processes everything.
        A common cutoff is 1000 pages, below which fragmentation rarely costs enough to be worth acting on. Columnstore indexes cannot be measured this way and are skipped with a warning when this is above 0.

    .PARAMETER Online
        Performs the rebuild online so the table stays available to other sessions for the duration.
        Requires Enterprise or Developer edition, or Azure SQL Database. Anything that cannot be rebuilt online is skipped with a warning rather than being rebuilt offline behind your back: XML and spatial indexes, which SQL Server never rebuilds online on any version, edition or platform, columnstore indexes before SQL Server 2019, heaps before SQL Server 2014, and disabled clustered indexes and indexed views.

    .PARAMETER MaxDop
        Limits the number of processors used for the operation by adding MAXDOP, from 0 to 64.
        Use this to stop a large rebuild from consuming every core on a busy instance.

    .PARAMETER FillFactor
        Sets the fill factor percentage applied during the rebuild, from 1 to 100.
        Leaving free space on each page reduces page splits on indexes that see frequent inserts into the middle of the key range. Omit it to keep whatever fill factor the index already has.

    .PARAMETER PadIndex
        Applies the fill factor to the intermediate index pages as well as the leaf level.
        Only meaningful alongside FillFactor, and ignored by REORGANIZE.

    .PARAMETER SortInTempdb
        Performs the intermediate sort for the rebuild in tempdb instead of the destination filegroup.
        Speeds up rebuilds when tempdb is on separate storage, at the cost of extra tempdb space. Cannot be combined with Resumable.

    .PARAMETER Resumable
        Makes the rebuild resumable so it can be paused and continued rather than rolled back.
        Requires SQL Server 2017 or later, or Azure SQL Database, and must be combined with Online. It is dropped, and the reason recorded in Notes, for everything SQL Server documents as unsupported: heaps, columnstore indexes, disabled indexes, filtered indexes, a computed or rowversion key column, and a computed or LOB included column. Those objects are rebuilt without it rather than being skipped.

    .PARAMETER ResumableMaxDuration
        Sets how many minutes a resumable rebuild runs before it pauses on its own, from 1 to 10080 (7 days).
        Use this to fit index maintenance into a fixed maintenance window without leaving a long rollback behind.

    .PARAMETER WaitAtLowPriority
        Makes the online rebuild wait at low priority for the schema modification locks it needs, so it does not block short queries behind it.
        Requires SQL Server 2014 or later, or Azure SQL Database, and must be combined with Online.

    .PARAMETER MaxDurationMinutes
        Sets how many minutes the low priority wait lasts before AbortAfterWait takes effect, from 0 to 71582.
        Only applies when WaitAtLowPriority is specified, and must be at least 1 when AbortAfterWait is not None.

    .PARAMETER AbortAfterWait
        Specifies what happens when the low priority wait expires. None lets the operation keep waiting normally, Self aborts the rebuild, and Blockers kills the sessions holding the blocking locks. Defaults to None.
        Anything other than None needs both WaitAtLowPriority and MaxDurationMinutes, because there is otherwise no wait to abort after.

    .PARAMETER IncludeHeap
        Includes heaps, meaning tables with no clustered index, rebuilt with ALTER TABLE ... REBUILD.
        Heaps fragment through forwarded records and deleted rows but are ignored by most maintenance solutions, so they are opt-in here rather than silently rebuilt. A heap rebuild also rebuilds the table's nonclustered indexes, so the rest of that table is skipped for the run: their measured fragmentation is stale from that point on.

    .PARAMETER StatementTimeout
        Sets the command timeout in minutes for each operation, from 0 to 35791394. Defaults to 0 (infinite timeout).
        Large rebuilds can run for hours, so the default lets them finish rather than failing partway through.

    .PARAMETER InputObject
        Accepts SMO objects from the pipeline: databases from Get-DbaDatabase, tables from Get-DbaDbTable, or views from Get-DbaDbView.
        Use this to filter the target objects with the full power of those commands before handing them over for maintenance.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run.

    .PARAMETER Confirm
        Prompts for confirmation of every step. For example:

        Are you sure you want to perform this action?
        Performing the operation "Rebuild ClusteredIndex PK_Orders" on target "dbo.Orders in Northwind on SQL2016".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per index or heap that was actually processed. Objects filtered out by a threshold, or skipped because they are incompatible with the requested operation, produce verbose messages or warnings instead of output. Nothing is returned when WhatIf is used.

        Default display properties (via Select-DefaultView):
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: Name of the database containing the object
        - Schema: Schema of the table or view
        - Table: Name of the table or view
        - IndexName: Name of the index, or the table name when the object is a heap
        - IndexType: The SMO index type such as ClusteredIndex or NonClusteredIndex, or "Heap" for a heap
        - Operation: The operation performed, either Rebuild or Reorganize
        - PageCount: Number of pages in the index or heap as measured before the operation (long); null for a columnstore index
        - FragmentationBefore: Average fragmentation percentage before the operation (double, 0-100); null for a columnstore index
        - FragmentationAfter: Average fragmentation percentage after the operation (double, 0-100); null when the operation failed or the object is a columnstore index
        - Duration: Elapsed time of the operation as hours:minutes:seconds, where hours is a running total rather than a clock reading
        - Success: Boolean indicating whether the operation completed without error

        Additional properties available:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - Online: Boolean indicating whether the operation actually ran online; always true for a reorganize, which never takes the object offline
        - Resumable: Boolean indicating whether the operation actually ran as resumable
        - Start: DateTime when the operation began
        - End: DateTime when the operation completed
        - Notes: Error text when the operation failed, or an explanation of why requested options were suppressed; null otherwise

    .NOTES
        Tags: Index, Maintenance, Rebuild, Reorganize, Fragmentation
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbIndexRebuild

    .EXAMPLE
        PS C:\> Invoke-DbaDbIndexRebuild -SqlInstance sql2017 -Database Northwind

        Rebuilds every index on every table and indexed view in Northwind.

    .EXAMPLE
        PS C:\> Invoke-DbaDbIndexRebuild -SqlInstance sql2017 -AllUserDatabases -Mode Auto -MinimumPageCount 1000

        Runs fragmentation driven maintenance across all user databases, leaving indexes under 1000 pages alone, reorganizing those between 5 and 30 percent fragmented and rebuilding anything worse.

    .EXAMPLE
        PS C:\> Invoke-DbaDbIndexRebuild -SqlInstance sql2019 -Database Sales -Table dbo.Orders -Index IX_Orders_CustomerID -Online -MaxDop 4

        Rebuilds one named index online, limited to four processors.

    .EXAMPLE
        PS C:\> Invoke-DbaDbIndexRebuild -SqlInstance sql2019 -Database Sales -Online -Resumable -ResumableMaxDuration 60

        Rebuilds the indexes in Sales as a resumable online operation that pauses itself after an hour, so maintenance fits inside a fixed window.

    .EXAMPLE
        PS C:\> Invoke-DbaDbIndexRebuild -SqlInstance sql2019 -Database Staging -IncludeHeap

        Rebuilds the indexes in Staging and also rebuilds its heaps, which most maintenance solutions skip entirely.

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql2019 -Database Sales -Table dbo.Orders | Invoke-DbaDbIndexRebuild -Mode Reorganize

        Reorganizes the indexes on a table piped in from Get-DbaDbTable.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2019 | Where-Object Name -match "^prod" | Invoke-DbaDbIndexRebuild -Mode Auto

        Runs Auto mode against the databases whose names start with prod.

    .EXAMPLE
        PS C:\> Invoke-DbaDbIndexRebuild -SqlInstance sql2022 -Database Sales -Online -WaitAtLowPriority -MaxDurationMinutes 5 -AbortAfterWait Blockers

        Rebuilds online, waiting at low priority for five minutes for the locks it needs, then killing the blocking sessions if they have not cleared.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [switch]$AllUserDatabases,
        [string[]]$Table,
        [string[]]$Index,
        [ValidateSet("Rebuild", "Reorganize", "Auto")]
        [string]$Mode = "Rebuild",
        [ValidateRange(0, 100)]
        [double]$ReorganizeThreshold = 5,
        [ValidateRange(0, 100)]
        [double]$RebuildThreshold = 30,
        [ValidateRange(0, 100)]
        [double]$MinimumFragmentation,
        [ValidateRange(0, 2147483647)]
        [int]$MinimumPageCount = 0,
        [switch]$Online,
        [ValidateRange(0, 64)]
        [int]$MaxDop,
        [ValidateRange(1, 100)]
        [int]$FillFactor,
        [switch]$PadIndex,
        [switch]$SortInTempdb,
        [switch]$Resumable,
        # The two MAX_DURATION clauses have different ceilings: 10080 minutes (7 days) for RESUMABLE,
        # 71582 for WAIT_AT_LOW_PRIORITY. Both were confirmed against SQL Server 2022.
        [ValidateRange(1, 10080)]
        [int]$ResumableMaxDuration,
        [switch]$WaitAtLowPriority,
        [ValidateRange(0, 71582)]
        [int]$MaxDurationMinutes,
        [ValidateSet("None", "Self", "Blockers")]
        [string]$AbortAfterWait = "None",
        [switch]$IncludeHeap,
        # The ceiling is int.MaxValue seconds expressed in minutes, because SMO's StatementTimeout is signed 32 bit seconds.
        [ValidateRange(0, 35791394)]
        [int]$StatementTimeout = 0,
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($ReorganizeThreshold -gt $RebuildThreshold) {
            Stop-Function -Message "ReorganizeThreshold ($ReorganizeThreshold) cannot be greater than RebuildThreshold ($RebuildThreshold)."
            return
        }

        if ($Mode -eq "Reorganize") {
            $ignoredByReorganize = @()
            # REORGANIZE is always an online operation, so -Online is not in this list: it is redundant, not ignored.
            foreach ($optionName in "FillFactor", "PadIndex", "SortInTempdb", "MaxDop", "Resumable", "ResumableMaxDuration", "WaitAtLowPriority", "MaxDurationMinutes", "AbortAfterWait") {
                if (Test-Bound -ParameterName $optionName) {
                    $ignoredByReorganize += $optionName
                }
            }
            if ($ignoredByReorganize) {
                Write-Message -Level Warning -Message "REORGANIZE ignores these options and they will not be applied: $($ignoredByReorganize -join ", ")"
            }
        } else {
            # Every option below belongs to REBUILD, so these combinations are only wrong when a rebuild can
            # actually happen. Under -Mode Reorganize the options are already reported as ignored above, and
            # refusing to run there would be a hard stop over something the caller was told does not apply.
            if ($Resumable -and -not $Online) {
                Stop-Function -Message "A resumable index operation requires ONLINE = ON. Add -Online, or drop -Resumable."
                return
            }

            if ($WaitAtLowPriority -and -not $Online) {
                Stop-Function -Message "WAIT_AT_LOW_PRIORITY only applies to online index operations. Add -Online, or drop -WaitAtLowPriority."
                return
            }

            if ($Resumable -and $SortInTempdb) {
                Stop-Function -Message "SORT_IN_TEMPDB = ON cannot be combined with RESUMABLE = ON. Drop -SortInTempdb, or drop -Resumable."
                return
            }

            if ($AbortAfterWait -ne "None" -and -not $WaitAtLowPriority) {
                Stop-Function -Message "AbortAfterWait only has meaning inside a low priority wait. Add -WaitAtLowPriority, or drop -AbortAfterWait."
                return
            }

            if ($AbortAfterWait -ne "None" -and $MaxDurationMinutes -lt 1) {
                Stop-Function -Message "AbortAfterWait $AbortAfterWait needs something to wait for. Set -MaxDurationMinutes to at least 1."
                return
            }
        }

        $statementTimeoutSeconds = $StatementTimeout * 60
        $fragmentationBound = Test-Bound -ParameterName MinimumFragmentation

        # One LIMITED scan per database drives the Auto decision, both filters and the reported numbers.
        # Only IN_ROW_DATA counts: LOB and row-overflow allocation units always report zero fragmentation and
        # would drag the average down. The average is weighted by pages so an unevenly filled partitioned index
        # is not decided by its smallest partition.
        $fragmentationSql = @"
SELECT s.object_id AS ObjectId, s.index_id AS IndexId, SUM(s.page_count) AS PageCount,
       CASE WHEN SUM(s.page_count) = 0 THEN 0.0
            ELSE SUM(s.avg_fragmentation_in_percent * s.page_count) / SUM(s.page_count) END AS AvgFragmentation
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') AS s
WHERE s.alloc_unit_type_desc = 'IN_ROW_DATA'
GROUP BY s.object_id, s.index_id
"@

        # Placeholders are filled with SMO object ids, which are integers, so this cannot carry injected text.
        $singleFragmentationSql = @"
SELECT CASE WHEN SUM(s.page_count) = 0 THEN 0.0
            ELSE SUM(s.avg_fragmentation_in_percent * s.page_count) / SUM(s.page_count) END AS AvgFragmentation
FROM sys.dm_db_index_physical_stats(DB_ID(), {0}, {1}, NULL, 'LIMITED') AS s
WHERE s.alloc_unit_type_desc = 'IN_ROW_DATA'
"@
    }

    process {
        if (Test-FunctionInterrupt) { return }

        $inputDatabase = @()
        $inputObjectByDatabase = New-Object -TypeName System.Collections.Hashtable

        foreach ($object in $InputObject) {
            $objectType = $object.GetType().FullName
            if ($objectType -eq "Microsoft.SqlServer.Management.Smo.Database") {
                $inputDatabase += $object
            } elseif ($objectType -in "Microsoft.SqlServer.Management.Smo.Table", "Microsoft.SqlServer.Management.Smo.View") {
                $parentDb = $object.Parent
                $dbKey = "$($parentDb.Parent.Name)|$($parentDb.Name)"
                if (-not $inputObjectByDatabase.ContainsKey($dbKey)) {
                    $inputObjectByDatabase[$dbKey] = [PSCustomObject]@{
                        Database = $parentDb
                        Objects  = @()
                    }
                }
                $inputObjectByDatabase[$dbKey].Objects += $object
            } else {
                $splatBadInput = @{
                    Message  = "InputObject of type $objectType is not supported. Pipe in databases from Get-DbaDatabase, tables from Get-DbaDbTable or views from Get-DbaDbView."
                    Target   = $object
                    Continue = $true
                }
                Stop-Function @splatBadInput
            }
        }

        if (-not $Database -and -not $ExcludeDatabase -and -not $AllDatabases -and -not $AllUserDatabases -and -not $InputObject) {
            Stop-Function -Message "You must specify databases to execute against using -Database, -ExcludeDatabase, -AllDatabases or -AllUserDatabases, or by piping them in"
            return
        }

        if (-not $SqlInstance -and -not $InputObject) {
            Stop-Function -Message "You must specify -SqlInstance, or pipe in databases from Get-DbaDatabase, tables from Get-DbaDbTable or views from Get-DbaDbView"
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $splatConnection = @{
                    SqlInstance    = $instance
                    SqlCredential  = $SqlCredential
                    MinimumVersion = 9
                }
                $server = Connect-DbaInstance @splatConnection
            } catch {
                $splatConnectionFailure = @{
                    Message     = "Failure"
                    Category    = "ConnectionError"
                    ErrorRecord = $PSItem
                    Target      = $instance
                    Continue    = $true
                }
                Stop-Function @splatConnectionFailure
            }

            $dbs = $server.Databases | Where-Object { $PSItem.IsAccessible }

            if ($AllUserDatabases -and -not $AllDatabases) {
                $dbs = $dbs | Where-Object { $PSItem.IsSystemObject -eq $false }
            }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                $inputDatabase += $db
            }
        }

        # A piped table brings its own database along, so those databases carry a restricted object list.
        $workItems = @()
        foreach ($db in $inputDatabase) {
            $workItems += [PSCustomObject]@{
                Database = $db
                Objects  = $null
            }
        }
        foreach ($entry in $inputObjectByDatabase.Values) {
            $workItems += $entry
        }

        # ExcludeDatabase has to reach piped databases and piped tables too, not only the ones -SqlInstance found.
        if ($ExcludeDatabase) {
            $workItems = $workItems | Where-Object { $PSItem.Database.Name -notin $ExcludeDatabase }
        }

        foreach ($workItem in $workItems) {
            $db = $workItem.Database
            $server = $db.Parent

            Write-Message -Level Verbose -Message "Processing $db on $server"

            if ($db.IsDatabaseSnapshot) {
                Write-Message -Level Warning -Message "Database $db on $server is a snapshot and is read only. Skipping."
                continue
            }

            if ($db.Status -ne "Normal") {
                Write-Message -Level Warning -Message "Database $db on $server has status $($db.Status) and will be skipped."
                continue
            }

            # A read-only database is online and accessible, so Status is Normal. Without this it would fail once per index.
            if (-not $db.IsUpdateable) {
                Write-Message -Level Warning -Message "Database $db on $server is read only and will be skipped."
                continue
            }

            # REORGANIZE takes neither clause, and begin{} already warned that they will be ignored. Failing
            # the database over a clause that is not going to be sent would contradict that warning.
            $optionsReachTheEngine = $Mode -ne "Reorganize"

            # Azure SQL Database reports version 12 but supports both clauses, so the version floors only apply to the box product.
            if ($optionsReachTheEngine -and $Resumable -and $server.VersionMajor -lt 14 -and -not $server.IsAzure) {
                $splatOldResumable = @{
                    Message  = "Resumable index operations require SQL Server 2017 (version 14) or later. $server is running version $($server.VersionMajor)."
                    Target   = $server
                    Continue = $true
                }
                Stop-Function @splatOldResumable
            }

            if ($optionsReachTheEngine -and $WaitAtLowPriority -and $server.VersionMajor -lt 12 -and -not $server.IsAzure) {
                $splatOldWait = @{
                    Message  = "WAIT_AT_LOW_PRIORITY requires SQL Server 2014 (version 12) or later. $server is running version $($server.VersionMajor)."
                    Target   = $server
                    Continue = $true
                }
                Stop-Function @splatOldWait
            }

            try {
                $fragmentationRows = $db.Query($fragmentationSql)
            } catch {
                $splatScanFailure = @{
                    Message     = "Failed to read index fragmentation for $db on $server"
                    ErrorRecord = $PSItem
                    Target      = $db
                    Continue    = $true
                }
                Stop-Function @splatScanFailure
            }

            $fragmentation = New-Object -TypeName System.Collections.Hashtable
            foreach ($row in $fragmentationRows) {
                $fragmentation["$($row.ObjectId)|$($row.IndexId)"] = $row
            }

            if ($workItem.Objects) {
                $objects = $workItem.Objects
            } elseif ($Table) {
                $tableParts = $Table | ForEach-Object { Get-ObjectNameParts -ObjectName $PSItem }
                $objects = foreach ($tablePart in $tableParts) {
                    $db.Tables | Where-Object {
                        $PSItem.IsSystemObject -eq $false -and
                        $PSItem.Name -eq $tablePart.Name -and
                        $tablePart.Schema -in ($PSItem.Schema, $null) -and
                        $tablePart.Database -in ($db.Name, $null)
                    }
                }
            } else {
                $objects = @($db.Tables | Where-Object { $PSItem.IsSystemObject -eq $false })
                # Indexed views are only worth walking when the caller did not name specific tables.
                $objects += @($db.Views | Where-Object { $PSItem.IsSystemObject -eq $false -and $PSItem.Indexes.Count -gt 0 })
            }

            foreach ($obj in $objects) {
                # Table.IsMemoryOptimized arrived with SQL Server 2014, and SMO throws rather than returning
                # false when the property does not exist on the server it is talking to. Nothing before 2014
                # has memory optimized tables anyway, so the question does not arise there.
                if ($server.VersionMajor -ge 12 -and $obj.IsMemoryOptimized) {
                    Write-Message -Level Verbose -Message "Skipping memory optimized object $($obj.Schema).$($obj.Name) in $db, ALTER INDEX REBUILD does not apply to it."
                    continue
                }

                $isView = $obj.GetType().FullName -eq "Microsoft.SqlServer.Management.Smo.View"

                $targets = @()

                # A heap is index_id 0 on the table itself rather than a member of the Indexes collection, and -Index cannot name it.
                # It goes first because rebuilding a heap moves every row, which rebuilds the table's nonclustered indexes too.
                if ($IncludeHeap -and -not $isView -and -not $obj.HasClusteredIndex -and -not $Index) {
                    $targets += [PSCustomObject]@{
                        Index     = $null
                        IndexId   = 0
                        IndexName = $obj.Name
                        IndexType = "Heap"
                        IsHeap    = $true
                    }
                }

                foreach ($smoIndex in $obj.Indexes) {
                    if ($Index -and $smoIndex.Name -notin $Index) {
                        continue
                    }
                    $targets += [PSCustomObject]@{
                        Index     = $smoIndex
                        IndexId   = $smoIndex.ID
                        IndexName = $smoIndex.Name
                        IndexType = "$($smoIndex.IndexType)"
                        IsHeap    = $false
                    }
                }

                $heapWasRebuilt = $false

                foreach ($target in $targets) {
                    $objectLabel = "$($db.Name).$($obj.Schema).$($obj.Name).$($target.IndexName)"
                    $isColumnstore = $target.IndexType -match "Columnstore"

                    # ALTER TABLE ... REBUILD on a heap moves every row, so SQL Server rebuilds the table's
                    # nonclustered indexes as part of it. Their measured fragmentation is stale from here on,
                    # which rules out an Auto decision as much as it rules out a second rebuild.
                    if ($heapWasRebuilt) {
                        Write-Message -Level Verbose -Message "Skipping $objectLabel, the heap rebuild on this table already rebuilt it."
                        continue
                    }

                    if ($isColumnstore) {
                        # sys.dm_db_index_physical_stats only sees a columnstore index's rowstore parts, so a
                        # clustered columnstore over millions of rows reports a handful of pages and a fragmentation
                        # figure that means nothing. Reporting nothing beats reporting that.
                        $pageCount = $null
                        $fragmentationBefore = $null
                        $hasStats = $false
                    } else {
                        $statsRow = $fragmentation["$($obj.ID)|$($target.IndexId)"]

                        if ($statsRow) {
                            $pageCount = [long]$statsRow.PageCount
                            $fragmentationBefore = [math]::Round([double]$statsRow.AvgFragmentation, 2)
                            $hasStats = $true
                        } else {
                            # An index with no allocated pages has no row in the DMV at all.
                            $pageCount = [long]0
                            $fragmentationBefore = [double]0
                            $hasStats = $false
                        }

                        if ($pageCount -lt $MinimumPageCount) {
                            Write-Message -Level Verbose -Message "Skipping $objectLabel, $pageCount pages is below MinimumPageCount $MinimumPageCount."
                            continue
                        }

                        if ($fragmentationBound -and $fragmentationBefore -lt $MinimumFragmentation) {
                            Write-Message -Level Verbose -Message "Skipping $objectLabel, $fragmentationBefore percent fragmentation is below MinimumFragmentation $MinimumFragmentation."
                            continue
                        }
                    }

                    if ($isColumnstore -and ($Mode -eq "Auto" -or $fragmentationBound -or $MinimumPageCount -gt 0)) {
                        Write-Message -Level Warning -Message "Skipping columnstore index $objectLabel, its fragmentation cannot be measured with sys.dm_db_index_physical_stats. Run it with an explicit -Mode Rebuild or -Mode Reorganize and no fragmentation or page filters."
                        continue
                    }

                    if ($Mode -eq "Auto") {
                        if (-not $hasStats) {
                            Write-Message -Level Verbose -Message "Skipping $objectLabel in Auto mode, it has no allocated pages to measure."
                            continue
                        }
                        if ($fragmentationBefore -lt $ReorganizeThreshold) {
                            Write-Message -Level Verbose -Message "Skipping $objectLabel, $fragmentationBefore percent fragmentation is below ReorganizeThreshold $ReorganizeThreshold."
                            continue
                        }
                        if ($fragmentationBefore -ge $RebuildThreshold) {
                            $operation = "Rebuild"
                        } else {
                            $operation = "Reorganize"
                        }
                    } else {
                        $operation = $Mode
                    }

                    if ($operation -eq "Reorganize") {
                        if ($target.IsHeap) {
                            Write-Message -Level Warning -Message "Skipping heap $objectLabel, a heap cannot be reorganized. Use -Mode Rebuild to defragment it."
                            continue
                        }
                        if ($target.Index.IsDisabled) {
                            Write-Message -Level Warning -Message "Skipping disabled index $objectLabel, REORGANIZE cannot run against a disabled index. Use -Mode Rebuild to re-enable it."
                            continue
                        }
                        # REORGANIZE compacts pages, so ALLOW_PAGE_LOCKS = OFF rules it out. The engine raises
                        # error 2552 for it, and in Auto mode that would fail an index the caller never singled out.
                        if (-not $isColumnstore -and $target.Index.DisallowPageLocks) {
                            Write-Message -Level Warning -Message "Skipping $objectLabel, REORGANIZE needs page level locking and this index has ALLOW_PAGE_LOCKS = OFF. Use -Mode Rebuild to defragment it."
                            continue
                        }
                    }

                    $suppressed = @()
                    $useOnline = [bool]$Online
                    $useResumable = [bool]$Resumable

                    if ($operation -eq "Rebuild" -and $useOnline) {
                        # Never quietly downgrade to an offline rebuild: -Online is what stands between the caller
                        # and a table lock, so anything that cannot honour it is skipped or fails out loud.

                        # Online index operations are an Enterprise feature of the box product, and SQL Server 2016
                        # SP1 did not move them to Standard. A whitelist rather than a Standard check: Web, Express
                        # and Personal cannot do this either, and SMO reports Developer as EnterpriseOrDeveloper.
                        # Azure SQL Database and Managed Instance always have them.
                        if ("$($server.EngineEdition)" -ne "EnterpriseOrDeveloper" -and -not $server.IsAzure) {
                            Write-Message -Level Warning -Message "Skipping $objectLabel, an online rebuild requires Enterprise or Developer edition and $server is $($server.EngineEdition). Drop -Online to rebuild it offline."
                            continue
                        }

                        if ($target.IsHeap) {
                            # ALTER TABLE ... REBUILD WITH (ONLINE = ON) arrived with SQL Server 2014.
                            if ($server.VersionMajor -lt 12 -and -not $server.IsAzure) {
                                Write-Message -Level Warning -Message "Skipping heap $objectLabel, an online heap rebuild requires SQL Server 2014 (version 12) or later. $server is running version $($server.VersionMajor). Drop -Online to rebuild it offline."
                                continue
                            }
                        } elseif ($target.IndexType -match "Xml|Spatial") {
                            # ALTER INDEX documents this with no version, edition or platform caveat: for an XML or
                            # spatial index only ONLINE = OFF is supported, and ONLINE = ON raises an error. Azure
                            # SQL Database is no exception, so this sits ahead of the Azure allowance below.
                            Write-Message -Level Warning -Message "Skipping $objectLabel, SQL Server does not support an online rebuild of an XML or spatial index on any version, edition or platform. Drop -Online to rebuild it offline."
                            continue
                        } elseif ($isColumnstore) {
                            # Online rebuild of a columnstore index arrived with SQL Server 2019, and Azure SQL
                            # Database has it as well.
                            if ($server.VersionMajor -lt 15 -and -not $server.IsAzure) {
                                Write-Message -Level Warning -Message "Skipping columnstore index $objectLabel, an online columnstore rebuild requires SQL Server 2019 (version 15) or later. $server is running version $($server.VersionMajor). Drop -Online to rebuild it offline."
                                continue
                            }
                        } elseif ($target.Index.IsDisabled -and ($target.IndexType -match "^Clustered" -or $isView)) {
                            # The last documented exclusion for ALTER INDEX REBUILD ONLINE: a disabled clustered
                            # index or a disabled indexed view. A disabled nonclustered index rebuilds online fine.
                            Write-Message -Level Warning -Message "Skipping $objectLabel, SQL Server does not rebuild a disabled clustered index or indexed view online. Drop -Online to rebuild it offline."
                            continue
                        } elseif ($server.VersionMajor -lt 11 -and -not $server.IsAzure -and -not $target.Index.IsOnlineRebuildSupported) {
                            # SMO decides IsOnlineRebuildSupported from the SQL Server 2008 rules and never caught up:
                            # it reports false for a nonclustered index with a LOB included column, which SQL Server
                            # 2012 made legal and SQL Server 2022 rebuilds online happily, and false for every
                            # columnstore index regardless of version. Below 2012 those rules are still the engine's,
                            # so the property is worth asking there and nowhere else.
                            Write-Message -Level Warning -Message "Skipping $objectLabel, this index does not support an online rebuild on $server. Drop -Online to rebuild it offline."
                            continue
                        }
                    }

                    if ($useResumable) {
                        if ($target.IsHeap) {
                            $useResumable = $false
                            $suppressed += "Resumable, which does not apply to heaps"
                        } elseif ($isColumnstore) {
                            $useResumable = $false
                            $suppressed += "Resumable, which a columnstore index does not support"
                        } elseif ($target.Index.IsDisabled) {
                            $useResumable = $false
                            $suppressed += "Resumable, which cannot re-enable a disabled index"
                        } elseif ($target.Index.HasFilter) {
                            $useResumable = $false
                            $suppressed += "Resumable, which is not supported for a filtered index"
                        } else {
                            # The documented restrictions, which SQL Server does not always enforce by failing the
                            # statement: a computed or rowversion key column, and a computed or LOB included column.
                            # A nonclustered index silently carries the clustered key, so its restrictions apply here too.
                            $keyColumnNames = @($target.Index.IndexedColumns | Where-Object { -not $PSItem.IsIncluded } | Select-Object -ExpandProperty Name)
                            if ($target.IndexType -notmatch "^Clustered" -and $obj.HasClusteredIndex) {
                                $clusteredIndex = $obj.Indexes | Where-Object { $PSItem.IndexType -match "^Clustered" -and $PSItem.IndexType -notmatch "Columnstore" }
                                $keyColumnNames += @($clusteredIndex.IndexedColumns | Where-Object { -not $PSItem.IsIncluded } | Select-Object -ExpandProperty Name)
                            }

                            $blockingColumn = $null
                            foreach ($keyColumnName in $keyColumnNames) {
                                $keyColumn = $obj.Columns[$keyColumnName]
                                if ($keyColumn.Computed) {
                                    $blockingColumn = "key computed column $keyColumnName"
                                    break
                                }
                                if ("$($keyColumn.DataType.SqlDataType)" -eq "Timestamp") {
                                    $blockingColumn = "key rowversion column $keyColumnName"
                                    break
                                }
                            }

                            if (-not $blockingColumn) {
                                $includedColumnNames = @($target.Index.IndexedColumns | Where-Object { $PSItem.IsIncluded } | Select-Object -ExpandProperty Name)
                                foreach ($includedColumnName in $includedColumnNames) {
                                    $includedColumn = $obj.Columns[$includedColumnName]
                                    if ($includedColumn.Computed) {
                                        $blockingColumn = "included computed column $includedColumnName"
                                        break
                                    }
                                    # MaxLength is -1 for the max types, which is what makes a column LOB here.
                                    if ("$($includedColumn.DataType.SqlDataType)" -in "NVarCharMax", "VarCharMax", "VarBinaryMax", "Text", "NText", "Image", "Xml" -or $includedColumn.DataType.MaximumLength -eq -1) {
                                        $blockingColumn = "included LOB column $includedColumnName"
                                        break
                                    }
                                }
                            }

                            if ($blockingColumn) {
                                $useResumable = $false
                                $suppressed += "Resumable, which a $blockingColumn rules out"
                            }
                        }
                    }

                    if ($target.IsHeap -or $isColumnstore) {
                        if ($target.IsHeap) {
                            $unsupportedReason = "does not apply to heaps"
                        } else {
                            $unsupportedReason = "does not apply to columnstore indexes"
                        }
                        foreach ($unsupportedOption in "FillFactor", "PadIndex", "SortInTempdb") {
                            if (Test-Bound -ParameterName $unsupportedOption) {
                                $suppressed += "$unsupportedOption, which $unsupportedReason"
                            }
                        }
                    }

                    # REORGANIZE never takes the object offline, whatever -Online said.
                    if ($operation -eq "Reorganize") {
                        $useOnline = $true
                        $useResumable = $false
                    }

                    if (-not $Pscmdlet.ShouldProcess("$($obj.Schema).$($obj.Name) in $($db.Name) on $server", "$operation $($target.IndexType) $($target.IndexName)")) {
                        continue
                    }

                    if ($target.IsHeap) {
                        $smoTarget = $obj
                    } else {
                        $smoTarget = $target.Index
                    }

                    $notes = $null
                    if ($suppressed) {
                        $notes = "Suppressed: $($suppressed -join "; ")"
                        Write-Message -Level Verbose -Message "$objectLabel - $notes"
                    }

                    # These are options for one operation rather than stored index settings, but SMO leaves them
                    # set on the object afterwards. A caller who pipes the same SMO object in twice would
                    # otherwise inherit the first run's MAXDOP or SORT_IN_TEMPDB. FillFactor and PadIndex are
                    # deliberately not in this list: those are stored settings the caller asked to change.
                    $transientOptions = "OnlineHeapOperation", "OnlineIndexOperation", "ResumableIndexOperation", "ResumableMaxDuration", "SortInTempdb", "MaximumDegreeOfParallelism", "LowPriorityMaxDuration", "LowPriorityAbortAfterWait"
                    $previousOptions = New-Object -TypeName System.Collections.Hashtable
                    foreach ($transientOption in $transientOptions) {
                        if ($null -ne $smoTarget.PSObject.Properties[$transientOption]) {
                            $previousOptions[$transientOption] = $smoTarget.$transientOption
                        }
                    }

                    $previousStatementTimeout = $server.ConnectionContext.StatementTimeout
                    $start = Get-Date
                    try {
                        $server.ConnectionContext.StatementTimeout = $statementTimeoutSeconds

                        if ($operation -eq "Reorganize") {
                            # -1 means every partition. SMO has no parameterless Reorganize overload.
                            $smoTarget.Reorganize(-1)
                        } else {
                            if ($target.IsHeap) {
                                $smoTarget.OnlineHeapOperation = $useOnline
                            } else {
                                $smoTarget.OnlineIndexOperation = $useOnline
                                $smoTarget.ResumableIndexOperation = $useResumable
                                if ($useResumable -and (Test-Bound -ParameterName ResumableMaxDuration)) {
                                    $smoTarget.ResumableMaxDuration = $ResumableMaxDuration
                                }
                                if (-not $isColumnstore) {
                                    if (Test-Bound -ParameterName FillFactor) {
                                        $smoTarget.FillFactor = $FillFactor
                                    }
                                    if (Test-Bound -ParameterName PadIndex) {
                                        $smoTarget.PadIndex = [bool]$PadIndex
                                    }
                                    if (Test-Bound -ParameterName SortInTempdb) {
                                        $smoTarget.SortInTempdb = [bool]$SortInTempdb
                                    }
                                }
                            }

                            if (Test-Bound -ParameterName MaxDop) {
                                $smoTarget.MaximumDegreeOfParallelism = $MaxDop
                            }

                            if ($WaitAtLowPriority -and $useOnline) {
                                $smoTarget.LowPriorityMaxDuration = $MaxDurationMinutes
                                $smoTarget.LowPriorityAbortAfterWait = [Microsoft.SqlServer.Management.Smo.AbortAfterWait]$AbortAfterWait
                            }

                            $smoTarget.Rebuild()
                        }
                        $success = $true
                        if ($target.IsHeap) {
                            $heapWasRebuilt = $true
                        }
                    } catch {
                        $success = $false
                        $failureMessage = "$operation failed for $objectLabel on $server. $($PSItem.Exception.GetBaseException().Message)"
                        $notes = $failureMessage
                        # A half-applied property set would otherwise leak into the next operation on this object.
                        try {
                            $smoTarget.Refresh()
                        } catch {
                            Write-Message -Level Verbose -Message "Could not refresh $objectLabel after the failure."
                        }
                        if ($EnableException) {
                            $splatOperationFailure = @{
                                Message         = $failureMessage
                                ErrorRecord     = $PSItem
                                Target          = $obj
                                EnableException = $EnableException
                            }
                            Stop-Function @splatOperationFailure
                        }
                        Write-Message -Level Warning -Message $failureMessage
                    } finally {
                        $server.ConnectionContext.StatementTimeout = $previousStatementTimeout
                        foreach ($previousOption in $previousOptions.Keys) {
                            try {
                                $smoTarget.$previousOption = $previousOptions[$previousOption]
                            } catch {
                                Write-Message -Level Verbose -Message "Could not restore $previousOption on $objectLabel after the operation."
                            }
                        }
                    }
                    $end = Get-Date

                    $fragmentationAfter = $null
                    if ($success -and -not $isColumnstore) {
                        try {
                            # Formatted outside the call: a comma inside a method argument list splits it into two arguments.
                            $afterScanSql = $singleFragmentationSql -f $obj.ID, $target.IndexId
                            $afterRow = $db.Query($afterScanSql)
                            if ($afterRow.AvgFragmentation -isnot [DBNull] -and $null -ne $afterRow.AvgFragmentation) {
                                $fragmentationAfter = [math]::Round([double]$afterRow.AvgFragmentation, 2)
                            }
                        } catch {
                            Write-Message -Level Verbose -Message "Could not re-measure fragmentation for $objectLabel. $($PSItem.Exception.Message)"
                        }
                    }

                    # Built from the total, not from a DateTime: a rebuild that runs past midnight would otherwise wrap to zero.
                    $span = New-TimeSpan -Start $start -End $end
                    $elapsed = "{0:00}:{1:00}:{2:00}" -f [math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds

                    $output = [PSCustomObject]@{
                        ComputerName        = $server.ComputerName
                        InstanceName        = $server.ServiceName
                        SqlInstance         = $server.DomainInstanceName
                        Database            = $db.Name
                        Schema              = $obj.Schema
                        Table               = $obj.Name
                        IndexName           = $target.IndexName
                        IndexType           = $target.IndexType
                        PageCount           = $pageCount
                        FragmentationBefore = $fragmentationBefore
                        FragmentationAfter  = $fragmentationAfter
                        Operation           = $operation
                        Online              = $useOnline
                        Resumable           = $useResumable
                        Start               = $start
                        End                 = $end
                        Duration            = $elapsed
                        Success             = $success
                        Notes               = $notes
                    }

                    Select-DefaultView -InputObject $output -Property SqlInstance, Database, Schema, Table, IndexName, IndexType, Operation, PageCount, FragmentationBefore, FragmentationAfter, Duration, Success
                }
            }
        }
    }
}
