#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaHelpIndex.ps1 at refs/pins/dbatools-2026-10-22: connect each -SqlInstance (MinimumVersion 10),
// add its databases as Get-DbaDatabase selects them to the piped ones, then run the pinned index and statistics query in
// each accessible database through the Database.Query script method and write one object per row, built as the pin
// builds it: an @{} hashtable of the instance properties and every property PowerShell reports for the DataRow.
/// <summary>Retrieves comprehensive index and statistics information from SQL Server databases for performance analysis and optimization.</summary>
[Cmdlet(VerbsCommon.Get, "DbaHelpIndex")]
public sealed class GetDbaHelpIndexCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to analyze.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to skip.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Database object(s) piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public SmoDatabase[]? InputObject { get; set; }

    /// <summary>The table to analyze, as name or schema.name.</summary>
    [Parameter(Position = 5)]
    public string? ObjectName { get; set; }

    /// <summary>Returns statistics objects in addition to indexes.</summary>
    [Parameter]
    public SwitchParameter IncludeStats { get; set; }

    /// <summary>Adds the data types of the key and include columns.</summary>
    [Parameter]
    public SwitchParameter IncludeDataTypes { get; set; }

    /// <summary>Returns numeric values without formatting and Size as a dbasize object.</summary>
    [Parameter]
    public SwitchParameter Raw { get; set; }

    /// <summary>Adds fragmentation from sys.dm_db_index_physical_stats in DETAILED mode.</summary>
    [Parameter]
    public SwitchParameter IncludeFragmentation { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS: $propertyMapping, the output name of a query column.
    private static readonly Dictionary<string, string> PropertyMapping = new(StringComparer.OrdinalIgnoreCase)
    {
        { "FullObjectName", "Object" },
        { "IndexName", "Index" },
        { "StatisticsName", "Statistics" },
        { "SizeKB", "Size" },
        { "MostRecentlyUsed", "MostRecentlyUsed" }
    };

    // PS: $numericProperties and $decimalProperties; -contains compares without regard to case.
    private static readonly string[] NumericProperties = { "IndexReads", "IndexUpdates", "SizeKB", "IndexRows", "IndexLookups", "StatsSampleRows", "StatsRowMods" };
    private static readonly string[] DecimalProperties = { "IndexFragInPercent" };

    private string sizesQuery = String.Empty;

    /// <summary>PS begin block: the query from the parameters.</summary>
    protected override void BeginProcessing()
    {
        // Correction (objectname-unicode): an nvarchar literal, where the pin's varchar literal lost every character
        // outside the database's code page and so found no table.
        string tablePredicate = String.IsNullOrEmpty(ObjectName)
            ? "DECLARE @TableName NVARCHAR(256);"
            : "DECLARE @TableName NVARCHAR(256); SET @TableName = N'" + ObjectName!.Replace("'", "''") + "';";

        // Correction (fragmentation-unmeasured-zero): the fragmentation of each index, read per index rather than
        // through its usage statistics row; none without -IncludeFragmentation.
        string fragmentation = IncludeFragmentation.ToBool() ? FragmentationMeasured : FragmentationNotMeasured;

        string includeStatsPredicate = IncludeStats.ToBool() ? String.Empty : "WHERE StatisticsName IS NULL";
        string includeDataTypesPredicate = IncludeDataTypes.ToBool()
            ? "DECLARE @IncludeDataTypes BIT; SET @IncludeDataTypes = 1"
            : "DECLARE @IncludeDataTypes BIT; SET @IncludeDataTypes = 0";

        sizesQuery = String.Format(CultureInfo.InvariantCulture, SizesQueryTemplate,
            tablePredicate, includeDataTypesPredicate, fragmentation, includeStatsPredicate);
    }

    protected override void ProcessRecord()
    {
        WriteMessage(MessageLevel.Debug, sizesQuery);

        // PS: $InputObject += Get-DbaDatabase ... inside the process block, so the piped databases of this record and
        // the gathered ones are processed together.
        List<SmoDatabase?> databases = new();
        if (InputObject is not null)
            databases.AddRange(InputObject);

        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            // PS: try { Connect-DbaInstance -MinimumVersion 10 } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 10);
            if (server is null)
                continue;

            // PS: Get-DbaDatabase -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase: the
            // object arrays bind to its string arrays. Correction (database-wildcards): the pinned help documents
            // wildcards for -Database, which Get-DbaDatabase's exact matching never honoured; a real database name of
            // the instance stays literal, and -ExcludeDatabase stays exact.
            string[]? include = Database is null ? null :
                (string[])LanguagePrimitives.ConvertTo(Database, typeof(string[]), CultureInfo.InvariantCulture);
            string[]? exclude = ExcludeDatabase is null ? null :
                (string[])LanguagePrimitives.ConvertTo(ExcludeDatabase, typeof(string[]), CultureInfo.InvariantCulture);
            databases.AddRange(NativeDatabaseSelection.GatherMatching(this, new[] { new DbaInstanceParameter(server) }, null,
                include, true, exclude, false, connected => { }, () => false));
        }

        foreach (SmoDatabase? db in databases)
        {
            // PS: if (!$db.IsAccessible) { Stop-Function -Message "$db is not accessible. Skipping." -Continue }
            if (db is null || !db.IsAccessible)
            {
                StopFunction((db is null ? String.Empty : db.ToString()) + " is not accessible. Skipping.", continueLoop: true);
                continue;
            }

            Server server = db.Parent;
            WriteMessage(MessageLevel.Debug, sizesQuery);
            try
            {
                DataTable details = QueryDatabase(db, sizesQuery);
                foreach (DataRow detail in details.Rows)
                    WriteObject(BuildOutput(server, db, detail));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception failure)
            {
                // PS: Stop-Function -Continue -ErrorRecord $_ -Message "Cannot process $db on $server"
                ErrorRecord record = failure is IContainsErrorRecord contained ? contained.ErrorRecord :
                    new ErrorRecord(failure, failure.GetType().FullName, ErrorCategory.OperationStopped, null);
                StopFunction("Cannot process " + db.ToString() + " on " + server.ToString(), errorRecord: record, continueLoop: true);
            }
        }
    }

    /// <summary>PS: the foreach body over $IndexDetails, ending in [pscustomobject]$properties.</summary>
    private PSObject BuildOutput(Server server, SmoDatabase db, DataRow detail)
    {
        PSObject row = PSObject.AsPSObject(detail);

        // PS: $recentlyused = [datetime]$detail.MostRecentlyUsed, $null when its year is 1900.
        DateTime converted = (DateTime)LanguagePrimitives.ConvertTo(row.Properties["MostRecentlyUsed"]?.Value, typeof(DateTime), CultureInfo.InvariantCulture);
        object? recentlyUsed = converted.Year == 1900 ? null : converted;

        // PS: the @{} literal of four entries, then $properties[$name] = $value for each DataRow property in the order
        // PowerShell reports them. [pscustomobject] keeps the hashtable's own enumeration order.
        Hashtable properties = PsHashtable.Literal(4);
        properties.Add("ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server));
        // Correction (azure-sqldb): Azure SQL Database has no service, and SMO raises "ServiceName: unknown property."
        // there, which made the pinned statement fail for every row; its instance name is null, as
        // SERVERPROPERTY('InstanceName') and the shared OutputHelper.AddInstanceProperties report.
        properties.Add("InstanceName", server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase ? null : server.ServiceName);
        properties.Add("SqlInstance", Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server));
        properties.Add("Database", db.Name);

        bool raw = Raw.ToBool();
        foreach (PSPropertyInfo property in row.Properties)
        {
            string propertyName = property.Name;
            object? propertyValue = property.Value;
            string outputPropertyName = PropertyMapping.TryGetValue(propertyName, out string? mapped) ? mapped! : propertyName;

            if (String.Equals(propertyName, "MostRecentlyUsed", StringComparison.OrdinalIgnoreCase))
            {
                propertyValue = recentlyUsed;
            }
            else if (String.Equals(propertyName, "SizeKB", StringComparison.OrdinalIgnoreCase))
            {
                // PS: [dbasize]($propertyValue * 1024) under -Raw; SizeKB is a bigint column. The branches stay apart:
                // a conditional expression would turn the text into a Size through Size's implicit string conversion.
                if (raw)
                    propertyValue = new Size(Convert.ToInt64(propertyValue, CultureInfo.InvariantCulture) * 1024);
                else
                    propertyValue = Format("{0:N0}", propertyValue);
            }
            else if (!raw && Contains(NumericProperties, propertyName))
            {
                propertyValue = Format("{0:N0}", propertyValue);
            }
            else if (!raw && Contains(DecimalProperties, propertyName))
            {
                propertyValue = Format("{0:F2}", propertyValue);
            }

            properties[outputPropertyName] = propertyValue;
        }

        PSObject output = new();
        foreach (DictionaryEntry entry in properties)
            output.Properties.Add(new PSNoteProperty(entry.Key.ToString(), entry.Value));
        return output;
    }

    /// <summary>PS: the -f operator, which formats in the current culture.</summary>
    private static string Format(string format, object? value)
    {
        return String.Format(CultureInfo.CurrentCulture, format, value);
    }

    private static bool Contains(string[] names, string name)
    {
        foreach (string candidate in names)
        {
            if (String.Equals(candidate, name, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    /// <summary>PS: $db.Query($SizesQuery). The script method returns ExecuteWithResults($query).Tables[0]; that issues a
    /// USE on the caller's own server connection and never switches back, so its finally puts the previous database back
    /// (#10555), and a failed restore only warns through plain Write-Warning with Stop or Inquire raised to Continue. A
    /// failed ExecuteWithResults surfaces as the script method's runtime exception.</summary>
    private DataTable QueryDatabase(SmoDatabase db, string query)
    {
        ServerConnection connection = db.Parent.ConnectionContext;
        string previousDatabase = connection.CurrentDatabase;
        try
        {
            try
            {
                return db.ExecuteWithResults(query).Tables[0];
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
                    "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
                MethodInvocationException fault = new(String.Format(CultureInfo.InvariantCulture,
                    "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", call.Message), call);
                throw new RuntimeException(fault.Message, fault, new ErrorRecord(fault, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null));
            }
        }
        finally
        {
            // -cne in the script method: database names follow the instance collation.
            if (!String.IsNullOrEmpty(previousDatabase) && !String.Equals(previousDatabase, connection.CurrentDatabase, StringComparison.Ordinal))
            {
                try
                {
                    connection.ExecuteNonQuery("USE [" + previousDatabase.Replace("]", "]]") + "]");
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    string text = String.Format(CultureInfo.InvariantCulture,
                        "The database context could not be restored to [{0}]: Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{1}\"",
                        previousDatabase, failure.Message);
                    try
                    {
                        WriteWarning(text); // style-ok: cs-raw-streams the Database.Query script method calls plain Write-Warning, not Write-Message
                    }
                    catch (ActionPreferenceStopException stopped)
                    {
                        // The script method raises Stop to Continue for this one warning, so it never ends the command.
                        WriteMessage(MessageLevel.Debug, stopped.Message);
                    }
                }
            }
        }
    }

    // Under -IncludeFragmentation: the average over every row sys.dm_db_index_physical_stats reports for the index, in
    // the pin's DETAILED mode, as the pin's average over its joined rows gives for an index with usage statistics.
    private const string FragmentationMeasured = @"SELECT  object_id ,
                                index_id ,
                                AVG(avg_fragmentation_in_percent) AS avg_fragmentation_in_percent
                    FROM     sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL , 'DETAILED')
                    GROUP BY object_id ,
                                index_id";

    private const string FragmentationNotMeasured = @"SELECT  CAST(NULL AS INT) AS object_id ,
                                CAST(NULL AS INT) AS index_id ,
                                CAST(NULL AS FLOAT) AS avg_fragmentation_in_percent
                    WHERE    1 = 0";

    // PS: $SizesQuery. {0} $TablePredicate, {1} $IncludeDataTypesPredicate, {2} the fragmentation rows,
    // {3} $IncludeStatsPredicate. Corrections against the pinned text:
    // column-list-truncation: the three column lists are nvarchar(max), where nvarchar(1000) cut long lists short.
    // fragmentation-unmeasured-zero: cteFragmentation joins per index, where $FragJoin read fragmentation only for
    // indexes with a usage statistics row and ISNULL(..., 0) reported 0 for every other one and without the switch;
    // statistics-only rows report NULL, not ''.
    // most-recently-used-ties: the latest of the three times wins with >=, where equal latest times gave ''.
    // statistics-of-other-tables: a statistic is left out of the statistics-only rows only when an index of its own
    // table has its id, where NOT IN on stats_id alone dropped it for an index of any table.
    private const string SizesQueryTemplate = @"
            SET NOCOUNT ON;
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

            {0}
            {1}
            ;

        DECLARE @IndexUsageStats TABLE
            (
            object_id INT ,
            index_id INT ,
            user_scans BIGINT ,
            user_seeks BIGINT ,
            user_updates BIGINT ,
            user_lookups BIGINT ,
            last_user_lookup DATETIME2(0) ,
            last_user_scan DATETIME2(0) ,
            last_user_seek DATETIME2(0) ,
            avg_fragmentation_in_percent FLOAT
            );

        DECLARE @StatsInfo TABLE
            (
            object_id INT ,
            stats_id INT ,
            stats_column_name NVARCHAR(128) ,
            stats_column_id INT ,
            stats_name NVARCHAR(128) ,
            stats_last_updated DATETIME2(0) ,
            stats_sampled_rows BIGINT ,
            rowmods BIGINT ,
            histogramsteps INT ,
            StatsRows BIGINT ,
            FullObjectName NVARCHAR(256)
            );

        INSERT  INTO @IndexUsageStats
                ( object_id ,
                index_id ,
                user_scans ,
                user_seeks ,
                user_updates ,
                user_lookups ,
                last_user_lookup ,
                last_user_scan ,
                last_user_seek ,
                avg_fragmentation_in_percent
                )
                SELECT  ustat.object_id ,
                        ustat.index_id ,
                        ustat.user_scans ,
                        ustat.user_seeks ,
                        ustat.user_updates ,
                        ustat.user_lookups ,
                        ustat.last_user_lookup ,
                        ustat.last_user_scan ,
                        ustat.last_user_seek
                        , NULL as avg_fragmentation_in_percent
                FROM    sys.dm_db_index_usage_stats ustat
                WHERE   ustat.database_id = DB_ID();

        INSERT  INTO @StatsInfo
                ( object_id ,
                stats_id ,
                stats_column_name ,
                stats_column_id ,
                stats_name ,
                stats_last_updated ,
                stats_sampled_rows ,
                rowmods ,
                histogramsteps ,
                StatsRows ,
                FullObjectName
                )
                SELECT  s.object_id ,
                        s.stats_id ,
                        c.name ,
                        sc.stats_column_id ,
                        s.name ,
                        sp.last_updated ,
                        sp.rows_sampled ,
                        sp.modification_counter ,
                        sp.steps ,
                        sp.rows ,
                        QUOTENAME(sch.name) + '.' + QUOTENAME(t.name) AS FullObjectName
                FROM    sys.stats AS s
                        INNER JOIN sys.stats_columns sc ON s.stats_id = sc.stats_id
                                                        AND s.object_id = sc.object_id
                        INNER JOIN sys.columns c ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                        INNER JOIN sys.tables t ON c.object_id = t.object_id
                        INNER JOIN sys.schemas sch ON sch.schema_id = t.schema_id
                        OUTER APPLY sys.dm_db_stats_properties(s.object_id,
                                                            s.stats_id) AS sp
                WHERE   s.object_id = CASE WHEN @TableName IS NULL THEN s.object_id
                                        ELSE OBJECT_ID(@TableName)
                                    END;


        ;
        WITH    cteStatsInfo
                AS ( SELECT   object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                STUFF((SELECT   N', ' + stats_column_name
                                    FROM     @StatsInfo si2
                                    WHERE    si2.object_id = si.object_id
                                                AND si2.stats_id = si.stats_id
                                    ORDER BY si2.stats_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(max)'), 1,
                                    2, N'') AS StatsColumns ,
                                MAX(si.stats_sampled_rows) AS SampleRows ,
                                MAX(si.rowmods) AS RowMods ,
                                MAX(si.histogramsteps) AS HistogramSteps ,
                                MAX(si.stats_last_updated) AS StatsLastUpdated ,
                                MAX(si.StatsRows) AS StatsRows,
                                FullObjectName
                    FROM     @StatsInfo si
                    GROUP BY si.object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                si.FullObjectName
                    ),
                cteFragmentation
                AS ( {2}
                    ),
                cteIndexSizes
                AS ( SELECT   object_id ,
                                index_id ,
                                CASE WHEN index_id < 2
                                    THEN ( ( SUM(in_row_data_page_count
                                                + lob_used_page_count
                                                + row_overflow_used_page_count)
                                            * 8192 ) / 1024 )
                                    else ( ( SUM(used_page_count) * 8192 ) / 1024 )
                                END AS SizeKB
                    FROM     sys.dm_db_partition_stats
                    GROUP BY object_id ,
                                index_id
                    ),
                cteRows
                AS ( SELECT   object_id ,
                                index_id ,
                                SUM(rows) AS IndexRows
                    FROM     sys.partitions
                    GROUP BY object_id ,
                                index_id
                    ),
                cteIndex
                AS ( SELECT   OBJECT_NAME(c.object_id) AS ObjectName ,
                                c.object_id ,
                                c.index_id ,
                                i.name COLLATE SQL_Latin1_General_CP1_CI_AS AS name ,
                                c.index_column_id ,
                                c.column_id ,
                                c.is_included_column ,
                                CASE WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 1
                                    THEN sc.name + ' DESC'
                                    WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 0 THEN sc.name
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 1
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' DESC (' + t.name + ') '
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 0
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' (' + t.name + ')'
                                    ELSE sc.name
                                END AS ColumnName ,
                                i.filter_definition ,
                                ISNULL(dd.user_scans, 0) AS user_scans ,
                                ISNULL(dd.user_seeks, 0) AS user_seeks ,
                                ISNULL(dd.user_updates, 0) AS user_updates ,
                                ISNULL(dd.user_lookups, 0) AS user_lookups ,
                                CONVERT(DATETIME2(0), ISNULL(dd.last_user_lookup,
                                                            '1901-01-01')) AS LastLookup ,
                                CONVERT(DATETIME2(0), ISNULL(dd.last_user_scan,
                                                            '1901-01-01')) AS LastScan ,
                                CONVERT(DATETIME2(0), ISNULL(dd.last_user_seek,
                                                            '1901-01-01')) AS LastSeek ,
                                i.fill_factor ,
                                c.is_descending_key ,
                                p.data_compression_desc ,
                                i.type_desc ,
                                i.is_unique ,
                                i.is_unique_constraint ,
                                i.is_primary_key ,
                                ci.SizeKB ,
                                cr.IndexRows ,
                                QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                fr.avg_fragmentation_in_percent AS avg_fragmentation_in_percent
                    FROM     sys.indexes i
                                JOIN sys.index_columns c ON i.object_id = c.object_id
                                                            AND i.index_id = c.index_id
                                JOIN sys.columns sc ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                                INNER JOIN sys.tables tbl ON c.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                                LEFT JOIN sys.types t ON sc.user_type_id = t.user_type_id
                                LEFT JOIN @IndexUsageStats dd ON i.object_id = dd.object_id
                                                                AND i.index_id = dd.index_id --AND dd.database_id = DB_ID()
                                LEFT JOIN cteFragmentation fr ON i.object_id = fr.object_id
                                                                AND i.index_id = fr.index_id
                                JOIN sys.partitions p ON i.object_id = p.object_id
                                                        AND i.index_id = p.index_id
                                JOIN cteIndexSizes ci ON i.object_id = ci.object_id
                                                        AND i.index_id = ci.index_id
                                JOIN cteRows cr ON i.object_id = cr.object_id
                                                AND i.index_id = cr.index_id
                    WHERE    i.object_id = CASE WHEN @TableName IS NULL
                                                THEN i.object_id
                                                ELSE OBJECT_ID(@TableName)
                                            END
                    ),
                cteResults
                AS ( SELECT   ci.FullObjectName ,
                                ci.object_id ,
                                MAX(index_id) AS Index_Id ,
                                ci.type_desc
                                + CASE WHEN ci.is_primary_key = 1
                                    THEN ' (PRIMARY KEY)'
                                    WHEN ci.is_unique_constraint = 1
                                    THEN ' (UNIQUE CONSTRAINT)'
                                    WHEN ci.is_unique = 1 THEN ' (UNIQUE)'
                                    ELSE ''
                                END AS IndexType ,
                                name AS IndexName ,
                                STUFF((SELECT   N', ' + ColumnName
                                    FROM     cteIndex ci2
                                    WHERE    ci2.name = ci.name AND ci2.object_id=ci.object_id
                                                AND ci2.is_included_column = 0
                                    GROUP BY ci2.index_column_id ,
                                                ci2.ColumnName
                                    ORDER BY ci2.index_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(max)'), 1,
                                    2, N'') AS KeyColumns ,
                                ISNULL(STUFF((SELECT    N', ' + ColumnName
                                            FROM      cteIndex ci3
                                            WHERE     ci3.name = ci.name AND ci3.object_id=ci.object_id
                                                        AND ci3.is_included_column = 1
                                            GROUP BY  ci3.index_column_id ,
                                                        ci3.ColumnName
                                            ORDER BY  ci3.index_column_id
                                    FOR   XML PATH(N'') ,
                                                TYPE).value(N'.[1]',
                                                            N'nvarchar(max)'), 1, 2,
                                            N''), '') AS IncludeColumns ,
                                ISNULL(filter_definition, '') AS FilterDefinition ,
                                ci.fill_factor ,
                                CASE WHEN ci.data_compression_desc = 'NONE' THEN ''
                                    ELSE ci.data_compression_desc
                                END AS DataCompression ,
                                MAX(ci.user_seeks) + MAX(ci.user_scans)
                                + MAX(ci.user_lookups) AS IndexReads ,
                                MAX(ci.user_lookups) AS IndexLookups ,
                                ci.user_updates AS IndexUpdates ,
                                ci.SizeKB AS SizeKB ,
                                ci.IndexRows AS IndexRows ,
                                CASE WHEN LastScan >= LastSeek
                                        AND LastScan >= LastLookup
                                        AND LastScan > '1901-01-01' THEN LastScan
                                    WHEN LastSeek >= LastLookup
                                        AND LastSeek > '1901-01-01' THEN LastSeek
                                    WHEN LastLookup > '1901-01-01' THEN LastLookup
                                    ELSE ''
                                END AS MostRecentlyUsed ,
                                AVG(ci.avg_fragmentation_in_percent) AS avg_fragmentation_in_percent
                    FROM     cteIndex ci
                    GROUP BY ci.ObjectName ,
                                ci.name ,
                                ci.filter_definition ,
                                ci.object_id ,
                                ci.LastLookup ,
                                ci.LastSeek ,
                                ci.LastScan ,
                                ci.user_updates ,
                                ci.fill_factor ,
                                ci.data_compression_desc ,
                                ci.type_desc ,
                                ci.is_primary_key ,
                                ci.is_unique ,
                                ci.is_unique_constraint ,
                                ci.SizeKB ,
                                ci.IndexRows ,
                                ci.FullObjectName
                    ),
                AllResults
                AS ( SELECT   c.FullObjectName ,
                                IndexType ,
                                ISNULL(IndexName, si.stats_name) AS IndexName ,
                                NULL as StatisticsName ,
                                ISNULL(KeyColumns, si.StatsColumns) AS KeyColumns ,
                                ISNULL(IncludeColumns, '') AS IncludeColumns ,
                                FilterDefinition ,
                                fill_factor AS [FillFactor] ,
                                DataCompression ,
                                IndexReads ,
                                IndexUpdates ,
                                SizeKB ,
                                IndexRows ,
                                IndexLookups ,
                                MostRecentlyUsed ,
                                SampleRows AS StatsSampleRows ,
                                RowMods AS StatsRowMods ,
                                si.HistogramSteps ,
                                si.StatsLastUpdated ,
                                avg_fragmentation_in_percent AS IndexFragInPercent,
                                1 AS Ordering
                    FROM     cteResults c
                                INNER JOIN cteStatsInfo si ON si.object_id = c.object_id
                                                            AND si.stats_id = c.Index_Id
                    UNION
                    SELECT   QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                '' ,
                                '' ,
                                stats_name ,
                                StatsColumns ,
                                '' ,
                                '' AS FilterDefinition ,
                                '' AS Fill_Factor ,
                                '' AS DataCompression ,
                                '' AS IndexReads ,
                                '' AS IndexUpdates ,
                                '' AS SizeKB ,
                                StatsRows AS IndexRows ,
                                '' AS IndexLookups ,
                                '' AS MostRecentlyUsed ,
                                SampleRows AS StatsSampleRows ,
                                RowMods AS StatsRowMods ,
                                csi.HistogramSteps ,
                                csi.StatsLastUpdated ,
                                NULL AS IndexFragInPercent ,
                                2
                    FROM     cteStatsInfo csi
                    INNER JOIN sys.tables tbl ON csi.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                    WHERE    NOT EXISTS (
                                SELECT  1
                                FROM    cteResults c
                                WHERE   c.object_id = csi.object_id
                                        AND c.Index_Id = csi.stats_id )
                    )
            SELECT  FullObjectName ,
                    IndexType ,
                    IndexName ,
                    StatisticsName ,
                    KeyColumns ,
                    ISNULL(IncludeColumns, '') AS IncludeColumns ,
                    FilterDefinition ,
                    [FillFactor] AS [FillFactor] ,
                    DataCompression ,
                    IndexReads ,
                    IndexUpdates ,
                    SizeKB ,
                    IndexRows ,
                    IndexLookups ,
                    MostRecentlyUsed ,
                    StatsSampleRows ,
                    StatsRowMods ,
                    HistogramSteps ,
                    StatsLastUpdated ,
                    IndexFragInPercent
            FROM    AllResults
                    {3}
        OPTION  ( RECOMPILE );
        ";
}
