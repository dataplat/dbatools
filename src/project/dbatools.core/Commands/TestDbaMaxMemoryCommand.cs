#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Calculates the recommended maximum server memory for SQL Server instances based on
/// total memory and instance count. Port of public/Test-DbaMaxMemory.ps1; surface pinned
/// by migration/baselines/Test-DbaMaxMemory.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaMaxMemory")]
[OutputType(typeof(PSObject))]
public sealed class TestDbaMaxMemoryCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Windows credential used when counting SQL Server services on the host.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            NestedCommand.InvokeScopedStreaming(this, item =>
            {
                if (item?.BaseObject is ErrorRecord nestedError)
                {
                    NestedCommand.RemoveDuplicateError(this, nestedError);
                    WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                    return;
                }
                WriteObject(item);
            }, ProcessScript,
            new DbaInstanceParameter[] { instance }, SqlCredential, Credential, EnableException.ToBool(),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    // PS: the source process foreach VERBATIM, one element per hop invocation (the
    // source loop line doubles as the guard loop, so the catch-path Stop-Function
    // -Continue and the null-memory bare continue land on it exactly like the function
    // world). Substitution only: -FunctionName appended to the seven hop-frame
    // Stop-Function/Write-Message sites (the hop scriptblock has no function frame to
    // stamp). $isLinux/$isMacOS resolve dynamically through the caller scope in both
    // worlds identically.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Credential, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [PSCredential]$Credential, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaMaxMemory
            }

            Write-Message -Level Verbose -Target $instance -Message "Retrieving maximum memory statistics from $instance" -FunctionName Test-DbaMaxMemory -ModuleName "dbatools"
            $serverMemory = Get-DbaMaxMemory -SqlInstance $server
            try {
                if ($isLinux -or $isMacOS) {
                    Write-Message -Level Warning -Target $instance -Message "Can't determine instance count from Linux or Mac. Defaulting to 1." -FunctionName Test-DbaMaxMemory -ModuleName "dbatools"
                    $instanceCount = 1
                } else {
                    Write-Message -Level Verbose -Target $instance -Message "Retrieving number of instances from $($instance.ComputerName)" -FunctionName Test-DbaMaxMemory -ModuleName "dbatools"
                    if ($Credential) {
                        $serverService = Get-DbaService -ComputerName $instance -Credential $Credential -EnableException
                    } else {
                        $serverService = Get-DbaService -ComputerName $instance -EnableException
                    }

                    $instanceCount = ($serverService | Where-Object State -Like Running | Where-Object InstanceName | Where-Object ServiceType -eq 'Engine' | Group-Object InstanceName | Measure-Object Count).Count

                    if ($instanceCount -eq 0) {
                        Write-Message -Level Warning -Message "Couldn't get accurate SQL Server instance count on $instance. Defaulting to 1." -FunctionName Test-DbaMaxMemory -ModuleName "dbatools"
                        $instanceCount = 1
                    }

                    $otherConsumers = $serverService | Where-Object ServiceType -in ('SSAS', 'SSRS', 'SSIS')
                    if ($null -ne $otherConsumers) {
                        Write-Message -Level Warning -Message "The memory calculation may be inaccurate as the following SQL components have also been detected: $($otherConsumers.ServiceType -join(','))" -FunctionName Test-DbaMaxMemory -ModuleName "dbatools"
                    }


                }
            } catch {
                Write-Message -Level Warning -Message "Couldn't get accurate SQL Server instance count on $instance. Defaulting to 1." -Target $instance -ErrorRecord $_ -FunctionName Test-DbaMaxMemory -ModuleName "dbatools"
                $instanceCount = 1
            }

            if ($null -eq $serverMemory) {
                continue
            }
            $reserve = 1

            $maxMemory = $serverMemory.MaxValue
            $totalMemory = $serverMemory.Total

            if ($totalMemory -ge 4096) {
                $currentCount = $totalMemory
                while ($currentCount / 4096 -gt 0) {
                    if ($currentCount -gt 16384) {
                        $reserve += 1
                        $currentCount += -8192
                    } else {
                        $reserve += 1
                        $currentCount += -4096
                    }
                }
                $recommendedMax = [int]($totalMemory - ($reserve * 1024))
            } else {
                $recommendedMax = $totalMemory * .5
            }

            $recommendedMax = $recommendedMax / $instanceCount

            [PSCustomObject]@{
                ComputerName     = $server.ComputerName
                InstanceName     = $server.ServiceName
                SqlInstance      = $server.DomainInstanceName
                InstanceCount    = $instanceCount
                Total            = [int]$totalMemory
                MaxValue         = [int]$maxMemory
                RecommendedValue = [int]$recommendedMax
                Server           = $server # This will allowing piping a non-connected object
            } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, InstanceCount, Total, MaxValue, RecommendedValue
        }
} $SqlInstance $SqlCredential $Credential $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
