#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Modifies Resource Governor workload groups. Port of
/// public/Set-DbaRgWorkloadGroup.ps1 (W1-121). The complete process body rides one
/// module-scoped PowerShell hop so no-input guards, connection and pool-selection flow,
/// stale locals, bound-key-sensitive assignments, Alter/reconfigure ShouldProcess calls,
/// final refetch projection, and EnableException behavior retain the source semantics.
/// The real cmdlet and every assignment-relevant caller-bound key cross the hop explicitly.
/// Surface pinned by migration/baselines/Set-DbaRgWorkloadGroup.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaRgWorkloadGroup", SupportsShouldProcess = true,
    ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Default")]
public sealed class SetDbaRgWorkloadGroupCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The workload-group names to modify.</summary>
    [Parameter(Position = 2)]
    public string[]? WorkloadGroup { get; set; }

    /// <summary>The resource pool containing the workload groups.</summary>
    [Parameter(Position = 3)]
    public string? ResourcePool { get; set; }

    /// <summary>Internal or External resource pool.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    [ValidateSet("Internal", "External")]
    public string? ResourcePoolType { get; set; }

    /// <summary>Relative scheduling importance.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    [ValidateSet("LOW", "MEDIUM", "HIGH")]
    public string? Importance { get; set; }

    /// <summary>Maximum memory grant percentage per request.</summary>
    [Parameter(Position = 6)]
    [ValidateRange(1, 100)]
    public int RequestMaximumMemoryGrantPercentage { get; set; }

    /// <summary>Maximum CPU time per request in seconds.</summary>
    [Parameter(Position = 7)]
    [ValidateRange(0, int.MaxValue)]
    public int RequestMaximumCpuTimeInSeconds { get; set; }

    /// <summary>Memory-grant wait timeout in seconds.</summary>
    [Parameter(Position = 8)]
    [ValidateRange(0, int.MaxValue)]
    public int RequestMemoryGrantTimeoutInSeconds { get; set; }

    /// <summary>Maximum degree of parallelism.</summary>
    [Parameter(Position = 9)]
    [ValidateRange(0, 64)]
    public int MaximumDegreeOfParallelism { get; set; }

    /// <summary>Maximum concurrent requests for the group.</summary>
    [Parameter(Position = 10)]
    [ValidateRange(0, int.MaxValue)]
    public int GroupMaximumRequests { get; set; }

    /// <summary>Skip Resource Governor reconfiguration after the change.</summary>
    [Parameter]
    public SwitchParameter SkipReconfigure { get; set; }

    /// <summary>Workload-group objects piped from Get-DbaRgWorkloadGroup.</summary>
    [Parameter(ValueFromPipeline = true, Position = 11)]
    public Microsoft.SqlServer.Management.Smo.WorkloadGroup[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
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
        }, BodyScript,
            SqlInstance, SqlCredential, WorkloadGroup, ResourcePool, ResourcePoolType,
            Importance, RequestMaximumMemoryGrantPercentage,
            RequestMaximumCpuTimeInSeconds, RequestMemoryGrantTimeoutInSeconds,
            MaximumDegreeOfParallelism, GroupMaximumRequests,
            SkipReconfigure.ToBool(), InputObject,
            TestBound("Importance"), TestBound("RequestMaximumMemoryGrantPercentage"),
            TestBound("RequestMaximumCpuTimeInSeconds"),
            TestBound("RequestMemoryGrantTimeoutInSeconds"),
            TestBound("MaximumDegreeOfParallelism"), TestBound("GroupMaximumRequests"),
            EnableException.ToBool(), this, BoundVerbose(), BoundDebug());
    }

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

    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $WorkloadGroup, $ResourcePool, $ResourcePoolType, $Importance, $RequestMaximumMemoryGrantPercentage, $RequestMaximumCpuTimeInSeconds, $RequestMemoryGrantTimeoutInSeconds, $MaximumDegreeOfParallelism, $GroupMaximumRequests, $SkipReconfigure, $InputObject, $__importanceBound, $__requestMemoryBound, $__requestCpuBound, $__requestTimeoutBound, $__maxDopBound, $__groupMaximumBound, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($SqlInstance, $SqlCredential, $WorkloadGroup, $ResourcePool, $ResourcePoolType, $Importance, $RequestMaximumMemoryGrantPercentage, $RequestMaximumCpuTimeInSeconds, $RequestMemoryGrantTimeoutInSeconds, $MaximumDegreeOfParallelism, $GroupMaximumRequests, $SkipReconfigure, $InputObject, $__importanceBound, $__requestMemoryBound, $__requestCpuBound, $__requestTimeoutBound, $__maxDopBound, $__groupMaximumBound, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $InputObject -and -not $WorkloadGroup) {
        Stop-Function -Message "You must pipe in a workload group or specify a ResourcePool." -FunctionName Set-DbaRgWorkloadGroup
        return
    }
    if (-not $InputObject -and -not $SqlInstance) {
        Stop-Function -Message "You must pipe in a workload group or specify a SqlInstance." -FunctionName Set-DbaRgWorkloadGroup
        return
    }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaRgWorkloadGroup
        }
        switch ($ResourcePoolType) {
            'Internal' { $resPools = $server.ResourceGovernor.ResourcePools }
            'External' { $resPools = $server.ResourceGovernor.ExternalResourcePools }
        }
        $resPool = $resPools | Where-Object Name -eq $ResourcePool
        $InputObject += $resPool.WorkloadGroups | Where-Object Name -in $WorkloadGroup
    }

    foreach ($wklGroup in $InputObject) {
        $resPool = $wklGroup.Parent
        switch ($resPool.GetType().Name) {
            'ResourcePool' { $resPoolType = "Internal" }
            'ExternalResourcePool' { $resPoolType = "External" }
        }
        $server = $resPool.Parent.Parent
        if ($__importanceBound) {
            $wklGroup.Importance = $Importance
        }
        if ($__requestMemoryBound) {
            $wklGroup.RequestMaximumMemoryGrantPercentage = $RequestMaximumMemoryGrantPercentage
        }
        if ($__requestCpuBound) {
            $wklGroup.RequestMaximumCpuTimeInSeconds = $RequestMaximumCpuTimeInSeconds
        }
        if ($__requestTimeoutBound) {
            $wklGroup.RequestMemoryGrantTimeoutInSeconds = $RequestMemoryGrantTimeoutInSeconds
        }
        if ($__maxDopBound) {
            $wklGroup.MaximumDegreeOfParallelism = $MaximumDegreeOfParallelism
        }
        if ($__groupMaximumBound) {
            $wklGroup.GroupMaximumRequests = $GroupMaximumRequests
        }

        #Execute
        try {
            if ($__realCmdlet.ShouldProcess($server, "Altering workload group $wklGroup")) {
                $wklGroup.Alter()
            }
        } catch {
            Stop-Function -Message "Failure setting the workload group $wklGroup." -ErrorRecord $_ -Target $wklGroup -Continue -FunctionName Set-DbaRgWorkloadGroup
        }

        #Reconfigure Resource Governor
        try {
            if ($SkipReconfigure) {
                Write-Message -Level Warning -Message "Workload group changes will not take effect in Resource Governor until it is reconfigured." -FunctionName Set-DbaRgWorkloadGroup -ModuleName "dbatools"
            } elseif ($__realCmdlet.ShouldProcess($server, "Reconfiguring the Resource Governor")) {
                $server.ResourceGovernor.Alter()
            }
        } catch {
            Stop-Function -Message "Failure reconfiguring the Resource Governor." -ErrorRecord $_ -Target $server.ResourceGovernor -Continue -FunctionName Set-DbaRgWorkloadGroup
        }
        Get-DbaRgResourcePool -SqlInstance $server -Type $resPoolType | Where-Object Name -eq $resPool.Name | Get-DbaRgWorkloadGroup | Where-Object Name -eq $wklGroup.Name
    }
} $SqlInstance $SqlCredential $WorkloadGroup $ResourcePool $ResourcePoolType $Importance $RequestMaximumMemoryGrantPercentage $RequestMaximumCpuTimeInSeconds $RequestMemoryGrantTimeoutInSeconds $MaximumDegreeOfParallelism $GroupMaximumRequests $SkipReconfigure $InputObject $__importanceBound $__requestMemoryBound $__requestCpuBound $__requestTimeoutBound $__maxDopBound $__groupMaximumBound $EnableException $__realCmdlet $__boundVerbose $__boundDebug 3>&1 2>&1
""";
}
