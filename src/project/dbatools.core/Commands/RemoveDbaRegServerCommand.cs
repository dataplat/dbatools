#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes registered servers (CMS or local store). Port of
/// public/Remove-DbaRegServer.ps1 (W3-079), RegServer family (Move-DbaRegServer/-Group
/// siblings). The process body rides one VERBATIM module hop per record; records are
/// SELF-CONTAINED (piped $InputObject rebinds per record; the += accumulation from the
/// SqlInstance loop and the no-SqlInstance-no-InputObject LOCAL-store fallback are both
/// invocation-local; drops happen inside process) - no sentinel, no discriminator (the
/// W3-074 shape). SOURCE QUIRK preserved: the Get-DbaRegServer calls pass
/// -ExcludeGroup $ExcludeGroup where $ExcludeGroup is NOT a declared parameter - the
/// undefined variable reads $null in the module scope exactly as it did in the function.
/// The Azure Data Studio guard (Stop-Function -Continue), the ID-vs-local defaults/target
/// split, the private Disconnect-RegServer and Select-DefaultView calls, and the
/// post-Drop output object ride verbatim. $Pscmdlet.ShouldProcess routes to the REAL
/// cmdlet (ConfirmImpact HIGH mirrored). NO WarningAction carrier (codex W3-005 r3).
/// Surface pinned by migration/baselines/Remove-DbaRegServer.json (implicit positions
/// 0-5, InputObject RegisteredServer[] pos5 VFP).
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaRegServer", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaRegServerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances (CMS).</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The display name(s) of the registered servers to remove.</summary>
    [Parameter(Position = 2)]
    public string[]? Name { get; set; }

    /// <summary>The server name(s) of the registered servers to remove.</summary>
    [Parameter(Position = 3)]
    public string[]? ServerName { get; set; }

    /// <summary>The group(s) whose registered servers should be removed.</summary>
    [Parameter(Position = 4)]
    public string[]? Group { get; set; }

    /// <summary>RegisteredServer object(s) from Get-DbaRegServer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

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
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Name, ServerName, Group, InputObject,
            EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM per record. Substitutions only: $Pscmdlet ->
    // $__realCmdlet and explicit -FunctionName Remove-DbaRegServer on Stop-Function
    // (W1-090). The undeclared-$ExcludeGroup quirk, the Azure Data Studio guard, and the
    // private Disconnect-RegServer/Select-DefaultView calls ride as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Name, $ServerName, $Group, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Name, [string[]]$ServerName, [string[]]$Group, [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer[]]$InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($instance in $SqlInstance) {
        $InputObject += Get-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group -ExcludeGroup $ExcludeGroup -Name $Name -ServerName $ServerName
    }

    if (-not $SqlInstance -and -not $InputObject) {
        $InputObject += Get-DbaRegServer -Group $Group -ExcludeGroup $ExcludeGroup -Name $Name -ServerName $ServerName
    }

    foreach ($regserver in $InputObject) {
        if ($regserver.Source -eq "Azure Data Studio") {
            Stop-Function -Message "You cannot use dbatools to remove or add registered servers in Azure Data Studio" -Continue -FunctionName Remove-DbaRegServer
        }

        if ($regserver.ID) {
            $defaults = "ComputerName", "InstanceName", "SqlInstance", "Name", "ServerName", "Status"
            $target = $regserver.Parent
        } else {
            $defaults = "Name", "ServerName", "Status"
            $target = "Local Registered Server Groups"
        }

        if ($__realCmdlet.ShouldProcess($target, "Removing $regserver")) {
            $null = $regserver.Drop()

            if ($regserver.ID) {
                Disconnect-RegServer -Server $regserver.Parent
            }

            try {
                [PSCustomObject]@{
                    ComputerName = $regserver.ComputerName
                    InstanceName = $regserver.InstanceName
                    SqlInstance  = $regserver.SqlInstance
                    Name         = $regserver.Name
                    ServerName   = $regserver.ServerName
                    Status       = "Dropped"
                } | Select-DefaultView -Property $defaults
            } catch {
                Stop-Function -Message "Failed to drop $regserver on $target" -ErrorRecord $_ -Continue -FunctionName Remove-DbaRegServer
            }
        }
    }
} $SqlInstance $SqlCredential $Name $ServerName $Group $InputObject $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
