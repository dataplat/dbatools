#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Kills an external process (xp_cmdshell child etc.) on a target computer. Port of
/// public/Stop-DbaExternalProcess.ps1 (W3-102). WHOLE-RECORD verbatim hop.
/// CLASSIFICATION TABLE (ComputerName/Credential/ProcessId are ByPropertyName
/// pipeline-bound; promoted question answered): no param mutations; $name is
/// per-iteration - no sentinel. The gate routes to the REAL cmdlet
/// ($Pscmdlet -> $__realCmdlet, ConfirmImpact High, hold-free). Checklist greps done:
/// Get-DbaCmObject and Invoke-Command2 both carry no Get-PSCallStack and no
/// scope-walking defaults; hop-frame Stop-Function carries -FunctionName (W1-090). The
/// source's "$name".ToString() null-shield (comment preserved), the whole-body
/// try/catch with -Continue, and the Invoke-Command2 $args-positional Stop-Process
/// scriptblock ride verbatim. Bind-time cast: [PsIntCast] on ProcessId (W1-043:
/// explicit null binds 0 exactly like the script binder). NO WarningAction carrier
/// (codex W3-005 r3). Surface pinned by
/// migration/baselines/Stop-DbaExternalProcess.json (no sets, implicit positions:
/// ComputerName SCALAR Mandatory pos0 ByPropertyName, Credential pos1 ByPropertyName,
/// ProcessId int pos2 ByPropertyName alias pid, ConfirmImpact High).
/// </summary>
[Cmdlet(VerbsLifecycle.Stop, "DbaExternalProcess", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class StopDbaExternalProcessCommand : DbaBaseCmdlet
{
    /// <summary>The target computer.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 0)]
    public DbaInstanceParameter ComputerName { get; set; } = null!;

    /// <summary>Windows credential for the remote work.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>The process id to kill.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 2)]
    [Alias("pid")]
    [PsIntCast]
    public int ProcessId { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // Codex r1: a fresh reference-identity marker instead of a keyed Hashtable -
        // command output (Invoke-Command2's flows to the pipeline here) can never
        // collide with an object the caller just allocated (smoke S9 regression-pins a
        // deliberately colliding hashtable passing through as ordinary output).
        object continueMarker = new object();
        bool continueEscaped = false;
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (ReferenceEquals(item?.BaseObject, continueMarker))
            {
                continueEscaped = true;
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
            ComputerName, Credential, ProcessId, EnableException.ToBool(), this,
            continueMarker,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));

        // CONTINUE RELAY, C# half: the hop completed (output drained, warnings
        // replayed); now let the source's escaped `continue` leave this cmdlet exactly
        // like it leaves the function - a second invocation whose only statement is
        // `continue` throws the engine's own flow-control with nothing buffered.
        if (continueEscaped)
        {
            foreach (PSObject? _ in NestedCommand.InvokeScoped(this, ContinueRelayScript))
            {
            }
        }
    }

    // PS: the engine-authored `continue` for the relay above.
    private const string ContinueRelayScript = """
continue
""";

    // PS: the ENTIRE process body VERBATIM per record. Substitutions only:
    // $Pscmdlet -> $__realCmdlet on the gate and explicit -FunctionName
    // Stop-DbaExternalProcess on the hop-frame Stop-Function (W1-090).
    private const string ProcessScript = """
param($ComputerName, $Credential, $ProcessId, $EnableException, $__realCmdlet, $__continueMarker, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$ComputerName, [PSCredential]$Credential, [int]$ProcessId, $EnableException, $__realCmdlet, $__continueMarker, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # CONTINUE RELAY, script half (this row's r2/r3 finding): the source's catch runs
    # Stop-Function -Continue in a LOOP-LESS process block, so the `continue` escapes
    # the command into the caller. A flow-control exception leaving this scriptblock
    # discards InvokeScoped's buffered output AND its warning replay (the just-merged
    # warning vanished - legacy streams it before the escape). The guard loop absorbs
    # the escape so the invocation COMPLETES (buffer drained, warnings replayed) and a
    # sentinel tells the C# side to re-issue the `continue` afterwards.
    $__continueEscaped = $true
    foreach ($__continueRelayGuard in @(1)) {
        . {
            try {
                # gotta add ToString(), otherwise it returns null after the process is killed
                $name = (Get-DbaCmObject -ComputerName $ComputerName -Credential $Credential -ClassName win32_process | Where-Object ProcessId -eq $ProcessId).ProcessName
                $name = "$name".ToString()

                if ($__realCmdlet.ShouldProcess($ComputerName, "Killing PID $ProcessId ($name)")) {
                    Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
                        Stop-Process -Id $args -Force -Confirm:$false
                    } -ArgumentList $ProcessId -ErrorAction Stop

                    [PSCustomObject]@{
                        ComputerName = $ComputerName
                        ProcessId    = $ProcessId
                        Name         = $name
                        Status       = "Stopped"
                    }
                }
            } catch {
                Stop-Function -Message "Error killing $ProcessId on $ComputerName" -ErrorRecord $_ -Continue -FunctionName Stop-DbaExternalProcess
            }
        }
        $__continueEscaped = $false
    }
    if ($__continueEscaped) { $__continueMarker }
} $ComputerName $Credential $ProcessId $EnableException $__realCmdlet $__continueMarker $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
