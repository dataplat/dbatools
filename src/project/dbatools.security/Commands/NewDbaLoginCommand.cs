#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates SQL Server login accounts, including password, certificate, and asymmetric-key logins.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the login creation, the SID
/// and password handling, the rename hashtable, the ShouldProcess gates, the emitted login objects, and
/// dbatools stream and error handling stay observable-identical to the script implementation.
/// </para>
/// <para>
/// The script's begin block MUTATES two parameters that its process block then reads: $Sid is validated
/// character by character and converted with Convert-HexStringToByte, and $HashedPassword is converted when
/// it arrives as a byte array. Neither is pipeline-bound, so in the function world those conversions happen
/// ONCE and every record sees the converted values. Begin therefore runs once in BeginProcessing and hands
/// both back through a sentinel into fields that thread into each record's process hop. The same sentinel
/// carries the dbatools interrupt latch: the begin block's SID validation calls Stop-Function with no
/// -Continue and returns, and the process block reads Test-FunctionInterrupt, so without the carry every
/// record after the first would re-run instead of returning (DEF-011). The -Force ConfirmPreference fold
/// rides at the top of the process hop, where the two ShouldProcess gates read it at call time.
/// </para>
/// <para>
/// FOUR pre-existing defects are PRESERVED verbatim under the coordinator's 2026-07-19 dossier ruling,
/// each a deliberate decision rather than an oversight:
/// the dead byte-array branch on $HashedPassword (the parameter is [string], so the binder stringifies any
/// byte[] before the type check runs); the DBNull that a null password column sends into
/// Convert-ByteToHexString's [byte[]] binder, which throws - measured identical in both editions, and
/// reproduced by construction because the hop makes that call verbatim in module scope; the character-set
/// TrimStart that silently destroys leading zero bytes in a string SID (upstream U-7); and the all-zero SID
/// hex that strips to empty and dies with a raw exception escaping begin, bypassing the -EnableException
/// contract (upstream U-8). Reproducing a source breach is the port's job; fixing it belongs upstream.
/// </para>
/// <para>
/// The command streams through InvokeScopedStreaming: it emits per login and a later login can raise a
/// terminating -EnableException failure, so a buffered call would discard the logins already created and
/// reported (DEF-001). The SecureString rides live and is flattened only by the source's own conversions
/// inside the ShouldProcess gate.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaLogin", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Password")]
public sealed class NewDbaLoginCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The login names to create.</summary>
    [Parameter(ParameterSetName = "Password", Position = 2)]
    [Parameter(ParameterSetName = "PasswordHash")]
    [Parameter(ParameterSetName = "MapToCertificate")]
    [Parameter(ParameterSetName = "MapToAsymmetricKey")]
    [Alias("LoginName", "Name")]
    [PsStringArrayCast]
    public string[]? Login { get; set; }

    /// <summary>Login objects to copy, from Get-DbaLogin.</summary>
    /// <remarks>
    /// Declared in every named set as well as pipeline-bound: the script's bare [parameter(ValueFromPipeline)]
    /// surfaces as a member of all four sets, and a bare [Parameter] here would drop that membership.
    /// </remarks>
    [Parameter(ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

    /// <summary>The password for a SQL login.</summary>
    [Parameter(ParameterSetName = "Password", Position = 3)]
    [Alias("Password")]
    public System.Security.SecureString? SecurePassword { get; set; }

    /// <summary>A hashed password value (0x...) for a SQL login.</summary>
    [Parameter(ParameterSetName = "PasswordHash")]
    [Alias("Hash", "PasswordHash")]
    [PsStringCast]
    public string? HashedPassword { get; set; }

    /// <summary>Creates the login mapped to this certificate.</summary>
    [Parameter(ParameterSetName = "MapToCertificate")]
    [PsStringCast]
    public string? MapToCertificate { get; set; }

    /// <summary>Creates the login mapped to this asymmetric key.</summary>
    [Parameter(ParameterSetName = "MapToAsymmetricKey")]
    [PsStringCast]
    public string? MapToAsymmetricKey { get; set; }

    /// <summary>Maps the login to this credential.</summary>
    [Parameter]
    [PsStringCast]
    public string? MapToCredential { get; set; }

    /// <summary>The SID for the new login, as a byte array or a 0x-prefixed string.</summary>
    [Parameter]
    public object? Sid { get; set; }

    /// <summary>The default database for the login.</summary>
    [Parameter(ParameterSetName = "Password")]
    [Parameter(ParameterSetName = "PasswordHash")]
    [Alias("DefaultDB")]
    [PsStringCast]
    public string? DefaultDatabase { get; set; }

    /// <summary>The default language for the login.</summary>
    [Parameter(ParameterSetName = "Password")]
    [Parameter(ParameterSetName = "PasswordHash")]
    [PsStringCast]
    public string? Language { get; set; }

    /// <summary>Enables password expiration checking.</summary>
    [Parameter(ParameterSetName = "Password")]
    [Parameter(ParameterSetName = "PasswordHash")]
    [Alias("CheckExpiration", "Expiration")]
    public SwitchParameter PasswordExpirationEnabled { get; set; }

    /// <summary>Enforces the Windows password policy.</summary>
    [Parameter(ParameterSetName = "Password")]
    [Parameter(ParameterSetName = "PasswordHash")]
    [Alias("CheckPolicy", "Policy")]
    public SwitchParameter PasswordPolicyEnforced { get; set; }

    /// <summary>Requires the password to change at next login.</summary>
    [Parameter(ParameterSetName = "Password")]
    [Alias("MustChange")]
    public SwitchParameter PasswordMustChange { get; set; }

    /// <summary>Creates the login disabled.</summary>
    [Parameter]
    [Alias("Disable")]
    public SwitchParameter Disabled { get; set; }

    /// <summary>Denies the login permission to connect.</summary>
    [Parameter]
    public SwitchParameter DenyWindowsLogin { get; set; }

    /// <summary>Generates a new SID rather than reusing the source login's.</summary>
    [Parameter]
    public SwitchParameter NewSid { get; set; }

    /// <summary>Creates the login from an external (Azure AD) provider.</summary>
    [Parameter]
    public SwitchParameter ExternalProvider { get; set; }

    /// <summary>Renames logins as they are created, keyed by source name.</summary>
    [Parameter]
    [Alias("Rename")]
    public Hashtable? LoginRenameHashtable { get; set; }

    /// <summary>Drops and recreates an existing login of the same name.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Set when the begin block latched the dbatools interrupt.</summary>
    private bool _beginInterrupted;

    /// <summary>$Sid and $HashedPassword as the begin block left them, read by every record.</summary>
    private object? _sidState;
    private object? _hashedPasswordState;

    /// <summary>
    /// The PROCESS block's own cross-record state.
    /// </summary>
    /// <remarks>
    /// The script's process block runs in ONE function scope for the whole pipeline, so values it
    /// assigns survive into later records. Three distinct leaks depend on that and a per-record hop
    /// would silently reset all of them:
    /// $SecurePassword is MUTATED when the body prompts for a password, so the script prompts ONCE and
    /// reuses that password for every later record - a per-record hop re-prompts and can create logins
    /// with different passwords. The $current* family is reset at the top of the plain-name branch, but
    /// that reset list deliberately OMITS $currentPasswordMustChange and $currentHashedPassword, and the
    /// SMO-login branch has no reset at all, so a value read off one source login carries onto a later
    /// one. And $currentCredential is assigned only when EnumCredentials() is non-empty, so a credential
    /// from one record stays active for a following login that has none. All of it is carried.
    /// </remarks>
    private object? _securePasswordState;
    private Hashtable? _processState;

    /// <summary>Set once the PROCESS block latches the dbatools interrupt (the script's line-267 gate).</summary>
    private bool _processInterrupted;

    /// <summary>Runs the begin block once and captures the values and latch it produced.</summary>
    protected override void BeginProcessing()
    {
        _sidState = Sid;
        _hashedPasswordState = HashedPassword;
        _securePasswordState = SecurePassword;

        // [DEF-001] streamed via InvokeScopedStreaming (B FINAL-CERT ruling): the begin body can emit
        // before a reachable terminating throw (Stop-Function -EnableException on an invalid Sid char),
        // so a buffered InvokeScoped could lose an earlier emit. Streaming yields each record as
        // produced. Const body byte-unchanged; the __NewDbaLoginBeginComplete sentinel still rides the
        // callback and is harvested into _sidState/_hashedPasswordState/_beginInterrupted as before.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__NewDbaLoginBeginComplete"]?.Value))
            {
                _sidState = UnwrapHopValue(item.Properties["Sid"]?.Value);
                _hashedPasswordState = UnwrapHopValue(item.Properties["HashedPassword"]?.Value);
                _beginInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
                return;
            }
            if (item is not null)
            {
                WriteObject(item);
            }
        }, BeginScript,
            Force.ToBool(), Sid, HashedPassword, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    /// <summary>Creates the logins for the current record.</summary>
    protected override void ProcessRecord()
    {
        // The script's process block opens with `if (Test-FunctionInterrupt) { return }`, so once ANY
        // record latches the interrupt every later record returns immediately. In-hop Stop-Function
        // cannot set DbaBaseCmdlet.Interrupted (DEF-011), so the latch is carried out of each hop and
        // short-circuited here instead.
        if (_beginInterrupted || _processInterrupted || Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && item.BaseObject is PSCustomObject && LanguagePrimitives.IsTrue(
                item.Properties["__NewDbaLoginProcessComplete"]?.Value))
            {
                _securePasswordState = UnwrapHopValue(item.Properties["SecurePassword"]?.Value);
                _processState = UnwrapHopValue(item.Properties["State"]?.Value) as Hashtable;
                _processInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Login, _securePasswordState, _hashedPasswordState, MapToCertificate,
            MapToAsymmetricKey, MapToCredential, _sidState, DefaultDatabase, Language,
            PasswordExpirationEnabled.ToBool(), PasswordPolicyEnforced.ToBool(), PasswordMustChange.ToBool(),
            Disabled.ToBool(), DenyWindowsLogin.ToBool(), NewSid.ToBool(), ExternalProvider.ToBool(),
            InputObject, LoginRenameHashtable, Force.ToBool(), EnableException.ToBool(), this,
            TestBound(nameof(DenyWindowsLogin)),
            // The body reads $PsCmdlet.ParameterSetName and $PSBoundParameters DIRECTLY. Inside the hop
            // both belong to the INNER scriptblock rather than to this cmdlet: that scriptblock declares
            // no parameter sets (so ParameterSetName is always __AllParameterSets) and every parameter is
            // passed to it positionally (so EVERY key counts as bound). The caller's real values are
            // therefore carried in explicitly.
            ParameterSetName,
            TestBound(nameof(PasswordExpirationEnabled)), TestBound(nameof(PasswordPolicyEnforced)),
            TestBound(nameof(PasswordMustChange)), TestBound(nameof(MapToAsymmetricKey)),
            TestBound(nameof(MapToCertificate)), TestBound(nameof(MapToCredential)),
            TestBound(nameof(Disabled)),
            _processState,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    /// <summary>
    /// Unwraps a value the begin hop carried out through its sentinel.
    /// </summary>
    /// <remarks>
    /// A value the script left unset arrives as AutomationNull, which behaves as $null in PowerShell but
    /// unwraps to a truthy, property-less object - so it comes back as null instead. Otherwise the value is
    /// unwrapped ONLY when the wrapper adds nothing: note properties live on the PSObject wrapper rather
    /// than the BaseObject, so unwrapping such a value silently discards them.
    /// </remarks>
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

    // PS: the begin block VERBATIM inside a dot-sourced block so its early return stays local and the
    // trailing sentinel still runs. The sentinel returns $Sid and $HashedPassword as begin left them,
    // plus the interrupt latch, so the process hop sees exactly what the script's function scope holds.
    private const string BeginScript = """
param($Force, $Sid, $HashedPassword, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($Force, $Sid, $HashedPassword, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if ($Force) { $ConfirmPreference = 'none' }

        if ($Sid) {
            if ($Sid.GetType().Name -ne 'Byte[]') {
                foreach ($symbol in $Sid.TrimStart("0x").ToCharArray()) {
                    if ($symbol -notin "0123456789ABCDEF".ToCharArray()) {
                        Stop-Function -Message "Sid has invalid character '$symbol', cannot proceed." -Category InvalidArgument -EnableException $EnableException -FunctionName New-DbaLogin
                        return
                    }
                }
                $Sid = Convert-HexStringToByte $Sid
            }
        }

        if ($HashedPassword) {
            if ($HashedPassword.GetType().Name -eq 'Byte[]') {
                $HashedPassword = Convert-ByteToHexString $HashedPassword
            }
        }
    }

    [pscustomobject]@{ __NewDbaLoginBeginComplete = $true; Sid = $Sid; HashedPassword = $HashedPassword; Interrupted = (Test-FunctionInterrupt) }
} $Force $Sid $HashedPassword $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";

    // PS: the process body VERBATIM, with the begin block's -Force ConfirmPreference fold at the top where
    // the ShouldProcess gates read it. Substitutions only: $Pscmdlet -> $__realCmdlet (2 gates); the single
    // Test-Bound read -> the carried by-name flag; -FunctionName on the 13 DIRECT Stop-Function calls;
    // -FunctionName + -ModuleName "dbatools" on the 18 DIRECT Write-Message calls. $Sid and
    // $HashedPassword arrive already converted by the begin hop.
    private const string ProcessScript = """



param($SqlInstance, $SqlCredential, $Login, $SecurePassword, $HashedPassword, $MapToCertificate, $MapToAsymmetricKey, $MapToCredential, $Sid, $DefaultDatabase, $Language, $PasswordExpirationEnabled, $PasswordPolicyEnforced, $PasswordMustChange, $Disabled, $DenyWindowsLogin, $NewSid, $ExternalProvider, $InputObject, $LoginRenameHashtable, $Force, $EnableException, $__realCmdlet, $__denyWindowsLoginBound, $__parameterSetName, $__boundPasswordExpirationEnabled, $__boundPasswordPolicyEnforced, $__boundPasswordMustChange, $__boundMapToAsymmetricKey, $__boundMapToCertificate, $__boundMapToCredential, $__boundDisabled, $__carryState, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param($SqlInstance, $SqlCredential, $Login, $SecurePassword, $HashedPassword, $MapToCertificate, $MapToAsymmetricKey, $MapToCredential, $Sid, $DefaultDatabase, $Language, $PasswordExpirationEnabled, $PasswordPolicyEnforced, $PasswordMustChange, $Disabled, $DenyWindowsLogin, $NewSid, $ExternalProvider, $InputObject, $LoginRenameHashtable, $Force, $EnableException, $__realCmdlet, $__denyWindowsLoginBound, $__parameterSetName, $__boundPasswordExpirationEnabled, $__boundPasswordPolicyEnforced, $__boundPasswordMustChange, $__boundMapToAsymmetricKey, $__boundMapToCertificate, $__boundMapToCredential, $__boundDisabled, $__carryState, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # The begin block's -Force fold rides at process-hop top, where the ShouldProcess gates read it.
    if ($Force) { $ConfirmPreference = 'none' }

    # PROCESS-scope cross-record state as the previous record left it. The script's process block is ONE
    # function scope for the whole pipeline, so these survive between records; a per-record hop would
    # reset them. The body's own resets still run exactly where the source runs them.
    if ($__carryState) { foreach ($__k in $__carryState.Keys) { Set-Variable -Name $__k -Value $__carryState[$__k] } }

    # try/finally, NOT a plain trailing line: the body contains RETURN statements (the no-logins
    # guard, and the line-267 interrupt gate). A return exits this scriptblock immediately and would
    # skip a trailing sentinel, so the interrupt latch would never reach the cmdlet and the NEXT
    # record would run - exactly the divergence codex reproduced. finally always runs.
    try {

        if (Test-FunctionInterrupt) { return }

        #At least one of those should be specified
        if (!($Login -or $InputObject)) {
            Stop-Function -Message "No logins have been specified." -Category InvalidArgument -EnableException $EnableException -FunctionName New-DbaLogin
            Return
        }

        if ($PasswordMustChange -and (-not $SecurePassword)) {
            Stop-Function -Message "You need to specified -SecurePassword when using -PasswordMustChange parameter." -Category InvalidArgument -EnableException $EnableException -FunctionName New-DbaLogin
            Return
        }

        $loginCollection = @()
        if ($InputObject) {
            $loginCollection += $InputObject
            if ($Login) {
                Stop-Function -Message "Parameter -Login is not supported when processing objects from -InputObject. If you need to rename the logins, please use -LoginRenameHashtable." -Category InvalidArgument -EnableException $EnableException -FunctionName New-DbaLogin
                Return
            }
        } else {
            $loginCollection += $Login
        }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaLogin
            }

            foreach ($loginItem in $loginCollection) {
                $usedTsql = $false
                #check if $loginItem is an SMO Login object
                if ($loginItem.GetType().Name -eq 'Login') {
                    #Get all the necessary fields
                    $loginName = $loginItem.Name
                    $loginType = $loginItem.LoginType
                    $currentSid = $loginItem.Sid
                    $currentDefaultDatabase = $loginItem.DefaultDatabase
                    $currentLanguage = $loginItem.Language
                    $currentPasswordExpirationEnabled = $loginItem.PasswordExpirationEnabled
                    $currentPasswordPolicyEnforced = $loginItem.PasswordPolicyEnforced
                    $currentPasswordMustChange = $loginItem.MustChangePassword
                    $currentDisabled = $loginItem.IsDisabled
                    $currentDenyWindowsLogin = $loginItem.DenyWindowsLogin
                    #Get previous password
                    if ($loginType -eq 'SqlLogin' -and !($SecurePassword -or $HashedPassword)) {
                        $sourceServer = $loginItem.Parent
                        switch ($sourceServer.versionMajor) {
                            0 { $sql = "SELECT CONVERT(VARBINARY(256),password) AS hashedpass FROM master.dbo.syslogins WHERE loginname='$loginName'" }
                            8 { $sql = "SELECT CONVERT(VARBINARY(256),password) AS hashedpass FROM dbo.syslogins WHERE name='$loginName'" }
                            9 { $sql = "SELECT CONVERT(VARBINARY(256),password_hash) AS hashedpass FROM sys.sql_logins WHERE name='$loginName'" }
                            default {
                                $sql = "SELECT CAST(CONVERT(VARCHAR(256), CAST(LOGINPROPERTY(name,'PasswordHash')
                                    AS VARBINARY(256)), 1) AS NVARCHAR(MAX)) AS hashedpass
                                    FROM sys.server_principals
                                    WHERE principal_id = $($loginItem.id)"
                            }
                        }

                        try {
                            $hashedPass = $sourceServer.ConnectionContext.ExecuteScalar($sql)
                        } catch {
                            $hashedPassDt = $sourceServer.Databases['master'].ExecuteWithResults($sql)
                            $hashedPass = $hashedPassDt.Tables[0].Rows[0].Item(0)
                        }

                        if ($hashedPass.GetType().Name -ne "String") {
                            $hashedPass = Convert-ByteToHexString $hashedPass
                        }
                        $currentHashedPassword = $hashedPass
                    }

                    #Get cryptography and attached credentials
                    if ($loginType -eq 'AsymmetricKey') {
                        $currentAsymmetricKey = $loginItem.AsymmetricKey
                    }
                    if ($loginType -eq 'Certificate') {
                        $currentCertificate = $loginItem.Certificate
                    }
                    #This method or property is accessible only while working with SQL Server 2008 or later.
                    if ($sourceServer.versionMajor -gt 9) {
                        if ($loginItem.EnumCredentials()) {
                            $currentCredential = $loginItem.EnumCredentials()
                        }
                    }
                } else {
                    $loginName = $loginItem
                    $currentSid = $currentDefaultDatabase = $currentLanguage = $currentPasswordExpirationEnabled = $currentAsymmetricKey = $currentCertificate = $currentCredential = $currentDisabled = $currentPasswordPolicyEnforced = $currentDenyWindowsLogin = $null

                    if ($__parameterSetName -eq "MapToCertificate") { $loginType = 'Certificate' }
                    elseif ($__parameterSetName -eq "MapToAsymmetricKey") { $loginType = 'AsymmetricKey' }
                    elseif ($ExternalProvider) { $loginType = 'ExternalUser' } # Before 'SqlLogin' check otherwise will assume it's a SqlLogin and will rquest pwd
                    elseif ($loginItem.IndexOf('\') -eq -1) { $loginType = 'SqlLogin' }
                    else { $loginType = 'WindowsUser' }
                }

                if ((-not $server.IsAzure) -and ($server.LoginMode -ne [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed) -and ($loginType -eq 'SqlLogin')) {
                    Write-Message -Level Warning -Message "$instance does not have Mixed Mode enabled. [$loginName] is an SQL Login. Enable mixed mode authentication after the migration completes to use this type of login." -FunctionName New-DbaLogin -ModuleName "dbatools"
                }

                if ($Sid) {
                    $currentSid = $Sid
                }
                if ($DefaultDatabase) {
                    $currentDefaultDatabase = $DefaultDatabase
                }
                if ($Language) {
                    $currentLanguage = $Language
                }
                if ($__boundPasswordExpirationEnabled) {
                    $currentPasswordExpirationEnabled = $PasswordExpirationEnabled
                }
                if ($__boundPasswordPolicyEnforced) {
                    $currentPasswordPolicyEnforced = $PasswordPolicyEnforced
                }
                if ($__boundPasswordMustChange) {
                    $currentPasswordMustChange = $PasswordMustChange
                    # Enforce Expiration and Policy properties as they are needed when we want to use "Must Change" property
                    Write-Message -Level Verbose -Message "Forcing 'Expiration' and 'Policy' properties to 'ON' because MustChange was specified." -FunctionName New-DbaLogin -ModuleName "dbatools"
                    $currentPasswordExpirationEnabled = $true
                    $currentPasswordPolicyEnforced = $true
                }
                if ($__boundMapToAsymmetricKey) {
                    $currentAsymmetricKey = $MapToAsymmetricKey
                }
                if ($__boundMapToCertificate) {
                    $currentCertificate = $MapToCertificate
                }
                if ($__boundMapToCredential) {
                    $currentCredential = $MapToCredential
                }
                if ($__boundDisabled) {
                    $currentDisabled = $Disabled
                }
                if ($__denyWindowsLoginBound) {
                    $currentDenyWindowsLogin = $DenyWindowsLogin
                }

                #Apply renaming if necessary
                if ($LoginRenameHashtable.Keys -contains $loginName) {
                    $loginName = $LoginRenameHashtable[$loginName]
                }

                #Requesting password if required
                if ($loginItem.GetType().Name -ne 'Login' -and $loginType -eq 'SqlLogin' -and !($SecurePassword -or $HashedPassword)) {
                    $SecurePassword = Read-Host -AsSecureString -Prompt "Enter a new password for the SQL Server login(s)"
                }

                #verify if login exists on the server
                if (($existingLogin = $server.Logins[$loginName])) {
                    if ($force) {
                        if ($__realCmdlet.ShouldProcess($existingLogin, "Dropping existing login $loginName on $instance because -Force was used")) {
                            try {
                                $existingLogin.Drop()
                            } catch {
                                Stop-Function -Message "Could not remove existing login $loginName on $instance, skipping." -Target $loginName -Continue -FunctionName New-DbaLogin
                            }
                        }
                    } else {
                        Stop-Function -Message "Login $loginName already exists on $instance and -Force was not specified" -Target $loginName -Continue -FunctionName New-DbaLogin
                    }
                }


                if ($__realCmdlet.ShouldProcess($SqlInstance, "Creating login $loginName on $instance")) {
                    try {
                        $loginName = $loginName.Replace('[', '').Replace(']', '')
                        $newLogin = New-Object Microsoft.SqlServer.Management.Smo.Login($server, $loginName)
                        $newLogin.LoginType = $loginType

                        $withParams = ""
                        $externalProviderAlterParams = ""

                        if ($loginType -eq 'SqlLogin' -and $currentSid -and !$NewSid) {
                            Write-Message -Level Verbose -Message "Setting $loginName SID" -FunctionName New-DbaLogin -ModuleName "dbatools"
                            $withParams += ", SID = " + (Convert-ByteToHexString $currentSid)
                            $newLogin.Set_Sid($currentSid)
                        }

                        if ($loginType -in ("WindowsUser", "WindowsGroup", "SqlLogin", "ExternalUser", "ExternalGroup")) {
                            if ($currentDefaultDatabase) {
                                Write-Message -Level Verbose -Message "Setting $loginName default database to $currentDefaultDatabase" -FunctionName New-DbaLogin -ModuleName "dbatools"
                                if ($loginType -in ("ExternalUser", "ExternalGroup")) {
                                    $externalProviderAlterParams += ", DEFAULT_DATABASE = [$currentDefaultDatabase]"
                                } else {
                                    $withParams += ", DEFAULT_DATABASE = [$currentDefaultDatabase]"
                                }
                                $newLogin.DefaultDatabase = $currentDefaultDatabase
                            }

                            if ($currentLanguage) {
                                Write-Message -Level Verbose -Message "Setting $loginName language to $currentLanguage" -FunctionName New-DbaLogin -ModuleName "dbatools"
                                if ($loginType -in ("ExternalUser", "ExternalGroup")) {
                                    $externalProviderAlterParams += ", DEFAULT_LANGUAGE = [$currentLanguage]"
                                } else {
                                    $withParams += ", DEFAULT_LANGUAGE = [$currentLanguage]"
                                }
                                $newLogin.Language = $currentLanguage
                            }

                            #CHECK_EXPIRATION: default - OFF
                            if ($currentPasswordExpirationEnabled) {
                                $withParams += ", CHECK_EXPIRATION = ON"
                                $newLogin.PasswordExpirationEnabled = $true
                            } elseif ($loginType -eq 'SqlLogin') {
                                $withParams += ", CHECK_EXPIRATION = OFF"
                                $newLogin.PasswordExpirationEnabled = $false
                            }

                            #CHECK_POLICY: default - ON
                            if ($currentPasswordPolicyEnforced) {
                                $withParams += ", CHECK_POLICY = ON"
                                $newLogin.PasswordPolicyEnforced = $true
                            } elseif ($loginType -eq 'SqlLogin') {
                                $withParams += ", CHECK_POLICY = OFF"
                                $newLogin.PasswordPolicyEnforced = $false
                            }

                            # DENY CONNECT SQL
                            if ($currentDenyWindowsLogin) {
                                Write-Message -Level VeryVerbose -Message "Setting $loginName DenyWindowsLogin to $currentDenyWindowsLogin" -FunctionName New-DbaLogin -ModuleName "dbatools"
                                $newLogin.DenyWindowsLogin = $currentDenyWindowsLogin
                            }

                            #Generate hashed password if necessary
                            if ($SecurePassword) {
                                $currentHashedPassword = Get-PasswordHash $SecurePassword $server.versionMajor
                            } elseif ($HashedPassword) {
                                $currentHashedPassword = $HashedPassword
                            }
                        } elseif ($loginType -eq 'AsymmetricKey') {
                            $newLogin.AsymmetricKey = $currentAsymmetricKey
                        } elseif ($loginType -eq 'Certificate') {
                            $newLogin.Certificate = $currentCertificate
                        }

                        #Add credential
                        if ($currentCredential) {
                            $withParams += ", CREDENTIAL = [$currentCredential]"
                        }

                        Write-Message -Level Verbose -Message "Adding as login type $loginType" -FunctionName New-DbaLogin -ModuleName "dbatools"

                        # Attempt to add login using SMO, then T-SQL
                        try {
                            if ($loginType -in ("WindowsUser", "WindowsGroup", "AsymmetricKey", "Certificate", "ExternalUser", "ExternalGroup")) {
                                if ($withParams) { $withParams = " WITH " + $withParams.TrimStart(',') }
                                $newLogin.Create()
                            } elseif ($loginType -eq "SqlLogin") {
                                $newLogin.Create($currentHashedPassword, [Microsoft.SqlServer.Management.Smo.LoginCreateOptions]::IsHashed)
                            }
                            $newLogin.Refresh()

                            #Adding credential
                            if ($currentCredential) {
                                try {
                                    $newLogin.AddCredential($currentCredential)
                                } catch {
                                    $newLogin.Drop()
                                    Stop-Function -Message "Failed to add $loginName to $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaLogin
                                }
                            }
                            Write-Message -Level Verbose -Message "Successfully added $loginName to $instance." -FunctionName New-DbaLogin -ModuleName "dbatools"
                        } catch {
                            Write-Message -Level Verbose -Message "Failed to create $loginName on $instance using SMO, trying T-SQL." -FunctionName New-DbaLogin -ModuleName "dbatools"
                            try {
                                if ($loginType -eq 'AsymmetricKey') { $sql = "CREATE LOGIN [$loginName] FROM ASYMMETRIC KEY [$currentAsymmetricKey]" }
                                elseif ($loginType -eq 'Certificate') { $sql = "CREATE LOGIN [$loginName] FROM CERTIFICATE [$currentCertificate]" }
                                elseif ($loginType -eq 'SqlLogin' -and $server.DatabaseEngineType -eq 'SqlAzureDatabase') {
                                    # Azure SQL doesn't support HASHED so we have to dump out the plain text password :(
                                    $sql = "CREATE LOGIN [$loginName] WITH PASSWORD = '$($SecurePassword | ConvertFrom-SecurePass)'"
                                } elseif ($loginType -in ('ExternalUser', 'ExternalGroup') -and ($server.DatabaseEngineType -eq 'SqlAzureDatabase' -or $server.DatabaseEngineEdition -eq 'SqlManagedInstance' -or $server.VersionMajor -ge 16)) {
                                    # Azure SQL DB, Azure SQL Managed Instance, and SQL Server 2022+ support FROM EXTERNAL PROVIDER syntax
                                    $sql = "CREATE LOGIN [$loginName] FROM EXTERNAL PROVIDER"
                                } elseif ($loginType -eq 'SqlLogin' ) {
                                    $sql = "CREATE LOGIN [$loginName] WITH PASSWORD = $currentHashedPassword HASHED" + $withParams
                                } else {
                                    $sql = "CREATE LOGIN [$loginName] FROM WINDOWS" + $withParams
                                }
                                $null = $server.Query($sql)
                                $newLogin = $server.logins[$loginName]
                                Write-Message -Level Verbose -Message "Successfully added $loginName to $instance." -FunctionName New-DbaLogin -ModuleName "dbatools"
                                $usedTsql = $true
                            } catch {
                                Stop-Function -Message "Failed to add $loginName to $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaLogin
                            }
                        }

                        if ($usedTsql -and $loginType -in ("ExternalUser", "ExternalGroup") -and $externalProviderAlterParams) {
                            try {
                                $sql = "ALTER LOGIN [$loginName] WITH " + $externalProviderAlterParams.TrimStart(',').Trim()
                                $null = $server.Query($sql)
                                $newLogin = $server.Logins[$loginName]
                            } catch {
                                Stop-Function -Message "Failed to configure $loginName on $instance after creation." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaLogin
                            }
                        }

                        #Process the Disabled property
                        if ($currentDisabled) {
                            try {
                                $newLogin.Disable()
                                Write-Message -Level Verbose -Message "Login $loginName has been disabled on $instance." -FunctionName New-DbaLogin -ModuleName "dbatools"
                            } catch {
                                Write-Message -Level Verbose -Message "Failed to disable $loginName on $instance using SMO, trying T-SQL." -FunctionName New-DbaLogin -ModuleName "dbatools"
                                try {
                                    $sql = "ALTER LOGIN [$loginName] DISABLE"
                                    $null = $server.Query($sql)
                                    Write-Message -Level Verbose -Message "Login $loginName has been disabled on $instance." -FunctionName New-DbaLogin -ModuleName "dbatools"
                                    $usedTsql = $true
                                } catch {
                                    Stop-Function -Message "Failed to disable $loginName on $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaLogin
                                }
                            }
                        }
                        #Process the DenyWindowsLogin property
                        if ($currentDenyWindowsLogin -ne $newLogin.DenyWindowsLogin) {
                            try {
                                $newLogin.DenyWindowsLogin = $currentDenyWindowsLogin
                                $newLogin.Alter()
                                Write-Message -Level Verbose -Message "Login $loginName has been denied from logging in on $instance." -FunctionName New-DbaLogin -ModuleName "dbatools"
                            } catch {
                                Write-Message -Level Verbose -Message "Failed to deny from logging in $loginName on $instance using SMO, trying T-SQL." -FunctionName New-DbaLogin -ModuleName "dbatools"
                                try {
                                    $sql = "DENY CONNECT SQL TO [{0}]" -f $newLogin.Name
                                    $null = $server.Query($sql)
                                    Write-Message -Level Verbose -Message "Login $loginName has been denied from logging in on $instance." -FunctionName New-DbaLogin -ModuleName "dbatools"
                                    $usedTsql = $true
                                } catch {
                                    Stop-Function -Message "Failed to set deny windows login priviledge $loginName on $instance." -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaLogin
                                }
                            }
                        }

                        #Process the MustChangePassword property
                        if ($null -ne $currentPasswordMustChange -and $currentPasswordMustChange -ne $newLogin.MustChangePassword) {
                            try {
                                $newLogin.ChangePassword($SecurePassword, $true, $true)
                                Write-Message -Level Verbose -Message "Login $loginName has been marked as must change password." -FunctionName New-DbaLogin -ModuleName "dbatools"

                                # We need to refresh login after ChangePassword. Otherwise, MustChangePassword will appear as False
                                $server.Logins[$loginName].Refresh()
                            } catch {
                                Write-Message -Level Verbose -Message "Failed to marked as must change password in $loginName on $instance using SMO." -FunctionName New-DbaLogin -ModuleName "dbatools"
                            }
                        }

                        #Display results
                        # If we ever used T-SQL, the smo is some times not up to date and should be refreshed
                        if ($usedTsql) {
                            $server.Logins.Refresh()
                        }

                        Add-TeppCacheItem -SqlInstance $server -Type login -Name $loginName

                        Get-DbaLogin -SqlInstance $server -Login $loginName

                    } catch {
                        Stop-Function -Message "Failed to create login $loginName on $instance." -Target $credential -InnerErrorRecord $_ -Continue -FunctionName New-DbaLogin
                    }
                }
            }
        }
    } finally {
    [pscustomobject]@{ __NewDbaLoginProcessComplete = $true; SecurePassword = $SecurePassword; Interrupted = (Test-FunctionInterrupt); State = @{ currentAsymmetricKey = $currentAsymmetricKey; currentCertificate = $currentCertificate; currentCredential = $currentCredential; currentDefaultDatabase = $currentDefaultDatabase; currentDenyWindowsLogin = $currentDenyWindowsLogin; currentDisabled = $currentDisabled; currentHashedPassword = $currentHashedPassword; currentLanguage = $currentLanguage; currentPasswordExpirationEnabled = $currentPasswordExpirationEnabled; currentPasswordMustChange = $currentPasswordMustChange; currentPasswordPolicyEnforced = $currentPasswordPolicyEnforced; currentSid = $currentSid; externalProviderAlterParams = $externalProviderAlterParams; hashedPass = $hashedPass; hashedPassDt = $hashedPassDt; loginCollection = $loginCollection; loginName = $loginName; loginType = $loginType; newLogin = $newLogin; server = $server; sourceServer = $sourceServer; sql = $sql; usedTsql = $usedTsql; withParams = $withParams } }
    }
} $SqlInstance $SqlCredential $Login $SecurePassword $HashedPassword $MapToCertificate $MapToAsymmetricKey $MapToCredential $Sid $DefaultDatabase $Language $PasswordExpirationEnabled $PasswordPolicyEnforced $PasswordMustChange $Disabled $DenyWindowsLogin $NewSid $ExternalProvider $InputObject $LoginRenameHashtable $Force $EnableException $__realCmdlet $__denyWindowsLoginBound $__parameterSetName $__boundPasswordExpirationEnabled $__boundPasswordPolicyEnforced $__boundPasswordMustChange $__boundMapToAsymmetricKey $__boundMapToCertificate $__boundMapToCredential $__boundDisabled $__carryState $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
