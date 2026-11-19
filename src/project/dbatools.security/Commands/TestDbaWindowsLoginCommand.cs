#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests SQL Server Windows logins and groups against Active Directory, reporting missing accounts,
/// SID mismatches, and account-control states.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the AD lookups
/// (Get-DbaADObject), the UserAccountControl decoding, the output shapes, and dbatools stream and error
/// handling stay observable-identical to the script implementation.
/// </para>
/// <para>
/// The script has TWO ValueFromPipeline parameters (SqlInstance and InputObject) that both ACCUMULATE into
/// the function-scope $allWindowsLoginsGroups across pipeline records, and its end block does all the AD
/// validation, so the port is COLLECT-THEN-ENDPROCESSING in one scope: the begin block runs once, the
/// process body replays per batch, and the end block runs after the batches. Each ProcessRecord snapshots
/// BOTH parameters' BoundParameters.ContainsKey state AND their current values - probe-proven ground truth:
/// pipeline-bound entries LINGER in $PSBoundParameters across records (a record that binds only InputObject
/// still sees SqlInstance bound if an earlier record bound it) and parameter variables retain their
/// last-bound values, so the script's `Test-Bound SqlInstance, InputObject -Max 1` guard and its
/// $SqlInstance loop both read that lingering state. The per-batch snapshot reproduces it exactly,
/// including the source quirk that a mixed pipeline re-processes the lingering $SqlInstance on later
/// records. A DbaInstanceParameter's permissive conversion also lets a piped Login object bind BOTH
/// parameters - source behavior, preserved by snapshotting what the binder actually did.
/// </para>
/// <para>
/// No ShouldProcess (the command only reads). The guard's Test-Bound maps to the two carried per-batch
/// flags: Test-Bound defaults to -Min 1, so with -Max 1 the source accepts EXACTLY ONE bound parameter -
/// zero bound (a bare invocation) fails the guard just like two. The dot-source keeps each batch's guard return local. The
/// only other edits are message attribution: -FunctionName on the 2 direct Stop-Function calls and
/// -FunctionName plus -ModuleName "dbatools" on the 21 direct Write-Message calls. Buffered InvokeScoped
/// is deliberate: the command emits only from EndProcessing after all input is collected, so there is no
/// earlier output for a late failure to discard.
/// </para>
/// </remarks>
[Cmdlet(VerbsDiagnostic.Test, "DbaWindowsLogin")]
public sealed class TestDbaWindowsLoginCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The Windows logins to test.</summary>
    [Parameter(Position = 2)]
    public string[]? Login { get; set; }

    /// <summary>Logins to exclude from the test.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeLogin { get; set; }

    /// <summary>Restricts the search to logins, groups, or both.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    [ValidateSet("LoginsOnly", "GroupsOnly", "None")]
    public string? FilterBy { get; set; } = "None";

    /// <summary>Domains to skip when validating logins.</summary>
    [Parameter(Position = 5)]
    [PsStringArrayCast]
    public string[]? IgnoreDomains { get; set; }

    /// <summary>Login objects from Get-DbaLogin for pipeline operations.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public Microsoft.SqlServer.Management.Smo.Login[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>One batch per pipeline record: { sqlBound, inputBound, SqlInstance, InputObject }.</summary>
    private readonly List<object?[]?> _batches = new List<object?[]?>();

    /// <summary>Snapshots each record's binding state and values; the work runs once in EndProcessing.</summary>
    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // ContainsKey reflects the engine's lingering per-record $PSBoundParameters state, and the
        // properties retain their last-bound values - both exactly what the script's process block sees.
        _batches.Add(new object?[]
        {
            MyInvocation.BoundParameters.ContainsKey("SqlInstance"),
            MyInvocation.BoundParameters.ContainsKey("InputObject"),
            SqlInstance,
            InputObject
        });
    }

    /// <summary>Runs begin once, replays the process body per batch, then runs the end block.</summary>
    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

        // [DEF-001] streamed via InvokeScopedStreaming: the hop body loops emitting per-item and
        // carries reachable terminating throws (-Continue Stop-Function under -EnableException), so a
        // buffered InvokeScoped would lose an earlier item's emit when a later item throws. Streaming
        // yields each record as produced; no state carry on this row.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            if (item is not null)
                WriteObject(item);
        }, ProcessScript,
            _batches.ToArray(), SqlCredential, Login, ExcludeLogin, FilterBy, IgnoreDomains, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block once, a per-batch dot-sourced replay of the process body (its $SqlInstance,
    // $InputObject, and both bound flags set from the batch snapshot), then the end block, all in one
    // scope. Substitutions only: the Test-Bound guard -> the two carried per-batch flags; -FunctionName on
    // the 2 DIRECT Stop-Function calls; -FunctionName + -ModuleName "dbatools" on the 21 DIRECT
    // Write-Message calls. EnableException received untyped.
    private const string ProcessScript = """
param($__batches, $SqlCredential, $Login, $ExcludeLogin, $FilterBy, $IgnoreDomains, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__batches, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Login, [string[]]$ExcludeLogin, [string]$FilterBy, [string[]]$IgnoreDomains, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if ($IgnoreDomains) {
            $IgnoreDomainsNormalized = $IgnoreDomains.ToUpper()
            Write-Message -Message ("Excluding logins for domains " + ($IgnoreDomains -join ',')) -Level Verbose -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
        }

        $mappingRaw = @{
            'SCRIPT'                                 = 1
            'ACCOUNTDISABLE'                         = 2
            'HOMEDIR_REQUIRED'                       = 8
            'LOCKOUT'                                = 16
            'PASSWD_NOTREQD'                         = 32
            'PASSWD_CANT_CHANGE'                     = 64
            'ENCRYPTED_TEXT_PASSWORD_ALLOWED'        = 128
            'TEMP_DUPLICATE_ACCOUNT'                 = 256
            'NORMAL_ACCOUNT'                         = 512
            'INTERDOMAIN_TRUST_ACCOUNT'              = 2048
            'WORKSTATION_TRUST_ACCOUNT'              = 4096
            'SERVER_TRUST_ACCOUNT'                   = 8192
            'DONT_EXPIRE_PASSWD'                     = 65536
            'MNS_LOGON_ACCOUNT'                      = 131072
            'SMARTCARD_REQUIRED'                     = 262144
            'TRUSTED_FOR_DELEGATION'                 = 524288
            'NOT_DELEGATED'                          = 1048576
            'USE_DES_KEY_ONLY'                       = 2097152
            'DONT_REQUIRE_PREAUTH'                   = 4194304
            'PASSWORD_EXPIRED'                       = 8388608
            'TRUSTED_TO_AUTHENTICATE_FOR_DELEGATION' = 16777216
            'NO_AUTH_DATA_REQUIRED'                  = 33554432
            'PARTIAL_SECRETS_ACCOUNT'                = 67108864
        }

        $allWindowsLoginsGroups = @( )

        foreach ($__batch in $__batches) {
            $__sqlBound = $__batch[0]
            $__inputBound = $__batch[1]
            [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance = $__batch[2]
            [Microsoft.SqlServer.Management.Smo.Login[]]$InputObject = $__batch[3]
            . {
        if (-not (([int]$__sqlBound + [int]$__inputBound) -eq 1)) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Test-DbaWindowsLogin
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaWindowsLogin
            }
            $allWindowsLoginsGroups += $server.Logins | Where-Object { $_.LoginType -in ('WindowsUser', 'WindowsGroup') }
        }

        if ($InputObject) {
            $allWindowsLoginsGroups += $InputObject
        }
            }
        }

        # we cannot validate local users
        $allWindowsLoginsGroups = $allWindowsLoginsGroups | Where-Object { $_.Name.StartsWith("NT ") -eq $false -and $_.Name.StartsWith($_.Parent.ComputerName) -eq $false -and $_.Name.StartsWith("BUILTIN") -eq $false }
        if ($Login) {
            $allWindowsLoginsGroups = $allWindowsLoginsGroups | Where-Object Name -In $Login
        }
        if ($ExcludeLogin) {
            $allWindowsLoginsGroups = $allWindowsLoginsGroups | Where-Object Name -NotIn $ExcludeLogin
        }
        switch ($FilterBy) {
            "LoginsOnly" {
                Write-Message -Message "Search restricted to logins." -Level Verbose -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                $windowsLogins = $allWindowsLoginsGroups | Where-Object LoginType -eq 'WindowsUser'
            }
            "GroupsOnly" {
                Write-Message -Message "Search restricted to groups." -Level Verbose -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                $windowsGroups = $allWindowsLoginsGroups | Where-Object LoginType -eq 'WindowsGroup'
            }
            "None" {
                Write-Message -Message "Search both logins and groups." -Level Verbose -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                $windowsLogins = $allWindowsLoginsGroups | Where-Object LoginType -eq 'WindowsUser'
                $windowsGroups = $allWindowsLoginsGroups | Where-Object LoginType -eq 'WindowsGroup'
            }
        }
        foreach ($winLogin in $windowsLogins) {
            $adLogin = $winLogin.Name
            $loginSid = $winLogin.Sid -join ''
            $domain, $username = $adLogin.Split("\")
            if ($domain.ToUpper() -in $IgnoreDomainsNormalized) {
                Write-Message -Message "Skipping Login $adLogin." -Level Verbose -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                continue
            }
            Write-Message -Message "Parsing Login $adLogin." -Level Verbose -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
            $exists = $false
            $samAccountNameMismatch = $false
            try {
                $loginBinary = [byte[]]$winLogin.Sid
                $SID = New-Object Security.Principal.SecurityIdentifier($loginBinary, 0)
                $SIDForAD = $SID.Value
                Write-Message -Message "SID for AD is $SIDForAD" -Level Debug -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                $u = Get-DbaADObject -ADObject "$domain\$SIDForAD" -Type User -IdentityType Sid -EnableException
                if ($null -eq $u -and $adLogin -like '*$') {
                    Write-Message -Message "Parsing Login as computer" -Level Verbose -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                    $u = Get-DbaADObject -ADObject $adLogin -Type Computer -EnableException
                    $adType = 'Computer'
                } else {
                    $adType = 'User'
                }
                $foundUser = $u.GetUnderlyingObject()
                $foundSid = $foundUser.ObjectSid.Value -join ''
                if ($foundUser) {
                    $exists = $true
                }
                if ($foundSid -ne $loginSid) {
                    Write-Message -Message "SID mismatch detected for $adLogin." -Level Warning -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                    Write-Message -Message "SID mismatch detected for $adLogin (MSSQL: $loginSid, AD: $foundSid)." -Level Debug -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                    $exists = $false
                }
                if ($u.SamAccountName -ne $username) {
                    Write-Message -Message "SamAccountName mismatch detected for $adLogin." -Level Warning -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                    Write-Message -Message "SamAccountName mismatch detected for $adLogin (MSSQL: $username, AD: $($u.SamAccountName))." -Level Debug -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                    $samAccountNameMismatch = $true
                }
            } catch {
                Write-Message -Message "AD Searcher Error for $username." -Level Warning -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
            }

            $uac = $foundUser.Properties.UserAccountControl

            $additionalProps = @{
                AccountNotDelegated               = $null
                AllowReversiblePasswordEncryption = $null
                CannotChangePassword              = $null
                PasswordExpired                   = $null
                LockedOut                         = $null
                Enabled                           = $null
                PasswordNeverExpires              = $null
                PasswordNotRequired               = $null
                SmartcardLogonRequired            = $null
                TrustedForDelegation              = $null
            }
            if ($uac) {
                $additionalProps = @{
                    AccountNotDelegated               = [bool]($uac.Value -band $mappingRaw['NOT_DELEGATED'])
                    AllowReversiblePasswordEncryption = [bool]($uac.Value -band $mappingRaw['ENCRYPTED_TEXT_PASSWORD_ALLOWED'])
                    CannotChangePassword              = [bool]($uac.Value -band $mappingRaw['PASSWD_CANT_CHANGE'])
                    PasswordExpired                   = [bool]($uac.Value -band $mappingRaw['PASSWORD_EXPIRED'])
                    LockedOut                         = [bool]($uac.Value -band $mappingRaw['LOCKOUT'])
                    Enabled                           = !($uac.Value -band $mappingRaw['ACCOUNTDISABLE'])
                    PasswordNeverExpires              = [bool]($uac.Value -band $mappingRaw['DONT_EXPIRE_PASSWD'])
                    PasswordNotRequired               = [bool]($uac.Value -band $mappingRaw['PASSWD_NOTREQD'])
                    SmartcardLogonRequired            = [bool]($uac.Value -band $mappingRaw['SMARTCARD_REQUIRED'])
                    TrustedForDelegation              = [bool]($uac.Value -band $mappingRaw['TRUSTED_FOR_DELEGATION'])
                    UserAccountControl                = $uac.Value
                }
            }
            $rtn = [PSCustomObject]@{
                Server                            = $winLogin.Parent.DomainInstanceName
                Domain                            = $domain
                Login                             = $username
                Type                              = $adType
                Found                             = $exists
                SamAccountNameMismatch            = $samAccountNameMismatch
                DisabledInSQLServer               = $winLogin.IsDisabled
                AccountNotDelegated               = $additionalProps.AccountNotDelegated
                AllowReversiblePasswordEncryption = $additionalProps.AllowReversiblePasswordEncryption
                CannotChangePassword              = $additionalProps.CannotChangePassword
                PasswordExpired                   = $additionalProps.PasswordExpired
                LockedOut                         = $additionalProps.LockedOut
                Enabled                           = $additionalProps.Enabled
                PasswordNeverExpires              = $additionalProps.PasswordNeverExpires
                PasswordNotRequired               = $additionalProps.PasswordNotRequired
                SmartcardLogonRequired            = $additionalProps.SmartcardLogonRequired
                TrustedForDelegation              = $additionalProps.TrustedForDelegation
                UserAccountControl                = $additionalProps.UserAccountControl
            }

            Select-DefaultView -InputObject $rtn -ExcludeProperty AccountNotDelegated, AllowReversiblePasswordEncryption, CannotChangePassword, PasswordNeverExpires, SmartcardLogonRequired, TrustedForDelegation, UserAccountControl
        }

        foreach ($winLogin in $windowsGroups) {
            $adLogin = $winLogin.Name
            $loginSid = $winLogin.Sid -join ''
            $domain, $groupName = $adLogin.Split("\")
            if ($domain.ToUpper() -in $IgnoreDomainsNormalized) {
                Write-Message -Message "Skipping Login $adLogin." -Level Verbose -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                continue
            }
            Write-Message -Message "Parsing Login $adLogin on $($_.Parent)." -Level Verbose -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
            $exists = $false
            $samAccountNameMismatch = $false
            try {
                $loginBinary = [byte[]]$winLogin.Sid
                $SID = New-Object Security.Principal.SecurityIdentifier($loginBinary, 0)
                $SIDForAD = $SID.Value
                Write-Message -Message "SID for AD is $SIDForAD" -Level Debug -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                $u = Get-DbaADObject -ADObject "$domain\$SIDForAD" -Type Group -IdentityType Sid -EnableException
                $foundUser = $u.GetUnderlyingObject()
                $foundSid = $foundUser.objectSid.Value -join ''
                if ($foundUser) {
                    $exists = $true
                }
                if ($foundSid -ne $loginSid) {
                    Write-Message -Message "SID mismatch detected for $adLogin." -Level Warning -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                    Write-Message -Message "SID mismatch detected for $adLogin (MSSQL: $loginSid, AD: $foundSid)." -Level Debug -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                    $exists = $false
                }
                if ($u.SamAccountName -ne $groupName) {
                    Write-Message -Message "SamAccountName mismatch detected for $adLogin." -Level Warning -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                    Write-Message -Message "SamAccountName mismatch detected for $adLogin (MSSQL: $groupName, AD: $($u.SamAccountName))." -Level Debug -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
                    $samAccountNameMismatch = $true
                }
            } catch {
                Write-Message -Message "AD Searcher Error for $groupName on $($_.Parent)" -Level Warning -FunctionName Test-DbaWindowsLogin -ModuleName "dbatools"
            }
            $rtn = [PSCustomObject]@{
                Server                            = $winLogin.Parent.DomainInstanceName
                Domain                            = $domain
                Login                             = $groupName
                Type                              = "Group"
                Found                             = $exists
                SamAccountNameMismatch            = $samAccountNameMismatch
                DisabledInSQLServer               = $winLogin.IsDisabled
                AccountNotDelegated               = $null
                AllowReversiblePasswordEncryption = $null
                CannotChangePassword              = $null
                PasswordExpired                   = $null
                LockedOut                         = $null
                Enabled                           = $null
                PasswordNeverExpires              = $null
                PasswordNotRequired               = $null
                SmartcardLogonRequired            = $null
                TrustedForDelegation              = $null
                UserAccountControl                = $null
            }

            Select-DefaultView -InputObject $rtn -ExcludeProperty AccountNotDelegated, AllowReversiblePasswordEncryption, CannotChangePassword, PasswordNeverExpires, SmartcardLogonRequired, TrustedForDelegation, UserAccountControl
        }
} $__batches $SqlCredential $Login $ExcludeLogin $FilterBy $IgnoreDomains $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
