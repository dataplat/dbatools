#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Revokes server-level role membership from SQL Server logins and roles.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the role-member drops, the
/// ShouldProcess gate, the input-type dispatch, and dbatools stream and error handling stay observable-identical
/// to the script implementation.
/// </para>
/// <para>
/// The script keeps state across its begin/process blocks in one function scope, and it has TWO ValueFromPipeline
/// parameters (SqlInstance and InputObject) plus a begin state-copy ($InputObject = $SqlInstance when SqlInstance
/// is bound by name). DEF-014: the source is begin/process with NO end block, so this port STREAMS per record
/// rather than buffering to EndProcessing. BeginProcessing captures the by-name flags (ContainsKey before any
/// pipeline record, so a piped SqlInstance reads false) and runs the begin block once. ProcessRecord runs the
/// process body for THAT record and emits immediately, overriding $InputObject only on a genuine rebind
/// (reference change); otherwise the begin's $InputObject (= $SqlInstance) stands. The shared scope the
/// single end-hop used to provide is reconstructed by carrying the process state across records, captured
/// in finally so an early return at the interrupt gate cannot skip the handoff.
/// </para>
/// <para>
/// The command mutates (DropMember/DropMembershipFromRole) and emits nothing. $Pscmdlet is redirected to
/// $__realCmdlet for the two ShouldProcess gates. EnableException is carried as a plain (untyped) value, because
/// a switch in the inner CmdletBinding scriptblock is excluded from positional binding. All five Test-Bound
/// checks (SqlInstance/ServerRole/Login in begin, ServerRole in process) map to the carried by-name flags. Every
/// DIRECT Stop-Function/Write-Message call takes -FunctionName; Get-DbaServerRole, Connect-DbaInstance, and the
/// SMO DropMember/DropMembershipFromRole methods are left unedited.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaServerRoleMember", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaServerRoleMemberCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The server-level roles to remove members from.</summary>
    [Parameter(Position = 2)]
    public string[]? ServerRole { get; set; }

    /// <summary>The logins to remove from the server roles.</summary>
    [Parameter(Position = 3)]
    public string[]? Login { get; set; }

    /// <summary>The nested roles to remove from the server roles.</summary>
    [Parameter(Position = 4)]
    public string[]? Role { get; set; }

    /// <summary>Server or ServerRole objects for pipeline operations.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>The InputObject seen at the previous ProcessRecord, to detect a genuine pipeline rebind.</summary>
    private object? _prevInputObject;

    /// <summary>$InputObject as the begin block left it, plus the process block's cross-record state.</summary>
    private object? _inputObjectState;
    private Hashtable? _processState;
    private bool _beginInterrupted;
    private bool _processInterrupted;

    /// <summary>The by-name InputObject value snapshotted at begin (the hop's initial $InputObject).</summary>
    private object? _byNameInputObject;

    private bool _sqlInstanceByName;
    private bool _serverRoleByName;
    private bool _loginByName;

    /// <summary>Captures the by-name binding of the parameters before any pipeline record arrives.</summary>
    protected override void BeginProcessing()
    {
        _sqlInstanceByName = MyInvocation.BoundParameters.ContainsKey("SqlInstance");
        _serverRoleByName = MyInvocation.BoundParameters.ContainsKey("ServerRole");
        _loginByName = MyInvocation.BoundParameters.ContainsKey("Login");
        // Snapshot the by-name InputObject (null unless -InputObject was passed by name). It is both the hop's
        // initial $InputObject and the rebind baseline, so the FIRST record's by-name value is NOT mistaken for
        // a pipeline rebind (which would defeat the begin block's $InputObject = $SqlInstance state-copy).
        _byNameInputObject = InputObject;
        _prevInputObject = InputObject;
        // The begin block's state-copy, mirrored here rather than round-tripped through the sentinel:
        // an SMO/DbaInstanceParameter array carried out as a PSObject can come back wrapped, and the body's
        // $input.GetType() dispatch then sees the wrapper instead of the element type.
        _inputObjectState = _sqlInstanceByName ? SqlInstance : InputObject;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            _byNameInputObject, SqlInstance, EnableException.ToBool(),
            _sqlInstanceByName, _serverRoleByName, _loginByName,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && item.BaseObject is PSCustomObject && LanguagePrimitives.IsTrue(
                item.Properties["__RemoveDbaServerRoleMemberBeginComplete"]?.Value))
            {
                _beginInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }
    }

    /// <summary>
    /// Runs the process body for THIS record and emits immediately.
    /// </summary>
    /// <remarks>
    /// DEF-014: the source is begin/process with NO end block, so it streams - each record's work is done
    /// and emitted as it arrives. This port previously buffered every record and did the work in
    /// EndProcessing, which PowerShell never calls when the upstream producer terminates, so a throwing
    /// producer silently discarded everything the source would already have emitted. The shared scope that
    /// the single end-hop provided is reconstructed explicitly by carrying the process state per record.
    /// </remarks>
    protected override void ProcessRecord()
    {
        if (_beginInterrupted || _processInterrupted || Interrupted)
            return;

        // The begin block may have replaced $InputObject with $SqlInstance; a genuine pipeline rebind
        // overrides it for this record, exactly as the parameter reassignment does in the function world.
        bool inputRebound = !ReferenceEquals(InputObject, _prevInputObject);
        _prevInputObject = InputObject;
        if (inputRebound)
            _inputObjectState = InputObject;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && item.BaseObject is PSCustomObject && LanguagePrimitives.IsTrue(
                item.Properties["__RemoveDbaServerRoleMemberProcessComplete"]?.Value))
            {
                _processState = UnwrapHopValue(item.Properties["State"]?.Value) as Hashtable;
                _processInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, ProcessScript,
            _inputObjectState, SqlInstance, SqlCredential, ServerRole, Login, Role,
            EnableException.ToBool(), this, _serverRoleByName, _processState,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    /// <summary>Unwraps a value the hop carried out through its sentinel.</summary>
    private static object? UnwrapHopValue(object? value)
    {
        if (value is null || ReferenceEquals(value, System.Management.Automation.Internal.AutomationNull.Value))
            return null;
        if (value is not PSObject wrapper)
            return value;
        foreach (PSMemberInfo member in wrapper.Members)
        {
            if (member is PSNoteProperty)
                return wrapper;
        }
        return wrapper.BaseObject;
    }

    // PS: the begin block (its Test-Bound checks mapped to the carried by-name flags), run ONCE in
    // BeginProcessing and handing $InputObject plus its interrupt latch out through a sentinel; the process
    // body then runs PER RECORD in its own hop (DEF-014). Substitutions only: $PSCmdlet -> $__realCmdlet (the two
    // ShouldProcess gates); Test-Bound SqlInstance/ServerRole/Login -> carried by-name flags; -FunctionName on the
    // 15 DIRECT Stop-Function/Write-Message calls. EnableException received untyped.
    private const string BeginScript = """
param($__byNameInputObject, $SqlInstance, $EnableException, $__sqlInstanceByName, $__serverRoleByName, $__loginByName, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
# No WhatIf/Confirm here: this begin hop is never handed $__realCmdlet, so it has no
# ShouldProcess gate, and its inner scriptblock is [CmdletBinding()] without
# SupportsShouldProcess. Reading $__boundWhatIf/$__boundConfirm - which this param()
# block does NOT declare - picked them up by dynamic scoping from an ENCLOSING hop
# whenever this command ran nested inside another ported command, and splatting them
# then threw "A parameter cannot be found that matches parameter name 'Confirm'".
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__byNameInputObject, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $EnableException, $__sqlInstanceByName, $__serverRoleByName, $__loginByName, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        $InputObject = $__byNameInputObject
        if ( (-not $__sqlInstanceByName) -and (-not $__serverRoleByName) -and (-not $__loginByName) ) {
            Stop-Function -Message "You must pipe in a ServerRole, Login, or specify a SqlInstance" -FunctionName Remove-DbaServerRoleMember
            return
        }

        if ($__sqlInstanceByName) {
            $InputObject = $SqlInstance
        }
    }

    [pscustomobject]@{ __RemoveDbaServerRoleMemberBeginComplete = $true; Interrupted = (Test-FunctionInterrupt) }
} $__byNameInputObject $SqlInstance $EnableException $__sqlInstanceByName $__serverRoleByName $__loginByName $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM, now STREAMED per record (DEF-014 - the source is begin/process
    // with no end block). Substitutions unchanged: $PSCmdlet -> $__realCmdlet on the two ShouldProcess
    // gates, the Test-Bound checks -> carried by-name flags, and -FunctionName attribution.
    private const string ProcessScript = """
param($InputObject, $SqlInstance, $SqlCredential, $ServerRole, $Login, $Role, $EnableException, $__realCmdlet, $__serverRoleByName, $__carryState, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param($InputObject, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$ServerRole, [string[]]$Login, [string[]]$Role, $EnableException, $__realCmdlet, $__serverRoleByName, $__carryState, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # Process-scope state as the previous record left it (DEF-014: this port now STREAMS per record to
    # match the source's begin/process shape, so the shared scope the single end-hop provided is
    # reconstructed explicitly). try/finally because the body returns early at the interrupt gate.
    if ($__carryState) { foreach ($__k in $__carryState.Keys) { Set-Variable -Name $__k -Value $__carryState[$__k] } }
    try {
        if (Test-FunctionInterrupt) { return }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName

            if ((-not $__serverRoleByName ) -and ($inputType -ne 'Microsoft.SqlServer.Management.Smo.ServerRole')) {
                Stop-Function -Message "You must pipe in a ServerRole or specify a ServerRole." -FunctionName Remove-DbaServerRoleMember
                return
            }

            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject" -FunctionName Remove-DbaServerRoleMember -ModuleName "dbatools"
                    try {
                        $serverRoles = Get-DbaServerRole -SqlInstance $input -SqlCredential $SqlCredential -ServerRole $ServerRole -EnableException
                    } catch {
                        Stop-Function -Message "Failure access $input" -ErrorRecord $_ -Target $input -Continue -FunctionName Remove-DbaServerRoleMember
                    }
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject" -FunctionName Remove-DbaServerRoleMember -ModuleName "dbatools"
                    try {
                        $serverRoles = Get-DbaServerRole -SqlInstance $input -SqlCredential $SqlCredential -ServerRole $ServerRole -EnableException
                    } catch {
                        Stop-Function -Message "Failure access $input" -ErrorRecord $_ -Target $input -Continue -FunctionName Remove-DbaServerRoleMember
                    }
                }
                'Microsoft.SqlServer.Management.Smo.ServerRole' {
                    Write-Message -Level Verbose -Message "Processing ServerRole through InputObject" -FunctionName Remove-DbaServerRoleMember -ModuleName "dbatools"
                    try {
                        $serverRoles = $inputObject
                    } catch {
                        Stop-Function -Message "Failure access $input" -ErrorRecord $_ -Target $input -Continue -FunctionName Remove-DbaServerRoleMember
                    }
                }
                default {
                    Stop-Function -Message "InputObject is not a server or role." -FunctionName Remove-DbaServerRoleMember
                    continue
                }
            }

            foreach ($sr in $serverRoles) {
                $instance = $sr.Parent
                foreach ($l in $Login) {
                    if ($__realCmdlet.ShouldProcess($instance, "Removing login $l from server-level role: $sr")) {
                        Write-Message -Level Verbose -Message "Removing login $l from server-level role: $sr on $instance" -FunctionName Remove-DbaServerRoleMember -ModuleName "dbatools"
                        try {
                            $sr.DropMember($l)
                        } catch {
                            Stop-Function -Message "Failure removing $l on $instance" -ErrorRecord $_ -Target $sr -FunctionName Remove-DbaServerRoleMember
                        }
                    }

                }
                foreach ($r in $Role) {
                    try {
                        $isServerRole = Get-DbaServerRole -SqlInstance $input -SqlCredential $SqlCredential -ServerRole $r -EnableException
                    } catch {
                        Stop-Function -Message "Failure access $input" -ErrorRecord $_ -Target $input -FunctionName Remove-DbaServerRoleMember
                        continue
                    }
                    if (-not $isServerRole) {
                        Write-Message -Level Warning -Message "$r server-level role was not found on $instance" -FunctionName Remove-DbaServerRoleMember -ModuleName "dbatools"
                        continue
                    }
                    if ($__realCmdlet.ShouldProcess($instance, "Removing role $r from server-level role: $sr")) {
                        Write-Message -Level Verbose -Message "Removing role $r from server-level role: $sr on $instance" -FunctionName Remove-DbaServerRoleMember -ModuleName "dbatools"
                        try {
                            $sr.DropMembershipFromRole($r)
                        } catch {
                            Stop-Function -Message "Failure removing $r on $instance" -ErrorRecord $_ -Target $sr -FunctionName Remove-DbaServerRoleMember
                        }
                    }
                }
            }
        }
    } finally {
    [pscustomobject]@{ __RemoveDbaServerRoleMemberProcessComplete = $true; Interrupted = (Test-FunctionInterrupt); State = @{ inputType = $inputType; instance = $instance; isServerRole = $isServerRole; serverRoles = $serverRoles } }
    }
} $InputObject $SqlInstance $SqlCredential $ServerRole $Login $Role $EnableException $__realCmdlet $__serverRoleByName $__carryState $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
