#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Gets databases from one or more SQL Server instances, with rich filtering. Port of
/// public/Get-DbaDatabase.ps1; the workflow remains a module-scoped
/// PowerShell compatibility hop. READ-ONLY (no SupportsShouldProcess).
///
/// BEGIN+PROCESS. -SqlInstance is Mandatory ValueFromPipeline, so process fires per piped instance.
///
/// NO CROSS-RECORD VALUE CARRY, and NO begin -> process value carry - established by triage, not
/// assumed. begin (:244-250) holds only one guard. The three Find-ConditionalCarry candidates were
/// all REFUTED before coding:
///   $pattern - the "foreach ($pattern ...)" loop variable INSIDE the $matchesPattern scriptblock
///     (:357-366); the reads at :370/:393/:403 are the PARAMETER $Pattern (capital P). A detector
///     case-insensitivity false positive, not a carry.
///   $NoLogBackupSince - defaulted at :427-428 only when empty, to "New-Object DateTime" (DateTime
///     .MinValue) + 1ms - a DETERMINISTIC value, so re-computing it per record is idempotent and
///     equals what a carry would hold. No carry.
///   $hasCopyOnly - assigned at :421 inside "if ($NoFullBackup -or $NoFullBackupSince)" (:413) and
///     read at :506 inside the SAME "if ($NoFullBackup -or $NoFullBackupSince)"; both are non-pipeline
///     parameters, constant across records, so it is always-assigned-before-read or never-read - the
///     $deploymentReport constant-gate pattern. No carry.
///   $server (raised in review; REFUTED) - assigned in the connection try (:256), whose catch
///     (:258) is Stop-Function -Continue. The "foreach ($instance in $SqlInstance)" loop opens at
///     :254 and CLOSES at :537, wrapping the whole body, so every $server read (:298/:327/.../:355
///     Invoke-QueryRawDatabases) is a STATEMENT AFTER that catch, inside the loop. The catch's
///     -Continue issues "continue", which is dynamically scoped and unwinds that foreach, so on a
///     connection failure those reads are UNREACHABLE - no stale cross-record $server is observed.
///     The settled continue-in-catch class (read AFTER a -Continue catch is unreachable on failure);
///     measured in a dedicated probe run.
///
/// UNBOUND [datetime] SEMANTICS. The source's -NoFullBackupSince and
/// -NoLogBackupSince are $null when the caller omits them; a non-nullable C# DateTime property is
/// MinValue instead, which is TRUTHY in PowerShell - it would wrongly enable the :413 backup filter
/// and defeat the :426 "if (!$NoLogBackupSince)" default init. So the property stays DateTime (the
/// surface is unchanged), but ProcessRecord passes $null into the hop when the parameter was NOT
/// bound (the two inner hop params are received UNTYPED so $null survives), and the real value -
/// including an explicitly-passed MinValue - when it was.
///
/// The query helper functions Invoke-QueryDBlastUsed (:297), Invoke-QueryRawDatabases (:325),
/// Invoke-QueryDatabaseSizes (:467) and the $matchesPattern scriptblock (:357) are all defined IN
/// PROCESS, so they ride verbatim in the process hop - no begin -> process recreation needed.
///
/// INTERRUPT CARRIES ON BOTH AXES, bridged conservatively. begin's only guard (:246, ExcludeUser +
/// ExcludeSystem) is Stop-Function -Continue and so does NOT set the module latch (a latent source
/// quirk - the guard warns but does not actually halt). The LIVE latch source is process: the
/// non-Continue "Stop-Function -Message 'Failure' -ErrorRecord $_" at :351 (a catch with NO following
/// return, inside Invoke-QueryRawDatabases called from the instance loop) sets the latch mid-record,
/// and process opens with "if (Test-FunctionInterrupt) { return }" at :252, so a Failure on one
/// record silences later records. The begin hop and each process hop read the latch at
/// Get-Variable -Scope 0 and carry it; a persisted C# _interrupted field bridges it across records.
/// Mechanism measured in a dedicated probe run.
///
/// ONE Test-Bound ("Encrypted" at :321, "$Encrypt = switch (Test-Bound -Parameter 'Encrypted')")
/// becomes a carried boundness flag $__boundEncrypted. The nine switches (ExcludeUser, ExcludeSystem,
/// Encrypted, NoFullBackup, NoLogBackup, IncludeLastUsed, OnlyAccessible) and inherited
/// EnableException cross as SwitchParameter OBJECTS received untyped. -ExcludeUser and -ExcludeSystem
/// carry their aliases. In-hop Stop-Function/Write-Message calls carry -FunctionName. Positions 0-10
/// are made explicit and confirmed against the exported baseline; SqlInstance is
/// Mandatory VFP at 0. Streaming: emits per database. Surface pinned by the captured surface baseline.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDatabase", DefaultParameterSetName = "Default")]
public sealed partial class GetDbaDatabaseCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Filter to these databases.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Exclude these databases.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Regex patterns to match database names against.</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Pattern { get; set; }

    /// <summary>Exclude user databases (system only).</summary>
    [Parameter]
    [Alias("SystemDbOnly", "NoUserDb", "ExcludeAllUserDb")]
    public SwitchParameter ExcludeUser { get; set; }

    /// <summary>Exclude system databases (user only).</summary>
    [Parameter]
    [Alias("UserDbOnly", "NoSystemDb", "ExcludeAllSystemDb")]
    public SwitchParameter ExcludeSystem { get; set; }

    /// <summary>Filter to databases owned by these logins.</summary>
    [Parameter(Position = 5)]
    [PsStringArrayCast]
    public string[]? Owner { get; set; }

    /// <summary>Filter to encrypted databases (bound-sensitive).</summary>
    [Parameter]
    public SwitchParameter Encrypted { get; set; }

    /// <summary>Filter to these database states.</summary>
    [Parameter(Position = 6)]
    [ValidateSet("EmergencyMode", "Normal", "Offline", "Recovering", "RecoveryPending", "Restoring", "Standby", "Suspect")]
    [PsStringArrayCast]
    public string[] Status { get; set; } = new[] { "EmergencyMode", "Normal", "Offline", "Recovering", "RecoveryPending", "Restoring", "Standby", "Suspect" };

    /// <summary>Filter by read-only or read-write access.</summary>
    [Parameter(Position = 7)]
    [ValidateSet("ReadOnly", "ReadWrite")]
    [PsStringCast]
    public string? Access { get; set; }

    /// <summary>Filter to these recovery models.</summary>
    [Parameter(Position = 8)]
    [ValidateSet("Full", "Simple", "BulkLogged")]
    [PsStringArrayCast]
    public string[] RecoveryModel { get; set; } = new[] { "Full", "Simple", "BulkLogged" };

    /// <summary>Filter to databases with no full backup.</summary>
    [Parameter]
    public SwitchParameter NoFullBackup { get; set; }

    /// <summary>Filter to databases with no full backup since this time.</summary>
    [Parameter(Position = 9)]
    public DateTime NoFullBackupSince { get; set; }

    /// <summary>Filter to databases with no log backup.</summary>
    [Parameter]
    public SwitchParameter NoLogBackup { get; set; }

    /// <summary>Filter to databases with no log backup since this time.</summary>
    [Parameter(Position = 10)]
    public DateTime NoLogBackupSince { get; set; }

    /// <summary>Include the last-used timestamp (extra query).</summary>
    [Parameter]
    public SwitchParameter IncludeLastUsed { get; set; }

    /// <summary>Only return accessible databases.</summary>
    [Parameter]
    public SwitchParameter OnlyAccessible { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // a Failure on one record silences later records.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        List<string> guardWarnings = new List<string>();
        try
        {
            foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
                ExcludeUser, ExcludeSystem, EnableException,
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"),
                guardWarnings))
            {
                if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__getDbaDatabaseBegin"))
                {
                    if (sentinel["__getDbaDatabaseBegin"] is Hashtable state)
                        _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
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
        }
        finally
        {
            bool boundStop = MyInvocation.BoundParameters.TryGetValue("WarningAction", out object? warningAction) &&
                warningAction is ActionPreference boundWarningPreference &&
                boundWarningPreference == ActionPreference.Stop;
            bool ambientStop = SessionState.PSVariable.GetValue("WarningPreference") is ActionPreference effectiveWarningPreference &&
                effectiveWarningPreference == ActionPreference.Stop;
            foreach (string guardWarning in guardWarnings)
            {
                if (boundStop || ambientStop)
                {
                    Host.UI.WriteWarningLine(guardWarning);
                    if (MyInvocation.BoundParameters.TryGetValue("WarningVariable", out object? warningVariable) &&
                        warningVariable is string warningVariableName)
                    {
                        warningVariableName = warningVariableName.TrimStart('+');
                        if (SessionState.PSVariable.GetValue(warningVariableName) is IList warningRecords)
                            warningRecords.Add(new WarningRecord(guardWarning));
                    }
                }
                else
                {
                    WriteWarning(guardWarning);
                }
            }
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _interrupted)
            return;

        // Streaming, not buffered: databases are emitted per instance as found, so a
        // buffered hop would discard results already produced when a later instance failed.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__getDbaDatabaseProcess"))
            {
                if (sentinel["__getDbaDatabaseProcess"] is Hashtable state)
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Pattern, ExcludeUser, ExcludeSystem,
            Owner, Encrypted, Status, Access, RecoveryModel, NoFullBackup,
            // The source's [datetime] params are $null when UNBOUND; a non-nullable DateTime property
            // defaults to MinValue, which is TRUTHY in PowerShell and would wrongly enable
            // the :413 backup filter and defeat the :426 "if (!$NoLogBackupSince)" default. Pass null
            // when the caller did not bind them (the inner hop params are untyped so $null survives),
            // and the actual value - including an explicit MinValue - when they did.
            MyInvocation.BoundParameters.ContainsKey("NoFullBackupSince") ? (object)NoFullBackupSince : null,
            NoLogBackup,
            MyInvocation.BoundParameters.ContainsKey("NoLogBackupSince") ? (object)NoLogBackupSince : null,
            IncludeLastUsed, OnlyAccessible, EnableException,
            MyInvocation.BoundParameters.ContainsKey("Encrypted"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
}
