#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Restores SQL Server databases from backup files with intelligent backup chain selection
/// and point-in-time recovery — the orchestrator over Get/Format/Select/Test-
/// DbaBackupInformation and Invoke-DbaAdvancedRestore. Port of
/// public/Restore-DbaDatabase.ps1; surface pinned by
/// migration/baselines/Restore-DbaDatabase.json.
/// </summary>
[Cmdlet(VerbsData.Restore, "DbaDatabase", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium, DefaultParameterSetName = "Restore")]
[OutputType(typeof(PSObject), typeof(string))]
public sealed partial class RestoreDbaDatabaseCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Mandatory = true)]
    public DbaInstanceParameter SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Location of backup files: local paths, UNC paths, Azure or S3 URLs, or piped file objects.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "Restore")]
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "RestorePage")]
    public object[] Path { get; set; } = null!;

    /// <summary>Target database name for the restored database when different from the original.</summary>
    [Parameter(ValueFromPipeline = true)]
    [Alias("Name")]
    public object[]? DatabaseName { get; set; }

    /// <summary>Target directory for data files on the destination instance.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public string? DestinationDataDirectory { get; set; }

    /// <summary>Target directory for transaction log files.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public string? DestinationLogDirectory { get; set; }

    /// <summary>Target directory for FILESTREAM data containers.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public string? DestinationFileStreamDirectory { get; set; }

    /// <summary>Point-in-time recovery target.</summary>
    [Parameter(ParameterSetName = "Restore")]
    [PsDateTimeCast]
    public DateTime RestoreTime { get; set; } = DateTime.Now.AddYears(1);

    /// <summary>Leaves the database in a restoring state for additional log restores.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter NoRecovery { get; set; }

    /// <summary>Allows overwriting an existing database with the same name.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter WithReplace { get; set; }

    /// <summary>Maintains replication settings when restoring.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter KeepReplication { get; set; }

    /// <summary>Forces backup file discovery through xp_dirtree.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter XpDirTree { get; set; }

    /// <summary>Prevents the XpDirTree scan from recursing.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter NoXpDirRecurse { get; set; }

    /// <summary>Generates the T-SQL RESTORE statements without executing them.</summary>
    [Parameter]
    public SwitchParameter OutputScriptOnly { get; set; }

    /// <summary>Validates backup files and restore paths without restoring.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter VerifyOnly { get; set; }

    /// <summary>Optimizes scanning for Ola Hallengren Maintenance Solution folder structures.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter MaintenanceSolutionBackup { get; set; }

    /// <summary>Maps logical file names to physical restore paths.</summary>
    [Parameter(ParameterSetName = "Restore", ValueFromPipelineByPropertyName = true)]
    public Hashtable? FileMapping { get; set; }

    /// <summary>Excludes transaction log backups from the restore.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter IgnoreLogBackup { get; set; }

    /// <summary>Skips differential backups during the restore.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter IgnoreDiffBackup { get; set; }

    /// <summary>Restores files to the instance's default data and log directories.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter UseDestinationDefaultDirectories { get; set; }

    /// <summary>Maintains the original file directory structure from the source server.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter ReuseSourceFolderStructure { get; set; }

    /// <summary>Prefix applied to all restored files (log and data).</summary>
    [Parameter(ParameterSetName = "Restore")]
    public string DestinationFilePrefix { get; set; } = "";

    /// <summary>Prefix for the restored database's name.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public string? RestoredDatabaseNamePrefix { get; set; }

    /// <summary>Bypasses backup header validation for piped backup history.</summary>
    [Parameter(ParameterSetName = "Restore")]
    [Parameter(ParameterSetName = "RestorePage")]
    public SwitchParameter TrustDbBackupHistory { get; set; }

    /// <summary>Maximum data transfer unit for the restore.</summary>
    [Parameter(ParameterSetName = "Restore")]
    [Parameter(ParameterSetName = "RestorePage")]
    public int MaxTransferSize { get; set; }

    /// <summary>Physical block size for backup reading.</summary>
    [Parameter(ParameterSetName = "Restore")]
    [Parameter(ParameterSetName = "RestorePage")]
    public int BlockSize { get; set; }

    /// <summary>Number of I/O buffers for the restore.</summary>
    [Parameter(ParameterSetName = "Restore")]
    [Parameter(ParameterSetName = "RestorePage")]
    public int BufferCount { get; set; }

    /// <summary>Recurse into the specified directory.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter DirectoryRecurse { get; set; }

    /// <summary>Directory for standby undo files (STANDBY mode).</summary>
    [Parameter(ParameterSetName = "Restore")]
    public string? StandbyDirectory { get; set; }

    /// <summary>Resumes log restores on databases in RESTORING or STANDBY state.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter Continue { get; set; }

    /// <summary>Login context under which the restore executes.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public string? ExecuteAs { get; set; }

    /// <summary>SQL Server credential for Azure blob storage or S3-compatible storage.</summary>
    [Parameter]
    [Alias("AzureCredential", "S3Credential")]
    public string? StorageCredential { get; set; }

    /// <summary>Substitutes the original database name with the new name in physical file names.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter ReplaceDbNameInFile { get; set; }

    /// <summary>Suffix applied to all restored files (log and data).</summary>
    [Parameter(ParameterSetName = "Restore")]
    public string? DestinationFileSuffix { get; set; }

    /// <summary>Brings databases in RESTORING state online (RESTORE WITH RECOVERY).</summary>
    [Parameter(ParameterSetName = "Recovery")]
    public SwitchParameter Recover { get; set; }

    /// <summary>Preserves Change Data Capture configuration and data.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter KeepCDC { get; set; }

    /// <summary>Ends all conversations in the database with an error when restoring.</summary>
    [Parameter(ParameterSetName = "Restore")]
    public SwitchParameter ErrorBrokerConversations { get; set; }

    /// <summary>Global variable name to hold the Get-DbaBackupInformation output.</summary>
    [Parameter]
    public string? GetBackupInformation { get; set; }

    /// <summary>Exit after returning GetBackupInformation.</summary>
    [Parameter]
    public SwitchParameter StopAfterGetBackupInformation { get; set; }

    /// <summary>Global variable name to hold the Select-DbaBackupInformation output.</summary>
    [Parameter]
    public string? SelectBackupInformation { get; set; }

    /// <summary>Exit after returning SelectBackupInformation.</summary>
    [Parameter]
    public SwitchParameter StopAfterSelectBackupInformation { get; set; }

    /// <summary>Global variable name to hold the Format-DbaBackupInformation output.</summary>
    [Parameter]
    public string? FormatBackupInformation { get; set; }

    /// <summary>Exit after returning FormatBackupInformation.</summary>
    [Parameter]
    public SwitchParameter StopAfterFormatBackupInformation { get; set; }

    /// <summary>Global variable name to hold the Test-DbaBackupInformation output.</summary>
    [Parameter]
    public string? TestBackupInformation { get; set; }

    /// <summary>Exit after returning TestBackupInformation.</summary>
    [Parameter]
    public SwitchParameter StopAfterTestBackupInformation { get; set; }

    /// <summary>Damaged pages from Get-DbaSuspectPage for page-level restore.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "RestorePage")]
    public object? PageRestore { get; set; }

    /// <summary>Folder for the tail log backup that page restore requires.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "RestorePage")]
    [PsStringCast]
    public string? PageRestoreTailFolder { get; set; }

    /// <summary>Stop before StopMark or StopAtLsn instead of at it.</summary>
    [Parameter]
    public SwitchParameter StopBefore { get; set; }

    /// <summary>Marked point in the transaction log to stop the restore at.</summary>
    [Parameter]
    public string? StopMark { get; set; }

    /// <summary>Stop at the first StopMark after this datetime.</summary>
    [Parameter]
    [PsDateTimeCast]
    public DateTime StopAfterDate { get; set; } = new DateTime(1971, 1, 1);

    /// <summary>LSN at which to stop the restore.</summary>
    [Parameter]
    public string? StopAtLsn { get; set; }

    /// <summary>Maximum minutes to wait for restore operations (0 = unlimited).</summary>
    [Parameter]
    public int StatementTimeout { get; set; }

    /// <summary>Enables backup checksum verification during the restore.</summary>
    [Parameter(ParameterSetName = "Restore")]
    [Parameter(ParameterSetName = "RestorePage")]
    public SwitchParameter Checksum { get; set; }

    /// <summary>Restarts an interrupted restore sequence.</summary>
    [Parameter(ParameterSetName = "Restore")]
    [Parameter(ParameterSetName = "RestorePage")]
    public SwitchParameter Restart { get; set; }

    private Server? _restoreInstance;
    private bool _useDestinationDefaultDirectories;
    private bool _withReplace;
    private bool _pipeDatabaseName;
    private object? _continuePoints;
    private object? _lastRestoreType;
    private object[]? _databaseName;
    private readonly List<object?> _backupHistory = new();
    private bool _skipEnd;
    private string? _recoveryDatabaseLeak;
}
