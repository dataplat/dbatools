#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Backs up one or more databases. Port of public/Backup-DbaDatabase.ps1 (W3-004, the
/// backup Giant). Shape per migration/designed/Backup-DbaDatabase-port-plan.md: a verbatim
/// BEGIN hop (validation + batch build + $PSBoundParameters.Path/.FilePath rewires) plus a
/// verbatim WHOLE-PROCESS-BODY hop per pipeline record. Per-element (per-db) hops are
/// FORBIDDEN here - the db loop carries cross-element state (Path/FileCount/MaxTransferSize/
/// IgnoreFileChecks/Initialize/SkipTapeHeader/NoAppendDbNameInPath/FilePath plus stale
/// isdir/failreason/HeaderInfo/Description), so the __w3004State sentinel round-trips the
/// full stale-able set between hops (P2A counter-case; Rename/W3-081 buffered-batch ruling
/// cited for the SqlInstance path). $PSBoundParameters fidelity rides the prune-prologue
/// (plan item 3; fallback = W3-063 carried flags); ShouldProcess and ExpectingInput route to
/// $__realCmdlet; switches ride RAW (the source calls $IncrementPrefix.ToBool() in-body).
/// SURFACE QUIRK preserved verbatim: the scalar SqlInstance lives in set "Pipe" and is NOT
/// pipeline-bound while InputObject lives in set "NoPipe" and IS - the names are backwards
/// in the source (:322/:337). [OutputType] omitted to match the frozen baseline
/// (outputType: []; architecture section-6 tension recorded, Remove/Rename precedent).
/// Owner-locked micro-refactors (contracts section 2): the master-cert lookup and the dead
/// asymmetric-key lookup are inline SMO instead of cross-satellite command calls.
/// Surface pinned by migration/baselines/Backup-DbaDatabase.json.
/// </summary>
[Cmdlet(VerbsData.Backup, "DbaDatabase", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium, DefaultParameterSetName = "Default")]
public sealed partial class BackupDbaDatabaseCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance (scalar - the source never declared an array).</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Pipe")]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Path(s) to place the backup files in.</summary>
    [Parameter]
    [Alias("BackupDirectory")]
    public string[]? Path { get; set; }

    /// <summary>The name of the backup file.</summary>
    [Parameter]
    [Alias("BackupFileName")]
    public string? FilePath { get; set; }

    /// <summary>Prefix stripe files with their stripe index.</summary>
    [Parameter]
    public SwitchParameter IncrementPrefix { get; set; }

    /// <summary>Replace naming tokens (dbname/instancename/servername/timestamp/backuptype) in paths.</summary>
    [Parameter]
    public SwitchParameter ReplaceInName { get; set; }

    /// <summary>Do not append the database name to the backup path.</summary>
    [Parameter]
    public SwitchParameter NoAppendDbNameInPath { get; set; }

    /// <summary>Perform a copy-only backup.</summary>
    [Parameter]
    public SwitchParameter CopyOnly { get; set; }

    /// <summary>The type of backup to perform.</summary>
    [Parameter]
    [ValidateSet("Full", "Log", "Differential", "Diff", "Database")]
    public string Type { get; set; } = "Database";

    /// <summary>Create the backup folder(s) when missing.</summary>
    [Parameter]
    public SwitchParameter CreateFolder { get; set; }

    /// <summary>Number of stripe files.</summary>
    [Parameter]
    public int FileCount { get; set; } = 0;

    /// <summary>Compress the backup.</summary>
    [Parameter]
    public SwitchParameter CompressBackup { get; set; }

    /// <summary>Calculate a checksum during backup.</summary>
    [Parameter]
    public SwitchParameter Checksum { get; set; }

    /// <summary>Verify the backup after completion.</summary>
    [Parameter]
    public SwitchParameter Verify { get; set; }

    /// <summary>Maximum transfer size in bytes.</summary>
    [Parameter]
    public int MaxTransferSize { get; set; }

    /// <summary>Block size for the backup device.</summary>
    [Parameter]
    public int BlockSize { get; set; }

    /// <summary>Number of IO buffers.</summary>
    [Parameter]
    public int BufferCount { get; set; }

    /// <summary>Cloud storage base URL(s) (Azure blob or S3).</summary>
    [Parameter]
    [Alias("AzureBaseUrl", "S3BaseUrl")]
    public string[]? StorageBaseUrl { get; set; }

    /// <summary>Name of the server credential for cloud storage.</summary>
    [Parameter]
    [Alias("AzureCredential", "S3Credential")]
    public string? StorageCredential { get; set; }

    /// <summary>Cloud storage region (S3).</summary>
    [Parameter]
    [Alias("S3Region")]
    public string? StorageRegion { get; set; }

    /// <summary>Back up with NORECOVERY (tail-log).</summary>
    [Parameter]
    public SwitchParameter NoRecovery { get; set; }

    /// <summary>Build any missing path components.</summary>
    [Parameter]
    public SwitchParameter BuildPath { get; set; }

    /// <summary>WITH FORMAT - also sets Initialize and SkipTapeHeader (source :949-953).</summary>
    [Parameter]
    public SwitchParameter WithFormat { get; set; }

    /// <summary>WITH INIT.</summary>
    [Parameter]
    public SwitchParameter Initialize { get; set; }

    /// <summary>WITH SKIP.</summary>
    [Parameter]
    public SwitchParameter SkipTapeHeader { get; set; }

    /// <summary>Timestamp format for auto-generated file names.</summary>
    [Parameter]
    public string? TimeStampFormat { get; set; }

    /// <summary>Skip path validity checks.</summary>
    [Parameter]
    public SwitchParameter IgnoreFileChecks { get; set; }

    /// <summary>Emit the T-SQL instead of running the backup.</summary>
    [Parameter]
    public SwitchParameter OutputScriptOnly { get; set; }

    /// <summary>Encryption algorithm for backup encryption.</summary>
    [Parameter]
    [ValidateSet("AES128", "AES192", "AES256", "TRIPLEDES")]
    public string? EncryptionAlgorithm { get; set; }

    /// <summary>Certificate (in master) encrypting the backup.</summary>
    [Parameter]
    public string? EncryptionCertificate { get; set; }

    /// <summary>Backup set description (truncated at 255 chars, source :743-745).</summary>
    [Parameter]
    public string? Description { get; set; }

    /// <summary>Piped database objects (the source's backwards set naming rides verbatim).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "NoPipe")]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Cross-hop state: the full stale-able local set (plan item 2) plus the plain
    // Stop-Function latch (Test-FunctionInterrupt cannot cross hops - Rename precedent).
    private Hashtable? _state;
    private bool _hopInterrupted;
    private Hashtable? _realBoundParameters;

    protected override void BeginProcessing()
    {
        // The caller's real bound set is invocation-stable: copied ONCE into a Hashtable. A
        // Hashtable survives the InvokeScoped arg-relay intact (a string[] carrier gets
        // unrolled crossing the splatted hop boundary, which emptied the prune's name list and
        // discarded every Test-Bound); the hop prunes its positional-bound superset against
        // this via ContainsKey.
        _realBoundParameters = new Hashtable(MyInvocation.BoundParameters);

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Path, FilePath,
            IncrementPrefix, ReplaceInName, NoAppendDbNameInPath, CopyOnly, Type,
            CreateFolder, FileCount, CompressBackup, Checksum, Verify, MaxTransferSize,
            BlockSize, BufferCount, StorageBaseUrl, StorageCredential, StorageRegion,
            NoRecovery, BuildPath, WithFormat, Initialize, SkipTapeHeader, TimeStampFormat,
            IgnoreFileChecks, OutputScriptOnly, EncryptionAlgorithm, EncryptionCertificate,
            Description, InputObject, EnableException.ToBool(),
            _realBoundParameters, this,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (ConsumeSentinel(item))
                continue;
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Path, FilePath,
            IncrementPrefix, ReplaceInName, NoAppendDbNameInPath, CopyOnly, Type,
            CreateFolder, FileCount, CompressBackup, Checksum, Verify, MaxTransferSize,
            BlockSize, BufferCount, StorageBaseUrl, StorageCredential, StorageRegion,
            NoRecovery, BuildPath, WithFormat, Initialize, SkipTapeHeader, TimeStampFormat,
            IgnoreFileChecks, OutputScriptOnly, EncryptionAlgorithm, EncryptionCertificate,
            Description, InputObject, EnableException.ToBool(),
            _state, _hopInterrupted, _realBoundParameters, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (ConsumeSentinel(item))
                continue;
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // Source has NO end block - EndProcessing intentionally not overridden (plan item 7).

    /// <summary>Folds a __w3004State sentinel back into cross-record state; true when consumed.</summary>
    private bool ConsumeSentinel(PSObject? item)
    {
        Hashtable? sentinel = item?.BaseObject as Hashtable;
        if (sentinel is null || !sentinel.ContainsKey("__w3004State"))
            return false;
        _state = sentinel["__w3004State"] as Hashtable;
        if (_state is not null && _state["interrupted"] is bool interrupted && interrupted)
            _hopInterrupted = true;
        return true;
    }

    private const string ProcessScript = ProcessScriptHead + "\n" + ProcessScriptMid + "\n" + ProcessScriptTail;
}
