#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes registered server groups (CMS or local store). Port of
/// public/Remove-DbaRegServerGroup.ps1 (W3-080), sibling of Remove-DbaRegServer
/// (W3-079): one VERBATIM module hop per record. Piped $InputObject rebinds and the +=
/// accumulation/LOCAL-store fallback are invocation-local (SqlInstance is not VFP), but
/// records are NOT fully self-contained: the leaked $parentserver crosses records in
/// the source fn scope, so the __w3080State sentinel carries it (B batch finding 11,
/// preserve-verbatim trio ruling). SOURCE QUIRKS preserved verbatim: the $parentserver
/// null-check runs AFTER the $parentserver.DomainInstanceName dereference, and the
/// LOCAL branch's output object reads $parentserver properties never assigned in that
/// iteration (stale from an earlier record/iteration, or null - exactly as the function
/// behaved). The Azure Data Studio guard (inside the
/// gate here, unlike the sibling), the ScriptDrop-ExecuteNonQuery CMS drop path with
/// its why-comment, and the private Get-RegServerParent/Select-DefaultView calls ride
/// the hop. $Pscmdlet.ShouldProcess routes to the REAL cmdlet (ConfirmImpact HIGH
/// mirrored). NO WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Remove-DbaRegServerGroup.json (implicit positions 0-3, Name
/// Alias Group, InputObject ServerGroup[] pos3 VFP).
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaRegServerGroup", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaRegServerGroupCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances (CMS).</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The group name(s) to remove.</summary>
    [Parameter(Position = 2)]
    [Alias("Group")]
    public string[]? Name { get; set; }

    /// <summary>ServerGroup object(s) from Get-DbaRegServerGroup.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Cross-record $parentserver leak (B batch finding 11, more-correct-than-source trio,
    // preserve-verbatim ruling): the source assigns $parentserver only in the ID branch
    // and the LOCAL branch's output object reads it unconditionally - a local group piped
    // AFTER a CMS group reads the PREVIOUS record's parent in the source. The sentinel
    // carries it across hop scopes.
    private Hashtable? _state;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3080State"))
            {
                _state = sentinel["__w3080State"] as Hashtable;
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
            SqlInstance, SqlCredential, Name, InputObject, EnableException.ToBool(), _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM per record. Substitutions only: $Pscmdlet ->
    // $__realCmdlet and explicit -FunctionName Remove-DbaRegServerGroup on Stop-Function
    // (W1-090). The dereference-before-null-check, the stale-$parentserver local output,
    // the ScriptDrop why-comment and the private Get-RegServerParent/Select-DefaultView
    // calls ride as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Name, $InputObject, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Name, [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]]$InputObject, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record restore: the leaked $parentserver (assigned only in the ID branch,
    # read unconditionally by the output object - B batch finding 11)
    $parentserver = $__state.parentserver

    foreach ($instance in $SqlInstance) {
        $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Name
    }

    if (-not $SqlInstance -and -not $InputObject) {
        $InputObject += Get-DbaRegServerGroup -Group $Name
    }

    foreach ($regservergroup in $InputObject) {
        if ($regservergroup.ID) {
            $parentserver = Get-RegServerParent -InputObject $regservergroup
            $target = $parentserver.DomainInstanceName
            if ($null -eq $parentserver) {
                Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue -FunctionName Remove-DbaRegServerGroup
            }
            $defaults = "ComputerName", "InstanceName", "SqlInstance", "Name", "Status"
        } else {
            $target = "Local Registered Servers"
            $defaults = "Name", "Status"
        }

        if ($__realCmdlet.ShouldProcess($target, "Removing $($regservergroup.Name) Group")) {
            if ($regservergroup.Source -eq "Azure Data Studio") {
                Stop-Function -Message "You cannot use dbatools to remove or add registered server groups in Azure Data Studio" -Continue -FunctionName Remove-DbaRegServerGroup
            }

            # try to avoid 'Collection was modified after the enumerator was instantiated' issue
            if ($regservergroup.ID) {
                $null = $parentserver.ServerConnection.ExecuteNonQuery($regservergroup.ScriptDrop().GetScript())
                $parentserver.ServerConnection.Disconnect()
            } else {
                $regservergroup.Drop()
            }

            try {
                [PSCustomObject]@{
                    ComputerName = $parentserver.ComputerName
                    InstanceName = $parentserver.InstanceName
                    SqlInstance  = $parentserver.SqlInstance
                    Name         = $regservergroup.Name
                    Status       = "Dropped"
                } | Select-DefaultView -Property $defaults
            } catch {
                Stop-Function -Message "Failed to drop $regservergroup on $parentserver" -ErrorRecord $_ -Continue -FunctionName Remove-DbaRegServerGroup
            }
        }
    }

    @{ __w3080State = @{ parentserver = $parentserver } }
} $SqlInstance $SqlCredential $Name $InputObject $EnableException $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
