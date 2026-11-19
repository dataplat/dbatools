#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Reduces msdb backup/restore history (server-wide by retention window or per-database
/// completely). Port of public/Remove-DbaDbBackupRestoreHistory.ps1 (W3-075). The begin
/// block computes once-per-invocation state - the KeepDays default (30 when neither
/// KeepDays nor Database is bound) and the $odt cutoff (Get-Date relative) - which rides
/// a BEGIN hop and returns through the __w3075State sentinel into every process hop (the
/// W3-063 begin-state shape). The process body rides one VERBATIM hop per record inside a
/// DOT-SOURCED inner block (W1-108: the KeepDays+Database validation is a
/// `Stop-Function; return` early exit that re-fires per record - no Interrupted latch in
/// the source). Records are otherwise SELF-CONTAINED: piped $InputObject rebinds per
/// record and the += accumulation from the SqlInstance branch is invocation-local.
/// [PsIntCast] on KeepDays (W1-043 class: the function binder converts an explicit null
/// to 0 - which then triggers the begin default exactly like unbound - where the compiled
/// binder would reject null). Two $Pscmdlet.ShouldProcess gates route to the REAL cmdlet
/// (ConfirmImpact HIGH mirrored); the DeleteBackupHistory/DropBackupHistory why-comments
/// ride verbatim. NO WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Remove-DbaDbBackupRestoreHistory.json (implicit positions 0-4,
/// no sets, InputObject Database[] pos4 VFP).
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbBackupRestoreHistory", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaDbBackupRestoreHistoryCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>History retention window in days (server-wide mode); defaults to 30.</summary>
    [Parameter(Position = 2)]
    [PsIntCast]
    public int KeepDays { get; set; }

    /// <summary>Database(s) whose complete history should be removed.</summary>
    [Parameter(Position = 3)]
    public string[]? Database { get; set; }

    /// <summary>SMO Database object(s), typically from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin-scope $KeepDays (defaulted) and $odt, computed once and read by every record.
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            KeepDays, Database, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3075State"))
            {
                _state = sentinel["__w3075State"] as Hashtable;
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

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            // Process hops re-emit the sentinel to carry the cross-record $servername
            // leak (B batch [P3]: assigned inside the per-db try, read by the catch -
            // record N's value must be visible to record N+1 like the source fn scope).
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3075State"))
            {
                _state = sentinel["__w3075State"] as Hashtable;
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
            SqlInstance, SqlCredential, Database, InputObject, EnableException.ToBool(),
            _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM; the (possibly defaulted) $KeepDays and $odt return
    // through the sentinel for the process hops.
    private const string BeginScript = """
param($KeepDays, $Database, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([int]$KeepDays, [string[]]$Database, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $KeepDays -and -not $Database) {
        $KeepDays = 30
    }
    $odt = (Get-Date).AddDays(-$KeepDays)
    @{ __w3075State = @{ KeepDays = $KeepDays; odt = $odt } }
} $KeepDays $Database $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM per record inside a dot-sourced block (the
    // KeepDays+Database validation early return re-fires per record). Substitutions only:
    // $KeepDays/$odt restore from the begin-computed sentinel, $Pscmdlet -> $__realCmdlet,
    // and explicit -FunctionName Remove-DbaDbBackupRestoreHistory on Stop-Function
    // (W1-090). The DeleteBackupHistory/DropBackupHistory why-comments ride as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $InputObject, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin-computed once-per-invocation state + cross-record leaked local restore
    $KeepDays = $__state.KeepDays
    $odt = $__state.odt
    $servername = $__state.servername

    . {
        if ($KeepDays -and $Database) {
            Stop-Function -Message "KeepDays cannot be used with Database. When Database is specified, all backup/restore history for that database is deleted." -FunctionName Remove-DbaDbBackupRestoreHistory
            return
        }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Remove-DbaDbBackupRestoreHistory
            }
            if (-not $Database) {
                try {
                    if ($__realCmdlet.ShouldProcess($server, "Remove backup/restore history before $($odt) for all databases")) {
                        # While this method is named DeleteBackupHistory, it also removes restore history
                        $server.DeleteBackupHistory($odt)
                        $server.Refresh()
                    }
                } catch {
                    Stop-Function -Message "Could not remove backup/restore history on $server" -Continue -FunctionName Remove-DbaDbBackupRestoreHistory
                }
            } else {
                $InputObject += $server.Databases | Where-Object { $_.Name -in $Database }
            }
        }

        foreach ($db in $InputObject) {
            try {
                $servername = $db.Parent.Name
                if ($__realCmdlet.ShouldProcess("$db on $servername", "Remove complete backup/restore history")) {
                    # While this method is named DropBackupHistory, it also removes restore history
                    $db.DropBackupHistory()
                    $db.Refresh()
                }
            } catch {
                Stop-Function -Message "Could not remove backup/restore history for database $db on $servername" -Continue -FunctionName Remove-DbaDbBackupRestoreHistory
            }
        }
    }

    @{ __w3075State = @{ KeepDays = $KeepDays; odt = $odt; servername = $servername } }
} $SqlInstance $SqlCredential $Database $InputObject $EnableException $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
