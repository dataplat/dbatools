#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Modifies SQL Server login properties including passwords, permissions, roles, and account status.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the SMO login mutations, the
/// policy-toggle unlock technique, the ShouldProcess gate, the output shape, and dbatools stream and error
/// handling stay observable-identical to the script implementation.
/// </para>
/// <para>
/// The script's function scope spans the whole pipeline, and two of its process-block locals are branch-assigned
/// in one record and readable in the next ($passwordChanged, read unconditionally when the result object is
/// built, and $instance, read by the rename-collision message outside its own loop). Its begin block also
/// derives $NewSecurePassword (from a PSCredential or SecureString, which rides live and is never flattened)
/// and arms the Stop-Function interrupt latch that the process block checks via Test-FunctionInterrupt - a
/// scope-relative variable, not a callstack lookup. DEF-014: the source is begin/process with NO end block,
/// so this port STREAMS per record - BeginProcessing captures the by-name bound flags and runs the begin
/// block once (handing out $NewSecurePassword and its interrupt latch), and ProcessRecord runs the process
/// body for THAT record and emits immediately. InputObject is the only pipeline-bound parameter, so every
/// pipeline record is a rebind (the engine reassigns the parameter before each process invocation even when
/// the same array instance arrives twice, discarding the body's += mutation like the function world does);
/// only a by-name InputObject persists across the whole run, and it seeds the hop unoverridden.
/// That KNOWN DIVERGENCE is now GONE. The buffered shape enumerated the whole producer before emitting
/// anything, so a downstream early stop (Select-Object -First 1) stopped the producer later than in the
/// function world - and, the reason DEF-014 was raised, a producer that THROWS discarded every record's
/// work outright, because PowerShell never calls EndProcessing in that case. The cross-record state that
/// made buffering attractive rides a state bag instead: restored at hop entry, captured in finally. $InputObject is a typed local ([Smo.Login[]]) so the body's += keeps the
/// source's typed-array re-coercion. try/finally keeps each record's early return from skipping the handoff, and the
/// interrupt latch, $passwordChanged, $instance and $allLogins are all carried explicitly across records.
/// </para>
/// <para>
/// The command emits one result object per modified login and can Stop-Function-terminate later in the run
/// under -EnableException, so it streams through InvokeScopedStreaming - a buffered call would drop the
/// already-emitted results before the throw. The callback dispatches ErrorRecords to WriteError, else
/// WriteObject. All switches and EnableException are carried as plain (untyped) values, because a switch in
/// the inner CmdletBinding scriptblock is excluded from positional binding. The script's ~25 Test-Bound reads
/// map to the carried by-name flags (Test-Bound scope-walks the caller and cannot ride a hop). $Pscmdlet is
/// redirected to $__realCmdlet for the single ShouldProcess gate. Every DIRECT Stop-Function call takes
/// -FunctionName, and every DIRECT Write-Message call takes -FunctionName plus -ModuleName "dbatools" (the
/// DEF-006 attribution rule). The $allLogins table is keyed by $instance.ToString() but read back by
/// $server.Name - a silent null on mismatch - and that source quirk is preserved verbatim, as are the
/// SMO Alter/Refresh/ChangePassword calls and the ALTER LOGIN ... HASHED query.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaLogin", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SetDbaLoginCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The SQL Server login names to modify.</summary>
    [Parameter(Position = 2)]
    public string[]? Login { get; set; }

    /// <summary>New password as a PSCredential or SecureString.</summary>
    [Parameter(Position = 3)]
    [Alias("Password")]
    public object? SecurePassword { get; set; }

    /// <summary>Hashed password value (0x...) for transferring logins between instances.</summary>
    [Parameter(Position = 4)]
    public string? PasswordHash { get; set; }

    /// <summary>The default database the login connects to after authentication.</summary>
    [Parameter(Position = 5)]
    [Alias("DefaultDB")]
    public string? DefaultDatabase { get; set; }

    /// <summary>Unlocks a locked login account.</summary>
    [Parameter]
    public SwitchParameter Unlock { get; set; }

    /// <summary>Forces the user to change their password at next login.</summary>
    [Parameter]
    [Alias("MustChange")]
    public SwitchParameter PasswordMustChange { get; set; }

    /// <summary>Renames the login to a new name.</summary>
    [Parameter(Position = 6)]
    public string? NewName { get; set; }

    /// <summary>Disables the login account.</summary>
    [Parameter]
    public SwitchParameter Disable { get; set; }

    /// <summary>Enables a previously disabled login account.</summary>
    [Parameter]
    public SwitchParameter Enable { get; set; }

    /// <summary>Denies the login permission to connect to the instance.</summary>
    [Parameter]
    public SwitchParameter DenyLogin { get; set; }

    /// <summary>Grants or restores the login permission to connect to the instance.</summary>
    [Parameter]
    public SwitchParameter GrantLogin { get; set; }

    /// <summary>Enables or disables Windows password policy enforcement for the login.</summary>
    [Parameter]
    public SwitchParameter PasswordPolicyEnforced { get; set; }

    /// <summary>Enables or disables password expiration checking for the login.</summary>
    [Parameter]
    public SwitchParameter PasswordExpirationEnabled { get; set; }

    /// <summary>Server-level roles to grant to the login.</summary>
    [Parameter(Position = 7)]
    [PsStringArrayCast]
    [ValidateSet("bulkadmin", "dbcreator", "diskadmin", "processadmin", "public", "securityadmin", "serveradmin", "setupadmin", "sysadmin")]
    public string[]? AddRole { get; set; }

    /// <summary>Server-level roles to revoke from the login.</summary>
    [Parameter(Position = 8)]
    [PsStringArrayCast]
    [ValidateSet("bulkadmin", "dbcreator", "diskadmin", "processadmin", "public", "securityadmin", "serveradmin", "setupadmin", "sysadmin")]
    public string[]? RemoveRole { get; set; }

    /// <summary>Login objects from Get-DbaLogin for pipeline operations.</summary>
    [Parameter(ValueFromPipeline = true, Position = 9)]
    public Microsoft.SqlServer.Management.Smo.Login[]? InputObject { get; set; }

    /// <summary>Unlocks a login without a password reset by toggling the policy settings.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>One batch per pipeline record: { inputRebound, InputObject }.</summary>
    /// <summary>$NewSecurePassword from the begin block, plus the process block's cross-record state.</summary>
    private object? _newSecurePasswordState;
    private Hashtable? _processState;
    private bool _beginInterrupted;
    private bool _processInterrupted;

    /// <summary>Whether -InputObject was bound by name (captured before any pipeline record arrives).</summary>
    private bool _inputObjectByName;

    /// <summary>The by-name InputObject value snapshotted at begin (the hop's initial $InputObject).</summary>
    private object? _byNameInputObject;

    private bool _sqlInstanceBound;
    private bool _loginBound;
    private bool _securePasswordBound;
    private bool _passwordHashBound;
    private bool _defaultDatabaseBound;
    private bool _unlockBound;
    private bool _passwordMustChangeBound;
    private bool _newNameBound;
    private bool _disableBound;
    private bool _enableBound;
    private bool _denyLoginBound;
    private bool _grantLoginBound;
    private bool _passwordPolicyEnforcedBound;
    private bool _passwordExpirationEnabledBound;
    private bool _forceBound;

    /// <summary>Captures the by-name binding of the parameters before any pipeline record arrives.</summary>
    protected override void BeginProcessing()
    {
        _sqlInstanceBound = MyInvocation.BoundParameters.ContainsKey("SqlInstance");
        _loginBound = MyInvocation.BoundParameters.ContainsKey("Login");
        _securePasswordBound = MyInvocation.BoundParameters.ContainsKey("SecurePassword");
        _passwordHashBound = MyInvocation.BoundParameters.ContainsKey("PasswordHash");
        _defaultDatabaseBound = MyInvocation.BoundParameters.ContainsKey("DefaultDatabase");
        _unlockBound = MyInvocation.BoundParameters.ContainsKey("Unlock");
        _passwordMustChangeBound = MyInvocation.BoundParameters.ContainsKey("PasswordMustChange");
        _newNameBound = MyInvocation.BoundParameters.ContainsKey("NewName");
        _disableBound = MyInvocation.BoundParameters.ContainsKey("Disable");
        _enableBound = MyInvocation.BoundParameters.ContainsKey("Enable");
        _denyLoginBound = MyInvocation.BoundParameters.ContainsKey("DenyLogin");
        _grantLoginBound = MyInvocation.BoundParameters.ContainsKey("GrantLogin");
        _passwordPolicyEnforcedBound = MyInvocation.BoundParameters.ContainsKey("PasswordPolicyEnforced");
        _passwordExpirationEnabledBound = MyInvocation.BoundParameters.ContainsKey("PasswordExpirationEnabled");
        _forceBound = MyInvocation.BoundParameters.ContainsKey("Force");
        // InputObject is the command's ONLY pipeline-bound parameter, so binding is bimodal: bound by name
        // (one ProcessRecord, the by-name value seeds the hop and is never overridden) or bound per pipeline
        // record (EVERY record is a rebind - the engine reassigns the parameter before each process
        // invocation even when the same array instance arrives twice, which discards the body's += mutation
        // exactly like the function world). Reference-identity detection would miss that same-instance case
        // and leak the previous record's expanded $InputObject.
        _inputObjectByName = MyInvocation.BoundParameters.ContainsKey("InputObject");
        _byNameInputObject = InputObject;

        // DEF-014: the begin block runs ONCE here rather than inside a single end-hop, handing out the
        // $NewSecurePassword it resolves and its interrupt latch so every record's hop sees them.
        // STREAMING, not buffered: a begin-block Stop-Function -Continue raises a ContinueException that
        // prevents a buffered collection from ever being returned, discarding warnings it already produced.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && item.BaseObject is PSCustomObject && LanguagePrimitives.IsTrue(
                item.Properties["__SetDbaLoginBeginComplete"]?.Value))
            {
                _newSecurePasswordState = UnwrapHopValue(item.Properties["NewSecurePassword"]?.Value);
                _beginInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, BeginScript,
            Login, SecurePassword, PasswordHash, NewName, EnableException.ToBool(),
            _sqlInstanceBound, _loginBound, _securePasswordBound, _passwordHashBound, _defaultDatabaseBound,
            _unlockBound, _passwordMustChangeBound, _newNameBound, _disableBound, _enableBound,
            _denyLoginBound, _grantLoginBound, _passwordPolicyEnforcedBound, _passwordExpirationEnabledBound, _forceBound,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    /// <summary>
    /// Runs the process body for THIS record and emits immediately.
    /// </summary>
    /// <remarks>
    /// DEF-014: the source is begin/process with NO end block, so it streams - each record's work is done
    /// and emitted as it arrives. This port previously buffered every record and did the work in
    /// EndProcessing, which PowerShell never calls when the upstream producer terminates, so a throwing
    /// producer silently discarded everything the source would already have emitted. The shared scope the
    /// single end-hop provided is reconstructed by carrying the process state across records.
    /// </remarks>
    protected override void ProcessRecord()
    {
        if (_beginInterrupted || _processInterrupted || Interrupted)
            return;

        // Bimodal binding, unchanged from the buffered shape: InputObject is either bound BY NAME (one
        // record, the by-name value stands) or rebound on EVERY pipeline record.
        object? effectiveInputObject = _inputObjectByName ? _byNameInputObject : InputObject;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && item.BaseObject is PSCustomObject && LanguagePrimitives.IsTrue(
                item.Properties["__SetDbaLoginProcessComplete"]?.Value))
            {
                _processState = UnwrapHopValue(item.Properties["State"]?.Value) as Hashtable;
                _processInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, ProcessScript,
            effectiveInputObject, SqlInstance, SqlCredential, Login, SecurePassword, PasswordHash, DefaultDatabase,
            Unlock.ToBool(), PasswordMustChange.ToBool(), NewName, Disable.ToBool(), Enable.ToBool(), DenyLogin.ToBool(), GrantLogin.ToBool(),
            PasswordPolicyEnforced.ToBool(), PasswordExpirationEnabled.ToBool(), AddRole, RemoveRole, Force.ToBool(), EnableException.ToBool(), this,
            _newSecurePasswordState, _processState,
            _sqlInstanceBound, _loginBound, _securePasswordBound, _passwordHashBound, _defaultDatabaseBound,
            _unlockBound, _passwordMustChangeBound, _newNameBound, _disableBound, _enableBound,
            _denyLoginBound, _grantLoginBound, _passwordPolicyEnforcedBound, _passwordExpirationEnabledBound, _forceBound,
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

    // PS: the begin block, run ONCE in BeginProcessing and handing out $NewSecurePassword plus its interrupt
    // latch through a sentinel; the process body then runs PER RECORD in its own hop (DEF-014).
    // Substitutions only: $Pscmdlet -> $__realCmdlet (the ShouldProcess gate); the Test-Bound reads -> carried
    // by-name flags; -FunctionName on the 24 DIRECT Stop-Function calls; -FunctionName +
    // on the 9 DIRECT Write-Message calls. EnableException and the switches received untyped.
    private const string BeginScript = """
param($Login, $SecurePassword, $PasswordHash, $NewName, $EnableException, $__sqlInstanceBound, $__loginBound, $__securePasswordBound, $__passwordHashBound, $__defaultDatabaseBound, $__unlockBound, $__passwordMustChangeBound, $__newNameBound, $__disableBound, $__enableBound, $__denyLoginBound, $__grantLoginBound, $__passwordPolicyEnforcedBound, $__passwordExpirationEnabledBound, $__forceBound, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
# No WhatIf/Confirm here: this begin hop is never handed $__realCmdlet, so it has no
# ShouldProcess gate, and its inner scriptblock is [CmdletBinding()] without
# SupportsShouldProcess. Reading $__boundWhatIf/$__boundConfirm - which this param()
# block does NOT declare - picked them up by dynamic scoping from an ENCLOSING hop
# (Sync-DbaLoginPassword calls Set-DbaLogin from inside its own hop), and splatting
# them then threw "A parameter cannot be found that matches parameter name 'Confirm'".
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string[]]$Login, $SecurePassword, [string]$PasswordHash, [string]$NewName, $EnableException, $__sqlInstanceBound, $__loginBound, $__securePasswordBound, $__passwordHashBound, $__defaultDatabaseBound, $__unlockBound, $__passwordMustChangeBound, $__newNameBound, $__disableBound, $__enableBound, $__denyLoginBound, $__grantLoginBound, $__passwordPolicyEnforcedBound, $__passwordExpirationEnabledBound, $__forceBound, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        # Check the parameters
        if (($__sqlInstanceBound) -and (-not $__loginBound)) {
            Stop-Function -Message 'You must specify a Login when using SqlInstance' -FunctionName Set-DbaLogin
        }

        if (($__newNameBound) -and $Login -eq $NewName) {
            Stop-Function -Message 'Login name is the same as the value in -NewName' -Target $Login -Continue -FunctionName Set-DbaLogin
        }

        if (($__disableBound) -and ($__enableBound)) {
            Stop-Function -Message 'You cannot use both -Enable and -Disable together' -Target $Login -Continue -FunctionName Set-DbaLogin
        }

        if (($__grantLoginBound) -and ($__denyLoginBound)) {
            Stop-Function -Message 'You cannot use both -GrantLogin and -DenyLogin together' -Target $Login -Continue -FunctionName Set-DbaLogin
        }

        if (($__securePasswordBound) -and ($__passwordHashBound)) {
            Stop-Function -Message 'You cannot use both -SecurePassword and -PasswordHash together' -Target $Login -Continue -FunctionName Set-DbaLogin
        }

        if (($__passwordHashBound) -and ($__passwordMustChangeBound)) {
            Stop-Function -Message 'You cannot use -PasswordHash with -PasswordMustChange' -Target $Login -Continue -FunctionName Set-DbaLogin
        }

        if (($__passwordHashBound) -and $PasswordHash -notmatch '^0x[0-9A-Fa-f]+$') {
            Stop-Function -Message 'PasswordHash must be in hexadecimal format starting with 0x' -Target $Login -Continue -FunctionName Set-DbaLogin
        }

        if ($__securePasswordBound) {
            switch ($SecurePassword.GetType().Name) {
                'PSCredential' { $NewSecurePassword = $SecurePassword.Password }
                'SecureString' { $NewSecurePassword = $SecurePassword }
                default {
                    Stop-Function -Message 'Password must be a PSCredential or SecureString' -Target $Login -FunctionName Set-DbaLogin
                }
            }
        }

        if (($__unlockBound) -and (-not $__securePasswordBound) -and (-not $__forceBound)) {
            Stop-Function -Message 'You must specify a password when using the -Unlock parameter or use the -Force parameter. See the help documentation for this command.' -FunctionName Set-DbaLogin
        }

        if (($__passwordMustChangeBound) -and (-not $__securePasswordBound)) {
            Stop-Function -Message 'You must specify a password when using the -PasswordMustChange parameter. See the command help for more details.' -FunctionName Set-DbaLogin
        }
    }

    [pscustomobject]@{ __SetDbaLoginBeginComplete = $true; NewSecurePassword = $NewSecurePassword; Interrupted = (Test-FunctionInterrupt) }
} $Login $SecurePassword $PasswordHash $NewName $EnableException $__sqlInstanceBound $__loginBound $__securePasswordBound $__passwordHashBound $__defaultDatabaseBound $__unlockBound $__passwordMustChangeBound $__newNameBound $__disableBound $__enableBound $__denyLoginBound $__grantLoginBound $__passwordPolicyEnforcedBound $__passwordExpirationEnabledBound $__forceBound $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM, now STREAMED per record (DEF-014).
    private const string ProcessScript = """
param($InputObject, $SqlInstance, $SqlCredential, $Login, $SecurePassword, $PasswordHash, $DefaultDatabase, $Unlock, $PasswordMustChange, $NewName, $Disable, $Enable, $DenyLogin, $GrantLogin, $PasswordPolicyEnforced, $PasswordExpirationEnabled, $AddRole, $RemoveRole, $Force, $EnableException, $__realCmdlet, $NewSecurePassword, $__carryState, $__sqlInstanceBound, $__loginBound, $__securePasswordBound, $__passwordHashBound, $__defaultDatabaseBound, $__unlockBound, $__passwordMustChangeBound, $__newNameBound, $__disableBound, $__enableBound, $__denyLoginBound, $__grantLoginBound, $__passwordPolicyEnforcedBound, $__passwordExpirationEnabledBound, $__forceBound, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Microsoft.SqlServer.Management.Smo.Login[]]$InputObject, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Login, $SecurePassword, [string]$PasswordHash, [string]$DefaultDatabase, $Unlock, $PasswordMustChange, [string]$NewName, $Disable, $Enable, $DenyLogin, $GrantLogin, $PasswordPolicyEnforced, $PasswordExpirationEnabled, [string[]]$AddRole, [string[]]$RemoveRole, $Force, $EnableException, $__realCmdlet, $NewSecurePassword, $__carryState, $__sqlInstanceBound, $__loginBound, $__securePasswordBound, $__passwordHashBound, $__defaultDatabaseBound, $__unlockBound, $__passwordMustChangeBound, $__newNameBound, $__disableBound, $__enableBound, $__denyLoginBound, $__grantLoginBound, $__passwordPolicyEnforcedBound, $__passwordExpirationEnabledBound, $__forceBound, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # DEF-014: this port STREAMS per record (source is begin/process, no end block). The shared scope the
    # single end-hop provided is reconstructed by carrying process state; finally so the interrupt gate's
    # early return cannot skip the handoff.
    if ($__carryState) { foreach ($__k in $__carryState.Keys) { Set-Variable -Name $__k -Value $__carryState[$__k] } }
    try {
        if (Test-FunctionInterrupt) { return }

        $allLogins = @{ }
        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9 -AzureUnsupported
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaLogin
            }
            $allLogins[$instance.ToString()] = Get-DbaLogin -SqlInstance $server
            $InputObject += $allLogins[$instance.ToString()] | Where-Object { ($_.Name -in $Login) -and ($_.Name -notlike '##*') }
        }

        # Loop through all the logins
        foreach ($l in $InputObject) {
            if ($__realCmdlet.ShouldProcess($l, "Setting Changes to Login on $($l.Parent.Name)")) {
                $server = $l.Parent

                # Create the notes
                $notes = @()

                # caller wants to unlock a login without a password and has specified the -Force param
                if (($__unlockBound) -and (-not $__securePasswordBound) -and ($__forceBound)) {
                    if (-not $l.IsLocked) {
                        Write-Message -Message "Login $l is not locked" -Level Warning -FunctionName Set-DbaLogin -ModuleName "dbatools"
                    } else {
                        try {
                            # save the current state of the policy options for check_policy and check_expiration
                            $checkPolicy = $l.PasswordPolicyEnforced
                            $checkExpiration = $l.PasswordExpirationEnabled

                            # alter the login to switch off the check_policy and check_expiration. Ref: https://www.mssqltips.com/sqlservertip/2758/how-to-unlock-a-sql-login-without-resetting-the-password/
                            $l.PasswordPolicyEnforced = $false
                            $l.PasswordExpirationEnabled = $false
                            $l.Alter()

                            # restore the settings immediately
                            $l.PasswordPolicyEnforced = $checkPolicy
                            $l.PasswordExpirationEnabled = $checkExpiration
                            $l.Alter()

                            # out of an abundance of caution let's refresh the login and double check the settings to see if they match what they were before
                            $l.Refresh()

                            if ($checkPolicy -ne $l.PasswordPolicyEnforced) {
                                Stop-Function -Message "Unable to restore the check_policy setting for $l" -Target $l -Continue -FunctionName Set-DbaLogin
                            }

                            if ($checkExpiration -ne $l.PasswordExpirationEnabled) {
                                Stop-Function -Message "Unable to restore the check_expiration setting for $l" -Target $l -Continue -FunctionName Set-DbaLogin
                            }
                        } catch {
                            $notes += "Unable to unlock"
                            Stop-Function -Message "Unable to unlock $l. Review the 'Enforce password policy' and 'Enforce password expiration' settings for $l" -Target $l -ErrorRecord $_ -Continue -FunctionName Set-DbaLogin
                        }
                    }
                }

                # Change the name
                if ($__newNameBound) {
                    # Check if the new name doesn't already exist
                    if ($allLogins[$server.Name].Name -notcontains $NewName) {
                        try {
                            $l.Rename($NewName)
                        } catch {
                            $notes += "Couldn't rename login"
                            Stop-Function -Message "Something went wrong changing the name for $l" -Target $l -ErrorRecord $_ -Continue -FunctionName Set-DbaLogin
                        }
                    } else {
                        $notes += 'New login name already exists'
                        Write-Message -Message "New login name $NewName already exists on $instance" -Level Verbose -FunctionName Set-DbaLogin -ModuleName "dbatools"
                    }
                }

                # Disable the login
                if ($__disableBound) {
                    if ($l.IsDisabled) {
                        Write-Message -Message "Login $l is already disabled" -Level Verbose -FunctionName Set-DbaLogin -ModuleName "dbatools"
                    } else {
                        try {
                            $l.Disable()
                        } catch {
                            $notes += "Couldn't disable login"
                            Stop-Function -Message "Something went wrong disabling $l" -Target $l -ErrorRecord $_ -Continue -FunctionName Set-DbaLogin
                        }
                    }
                }

                # Enable the login
                if ($__enableBound) {
                    if (-not $l.IsDisabled) {
                        Write-Message -Message "Login $l is already enabled" -Level Verbose -FunctionName Set-DbaLogin -ModuleName "dbatools"
                    } else {
                        try {
                            $l.Enable()
                        } catch {
                            $notes += "Couldn't enable login"
                            Stop-Function -Message "Something went wrong enabling $l" -Target $l -ErrorRecord $_ -Continue -FunctionName Set-DbaLogin
                        }
                    }
                }

                # Deny access
                if ($__denyLoginBound) {
                    if ($l.DenyWindowsLogin) {
                        Write-Message -Message "Login $l already has login access denied" -Level Verbose -FunctionName Set-DbaLogin -ModuleName "dbatools"
                    } else {
                        $l.DenyWindowsLogin = $true
                    }
                }

                # Grant access
                if ($__grantLoginBound) {
                    if (-not $l.DenyWindowsLogin) {
                        Write-Message -Message "Login $l already has login access granted" -Level Verbose -FunctionName Set-DbaLogin -ModuleName "dbatools"
                    } else {
                        $l.DenyWindowsLogin = $false
                    }
                }

                # Enforce password policy
                if ($__passwordPolicyEnforcedBound) {
                    if ($l.PasswordPolicyEnforced -eq $PasswordPolicyEnforced) {
                        Write-Message -Message "Login $l password policy is already set to $($l.PasswordPolicyEnforced)" -Level Verbose -FunctionName Set-DbaLogin -ModuleName "dbatools"
                    } else {
                        $l.PasswordPolicyEnforced = $PasswordPolicyEnforced
                    }
                }

                # Enforce password expiration
                if ($__passwordExpirationEnabledBound) {

                    if ($PasswordExpirationEnabled -and $l.PasswordPolicyEnforced -eq $false) {
                        $notes += "Couldn't set check_expiration = ON because check_policy = OFF for $l. See the command description for more details on these settings."
                        Stop-Function -Message "Couldn't set check_expiration = ON because check_policy = OFF for $l. See the command description for more details on these settings." -Target $l -Continue -FunctionName Set-DbaLogin
                    }

                    if ($l.PasswordExpirationEnabled -eq $PasswordExpirationEnabled) {
                        Write-Message -Message "Login $l password expiration check is already set to $($l.PasswordExpirationEnabled)" -Level Verbose -FunctionName Set-DbaLogin -ModuleName "dbatools"
                    } else {
                        $l.PasswordExpirationEnabled = $PasswordExpirationEnabled
                    }
                }

                # Add server roles to login
                if ($AddRole) {
                    # Loop through each of the roles
                    foreach ($role in $AddRole) {
                        try {
                            $l.AddToRole($role)
                        } catch {
                            $notes += "Couldn't add role $role"
                            Stop-Function -Message "Something went wrong adding role $role to $l" -Target $l -ErrorRecord $_ -Continue -FunctionName Set-DbaLogin
                        }
                    }
                }

                # Remove server roles from login
                if ($RemoveRole) {
                    # Loop through each of the roles
                    foreach ($role in $RemoveRole) {
                        try {
                            $server.Roles[$role].DropMember($l.Name)
                        } catch {
                            $notes += "Couldn't remove role $role"
                            Stop-Function -Message "Something went wrong removing role $role to $l" -Target $l -ErrorRecord $_ -Continue -FunctionName Set-DbaLogin
                        }
                    }
                }

                # Set the default database
                if ($__defaultDatabaseBound) {
                    if ($l.DefaultDatabase -eq $DefaultDatabase) {
                        Write-Message -Message "Login $l default database is already set to $($l.DefaultDatabase)" -Level Verbose -FunctionName Set-DbaLogin -ModuleName "dbatools"
                    } else {
                        $l.DefaultDatabase = $DefaultDatabase
                    }
                }

                # Alter the login to make the changes
                $l.Alter()
                $l.Refresh()

                # Change the password after the Alter() because the must_change requires the policy settings to be enabled first.
                if ($__securePasswordBound) {
                    if ($__passwordMustChangeBound) {
                        # Validate if the check_policy and check_expiration options are enabled on the login. These are required for the must_change option for alter login.
                        if ((-not $l.PasswordPolicyEnforced) -or (-not $l.PasswordExpirationEnabled)) {
                            Stop-Function -Message "Unable to change the password and set the must_change option for $l because check_policy = $($l.PasswordPolicyEnforced) and check_expiration = $($l.PasswordExpirationEnabled). See the command help for additional information on the -MustChange parameter." -Target $l -Continue -FunctionName Set-DbaLogin
                        }
                    }

                    try {
                        $l.ChangePassword($NewSecurePassword, $Unlock, $PasswordMustChange)
                        $passwordChanged = $true

                        if ($__passwordMustChangeBound) {
                            $l.Refresh()  # necessary so that the read only property PasswordMustChange is updated
                        }
                    } catch {
                        $notes += "Couldn't change password"
                        $passwordChanged = $false
                        Stop-Function -Message "Something went wrong changing the password for $l" -Target $l -ErrorRecord $_ -Continue -FunctionName Set-DbaLogin
                    }
                }

                # Change the password using a hash value
                if ($__passwordHashBound) {
                    # Verify this is a SQL login
                    if ($l.LoginType -ne "SqlLogin") {
                        $notes += "Cannot set password hash on non-SQL login"
                        Stop-Function -Message "Login $l is not a SQL Server login. Password hash can only be set on SQL Server authentication logins." -Target $l -Continue -FunctionName Set-DbaLogin
                    }

                    try {
                        $loginName = $l.Name.Replace("'", "''")
                        $sql = "ALTER LOGIN [$loginName] WITH PASSWORD = $PasswordHash HASHED"
                        $null = $server.Query($sql)
                        $passwordChanged = $true
                        $l.Refresh()
                    } catch {
                        $notes += "Couldn't set password hash"
                        $passwordChanged = $false
                        Stop-Function -Message "Something went wrong setting the password hash for $l" -Target $l -ErrorRecord $_ -Continue -FunctionName Set-DbaLogin
                    }
                }

                # Retrieve the server roles for the login
                $roles = Get-DbaServerRoleMember -SqlInstance $server | Where-Object { $_.Name -eq $l.Name }

                # Check if there were any notes to include in the results
                if ($notes) {
                    $notes = $notes | Get-Unique
                    $notes = $notes -Join ';'
                } else {
                    $notes = $null
                }
                $rolenames = $roles.Role | Select-Object -Unique

                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name PasswordChanged -Value $passwordChanged
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name ServerRole -Value ($rolenames -join ', ')
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name Notes -Value $notes

                # backwards compatibility: LoginName, DenyLogin
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name LoginName -Value $l.Name
                Add-Member -Force -InputObject $l -MemberType NoteProperty -Name DenyLogin -Value $l.DenyWindowsLogin

                $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'DenyLogin', 'IsDisabled', 'IsLocked',
                'PasswordPolicyEnforced', 'PasswordExpirationEnabled', 'MustChangePassword', 'PasswordChanged', 'ServerRole', 'Notes'

                Select-DefaultView -InputObject $l -Property $defaults
            }
        }
    } finally {
    [pscustomobject]@{ __SetDbaLoginProcessComplete = $true; Interrupted = (Test-FunctionInterrupt); State = @{ allLogins = $allLogins; checkExpiration = $checkExpiration; checkPolicy = $checkPolicy; defaults = $defaults; loginName = $loginName; notes = $notes; passwordChanged = $passwordChanged; rolenames = $rolenames; roles = $roles; server = $server; sql = $sql } }
    }
} $InputObject $SqlInstance $SqlCredential $Login $SecurePassword $PasswordHash $DefaultDatabase $Unlock $PasswordMustChange $NewName $Disable $Enable $DenyLogin $GrantLogin $PasswordPolicyEnforced $PasswordExpirationEnabled $AddRole $RemoveRole $Force $EnableException $__realCmdlet $NewSecurePassword $__carryState $__sqlInstanceBound $__loginBound $__securePasswordBound $__passwordHashBound $__defaultDatabaseBound $__unlockBound $__passwordMustChangeBound $__newNameBound $__disableBound $__enableBound $__denyLoginBound $__grantLoginBound $__passwordPolicyEnforcedBound $__passwordExpirationEnabledBound $__forceBound $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
