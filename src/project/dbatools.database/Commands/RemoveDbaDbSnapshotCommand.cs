#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Drops database snapshots. Port of public/Remove-DbaDbSnapshot.ps1 (W2-168); the workflow remains
/// a module-scoped PowerShell compatibility hop.
///
/// A begin/process port whose begin block does TWO things, and they are carried differently:
///
/// 1. $defaultProps (the Select-DefaultView property list) is computed in begin and read three times
///    in process, so it rides a begin STATE SENTINEL per the NewDbaAgentJob exemplar. Note this is
///    the one carry shape my DEF-012 detector DOES see - it flagged $defaultProps as BEGIN-CARRY,
///    unlike the W2-172/W2-170 accumulators, which the process-block-only tool was blind to.
///
/// 2. `if ($Force) { $ConfirmPreference = 'none' }` - the CONFIRMPREFERENCE-FROM-FORCE class. This
///    line cannot stay in a begin hop: the ShouldProcess gate lives in PROCESS, and begin and process
///    are separate scoped invocations, so an assignment made in the begin hop's scope is gone by the
///    time the gate runs. It is RELOCATED verbatim to the top of the process hop, which is where every
///    shipped port of this class already has it (CopyDbaAgentAlert, CopyDbaAgentJob,
///    CopyDbaAgentJobCategory, CopyDbaAgentOperator/Proxy/Schedule/Server, NewDbaAgentAlertCategory and
///    others all keep the line verbatim in the SAME hop as their $__realCmdlet.ShouldProcess calls).
///    Same relocation reasoning as the W2-181 helper: an effect must live in the scope that consumes it.
///
///    OPEN AND MEASURED SEPARATELY, not assumed: whether assigning $ConfirmPreference inside the hop
///    scope actually suppresses the prompt on $__realCmdlet.ShouldProcess, given the real cmdlet reads
///    its own runtime preference. The shipped ports imply it does, but implication is not measurement,
///    and if it does NOT then -Force silently stops suppressing confirmation on a High-impact
///    destructive command - a finding for the whole class rather than this row. The row is not sealed
///    until a -Force A/B against the legacy function settles it.
///
/// ShouldProcess is real at HIGH impact, so $PsCmdlet.ShouldProcess becomes $__realCmdlet.ShouldProcess
/// with target and action byte-for-byte.
///
/// The process guard exits with a plain `return`, so NO continue-guard wrapper is involved. Both
/// Stop-Function -Continue sites sit inside genuine foreach loops (over $SqlInstance and over
/// $InputObject), so neither needs one either.
///
/// There are ZERO Test-Bound calls: the guard tests parameter VALUES
/// (`!$Snapshot -and !$Database -and !$AllSnapshots -and $null -eq $InputObject -and !$ExcludeDatabase`),
/// so no bound-flag substitution is carried at all. Worth stating so it does not read as an omission.
///
/// The private helpers Select-DefaultView and Get-ErrorMessage both resolve because the hop executes
/// in module scope.
///
/// Surface pinned by migration/baselines/Remove-DbaDbSnapshot.json
/// (sourceSha256 1e2c9e93d49e60edb2c5eb1012a144d75577815d04b3a66fa0e4b6d14bbd49e5): no named parameter
/// sets; SqlInstance 0, SqlCredential 1, Database 2, ExcludeDatabase 3, Snapshot 4, InputObject 5
/// ValueFromPipeline; AllSnapshots / Force / EnableException non-positional switches; outputType empty.
/// Positions declared explicitly per the positional-binding-loss class.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbSnapshot", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaDbSnapshotCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) whose snapshots are targeted.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>The snapshot(s) to drop.</summary>
    [Parameter(Position = 4)]
    public string[]? Snapshot { get; set; }

    /// <summary>Snapshot database object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>Drop every snapshot on the instance.</summary>
    [Parameter]
    public SwitchParameter AllSnapshots { get; set; }

    /// <summary>Drop via Remove-DbaDatabase, killing connections, and suppress confirmation.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin-computed Select-DefaultView property list, carried into the process hop.
    private object? _defaultProps;

    protected override void BeginProcessing()
    {

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__removeDbaDbSnapshotBegin"))
            {
                if (sentinel["__removeDbaDbSnapshotBegin"] is Hashtable state)
                {
                    _defaultProps = state["DefaultProps"];
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BeginScript,
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Snapshot, InputObject,
            AllSnapshots.ToBool(), Force.ToBool(), EnableException.ToBool(),
            _defaultProps, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block's $defaultProps assignment, handed to the process hop on a sentinel. The
    // begin block's OTHER statement - if ($Force) { $ConfirmPreference = 'none' } - is deliberately
    // NOT here; it lives in the process hop beside the gate it exists to affect.
    private const string BeginScript = """
param($EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $defaultProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database as Name', 'Status'

    # Hop mechanism, not source: hand the begin-computed property list to the process script.
    @{ __removeDbaDbSnapshotBegin = @{ DefaultProps = $defaultProps } }
} $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block verbatim, preceded by the begin block's ConfirmPreference line relocated
    // here (see the class remarks - it must sit in the same scope as the gate it affects). Edits:
    // $PsCmdlet -> $__realCmdlet, and -FunctionName Remove-DbaDbSnapshot on the direct Stop-Function
    // and Write-Message sites.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Snapshot, $InputObject, $AllSnapshots, $Force, $EnableException, $defaultProps, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [string[]]$Snapshot, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $AllSnapshots, $Force, $EnableException, $defaultProps, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # RELOCATED from the source's begin block - see the class remarks. It has to be in the same scope
    # as the ShouldProcess gate below, which a separate begin hop is not.
    if ($Force) { $ConfirmPreference = 'none' }

    if (!$Snapshot -and !$Database -and !$AllSnapshots -and $null -eq $InputObject -and !$ExcludeDatabase) {
        Stop-Function -Message "You must pipe in a snapshot or specify -Snapshot, -Database, -ExcludeDatabase or -AllSnapshots" -FunctionName Remove-DbaDbSnapshot
        return
    }

    # if piped value either doesn't exist or is not the proper type
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Remove-DbaDbSnapshot
        }

        $InputObject += Get-DbaDbSnapshot -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase -Snapshot $Snapshot
    }

    foreach ($db in $InputObject) {
        $server = $db.Parent

        if (-not $db.DatabaseSnapshotBaseName) {
            Stop-Function -Message "$db on $server is not a database snapshot" -Continue -FunctionName Remove-DbaDbSnapshot
        }

        if ($Force) {
            $db | Remove-DbaDatabase -Confirm:$false | Select-DefaultView -Property $defaultProps
        } else {
            try {
                if ($__realCmdlet.ShouldProcess("$db on $server", "Drop snapshot")) {
                    $db.Drop()
                    $server.Refresh()

                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.name
                        Status       = "Dropped"
                    } | Select-DefaultView -Property $defaultProps
                }
            } catch {
                Write-Message -Level Verbose -Message "Could not drop database $db on $server" -FunctionName Remove-DbaDbSnapshot -ModuleName "dbatools"

                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Database     = $db.name
                    Status       = (Get-ErrorMessage -Record $_)
                } | Select-DefaultView -Property $defaultProps
            }
        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Snapshot $InputObject $AllSnapshots $Force $EnableException $defaultProps $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
