#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes custom server-level roles from one or more SQL Server instances.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the server-role drop, the
/// ShouldProcess gate, the output shape, and dbatools stream and error handling stay observable-identical to
/// the script implementation.
/// </para>
/// <para>
/// The command is process-only and mutating, so it ships as a single hop per record and streams its output
/// through InvokeScopedStreaming: InputObject is ValueFromPipeline and the body emits one object per role
/// processed, so a downstream early stop must halt before the remaining roles are dropped - exactly as the
/// script's pipeline does. SqlInstance is not ValueFromPipeline, so the only pipeline target is InputObject,
/// which rebinds each record - there is no cross-record accumulation of the script's $InputObject +=. The role
/// drop uses the SMO $srvrole.Drop() method (verbatim). The callback dispatches ErrorRecords to WriteError,
/// else WriteObject. EnableException is carried as a plain (untyped) value, because a switch in the inner
/// CmdletBinding scriptblock is excluded from positional binding. The one DIRECT Stop-Function call takes
/// -FunctionName; $Pscmdlet is redirected to the real cmdlet ($__realCmdlet) for the ShouldProcess gate.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaServerRole", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaServerRoleCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The custom server-level role name to remove.</summary>
    [Parameter(Position = 2)]
    public string[]? ServerRole { get; set; }

    /// <summary>ServerRole objects from Get-DbaServerRole for pipeline operations.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public Microsoft.SqlServer.Management.Smo.ServerRole[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Removes server roles for one pipeline record.</summary>
    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, ServerRole, InputObject, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet (the ShouldProcess gate);
    // -FunctionName on the one DIRECT Stop-Function call. EnableException received untyped.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $ServerRole, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$ServerRole, [Microsoft.SqlServer.Management.Smo.ServerRole[]]$InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if ($SqlInstance) {
            $InputObject += Get-DbaServerRole -SqlInstance $SqlInstance -SqlCredential $SqlCredential -ServerRole $ServerRole
        }

        foreach ($srvrole in $InputObject) {
            if ($__realCmdlet.ShouldProcess($srvrole.DomainInstanceName, "Dropping the server-role named $($srvrole.Role) on $($srvrole.DomainInstanceName)")) {
                try {
                    $srvrole.Drop()

                    [PSCustomObject]@{
                        ComputerName = $srvrole.ComputerName
                        InstanceName = $srvrole.InstanceName
                        SqlInstance  = $srvrole.SqlInstance
                        ServerRole   = $srvrole.Role
                        Status       = "Success"
                    }
                } catch {
                    Stop-Function -Message "Failed to drop server-role named $($srvrole.Name) on $($srvrole.Name)." -Target $srvrole -ErrorRecord $_ -Continue -FunctionName Remove-DbaServerRole

                    [PSCustomObject]@{
                        ComputerName = $srvrole.ComputerName
                        InstanceName = $srvrole.InstanceName
                        SqlInstance  = $srvrole.SqlInstance
                        ServerRole   = $srvrole.Role
                        Status       = "Failed"
                    }
                }
            }
        }
} $SqlInstance $SqlCredential $ServerRole $InputObject $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
