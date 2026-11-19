#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoAgentAlert = Microsoft.SqlServer.Management.Smo.Agent.Alert;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Modifies properties of existing SQL Server Agent alerts.
/// </summary>
/// <remarks>
/// The instance connection, the alert lookup/validation, the rename/enable/disable option handling, the
/// Alter, and the output all run the original dbatools PowerShell body inside the dbatools module scope
/// rather than being reimplemented in C#, so the engine decides the observable details.
///
/// InputObject is the only pipeline-bound parameter; the body gathers each SqlInstance/Alert match into
/// $InputObject (a VFP param rebound per record, so the += stays within one record) and then updates every
/// alert. Every other local is per-iteration, so there is no cross-record DATA state.
///
/// There IS cross-record CONTROL state: the process block starts with Test-FunctionInterrupt and its
/// no-Continue Stop-Functions (the "no alert/InputObject" guard - which also returns - and the
/// "alert doesn't exist" check) set the function-scope interrupt. That interrupt is written at -Scope 1 of
/// the process hop's own scriptblock and dies with the hop, so the process hop reads it with
/// Get-Variable -Scope 0 after a dot-sourced body and reports it in a sentinel; the C# field then guards
/// subsequent records (the in-hop Test-FunctionInterrupt is preserved verbatim but inert - the C# guard
/// short-circuits an already-interrupted record). Under -EnableException those Stop-Functions throw instead,
/// terminating the record. Note the "alert doesn't exist" Stop-Function has NO explicit return after it, so
/// (matching the source) it sets the interrupt but the current record keeps processing; only later records
/// are skipped.
///
/// The begin block's "if (\$Force) { \$ConfirmPreference = 'none' }" is folded into the top of the process
/// hop with \$__gate = if (\$Force) { \$PSCmdlet } else { \$__realCmdlet }; under -Force the inner \$PSCmdlet
/// reads the hop scope's lowered preference (the New-DbaAgentAlertCategory pattern).
///
/// Output streams: each altered alert is emitted before a later one may fail under -EnableException, so the
/// hop streams. Surface pinned by migration/baselines/Set-DbaAgentAlert.json.
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaAgentAlert", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class SetDbaAgentAlertCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) of the SQL Agent alerts to modify.</summary>
    [Parameter(Position = 2)]
    public object[]? Alert { get; set; }

    /// <summary>A new name for the alert being modified.</summary>
    [Parameter(Position = 3)]
    public string? NewName { get; set; }

    /// <summary>Enables the specified alert(s).</summary>
    [Parameter]
    public SwitchParameter Enabled { get; set; }

    /// <summary>Disables the specified alert(s).</summary>
    [Parameter]
    public SwitchParameter Disabled { get; set; }

    /// <summary>Bypass the confirmation prompt.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>Agent alert objects piped in from Get-DbaAgentAlert.</summary>
    [Parameter(Position = 4, ValueFromPipeline = true)]
    public SmoAgentAlert[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    // The function-scope interrupt set by the process block's no-Continue Stop-Functions; carried across
    // records (Stop-Function writes it in the process hop's scope, which dies with that hop).
    private bool _interrupted;

    protected override void ProcessRecord()
    {
        if (Interrupted || _interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__setDbaAgentAlertProcess"))
            {
                if (sentinel["__setDbaAgentAlertProcess"] is Hashtable state)
                {
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BodyScript,
            SqlInstance, SqlCredential, Alert, NewName, Enabled.ToBool(), Disabled.ToBool(), Force.ToBool(),
            InputObject, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__gate.ShouldProcess and
    // -FunctionName Set-DbaAgentAlert on the direct Stop-Function/Write-Message sites. The begin's
    // Force/ConfirmPreference line and the gate selection are prepended (folded from begin). The body is
    // dot-sourced so the two early returns (Test-FunctionInterrupt and the empty-arg guard) exit only the
    // block, after which the interrupt flag is read at Get-Variable -Scope 0 and reported in a sentinel.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Alert, $NewName, $Enabled, $Disabled, $Force, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Alert, [string]$NewName, $Enabled, $Disabled, $Force, [Microsoft.SqlServer.Management.Smo.Agent.Alert[]]$InputObject, $EnableException, $__realCmdlet)
    if ($Force) { $ConfirmPreference = 'none' }
    $__gate = if ($Force) { $PSCmdlet } else { $__realCmdlet }
    . {
        if (Test-FunctionInterrupt) { return }

        if ((-not $InputObject) -and (-not $Alert)) {
            Stop-Function -Message "You must specify an alert name or pipe in results from another command" -Target $SqlInstance -FunctionName Set-DbaAgentAlert
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaAgentAlert
            }
            foreach ($a in $Alert) {
                # Check if the alert exists
                if ($server.JobServer.Alerts.Name -notcontains $a) {
                    Stop-Function -Message "Alert $a doesn't exists on $instance" -Target $instance -FunctionName Set-DbaAgentAlert
                } else {
                    # Get the alert
                    try {
                        $InputObject += $server.JobServer.Alerts[$a]

                        # Refresh the object
                        $InputObject.Refresh()
                    } catch {
                        Stop-Function -Message "Something went wrong retrieving the alert" -Target $a -ErrorRecord $_ -Continue -FunctionName Set-DbaAgentAlert
                    }
                }
            }
        }

        foreach ($currentAlert in $InputObject) {
            $server = $currentAlert.Parent.Parent

            #region alert options
            # Settings the options for the alert
            if ($NewName) {
                if ($__gate.ShouldProcess($server, "Setting alert name to $NewName for $currentAlert")) {
                    $currentAlert.Rename($NewName)
                }
            }

            if ($Enabled) {
                Write-Message -Message "Setting alert to enabled" -Level Verbose -FunctionName Set-DbaAgentAlert -ModuleName "dbatools"
                $currentAlert.IsEnabled = $true
            }

            if ($Disabled) {
                Write-Message -Message "Setting alert to disabled" -Level Verbose -FunctionName Set-DbaAgentAlert -ModuleName "dbatools"
                $currentAlert.IsEnabled = $false
            }

            #endregion alert options

            # Execute
            if ($__gate.ShouldProcess($SqlInstance, "Committing changes for alert $a")) {
                try {
                    Write-Message -Message "Committing changes for alert $a" -Level Verbose -FunctionName Set-DbaAgentAlert -ModuleName "dbatools"

                    # Change the alert
                    $currentAlert.Alter()
                } catch {
                    Stop-Function -Message "Something went wrong changing the alert" -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaAgentAlert
                }
                Get-DbaAgentAlert -SqlInstance $server | Where-Object Name -eq $currentAlert.name
            }
        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __setDbaAgentAlertProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $SqlCredential $Alert $NewName $Enabled $Disabled $Force $InputObject $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
