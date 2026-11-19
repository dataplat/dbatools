#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes linked servers. Port of public/Remove-DbaLinkedServer.ps1 (W3-077), completing
/// the LinkedServer trio (W3-067/W3-068 siblings). The source accumulates drop targets
/// across process records and DROPS IN THE END BLOCK, so the port carries the
/// $linkedServersToDrop accumulator through the __w3077State sentinel from per-record
/// process hops into one end hop (the W3-072 shape; the begin block only initializes the
/// accumulator, folded into the null-state first-record init). InputObject is object[]
/// (pos3 VFP) with the source's runtime TYPE DISPATCH (Server vs LinkedServer) riding
/// verbatim; the $InputObject += Connect-DbaInstance accumulation is invocation-local
/// (piped records rebind). Test-Bound -Not LinkedServer carried as a bound flag. The end
/// hop wraps the drop loop with the $__realCmdlet.ShouldProcess gate (ConfirmImpact HIGH
/// mirrored) and the source's Drop([boolean]$Force) + catch Stop-Function -Continue. NO
/// WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Remove-DbaLinkedServer.json (implicit positions 0-3, no sets).
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaLinkedServer", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaLinkedServerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The linked server(s) to remove.</summary>
    [Parameter(Position = 2)]
    public string[]? LinkedServer { get; set; }

    /// <summary>Server or LinkedServer object(s) (type-dispatched like the source).</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public object[]? InputObject { get; set; }

    /// <summary>Drops the linked server even when remote/linked logins still exist.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The cross-block $linkedServersToDrop accumulator (begin inits, process appends,
    // end drops).
    private Hashtable? _state;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3077State"))
            {
                _state = sentinel["__w3077State"] as Hashtable;
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
            SqlInstance, SqlCredential, LinkedServer, InputObject, EnableException.ToBool(),
            _state, TestBound(nameof(LinkedServer)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, EndScript,
            Force.ToBool(), EnableException.ToBool(), _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM per record. Substitutions only: Test-Bound -Not
    // -ParameterName LinkedServer -> the negated carried flag, explicit -FunctionName
    // Remove-DbaLinkedServer on Stop-Function (W1-090). $linkedServersToDrop restores
    // from the sentinel ($null first record = the begin block's @( ) init, which had no
    // other effect) and returns through it.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $LinkedServer, $InputObject, $EnableException, $__state, $__boundLinkedServer, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$LinkedServer, [object[]]$InputObject, $EnableException, $__state, $__boundLinkedServer, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin-block init on the first record; later records restore the accumulator
    if ($null -eq $__state) {
        $linkedServersToDrop = @()
    } else {
        $linkedServersToDrop = $__state.linkedServersToDrop
    }

    foreach ($instance in $SqlInstance) {
        $InputObject += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
    }

    foreach ($obj in $InputObject) {

        if ($obj -is [Microsoft.SqlServer.Management.Smo.Server]) {

            if (-not $__boundLinkedServer) {
                Stop-Function -Message "LinkedServer is required" -Continue -FunctionName Remove-DbaLinkedServer
            }

            foreach ($ls in $LinkedServer) {

                if ($obj.LinkedServers.Name -notcontains $ls) {
                    Stop-Function -Message "Linked server $ls does not exist on $($obj.Name)" -Continue -FunctionName Remove-DbaLinkedServer
                }

                $linkedServersToDrop += $obj.LinkedServers[$ls]
            }

        } elseif ($obj -is [Microsoft.SqlServer.Management.Smo.LinkedServer]) {
            $linkedServersToDrop += $obj
        }
    }

    @{ __w3077State = @{ linkedServersToDrop = $linkedServersToDrop } }
} $SqlInstance $SqlCredential $LinkedServer $InputObject $EnableException $__state $__boundLinkedServer $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet and
    // explicit -FunctionName Remove-DbaLinkedServer on Stop-Function (W1-090).
    private const string EndScript = """
param($Force, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($Force, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $linkedServersToDrop = if ($null -eq $__state) { @( ) } else { $__state.linkedServersToDrop }

    foreach ($lsToDrop in $linkedServersToDrop) {

        if ($__realCmdlet.ShouldProcess($lsToDrop.Parent.Name, "Removing the linked server $($lsToDrop.Name) on $($lsToDrop.Parent.Name)")) {
            try {
                $lsToDrop.Drop([boolean]$Force)
            } catch {
                Stop-Function -Message "Failure on $($lsToDrop.Parent.Name) to remove the linked server $($lsToDrop.Name)" -ErrorRecord $_ -Continue -FunctionName Remove-DbaLinkedServer
            }
        }
    }
} $Force $EnableException $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
