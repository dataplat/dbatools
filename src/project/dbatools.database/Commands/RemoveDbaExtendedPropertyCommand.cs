#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Drops extended properties. Port of public/Remove-DbaExtendedProperty.ps1; the workflow remains a
/// module-scoped PowerShell compatibility hop.
///
/// Stateless: the source has no begin block, and $object and $db are each assigned and read within a
/// single loop iteration, so nothing rides a state sentinel. There is no instance loop - the only
/// loop is over the piped $InputObject - so the per-element hop question does not arise.
///
/// The ShouldProcess gate is routed to the OUTER cmdlet ($Pscmdlet becomes $__realCmdlet). That
/// matters more here than on most rows: ConfirmImpact is High, so this command prompts by default,
/// and -Confirm's "Yes to All" answer is held on the invoking runtime. A gate owned by the inner
/// scriptblock would forget that answer on the next pipeline record and re-prompt for every
/// property - which, for a caller piping a hundred properties in to be dropped, is the difference
/// between one prompt and a hundred.
///
/// No graceful-stop latch: the source has no Test-FunctionInterrupt guard, and its only
/// Stop-Function is -Continue, which does not set the stop latch in the first place.
///
/// The hop streams rather than buffers. This command DROPS extended properties and each emitted
/// object is the record of one that was actually dropped, so a buffered invocation would discard the
/// audit trail of completed drops if a later property threw under -EnableException.
///
/// The nested Get-ConnectionParent helper resolves through the module scope and derives nothing from
/// the call stack, so it needs no named-wrapper shim.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaExtendedProperty", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed class RemoveDbaExtendedPropertyCommand : DbaBaseCmdlet
{
    /// <summary>The extended property or properties to drop, typically from Get-DbaExtendedProperty.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.ExtendedProperty[]? InputObject { get; set; }

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
        }, BodyScript,
            InputObject, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source's process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet so the
    // gate is owned by the outer cmdlet, and -FunctionName on Stop-Function.
    private const string BodyScript = """
param($InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Microsoft.SqlServer.Management.Smo.ExtendedProperty[]]$InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        foreach ($object in $InputObject) {
            if ($__realCmdlet.ShouldProcess($object.Name, "Dropping")) {
                $db = $object | Get-ConnectionParent -Database
                try {
                    $null = $db.Invoke("EXEC sp_dropextendedproperty @name = N'$($object.Name)'; ")
                    [PSCustomObject]@{
                        ComputerName = $object.ComputerName
                        InstanceName = $object.InstanceName
                        SqlInstance  = $object.SqlInstance
                        ParentName   = $object.ParentName
                        PropertyType = $object.Type
                        Name         = $object.Name
                        Status       = "Dropped"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Remove-DbaExtendedProperty
                }
            }
        }

} $InputObject $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
