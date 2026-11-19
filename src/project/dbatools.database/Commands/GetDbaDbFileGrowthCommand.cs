#nullable enable

using System;
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

// Port of public/Get-DbaDbFileGrowth.ps1, which forwards its bound parameters to Get-DbaDbFile once per record and
// shapes each file row with Select-DefaultView. The Get-DbaDbFile reading (public/Get-DbaDbFile.ps1 at the active pin) is
// absorbed here: its messages and Stop-Function sites keep the Get-DbaDbFile attribution, and its rows are collected for
// the whole record before any is emitted, as the source's $dbs assignment does. Surface pinned by
// migration/baselines/Get-DbaDbFileGrowth.json (positions 0-3, InputObject VFP, no ShouldProcess). The help below is the
// pinned comment-based help of refs/pins/dbatools-2026-10-22:public/Get-DbaDbFileGrowth.ps1.
/// <summary>Retrieves database file auto-growth settings and maximum size limits</summary>
/// <para>
/// Retrieves auto-growth configuration for data and log files across SQL Server databases, including growth type (percentage or fixed MB), growth increment values, and maximum size limits. This function helps DBAs quickly identify databases with problematic growth settings like percentage-based growth on large files, unlimited growth configurations, or insufficient growth increments that could cause performance issues during auto-growth events.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbFileGrowth -SqlInstance sql2017, sql2016, sql2012
/// </code>
/// <para>
/// Gets all database file growths on sql2017, sql2016, sql2012
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbFileGrowth -SqlInstance sql2017, sql2016, sql2012 -Database pubs
/// </code>
/// <para>
/// Gets the database file growth info for pubs on sql2017, sql2016, sql2012
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDatabase -SqlInstance sql2016 -Database test | Get-DbaDbFileGrowth
/// </code>
/// <para>
/// Gets the test database file growth information on sql2016
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Storage, Data, File, Log
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2021 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbFileGrowth" />
[Cmdlet(VerbsCommon.Get, "DbaDbFileGrowth")]
public sealed class GetDbaDbFileGrowthCommand : DbaBaseCmdlet
{
    private const string FileFunction = "Get-DbaDbFile";

    private const string SqlColumns = @"SELECT
            fg.name AS FileGroupName,
            df.file_id AS 'ID',
            df.Type,
            df.type_desc AS TypeDescription,
            df.name AS LogicalName,
            mf.physical_name AS PhysicalName,
            df.state_desc AS State,
            df.max_size AS MaxSize,
            CASE mf.is_percent_growth WHEN 1 THEN df.growth ELSE df.Growth*8 END AS Growth,
            COALESCE(FILEPROPERTY(df.name, 'spaceused'), 0) AS UsedSpace,
            df.size AS Size,
            COALESCE(vfs.size_on_disk_bytes, 0) AS size_on_disk_bytes,
            CASE df.state_desc WHEN 'OFFLINE' THEN 'True' ELSE 'False' END AS IsOffline,
            CASE mf.is_read_only WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnly,
            CASE mf.is_media_read_only WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnlyMedia,
            CASE mf.is_sparse WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsSparse,
            CASE mf.is_percent_growth WHEN 1 THEN 'Percent' WHEN 0 THEN 'kb' END AS GrowthType,
            COALESCE(vfs.num_of_writes, 0) AS NumberOfDiskWrites,
            COALESCE(vfs.num_of_reads, 0) AS NumberOfDiskReads,
            COALESCE(vfs.num_of_bytes_read, 0) AS BytesReadFromDisk,
            COALESCE(vfs.num_of_bytes_written, 0) AS BytesWrittenToDisk,
            fg.data_space_id AS FileGroupDataSpaceId,
            fg.Type AS FileGroupType,
            fg.type_desc AS FileGroupTypeDescription,
            CASE fg.is_default WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS FileGroupDefault,
            fg.is_read_only AS FileGroupReadOnly";

    private const string SqlFrom = @"FROM sys.database_files df
            LEFT OUTER JOIN  sys.filegroups fg ON df.data_space_id=fg.data_space_id
            LEFT JOIN sys.dm_io_virtual_file_stats(DB_ID(),NULL) vfs ON df.file_id=vfs.file_id
            INNER JOIN sys.master_files mf ON df.file_id = mf.file_id
            AND mf.database_id = DB_ID()";

    // Correction azure-database-files: Azure SQL Database keeps no sys.master_files and no volume statistics
    // (Microsoft Learn: sys.master_files and sys.dm_os_volume_stats apply to SQL Server and Azure SQL Managed
    // Instance only), so there the same columns are read from the database's own sys.database_files.
    private const string SqlColumnsAzure = @"SELECT
            fg.name AS FileGroupName,
            df.file_id AS 'ID',
            df.Type,
            df.type_desc AS TypeDescription,
            df.name AS LogicalName,
            df.physical_name AS PhysicalName,
            df.state_desc AS State,
            df.max_size AS MaxSize,
            CASE df.is_percent_growth WHEN 1 THEN df.growth ELSE df.Growth*8 END AS Growth,
            COALESCE(FILEPROPERTY(df.name, 'spaceused'), 0) AS UsedSpace,
            df.size AS Size,
            COALESCE(vfs.size_on_disk_bytes, 0) AS size_on_disk_bytes,
            CASE df.state_desc WHEN 'OFFLINE' THEN 'True' ELSE 'False' END AS IsOffline,
            CASE df.is_read_only WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnly,
            CASE df.is_media_read_only WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnlyMedia,
            CASE df.is_sparse WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsSparse,
            CASE df.is_percent_growth WHEN 1 THEN 'Percent' WHEN 0 THEN 'kb' END AS GrowthType,
            COALESCE(vfs.num_of_writes, 0) AS NumberOfDiskWrites,
            COALESCE(vfs.num_of_reads, 0) AS NumberOfDiskReads,
            COALESCE(vfs.num_of_bytes_read, 0) AS BytesReadFromDisk,
            COALESCE(vfs.num_of_bytes_written, 0) AS BytesWrittenToDisk,
            fg.data_space_id AS FileGroupDataSpaceId,
            fg.Type AS FileGroupType,
            fg.type_desc AS FileGroupTypeDescription,
            CASE fg.is_default WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS FileGroupDefault,
            fg.is_read_only AS FileGroupReadOnly";

    private const string SqlFromAzure = @"FROM sys.database_files df
            LEFT OUTER JOIN  sys.filegroups fg ON df.data_space_id=fg.data_space_id
            LEFT JOIN sys.dm_io_virtual_file_stats(DB_ID(),NULL) vfs ON df.file_id=vfs.file_id";

    private const string SqlVolumeColumn = ",vs.available_bytes AS 'VolumeFreeSpace'";

    private const string SqlVolumeFrom = "CROSS APPLY sys.dm_os_volume_stats(DB_ID(),df.file_id) vs";

    private const string Sql2000 =
        "SELECT\n" +
        "            fg.groupname AS FileGroupName,\n" +
        "            df.fileid AS ID,\n" +
        "            CONVERT(INT,df.status & 0x40) / 64 AS Type,\n" +
        "            CASE CONVERT(INT,df.status & 0x40) / 64 WHEN 1 THEN 'LOG' ELSE 'ROWS' END AS TypeDescription,\n" +
        "            df.name AS LogicalName,\n" +
        "            df.filename AS PhysicalName,\n" +
        "            'Existing' AS State,\n" +
        "            df.maxsize AS MaxSize,\n" +
        "            CASE CONVERT(INT,df.status & 0x100000) / 1048576 WHEN 1 THEN df.growth WHEN 0 THEN df.growth*8 END AS Growth,\n" +
        "            FILEPROPERTY(df.name, 'spaceused') AS UsedSpace,\n" +
        "            df.size AS Size,\n" +
        "            CASE CONVERT(INT,df.status & 0x20000000) / 536870912 WHEN 1 THEN 'True' ELSE 'False' END AS IsOffline,\n" +
        "            CASE CONVERT(INT,df.status & 0x1000) / 4096 WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnlyMedia,\n" +
        "            CASE CONVERT(INT,df.status & 0x10000000) / 268435456 WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsSparse,\n" +
        "            CASE CONVERT(INT,df.status & 0x100000) / 1048576 WHEN 1 THEN 'Percent' WHEN 0 THEN 'kb' END AS GrowthType,\n" +
        "            CASE CONVERT(INT,df.status & 0x1000) / 4096 WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnly,\n" +
        "            fg.groupid AS FileGroupDataSpaceId,\n" +
        "            NULL AS FileGroupType,\n" +
        "            NULL AS FileGroupTypeDescription,\n" +
        "            CAST(fg.status & 0x10 AS BIT) AS FileGroupDefault,\n" +
        "            CAST(fg.status & 0x8 AS BIT) AS FileGroupReadOnly\n" +
        "            FROM sysfiles df\n" + // style-ok: sql-deprecated-views pinned compatibility level 80 query, also the pinned fallback when the level lookup fails
        "            LEFT OUTER JOIN  sysfilegroups fg ON df.groupid=fg.groupid"; // style-ok: sql-deprecated-views pinned compatibility level 80 query, also the pinned fallback when the level lookup fails

    private const string SqlCompatibilityLevel = "SELECT compatibility_level FROM sys.databases WHERE database_id = {0}";

    private const string SqlMasterFiles = @"SELECT
    mf.file_id AS 'ID',
    mf.Type,
    mf.type_desc AS TypeDescription,
    mf.name AS LogicalName,
    mf.physical_name AS PhysicalName,
    mf.state_desc AS State,
    mf.max_size AS MaxSize,
    CASE mf.is_percent_growth WHEN 1 THEN mf.growth ELSE mf.Growth*8 END AS Growth,
    mf.size AS Size,
    CASE mf.state_desc WHEN 'OFFLINE' THEN 'True' ELSE 'False' END AS IsOffline,
    CASE mf.is_read_only WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnly,
    CASE mf.is_media_read_only WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnlyMedia,
    CASE mf.is_sparse WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsSparse,
    CASE mf.is_percent_growth WHEN 1 THEN 'Percent' WHEN 0 THEN 'kb' END AS GrowthType,
    NULLIF(mf.data_space_id, 0) AS FileGroupDataSpaceId
FROM sys.master_files mf
WHERE mf.database_id = {0}";

    private const string SqlMasterFiles2000 =
        "SELECT\n" +
        "    df.fileid AS ID,\n" +
        "    CONVERT(INT,df.status & 0x40) / 64 AS Type,\n" +
        "    CASE CONVERT(INT,df.status & 0x40) / 64 WHEN 1 THEN 'LOG' ELSE 'ROWS' END AS TypeDescription,\n" +
        "    df.name AS LogicalName,\n" +
        "    df.filename AS PhysicalName,\n" +
        "    'Existing' AS State,\n" +
        "    df.maxsize AS MaxSize,\n" +
        "    CASE CONVERT(INT,df.status & 0x100000) / 1048576 WHEN 1 THEN df.growth WHEN 0 THEN df.growth*8 END AS Growth,\n" +
        "    df.size AS Size,\n" +
        "    CASE CONVERT(INT,df.status & 0x20000000) / 536870912 WHEN 1 THEN 'True' ELSE 'False' END AS IsOffline,\n" +
        "    CASE CONVERT(INT,df.status & 0x1000) / 4096 WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnly,\n" +
        "    CASE CONVERT(INT,df.status & 0x1000) / 4096 WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsReadOnlyMedia,\n" +
        "    CASE CONVERT(INT,df.status & 0x10000000) / 268435456 WHEN 1 THEN 'True' WHEN 0 THEN 'False' END AS IsSparse,\n" +
        "    CASE CONVERT(INT,df.status & 0x100000) / 1048576 WHEN 1 THEN 'Percent' WHEN 0 THEN 'kb' END AS GrowthType,\n" +
        "    NULLIF(df.groupid, 0) AS FileGroupDataSpaceId\n" +
        "FROM master.dbo.sysaltfiles df\n" + // style-ok: sql-deprecated-views VersionMajor 8 branch of the pinned source
        "WHERE df.dbid = {0}";

    private const string SqlFixedDrives = @"-- to get drive free space for each drive that a database has files on
DECLARE @FixedDrives TABLE(Drive CHAR(1), MB_Free BIGINT);
INSERT @FixedDrives EXEC sys.xp_fixeddrives;

SELECT DISTINCT fd.MB_Free, LEFT(df.physical_name, 1) AS [Drive]
FROM @FixedDrives AS fd
INNER JOIN sys.database_files AS df
ON fd.Drive = LEFT(df.physical_name, 1);";

    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies which databases to analyze for file growth settings. Accepts wildcards for pattern matching.
    /// Use this when you need to check growth configuration for specific databases instead of all databases on the instance.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <para>
    /// Accepts database objects from Get-DbaDatabase via pipeline input.
    /// Use this when you want to analyze file growth settings for databases already retrieved by another dbatools command.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public SmoDatabase[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // SqlInstance is never pipeline-bound, so its databases belong to the invocation, not to a record.
    private bool _instancesRead;

    protected override void ProcessRecord()
    {
        // The source has no Test-FunctionInterrupt gate, so this invocation-level guard warns for every record.
        if (TestBound(nameof(Database)) && !TestBound(nameof(SqlInstance)))
        {
            StopFunction("You must specify SqlInstance when specifying Database");
            return;
        }

        foreach (PSObject file in ReadFiles())
        {
            // Select-DefaultView -Property ..., 'LogicalName as File', 'PhysicalName as FileName', State
            OutputHelper.AddAliasProperty(file, "File", "LogicalName");
            OutputHelper.AddAliasProperty(file, "FileName", "PhysicalName");
            OutputHelper.SetDefaultDisplayPropertySet(file, "ComputerName", "InstanceName", "SqlInstance",
                "Database", "MaxSize", "GrowthType", "Growth", "File", "FileName", "State");
            WriteObject(file);
        }
    }

    // One Get-DbaDbFile invocation with this record's bound parameters: piped databases first, then the
    // databases Get-DbaDatabase finds on SqlInstance (which does not receive EnableException).
    private List<PSObject> ReadFiles()
    {
        List<PSObject> files = new();
        List<SmoDatabase?> databases = new();
        if (InputObject != null)
            databases.AddRange(InputObject);
        // The source forwards -SqlInstance to Get-DbaDbFile on every piped record, which appended the
        // instance databases each time and repeated their file rows once per record. They are read
        // once, on the first record, after that record's piped databases.
        if (LanguagePrimitives.IsTrue(SqlInstance) && !_instancesRead)
        {
            _instancesRead = true;
            // Pinned help documents wildcards for -Database, which Get-DbaDatabase's literal -in never
            // honoured; it opts in to the shared wildcard union.
            databases.AddRange(NativeDatabaseSelection.GatherMatching(this, SqlInstance, SqlCredential, Database, true,
                null, false, server => SetActiveConnection(server.ConnectionContext), () => Interrupted));
        }
        foreach (SmoDatabase? database in databases)
            ReadDatabase(database, files);
        return files;
    }

    private void ReadDatabase(SmoDatabase? database, List<PSObject> files)
    {
        Server? server = database?.Parent;
        string label = database?.ToString() ?? String.Empty;
        FileMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Querying database {0}", label));

        // An inaccessible database cannot be the query context, so its layout is read from master.
        // A null array element reads as inaccessible, exactly as -not $db.IsAccessible does.
        bool useMasterFiles = database is null || !database.IsAccessible;
        string query;
        if (useMasterFiles)
        {
            FileMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                "Database {0} is not accessible, reading the file layout from master instead", label));
            // The FileGroup skip of the source cannot occur: this command never forwards -FileGroup.
            bool legacy = server is null || server.VersionMajor <= 8;
            query = String.Format(CultureInfo.InvariantCulture, legacy ? SqlMasterFiles2000 : SqlMasterFiles, database?.ID ?? 0);
        }
        else if (server!.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase)
        {
            // Correction azure-database-files: the database's own catalog, without sys.master_files.
            query = String.Join("\n", SqlColumnsAzure, SqlFromAzure);
        }
        else
        {
            int version = CompatibilityVersion(server!, database!.ID);
            if (version >= 11)
                query = String.Join("\n", SqlColumns, SqlVolumeColumn, SqlFrom, SqlVolumeFrom);
            else if (version >= 9)
                query = String.Join("\n", SqlColumns, SqlFrom);
            else
                query = Sql2000;
        }

        FileMessage(MessageLevel.Debug, "SQL Statement: " + query);

        if (server is null)
        {
            // $server.Query(...) on the null parent of a null element, caught by the source's try.
            ErrorRecord nullCall = new(new RuntimeException("You cannot call a method on a null-valued expression."),
                "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null);
            FileStop("Failure", nullCall, null);
            return;
        }

        DataTable? results;
        ErrorRecord? failure;
        if (!TryQuery(server, useMasterFiles ? null : database!.Name, query, out results, out failure))
        {
            FileStop("Failure", failure, null);
            return;
        }

        // sys.master_files rows are visible only with CREATE DATABASE, ALTER ANY DATABASE or VIEW ANY
        // DEFINITION, so an empty result there is a permission problem.
        if (useMasterFiles && (results is null || results.Rows.Count == 0))
        {
            FileStop(String.Format(CultureInfo.InvariantCulture,
                "No file information returned for the inaccessible database {0} on {1}. Reading it needs CREATE DATABASE, ALTER ANY DATABASE or VIEW ANY DEFINITION permission on the instance.",
                label, server), null, database);
            return;
        }

        if (results is null)
            return;
        foreach (DataRow row in results.Rows)
            files.Add(BuildFile(server, database!, row, useMasterFiles));
    }

    private PSObject BuildFile(Server server, SmoDatabase database, DataRow row, bool useMasterFiles)
    {
        Size size = new(Number(Column(row, "Size")) * 8192);
        Size? usedSpace = null;
        Size? availableSpace = null;
        if (!useMasterFiles)
        {
            usedSpace = new Size(Number(Column(row, "UsedSpace")) * 8192);
            // Available space uses the recorded size; the reported size then becomes the allocated one,
            // which differs for snapshots and sparse files.
            availableSpace = size - usedSpace;
            object? onDisk = Column(row, "size_on_disk_bytes");
            if (LanguagePrimitives.IsTrue(onDisk))
                size = ToSize(onDisk)!;
        }

        long maxPages = Number(Column(row, "MaxSize"));
        Size maxSize = maxPages > -1 ? new Size(maxPages * 8192) : new Size(maxPages);

        object? numberOfDiskWrites = null;
        object? numberOfDiskReads = null;
        Size? readFromDisk = null;
        Size? writtenToDisk = null;
        object? fileGroupName = null;
        object? fileGroupType = null;
        object? fileGroupTypeDescription = null;
        object? fileGroupDefault = null;
        object? fileGroupReadOnly = null;
        Size? volumeFreeSpace = null;
        if (!useMasterFiles)
        {
            numberOfDiskWrites = Column(row, "NumberOfDiskWrites");
            numberOfDiskReads = Column(row, "NumberOfDiskReads");
            readFromDisk = ToSize(Column(row, "BytesReadFromDisk"));
            writtenToDisk = ToSize(Column(row, "BytesWrittenToDisk"));
            fileGroupName = Column(row, "FileGroupName");
            fileGroupType = Column(row, "FileGroupType");
            fileGroupTypeDescription = Column(row, "FileGroupTypeDescription");
            fileGroupDefault = Column(row, "FileGroupDefault");
            fileGroupReadOnly = Column(row, "FileGroupReadOnly");

            object? volume = Column(row, "VolumeFreeSpace");
            // Correction azure-database-files: Azure SQL Database exposes no volume (and no xp_fixeddrives), so its
            // free space stays unknown (null), never 0.
            if (LanguagePrimitives.IsTrue(volume))
                volumeFreeSpace = ToSize(volume);
            else if (server.VersionMajor > 8 && server.DatabaseEngineType != DatabaseEngineType.SqlAzureDatabase)
                volumeFreeSpace = FixedDriveFreeSpace(server, database.Name, Column(row, "PhysicalName"));
        }

        long growth = Number(Column(row, "Growth"));
        Size nextGrowth;
        if (String.Equals(Text(Column(row, "GrowthType")), "Percent", StringComparison.OrdinalIgnoreCase))
            nextGrowth = new Size((long)((double)(Number(Column(row, "Size")) * 8) * (growth * 0.01) * 1024));
        else
            nextGrowth = new Size(growth * 1024);
        if (nextGrowth.Byte > maxSize.Byte - size.Byte && maxSize.Byte > 0)
            nextGrowth = new Size(0);

        PSObject file = new();
        OutputHelper.AddInstanceProperties(file, server);
        file.Properties.Add(new PSNoteProperty("Database", database.Name));
        file.Properties.Add(new PSNoteProperty("DatabaseID", database.ID));
        file.Properties.Add(new PSNoteProperty("FileGroupName", fileGroupName));
        file.Properties.Add(new PSNoteProperty("ID", Column(row, "ID")));
        file.Properties.Add(new PSNoteProperty("Type", Column(row, "Type")));
        file.Properties.Add(new PSNoteProperty("TypeDescription", Column(row, "TypeDescription")));
        file.Properties.Add(new PSNoteProperty("LogicalName", Text(Column(row, "LogicalName")).Trim()));
        file.Properties.Add(new PSNoteProperty("PhysicalName", Text(Column(row, "PhysicalName")).Trim()));
        file.Properties.Add(new PSNoteProperty("State", Column(row, "State")));
        file.Properties.Add(new PSNoteProperty("MaxSize", maxSize));
        file.Properties.Add(new PSNoteProperty("Growth", Column(row, "Growth")));
        file.Properties.Add(new PSNoteProperty("GrowthType", Column(row, "GrowthType")));
        file.Properties.Add(new PSNoteProperty("NextGrowthEventSize", nextGrowth));
        file.Properties.Add(new PSNoteProperty("Size", size));
        file.Properties.Add(new PSNoteProperty("UsedSpace", usedSpace));
        file.Properties.Add(new PSNoteProperty("AvailableSpace", availableSpace));
        file.Properties.Add(new PSNoteProperty("IsOffline", Column(row, "IsOffline")));
        file.Properties.Add(new PSNoteProperty("IsReadOnly", Column(row, "IsReadOnly")));
        file.Properties.Add(new PSNoteProperty("IsReadOnlyMedia", Column(row, "IsReadOnlyMedia")));
        file.Properties.Add(new PSNoteProperty("IsSparse", Column(row, "IsSparse")));
        file.Properties.Add(new PSNoteProperty("NumberOfDiskWrites", numberOfDiskWrites));
        file.Properties.Add(new PSNoteProperty("NumberOfDiskReads", numberOfDiskReads));
        file.Properties.Add(new PSNoteProperty("ReadFromDisk", readFromDisk));
        file.Properties.Add(new PSNoteProperty("WrittenToDisk", writtenToDisk));
        file.Properties.Add(new PSNoteProperty("VolumeFreeSpace", volumeFreeSpace));
        file.Properties.Add(new PSNoteProperty("FileGroupDataSpaceId", Column(row, "FileGroupDataSpaceId")));
        file.Properties.Add(new PSNoteProperty("FileGroupType", fileGroupType));
        file.Properties.Add(new PSNoteProperty("FileGroupTypeDescription", fileGroupTypeDescription));
        file.Properties.Add(new PSNoteProperty("FileGroupDefault", fileGroupDefault));
        file.Properties.Add(new PSNoteProperty("FileGroupReadOnly", fileGroupReadOnly));
        return file;
    }

    // Compatibility levels below 110 carry no volume statistics column, so the source asks
    // xp_fixeddrives for the free space of the drive letter the file lives on.
    private Size? FixedDriveFreeSpace(Server server, string databaseName, object? physicalName)
    {
        DataTable? disks;
        ErrorRecord? failure;
        if (!TryQuery(server, databaseName, SqlFixedDrives, out disks, out failure))
        {
            // caller-try: terminate -- this query sits outside any source try; it continues only without a caller try, and then reuses the previous file's drive list
            ThrowTerminatingError(failure!); // style-ok: cs-raw-streams uncaught statement fault of the source, not a Stop-Function site
        }

        string path = Text(physicalName);
        if (disks is null || path.Length == 0)
            return null;
        string drive = path.Substring(0, 1);
        foreach (DataRow disk in disks.Rows)
        {
            if (LanguagePrimitives.Equals(Column(disk, "Drive"), drive, true, CultureInfo.InvariantCulture))
                return new Size(Number(Column(disk, "MB_Free")) * 1024 * 1024);
        }
        return null;
    }

    // $version = $server.Query(...); [int]($version.compatibility_level / 10), with any failure read as 8.
    // No row reads as 0, which selects the compatibility level 80 query as the source does.
    private int CompatibilityVersion(Server server, int databaseId)
    {
        DataTable? table;
        ErrorRecord? failure;
        string query = String.Format(CultureInfo.InvariantCulture, SqlCompatibilityLevel, databaseId);
        if (!TryQuery(server, null, query, out table, out failure))
            return 8;
        if (table is null || table.Rows.Count == 0)
            return 0;
        try
        {
            object? level = Column(table.Rows[0], "compatibility_level");
            if (level is null || level is DBNull)
                return 0;
            return Convert.ToInt32(Convert.ToDouble(level, CultureInfo.InvariantCulture) / 10);
        }
        catch (Exception)
        {
            // The conversion runs inside the source's try as well, whose catch selects 8.
            return 8;
        }
    }

    // The Server.Query script method of xml/dbatools.Types.ps1xml: database-scoped queries run through the
    // database object and put the previous database context back; failures surface as the
    // MethodInvocationException that calling the script method produces.
    private bool TryQuery(Server server, string? databaseName, string query, out DataTable? table, out ErrorRecord? failure)
    {
        table = null;
        failure = null;
        SetActiveConnection(server.ConnectionContext);
        try
        {
            DataSet result;
            if (databaseName != null)
            {
                ServerConnection connection = server.ConnectionContext;
                string previous = connection.CurrentDatabase;
                try
                {
                    SmoDatabase? target = server.Databases[databaseName];
                    if (target is null)
                        throw new NullTargetException();
                    result = target.ExecuteWithResults(query);
                }
                finally
                {
                    RestoreDatabaseContext(connection, previous);
                }
            }
            else
            {
                result = server.ConnectionContext.ExecuteWithResults(query);
            }
            table = result.Tables.Count > 0 ? result.Tables[0] : null;
            return true;
        }
        catch (Exception error) when (error is not PipelineStoppedException)
        {
            // The script method concatenates the messages below the method-call wrapper and throws that text.
            string message = String.Empty;
            if (error is not NullTargetException)
            {
                Exception inner = error;
                while (inner.InnerException != null)
                {
                    message += inner.Message;
                    inner = inner.InnerException;
                }
                message += inner.Message;
            }
            MethodInvocationException wrapped = new(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Query\" with \"{0}\" argument(s): \"{1}\"", databaseName != null ? 2 : 1, message),
                new RuntimeException(message));
            failure = new ErrorRecord(wrapped, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
            return false;
        }
    }

    private void RestoreDatabaseContext(ServerConnection connection, string previous)
    {
        // Case-sensitive on purpose: database names follow the instance collation.
        if (String.IsNullOrEmpty(previous) || String.Equals(connection.CurrentDatabase, previous, StringComparison.Ordinal))
            return;
        try
        {
            connection.ExecuteNonQuery("USE [" + previous.Replace("]", "]]") + "]");
        }
        catch (Exception error) when (error is not PipelineStoppedException)
        {
            // Restoring the context is housekeeping and never becomes the outcome of the query.
            string text = String.Format(CultureInfo.InvariantCulture,
                "The database context could not be restored to [{0}]: Exception calling \"ExecuteNonQuery\" with \"1\" argument(s): \"{1}\"",
                previous, error.Message);
            try
            {
                WriteWarning(text); // style-ok: cs-raw-streams the source script method calls plain Write-Warning, not Write-Message
            }
            catch (ActionPreferenceStopException)
            {
                // The source forces this one warning to Continue, so a Stop preference must not end the command here.
            }
        }
    }

    private void FileMessage(MessageLevel level, string message)
    {
        WriteAttributedMessage(FileFunction, level, message);
    }

    // Stop-Function -Continue inside Get-DbaDbFile: its own attribution and error ID. Under EnableException
    // it throws out of Get-DbaDbFile and out of this command, which has no try around that call.
    private void FileStop(string message, ErrorRecord? failure, object? target)
    {
        bool enableException = EnableException.ToBool();
        MessageService.MessageRequest request = new()
        {
            FunctionName = FileFunction,
            ModuleName = "dbatools",
            Level = MessageLevel.Warning,
            Message = message,
            EnableException = enableException,
            SuppressWarningDisplay = enableException,
            FromStopFunction = true,
            File = MyInvocation.ScriptName,
            Line = MyInvocation.ScriptLineNumber
        };
        object? displayTarget = target is null ? null :
            MessageService.CollapseTarget(MessageService.ResolveTarget(this, request, target));
        ErrorRecord record;
        if (failure != null)
        {
            Exception transformed = MessageService.ResolveException(this, request, failure.Exception);
            ErrorRecord input = ReferenceEquals(transformed, failure.Exception) ? failure :
                new ErrorRecord(transformed, failure.FullyQualifiedErrorId, failure.CategoryInfo.Category, failure.TargetObject);
            record = new ErrorRecord(new Exception(MessageService.GetErrorMessage(input), input.Exception),
                "dbatools_" + FileFunction, input.CategoryInfo.Category, displayTarget);
        }
        else
        {
            record = new ErrorRecord(new Exception(message), "dbatools_" + FileFunction, ErrorCategory.NotSpecified, displayTarget);
            request.OverrideExceptionMessage = true;
        }
        request.Target = displayTarget;
        request.ErrorRecord = new[] { record };
        MessageService.Write(this, request);
        if (enableException)
        {
            // caller-try: terminate -- Stop-Function under EnableException throws out of Get-DbaDbFile and the source has no try around that call
            ThrowTerminatingError(record); // style-ok: cs-raw-streams keeps the absorbed Get-DbaDbFile attribution after the native message path
        }
        InsertGlobalError(record);
    }

    // Stop-Function's redirected Write-Error lands the record in $Error without displaying it.
    private void InsertGlobalError(ErrorRecord record)
    {
        try
        {
            if (SessionState.PSVariable.GetValue("global:Error") is System.Collections.ArrayList errors)
            {
                errors.Insert(0, record);
                int limit;
                if (!Int32.TryParse(Convert.ToString(SessionState.PSVariable.GetValue("MaximumErrorCount"), CultureInfo.InvariantCulture), out limit))
                    limit = 256;
                if (limit >= 0 && errors.Count > limit)
                    errors.RemoveRange(limit, errors.Count - limit);
            }
        }
        catch (Exception)
        {
            // As in the shared native stop path, restricted session state must not replace the original failure.
        }
    }

    // $result.<Column>: a column the query did not select reads as null, a NULL value as DBNull.
    private static object? Column(DataRow row, string name)
    {
        return row.Table.Columns.Contains(name) ? row[name] : null;
    }

    private static long Number(object? value)
    {
        if (value is null || value is DBNull)
            return 0;
        return Convert.ToInt64(value, CultureInfo.InvariantCulture);
    }

    private static string Text(object? value)
    {
        return Convert.ToString(value, CultureInfo.InvariantCulture) ?? String.Empty;
    }

    // [dbasize]$value: PowerShell's own conversion, so a missing column stays null.
    private static Size? ToSize(object? value)
    {
        if (value is null)
            return null;
        return (Size?)LanguagePrimitives.ConvertTo(value, typeof(Size), CultureInfo.InvariantCulture);
    }

    // $this.Databases[$Database] returned null, so the script method's catch has no inner message.
    private sealed class NullTargetException : Exception
    {
    }
}
