#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes SQL Server logins from one or more target instances.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the login drop, the dependency
/// and session handling, the ShouldProcess gate, the output shape, and dbatools stream and error handling stay
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// The command is process-only and mutating, so it ships as a single hop per record and streams its output
/// through InvokeScopedStreaming: InputObject is ValueFromPipeline and the body emits one object per login
/// processed, so a downstream early stop must halt before the remaining logins are dropped - exactly as the
/// script's pipeline does. SqlInstance is a plain (non-pipeline) parameter in the "instance" set, so the only
/// pipeline target is InputObject (the "Logins" set), which rebinds each record - there is no cross-record
/// accumulation of the script's $InputObject +=. The script's begin block (if ($Force) { $ConfirmPreference =
/// 'none' }) is folded verbatim into the per-record hop, ahead of the process body: it is deterministic and
/// idempotent, and $__realCmdlet.ShouldProcess reads that hop-scope $ConfirmPreference at call time, so -Force
/// suppresses the confirm prompt exactly as the script does (the same technique as the CLEAN Copy-Dba* hops).
/// The callback dispatches ErrorRecords to WriteError, else WriteObject. EnableException and Force are carried
/// as plain (untyped) values, because a switch in the inner CmdletBinding scriptblock is excluded from
/// positional binding. The three DIRECT Stop-Function/Write-Message calls take -FunctionName; $Pscmdlet is
/// redirected to the real cmdlet ($__realCmdlet) for the ShouldProcess gate (that redirect is the fourth
/// edit). Stop-DbaProcess and
/// Remove-TeppCacheItem are nested calls, left unedited.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaLogin", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "Default")]
public sealed class RemoveDbaLoginCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "instance")]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The SQL Server login names to remove.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "instance")]
    public string[]? Login { get; set; }

    /// <summary>Login objects piped from Get-DbaLogin.</summary>
    [Parameter(ValueFromPipeline = true, Mandatory = true, ParameterSetName = "Logins")]
    public Microsoft.SqlServer.Management.Smo.Login[]? InputObject { get; set; }

    /// <summary>Terminates active sessions for the login before removal.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Removes logins for one pipeline record.</summary>
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
            SqlInstance, SqlCredential, Login, InputObject, Force.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block (if ($Force) { $ConfirmPreference = 'none' }) folded verbatim, then the process body
    // VERBATIM. Four edits: $Pscmdlet -> $__realCmdlet (the ShouldProcess gate) plus -FunctionName on the
    // three DIRECT Stop-Function/Write-Message calls. EnableException and Force received untyped.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Login, $InputObject, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Login, [Microsoft.SqlServer.Management.Smo.Login[]]$InputObject, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if ($Force) { $ConfirmPreference = 'none' }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Remove-DbaLogin
            }

            $foundLogins = $server.Logins | Where-Object { $_.Name -in $Login }
            $foundLoginNames = $foundLogins.Name

            # Warn if specific logins were requested but not found
            foreach ($requestedLogin in $Login) {
                if ($requestedLogin -notin $foundLoginNames) {
                    Write-Message -Level Warning -Message "Login '$requestedLogin' not found on instance $instance" -FunctionName Remove-DbaLogin -ModuleName "dbatools"
                }
            }

            $InputObject += $foundLogins
        }

        foreach ($currentlogin in $InputObject) {
            try {
                $server = $currentlogin.Parent
                if ($__realCmdlet.ShouldProcess("$currentlogin on $server", "KillLogin")) {
                    if ($force) {
                        $null = Stop-DbaProcess -SqlInstance $server -Login $currentlogin.name
                    }

                    $currentlogin.Drop()

                    Remove-TeppCacheItem -SqlInstance $server -Type login -Name $currentlogin.name

                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Login        = $currentlogin.name
                        Status       = "Dropped"
                    }
                }
            } catch {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Login        = $currentlogin.name
                    Status       = $_
                }
                Stop-Function -Message "Could not drop Login $currentlogin on $server" -ErrorRecord $_ -Target $currentlogin -Continue -FunctionName Remove-DbaLogin
            }
        }
} $SqlInstance $SqlCredential $Login $InputObject $Force $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
