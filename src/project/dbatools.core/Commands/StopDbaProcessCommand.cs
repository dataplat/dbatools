#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Kills SQL Server sessions (spids). Port of public/Stop-DbaProcess.ps1 (W3-103).
/// WHOLE-RECORD verbatim hop. CLASSIFICATION TABLE (InputObject is VFP in the Process
/// set; promoted question answered): $InputObject is reassigned only on the
/// no-pipeline sets (single record), all other locals per-iteration - no sentinel.
/// $PSBOUNDPARAMETERS CLASS (the W3-090 technique): the source snapshots
/// $PSBoundParameters, strips WhatIf/Confirm and SPLATS Get-DbaProcess with the rest -
/// the hop's own automatic variable holds hop params, so the C# side passes
/// `new Hashtable(MyInvocation.BoundParameters)` per record and the hop substitutes
/// $bound = $__boundParameters (the source's in-place .Remove mutation of the live
/// automatic variable has no later reader - the copy is observation-identical). Both
/// `Continue` sites sit INSIDE the source's foreach (absorbed there - the W3-102
/// continue-relay class does NOT apply); the InvalidData `return` after a latching
/// Stop-Function exits the record's hop exactly like it exits process, and the
/// verbatim Test-FunctionInterrupt gate carries the latch to later records. Gates
/// route to the REAL cmdlet ($Pscmdlet -> $__realCmdlet). Checklist greps done:
/// Get-DbaProcess is a scope-walk-free, callstack-free PS function; hop-frame
/// Stop-Function/Write-Message carry -FunctionName (W1-090). No bind-time casts:
/// Spid/ExcludeSpid/string filters are non-mandatory and unvalidated (outside the
/// ratified cast laws). NO WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Stop-DbaProcess.json (sets Default/Server/Process - NO
/// positions per the sets-exist law; SqlInstance SCALAR Mandatory in Server;
/// InputObject object[] Mandatory VFP in Process; default set Default).
/// </summary>
[Cmdlet(VerbsLifecycle.Stop, "DbaProcess", SupportsShouldProcess = true, DefaultParameterSetName = "Default")]
public sealed class StopDbaProcessCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance (Server set).</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Server")]
    public DbaInstanceParameter SqlInstance { get; set; } = null!;

    /// <summary>Credential for SQL Server authentication.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Spid(s) to kill.</summary>
    [Parameter]
    public int[]? Spid { get; set; }

    /// <summary>Spid(s) to exclude.</summary>
    [Parameter]
    public int[]? ExcludeSpid { get; set; }

    /// <summary>Database filter.</summary>
    [Parameter]
    public string[]? Database { get; set; }

    /// <summary>Login filter.</summary>
    [Parameter]
    public string[]? Login { get; set; }

    /// <summary>Host filter.</summary>
    [Parameter]
    public string[]? Hostname { get; set; }

    /// <summary>Program filter.</summary>
    [Parameter]
    public string[]? Program { get; set; }

    /// <summary>Process objects from Get-DbaProcess (Process set).</summary>
    [Parameter(ValueFromPipeline = true, Mandatory = true, ParameterSetName = "Process")]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        if (_hopInterrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3103State"))
            {
                Hashtable? latch = sentinel["__w3103State"] as Hashtable;
                if (latch is not null && LanguagePrimitives.IsTrue(latch["interrupted"]))
                {
                    _hopInterrupted = true;
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
        }, ProcessScript,
            InputObject, new Hashtable(MyInvocation.BoundParameters),
            EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // CROSS-RECORD LATCH (the W3-066 carry): Stop-Function's non-Continue path sets
    // the interrupt flag with -Scope 1 - in the source that is the FUNCTION scope
    // (spans the pipeline), in the hop it dies with the record. The hop reports the
    // flag through the sentinel and this gate skips later records exactly like the
    // source's Test-FunctionInterrupt (smoke S3: a bad piped record latches, the next
    // record produces nothing).
    private bool _hopInterrupted;

    // PS: the ENTIRE process body VERBATIM per record. Substitutions only:
    // $bound = $PSBoundParameters -> the carried per-record copy (W3-090 technique),
    // $Pscmdlet -> $__realCmdlet on the gate, and explicit -FunctionName
    // Stop-DbaProcess on hop-frame Stop-Function/Write-Message (W1-090).
    private const string ProcessScript = """
param($InputObject, $__boundParameters, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([object[]]$InputObject, $__boundParameters, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject) {
            $bound = $__boundParameters
            $null = $bound.Remove("WhatIf")
            $null = $bound.Remove("Confirm")
            $InputObject = Get-DbaProcess @bound
        }

        foreach ($session in $InputObject) {
            $sourceserver = $session.Parent

            if (!$sourceserver) {
                Stop-Function -Message "Only process objects can be passed through the pipeline." -Category InvalidData -Target $session -FunctionName Stop-DbaProcess
                return
            }

            $currentspid = $session.spid

            if ($sourceserver.ConnectionContext.ProcessID -eq $currentspid) {
                Write-Message -Level Warning -Message "Skipping spid $currentspid because you cannot use KILL to kill your own process." -Target $session -FunctionName Stop-DbaProcess -ModuleName "dbatools"
                Continue
            }

            if ($__realCmdlet.ShouldProcess($sourceserver, "Killing spid $currentspid")) {
                try {
                    $sourceserver.KillProcess($currentspid)
                    [PSCustomObject]@{
                        SqlInstance = $sourceserver.name
                        Spid        = $session.Spid
                        Login       = $session.Login
                        Host        = $session.Host
                        Database    = $session.Database
                        Program     = $session.Program
                        Status      = 'Killed'
                    }
                } catch {
                    Stop-Function -Message "Couldn't kill spid $currentspid." -Target $session -ErrorRecord $_ -Continue -FunctionName Stop-DbaProcess
                }
            }
        }
    }
    # CROSS-RECORD LATCH carry (runs even after the dot-block's early return): report
    # whether Stop-Function's -Scope 1 interrupt flag landed in this hop's scope so the
    # C# gate can skip later records like the source's Test-FunctionInterrupt.
    @{ __w3103State = @{ interrupted = [bool](Get-Variable -Name "__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r" -ErrorAction Ignore -ValueOnly) } }
} $InputObject $__boundParameters $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
