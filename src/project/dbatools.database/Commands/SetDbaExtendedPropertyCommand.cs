#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets the value of an extended property. Port of public/Set-DbaExtendedProperty.ps1; the
/// workflow remains a module-scoped PowerShell compatibility hop.
///
/// The source has no begin block and no cross-record state: $object is the element loop variable,
/// assigned and read within one iteration, so nothing rides a sentinel here.
///
/// The ShouldProcess gate is routed to the OUTER cmdlet. The hop body's $Pscmdlet.ShouldProcess
/// becomes $__realCmdlet.ShouldProcess, where $__realCmdlet is this cmdlet instance passed into the
/// hop. That matters for more than attribution: -Confirm's "Yes to All" / "No to All" answer is held
/// on the invoking runtime, so a gate owned by the inner scriptblock would forget the answer on the
/// next pipeline record and re-prompt for every object. Routing to the outer cmdlet keeps that state
/// where it already persists, which is why this port needs no prompt-state transplant.
///
/// The hop streams rather than buffers. This command MUTATES server state - each emitted object is
/// the record of a property that was actually altered - and a buffered invocation would discard the
/// records of already-altered properties if a later object threw under -EnableException.
///
/// -WhatIf and -Confirm ride explicit carriers rather than being inherited, because the hop is a
/// separate invocation and would not otherwise see the caller's preference.
///
/// $EnableException is passed into the hop because Stop-Function's own parameter block defaults it
/// from the caller's scope. The in-hop Stop-Function and Write-Message carry -FunctionName, because
/// both derive the reporting command from the call stack, which is a scriptblock in a hop.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaExtendedProperty", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed class SetDbaExtendedPropertyCommand : DbaBaseCmdlet
{
    /// <summary>The extended property or properties to update, typically from Get-DbaExtendedProperty.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.ExtendedProperty[]? InputObject { get; set; }

    /// <summary>The new value for the extended property.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [PsStringCast]
    public string? Value { get; set; }

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
            InputObject, Value, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source's process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet so the
    // gate is owned by the outer cmdlet, and -FunctionName on Stop-Function/Write-Message.
    private const string BodyScript = """
param($InputObject, $Value, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Microsoft.SqlServer.Management.Smo.ExtendedProperty[]]$InputObject, [string]$Value, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        foreach ($object in $InputObject) {
            if ($__realCmdlet.ShouldProcess($object.Name, "Updating value from '$($object.Value)' to '$Value'")) {
                try {
                    Write-Message -Level System -Message "Updating value from '$($object.Value)' to '$Value'" -FunctionName Set-DbaExtendedProperty -ModuleName "dbatools"
                    $object.Value = $Value
                    $object.Alter()
                    $object.Refresh()
                    $object
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Set-DbaExtendedProperty
                }
            }
        }

} $InputObject $Value $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
