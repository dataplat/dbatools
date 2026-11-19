#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoAgentSubSystem = Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem;
using SmoProxyAccount = Microsoft.SqlServer.Management.Smo.Agent.ProxyAccount;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Modifies existing SQL Server Agent proxy accounts - properties, name, and login/role/subsystem grants.
/// </summary>
/// <remarks>
/// The instance/pipeline duality, the proxy lookup, the property assignments, the Alter, the rename, the
/// association grants, and the output all run a module-scoped PowerShell body inside the dbatools module
/// scope rather than being reimplemented in C#, so the engine decides the observable details and the body
/// can call Get-DbaAgentProxy, Get-ConnectionParent, Select-DefaultView, Stop-Function and Write-Message
/// directly.
///
/// CredentialName is only reassigned when -ProxyCredential is bound. The proxy is always fetched live via
/// Get-DbaAgentProxy, so its CredentialName property is already populated; SMO's ScriptAlter emits
/// @credential_name unconditionally, and because the object carries its current value the Alter rewrites the
/// existing name rather than blanking it. Description and IsEnabled read boundness (a bound empty Description
/// clears it; -Enabled:$false disables), so the C# passes explicit bound-ness flags computed with TestBound.
///
/// Associations run their own ExecuteNonQuery immediately and are not atomic with Alter. The body therefore
/// applies the property Alter first, then Rename, then removes-before-adds within each family, tracking the
/// operations that completed so a mid-sequence failure warns exactly what already landed rather than claiming
/// a rollback that is not possible.
///
/// This cmdlet supplies the real ShouldProcess runtime (ConfirmImpact Low, no -Force). No cross-record state
/// is carried - non-pipeline parameters are not mutated in place - so each record runs an independent hop.
/// Surface pinned by migration/designed/Set-DbaAgentProxy.json.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaAgentProxy", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(SmoProxyAccount))]
public sealed class SetDbaAgentProxyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) of the existing proxy account(s) to modify.</summary>
    [Parameter(Position = 2)]
    public string[]? Proxy { get; set; }

    /// <summary>The name of an existing SQL Server credential to assign to the proxy.</summary>
    [Parameter(Position = 3)]
    public string? ProxyCredential { get; set; }

    /// <summary>A new text description for the proxy account.</summary>
    [Parameter(Position = 4)]
    public string? Description { get; set; }

    /// <summary>Renames the proxy account to this value.</summary>
    [Parameter(Position = 5)]
    public string? NewName { get; set; }

    /// <summary>Agent proxy objects piped in from Get-DbaAgentProxy.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public SmoProxyAccount[]? InputObject { get; set; }

    /// <summary>Enables (-Enabled) or disables (-Enabled:$false) the proxy account.</summary>
    [Parameter]
    public SwitchParameter Enabled { get; set; }

    /// <summary>Logins to grant use of this proxy account.</summary>
    [Parameter]
    public string[]? AddLogin { get; set; }

    /// <summary>Logins to revoke from this proxy account.</summary>
    [Parameter]
    public string[]? RemoveLogin { get; set; }

    /// <summary>Fixed server roles to grant use of this proxy account.</summary>
    [Parameter]
    public string[]? AddServerRole { get; set; }

    /// <summary>Fixed server roles to revoke from this proxy account.</summary>
    [Parameter]
    public string[]? RemoveServerRole { get; set; }

    /// <summary>msdb database roles to grant use of this proxy account.</summary>
    [Parameter]
    public string[]? AddMsdbRole { get; set; }

    /// <summary>msdb database roles to revoke from this proxy account.</summary>
    [Parameter]
    public string[]? RemoveMsdbRole { get; set; }

    /// <summary>SQL Agent subsystems to grant this proxy account.</summary>
    [Parameter]
    public SmoAgentSubSystem[]? AddSubsystem { get; set; }

    /// <summary>SQL Agent subsystems to revoke from this proxy account.</summary>
    [Parameter]
    public SmoAgentSubSystem[]? RemoveSubsystem { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (all params are in
    // __AllParameterSets), so the inherited [Parameter] already matches; no per-set override needed.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BodyScript,
            SqlInstance, SqlCredential, Proxy, ProxyCredential, Description, NewName, InputObject,
            Enabled.ToBool(), AddLogin, RemoveLogin, AddServerRole, RemoveServerRole, AddMsdbRole,
            RemoveMsdbRole, AddSubsystem, RemoveSubsystem, EnableException.ToBool(), this,
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), TestBound(nameof(Proxy)),
            TestBound(nameof(ProxyCredential)), TestBound(nameof(Description)), TestBound(nameof(NewName)),
            TestBound(nameof(Enabled)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the module-scoped body. Property Alter runs first, then Rename, then removes-before-adds per
    // association family; the property change and the associations share the one "Altering" ShouldProcess
    // decision while Rename carries its own, so -WhatIf lands no side effect. $applied records completed
    // operations so a partial failure warns precisely what landed. -Enabled/-Description/-ProxyCredential
    // read the bound-ness flags (a bound empty Description clears it, -Enabled:$false disables).
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Proxy, $ProxyCredential, $Description, $NewName, $InputObject, $Enabled, $AddLogin, $RemoveLogin, $AddServerRole, $RemoveServerRole, $AddMsdbRole, $RemoveMsdbRole, $AddSubsystem, $RemoveSubsystem, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundProxy, $__boundProxyCredential, $__boundDescription, $__boundNewName, $__boundEnabled, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Proxy, [string]$ProxyCredential, [string]$Description, [string]$NewName, [Microsoft.SqlServer.Management.Smo.Agent.ProxyAccount[]]$InputObject, $Enabled, [string[]]$AddLogin, [string[]]$RemoveLogin, [string[]]$AddServerRole, [string[]]$RemoveServerRole, [string[]]$AddMsdbRole, [string[]]$RemoveMsdbRole, [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem[]]$AddSubsystem, [Microsoft.SqlServer.Management.Smo.Agent.AgentSubSystem[]]$RemoveSubsystem, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundProxy, $__boundProxyCredential, $__boundDescription, $__boundNewName, $__boundEnabled)

    if (-not $__boundSqlInstance -and -not $__boundInputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Set-DbaAgentProxy
        return
    }

    if ($__boundSqlInstance) {
        $splatGet = @{
            SqlInstance     = $SqlInstance
            SqlCredential   = $SqlCredential
            EnableException = $true
        }
        if ($__boundProxy) { $splatGet.Proxy = $Proxy }
        try {
            $InputObject += Get-DbaAgentProxy @splatGet
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -Continue -FunctionName Set-DbaAgentProxy
        }
    }

    foreach ($currentProxy in $InputObject) {
        $server = $currentProxy | Get-ConnectionParent
        $applied = New-Object System.Collections.Generic.List[string]

        $wantAlter = $__boundProxyCredential -or $__boundDescription -or $__boundEnabled -or $AddSubsystem -or $RemoveSubsystem -or $AddLogin -or $RemoveLogin -or $AddServerRole -or $RemoveServerRole -or $AddMsdbRole -or $RemoveMsdbRole
        $doAlter = $wantAlter -and $__realCmdlet.ShouldProcess($server, "Altering Agent proxy $($currentProxy.Name)")
        $changed = $false

        try {
            if ($doAlter) {
                $propertyChanged = $false
                if ($__boundProxyCredential) {
                    $currentProxy.CredentialName = $ProxyCredential
                    $propertyChanged = $true
                }
                if ($__boundDescription) {
                    $currentProxy.Description = $Description
                    $propertyChanged = $true
                }
                if ($__boundEnabled) {
                    $currentProxy.IsEnabled = [bool]$Enabled
                    $propertyChanged = $true
                }
                if ($propertyChanged) {
                    $currentProxy.Alter()
                    $applied.Add("altered properties")
                    $changed = $true
                }
            }

            if ($__boundNewName) {
                if ($__realCmdlet.ShouldProcess($server, "Renaming Agent proxy $($currentProxy.Name) to $NewName")) {
                    $currentProxy.Rename($NewName)
                    $applied.Add("renamed to $NewName")
                    $changed = $true
                }
            }

            if ($doAlter) {
                foreach ($item in $RemoveSubsystem) { $currentProxy.RemoveSubSystem($item); $applied.Add("removed subsystem $item"); $changed = $true }
                foreach ($item in $AddSubsystem) { $currentProxy.AddSubSystem($item); $applied.Add("added subsystem $item"); $changed = $true }

                foreach ($item in $RemoveLogin) { $currentProxy.RemoveLogin($item); $applied.Add("removed login $item"); $changed = $true }
                foreach ($item in $AddLogin) { $currentProxy.AddLogin($item); $applied.Add("added login $item"); $changed = $true }

                foreach ($item in $RemoveServerRole) { $currentProxy.RemoveServerRole($item); $applied.Add("removed server role $item"); $changed = $true }
                foreach ($item in $AddServerRole) { $currentProxy.AddServerRole($item); $applied.Add("added server role $item"); $changed = $true }

                foreach ($item in $RemoveMsdbRole) { $currentProxy.RemoveMsdbRole($item); $applied.Add("removed msdb role $item"); $changed = $true }
                foreach ($item in $AddMsdbRole) { $currentProxy.AddMsdbRole($item); $applied.Add("added msdb role $item"); $changed = $true }
            }
        } catch {
            $completed = if ($applied.Count) { " Completed before the failure: $($applied -join ', ')." } else { "" }
            Stop-Function -Message "Failed to update Agent proxy $($currentProxy.Name) on $server.$completed" -ErrorRecord $_ -Target $server -Continue -FunctionName Set-DbaAgentProxy
            continue
        }

        if ($changed) {
            $currentProxy.Refresh()
            Add-Member -Force -InputObject $currentProxy -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
            Add-Member -Force -InputObject $currentProxy -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $currentProxy -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
            Select-DefaultView -InputObject $currentProxy -Property ComputerName, SqlInstance, InstanceName, Name, ID, CredentialID, CredentialIdentity, CredentialName, Description, IsEnabled
        }
    }
} $SqlInstance $SqlCredential $Proxy $ProxyCredential $Description $NewName $InputObject $Enabled $AddLogin $RemoveLogin $AddServerRole $RemoveServerRole $AddMsdbRole $RemoveMsdbRole $AddSubsystem $RemoveSubsystem $EnableException $__realCmdlet $__boundSqlInstance $__boundInputObject $__boundProxy $__boundProxyCredential $__boundDescription $__boundNewName $__boundEnabled @__commonParameters 3>&1 2>&1
""";
}
