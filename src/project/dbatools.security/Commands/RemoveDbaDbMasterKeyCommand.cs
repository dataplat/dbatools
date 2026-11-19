#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes database master keys from one or more SQL Server databases.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the DROP MASTER KEY execution,
/// the ShouldProcess gate, the output shape, and dbatools stream and error handling stay observable-identical
/// to the script implementation.
/// </para>
/// <para>
/// The command is process-only and mutating, so it ships as a single hop per record and streams its output
/// through InvokeScopedStreaming: InputObject is ValueFromPipeline and the body emits one object per master
/// key dropped, so a downstream early stop must halt before the remaining keys are dropped - exactly as the
/// script's pipeline does. SqlInstance is not ValueFromPipeline, so the only pipeline target is InputObject,
/// which rebinds each record - there is no cross-record accumulation of the script's $InputObject +=. The
/// early "you must specify Database, ExcludeDatabase or All" Stop-Function then return runs inside the
/// per-record hop, so the return skips only that record. The DROP is executed via the SMO
/// $masterkey.Parent.Query method (verbatim, not Invoke-DbaQuery). The callback dispatches ErrorRecords to
/// WriteError, else WriteObject. EnableException and All are carried as plain (untyped) values, because a
/// switch in the inner CmdletBinding scriptblock is excluded from positional binding. The two DIRECT
/// Stop-Function calls take -FunctionName; $Pscmdlet is redirected to the real cmdlet ($__realCmdlet) for the
/// ShouldProcess gate.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaDbMasterKey", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaDbMasterKeyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The databases to remove master keys from.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The databases to skip when using -All.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Removes master keys from all user databases on the instance.</summary>
    [Parameter]
    public SwitchParameter All { get; set; }

    /// <summary>MasterKey objects from Get-DbaDbMasterKey for pipeline operations.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.MasterKey[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Removes master keys for one pipeline record.</summary>
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, All.ToBool(), InputObject, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet (the ShouldProcess gate);
    // -FunctionName on the two DIRECT Stop-Function calls. EnableException and All received untyped.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $All, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, $All, [Microsoft.SqlServer.Management.Smo.MasterKey[]]$InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if ($SqlInstance) {
            if (-not $Database -and -not $ExcludeDatabase -and -not $All) {
                Stop-Function -Message "You must specify Database, ExcludeDatabase or All when using SqlInstance" -FunctionName Remove-DbaDbMasterKey
                return
            }
            # all does not need to be addressed in the code because it gets all the dbs if $databases is empty
            $databases = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
            if ($databases) {
                foreach ($key in $databases.MasterKey) {
                    $InputObject += $key
                }
            }
        }

        foreach ($masterkey in $InputObject) {
            $server = $masterkey.Parent.Parent
            $db = $masterkey.Parent
            if ($__realCmdlet.ShouldProcess($server.Name, "Removing master key on $($db.Name)")) {
                # avoid enumeration issues
                try {
                    $masterkey.Parent.Query("DROP MASTER KEY")
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.Name
                        Status       = "Master key removed"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Remove-DbaDbMasterKey
                }
            }
        }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $All $InputObject $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
