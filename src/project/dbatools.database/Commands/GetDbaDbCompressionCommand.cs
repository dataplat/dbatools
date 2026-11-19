#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;
using SmoIndex = Microsoft.SqlServer.Management.Smo.Index;
using SmoTable = Microsoft.SqlServer.Management.Smo.Table;

namespace Dataplat.Dbatools.Commands;

// Retrieves table and index compression information directly through SMO.
/// <summary>Retrieves compression settings, sizes, and row counts for tables and indexes across SQL Server databases.</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbCompression", DefaultParameterSetName = "Default")]
public sealed class GetDbaDbCompressionCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>The table(s) to process.</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Table { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, minimumVersion: 10);
            if (server is null)
                continue;

            List<SmoDatabase> databases = new();
            try
            {
                foreach (SmoDatabase database in server.Databases)
                {
                    if (!database.IsAccessible || database.IsSystemObject)
                        continue;
                    if (LanguagePrimitives.IsTrue(Database) && !NativeDatabaseSelection.ContainsName(Database, database.Name))
                        continue;
                    if (LanguagePrimitives.IsTrue(ExcludeDatabase) && NativeDatabaseSelection.ContainsName(ExcludeDatabase, database.Name))
                        continue;
                    databases.Add(database);
                }
            }
            catch (Exception exception) when (exception is not PipelineStoppedException)
            {
                ReportFailure(String.Format("Unable to gather list of databases for {0}", instance), instance, exception);
                continue;
            }

            foreach (SmoDatabase database in databases)
            {
                try
                {
                    Dictionary<(int, int, int), PartitionPages>? partitionPages = null;
                    Dictionary<(int, int), double>? azureSizes = null;
                    IEnumerable tables = server.Databases[database.Name].Tables;
                    if (LanguagePrimitives.IsTrue(Table))
                    {
                        List<SmoTable> selected = new();
                        foreach (SmoTable table in tables)
                        {
                            if (NativeDatabaseSelection.ContainsName(Table, table.Name))
                                selected.Add(table);
                        }
                        tables = selected;
                    }
                    foreach (SmoTable table in tables)
                    {
                        if (table.HasHeapIndex)
                        {
                            bool split = table.PhysicalPartitions.Count > 1;
                            foreach (PhysicalPartition partition in table.PhysicalPartitions)
                            {
                                PartitionPages? pages = split ? FindPages(database, ref partitionPages, table.ID, 0, partition.PartitionNumber) : null;
                                WritePartition(server, database, table, null, partition, pages, ref azureSizes);
                            }
                        }
                        foreach (SmoIndex index in table.Indexes)
                        {
                            bool measured = index.PhysicalPartitions.Count > 1 || IsColumnstore(index);
                            foreach (PhysicalPartition partition in index.PhysicalPartitions)
                            {
                                PartitionPages? pages = measured ? FindPages(database, ref partitionPages, table.ID, index.ID, partition.PartitionNumber) : null;
                                WritePartition(server, database, table, index, partition, pages, ref azureSizes);
                            }
                        }
                    }
                }
                catch (Exception exception) when (exception is not PipelineStoppedException)
                {
                    ReportFailure(String.Format("Unable to query {0} - {1}", instance, database), database, exception);
                }
            }
        }
    }

    // Per partition of each multi-partition heap or index and of each columnstore index: the SMO
    // Table.DataSpaceUsed and Index.SpaceUsed page terms restricted to the partition, and the
    // columnstore storage of the partition. {0} is the quoted database name: the catalog views are
    // read database-qualified on the server connection, so the caller's connection never switches
    // database (the pinned command runs no query of its own). {1} reads the pages of the
    // columnstore internal rowsets (delta stores, delete bitmaps and buffers) per partition; their
    // in-row and row-overflow allocation units belong to the rowset's hobt, not to the partition.
    private const string PartitionPagesQuery = @"SELECT s.object_id, s.index_id, s.partition_number, s.data_pages, s.index_pages,
    s.used_pages + ISNULL(x.internal_pages, 0) AS columnstore_pages
FROM (SELECT p.object_id, p.index_id, p.partition_number,
        ISNULL(SUM(CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END), 0) AS data_pages,
        ISNULL(SUM(a.used_pages - CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END), 0) AS index_pages,
        ISNULL(SUM(a.used_pages), 0) AS used_pages
    FROM {0}.sys.partitions AS p
    LEFT JOIN {0}.sys.allocation_units AS a ON a.container_id = p.partition_id
    WHERE EXISTS (SELECT 1 FROM {0}.sys.partitions AS q WHERE q.object_id = p.object_id AND q.index_id = p.index_id AND q.partition_number > 1)
        OR EXISTS (SELECT 1 FROM {0}.sys.indexes AS i WHERE i.object_id = p.object_id AND i.index_id = p.index_id AND i.type IN (5, 6))
    GROUP BY p.object_id, p.index_id, p.partition_number) AS s
LEFT JOIN ({1}) AS x ON x.object_id = s.object_id AND x.index_id = s.index_id AND x.partition_number = s.partition_number";

    // SQL Server 2016 and later, and Azure SQL Database (which reports version 12).
    private const string InternalPartitionPagesQuery = @"SELECT ip.object_id, ip.index_id, ip.partition_number, SUM(au.used_pages) AS internal_pages
    FROM {0}.sys.internal_partitions AS ip
    JOIN {0}.sys.allocation_units AS au ON au.container_id = CASE WHEN au.type = 2 THEN ip.partition_id ELSE ip.hobt_id END
    GROUP BY ip.object_id, ip.index_id, ip.partition_number";

    // SQL Server 2014: delta stores are the only internal rowsets, listed by their hobt.
    private const string DeltaStorePagesQuery = @"SELECT rg.object_id, rg.index_id, rg.partition_number, SUM(au.used_pages) AS internal_pages
    FROM {0}.sys.column_store_row_groups AS rg
    JOIN {0}.sys.allocation_units AS au ON au.container_id = rg.delta_store_hobt_id
    GROUP BY rg.object_id, rg.index_id, rg.partition_number";

    // SQL Server 2008 and 2012: no updatable columnstore, so no internal rowsets.
    private const string NoInternalPagesQuery = @"SELECT CAST(NULL AS int) AS object_id, CAST(NULL AS int) AS index_id,
    CAST(NULL AS int) AS partition_number, CAST(NULL AS bigint) AS internal_pages WHERE 1 = 0";

    // Azure SQL Database, where SMO supplies neither Table.DataSpaceUsed nor Index.SpaceUsed: SMO's own definitions of
    // both (Microsoft.SqlServer.SqlEnum table.xml and index.xml) in KB, from the page counts of sys.dm_db_partition_stats.
    // Index rows (index_id 0 and up): Index.SpaceUsed, the in-row used pages less the in-row data pages of a heap or
    // clustered index. Table rows (index_id -1): Table.DataSpaceUsed, the in-row data pages of the heap or clustered
    // index plus the LOB and row-overflow pages of every index, or memory_used_by_table_kb for a memory-optimized table.
    private const string AzureSizeQuery = @"SELECT ps.object_id, ps.index_id,
    8 * SUM(ps.in_row_used_page_count - CASE WHEN ps.index_id < 2 THEN ps.in_row_data_page_count ELSE 0 END) AS size_kb
FROM {0}.sys.dm_db_partition_stats AS ps
GROUP BY ps.object_id, ps.index_id
UNION ALL
SELECT t.object_id, -1,
    CASE WHEN t.is_memory_optimized = 1 THEN ISNULL(x.memory_used_by_table_kb, 0) ELSE 8 * ISNULL(d.data_pages, 0) END
FROM {0}.sys.tables AS t
LEFT JOIN (SELECT ps.object_id,
        SUM(CASE WHEN ps.index_id < 2 THEN ps.in_row_data_page_count ELSE 0 END + ps.lob_used_page_count + ps.row_overflow_used_page_count) AS data_pages
    FROM {0}.sys.dm_db_partition_stats AS ps
    GROUP BY ps.object_id) AS d ON d.object_id = t.object_id
LEFT JOIN {0}.sys.dm_db_xtp_table_memory_stats AS x ON x.object_id = t.object_id";

    private readonly struct PartitionPages
    {
        public PartitionPages(long dataPages, long indexPages, long columnstorePages)
        {
            DataPages = dataPages;
            IndexPages = indexPages;
            ColumnstorePages = columnstorePages;
        }

        public long DataPages { get; }
        public long IndexPages { get; }
        public long ColumnstorePages { get; }
    }

    private static bool IsColumnstore(SmoIndex? index)
    {
        return index is not null && (index.IndexType == IndexType.ClusteredColumnStoreIndex ||
            index.IndexType == IndexType.NonClusteredColumnStoreIndex);
    }

    private static PartitionPages FindPages(SmoDatabase database, ref Dictionary<(int, int, int), PartitionPages>? cache,
        int objectId, int indexId, int partitionNumber)
    {
        if (cache is null)
        {
            cache = new Dictionary<(int, int, int), PartitionPages>();
            Server server = database.Parent;
            string internalQuery;
            if (server.VersionMajor >= 13 || server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase)
                internalQuery = InternalPartitionPagesQuery;
            else if (server.VersionMajor == 12)
                internalQuery = DeltaStorePagesQuery;
            else
                internalQuery = NoInternalPagesQuery;
            string quotedDatabase = "[" + database.Name.Replace("]", "]]") + "]";
            string query = String.Format(CultureInfo.InvariantCulture, PartitionPagesQuery, quotedDatabase,
                String.Format(CultureInfo.InvariantCulture, internalQuery, quotedDatabase));
            DataSet result = server.ConnectionContext.ExecuteWithResults(query);
            foreach (DataRow row in result.Tables[0].Rows)
            {
                (int, int, int) key = (Convert.ToInt32(row["object_id"], CultureInfo.InvariantCulture),
                    Convert.ToInt32(row["index_id"], CultureInfo.InvariantCulture),
                    Convert.ToInt32(row["partition_number"], CultureInfo.InvariantCulture));
                cache[key] = new PartitionPages(Convert.ToInt64(row["data_pages"], CultureInfo.InvariantCulture),
                    Convert.ToInt64(row["index_pages"], CultureInfo.InvariantCulture),
                    Convert.ToInt64(row["columnstore_pages"], CultureInfo.InvariantCulture));
            }
        }
        // A partition without allocation units has used no pages, as SMO's ISNULL(..., 0.0) reports.
        return cache.TryGetValue((objectId, indexId, partitionNumber), out PartitionPages pages) ? pages : new PartitionPages(0, 0, 0);
    }

    // Azure SQL Database: the SMO size of a table (indexId -1) or index in KB, read once per database. An index with no
    // partition stats has used no pages; SMO's own definitions report ISNULL(..., 0.0) for it too.
    private static double FindAzureSize(SmoDatabase database, ref Dictionary<(int, int), double>? cache, int objectId, int indexId)
    {
        if (cache is null)
        {
            cache = new Dictionary<(int, int), double>();
            string quotedDatabase = "[" + database.Name.Replace("]", "]]") + "]";
            string query = String.Format(CultureInfo.InvariantCulture, AzureSizeQuery, quotedDatabase);
            DataSet result = database.Parent.ConnectionContext.ExecuteWithResults(query);
            foreach (DataRow row in result.Tables[0].Rows)
            {
                cache[(Convert.ToInt32(row["object_id"], CultureInfo.InvariantCulture), Convert.ToInt32(row["index_id"], CultureInfo.InvariantCulture))] =
                    Convert.ToDouble(row["size_kb"], CultureInfo.InvariantCulture);
            }
        }
        return cache.TryGetValue((objectId, indexId), out double size) ? size : 0;
    }

    private void WritePartition(Server server, SmoDatabase database, SmoTable table, SmoIndex? index,
        PhysicalPartition partition, PartitionPages? pages, ref Dictionary<(int, int), double>? azureSizes)
    {
        PSObject output = new();
        OutputHelper.AddInstanceProperties(output, server);
        output.Properties.Add(new PSNoteProperty("Database", database.Name));
        output.Properties.Add(new PSNoteProperty("DatabaseId", database.ID));
        output.Properties.Add(new PSNoteProperty("Schema", table.Schema));
        output.Properties.Add(new PSNoteProperty("TableName", table.Name));
        output.Properties.Add(new PSNoteProperty("IndexName", index?.Name));
        output.Properties.Add(new PSNoteProperty("Partition", partition.PartitionNumber));
        output.Properties.Add(new PSNoteProperty("IndexID", index?.ID ?? 0));
        output.Properties.Add(new PSNoteProperty("IndexType", index is null ? (object)"Heap" : index.IndexType));
        output.Properties.Add(new PSNoteProperty("DataCompression", partition.DataCompression));
        // Upstream correction (wrong data): the pinned command reports the whole table's
        // DataSpaceUsed/RowCount or the whole index's SpaceUsed on every partition row. A
        // single-partition rowstore object keeps the pinned values; a multi-partition one reports the same
        // SMO page terms for the row's own partition, 8 KB per page. Table.DataSpaceUsed also counts
        // the LOB and row-overflow pages of nonclustered indexes; the per-partition data term reads
        // only the heap or clustered index and Index.SpaceUsed excludes those pages, so no partition
        // row reports them and a table's partition rows need not sum to its DataSpaceUsed.
        // Upstream correction (wrong data): Index.SpaceUsed subtracts LOB pages, where a columnstore
        // index keeps its compressed segments, and never counts its delta stores, so the pinned
        // command reports about 0 bytes for a populated columnstore index. A columnstore index row
        // reports all pages its partition uses: segments plus internal rowsets.
        // Upstream correction (wrong data): SMO supplies neither Table.DataSpaceUsed nor Index.SpaceUsed on Azure SQL
        // Database, so the pinned formula has no size there. There a single-partition rowstore row reports the same
        // SMO definition computed from sys.dm_db_partition_stats; every other engine keeps the SMO properties.
        bool dataTerm = index is null || index.IndexType == IndexType.ClusteredIndex;
        double used;
        if (pages is PartitionPages own)
            used = (IsColumnstore(index) ? own.ColumnstorePages : dataTerm ? own.DataPages : own.IndexPages) * 8.0;
        else if (server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase)
            used = FindAzureSize(database, ref azureSizes, table.ID, dataTerm ? -1 : index!.ID);
        else
            used = dataTerm ? table.DataSpaceUsed : index!.SpaceUsed;
        output.Properties.Add(new PSNoteProperty("SizeCurrent", (Size)(used * 1024)));
        object rowCount;
        if (index is not null)
            rowCount = partition.RowCount;
        else if (pages is null)
            rowCount = table.RowCount;
        else
            rowCount = Convert.ToInt64(partition.RowCount, CultureInfo.InvariantCulture);
        output.Properties.Add(new PSNoteProperty("RowCount", rowCount));
        WriteObject(output);
    }

    private void ReportFailure(string message, object target, Exception exception)
    {
        ErrorRecord error = exception is IContainsErrorRecord existing ? existing.ErrorRecord :
            new ErrorRecord(exception, "Get-DbaDbCompression", ErrorCategory.NotSpecified, target);
        StopFunction(message, target: target, errorRecord: error, continueLoop: true);
    }
}
