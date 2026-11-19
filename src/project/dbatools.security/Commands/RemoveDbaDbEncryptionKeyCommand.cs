#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes database encryption keys from one or more SQL Server databases to disable Transparent Data
/// Encryption.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the DROP DATABASE ENCRYPTION KEY
/// execution, the ShouldProcess gate, the output shape, and dbatools stream and error handling stay
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// The command is process-only and mutating, so it ships as a single hop per record and streams its output
/// through InvokeScopedStreaming: InputObject is ValueFromPipeline and the body emits one object per key
/// dropped, so a downstream early stop must halt before the remaining keys are dropped - exactly as the
/// script's pipeline does. SqlInstance is not ValueFromPipeline, so the only pipeline target is InputObject,
/// which rebinds each record - there is no cross-record accumulation of the script's $InputObject +=. The
/// early "you must specify Database" Stop-Function then return runs inside the per-record hop, so the return
/// skips only that record, matching the script's process block. The callback dispatches ErrorRecords to
/// WriteError, else WriteObject. EnableException is carried as a plain (untyped) value, because a switch in
/// the inner CmdletBinding scriptblock is excluded from positional binding. The three DIRECT
/// Stop-Function/Write-Message calls take -FunctionName; $Pscmdlet is redirected to the real cmdlet
/// ($__realCmdlet) for the ShouldProcess gate.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaDbEncryptionKey", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaDbEncryptionKeyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The databases from which to remove the database encryption key.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>DatabaseEncryptionKey objects from Get-DbaDbEncryptionKey for pipeline operations.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public Microsoft.SqlServer.Management.Smo.DatabaseEncryptionKey[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Removes encryption keys for one pipeline record.</summary>
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
            SqlInstance, SqlCredential, Database, InputObject, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet (the ShouldProcess gate);
    // -FunctionName on the three DIRECT Stop-Function/Write-Message calls. EnableException received untyped.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Database, [Microsoft.SqlServer.Management.Smo.DatabaseEncryptionKey[]]$InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if ($SqlInstance) {
            if (-not $Database) {
                Stop-Function -Message "You must specify Database when using the SqlInstance parameter" -FunctionName Remove-DbaDbEncryptionKey
                return
            }

            $InputObject += Get-DbaDbEncryptionKey -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }
        foreach ($key in $InputObject) {
            $db = $key.Parent
            $server = $db.Parent
            if ($__realCmdlet.ShouldProcess($server.Name, "Dropping the encryption key for database $db")) {
                try {
                    # Avoids modifying the collection
                    Invoke-DbaQuery -SqlInstance $server -Database $db.Name -Query "DROP DATABASE ENCRYPTION KEY" -EnableException
                    Write-Message -Level Verbose -Message "Successfully removed encryption key from the $db database on $server" -FunctionName Remove-DbaDbEncryptionKey -ModuleName "dbatools"
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.Name
                        Status       = "Success"
                    }
                } catch {
                    Stop-Function -Message "Failed to drop encryption key from $($db.Name) on $($server.Name)." -Target $db -ErrorRecord $_ -Continue -FunctionName Remove-DbaDbEncryptionKey
                }
            }
        }
} $SqlInstance $SqlCredential $Database $InputObject $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
