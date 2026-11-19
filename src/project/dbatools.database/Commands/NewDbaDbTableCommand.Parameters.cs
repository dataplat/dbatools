#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

// Parameter surface - split out per the repo 400-line file limit.
public sealed partial class NewDbaDbTableCommand
{
    // Real per-parameter boundness (W2-151): MyInvocation.BoundParameters is empty for this cmdlet, so
    // each setter records that the binder actually supplied the parameter. The projection carrier and the
    // Test-Bound gates read this instead of inferring boundness from values, which cannot tell an explicit
    // value that equals a default (e.g. -Schema dbo, -MaximumDegreeOfParallelism 0) from an unset one.
    private readonly System.Collections.Generic.HashSet<string> _bound = new System.Collections.Generic.HashSet<string>(System.StringComparer.OrdinalIgnoreCase);

    /// <summary>SqlInstance.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get => _SqlInstance; set { _SqlInstance = value; _bound.Add("SqlInstance"); } }
    private DbaInstanceParameter[]? _SqlInstance;

    /// <summary>SqlCredential.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get => _SqlCredential; set { _SqlCredential = value; _bound.Add("SqlCredential"); } }
    private PSCredential? _SqlCredential;

    /// <summary>Database.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get => _Database; set { _Database = value; _bound.Add("Database"); } }
    private string[]? _Database;

    /// <summary>Name.</summary>
    [Parameter(Position = 3)]
    [Alias("Table")]
    [PsStringCast]
    public string? Name { get => _Name; set { _Name = value; _bound.Add("Name"); } }
    private string? _Name;

    /// <summary>Schema.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string Schema { get => _Schema; set { _Schema = value; _bound.Add("Schema"); } }
    private string _Schema = "dbo";

    /// <summary>ColumnMap.</summary>
    [Parameter(Position = 5)]
    public Hashtable[]? ColumnMap { get => _ColumnMap; set { _ColumnMap = value; _bound.Add("ColumnMap"); } }
    private Hashtable[]? _ColumnMap;

    /// <summary>ColumnObject.</summary>
    [Parameter(Position = 6)]
    public Microsoft.SqlServer.Management.Smo.Column[]? ColumnObject { get => _ColumnObject; set { _ColumnObject = value; _bound.Add("ColumnObject"); } }
    private Microsoft.SqlServer.Management.Smo.Column[]? _ColumnObject;

    /// <summary>AnsiNullsStatus.</summary>
    [Parameter]
    public SwitchParameter AnsiNullsStatus { get => _AnsiNullsStatus; set { _AnsiNullsStatus = value; _bound.Add("AnsiNullsStatus"); } }
    private SwitchParameter _AnsiNullsStatus;

    /// <summary>ChangeTrackingEnabled.</summary>
    [Parameter]
    public SwitchParameter ChangeTrackingEnabled { get => _ChangeTrackingEnabled; set { _ChangeTrackingEnabled = value; _bound.Add("ChangeTrackingEnabled"); } }
    private SwitchParameter _ChangeTrackingEnabled;

    /// <summary>DataSourceName.</summary>
    [Parameter(Position = 7)]
    [PsStringCast]
    public string? DataSourceName { get => _DataSourceName; set { _DataSourceName = value; _bound.Add("DataSourceName"); } }
    private string? _DataSourceName;

    /// <summary>Durability.</summary>
    [Parameter(Position = 8)]
    public Microsoft.SqlServer.Management.Smo.DurabilityType Durability { get => _Durability; set { _Durability = value; _bound.Add("Durability"); } }
    private Microsoft.SqlServer.Management.Smo.DurabilityType _Durability;

    /// <summary>ExternalTableDistribution.</summary>
    [Parameter(Position = 9)]
    public Microsoft.SqlServer.Management.Smo.ExternalTableDistributionType ExternalTableDistribution { get => _ExternalTableDistribution; set { _ExternalTableDistribution = value; _bound.Add("ExternalTableDistribution"); } }
    private Microsoft.SqlServer.Management.Smo.ExternalTableDistributionType _ExternalTableDistribution;

    /// <summary>FileFormatName.</summary>
    [Parameter(Position = 10)]
    [PsStringCast]
    public string? FileFormatName { get => _FileFormatName; set { _FileFormatName = value; _bound.Add("FileFormatName"); } }
    private string? _FileFormatName;

    /// <summary>FileGroup.</summary>
    [Parameter(Position = 11)]
    [PsStringCast]
    public string? FileGroup { get => _FileGroup; set { _FileGroup = value; _bound.Add("FileGroup"); } }
    private string? _FileGroup;

    /// <summary>FileStreamFileGroup.</summary>
    [Parameter(Position = 12)]
    [PsStringCast]
    public string? FileStreamFileGroup { get => _FileStreamFileGroup; set { _FileStreamFileGroup = value; _bound.Add("FileStreamFileGroup"); } }
    private string? _FileStreamFileGroup;

    /// <summary>FileStreamPartitionScheme.</summary>
    [Parameter(Position = 13)]
    [PsStringCast]
    public string? FileStreamPartitionScheme { get => _FileStreamPartitionScheme; set { _FileStreamPartitionScheme = value; _bound.Add("FileStreamPartitionScheme"); } }
    private string? _FileStreamPartitionScheme;

    /// <summary>FileTableDirectoryName.</summary>
    [Parameter(Position = 14)]
    [PsStringCast]
    public string? FileTableDirectoryName { get => _FileTableDirectoryName; set { _FileTableDirectoryName = value; _bound.Add("FileTableDirectoryName"); } }
    private string? _FileTableDirectoryName;

    /// <summary>FileTableNameColumnCollation.</summary>
    [Parameter(Position = 15)]
    [PsStringCast]
    public string? FileTableNameColumnCollation { get => _FileTableNameColumnCollation; set { _FileTableNameColumnCollation = value; _bound.Add("FileTableNameColumnCollation"); } }
    private string? _FileTableNameColumnCollation;

    /// <summary>FileTableNamespaceEnabled.</summary>
    [Parameter]
    public SwitchParameter FileTableNamespaceEnabled { get => _FileTableNamespaceEnabled; set { _FileTableNamespaceEnabled = value; _bound.Add("FileTableNamespaceEnabled"); } }
    private SwitchParameter _FileTableNamespaceEnabled;

    /// <summary>HistoryTableName.</summary>
    [Parameter(Position = 16)]
    [PsStringCast]
    public string? HistoryTableName { get => _HistoryTableName; set { _HistoryTableName = value; _bound.Add("HistoryTableName"); } }
    private string? _HistoryTableName;

    /// <summary>HistoryTableSchema.</summary>
    [Parameter(Position = 17)]
    [PsStringCast]
    public string? HistoryTableSchema { get => _HistoryTableSchema; set { _HistoryTableSchema = value; _bound.Add("HistoryTableSchema"); } }
    private string? _HistoryTableSchema;

    /// <summary>IsExternal.</summary>
    [Parameter]
    public SwitchParameter IsExternal { get => _IsExternal; set { _IsExternal = value; _bound.Add("IsExternal"); } }
    private SwitchParameter _IsExternal;

    /// <summary>IsFileTable.</summary>
    [Parameter]
    public SwitchParameter IsFileTable { get => _IsFileTable; set { _IsFileTable = value; _bound.Add("IsFileTable"); } }
    private SwitchParameter _IsFileTable;

    /// <summary>IsMemoryOptimized.</summary>
    [Parameter]
    public SwitchParameter IsMemoryOptimized { get => _IsMemoryOptimized; set { _IsMemoryOptimized = value; _bound.Add("IsMemoryOptimized"); } }
    private SwitchParameter _IsMemoryOptimized;

    /// <summary>IsSystemVersioned.</summary>
    [Parameter]
    public SwitchParameter IsSystemVersioned { get => _IsSystemVersioned; set { _IsSystemVersioned = value; _bound.Add("IsSystemVersioned"); } }
    private SwitchParameter _IsSystemVersioned;

    /// <summary>Location.</summary>
    [Parameter(Position = 18)]
    [PsStringCast]
    public string? Location { get => _Location; set { _Location = value; _bound.Add("Location"); } }
    private string? _Location;

    /// <summary>LockEscalation.</summary>
    [Parameter(Position = 19)]
    public Microsoft.SqlServer.Management.Smo.LockEscalationType LockEscalation { get => _LockEscalation; set { _LockEscalation = value; _bound.Add("LockEscalation"); } }
    private Microsoft.SqlServer.Management.Smo.LockEscalationType _LockEscalation;

    /// <summary>Owner.</summary>
    [Parameter(Position = 20)]
    [PsStringCast]
    public string? Owner { get => _Owner; set { _Owner = value; _bound.Add("Owner"); } }
    private string? _Owner;

    /// <summary>PartitionScheme.</summary>
    [Parameter(Position = 21)]
    [PsStringCast]
    public string? PartitionScheme { get => _PartitionScheme; set { _PartitionScheme = value; _bound.Add("PartitionScheme"); } }
    private string? _PartitionScheme;

    /// <summary>QuotedIdentifierStatus.</summary>
    [Parameter]
    public SwitchParameter QuotedIdentifierStatus { get => _QuotedIdentifierStatus; set { _QuotedIdentifierStatus = value; _bound.Add("QuotedIdentifierStatus"); } }
    private SwitchParameter _QuotedIdentifierStatus;

    /// <summary>RejectSampleValue.</summary>
    [Parameter(Position = 22)]
    public double RejectSampleValue { get => _RejectSampleValue; set { _RejectSampleValue = value; _bound.Add("RejectSampleValue"); } }
    private double _RejectSampleValue;

    /// <summary>RejectType.</summary>
    [Parameter(Position = 23)]
    public Microsoft.SqlServer.Management.Smo.ExternalTableRejectType RejectType { get => _RejectType; set { _RejectType = value; _bound.Add("RejectType"); } }
    private Microsoft.SqlServer.Management.Smo.ExternalTableRejectType _RejectType;

    /// <summary>RejectValue.</summary>
    [Parameter(Position = 24)]
    public double RejectValue { get => _RejectValue; set { _RejectValue = value; _bound.Add("RejectValue"); } }
    private double _RejectValue;

    /// <summary>RemoteDataArchiveDataMigrationState.</summary>
    [Parameter(Position = 25)]
    public Microsoft.SqlServer.Management.Smo.RemoteDataArchiveMigrationState RemoteDataArchiveDataMigrationState { get => _RemoteDataArchiveDataMigrationState; set { _RemoteDataArchiveDataMigrationState = value; _bound.Add("RemoteDataArchiveDataMigrationState"); } }
    private Microsoft.SqlServer.Management.Smo.RemoteDataArchiveMigrationState _RemoteDataArchiveDataMigrationState;

    /// <summary>RemoteDataArchiveEnabled.</summary>
    [Parameter]
    public SwitchParameter RemoteDataArchiveEnabled { get => _RemoteDataArchiveEnabled; set { _RemoteDataArchiveEnabled = value; _bound.Add("RemoteDataArchiveEnabled"); } }
    private SwitchParameter _RemoteDataArchiveEnabled;

    /// <summary>RemoteDataArchiveFilterPredicate.</summary>
    [Parameter(Position = 26)]
    [PsStringCast]
    public string? RemoteDataArchiveFilterPredicate { get => _RemoteDataArchiveFilterPredicate; set { _RemoteDataArchiveFilterPredicate = value; _bound.Add("RemoteDataArchiveFilterPredicate"); } }
    private string? _RemoteDataArchiveFilterPredicate;

    /// <summary>RemoteObjectName.</summary>
    [Parameter(Position = 27)]
    [PsStringCast]
    public string? RemoteObjectName { get => _RemoteObjectName; set { _RemoteObjectName = value; _bound.Add("RemoteObjectName"); } }
    private string? _RemoteObjectName;

    /// <summary>RemoteSchemaName.</summary>
    [Parameter(Position = 28)]
    [PsStringCast]
    public string? RemoteSchemaName { get => _RemoteSchemaName; set { _RemoteSchemaName = value; _bound.Add("RemoteSchemaName"); } }
    private string? _RemoteSchemaName;

    /// <summary>RemoteTableName.</summary>
    [Parameter(Position = 29)]
    [PsStringCast]
    public string? RemoteTableName { get => _RemoteTableName; set { _RemoteTableName = value; _bound.Add("RemoteTableName"); } }
    private string? _RemoteTableName;

    /// <summary>RemoteTableProvisioned.</summary>
    [Parameter]
    public SwitchParameter RemoteTableProvisioned { get => _RemoteTableProvisioned; set { _RemoteTableProvisioned = value; _bound.Add("RemoteTableProvisioned"); } }
    private SwitchParameter _RemoteTableProvisioned;

    /// <summary>ShardingColumnName.</summary>
    [Parameter(Position = 30)]
    [PsStringCast]
    public string? ShardingColumnName { get => _ShardingColumnName; set { _ShardingColumnName = value; _bound.Add("ShardingColumnName"); } }
    private string? _ShardingColumnName;

    /// <summary>TextFileGroup.</summary>
    [Parameter(Position = 31)]
    [PsStringCast]
    public string? TextFileGroup { get => _TextFileGroup; set { _TextFileGroup = value; _bound.Add("TextFileGroup"); } }
    private string? _TextFileGroup;

    /// <summary>TrackColumnsUpdatedEnabled.</summary>
    [Parameter]
    public SwitchParameter TrackColumnsUpdatedEnabled { get => _TrackColumnsUpdatedEnabled; set { _TrackColumnsUpdatedEnabled = value; _bound.Add("TrackColumnsUpdatedEnabled"); } }
    private SwitchParameter _TrackColumnsUpdatedEnabled;

    /// <summary>HistoryRetentionPeriod.</summary>
    [Parameter(Position = 32)]
    public int HistoryRetentionPeriod { get => _HistoryRetentionPeriod; set { _HistoryRetentionPeriod = value; _bound.Add("HistoryRetentionPeriod"); } }
    private int _HistoryRetentionPeriod;

    /// <summary>HistoryRetentionPeriodUnit.</summary>
    [Parameter(Position = 33)]
    public Microsoft.SqlServer.Management.Smo.TemporalHistoryRetentionPeriodUnit HistoryRetentionPeriodUnit { get => _HistoryRetentionPeriodUnit; set { _HistoryRetentionPeriodUnit = value; _bound.Add("HistoryRetentionPeriodUnit"); } }
    private Microsoft.SqlServer.Management.Smo.TemporalHistoryRetentionPeriodUnit _HistoryRetentionPeriodUnit;

    /// <summary>DwTableDistribution.</summary>
    [Parameter(Position = 34)]
    public Microsoft.SqlServer.Management.Smo.DwTableDistributionType DwTableDistribution { get => _DwTableDistribution; set { _DwTableDistribution = value; _bound.Add("DwTableDistribution"); } }
    private Microsoft.SqlServer.Management.Smo.DwTableDistributionType _DwTableDistribution;

    /// <summary>RejectedRowLocation.</summary>
    [Parameter(Position = 35)]
    [PsStringCast]
    public string? RejectedRowLocation { get => _RejectedRowLocation; set { _RejectedRowLocation = value; _bound.Add("RejectedRowLocation"); } }
    private string? _RejectedRowLocation;

    /// <summary>OnlineHeapOperation.</summary>
    [Parameter]
    public SwitchParameter OnlineHeapOperation { get => _OnlineHeapOperation; set { _OnlineHeapOperation = value; _bound.Add("OnlineHeapOperation"); } }
    private SwitchParameter _OnlineHeapOperation;

    /// <summary>LowPriorityMaxDuration.</summary>
    [Parameter(Position = 36)]
    public int LowPriorityMaxDuration { get => _LowPriorityMaxDuration; set { _LowPriorityMaxDuration = value; _bound.Add("LowPriorityMaxDuration"); } }
    private int _LowPriorityMaxDuration;

    /// <summary>DataConsistencyCheck.</summary>
    [Parameter]
    public SwitchParameter DataConsistencyCheck { get => _DataConsistencyCheck; set { _DataConsistencyCheck = value; _bound.Add("DataConsistencyCheck"); } }
    private SwitchParameter _DataConsistencyCheck;

    /// <summary>LowPriorityAbortAfterWait.</summary>
    [Parameter(Position = 37)]
    public Microsoft.SqlServer.Management.Smo.AbortAfterWait LowPriorityAbortAfterWait { get => _LowPriorityAbortAfterWait; set { _LowPriorityAbortAfterWait = value; _bound.Add("LowPriorityAbortAfterWait"); } }
    private Microsoft.SqlServer.Management.Smo.AbortAfterWait _LowPriorityAbortAfterWait;

    /// <summary>MaximumDegreeOfParallelism.</summary>
    [Parameter(Position = 38)]
    public int MaximumDegreeOfParallelism { get => _MaximumDegreeOfParallelism; set { _MaximumDegreeOfParallelism = value; _bound.Add("MaximumDegreeOfParallelism"); } }
    private int _MaximumDegreeOfParallelism;

    /// <summary>IsNode.</summary>
    [Parameter]
    public SwitchParameter IsNode { get => _IsNode; set { _IsNode = value; _bound.Add("IsNode"); } }
    private SwitchParameter _IsNode;

    /// <summary>IsEdge.</summary>
    [Parameter]
    public SwitchParameter IsEdge { get => _IsEdge; set { _IsEdge = value; _bound.Add("IsEdge"); } }
    private SwitchParameter _IsEdge;

    /// <summary>IsVarDecimalStorageFormatEnabled.</summary>
    [Parameter]
    public SwitchParameter IsVarDecimalStorageFormatEnabled { get => _IsVarDecimalStorageFormatEnabled; set { _IsVarDecimalStorageFormatEnabled = value; _bound.Add("IsVarDecimalStorageFormatEnabled"); } }
    private SwitchParameter _IsVarDecimalStorageFormatEnabled;

    /// <summary>Passthru.</summary>
    [Parameter]
    public SwitchParameter Passthru { get => _Passthru; set { _Passthru = value; _bound.Add("Passthru"); } }
    private SwitchParameter _Passthru;

    /// <summary>InputObject.</summary>
    [Parameter(ValueFromPipeline = true, Position = 39)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get => _InputObject; set { _InputObject = value; _bound.Add("InputObject"); } }
    private Microsoft.SqlServer.Management.Smo.Database[]? _InputObject;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // $object / $schemaObject carried across records for the catch-cleanup failure path (codex r1):
    // if the try throws before those assignments, the SOURCE's persistent process scope still holds
    // the PREVIOUS record's objects and the cleanup drops them. Opaque to C#.
    private Hashtable? _state;
}
