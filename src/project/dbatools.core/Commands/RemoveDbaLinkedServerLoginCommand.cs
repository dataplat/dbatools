#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes linked server login mappings. Port of public/Remove-DbaLinkedServerLogin.ps1
/// (W3-078), fourth LinkedServer-family row (W3-067/068/077 siblings). The source
/// accumulates drop targets across process records and DROPS IN THE END BLOCK, so the
/// port carries the $linkedServerLoginsToDrop accumulator through the __w3078State
/// sentinel from per-record process hops into one end hop (the W3-072 shape; the begin
/// block only initializes the accumulator, folded into the null-state first-record
/// init). The process body rides inside a DOT-SOURCED inner block (W1-108: the
/// SqlInstance-without-LinkedServer validation is a `Stop-Function; return` early exit
/// that re-fires per record). InputObject is object[] (pos4 VFP) with the source's
/// THREE-WAY runtime type dispatch (Server / LinkedServer / LinkedServerLogin) riding
/// verbatim; negated Test-Bound LinkedServer carried as a bound flag. The end hop wraps
/// the drop loop with the $__realCmdlet.ShouldProcess gate (ConfirmImpact HIGH mirrored)
/// including the source's UNREACHABLE Failure status object (the catch's Stop-Function
/// -Continue continues the loop before the emit in non-EE and throws under EE - dead
/// code preserved verbatim). NO WarningAction carrier (codex W3-005 r3). Surface pinned
/// by migration/baselines/Remove-DbaLinkedServerLogin.json (implicit positions 0-4).
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaLinkedServerLogin", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaLinkedServerLoginCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The linked server(s) whose login mappings should be removed.</summary>
    [Parameter(Position = 2)]
    public string[]? LinkedServer { get; set; }

    /// <summary>The local login(s) whose mappings should be removed.</summary>
    [Parameter(Position = 3)]
    public string[]? LocalLogin { get; set; }

    /// <summary>Server, LinkedServer or LinkedServerLogin object(s) (type-dispatched like the source).</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The cross-block $linkedServerLoginsToDrop accumulator (begin inits, process
    // appends, end drops).
    private Hashtable? _state;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3078State"))
            {
                _state = sentinel["__w3078State"] as Hashtable;
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
            SqlInstance, SqlCredential, LinkedServer, LocalLogin, InputObject,
            EnableException.ToBool(), _state, TestBound(nameof(LinkedServer)),
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
            EnableException.ToBool(), _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM per record inside a dot-sourced block (the
    // SqlInstance-without-LinkedServer validation early return re-fires per record).
    // Substitutions only: Test-Bound -Not -ParameterName LinkedServer -> the negated
    // carried flag, explicit -FunctionName Remove-DbaLinkedServerLogin on Stop-Function
    // (W1-090). $linkedServerLoginsToDrop restores from the sentinel ($null first record
    // = the begin block's @( ) init, which had no other effect) and returns through it.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $LinkedServer, $LocalLogin, $InputObject, $EnableException, $__state, $__boundLinkedServer, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$LinkedServer, [string[]]$LocalLogin, [object[]]$InputObject, $EnableException, $__state, $__boundLinkedServer, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin-block init on the first record; later records restore the accumulator
    if ($null -eq $__state) {
        $linkedServerLoginsToDrop = @()
    } else {
        $linkedServerLoginsToDrop = $__state.linkedServerLoginsToDrop
    }

    . {
        if ($SqlInstance -and (-not $LinkedServer)) {
            Stop-Function -Message "LinkedServer is required when SqlInstance is specified" -FunctionName Remove-DbaLinkedServerLogin
            return
        }

        foreach ($instance in $SqlInstance) {
            $linkedServerLoginsToDrop += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential | Get-DbaLinkedServerLogin -LinkedServer $LinkedServer -LocalLogin $LocalLogin
        }

        foreach ($object in $InputObject) {

            if ($object -is [Microsoft.SqlServer.Management.Smo.Server]) {

                if (-not $__boundLinkedServer) {
                    Stop-Function -Message "LinkedServer is required" -Continue -FunctionName Remove-DbaLinkedServerLogin
                }

                $linkedServerLoginsToDrop += Get-DbaLinkedServerLogin -SqlInstance $object -LinkedServer $LinkedServer -LocalLogin $LocalLogin
            } elseif ($object -is [Microsoft.SqlServer.Management.Smo.LinkedServer]) {
                $linkedServerLoginsToDrop += $object | Get-DbaLinkedServerLogin -LocalLogin $LocalLogin
            } elseif ($object -is [Microsoft.SqlServer.Management.Smo.LinkedServerLogin]) {
                $linkedServerLoginsToDrop += $object
            }
        }
    }

    @{ __w3078State = @{ linkedServerLoginsToDrop = $linkedServerLoginsToDrop } }
} $SqlInstance $SqlCredential $LinkedServer $LocalLogin $InputObject $EnableException $__state $__boundLinkedServer $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet and
    // explicit -FunctionName Remove-DbaLinkedServerLogin on Stop-Function (W1-090). The
    // grab-info comment and the UNREACHABLE post-Stop-Function Failure object ride as-is.
    private const string EndScript = """
param($EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $linkedServerLoginsToDrop = if ($null -eq $__state) { @( ) } else { $__state.linkedServerLoginsToDrop }

    foreach ($lsLoginToDrop in $linkedServerLoginsToDrop) {
        # grab info to be used in output.
        $lsqlinstance = $lsLoginToDrop.Parent.Parent.Name
        $lserver = $lsLoginToDrop.Parent.Name
        $lsqlcomputername = $lsLoginToDrop.Parent.Parent.ComputerName
        $lsqlinstancename = $lsLoginToDrop.Parent.Parent.ServiceName
        $lsloginname = $lsLoginToDrop.Name

        if ($__realCmdlet.ShouldProcess($lsqlinstance, "Removing the linked server login $lsloginname for the linked server $lserver on $lsqlinstance")) {
            try {
                $lsLoginToDrop.Drop()
                [PSCustomObject]@{
                    ComputerName = $lsqlcomputername
                    InstanceName = $lsqlinstancename
                    SqlInstance  = $lsqlinstance
                    LinkedServer = $lserver
                    Login        = $lsLoginToDrop.Name
                    Status       = "Removed"
                }
            } catch {
                Stop-Function -Message "Failure on $lsqlinstance to remove the linked server login $lsloginname for the linked server $lserver" -ErrorRecord $_ -Continue -FunctionName Remove-DbaLinkedServerLogin
                [PSCustomObject]@{
                    ComputerName = $lsqlcomputername
                    InstanceName = $lsqlinstancename
                    SqlInstance  = $lsqlinstance
                    LinkedServer = $lserver
                    Login        = $lsLoginToDrop.Name
                    Status       = "Failure"
                }
            }
        }
    }
} $EnableException $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
