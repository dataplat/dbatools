#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates Resource Governor resource pools. Port of public/New-DbaRgResourcePool.ps1
/// (W1-112). The WHOLE process body rides ONE VERBATIM module hop per pipeline record
/// (both loops with their contained Stop-Function -Continues - including the dead
/// `return` after the already-exists -Continue - the Get-DbaRgResourcePool existence
/// probe and refetch emission, the Force drop, the SMO
/// ResourcePool/ExternalResourcePool Create calls, the SkipReconfigure warning vs the
/// ResourceGovernor.Alter reconfigure, and the Set-DbaRgResourcePool splat);
/// $Pscmdlet.ShouldProcess routes to the real cmdlet via $__realCmdlet (W1-085/W1-107
/// pattern); in-hop Stop-Functions carry -FunctionName (W1-090) and read
/// $EnableException from the hop param scope; merged-back 2&gt;&amp;1 records re-emit
/// via WriteError with the W1-045 compensation. Multiple parameter sets suppress ALL
/// implicit positional binding (W1-094 surface law) - no Position anywhere. Surface
/// pinned by migration/baselines/New-DbaRgResourcePool.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaRgResourcePool", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Default")]
public sealed class NewDbaRgResourcePoolCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ValueFromPipelineByPropertyName = true)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name of the resource pool(s) to create.</summary>
    [Parameter]
    public string[]? ResourcePool { get; set; }

    /// <summary>Internal or External resource pool.</summary>
    [Parameter]
    [PsStringCast]
    [ValidateSet("Internal", "External")]
    public string Type { get; set; } = "Internal";

    /// <summary>Minimum guaranteed average CPU bandwidth percentage.</summary>
    [Parameter(ParameterSetName = "Internal")]
    [ValidateRange(0, 100)]
    public int MinimumCpuPercentage { get; set; } = 0;

    /// <summary>Maximum average CPU bandwidth percentage.</summary>
    [Parameter]
    [ValidateRange(1, 100)]
    public int MaximumCpuPercentage { get; set; } = 100;

    /// <summary>Hard cap CPU bandwidth percentage.</summary>
    [Parameter(ParameterSetName = "Internal")]
    [ValidateRange(1, 100)]
    public int CapCpuPercentage { get; set; } = 100;

    /// <summary>Minimum memory percentage.</summary>
    [Parameter(ParameterSetName = "Internal")]
    [ValidateRange(0, 100)]
    public int MinimumMemoryPercentage { get; set; } = 0;

    /// <summary>Maximum memory percentage.</summary>
    [Parameter]
    [ValidateRange(1, 100)]
    public int MaximumMemoryPercentage { get; set; } = 100;

    /// <summary>Minimum IOPS per volume.</summary>
    [Parameter(ParameterSetName = "Internal")]
    [ValidateRange(0, 2147483647)]
    public int MinimumIOPSPerVolume { get; set; } = 0;

    /// <summary>Maximum IOPS per volume.</summary>
    [Parameter(ParameterSetName = "Internal")]
    [ValidateRange(0, 2147483647)]
    public int MaximumIOPSPerVolume { get; set; } = 0;

    /// <summary>Maximum external processes (external pools).</summary>
    [Parameter(ParameterSetName = "External")]
    public int MaximumProcesses { get; set; }

    /// <summary>Skip the Resource Governor reconfigure after creating the pool.</summary>
    [Parameter]
    public SwitchParameter SkipReconfigure { get; set; }

    /// <summary>Drop and recreate an existing pool of the same name.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: Connect-DbaInstance inside the fn's try - NestedConnect reproduces the
            // nested cmdlet's OWN warning on the caller stream (the fn world shows BOTH
            // the [Connect-DbaInstance] and the [New-DbaRgResourcePool] warnings on a
            // failed connect; a bare in-hop call loses the nested one - smoke-caught).
            Hashtable connectParams = new Hashtable();
            connectParams["SqlInstance"] = instance;
            connectParams["SqlCredential"] = SqlCredential;
            NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
            if (!connection.Ok)
            {
                StopFunction("Failure", target: instance, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }
            // PS: $server keeps Connect-DbaInstance's wrapper (the W1-105 dispatch law).
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
            serverValue, instance, ResourcePool, Type,
                MinimumCpuPercentage, MaximumCpuPercentage, CapCpuPercentage,
                MinimumMemoryPercentage, MaximumMemoryPercentage,
                MinimumIOPSPerVolume, MaximumIOPSPerVolume, MaximumProcesses,
                SkipReconfigure.ToBool(), Force.ToBool(), EnableException.ToBool(),
                this, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    // PS: the per-instance body VERBATIM in the dbatools module scope (the connect
    // rides NestedConnect in C# for nested-warning parity); the $resPool loop is
    // inside the hop so the Stop-Function -Continues target their real enclosing
    // loop; ShouldProcess routes to the real cmdlet.
    private const string BodyScript = """
param($server, $instance, $ResourcePool, $Type, $MinimumCpuPercentage, $MaximumCpuPercentage, $CapCpuPercentage, $MinimumMemoryPercentage, $MaximumMemoryPercentage, $MinimumIOPSPerVolume, $MaximumIOPSPerVolume, $MaximumProcesses, $SkipReconfigure, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($server, $instance, $ResourcePool, $Type, $MinimumCpuPercentage, $MaximumCpuPercentage, $CapCpuPercentage, $MinimumMemoryPercentage, $MaximumMemoryPercentage, $MinimumIOPSPerVolume, $MaximumIOPSPerVolume, $MaximumProcesses, $SkipReconfigure, $Force, $EnableException, $__realCmdlet)
    foreach ($resPool in $ResourcePool) {
            $existingResourcePool = Get-DbaRgResourcePool -SqlInstance $server -Type $Type | Where-Object Name -eq $resPool
            if ($null -ne $existingResourcePool) {
                if ($Force) {
                    if ($__realCmdlet.ShouldProcess($existingResourcePool, "Dropping existing resource pool '$resPool' because -Force was used")) {
                        try {
                            $existingResourcePool.Drop()
                        } catch {
                            Stop-Function -Message "Could not remove existing resource pool '$resPool' on $instance, skipping." -Target $existingResourcePool -Continue -FunctionName New-DbaRgResourcePool
                        }
                    }
                } else {
                    Stop-Function -Message "Resource Pool '$resPool' already exists." -Category ResourceExists -Target $existingResourcePool -Continue -FunctionName New-DbaRgResourcePool
                    return
                }
            }

            #Create resource pool
            if ($__realCmdlet.ShouldProcess($instance, "Creating resource pool '$resPool'")) {
                try {
                    if ($Type -eq "External") {
                        $splatSetDbaRgResourcePool = @{
                            SqlInstance             = $server
                            ResourcePool            = $resPool
                            Type                    = $Type
                            MaximumCpuPercentage    = $MaximumCpuPercentage
                            MaximumMemoryPercentage = $MaximumMemoryPercentage
                            MaximumProcesses        = $MaximumProcesses
                            SkipReconfigure         = $SkipReconfigure
                        }
                        $newResourcePool = New-Object Microsoft.SqlServer.Management.Smo.ExternalResourcePool($server.ResourceGovernor, $resPool)
                        $newResourcePool.Create()
                    } elseif ($Type -eq "Internal") {
                        $splatSetDbaRgResourcePool = @{
                            SqlInstance             = $server
                            ResourcePool            = $resPool
                            Type                    = $Type
                            MinimumCpuPercentage    = $MinimumCpuPercentage
                            MaximumCpuPercentage    = $MaximumCpuPercentage
                            CapCpuPercentage        = $CapCpuPercentage
                            MinimumMemoryPercentage = $MinimumMemoryPercentage
                            MaximumMemoryPercentage = $MaximumMemoryPercentage
                            MinimumIOPSPerVolume    = $MinimumIOPSPerVolume
                            MaximumIOPSPerVolume    = $MaximumIOPSPerVolume
                            SkipReconfigure         = $SkipReconfigure
                        }
                        $newResourcePool = New-Object Microsoft.SqlServer.Management.Smo.ResourcePool($server.ResourceGovernor, $resPool)
                        $newResourcePool.Create()
                    }

                    #Reconfigure Resource Governor
                    if ($SkipReconfigure) {
                        Write-Message -Level Warning -Message "Not reconfiguring the Resource Governor after creating a new pool may create problems." -FunctionName New-DbaRgResourcePool -ModuleName "dbatools"
                    } elseif ($__realCmdlet.ShouldProcess($instance, "Reconfiguring the Resource Governor")) {
                        $server.ResourceGovernor.Alter()
                    }

                    $null = Set-DbaRgResourcePool @splatSetDbaRgResourcePool
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $newResourcePool -Continue -FunctionName New-DbaRgResourcePool
                }
            }
        Get-DbaRgResourcePool -SqlInstance $server -Type $Type | Where-Object Name -eq $resPool
    }
} $server $instance $ResourcePool $Type $MinimumCpuPercentage $MaximumCpuPercentage $CapCpuPercentage $MinimumMemoryPercentage $MaximumMemoryPercentage $MinimumIOPSPerVolume $MaximumIOPSPerVolume $MaximumProcesses $SkipReconfigure $Force $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
