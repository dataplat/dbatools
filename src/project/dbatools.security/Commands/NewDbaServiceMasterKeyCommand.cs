#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a database master key in the master database of one or more SQL Server instances.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the master-key creation,
/// the ShouldProcess gate, the output shape, and dbatools stream and error handling stay
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// The command is process-only and mutating, so it ships as a single hop per record and streams its
/// output through InvokeScopedStreaming. Because SqlInstance binds an array within a record, a downstream
/// early stop (a consumer taking only the first result) must halt the work before the remaining instances
/// are created - exactly as the script's pipeline does; the streaming helper propagates that stop, where a
/// buffered call would run the whole record to completion and create keys the script never would.
/// </para>
/// <para>
/// The SecurePassword rides into the hop as a live SecureString and is handed to the nested
/// New-DbaDbMasterKey call inside the ShouldProcess gate, so it is never flattened or logged and is used
/// only at the same point the script uses it. EnableException is carried as a plain (untyped) value,
/// because a switch in the inner CmdletBinding scriptblock is excluded from positional binding.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaServiceMasterKey", SupportsShouldProcess = true)]
public sealed class NewDbaServiceMasterKeyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>A credential whose password secures the master key when SecurePassword is not supplied.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>The password that secures the new master key.</summary>
    [Parameter(Position = 3)]
    [Alias("Password")]
    public System.Security.SecureString? SecurePassword { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Creates the service master key for one pipeline record.</summary>
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
            SqlInstance, SqlCredential, Credential, SecurePassword, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM. Substitution only: $Pscmdlet -> $__realCmdlet (the ShouldProcess gate).
    // No Stop-Function, Write-Message, Test-Bound, or config defaults. The SecureString rides live and is
    // used only inside the gate; EnableException is received untyped.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Credential, $SecurePassword, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [System.Management.Automation.PSCredential]$Credential, [System.Security.SecureString]$SecurePassword, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        foreach ($instance in $SqlInstance) {
            if ($__realCmdlet.ShouldProcess("$instance", "Creating new master key")) {
                New-DbaDbMasterKey -SqlInstance $instance -SqlCredential $SqlCredential -Database master -SecurePassword $SecurePassword -Credential $Credential
            }
        }
} $SqlInstance $SqlCredential $Credential $SecurePassword $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
