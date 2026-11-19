#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes Resource Governor workload groups. Port of
/// public/Remove-DbaRgWorkloadGroup.ps1 (W1-117). Process and end remain distinct, matching
/// the source advanced function: each process record runs the no-input guards and optional
/// connection/pool append, then a private carrier retains only the final effective
/// InputObject for EndProcessing. The end body rides one module-scoped hop so its stale
/// `$output` behavior, nested Stop-Function continues, Drop/reconfigure ShouldProcess calls,
/// status mutation, warning flow, and final emission retain PowerShell semantics. Carrier
/// records are internal and never enter the user pipeline.
/// Surface pinned by migration/baselines/Remove-DbaRgWorkloadGroup.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaRgWorkloadGroup", SupportsShouldProcess = true,
    ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Default")]
public sealed class RemoveDbaRgWorkloadGroupCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, ValueFromPipelineByPropertyName = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The workload-group names to remove.</summary>
    [Parameter(Position = 2)]
    public string[]? WorkloadGroup { get; set; }

    /// <summary>The resource pool containing the workload groups.</summary>
    [Parameter(Position = 3)]
    public string ResourcePool { get; set; } = "default";

    /// <summary>Internal or External resource pool.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    [ValidateSet("Internal", "External")]
    public string ResourcePoolType { get; set; } = "Internal";

    /// <summary>Skip Resource Governor reconfiguration after removal.</summary>
    [Parameter]
    public SwitchParameter SkipReconfigure { get; set; }

    /// <summary>Workload-group objects piped from Get-DbaRgWorkloadGroup.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.Smo.WorkloadGroup[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _effectiveInputObject;
    // The most recently OBSERVED InputObject reference: the engine only rebinds the property
    // for records that PIPE workload groups, so a reference CHANGE from the last observation is
    // the per-record rebind signal (codex r2/r3: a fixed first-record snapshot misclassifies
    // later non-rebinding records after one genuine rebind - the property retains the last
    // piped value - and BoundParameters.ContainsKey stays true for invocation-bound
    // -InputObject, which must ACCUMULATE like the function world's process scope).
    private object? _lastObservedInputObject;

    protected override void ProcessRecord()
    {
        // The source's guard `Stop-Function; return` has NO Test-FunctionInterrupt prologue:
        // it abandons only the CURRENT process invocation - later pipeline records re-run the
        // guards and the end block still executes (architecture.md 2.1 no-prologue note).
        // The earlier _skipEnd whole-cmdlet stop diverged (opus W1-117 round 1).
        if (Interrupted) { return; }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item?.Properties[CarrierMarker] is not null &&
                     LanguagePrimitives.IsTrue(item.Properties[CarrierMarker].Value))
            {
                _effectiveInputObject = item.Properties["InputObject"]?.Value;
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, WorkloadGroup, ResourcePool, ResourcePoolType,
            // DEF-011/012 (the row's confirmed P1, codex cross-vendor rounds 1+2): the
            // function world's process scope ACCUMULATES $InputObject += across pipeline
            // records. Only a genuine per-record PIPELINE rebind (reference transition from
            // the invocation-time snapshot) starts fresh, exactly like the engine's VFP
            // rebinding; otherwise the hop seeds from the accumulated carrier total (falling
            // back to the invocation-bound value on the first record).
            SelectProcessInputObject(),
            EnableException.ToBool(), BoundVerbose(), BoundDebug());
    }

    protected override void BeginProcessing()
    {
        base.BeginProcessing();
        // Baseline = the invocation-bound value (or null) before any pipeline record.
        _lastObservedInputObject = InputObject;
    }

    private object? SelectProcessInputObject()
    {
        bool pipelineRebound = !ReferenceEquals(InputObject, _lastObservedInputObject);
        _lastObservedInputObject = InputObject;
        if (pipelineRebound)
            return InputObject;
        return _effectiveInputObject ?? InputObject;
    }

    protected override void EndProcessing()
    {
        if (Interrupted) { return; }

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
        }, EndScript,
            _effectiveInputObject, SkipReconfigure.ToBool(), EnableException.ToBool(),
            this, BoundVerbose(), BoundDebug());
    }

    private const string CarrierMarker = "__dbatoolsRrwgCarrier";

    private object? BoundDebug()
    {
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out object? debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    private object? BoundVerbose()
    {
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out object? verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $WorkloadGroup, $ResourcePool, $ResourcePoolType, $InputObject, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($SqlInstance, $SqlCredential, $WorkloadGroup, $ResourcePool, $ResourcePoolType, $InputObject, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $InputObject -and -not $WorkloadGroup) {
        Stop-Function -Message "You must pipe in a workload group or specify a WorkloadGroup." -FunctionName Remove-DbaRgWorkloadGroup
        [pscustomobject]@{ __dbatoolsRrwgCarrier = $true; InputObject = $InputObject }
        return
    }
    if (-not $InputObject -and -not $SqlInstance) {
        Stop-Function -Message "You must pipe in a workload group or specify a SqlInstance." -FunctionName Remove-DbaRgWorkloadGroup
        [pscustomobject]@{ __dbatoolsRrwgCarrier = $true; InputObject = $InputObject }
        return
    }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Remove-DbaRgWorkloadGroup
        }

        if ($ResourcePoolType -eq "Internal") {
            $resPools = $server.ResourceGovernor.ResourcePools
        } elseif ($ResourcePoolType -eq "External") {
            $resPools = $server.ResourceGovernor.ExternalResourcePools
        }
        $resPool = $resPools | Where-Object Name -eq $ResourcePool
        $InputObject += $resPool.WorkloadGroups | Where-Object Name -in $WorkloadGroup
    }

    [pscustomobject]@{ __dbatoolsRrwgCarrier = $true; InputObject = $InputObject }
} $SqlInstance $SqlCredential $WorkloadGroup $ResourcePool $ResourcePoolType $InputObject $EnableException $__boundVerbose $__boundDebug 3>&1 2>&1
""";

    private const string EndScript = """
param($InputObject, $SkipReconfigure, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($InputObject, $SkipReconfigure, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($wklGroup in $InputObject) {
        $server = $wklGroup.Parent.Parent.Parent
        if ($__realCmdlet.ShouldProcess($wklGroup, "Dropping workload group")) {
            $output = [PSCustomObject]@{
                ComputerName = $server.ComputerName
                InstanceName = $server.ServiceName
                SqlInstance  = $server.DomainInstanceName
                Name         = $wklGroup.Name
                Status       = $null
                IsRemoved    = $false
            }
            try {
                $wklGroup.Drop()
                $output.Status = "Dropped"
                $output.IsRemoved = $true
            } catch {
                Stop-Function -Message "Could not remove existing workload group $wklGroup on $server." -Target $wklGroup -Continue -FunctionName Remove-DbaRgWorkloadGroup
                $output.Status = (Get-ErrorMessage -Record $_)
                $output.IsRemoved = $false
            }
        }

        # Reconfigure Resource Governor
        if ($SkipReconfigure) {
            Write-Message -Level Warning -Message "Workload group changes will not take effect in Resource Governor until it is reconfigured." -FunctionName Remove-DbaRgWorkloadGroup -ModuleName "dbatools"
        } elseif ($__realCmdlet.ShouldProcess($server, "Reconfiguring the Resource Governor")) {
            try {
                $server.ResourceGovernor.Alter()
            } catch {
                Stop-Function -Message "Could not reconfigure Resource Governor on $server." -Target $server.ResourceGovernor -Continue -FunctionName Remove-DbaRgWorkloadGroup
            }
        }
        $output
    }
} $InputObject $SkipReconfigure $EnableException $__realCmdlet $__boundVerbose $__boundDebug 3>&1 2>&1
""";
}
