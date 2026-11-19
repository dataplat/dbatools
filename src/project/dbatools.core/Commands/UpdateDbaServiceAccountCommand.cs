#nullable enable

using System.Collections;
using System.Management.Automation;
using System.Security;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Changes the service account or its password for SQL Server-related services.
/// Port of public/Update-DbaServiceAccount.ps1; surface pinned by
/// migration/baselines/Update-DbaServiceAccount.json.
/// </summary>
[Cmdlet(VerbsData.Update, "DbaServiceAccount", SupportsShouldProcess = true, DefaultParameterSetName = "ServiceName")]
[OutputType(typeof(PSObject))]
public sealed partial class UpdateDbaServiceAccountCommand : DbaBaseCmdlet
{
    /// <summary>The target computer or computers to operate against.</summary>
    [Parameter(ParameterSetName = "ServiceName")]
    [Alias("cn", "host", "Server")]
    public DbaInstanceParameter[] ComputerName { get; set; } =
        (DbaInstanceParameter[])LanguagePrimitives.ConvertTo(
            System.Environment.GetEnvironmentVariable("COMPUTERNAME"),
            typeof(DbaInstanceParameter[]), System.Globalization.CultureInfo.InvariantCulture);

    /// <summary>Windows credential used to connect to the computers and their WMI service configuration.</summary>
    [Parameter]
    public PSCredential? Credential { get; set; }

    /// <summary>Service objects from Get-DbaService to update.</summary>
    [Parameter(ValueFromPipeline = true, Mandatory = true, ParameterSetName = "InputObject")]
    [Alias("ServiceCollection")]
    public object[]? InputObject { get; set; }

    /// <summary>The service or services to update on the target computers.</summary>
    [Parameter(ParameterSetName = "ServiceName", Position = 1, Mandatory = true)]
    [Alias("Name", "Service")]
    public string[]? ServiceName { get; set; }

    /// <summary>The account name the services should run under.</summary>
    [Parameter]
    [Alias("User")]
    public string? Username { get; set; }

    /// <summary>The account and password the services should run under, as a credential.</summary>
    [Parameter]
    public PSCredential? ServiceCredential { get; set; }

    /// <summary>The current password, required by a password change.</summary>
    [Parameter]
    public SecureString PreviousPassword { get; set; } = new SecureString();

    /// <summary>The new password for the account or the service login.</summary>
    [Parameter]
    [Alias("NewPassword", "Password")]
    public SecureString SecurePassword { get; set; } = new SecureString();

    /// <summary>Skips the automatic SQL Agent restart after an Engine account change.</summary>
    [Parameter]
    public SwitchParameter NoRestart { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    // The source's begin-block Stop-Function calls latch the interrupt flag with -Scope 1;
    // in the source that is the function scope Test-FunctionInterrupt reads in process, but
    // in a port it dies with the begin hop. The begin hop tail reports whether the flag
    // landed and this field gates ProcessRecord exactly like Test-FunctionInterrupt (the
    // source end block carries no interrupt check - it no-ops naturally on the empty
    // accumulator - so EndProcessing is deliberately not gated).
    private bool _hopInterrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        string[] boundKeys = new string[MyInvocation.BoundParameters.Keys.Count];
        MyInvocation.BoundParameters.Keys.CopyTo(boundKeys, 0);

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Username, ServiceCredential, SecurePassword, EnableException.ToBool(), boundKeys,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3114State"))
            {
                _state = sentinel["__w3114State"] as Hashtable;
                if (_state is not null && LanguagePrimitives.IsTrue(_state["interrupted"]))
                {
                    _hopInterrupted = true;
                }
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
        {
            return;
        }
        if (_hopInterrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3114State"))
            {
                _state = sentinel["__w3114State"] as Hashtable;
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
            ComputerName, InputObject, ServiceName, Credential, EnableException.ToBool(),
            ParameterSetName, _state,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        // DEF-001 cond1 fix (W3-114 re-open, coord 19:06 RATIFIED): the source's end{} loop emits a
        // result object per found service (ps:305) THEN can throw mid-loop via Stop-Function -Continue
        // under -EnableException (ps:284 update-failure catch, ps:307 service-not-found). A buffered
        // InvokeScoped discards every already-emitted row when EndScript throws, where the streaming
        // function world keeps them. Stream each item out as it is produced - identical to ProcessRecord.
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
            Credential, PreviousPassword, NoRestart.ToBool(), EnableException.ToBool(),
            _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM inside a dot-sourced block, so its early returns exit
    // the dot-block while the state tail still runs and the locals land in the enclosing
    // scope (dot-source semantics). Substitutions: -FunctionName on the two Stop-Function
    // sites; the single $PSBoundParameters.Keys read becomes the carried
    // $__boundParameterKeys (the hop has no bound-parameter view of the outer cmdlet).
    private const string BeginScript = """
param($Username, $ServiceCredential, $SecurePassword, $EnableException, $__boundParameterKeys, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($Username, [PSCredential]$ServiceCredential, [securestring]$SecurePassword, $EnableException, $__boundParameterKeys, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        $svcCollection = @()
        $scriptAccountChange = {
            $service = $wmi.Services[$args[0]]
            $service.SetServiceAccount($args[1], $args[2])
            $service.Alter()
        }
        $scriptPasswordChange = {
            $service = $wmi.Services[$args[0]]
            $service.ChangePassword($args[1], $args[2])
            $service.Alter()
        }
        #Check parameters
        if ($Username) {
            $actionType = 'Account'
            if ($ServiceCredential) {
                Stop-Function -EnableException $EnableException -Message "You cannot specify both -UserName and -ServiceCredential parameters" -Category InvalidArgument -FunctionName Update-DbaServiceAccount
                return
            }
            #System logins should not have a domain name, whitespaces or passwords
            $trimmedUsername = (Split-Path $Username -Leaf).Trim().Replace(' ', '')
            #Request password input if password was not specified and account is not MSA or system login
            if ($SecurePassword.Length -eq 0 -and $__boundParameterKeys -notcontains 'SecurePassword' -and $trimmedUsername -notin 'NETWORKSERVICE', 'LOCALSYSTEM', 'LOCALSERVICE' -and $Username.EndsWith('$') -eq $false -and $Username.StartsWith('NT Service\') -eq $false) {
                $SecurePassword = Read-Host -Prompt "Input new password for account $UserName" -AsSecureString
                $NewPassword2 = Read-Host -Prompt "Repeat password" -AsSecureString
                if ((New-Object System.Management.Automation.PSCredential ("user", $SecurePassword)).GetNetworkCredential().Password -ne `
                    (New-Object System.Management.Automation.PSCredential ("user", $NewPassword2)).GetNetworkCredential().Password) {
                    Stop-Function -Message "Passwords do not match" -Category InvalidArgument -EnableException $EnableException -FunctionName Update-DbaServiceAccount
                    return
                }
            }
            $currentCredential = New-Object System.Management.Automation.PSCredential ($Username, $SecurePassword)
        } elseif ($ServiceCredential) {
            $actionType = 'Account'
            $currentCredential = $ServiceCredential
        } else {
            $actionType = 'Password'
        }
        if ($actionType -eq 'Account') {
            #System logins should not have a domain name, whitespaces or passwords
            $credUserName = (Split-Path $currentCredential.UserName -Leaf).Trim().Replace(' ', '')
            #Check for system logins and replace the Credential object to simplify passing localsystem-like login names
            if ($credUserName -in 'NETWORKSERVICE', 'LOCALSYSTEM', 'LOCALSERVICE') {
                $currentCredential = New-Object System.Management.Automation.PSCredential ($credUserName, (New-Object System.Security.SecureString))
            }
        }
    }
    @{ __w3114State = @{
        svcCollection        = $svcCollection
        actionType           = $actionType
        currentCredential    = $currentCredential
        securePassword       = $SecurePassword
        scriptAccountChange  = $scriptAccountChange
        scriptPasswordChange = $scriptPasswordChange
        interrupted          = [bool](Get-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -ErrorAction Ignore -ValueOnly)
    } }
} $Username $ServiceCredential $SecurePassword $EnableException $__boundParameterKeys $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM (whole-record hop: the accumulator loops carry
    // cross-element state by design, so the record's arrays ride whole). The source's own
    // Test-FunctionInterrupt line is inert inside the hop scope; the C#-side
    // _hopInterrupted gate provides the actual latch semantics. Substitutions:
    // -FunctionName on the three Stop-Function sites; $PsCmdlet.ParameterSetName reads
    // the carried set name.
    private const string ProcessScript = """
param($ComputerName, $InputObject, $ServiceName, $Credential, $EnableException, $__parameterSetName, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$ComputerName, [object[]]$InputObject, [string[]]$ServiceName, [PSCredential]$Credential, $EnableException, $__parameterSetName, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $svcCollection = $__state.svcCollection
    . {
        if (Test-FunctionInterrupt) { return }

        if ($__parameterSetName -match 'ServiceName') {
            foreach ($Computer in $ComputerName.ComputerName) {
                $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
                if ($Server.FullComputerName) {
                    foreach ($service in $ServiceName) {
                        $svcCollection += [psobject]@{
                            ComputerName = $server.FullComputerName
                            ServiceName  = $service
                        }
                    }
                } else {
                    Stop-Function -EnableException $EnableException -Message "Failed to connect to $Computer" -Continue -FunctionName Update-DbaServiceAccount
                }
            }
        } elseif ($__parameterSetName -match 'InputObject') {
            foreach ($service in $InputObject) {
                if ($service.ServiceName -eq 'PowerBIReportServer') {
                    Stop-Function -Message "PowerBIReportServer service is not supported, skipping." -Continue -FunctionName Update-DbaServiceAccount
                } else {
                    $Server = Resolve-DbaNetworkName -ComputerName $service.ComputerName -Credential $credential
                    if ($Server.FullComputerName) {
                        $svcCollection += [psobject]@{
                            ComputerName = $Server.FullComputerName
                            ServiceName  = $service.ServiceName
                        }
                    } else {
                        Stop-Function -EnableException $EnableException -Message "Failed to connect to $($service.FullComputerName)" -Continue -FunctionName Update-DbaServiceAccount
                    }
                }
            }
        }

    }
    @{ __w3114State = @{
        svcCollection        = $svcCollection
        actionType           = $__state.actionType
        currentCredential    = $__state.currentCredential
        securePassword       = $__state.securePassword
        scriptAccountChange  = $__state.scriptAccountChange
        scriptPasswordChange = $__state.scriptPasswordChange
    } }
} $ComputerName $InputObject $ServiceName $Credential $EnableException $__parameterSetName $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
