#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a SQL Server Agent proxy account.
/// </summary>
/// <remarks>
/// The instance connection, the existing-proxy/-Force handling, the credential/principal validation, the
/// SMO ProxyAccount construction, the login/role/subsystem grants, the Alter, and the output all run the
/// original dbatools PowerShell body inside the dbatools module scope rather than being reimplemented in
/// C#, so the engine decides the observable details.
///
/// $proxy spans the pipeline in the source's shared process scope: it is created inside a ShouldProcess
/// gate but is never reset per proxy-name iteration, and it is READ across iterations/records - in the
/// "already exists" warning message (before creation, so it interpolates a prior iteration's proxy), and,
/// under an interactive -Confirm where the create prompt is declined but a later grant prompt is accepted,
/// the grant runs against a prior record's proxy. A per-record hop scope would reset it, so $proxy is
/// carried record-to-record via a sentinel (C# field seeded into the hop top, re-emitted at the end).
/// Null-init matches the source's unassigned first-record state, so no first-vs-carried flag is needed.
///
/// The begin block's "if (\$Force) { \$ConfirmPreference = 'none' }" is folded into the top of the process
/// hop with \$__gate = if (\$Force) { \$PSCmdlet } else { \$__realCmdlet }; all seven ShouldProcess sites
/// route through \$__gate so -Force suppresses the prompts. -Force is also read by value in the drop-existing
/// branch. Test-Bound -ParameterName Disabled (a boundness check - the source's create arg keys off whether
/// -Disabled was supplied, not its value) becomes the carried \$__boundDisabled flag.
///
/// Output streams: each created proxy is emitted before a later one may fail under -EnableException
/// (DEF-001). Surface pinned by migration/baselines/New-DbaAgentProxy.json.
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaAgentProxy", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaAgentProxyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) for the SQL Agent proxy account(s) being created.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public string[] Name { get; set; } = null!;

    /// <summary>The name of an existing SQL Server credential the proxy will use.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    public string[] ProxyCredential { get; set; } = null!;

    /// <summary>Which SQL Agent subsystems can use this proxy (defaults to CmdExec).</summary>
    [Parameter(Position = 4)]
    [ValidateSet("ActiveScripting", "AnalysisCommand", "AnalysisQuery", "CmdExec", "Distribution", "LogReader", "Merge", "PowerShell", "QueueReader", "Snapshot", "Ssis")]
    public string[] SubSystem { get; set; } = new[] { "CmdExec" };

    /// <summary>A text description for the proxy account.</summary>
    [Parameter(Position = 5)]
    public string? Description { get; set; }

    /// <summary>Which SQL Server logins can use this proxy account.</summary>
    [Parameter(Position = 6)]
    public string[]? Login { get; set; }

    /// <summary>Which SQL Server fixed server roles can use this proxy account.</summary>
    [Parameter(Position = 7)]
    public string[]? ServerRole { get; set; }

    /// <summary>Which msdb database roles can use this proxy account.</summary>
    [Parameter(Position = 8)]
    public string[]? MsdbRole { get; set; }

    /// <summary>Creates the proxy account in a disabled state.</summary>
    [Parameter]
    public SwitchParameter Disabled { get; set; }

    /// <summary>Drops and recreates the proxy account if one with the same name already exists.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    // $proxy carried across records: the source keeps it in the shared process scope and never resets it, so
    // a record that reads it without a fresh create (the "already exists" message, or a -Confirm-declined
    // create) sees the prior record's object. Null-init matches the source's unassigned first-record state.
    private object? _proxy;

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaAgentProxyState"))
            {
                if (sentinel["__newDbaAgentProxyState"] is Hashtable state)
                {
                    _proxy = state["Proxy"];
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
        }, BodyScript,
            SqlInstance, SqlCredential, Name, ProxyCredential, SubSystem, Description, Login, ServerRole,
            MsdbRole, Force.ToBool(), EnableException.ToBool(),
            MyInvocation.BoundParameters.ContainsKey("Disabled"), _proxy, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from $Pscmdlet.ShouldProcess -> $__gate.ShouldProcess,
    // Test-Bound -ParameterName Disabled -> the carried $__boundDisabled flag, and -FunctionName
    // New-DbaAgentProxy on the direct Stop-Function/Write-Message sites. The begin's Force/ConfirmPreference
    // line and the gate selection are prepended (folded from begin). $proxy is seeded from the carried value
    // at the top and re-emitted in a sentinel at the end so the source's cross-record retention is reproduced.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Name, $ProxyCredential, $SubSystem, $Description, $Login, $ServerRole, $MsdbRole, $Force, $EnableException, $__boundDisabled, $__carriedProxy, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Name, [string[]]$ProxyCredential, [string[]]$SubSystem, [string]$Description, [string[]]$Login, [string[]]$ServerRole, [string[]]$MsdbRole, $Force, $EnableException, $__boundDisabled, $__carriedProxy, $__realCmdlet)
    if ($Force) { $ConfirmPreference = 'none' }
    $__gate = if ($Force) { $PSCmdlet } else { $__realCmdlet }
    # Seed the carried cross-record $proxy (source keeps it in the shared process scope, never reset).
    $proxy = $__carriedProxy
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaAgentProxy
        }

        if ($Subsystem -eq "ActiveScripting" -and $server.VersionMajor -ge 13) {
            Stop-Function -Message "ActiveScripting (ActiveX script) is not supported in SQL Server 2016 or higher" -Target $server -Continue -FunctionName New-DbaAgentProxy
        }

        try {
            $jobServer = $server.JobServer
        } catch {
            Stop-Function -Message "Failure. Is SQL Agent started?" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaAgentProxy
        }

        foreach ($proxyname in $name) {

            if ($jobServer.ProxyAccounts[$proxyName]) {
                if ($force) {
                    if ($__gate.ShouldProcess($instance, "Dropping $proxyname")) {
                        $jobServer.ProxyAccounts[$proxyName].Drop()
                        $jobServer.ProxyAccounts.Refresh()
                    }
                } else {
                    Write-Message -Level Warning -Message "Proxy account $proxy already exists on $instance. Use -Force to drop and recreate." -FunctionName New-DbaAgentProxy -ModuleName "dbatools"
                    continue
                }
            }

            if (-not $server.Credentials[$ProxyCredential]) {
                Write-Message -Level Warning -Message "Credential '$ProxyCredential' does not exist on $instance" -FunctionName New-DbaAgentProxy -ModuleName "dbatools"
                continue
            }

            if ($__gate.ShouldProcess($instance, "Adding $proxyname with the $ProxyCredential credential")) {
                # the new-object is stubborn and $true/$false has to be forced in
                try {
                    switch ($__boundDisabled) {
                        $false {
                            $proxy = New-Object Microsoft.SqlServer.Management.Smo.Agent.ProxyAccount -ArgumentList $jobServer, $ProxyName, $ProxyCredential, $true, $Description
                        }
                        $true {
                            $proxy = New-Object Microsoft.SqlServer.Management.Smo.Agent.ProxyAccount -ArgumentList $jobServer, $ProxyName, $ProxyCredential, $false, $Description
                        }
                    }
                } catch {
                    if ($_.Exception.Message -match "newParent") {
                        Stop-Function -Message "Cannot create agent proxy through a contained availability group listener. SQL Server Agent objects are instance-level and must be managed on the instance directly. Please connect to the primary replica instead of the listener. Use Get-DbaAvailabilityGroup to find the current primary replica." -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaAgentProxy
                    } else {
                        throw
                    }
                }

                try {
                    $proxy.Create()
                } catch {
                    Stop-Function -Message "Could not create proxy account" -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaAgentProxy
                }
            }

            foreach ($loginname in $login) {
                if ($server.Logins[$loginname]) {
                    if ($__gate.ShouldProcess($instance, "Adding login $loginname to proxy")) {
                        $proxy.AddLogin($loginname)
                    }
                } else {
                    Write-Message -Level Warning -Message "Login '$loginname' does not exist on $instance" -FunctionName New-DbaAgentProxy -ModuleName "dbatools"
                }
            }

            foreach ($role in $ServerRole) {
                if ($server.Roles[$role]) {
                    if ($__gate.ShouldProcess($instance, "Adding server role $role to proxy")) {
                        $proxy.AddServerRole($role)
                    }
                } else {
                    Write-Message -Level Warning -Message "Server Role '$role' does not exist on $instance" -FunctionName New-DbaAgentProxy -ModuleName "dbatools"
                }
            }

            foreach ($role in $MsdbRole) {
                if ($server.Databases['msdb'].Roles[$role]) {
                    if ($__gate.ShouldProcess($instance, "Adding msdb role $role to proxy")) {
                        $proxy.AddMsdbRole($role)
                    }
                } else {
                    Write-Message -Level Warning -Message "msdb role '$role' does not exist on $instance" -FunctionName New-DbaAgentProxy -ModuleName "dbatools"
                }
            }

            foreach ($system in $SubSystem) {
                if ($__gate.ShouldProcess($instance, "Adding subsystem $system to proxy")) {
                    $proxy.AddSubSystem($system)
                }
            }

            if ($__gate.ShouldProcess("console", "Outputting Proxy object")) {
                $proxy.Alter()
                $proxy.Refresh()
                Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name Logins -value $proxy.EnumLogins()
                Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name ServerRoles -value $proxy.EnumServerRoles()
                Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name MsdbRoles -value $proxy.EnumMsdbRoles()
                Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name Subsystems -value $proxy.EnumSubSystems()

                Select-DefaultView -InputObject $proxy -Property ComputerName, InstanceName, SqlInstance, ID, Name, CredentialName, CredentialIdentity, Description, Logins, ServerRoles, MsdbRoles, SubSystems, IsEnabled
            }
        }
    }

    @{ __newDbaAgentProxyState = @{ Proxy = $proxy } }
} $SqlInstance $SqlCredential $Name $ProxyCredential $SubSystem $Description $Login $ServerRole $MsdbRole $Force $EnableException $__boundDisabled $__carriedProxy $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
