#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Modifies internal or external Resource Governor pools. Port of
/// public/Set-DbaRgResourcePool.ps1 (W1-120). The complete process body rides one
/// module-scoped PowerShell hop so its no-input guards, source type-inference quirk,
/// per-instance connection/append loop, bound-key-sensitive property assignments,
/// version warning, Alter/reconfigure ShouldProcess calls, output decoration, and
/// EnableException flow retain their original PowerShell semantics. The compiled cmdlet
/// supplies the real ShouldProcess implementation and carries every caller-bound key the
/// nested module scope must observe. Surface pinned by
/// migration/baselines/Set-DbaRgResourcePool.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaRgResourcePool", SupportsShouldProcess = true,
    ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Default")]
public sealed class SetDbaRgResourcePoolCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, ValueFromPipelineByPropertyName = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The resource-pool names to modify.</summary>
    [Parameter]
    public string[]? ResourcePool { get; set; }

    /// <summary>Internal or External resource pool.</summary>
    [Parameter]
    [PsStringCast]
    [ValidateSet("Internal", "External")]
    public string Type { get; set; } = "Internal";

    /// <summary>Minimum guaranteed average CPU bandwidth percentage.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true)]
    [Parameter(ParameterSetName = "Internal")]
    [ValidateRange(0, 100)]
    public int MinimumCpuPercentage { get; set; }

    /// <summary>Maximum average CPU bandwidth percentage.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true)]
    [ValidateRange(1, 100)]
    public int MaximumCpuPercentage { get; set; }

    /// <summary>Hard cap CPU bandwidth percentage.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true)]
    [Parameter(ParameterSetName = "Internal")]
    [ValidateRange(1, 100)]
    public int CapCpuPercentage { get; set; }

    /// <summary>Minimum memory percentage.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true)]
    [Parameter(ParameterSetName = "Internal")]
    [ValidateRange(0, 100)]
    public int MinimumMemoryPercentage { get; set; }

    /// <summary>Maximum memory percentage.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true)]
    [ValidateRange(1, 100)]
    public int MaximumMemoryPercentage { get; set; }

    /// <summary>Minimum IOPS per volume.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true)]
    [Parameter(ParameterSetName = "Internal")]
    [ValidateRange(0, 2147483647)]
    public int MinimumIOPSPerVolume { get; set; }

    /// <summary>Maximum IOPS per volume.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true)]
    [Parameter(ParameterSetName = "Internal")]
    [ValidateRange(0, 2147483647)]
    public int MaximumIOPSPerVolume { get; set; }

    /// <summary>Maximum external processes.</summary>
    [Parameter(ParameterSetName = "External")]
    public int MaximumProcesses { get; set; }

    /// <summary>Skip Resource Governor reconfiguration after the change.</summary>
    [Parameter]
    public SwitchParameter SkipReconfigure { get; set; }

    /// <summary>Resource-pool objects piped from Get-DbaRgResourcePool.</summary>
    [Parameter(ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

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
            SqlInstance, SqlCredential, ResourcePool, Type,
            MinimumCpuPercentage, MaximumCpuPercentage, CapCpuPercentage,
            MinimumMemoryPercentage, MaximumMemoryPercentage,
            MinimumIOPSPerVolume, MaximumIOPSPerVolume, MaximumProcesses,
            SkipReconfigure.ToBool(), InputObject,
            TestBound("Type"), TestBound("MinimumCpuPercentage"),
            TestBound("MaximumCpuPercentage"), TestBound("CapCpuPercentage"),
            TestBound("MinimumMemoryPercentage"), TestBound("MaximumMemoryPercentage"),
            TestBound("MinimumIOPSPerVolume"), TestBound("MaximumIOPSPerVolume"),
            TestBound("MaximumProcesses"), EnableException.ToBool(), this, BoundVerbose(), BoundDebug());
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
param($SqlInstance, $SqlCredential, $ResourcePool, $Type, $MinimumCpuPercentage, $MaximumCpuPercentage, $CapCpuPercentage, $MinimumMemoryPercentage, $MaximumMemoryPercentage, $MinimumIOPSPerVolume, $MaximumIOPSPerVolume, $MaximumProcesses, $SkipReconfigure, $InputObject, $__typeBound, $__minimumCpuBound, $__maximumCpuBound, $__capCpuBound, $__minimumMemoryBound, $__maximumMemoryBound, $__minimumIopsBound, $__maximumIopsBound, $__maximumProcessesBound, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($SqlInstance, $SqlCredential, $ResourcePool, $Type, $MinimumCpuPercentage, $MaximumCpuPercentage, $CapCpuPercentage, $MinimumMemoryPercentage, $MaximumMemoryPercentage, $MinimumIOPSPerVolume, $MaximumIOPSPerVolume, $MaximumProcesses, $SkipReconfigure, $InputObject, $__typeBound, $__minimumCpuBound, $__maximumCpuBound, $__capCpuBound, $__minimumMemoryBound, $__maximumMemoryBound, $__minimumIopsBound, $__maximumIopsBound, $__maximumProcessesBound, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $InputObject -and -not $ResourcePool) {
        Stop-Function -Message "You must pipe in a resource pool or specify a ResourcePool." -FunctionName Set-DbaRgResourcePool
        return
    }
    if (-not $InputObject -and -not $SqlInstance) {
        Stop-Function -Message "You must pipe in a resource pool or specify a SqlInstance." -FunctionName Set-DbaRgResourcePool
        return
    }

    if (($InputObject) -and (-not $__typeBound)) {
        if ($InputObject -is [Microsoft.SqlServer.Management.Smo.ResourcePool]) {
            $Type = "Internal"
        } elseif ($InputObject -is [Microsoft.SqlServer.Management.Smo.ExternalResourcePool]) {
            $Type = "External"
        }
    }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaRgResourcePool
        }
        if ($Type -eq "Internal") {
            $InputObject += $server.ResourceGovernor.ResourcePools | Where-Object Name -in $ResourcePool
        } elseif ($Type -eq "External") {
            $InputObject += $server.ResourceGovernor.ExternalResourcePools | Where-Object Name -in $ResourcePool
        }
    }

    foreach ($resPool in $InputObject) {
        $server = $resPool.Parent.Parent
        if ($Type -eq "External") {
            if ($__maximumCpuBound) {
                $resPool.MaximumCpuPercentage = $MaximumCpuPercentage
            }
            if ($__maximumMemoryBound) {
                $resPool.MaximumMemoryPercentage = $MaximumMemoryPercentage
            }
            if ($__maximumProcessesBound) {
                $resPool.MaximumProcesses = $MaximumProcesses
            }
        } elseif ($Type -eq "Internal") {
            if ($__minimumCpuBound) {
                $resPool.MinimumCpuPercentage = $MinimumCpuPercentage
            }
            if ($__maximumCpuBound) {
                $resPool.MaximumCpuPercentage = $MaximumCpuPercentage
            }
            if ($__minimumMemoryBound) {
                $resPool.MinimumMemoryPercentage = $MinimumMemoryPercentage
            }
            if ($__maximumMemoryBound) {
                $resPool.MaximumMemoryPercentage = $MaximumMemoryPercentage
            }
            if ($__minimumIopsBound) {
                $resPool.MinimumIopsPerVolume = $MinimumIOPSPerVolume
            }
            if ($__maximumIopsBound) {
                $resPool.MaximumIopsPerVolume = $MaximumIOPSPerVolume
            }
            if ($__capCpuBound) {
                if ($server.ResourceGovernor.ServerVersion.Major -ge 11) {
                    $resPool.CapCpuPercentage = $CapCpuPercentage
                } elseif ($server.ResourceGovernor.ServerVersion.Major -lt 11) {
                    Write-Message -Level Warning -Message "SQL Server version 2012+ required to specify a CPU percentage cap." -FunctionName Set-DbaRgResourcePool -ModuleName "dbatools"
                }
            }
        }

        #Execute
        try {
            if ($__realCmdlet.ShouldProcess($server, "Altering resource pool $resPool")) {
                $resPool.Alter()
            }
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $resPool -Continue -FunctionName Set-DbaRgResourcePool
        }

        #Reconfigure Resource Governor
        try {
            if ($SkipReconfigure) {
                Write-Message -Level Warning -Message "Resource pool changes will not take effect in Resource Governor until it is reconfigured." -FunctionName Set-DbaRgResourcePool -ModuleName "dbatools"
            } elseif ($__realCmdlet.ShouldProcess($server, "Reconfiguring the Resource Governor")) {
                $server.ResourceGovernor.Alter()
            }
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server.ResourceGovernor -Continue -FunctionName Set-DbaRgResourcePool
        }

        $respool | Add-Member -Force -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
        $respool | Add-Member -Force -MemberType NoteProperty -Name InstanceName -value $server.InstanceName
        $respool | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
        $respool | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, CapCpuPercentage, IsSystemObject, MaximumCpuPercentage, MaximumIopsPerVolume, MaximumMemoryPercentage, MinimumCpuPercentage, MinimumIopsPerVolume, MinimumMemoryPercentage, WorkloadGroups
    }
} $SqlInstance $SqlCredential $ResourcePool $Type $MinimumCpuPercentage $MaximumCpuPercentage $CapCpuPercentage $MinimumMemoryPercentage $MaximumMemoryPercentage $MinimumIOPSPerVolume $MaximumIOPSPerVolume $MaximumProcesses $SkipReconfigure $InputObject $__typeBound $__minimumCpuBound $__maximumCpuBound $__capCpuBound $__minimumMemoryBound $__maximumMemoryBound $__minimumIopsBound $__maximumIopsBound $__maximumProcessesBound $EnableException $__realCmdlet $__boundVerbose $__boundDebug 3>&1 2>&1
""";
}
