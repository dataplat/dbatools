#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Restores the last backups to a test server and DBCC-checks them. Port of
/// public/Test-DbaLastBackup.ps1 (W3-110, MAX row). WHOLE-RECORD verbatim hop
/// (process-only source, 961 lines; body mechanically extracted, reverse-diff-proven).
/// CLASSIFICATION TABLE (InputObject is the VFP - SMO Database[]; promoted question
/// answered per mutated param/local): (1) $CopyPath is mutated in the per-db loop (the
/// destination BackupDirectory backfill) and READ BEFORE REFRESH on later records -
/// THE sentinel carry (__w3110State); (2) the two loop-less `Stop-Function -Continue`
/// sites in the Path branch make the continue ESCAPE the command - the W3-102
/// CONTINUE RELAY rides this row (script guard + marker + C#-side re-issue); (3) the
/// loop-less latching Stop-Function+return sites need NO latch carry: this source has
/// no Test-FunctionInterrupt anywhere, the latch variable is WRITE-ONLY and each
/// record re-runs fully in the function world too; (4) $Destination /
/// $DestinationSqlCredential in-loop mutations are REFRESHED BEFORE EVERY READ per
/// iteration (the unbound-Destination branch re-assigns per db) - no carry; (5) $diff
/// 's branch-assigned/unconditional-read shape is null-consistent in both worlds
/// under every flag combination (never assigned anywhere when IgnoreDiffBackup is
/// bound) - no carry; (6) $InputObject += rides the engine's per-record pipeline
/// rebind; $workItems and all phase locals are per-record. Gates route to the REAL
/// cmdlet ($Pscmdlet/$PSCmdlet x3 -> $__realCmdlet; no Force convention).
/// Start-DbccCheck owns its own SupportsShouldProcess (WhatIf flows to it by
/// preference inheritance identically in both worlds). Checklist greps clean on
/// Get-SqlDefaultPaths/Join-AdminUnc/Get-ErrorMessage/Start-DbccCheck (no callstack,
/// no scope-walk defaults). The 12 Test-Bound sites ride as carried flags (W3-093).
/// Bind-time casts per laws: [PsStringCast] on the scalar strings, [PsIntCast] on the
/// scalar ints. NO WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Test-DbaLastBackup.json (no sets, 30 params, implicit
/// positions in declaration order, InputObject VFP).
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaLastBackup", SupportsShouldProcess = true)]
public sealed partial class TestDbaLastBackupCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance(s) whose databases should be tested.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Credential for the source instance(s).</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Database filter.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Database exclusion filter.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Destination test server.</summary>
    [Parameter(Position = 4)]
    public DbaInstanceParameter? Destination { get; set; }

    /// <summary>Credential for the destination server.</summary>
    [Parameter(Position = 5)]
    public object? DestinationSqlCredential { get; set; }

    /// <summary>Data file directory on the destination.</summary>
    [Parameter(Position = 6)]
    [PsStringCast]
    public string? DataDirectory { get; set; }

    /// <summary>Log file directory on the destination.</summary>
    [Parameter(Position = 7)]
    [PsStringCast]
    public string? LogDirectory { get; set; }

    /// <summary>FileStream directory on the destination.</summary>
    [Parameter(Position = 8)]
    [PsStringCast]
    public string? FileStreamDirectory { get; set; }

    /// <summary>Restored database name prefix.</summary>
    [Parameter(Position = 9)]
    [PsStringCast]
    public string Prefix { get; set; } = "dbatools-testrestore-";

    /// <summary>RESTORE VERIFYONLY instead of a full restore.</summary>
    [Parameter]
    public SwitchParameter VerifyOnly { get; set; }

    /// <summary>Skips DBCC CHECKDB.</summary>
    [Parameter]
    public SwitchParameter NoCheck { get; set; }

    /// <summary>Keeps the restored database.</summary>
    [Parameter]
    public SwitchParameter NoDrop { get; set; }

    /// <summary>Copies backup files to the destination before restoring.</summary>
    [Parameter]
    public SwitchParameter CopyFile { get; set; }

    /// <summary>Where copied backup files land.</summary>
    [Parameter(Position = 10)]
    [PsStringCast]
    public string? CopyPath { get; set; }

    /// <summary>Maximum backup size (MB) to test.</summary>
    [Parameter(Position = 11)]
    [PsIntCast]
    public int MaxSize { get; set; }

    /// <summary>Backup device type filter.</summary>
    [Parameter(Position = 12)]
    public string[]? DeviceType { get; set; }

    /// <summary>Includes copy-only backups.</summary>
    [Parameter]
    public SwitchParameter IncludeCopyOnly { get; set; }

    /// <summary>Ignores log backups (restore up to full/diff only).</summary>
    [Parameter]
    public SwitchParameter IgnoreLogBackup { get; set; }

    /// <summary>Cloud storage credential name.</summary>
    [Parameter(Position = 13)]
    [Alias("AzureCredential", "S3Credential")]
    [PsStringCast]
    public string? StorageCredential { get; set; }

    /// <summary>Database objects from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 14)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>Restore MAXTRANSFERSIZE.</summary>
    [Parameter(Position = 15)]
    [PsIntCast]
    public int MaxTransferSize { get; set; }

    /// <summary>Restore BUFFERCOUNT.</summary>
    [Parameter(Position = 16)]
    [PsIntCast]
    public int BufferCount { get; set; }

    /// <summary>Ignores diff backups during restore.</summary>
    [Parameter]
    public SwitchParameter IgnoreDiffBackup { get; set; }

    /// <summary>DBCC MAXDOP.</summary>
    [Parameter(Position = 17)]
    [PsIntCast]
    public int MaxDop { get; set; }

    /// <summary>Restores files to their source folder structure.</summary>
    [Parameter]
    public SwitchParameter ReuseSourceFolderStructure { get; set; }

    /// <summary>Adds CHECKSUM to the restore.</summary>
    [Parameter]
    public SwitchParameter Checksum { get; set; }

    /// <summary>Seconds to wait between databases.</summary>
    [Parameter(Position = 18)]
    [PsIntCast]
    public int Wait { get; set; }

    /// <summary>Backup folder path(s) to test instead of live history.</summary>
    [Parameter(Position = 19)]
    public string[]? Path { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // cross-record carry: the in-loop $CopyPath backfill (see class doc).
    private Hashtable _state = new Hashtable();

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // CONTINUE RELAY, C# half (the W3-102 mechanism): reference-identity marker.
        object continueMarker = new object();
        bool continueEscaped = false;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Destination,
            DestinationSqlCredential, DataDirectory, LogDirectory, FileStreamDirectory,
            Prefix, VerifyOnly.ToBool(), NoCheck.ToBool(), NoDrop.ToBool(),
            CopyFile.ToBool(), CopyPath, MaxSize, DeviceType, IncludeCopyOnly.ToBool(),
            IgnoreLogBackup.ToBool(), StorageCredential, InputObject, MaxTransferSize,
            BufferCount, IgnoreDiffBackup.ToBool(), MaxDop,
            ReuseSourceFolderStructure.ToBool(), Checksum.ToBool(), Wait, Path,
            EnableException.ToBool(),
            TestBound(nameof(Database)), TestBound(nameof(ExcludeDatabase)),
            TestBound(nameof(Path)), TestBound(nameof(Destination)),
            TestBound(nameof(StorageCredential)), TestBound(nameof(IgnoreDiffBackup)),
            TestBound(nameof(IgnoreLogBackup)), TestBound(nameof(CopyFile)),
            TestBound(nameof(MaxTransferSize)), TestBound(nameof(BufferCount)),
            TestBound(nameof(FileStreamDirectory)), TestBound(nameof(Checksum)),
            _state, this, continueMarker,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (ReferenceEquals(item?.BaseObject, continueMarker))
            {
                continueEscaped = true;
                continue;
            }
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3110State"))
            {
                _state = sentinel["__w3110State"] as Hashtable ?? _state;
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }

        // The hop completed (output drained, warnings replayed); re-issue the escaped
        // `continue` so it leaves this cmdlet exactly like it leaves the function.
        if (continueEscaped)
        {
            foreach (PSObject? _ in NestedCommand.InvokeScoped(this, ContinueRelayScript))
            {
            }
        }
    }
}
