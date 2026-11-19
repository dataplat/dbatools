#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbCompression",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.

Describe "Native database compression behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeCompressionCreated = $false
        $nativeCompressionListener = $null
        $nativeCompressionServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeCompressionDatabaseName = "native_compression_" + [Guid]::NewGuid().ToString("N")
        $nativeCompressionDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeCompressionServer, $nativeCompressionDatabaseName
        $nativeCompressionDatabase.Create()
        $nativeCompressionCreated = $true
        $nativeCompressionDatabase.ExecuteNonQuery(@"
CREATE TABLE dbo.compression_heap (id int NOT NULL, payload char(200) NOT NULL) WITH (DATA_COMPRESSION = ROW);
INSERT dbo.compression_heap VALUES (1, 'a'), (2, 'b'), (3, 'c');
CREATE NONCLUSTERED INDEX compression_heap_nc ON dbo.compression_heap (id) WITH (DATA_COMPRESSION = PAGE);
CREATE TABLE dbo.compression_clustered (id int NOT NULL PRIMARY KEY CLUSTERED, payload char(200) NOT NULL);
INSERT dbo.compression_clustered VALUES (1, 'a'), (2, 'b');
"@)
        $nativeCompressionDatabase.Tables.Refresh()
        $nativeCompressionHeap = $nativeCompressionDatabase.Tables["compression_heap", "dbo"]
        $nativeCompressionClustered = $nativeCompressionDatabase.Tables["compression_clustered", "dbo"]
        $nativeCompressionListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        $nativeCompressionListener.Start()
        $nativeCompressionPort = $nativeCompressionListener.LocalEndpoint.Port
        $nativeCompressionBadInstance = "Data Source=tcp:127.0.0.1,$nativeCompressionPort;Integrated Security=True;Connect Timeout=1;Pooling=False"
    }

    AfterAll {
        if ($nativeCompressionListener) { $nativeCompressionListener.Stop() }
        if ($nativeCompressionCreated) {
            $splatRemoveNativeCompression = @{
                SqlInstance     = $nativeCompressionServer
                Database        = $nativeCompressionDatabaseName
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeCompression
        }
    }

    It "returns heap and index rows with typed sizes and exact name filtering" {
        $splatNativeCompressionRead = @{
            SqlInstance     = $nativeCompressionServer
            Database        = $nativeCompressionDatabaseName.ToUpperInvariant()
            EnableException = $true
        }
        $nativeCompressionRows = @(Get-DbaDbCompression @splatNativeCompressionRead)
        $nativeCompressionRows.Count | Should -Be 3
        foreach ($nativeCompressionRow in $nativeCompressionRows) {
            ($nativeCompressionRow.PSObject.Properties.Name -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Database,DatabaseId,Schema,TableName,IndexName,Partition,IndexID,IndexType,DataCompression,SizeCurrent,RowCount"
            $nativeCompressionRow.ComputerName | Should -BeExactly $nativeCompressionServer.ComputerName
            $nativeCompressionRow.InstanceName | Should -BeExactly $nativeCompressionServer.ServiceName
            $nativeCompressionRow.SqlInstance | Should -BeExactly $nativeCompressionServer.DomainInstanceName
            $nativeCompressionRow.Database | Should -BeExactly $nativeCompressionDatabaseName
            $nativeCompressionRow.DatabaseId | Should -Be $nativeCompressionDatabase.ID
            $nativeCompressionRow.Schema | Should -BeExactly "dbo"
            $nativeCompressionRow.Partition | Should -Be 1
            $nativeCompressionRow.SizeCurrent | Should -BeOfType Dataplat.Dbatools.Utility.Size
            $nativeCompressionRow.SizeCurrent.Byte | Should -BeGreaterOrEqual 0
        }
        $nativeCompressionHeapRow = $nativeCompressionRows | Where-Object IndexID -eq 0
        $nativeCompressionHeapRow.IndexName | Should -BeNullOrEmpty
        $nativeCompressionHeapRow.IndexType | Should -BeExactly "Heap"
        $nativeCompressionHeapRow.DataCompression | Should -Be "Row"
        $nativeCompressionHeapRow.RowCount | Should -Be 3
        $nativeCompressionHeapRow.RowCount | Should -BeOfType [long]
        $nativeCompressionHeapRow.SizeCurrent.Byte | Should -Be ([long]($nativeCompressionHeap.DataSpaceUsed * 1024))
        $nativeCompressionIndexRow = $nativeCompressionRows | Where-Object IndexName -eq "compression_heap_nc"
        $nativeCompressionIndexRow.IndexType | Should -Be "NonClusteredIndex"
        $nativeCompressionIndexRow.DataCompression | Should -Be "Page"
        $nativeCompressionIndexRow.RowCount | Should -Be 3
        $nativeCompressionIndexRow.RowCount | Should -BeOfType [double]
        $nativeCompressionIndexRow.SizeCurrent.Byte | Should -Be ([long]($nativeCompressionHeap.Indexes["compression_heap_nc"].SpaceUsed * 1024))
        $nativeCompressionClusteredRow = $nativeCompressionRows | Where-Object TableName -eq "compression_clustered"
        $nativeCompressionClusteredRow.IndexType | Should -Be "ClusteredIndex"
        $nativeCompressionClusteredRow.RowCount | Should -Be 2
        $nativeCompressionClusteredRow.SizeCurrent.Byte | Should -Be ([long]($nativeCompressionClustered.DataSpaceUsed * 1024))

        $splatNativeCompressionRead.Table = "COMPRESSION_HEAP"
        @(Get-DbaDbCompression @splatNativeCompressionRead).Count | Should -Be 2
        $splatNativeCompressionRead.Table = "compression_*"
        @(Get-DbaDbCompression @splatNativeCompressionRead).Count | Should -Be 0
        $splatNativeCompressionRead.Table = @()
        @(Get-DbaDbCompression @splatNativeCompressionRead).Count | Should -Be 3
        $splatNativeCompressionRead.ExcludeDatabase = $nativeCompressionDatabaseName.ToUpperInvariant()
        @(Get-DbaDbCompression @splatNativeCompressionRead).Count | Should -Be 0
        $splatNativeCompressionRead.Remove("ExcludeDatabase")
        $splatNativeCompressionRead.Database = "native_compression_*"
        @(Get-DbaDbCompression @splatNativeCompressionRead).Count | Should -Be 0
        $splatNativeCompressionRead.Database = "master"
        @(Get-DbaDbCompression @splatNativeCompressionRead).Count | Should -Be 0
    }

    It "continues successful pipeline records around a failed connection with EnableException false" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeCompressionWarnings = @()
        $nativeCompressionPreviousErrors = @($global:Error)
        $splatNativeCompressionContinue = @{
            Database        = $nativeCompressionDatabaseName
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeCompressionWarnings"
        }
        $nativeCompressionContinued = @(
            @($nativeCompressionServer, $nativeCompressionBadInstance, $nativeCompressionServer) |
                Get-DbaDbCompression @splatNativeCompressionContinue
        )
        $nativeCompressionContinued.Count | Should -Be 6
        @($nativeCompressionContinued | Where-Object Database -ne $nativeCompressionDatabaseName).Count | Should -Be 0
        @($nativeCompressionContinued | Where-Object IndexID -eq 0).Count | Should -Be 2
        ($nativeCompressionWarnings -join " ") | Should -BeLike "*Failure*"
        $nativeCompressionConnectionError = $global:Error | Where-Object {
            $nativeCompressionPreviousErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDbCompression*"
        } | Select-Object -First 1
        $nativeCompressionConnectionError | Should -Not -BeNullOrEmpty
        $nativeCompressionConnectionError.CategoryInfo.Category | Should -Be "ConnectionError"
    }

    It "retains earlier rows and terminates at the failed pipeline connection under EnableException" -Tag "NativeChecklist:enable-exception" {
        $nativeCompressionObserved = New-Object System.Collections.ArrayList
        $nativeCompressionCaught = $null
        $splatNativeCompressionTerminate = @{
            Database        = $nativeCompressionDatabaseName
            EnableException = $true
        }
        try {
            @($nativeCompressionServer, $nativeCompressionBadInstance, $nativeCompressionServer) |
                Get-DbaDbCompression @splatNativeCompressionTerminate |
                ForEach-Object { $null = $nativeCompressionObserved.Add($PSItem) }
        } catch {
            $nativeCompressionCaught = $PSItem
        }
        $nativeCompressionCaught | Should -Not -BeNullOrEmpty
        $nativeCompressionCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativeCompressionCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbCompression*"
        $nativeCompressionCaught.Exception.Message | Should -Match "^The wait operation timed out\.?$"
        $nativeCompressionObserved.Count | Should -Be 3
        @($nativeCompressionObserved | Where-Object Database -ne $nativeCompressionDatabaseName).Count | Should -Be 0
    }
}

Describe "Native database compression partition measurements" -Tag IntegrationTests {
    BeforeAll {
        $nativePartitionCreated = $false
        $nativePartitionServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativePartitionDatabaseName = "native_compression_part_" + [Guid]::NewGuid().ToString("N")
        $nativePartitionDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativePartitionServer, $nativePartitionDatabaseName
        $nativePartitionDatabase.Create()
        $nativePartitionCreated = $true
        $nativePartitionDatabase.ExecuteNonQuery("CREATE PARTITION FUNCTION native_compression_pf (int) AS RANGE RIGHT FOR VALUES (100);")
        $nativePartitionDatabase.ExecuteNonQuery("CREATE PARTITION SCHEME native_compression_ps AS PARTITION native_compression_pf ALL TO ([PRIMARY]);")
        $nativePartitionDatabase.ExecuteNonQuery(@'
CREATE TABLE dbo.partitioned_heap (id int NOT NULL, payload char(400) NOT NULL) ON native_compression_ps (id);
CREATE TABLE dbo.partitioned_clustered (id int NOT NULL, tag char(300) NOT NULL, payload char(400) NOT NULL, CONSTRAINT pk_partitioned_clustered PRIMARY KEY CLUSTERED (id)) ON native_compression_ps (id);
'@)
        $nativePartitionDatabase.ExecuteNonQuery(@'
INSERT dbo.partitioned_heap (id, payload) SELECT TOP (3) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 'low' FROM sys.all_columns;
INSERT dbo.partitioned_heap (id, payload) SELECT TOP (200) 99 + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 'high' FROM sys.all_columns;
INSERT dbo.partitioned_clustered (id, tag, payload) SELECT TOP (2) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 'low', 'low' FROM sys.all_columns;
INSERT dbo.partitioned_clustered (id, tag, payload) SELECT TOP (150) 99 + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 'high', 'high' FROM sys.all_columns;
CREATE NONCLUSTERED INDEX ix_partitioned_clustered_tag ON dbo.partitioned_clustered (tag) ON native_compression_ps (id);
'@)

        # Independent per-partition measurements: COUNT_BIG over the partition function, and
        # sys.dm_db_partition_stats allocation counts (8 KB pages) for each heap or index partition.
        $nativePartitionCounts = @{ }
        $nativePartitionCountRows = $nativePartitionDatabase.ExecuteWithResults(@'
SELECT N'partitioned_heap' AS table_name, $PARTITION.native_compression_pf(id) AS partition_number, COUNT_BIG(*) AS row_count
FROM dbo.partitioned_heap GROUP BY $PARTITION.native_compression_pf(id)
UNION ALL
SELECT N'partitioned_clustered', $PARTITION.native_compression_pf(id), COUNT_BIG(*)
FROM dbo.partitioned_clustered GROUP BY $PARTITION.native_compression_pf(id);
'@).Tables[0].Rows
        foreach ($nativePartitionCountRow in $nativePartitionCountRows) {
            $nativePartitionCounts["$($nativePartitionCountRow.table_name)/$($nativePartitionCountRow.partition_number)"] = [long]$nativePartitionCountRow.row_count
        }
        $nativePartitionPages = @{ }
        $nativePartitionPageRows = $nativePartitionDatabase.ExecuteWithResults(@'
SELECT OBJECT_NAME(ps.object_id) AS table_name, ps.index_id, ps.partition_number,
    ps.in_row_data_page_count + ps.lob_used_page_count + ps.row_overflow_used_page_count AS data_pages,
    ps.in_row_used_page_count AS index_pages
FROM sys.dm_db_partition_stats AS ps
WHERE ps.object_id IN (OBJECT_ID(N'dbo.partitioned_heap'), OBJECT_ID(N'dbo.partitioned_clustered'));
'@).Tables[0].Rows
        foreach ($nativePartitionPageRow in $nativePartitionPageRows) {
            $nativePartitionPages["$($nativePartitionPageRow.table_name)/$($nativePartitionPageRow.index_id)/$($nativePartitionPageRow.partition_number)"] = $nativePartitionPageRow
        }

        $splatNativePartitionRead = @{
            SqlInstance     = $nativePartitionServer
            Database        = $nativePartitionDatabaseName
            EnableException = $true
        }
        $nativePartitionRows = @(Get-DbaDbCompression @splatNativePartitionRead)
    }

    AfterAll {
        if ($nativePartitionCreated) {
            $splatRemoveNativePartition = @{
                SqlInstance     = $nativePartitionServer
                Database        = $nativePartitionDatabaseName
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativePartition
        }
    }

    It "reports each heap partition's own row count and allocated data size" {
        $nativePartitionCounts["partitioned_heap/1"] | Should -Be 3
        $nativePartitionCounts["partitioned_heap/2"] | Should -Be 200
        $nativePartitionHeapLow = [long]$nativePartitionPages["partitioned_heap/0/1"].data_pages
        $nativePartitionHeapHigh = [long]$nativePartitionPages["partitioned_heap/0/2"].data_pages
        $nativePartitionHeapLow | Should -BeGreaterThan 0
        $nativePartitionHeapHigh | Should -BeGreaterThan $nativePartitionHeapLow

        $nativePartitionHeapRows = @($nativePartitionRows | Where-Object TableName -eq "partitioned_heap" | Sort-Object Partition)
        $nativePartitionHeapRows.Count | Should -Be 2
        foreach ($nativePartitionHeapRow in $nativePartitionHeapRows) {
            $nativePartitionHeapRow.IndexID | Should -Be 0
            $nativePartitionHeapRow.IndexType | Should -BeExactly "Heap"
            $nativePartitionHeapRow.RowCount | Should -BeOfType [long]
            $nativePartitionHeapRow.RowCount | Should -Be $nativePartitionCounts["partitioned_heap/$($nativePartitionHeapRow.Partition)"]
            $nativePartitionHeapRow.SizeCurrent | Should -BeOfType Dataplat.Dbatools.Utility.Size
            $nativePartitionHeapRow.SizeCurrent.Byte | Should -Be ([long]$nativePartitionPages["partitioned_heap/0/$($nativePartitionHeapRow.Partition)"].data_pages * 8192)
        }
        ($nativePartitionHeapRows.Partition -join ",") | Should -BeExactly "1,2"
    }

    It "reports each clustered and nonclustered index partition's own allocated size" {
        $nativePartitionCounts["partitioned_clustered/1"] | Should -Be 2
        $nativePartitionCounts["partitioned_clustered/2"] | Should -Be 150
        [long]$nativePartitionPages["partitioned_clustered/1/2"].data_pages | Should -BeGreaterThan ([long]$nativePartitionPages["partitioned_clustered/1/1"].data_pages)
        [long]$nativePartitionPages["partitioned_clustered/2/2"].index_pages | Should -BeGreaterThan ([long]$nativePartitionPages["partitioned_clustered/2/1"].index_pages)

        $nativePartitionClusteredRows = @($nativePartitionRows | Where-Object { $PSItem.TableName -eq "partitioned_clustered" -and $PSItem.IndexID -eq 1 } | Sort-Object Partition)
        $nativePartitionClusteredRows.Count | Should -Be 2
        foreach ($nativePartitionClusteredRow in $nativePartitionClusteredRows) {
            $nativePartitionClusteredRow.IndexName | Should -BeExactly "pk_partitioned_clustered"
            $nativePartitionClusteredRow.IndexType | Should -Be "ClusteredIndex"
            $nativePartitionClusteredRow.RowCount | Should -Be $nativePartitionCounts["partitioned_clustered/$($nativePartitionClusteredRow.Partition)"]
            $nativePartitionClusteredRow.SizeCurrent.Byte | Should -Be ([long]$nativePartitionPages["partitioned_clustered/1/$($nativePartitionClusteredRow.Partition)"].data_pages * 8192)
        }

        $nativePartitionIndexRows = @($nativePartitionRows | Where-Object IndexName -eq "ix_partitioned_clustered_tag" | Sort-Object Partition)
        $nativePartitionIndexRows.Count | Should -Be 2
        foreach ($nativePartitionIndexRow in $nativePartitionIndexRows) {
            $nativePartitionIndexRow.IndexType | Should -Be "NonClusteredIndex"
            $nativePartitionIndexRow.RowCount | Should -Be $nativePartitionCounts["partitioned_clustered/$($nativePartitionIndexRow.Partition)"]
            $nativePartitionIndexId = $nativePartitionIndexRow.IndexID
            $nativePartitionIndexRow.SizeCurrent.Byte | Should -Be ([long]$nativePartitionPages["partitioned_clustered/$nativePartitionIndexId/$($nativePartitionIndexRow.Partition)"].index_pages * 8192)
        }
        @($nativePartitionRows).Count | Should -Be 6
    }
}

Describe "Native database compression columnstore measurements" -Tag IntegrationTests {
    BeforeAll {
        $nativeColumnstoreCreated = $false
        $nativeColumnstoreServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeColumnstoreDatabaseName = "native_compression_cs_" + [Guid]::NewGuid().ToString("N")
        $nativeColumnstoreDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeColumnstoreServer, $nativeColumnstoreDatabaseName
        $nativeColumnstoreDatabase.Create()
        $nativeColumnstoreCreated = $true
        $nativeColumnstoreDatabase.ExecuteNonQuery("CREATE PARTITION FUNCTION native_columnstore_pf (int) AS RANGE RIGHT FOR VALUES (100);")
        $nativeColumnstoreDatabase.ExecuteNonQuery("CREATE PARTITION SCHEME native_columnstore_ps AS PARTITION native_columnstore_pf ALL TO ([PRIMARY]);")
        # Each columnstore index holds compressed rowgroups (built by CREATE INDEX over existing rows) and
        # then an open delta rowgroup (rows inserted afterwards), so both kinds of storage are measured.
        $nativeColumnstoreDatabase.ExecuteNonQuery(@'
CREATE TABLE dbo.columnstore_partitioned (id int NOT NULL, payload char(100) NOT NULL) ON native_columnstore_ps (id);
INSERT dbo.columnstore_partitioned (id, payload) SELECT TOP (50) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1, 'low' FROM sys.all_columns;
INSERT dbo.columnstore_partitioned (id, payload) SELECT TOP (300) 99 + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 'high' FROM sys.all_columns;
CREATE CLUSTERED COLUMNSTORE INDEX cci_columnstore_partitioned ON dbo.columnstore_partitioned ON native_columnstore_ps (id);
INSERT dbo.columnstore_partitioned (id, payload) SELECT TOP (20) 49 + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 'delta' FROM sys.all_columns;
CREATE TABLE dbo.columnstore_single (id int NOT NULL, payload char(100) NOT NULL);
INSERT dbo.columnstore_single (id, payload) SELECT TOP (500) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 'single' FROM sys.all_columns;
CREATE CLUSTERED COLUMNSTORE INDEX cci_columnstore_single ON dbo.columnstore_single;
INSERT dbo.columnstore_single (id, payload) SELECT TOP (10) 1000 + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 'delta' FROM sys.all_columns;
CREATE TABLE dbo.columnstore_rowstore (id int NOT NULL, payload char(100) NOT NULL, CONSTRAINT pk_columnstore_rowstore PRIMARY KEY CLUSTERED (id));
INSERT dbo.columnstore_rowstore (id, payload) SELECT TOP (500) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 'rowstore' FROM sys.all_columns;
CREATE NONCLUSTERED COLUMNSTORE INDEX ncci_columnstore_rowstore ON dbo.columnstore_rowstore (id, payload);
INSERT dbo.columnstore_rowstore (id, payload) SELECT TOP (10) 1000 + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 'delta' FROM sys.all_columns;
'@)

        # Independent per-partition measurement of each columnstore index, in 8 KB pages: the partition's
        # sys.dm_db_partition_stats LOB and row-overflow pages (the compressed segments, stored as LOB) plus the pages of
        # its internal rowsets (delta store, delete bitmap) from sys.internal_partitions. The DMV's in-row pages of a
        # columnstore partition are its delta stores (red c1a3569d: in-row 2 = delta store 2 on every leg), which the
        # internal rowsets already count.
        $nativeColumnstoreMeasureQuery = @'
SELECT OBJECT_NAME(ps.object_id) AS table_name, ps.index_id, ps.partition_number,
    ps.lob_used_page_count + ps.row_overflow_used_page_count AS stored_pages,
    ISNULL((SELECT SUM(au.used_pages)
        FROM sys.internal_partitions AS ip
        JOIN sys.allocation_units AS au ON au.container_id = CASE WHEN au.type = 2 THEN ip.partition_id ELSE ip.hobt_id END
        WHERE ip.object_id = ps.object_id AND ip.index_id = ps.index_id AND ip.partition_number = ps.partition_number), 0) AS internal_pages
FROM sys.dm_db_partition_stats AS ps
JOIN sys.indexes AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE i.type IN (5, 6)
    AND ps.object_id IN (OBJECT_ID(N'dbo.columnstore_partitioned'), OBJECT_ID(N'dbo.columnstore_single'), OBJECT_ID(N'dbo.columnstore_rowstore'));
'@
        $splatNativeColumnstoreRead = @{
            SqlInstance     = $nativeColumnstoreServer
            Database        = $nativeColumnstoreDatabaseName
            EnableException = $true
        }
        # The measurement is read before and after the command; a background tuple mover that changes the
        # storage in between makes the pair differ, and the read is repeated.
        for ($nativeColumnstoreAttempt = 0; $nativeColumnstoreAttempt -lt 3; $nativeColumnstoreAttempt++) {
            $nativeColumnstoreBefore = @{ }
            foreach ($nativeColumnstoreMeasure in $nativeColumnstoreDatabase.ExecuteWithResults($nativeColumnstoreMeasureQuery).Tables[0].Rows) {
                $nativeColumnstoreBefore["$($nativeColumnstoreMeasure.table_name)/$($nativeColumnstoreMeasure.index_id)/$($nativeColumnstoreMeasure.partition_number)"] = "$($nativeColumnstoreMeasure.stored_pages)/$($nativeColumnstoreMeasure.internal_pages)"
            }
            $nativeColumnstoreRows = @(Get-DbaDbCompression @splatNativeColumnstoreRead)
            $nativeColumnstorePages = @{ }
            $nativeColumnstoreAfter = @{ }
            foreach ($nativeColumnstoreMeasure in $nativeColumnstoreDatabase.ExecuteWithResults($nativeColumnstoreMeasureQuery).Tables[0].Rows) {
                $nativeColumnstoreKey = "$($nativeColumnstoreMeasure.table_name)/$($nativeColumnstoreMeasure.index_id)/$($nativeColumnstoreMeasure.partition_number)"
                $nativeColumnstorePages[$nativeColumnstoreKey] = $nativeColumnstoreMeasure
                $nativeColumnstoreAfter[$nativeColumnstoreKey] = "$($nativeColumnstoreMeasure.stored_pages)/$($nativeColumnstoreMeasure.internal_pages)"
            }
            $nativeColumnstoreStable = $nativeColumnstoreBefore.Count -eq $nativeColumnstoreAfter.Count
            foreach ($nativeColumnstoreKey in $nativeColumnstoreAfter.Keys) {
                if ($nativeColumnstoreBefore[$nativeColumnstoreKey] -ne $nativeColumnstoreAfter[$nativeColumnstoreKey]) { $nativeColumnstoreStable = $false }
            }
            if ($nativeColumnstoreStable) { break }
        }

        # A failed size assertion reports where each partition's pages are: allocation units by partition_id and by
        # hobt_id, the sys.dm_db_partition_stats columns, and the internal rowsets by kind.
        $nativeColumnstoreDetailQuery = @'
SELECT OBJECT_NAME(p.object_id) AS table_name, p.index_id, p.partition_number,
    CASE WHEN p.hobt_id = p.partition_id THEN 1 ELSE 0 END AS same_id,
    ISNULL((SELECT SUM(a.used_pages) FROM sys.allocation_units AS a WHERE a.container_id = p.partition_id), 0) AS partition_units,
    ISNULL((SELECT SUM(a.used_pages) FROM sys.allocation_units AS a WHERE a.container_id = p.hobt_id AND p.hobt_id <> p.partition_id), 0) AS hobt_units,
    (SELECT COUNT(*) FROM sys.dm_db_partition_stats AS q WHERE q.object_id = p.object_id AND q.index_id = p.index_id AND q.partition_number = p.partition_number) AS dmv_rows,
    ps.in_row_used_page_count AS dmv_in_row, ps.lob_used_page_count AS dmv_lob, ps.row_overflow_used_page_count AS dmv_overflow,
    ISNULL((SELECT SUM(au.used_pages) FROM sys.internal_partitions AS ip JOIN sys.allocation_units AS au ON au.container_id IN (ip.partition_id, ip.hobt_id)
        WHERE ip.object_id = p.object_id AND ip.index_id = p.index_id AND ip.partition_number = p.partition_number
            AND ip.internal_object_type_desc = N'COLUMN_STORE_DELTA_STORE'), 0) AS delta_pages,
    ISNULL((SELECT SUM(au.used_pages) FROM sys.internal_partitions AS ip JOIN sys.allocation_units AS au ON au.container_id IN (ip.partition_id, ip.hobt_id)
        WHERE ip.object_id = p.object_id AND ip.index_id = p.index_id AND ip.partition_number = p.partition_number
            AND ip.internal_object_type_desc <> N'COLUMN_STORE_DELTA_STORE'), 0) AS other_internal_pages
FROM sys.partitions AS p
JOIN sys.indexes AS i ON i.object_id = p.object_id AND i.index_id = p.index_id
LEFT JOIN sys.dm_db_partition_stats AS ps ON ps.partition_id = p.partition_id
WHERE i.type IN (5, 6)
    AND p.object_id IN (OBJECT_ID(N'dbo.columnstore_partitioned'), OBJECT_ID(N'dbo.columnstore_single'), OBJECT_ID(N'dbo.columnstore_rowstore'))
ORDER BY table_name, p.partition_number;
'@
        try {
            $nativeColumnstoreDetail = @(
                foreach ($nativeColumnstoreDetailRow in $nativeColumnstoreDatabase.ExecuteWithResults($nativeColumnstoreDetailQuery).Tables[0].Rows) {
                    "{0}/{1}/{2} same={3} part={4} hobt={5} dmvrows={6} dmv={7}+{8}+{9} delta={10} other={11}" -f $nativeColumnstoreDetailRow.table_name, $nativeColumnstoreDetailRow.index_id, $nativeColumnstoreDetailRow.partition_number, $nativeColumnstoreDetailRow.same_id, $nativeColumnstoreDetailRow.partition_units, $nativeColumnstoreDetailRow.hobt_units, $nativeColumnstoreDetailRow.dmv_rows, $nativeColumnstoreDetailRow.dmv_in_row, $nativeColumnstoreDetailRow.dmv_lob, $nativeColumnstoreDetailRow.dmv_overflow, $nativeColumnstoreDetailRow.delta_pages, $nativeColumnstoreDetailRow.other_internal_pages
                }
            ) -join "; "
        } catch {
            $nativeColumnstoreDetail = "page detail unavailable: $($PSItem.Exception.Message)"
        }
    }

    AfterAll {
        if ($nativeColumnstoreCreated) {
            $splatRemoveNativeColumnstore = @{
                SqlInstance     = $nativeColumnstoreServer
                Database        = $nativeColumnstoreDatabaseName
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeColumnstore
        }
    }

    It "reports each columnstore index partition's compressed and delta storage" {
        $nativeColumnstoreStable | Should -BeTrue
        $nativeColumnstorePages.Count | Should -Be 4
        [long]$nativeColumnstorePages["columnstore_partitioned/1/1"].internal_pages | Should -BeGreaterThan 0
        [long]$nativeColumnstorePages["columnstore_partitioned/1/2"].stored_pages | Should -BeGreaterThan 0

        $nativeColumnstoreIndexRows = @($nativeColumnstoreRows | Where-Object { $PSItem.IndexType -in "ClusteredColumnStoreIndex", "NonClusteredColumnStoreIndex" } | Sort-Object TableName, Partition)
        $nativeColumnstoreIndexRows.Count | Should -Be 4
        (@($nativeColumnstoreIndexRows | ForEach-Object { "$($PSItem.TableName)/$($PSItem.IndexName)/$($PSItem.Partition)" }) -join ",") | Should -BeExactly "columnstore_partitioned/cci_columnstore_partitioned/1,columnstore_partitioned/cci_columnstore_partitioned/2,columnstore_rowstore/ncci_columnstore_rowstore/1,columnstore_single/cci_columnstore_single/1"
        foreach ($nativeColumnstoreIndexRow in $nativeColumnstoreIndexRows) {
            $nativeColumnstoreMeasure = $nativeColumnstorePages["$($nativeColumnstoreIndexRow.TableName)/$($nativeColumnstoreIndexRow.IndexID)/$($nativeColumnstoreIndexRow.Partition)"]
            $nativeColumnstoreExpected = ([long]$nativeColumnstoreMeasure.stored_pages + [long]$nativeColumnstoreMeasure.internal_pages) * 8192
            $nativeColumnstoreExpected | Should -BeGreaterThan 0
            $nativeColumnstoreIndexRow.SizeCurrent | Should -BeOfType Dataplat.Dbatools.Utility.Size
            $nativeColumnstoreIndexRow.SizeCurrent.Byte | Should -Be $nativeColumnstoreExpected -Because "row $($nativeColumnstoreIndexRow.TableName)/$($nativeColumnstoreIndexRow.Partition), pages $nativeColumnstoreDetail"
        }
    }
}

Describe "Native database compression size definitions" -Tag IntegrationTests {
    BeforeAll {
        $nativeDefinitionCreated = $false
        $nativeDefinitionServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeDefinitionDatabaseName = "native_compression_def_" + [Guid]::NewGuid().ToString("N")
        $nativeDefinitionDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeDefinitionServer, $nativeDefinitionDatabaseName
        $nativeDefinitionDatabase.Create()
        $nativeDefinitionCreated = $true
        # In-row, LOB and row-overflow pages on a heap, a clustered index and nonclustered indexes, one of them
        # carrying LOB pages of its own (Table.DataSpaceUsed counts those, Index.SpaceUsed does not).
        $nativeDefinitionDatabase.ExecuteNonQuery(@'
CREATE TABLE dbo.definition_heap (id int NOT NULL, doc varchar(max) NULL, wide1 varchar(5000) NULL, wide2 varchar(5000) NULL);
INSERT dbo.definition_heap (id, doc, wide1, wide2) SELECT TOP (40) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), REPLICATE(CAST('d' AS varchar(max)), 20000), REPLICATE('a', 5000), REPLICATE('b', 5000) FROM sys.all_columns;
CREATE NONCLUSTERED INDEX ix_definition_heap ON dbo.definition_heap (id) INCLUDE (doc);
CREATE TABLE dbo.definition_clustered (id int NOT NULL CONSTRAINT pk_definition_clustered PRIMARY KEY CLUSTERED, tag char(300) NOT NULL, note nvarchar(max) NULL);
INSERT dbo.definition_clustered (id, tag, note) SELECT TOP (300) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 'tag', REPLICATE(CAST(N'n' AS nvarchar(max)), 6000) FROM sys.all_columns;
CREATE NONCLUSTERED INDEX ix_definition_clustered_tag ON dbo.definition_clustered (tag);
'@)
        $nativeDefinitionDatabase.Tables.Refresh()
    }

    AfterAll {
        if ($nativeDefinitionCreated) {
            $splatRemoveNativeDefinition = @{
                SqlInstance     = $nativeDefinitionServer
                Database        = $nativeDefinitionDatabaseName
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeDefinition
        }
    }

    It "computes SMO DataSpaceUsed and SpaceUsed from sys.dm_db_partition_stats" {
        # The page terms the command reads on Azure SQL Database, where SMO supplies neither property.
        $nativeDefinitionRows = $nativeDefinitionDatabase.ExecuteWithResults(@'
SELECT OBJECT_NAME(ps.object_id) AS table_name, ps.index_id,
    SUM(CASE WHEN ps.index_id < 2 THEN ps.in_row_data_page_count ELSE 0 END + ps.lob_used_page_count + ps.row_overflow_used_page_count) AS data_pages,
    SUM(ps.in_row_used_page_count - CASE WHEN ps.index_id < 2 THEN ps.in_row_data_page_count ELSE 0 END) AS index_pages,
    SUM(ps.lob_used_page_count) AS lob_pages, SUM(ps.row_overflow_used_page_count) AS overflow_pages
FROM sys.dm_db_partition_stats AS ps
WHERE ps.object_id IN (OBJECT_ID(N'dbo.definition_heap'), OBJECT_ID(N'dbo.definition_clustered'))
GROUP BY ps.object_id, ps.index_id;
'@).Tables[0].Rows
        $nativeDefinitionPages = @{ }
        foreach ($nativeDefinitionRow in $nativeDefinitionRows) {
            $nativeDefinitionPages["$($nativeDefinitionRow.table_name)/$($nativeDefinitionRow.index_id)"] = $nativeDefinitionRow
        }
        $nativeDefinitionPages.Count | Should -Be 4
        [long]$nativeDefinitionPages["definition_heap/0"].lob_pages | Should -BeGreaterThan 0
        [long]$nativeDefinitionPages["definition_heap/0"].overflow_pages | Should -BeGreaterThan 0
        [long]$nativeDefinitionPages["definition_heap/2"].lob_pages | Should -BeGreaterThan 0
        [long]$nativeDefinitionPages["definition_clustered/1"].lob_pages | Should -BeGreaterThan 0

        foreach ($nativeDefinitionTableName in "definition_heap", "definition_clustered") {
            $nativeDefinitionTable = $nativeDefinitionDatabase.Tables[$nativeDefinitionTableName, "dbo"]
            $nativeDefinitionDataPages = [long](@($nativeDefinitionRows | Where-Object table_name -eq $nativeDefinitionTableName | Measure-Object -Property data_pages -Sum).Sum)
            $nativeDefinitionDataPages | Should -BeGreaterThan 0
            ($nativeDefinitionDataPages * 8) | Should -Be $nativeDefinitionTable.DataSpaceUsed -Because "Table.DataSpaceUsed of $nativeDefinitionTableName"
            @($nativeDefinitionTable.Indexes).Count | Should -BeGreaterThan 0
            foreach ($nativeDefinitionIndex in $nativeDefinitionTable.Indexes) {
                $nativeDefinitionIndexPages = [long]$nativeDefinitionPages["$nativeDefinitionTableName/$($nativeDefinitionIndex.ID)"].index_pages
                $nativeDefinitionIndexPages | Should -BeGreaterThan 0
                ($nativeDefinitionIndexPages * 8) | Should -Be $nativeDefinitionIndex.SpaceUsed -Because "Index.SpaceUsed of $($nativeDefinitionIndex.Name)"
            }
        }
    }
}

# NativeChecklist azure-sqldb: tested. The pinned SizeCurrent formulas read SMO Table.DataSpaceUsed and Index.SpaceUsed
# (pinned public/Get-DbaDbCompression.ps1:146, :167), which SMO does not support on Azure SQL Database, so a port of them
# fails there and gives no data. Corrections columnstore-size and azure-size read the catalog and
# sys.dm_db_partition_stats instead; this test proves each row's size on Azure.
Describe "Native database compression on Azure SQL Database" -Tag IntegrationTests {
    It "reads heap and columnstore compression in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once on the connected server.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        # Six legs share the database: unique table names and cleanup.
        $azureSuffix = [Guid]::NewGuid().ToString("N")
        $azureHeapName = "native_compression_heap_$azureSuffix"
        $azureColumnstoreName = "native_compression_cs_$azureSuffix"
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE dbo.[$azureHeapName] (id int NOT NULL) WITH (DATA_COMPRESSION = ROW); INSERT dbo.[$azureHeapName] VALUES (1), (2); CREATE NONCLUSTERED INDEX [ix_$azureSuffix] ON dbo.[$azureHeapName] (id);")
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE dbo.[$azureColumnstoreName] (id int NOT NULL, INDEX [cci_$azureSuffix] CLUSTERED COLUMNSTORE); INSERT dbo.[$azureColumnstoreName] VALUES (1), (2), (3);")
            # Independent sizes in 8 KB pages. Heap and nonclustered index: SMO's own Table.DataSpaceUsed and
            # Index.SpaceUsed definitions over sys.partitions and sys.allocation_units, which SMO does not run on Azure
            # SQL Database. Columnstore: the partition's LOB and row-overflow pages plus its internal rowsets, as
            # measured on premises.
            $azureRowstorePages = $azureServer.ConnectionContext.ExecuteWithResults(@"
SELECT p.index_id,
    SUM(CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END) AS data_pages,
    SUM(a.used_pages - CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END) AS index_pages
FROM sys.partitions AS p
JOIN sys.allocation_units AS a ON a.container_id = p.partition_id
WHERE p.object_id = OBJECT_ID(N'dbo.[$azureHeapName]')
GROUP BY p.index_id;
"@).Tables[0].Rows
            $azureHeapExpected = [long](($azureRowstorePages | Measure-Object -Property data_pages -Sum).Sum) * 8192
            $azureIndexExpected = [long](($azureRowstorePages | Where-Object index_id -eq 2).index_pages) * 8192
            $azureColumnstoreExpected = [long]$azureServer.ConnectionContext.ExecuteScalar(@"
SELECT (SELECT ISNULL(SUM(ps.lob_used_page_count + ps.row_overflow_used_page_count), 0) FROM sys.dm_db_partition_stats AS ps WHERE ps.object_id = OBJECT_ID(N'dbo.[$azureColumnstoreName]') AND ps.index_id = 1)
    + ISNULL((SELECT SUM(au.used_pages)
        FROM sys.internal_partitions AS ip
        JOIN sys.allocation_units AS au ON au.container_id = CASE WHEN au.type = 2 THEN ip.partition_id ELSE ip.hobt_id END
        WHERE ip.object_id = OBJECT_ID(N'dbo.[$azureColumnstoreName]') AND ip.index_id = 1), 0);
"@) * 8192
            $azureHeapExpected | Should -BeGreaterThan 0
            $azureIndexExpected | Should -BeGreaterThan 0
            $azureColumnstoreExpected | Should -BeGreaterThan 0
            $splatAzureCompression = @{
                SqlInstance     = $azureServer
                Database        = $TestConfig.AzureSqlDbName
                Table           = $azureHeapName, $azureColumnstoreName
                EnableException = $true
            }
            $azureRows = @(Get-DbaDbCompression @splatAzureCompression | Sort-Object IndexID)
            $azureRows.Count | Should -Be 3
            $azureRows[0].TableName | Should -BeExactly $azureHeapName
            $azureRows[0].IndexType | Should -BeExactly "Heap"
            $azureRows[0].DataCompression | Should -Be "Row"
            $azureRows[0].RowCount | Should -Be 2
            $azureRows[0].SizeCurrent.Byte | Should -Be $azureHeapExpected
            $azureRows[1].TableName | Should -BeExactly $azureColumnstoreName
            $azureRows[1].IndexType | Should -Be "ClusteredColumnStoreIndex"
            $azureRows[1].DataCompression | Should -Be "ColumnStore"
            $azureRows[1].SizeCurrent.Byte | Should -Be $azureColumnstoreExpected
            $azureRows[2].TableName | Should -BeExactly $azureHeapName
            $azureRows[2].IndexName | Should -BeExactly "ix_$azureSuffix"
            $azureRows[2].IndexType | Should -Be "NonClusteredIndex"
            $azureRows[2].SizeCurrent.Byte | Should -Be $azureIndexExpected
            foreach ($azureRow in $azureRows) {
                $azureRow.Database | Should -BeExactly $TestConfig.AzureSqlDbName
                $azureRow.SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
                $azureRow.SizeCurrent | Should -BeOfType Dataplat.Dbatools.Utility.Size
            }
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("DROP TABLE IF EXISTS dbo.[$azureHeapName]; DROP TABLE IF EXISTS dbo.[$azureColumnstoreName];")
        }
    }
}

Describe "Native database compression over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_compression_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE TABLE dbo.login_heap (id int NOT NULL) WITH (DATA_COMPRESSION = PAGE); INSERT dbo.login_heap VALUES (1), (2), (3);")
        }
        AfterAll {
            if ($loginServer) {
                # KillDatabase ends the command's pooled connections before the drop.
                $loginServer.Databases.Refresh()
                if ($loginServer.Databases[$loginDbName]) {
                    $loginServer.KillDatabase($loginDbName)
                }
            }
        }

        It "works with -SqlCredential" {
            $splatLoginCompression = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = $loginDbName
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbCompression @splatLoginCompression)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Database | Should -BeExactly $loginDbName
            $loginRows[0].TableName | Should -BeExactly "login_heap"
            $loginRows[0].IndexType | Should -BeExactly "Heap"
            $loginRows[0].DataCompression | Should -Be "Page"
            $loginRows[0].RowCount | Should -Be 3
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Database        = $loginDbName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaDbCompression @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws" {
            { Get-DbaDbCompression -SqlInstance $loginInstance -Database $loginDbName -EnableException } | Should -Throw
        }
    }
}
