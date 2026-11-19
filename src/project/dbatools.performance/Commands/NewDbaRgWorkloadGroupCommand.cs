#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates Resource Governor workload groups. Port of public/New-DbaRgWorkloadGroup.ps1
/// (W1-113). The per-instance body rides one VERBATIM module-scoped hop: resource-pool
/// selection, existing-group Force/drop flow, contained Stop-Function -Continues, SMO
/// WorkloadGroup construction/property assignment/Create, SkipReconfigure warning versus
/// ResourceGovernor.Alter, and the final Get-DbaRgResourcePool/Get-DbaRgWorkloadGroup
/// refetch projection. ShouldProcess routes to the real cmdlet; Stop-Function calls carry
/// the original command name and inherited EnableException value; merged error records are
/// re-emitted with the W1-045 bookkeeping compensation. This function has one effective
/// parameter set, so its PowerShell function surface exposes implicit positions 0 through
/// 10; the compiled attributes state those positions explicitly. Surface pinned by
/// migration/baselines/New-DbaRgWorkloadGroup.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaRgWorkloadGroup", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Default")]
public sealed class NewDbaRgWorkloadGroupCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, ValueFromPipelineByPropertyName = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The workload-group names to create.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? WorkloadGroup { get; set; }

    /// <summary>The resource pool that will contain the workload groups.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string ResourcePool { get; set; } = "default";

    /// <summary>Internal or External resource pool.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    [ValidateSet("Internal", "External")]
    public string ResourcePoolType { get; set; } = "Internal";

    /// <summary>Relative scheduling importance.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    [ValidateSet("LOW", "MEDIUM", "HIGH")]
    public string Importance { get; set; } = "MEDIUM";

    /// <summary>Maximum memory grant percentage per request.</summary>
    [Parameter(Position = 6)]
    [ValidateRange(1, 100)]
    [PsIntCast]
    public int RequestMaximumMemoryGrantPercentage { get; set; } = 25;

    /// <summary>Maximum CPU time per request in seconds.</summary>
    [Parameter(Position = 7)]
    [ValidateRange(0, int.MaxValue)]
    [PsIntCast]
    public int RequestMaximumCpuTimeInSeconds { get; set; }

    /// <summary>Memory-grant wait timeout in seconds.</summary>
    [Parameter(Position = 8)]
    [ValidateRange(0, int.MaxValue)]
    [PsIntCast]
    public int RequestMemoryGrantTimeoutInSeconds { get; set; }

    /// <summary>Maximum degree of parallelism.</summary>
    [Parameter(Position = 9)]
    [ValidateRange(0, 64)]
    [PsIntCast]
    public int MaximumDegreeOfParallelism { get; set; }

    /// <summary>Maximum concurrent requests for the group.</summary>
    [Parameter(Position = 10)]
    [ValidateRange(0, int.MaxValue)]
    [PsIntCast]
    public int GroupMaximumRequests { get; set; }

    /// <summary>Skip the Resource Governor reconfigure after creation.</summary>
    [Parameter]
    public SwitchParameter SkipReconfigure { get; set; }

    /// <summary>Drop and recreate an existing workload group.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        // The source's already-exists/no-Force site reads process-level $_ into Stop-Function
        // -ErrorRecord ([ErrorRecord[]]): a piped record fails argument transformation and
        // terminates the invocation (probe: migration/tools/Probe-RgStopFunctionFlowTruthTable.ps1,
        // both editions). Carry the record so the verbatim statement reproduces it organically.
        object? pipelineItem = PsPipelineItem.Current(this);
        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            // Connect-DbaInstance is inside the PowerShell function's try. NestedConnect
            // preserves its nested warning/error behavior and the raw wrapper used by later
            // module-scoped command dispatch.
            Hashtable connectParams = new Hashtable();
            connectParams["SqlInstance"] = instance;
            connectParams["SqlCredential"] = SqlCredential;
            NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
            if (!connection.Ok)
            {
                StopFunction("Failure", target: instance, errorRecord: connection.Failure,
                    category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            object serverValue = connection.RawServerValue ?? connection.Server!;
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
            serverValue, instance, WorkloadGroup, ResourcePool, ResourcePoolType,
                Importance, RequestMaximumMemoryGrantPercentage,
                RequestMaximumCpuTimeInSeconds, RequestMemoryGrantTimeoutInSeconds,
                MaximumDegreeOfParallelism, GroupMaximumRequests,
                SkipReconfigure.ToBool(), Force.ToBool(), EnableException.ToBool(),
                this, BoundVerbose(), BoundDebug(), pipelineItem);
        }
    }

    /// <summary>A bound -Debug carrier, mirroring BoundVerbose (source debug records
    /// otherwise vanish - the hop scope never sees the caller's -Debug).</summary>
    private object? BoundDebug()
    {
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out object? debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose carrier for module-scoped nested commands.</summary>
    private object? BoundVerbose()
    {
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out object? verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    private const string BodyScript = """
param($server, $instance, $WorkloadGroup, $ResourcePool, $ResourcePoolType, $Importance, $RequestMaximumMemoryGrantPercentage, $RequestMaximumCpuTimeInSeconds, $RequestMemoryGrantTimeoutInSeconds, $MaximumDegreeOfParallelism, $GroupMaximumRequests, $SkipReconfigure, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug, $__pipelineItem)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($server, $instance, $WorkloadGroup, $ResourcePool, $ResourcePoolType, $Importance, $RequestMaximumMemoryGrantPercentage, $RequestMaximumCpuTimeInSeconds, $RequestMemoryGrantTimeoutInSeconds, $MaximumDegreeOfParallelism, $GroupMaximumRequests, $SkipReconfigure, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug, $__pipelineItem)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    # Process-block $_ carrier: the already-exists Stop-Function reads $_ into -ErrorRecord.
    $_ = $__pipelineItem

    foreach ($wklGroup in $WorkloadGroup) {
        switch ($ResourcePoolType) {
            'Internal' { $resPools = $server.ResourceGovernor.ResourcePools }
            'External' { $resPools = $server.ResourceGovernor.ExternalResourcePools }
        }
        $resPool = $resPools | Where-Object Name -eq $ResourcePool
        $existingWorkloadGroup = $resPool.WorkloadGroups | Where-Object Name -eq $wklGroup
        if ($null -ne $existingWorkloadGroup) {
            if ($Force) {
                if ($__realCmdlet.ShouldProcess($existingWorkloadGroup, "Dropping existing workload group $wklGroup because -Force was used")) {
                    try {
                        $existingWorkloadGroup.Drop()
                    } catch {
                        Stop-Function -Message "Could not remove existing workload group $wklGroup on $instance, skipping." -Target $existingWorkloadGroup -Continue -FunctionName New-DbaRgWorkloadGroup
                    }
                }
            } else {
                Stop-Function -Message "Workload group $wklGroup already exists." -Category ResourceExists -ErrorRecord $_ -Target $existingWorkloadGroup -Continue -FunctionName New-DbaRgWorkloadGroup
                return
            }
        }

        #Create workload group
        if ($__realCmdlet.ShouldProcess($instance, "Creating workload group $wklGroup")) {
            try {
                $newWorkloadGroup = New-Object Microsoft.SqlServer.Management.Smo.WorkloadGroup($resPool, $wklGroup)
                $newWorkloadGroup.Importance = $Importance
                $newWorkloadGroup.RequestMaximumMemoryGrantPercentage = $RequestMaximumMemoryGrantPercentage
                $newWorkloadGroup.RequestMaximumCpuTimeInSeconds = $RequestMaximumCpuTimeInSeconds
                $newWorkloadGroup.RequestMemoryGrantTimeoutInSeconds = $RequestMemoryGrantTimeoutInSeconds
                $newWorkloadGroup.MaximumDegreeOfParallelism = $MaximumDegreeOfParallelism
                $newWorkloadGroup.GroupMaximumRequests = $GroupMaximumRequests
                $newWorkloadGroup.Create()

                #Reconfigure Resource Governor
                if ($SkipReconfigure) {
                    Write-Message -Level Warning -Message "Not reconfiguring the Resource Governor after creating a new workload group may create problems." -FunctionName New-DbaRgWorkloadGroup -ModuleName "dbatools"
                } elseif ($__realCmdlet.ShouldProcess($instance, "Reconfiguring the Resource Governor")) {
                    $server.ResourceGovernor.Alter()
                }

            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $newWorkloadGroup -Continue -FunctionName New-DbaRgWorkloadGroup
            }
        }
        Get-DbaRgResourcePool -SqlInstance $server -Type $ResourcePoolType | Where-Object Name -eq $resPool.Name | Get-DbaRgWorkloadGroup | Where-Object Name -eq $wklGroup
    }
} $server $instance $WorkloadGroup $ResourcePool $ResourcePoolType $Importance $RequestMaximumMemoryGrantPercentage $RequestMaximumCpuTimeInSeconds $RequestMemoryGrantTimeoutInSeconds $MaximumDegreeOfParallelism $GroupMaximumRequests $SkipReconfigure $Force $EnableException $__realCmdlet $__boundVerbose $__boundDebug $__pipelineItem 3>&1 2>&1
""";
}
