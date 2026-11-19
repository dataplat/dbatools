#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates linked server login mappings. Port of public/New-DbaLinkedServerLogin.ps1
/// (W3-068). The process body rides one VERBATIM module hop per record inside a
/// DOT-SOURCED inner block (W1-108: two validation `Stop-Function; return` early exits -
/// the source LACKS the Interrupted prologue, so the validations re-fire per record
/// exactly as the function's did; no C#-side latch). $Pscmdlet.ShouldProcess routes to
/// the REAL cmdlet (ConfirmImpact Low mirrored). The __w3068State sentinel carries the
/// $InputObject += Get-DbaLinkedServer accumulation (W1-070 + the F1 named-at-begin
/// rebind discriminator) and stale locals. SECURITY, source-verbatim: the RemoteUserPassword
/// branch flattens the caller-supplied SecureString through the private
/// ConvertFrom-SecurePass into SMO SetRemotePassword - shipped provisioning behavior
/// reproduced exactly (SMO transmits it to sp_addlinkedsrvlogin in plain text per the
/// function's own documented warning); the SecureString itself rides the hop as the live
/// object and never appears in messages or logs. Three Test-Bound reads carried as flags.
/// NO WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/New-DbaLinkedServerLogin.json (implicit positions 0-6,
/// Impersonate switch non-positional, InputObject LinkedServer[] pos6 VFP,
/// ConfirmImpact Low).
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaLinkedServerLogin", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaLinkedServerLoginCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The linked server(s) to create the login mapping on.</summary>
    [Parameter(Position = 2)]
    public string[]? LinkedServer { get; set; }

    /// <summary>The local login to map.</summary>
    [Parameter(Position = 3)]
    public string? LocalLogin { get; set; }

    /// <summary>The remote user to map the local login to.</summary>
    [Parameter(Position = 4)]
    public string? RemoteUser { get; set; }

    /// <summary>The remote user's password.</summary>
    [Parameter(Position = 5)]
    public System.Security.SecureString? RemoteUserPassword { get; set; }

    /// <summary>Map local logins to connect using their own credentials.</summary>
    [Parameter]
    public SwitchParameter Impersonate { get; set; }

    /// <summary>SMO LinkedServer object(s) from Get-DbaLinkedServer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public Microsoft.SqlServer.Management.Smo.LinkedServer[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Fn-scope $InputObject accumulation across records (the bag rides the hop).
    private Hashtable? _state;
    private object? _inputObjectState;
    private object? _lastBoundInputObject;
    private bool _bindInitialized;
    private bool _inputObjectNamedBound;

    protected override void BeginProcessing()
    {
        // Pipeline bindings are absent at begin time - the F1 named-at-begin rebind
        // discriminator (codex W3-002 F1, family-wide).
        _inputObjectNamedBound = TestBound(nameof(InputObject));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // W1-070 + F1: a piped LinkedServer re-binds EVERY record it arrives in.
        if ((!_inputObjectNamedBound && TestBound(nameof(InputObject))) ||
            !ReferenceEquals(InputObject, _lastBoundInputObject) || !_bindInitialized)
        {
            _inputObjectState = InputObject;
            _lastBoundInputObject = InputObject;
            _bindInitialized = true;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3068State"))
            {
                _state = sentinel["__w3068State"] as Hashtable;
                if (_state is not null)
                {
                    _inputObjectState = _state["InputObject"];
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
        }, ProcessScript,
            SqlInstance, SqlCredential, LinkedServer, LocalLogin, RemoteUser,
            RemoteUserPassword, Impersonate.ToBool(), _inputObjectState,
            EnableException.ToBool(), _state,
            TestBound(nameof(LocalLogin)), TestBound(nameof(RemoteUser)),
            TestBound(nameof(RemoteUserPassword)), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM inside a dot-sourced inner block (two
    // validation early returns; the trailing state sentinel still emits). Substitutions
    // only: Test-Bound X -> carried $__boundX flags, $Pscmdlet -> $__realCmdlet, and
    // explicit -FunctionName New-DbaLinkedServerLogin on Stop-Function (W1-090). The
    // SetRemotePassword line keeps the SOURCE's own ConvertFrom-SecurePass flatten -
    // verbatim shipped behavior.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $LinkedServer, $LocalLogin, $RemoteUser, $RemoteUserPassword, $Impersonate, $InputObject, $EnableException, $__state, $__boundLocalLogin, $__boundRemoteUser, $__boundRemoteUserPassword, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$LinkedServer, [string]$LocalLogin, [string]$RemoteUser, [Security.SecureString]$RemoteUserPassword, $Impersonate, [Microsoft.SqlServer.Management.Smo.LinkedServer[]]$InputObject, $EnableException, $__state, $__boundLocalLogin, $__boundRemoteUser, $__boundRemoteUserPassword, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # restore fn-scope locals mutated by earlier records
    if ($null -ne $__state) {
        $lnkSrv = $__state.lnkSrv
        $newLinkedServerLogin = $__state.newLinkedServerLogin
        $instance = $__state.instance
    }

    . {
        if ($SqlInstance -and (-not $LinkedServer)) {
            Stop-Function -Message "LinkedServer is required when SqlInstance is specified" -FunctionName New-DbaLinkedServerLogin
            return
        }

        if (-not $LocalLogin) {
            Stop-Function -Message "LocalLogin is required in all scenarios" -FunctionName New-DbaLinkedServerLogin
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaLinkedServer -SqlInstance $instance -SqlCredential $SqlCredential -LinkedServer $LinkedServer
        }

        foreach ($lnkSrv in $InputObject) {

            if ($__realCmdlet.ShouldProcess($($lnkSrv.Parent.Name), "Creating the linked server login on $($lnkSrv.Parent.Name)")) {
                try {
                    $newLinkedServerLogin = New-Object Microsoft.SqlServer.Management.Smo.LinkedServerLogin
                    $newLinkedServerLogin.Parent = $lnkSrv

                    if ($__boundLocalLogin) {
                        $newLinkedServerLogin.Name = $LocalLogin
                    }

                    if ($__boundRemoteUser) {
                        $newLinkedServerLogin.RemoteUser = $RemoteUser
                    }

                    if ($__boundRemoteUserPassword) {
                        $newLinkedServerLogin.SetRemotePassword(($RemoteUserPassword | ConvertFrom-SecurePass))
                    }

                    $newLinkedServerLogin.Impersonate = [boolean]$Impersonate

                    $newLinkedServerLogin.Create()

                    $lnkSrv | Get-DbaLinkedServerLogin -LocalLogin $LocalLogin

                } catch {
                    Stop-Function -Message "Failure on $($lnkSrv.Parent.Name) to create the linked server login for $lnkSrv" -ErrorRecord $_ -Continue -FunctionName New-DbaLinkedServerLogin
                }
            }
        }
    }
    @{ __w3068State = @{ InputObject = $InputObject; lnkSrv = $lnkSrv; newLinkedServerLogin = $newLinkedServerLogin; instance = $instance } }
} $SqlInstance $SqlCredential $LinkedServer $LocalLogin $RemoteUser $RemoteUserPassword $Impersonate $InputObject $EnableException $__state $__boundLocalLogin $__boundRemoteUser $__boundRemoteUserPassword $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
