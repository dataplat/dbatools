#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes database certificates from one or more SQL Server databases.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the DROP CERTIFICATE execution,
/// the ShouldProcess gate, the output shape, and dbatools stream and error handling stay observable-identical
/// to the script implementation.
/// </para>
/// <para>
/// The command is process-only and mutating, so it ships as a single hop per record and streams its output
/// through InvokeScopedStreaming: InputObject is ValueFromPipeline and the body emits one object per
/// certificate dropped, so a downstream early stop must halt before the remaining certificates are dropped -
/// exactly as the script's pipeline does; a buffered call would run the whole record to completion and drop
/// certificates the script never would. SqlInstance is not ValueFromPipeline, so the only pipeline target is
/// InputObject, which rebinds each record - there is no cross-record accumulation of the script's
/// $InputObject +=. The callback dispatches ErrorRecords to WriteError, else WriteObject. EnableException is
/// carried as a plain (untyped) value, because a switch in the inner CmdletBinding scriptblock is excluded
/// from positional binding. Only the two DIRECT Write-Message/Stop-Function calls take -FunctionName;
/// $Pscmdlet is redirected to the real cmdlet ($__realCmdlet) for the ShouldProcess gate.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaDbCertificate", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaDbCertificateCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The target databases containing certificates to remove.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The names of certificates to remove.</summary>
    [Parameter(Position = 3)]
    public string[]? Certificate { get; set; }

    /// <summary>Certificate objects from Get-DbaDbCertificate for pipeline operations.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.Certificate[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Removes certificates for one pipeline record.</summary>
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
            SqlInstance, SqlCredential, Database, Certificate, InputObject, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet (the ShouldProcess gate);
    // -FunctionName on the two DIRECT Write-Message/Stop-Function calls. The Stop-Function -Target $smocert
    // references an undefined variable in the source (a source typo); it is preserved verbatim. EnableException
    // received untyped.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Certificate, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Certificate, [Microsoft.SqlServer.Management.Smo.Certificate[]]$InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if ($SqlInstance) {
            $InputObject += Get-DbaDbCertificate -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Certificate $Certificate -Database $Database
        }
        foreach ($cert in $InputObject) {
            $db = $cert.Parent
            $server = $db.Parent

            if ($__realCmdlet.ShouldProcess($server.Name, "Dropping the certificate named $cert for database $db")) {
                try {
                    # erroractionprefs are not invoked for .net methods suddenly (??), so use Invoke-DbaQuery
                    # Avoids modifying the collection
                    Invoke-DbaQuery -SqlInstance $server -Database $db.Name -Query "DROP CERTIFICATE $cert" -EnableException
                    Write-Message -Level Verbose -Message "Successfully removed certificate named $cert from the $db database on $server" -FunctionName Remove-DbaDbCertificate -ModuleName "dbatools"
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.Name
                        Certificate  = $cert.Name
                        Status       = "Success"
                    }
                } catch {
                    Stop-Function -Message "Failed to drop certificate named $($cert.Name) from $($db.Name) on $($server.Name)." -Target $smocert -ErrorRecord $_ -Continue -FunctionName Remove-DbaDbCertificate
                }
            }
        }
} $SqlInstance $SqlCredential $Database $Certificate $InputObject $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
