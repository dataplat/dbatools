#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Executes database restores from processed BackupHistory objects — the final execution
/// step in the dbatools restore pipeline. Port of public/Invoke-DbaAdvancedRestore.ps1;
/// surface pinned by migration/baselines/Invoke-DbaAdvancedRestore.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaAdvancedRestore", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(PSObject), typeof(string))]
public sealed partial class InvokeDbaAdvancedRestoreCommand : DbaBaseCmdlet
{
    /// <summary>Processed BackupHistory objects from the dbatools restore pipeline.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public object[] BackupHistory { get; set; } = null!;

    /// <summary>The SqlInstance to which the backups should be restored.</summary>
    [Parameter(Position = 1)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 2)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Generates T-SQL RESTORE scripts without executing them.</summary>
    [Parameter]
    public SwitchParameter OutputScriptOnly { get; set; }

    /// <summary>Performs RESTORE VERIFYONLY without actually restoring.</summary>
    [Parameter]
    public SwitchParameter VerifyOnly { get; set; }

    /// <summary>The exact point-in-time for log restore operations.</summary>
    [Parameter(Position = 3)]
    [PsDateTimeCast]
    public DateTime RestoreTime { get; set; } = DateTime.Now.AddDays(2);

    /// <summary>Directory where SQL Server creates standby files (puts the database in standby mode).</summary>
    [Parameter(Position = 4)]
    public string? StandbyDirectory { get; set; }

    /// <summary>Leaves the database in RESTORING state for additional log restores.</summary>
    [Parameter]
    public SwitchParameter NoRecovery { get; set; }

    /// <summary>Maximum data transfer unit between SQL Server and backup devices.</summary>
    [Parameter(Position = 5)]
    public int MaxTransferSize { get; set; }

    /// <summary>Physical block size for backup device I/O.</summary>
    [Parameter(Position = 6)]
    public int BlockSize { get; set; }

    /// <summary>Number of I/O buffers used during the restore.</summary>
    [Parameter(Position = 7)]
    public int BufferCount { get; set; }

    /// <summary>Continues a previously started restore sequence; enables WithReplace.</summary>
    [Parameter]
    public SwitchParameter Continue { get; set; }

    /// <summary>SQL Server credential for Azure blob storage or S3-compatible object storage.</summary>
    [Parameter(Position = 8)]
    [Alias("AzureCredential", "S3Credential")]
    public string? StorageCredential { get; set; }

    /// <summary>Allows overwriting an existing database with the same name.</summary>
    [Parameter]
    public SwitchParameter WithReplace { get; set; }

    /// <summary>Preserves replication settings during the restore.</summary>
    [Parameter]
    public SwitchParameter KeepReplication { get; set; }

    /// <summary>Preserves Change Data Capture configuration during the restore.</summary>
    [Parameter]
    public SwitchParameter KeepCDC { get; set; }

    /// <summary>Ends all conversations in the database with an error (ERROR_BROKER_CONVERSATIONS).</summary>
    [Parameter]
    public SwitchParameter ErrorBrokerConversations { get; set; }

    /// <summary>Page objects from Get-DbaSuspectPage for page-level restore.</summary>
    [Parameter(Position = 9)]
    public object[]? PageRestore { get; set; }

    /// <summary>SQL Server login to impersonate during the restore.</summary>
    [Parameter(Position = 10)]
    public string? ExecuteAs { get; set; }

    /// <summary>Stop before the StopMark/StopAtLsn rather than after it.</summary>
    [Parameter]
    public SwitchParameter StopBefore { get; set; }

    /// <summary>Named transaction mark where the restore should stop.</summary>
    [Parameter(Position = 11)]
    public string? StopMark { get; set; }

    /// <summary>Only StopMark occurrences after this date are considered.</summary>
    [Parameter(Position = 12)]
    [PsDateTimeCast]
    public DateTime StopAfterDate { get; set; }

    /// <summary>LSN at which to stop the restore (numeric or colon-delimited form).</summary>
    [Parameter(Position = 13)]
    public string? StopAtLsn { get; set; }

    /// <summary>Enables backup checksum verification during the restore.</summary>
    [Parameter]
    public SwitchParameter Checksum { get; set; }

    /// <summary>Restarts an interrupted restore sequence.</summary>
    [Parameter]
    public SwitchParameter Restart { get; set; }

    private Server? _server;
    private bool _noRecoveryEffective;
    private string? _pages;
    private readonly List<object?> _internalHistory = new();

    protected override void BeginProcessing()
    {
        StandbyDirectory = RestoreUtility.PsString(StandbyDirectory);
        ExecuteAs = RestoreUtility.PsString(ExecuteAs);
        StopMark = RestoreUtility.PsString(StopMark);
        StopAtLsn = RestoreUtility.PsString(StopAtLsn);
        StorageCredential = RestoreUtility.PsString(StorageCredential);
        _noRecoveryEffective = NoRecovery.ToBool();

        try
        {
            SmoConnectionRequest request = new()
            {
                Instance = SqlInstance,
                SqlCredential = SqlCredential
            };
            _server = ConnectionService.GetServer(request);
            SetActiveConnection(_server.ConnectionContext);
        }
        catch (Exception ex)
        {
            ErrorRecord record = new(ex, "dbatools_Invoke-DbaAdvancedRestore", ErrorCategory.ConnectionError, SqlInstance);
            StopFunction("Failure", target: SqlInstance, errorRecord: record, category: ErrorCategory.ConnectionError);
            return;
        }
        if (KeepCDC.ToBool() && (_noRecoveryEffective || StandbyDirectory != ""))
        {
            StopFunction("KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work", category: ErrorCategory.InvalidArgument);
            return;
        }
        if (ErrorBrokerConversations.ToBool() && (_noRecoveryEffective || StandbyDirectory != ""))
        {
            StopFunction("ErrorBrokerConversations cannot be specified with Norecovery or Standby as it needs recovery to work", category: ErrorCategory.InvalidArgument);
            return;
        }
        if (!string.IsNullOrWhiteSpace(StopAtLsn))
        {
            string stopAtLsnValue = StopAtLsn!.Trim();
            if (stopAtLsnValue.StartsWith("lsn:", StringComparison.OrdinalIgnoreCase))
            {
                stopAtLsnValue = stopAtLsnValue.Substring(4);
            }
            if (stopAtLsnValue.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
            {
                stopAtLsnValue = stopAtLsnValue.Substring(2);
            }
            if (!System.Text.RegularExpressions.Regex.IsMatch(stopAtLsnValue, "^[0-9]+$"))
            {
                const string message = "StopAtLsn must be a numeric restore LSN or a colon-delimited value such as 00000030:00000f28:0001.";
                LsnConversion? convertedLsn;
                try
                {
                    convertedLsn = RestoreUtility.ConvertDbaLsn(this, stopAtLsnValue, enableException: true);
                }
                catch (InnerCommandException ex)
                {
                    StopFunction(message, errorRecord: ex.FirstRecord, category: ErrorCategory.InvalidArgument);
                    return;
                }
                if (convertedLsn is null || string.IsNullOrWhiteSpace(convertedLsn.Numeric))
                {
                    StopFunction(message, category: ErrorCategory.InvalidArgument);
                    return;
                }
                stopAtLsnValue = convertedLsn.Numeric!;
            }
            StopAtLsn = stopAtLsnValue;
        }

        if (PageRestore is not null)
        {
            WriteMessage(MessageLevel.Verbose, "Doing Page Recovery");
            List<string> tmpPages = new();
            foreach (object page in PageRestore)
            {
                tmpPages.Add($"{RestoreUtility.PsStringify(PsProperty.Get(page, "FileId"))}:{RestoreUtility.PsStringify(PsProperty.Get(page, "PageID"))}");
            }
            _noRecoveryEffective = true;
            _pages = string.Join(",", tmpPages);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (object bh in BackupHistory)
        {
            _internalHistory.Add(bh);
        }
    }
}
