#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets up database mirroring: validates the pair, seeds the mirror from backups,
/// creates and starts the mirroring endpoints, grants CONNECT to the service accounts
/// and wires the partners (and witness).
/// Port of public/Invoke-DbaDbMirroring.ps1; surface pinned by
/// migration/baselines/Invoke-DbaDbMirroring.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbMirroring", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed partial class InvokeDbaDbMirroringCommand : DbaBaseCmdlet
{
    /// <summary>The primary SQL Server instance.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? Primary { get; set; }

    /// <summary>Login to the primary instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? PrimarySqlCredential { get; set; }

    /// <summary>The mirror SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[]? Mirror { get; set; }

    /// <summary>Login to the mirror instances using alternative credentials.</summary>
    [Parameter(Position = 3)]
    public PSCredential? MirrorSqlCredential { get; set; }

    /// <summary>The witness SQL Server instance.</summary>
    [Parameter(Position = 4)]
    public DbaInstanceParameter? Witness { get; set; }

    /// <summary>Login to the witness instance using alternative credentials.</summary>
    [Parameter(Position = 5)]
    public PSCredential? WitnessSqlCredential { get; set; }

    /// <summary>The databases to mirror.</summary>
    [Parameter(Position = 6)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Endpoint encryption requirement.</summary>
    [Parameter(Position = 7)]
    [ValidateSet("Disabled", "Required", "Supported")]
    [PsStringCast]
    public string EndpointEncryption { get; set; } = "Required";

    /// <summary>Endpoint encryption algorithm.</summary>
    [Parameter(Position = 8)]
    [ValidateSet("Aes", "AesRC4", "None", "RC4", "RC4Aes")]
    [PsStringCast]
    public string EncryptionAlgorithm { get; set; } = "Aes";

    /// <summary>Network share both instances can read, used to stage the seeding backups.</summary>
    [Parameter(Position = 9)]
    public string? SharedPath { get; set; }

    /// <summary>Database objects piped from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 10)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>Seeds the mirror from the existing backup chain instead of taking new backups.</summary>
    [Parameter]
    public SwitchParameter UseLastBackup { get; set; }

    /// <summary>Drops and recreates an existing mirroring configuration, suppressing prompts.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Invoke-DbaDbMirroring");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop per the W3-005/W4-011 convention with a NESTED foreach (primary
        // database x mirror instance). The begin block's Force -> ConfirmPreference
        // suppression and its $params construction ride at the hop top; all four
        // ShouldProcess gates run on the INNER scriptblock's own $Pscmdlet (hop-scope-local,
        // so the Force suppression applies).
        //
        // THREE kinds of state cross the record boundary in the source and therefore ride
        // the __w4041State sentinel:
        //   1. ShouldProcess Yes/No-to-All - the W3-082 prompt-state transplant, because a
        //      fresh inner $Pscmdlet per record would lose the answer the source's single
        //      function-scope $Pscmdlet keeps.
        //   2. $Primary - the source REASSIGNS this parameter ($Primary = $source =
        //      $primarydb.Parent) and parameters are function-scope, so a later piped record
        //      observes the earlier record's value; it is read by two gates and the output.
        //   3. $UseLastBackup - likewise reassigned to $true after the seeding backups are
        //      taken, which changes how the NEXT record seeds.
        // Probe-confirmed class: migration/tools/Probe-W4042ParamAccumulation.ps1.
        //
        // The source's begin captures $PSBoundParameters into $params and strips four keys
        // before splatting it at Invoke-DbMirrorValidation. The hop's own $PSBoundParameters
        // would see hop plumbing, so a clone of the REAL bound parameters is carried as
        // $__allParams (W3-090 Set-DbaDbState precedent). The clone is built with an
        // ORDINAL-IGNORE-CASE comparer: PowerShell binds parameters case-insensitively and
        // the source removes the key spelled 'Whatif', which a default (case-sensitive)
        // Hashtable would leave behind for the validation splat to reject.
        // Probe: migration/tools/Probe-W4041HashtableCaseComparer.ps1.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4041State"))
            {
                _state = sentinel["__w4041State"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            Primary, PrimarySqlCredential, Mirror, MirrorSqlCredential, Witness,
            WitnessSqlCredential, Database, EndpointEncryption, EncryptionAlgorithm,
            SharedPath, InputObject, UseLastBackup.ToBool(), Force.ToBool(),
            EnableException.ToBool(),
            new Hashtable((IDictionary)MyInvocation.BoundParameters, StringComparer.OrdinalIgnoreCase),
            TestBound(nameof(Primary)), TestBound(nameof(Database)),
            TestBound(nameof(SharedPath)), TestBound(nameof(UseLastBackup)), _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string ProcessScript = ProcessScriptHead + "\r\n" + ProcessScriptTail;
}