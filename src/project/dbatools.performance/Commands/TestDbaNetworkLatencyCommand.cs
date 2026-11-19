#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Measures SQL query round-trip and execution-only latency. Port of
/// public/Test-DbaNetworkLatency.ps1 (W1-132). The complete per-record body rides an
/// advanced module-scoped PowerShell hop so private helpers, Server.Query ETS dispatch,
/// Stopwatch and arithmetic semantics, dynamic continues, stream behavior, test mocks,
/// and Select-DefaultView retain the function's engine behavior. Surface pinned by
/// migration/baselines/Test-DbaNetworkLatency.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaNetworkLatency")]
[OutputType(typeof(object[]))]
public sealed class TestDbaNetworkLatencyCommand : DbaBaseCmdlet
{
    /// <summary>SQL Server instances to test.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative SQL credential.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Query executed for each measurement.</summary>
    [Parameter(Position = 2)]
    public string Query { get; set; } = "SELECT TOP 100 * FROM INFORMATION_SCHEMA.TABLES";

    /// <summary>Number of executions per instance.</summary>
    [Parameter(Position = 3)]
    public int Count { get; set; } = 3;

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
        }, ProcessScript,
            SqlInstance, SqlCredential, Query, Count, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Query, $Count, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($SqlInstance, $SqlCredential, $Query, $Count, $EnableException)

        foreach ($instance in $SqlInstance) {
            try {
                $start = [System.Diagnostics.Stopwatch]::StartNew()
                $currentCount = 0
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaNetworkLatency
                }

                do {
                    if (++$currentCount -eq 1) {
                        $first = [System.Diagnostics.Stopwatch]::StartNew()
                    }
                    $null = $server.Query($query)
                    if ($currentCount -eq $count) {
                        $last = $first.Elapsed
                    }
                }
                while ($currentCount -lt $count)

                $end = $start.Elapsed
                $totalTime = $end.TotalMilliseconds
                $average = $totalTime / $count

                $totalWarm = $last.TotalMilliseconds
                if ($Count -eq 1) {
                    $averageWarm = $totalWarm
                } else {
                    $averageWarm = $totalWarm / $count
                }

                [PSCustomObject]@{
                    ComputerName     = $server.ComputerName
                    InstanceName     = $server.ServiceName
                    SqlInstance      = $server.DomainInstanceName
                    Count            = $count
                    Total            = [prettytimespan]::FromMilliseconds($totalTime)
                    Avg              = [prettytimespan]::FromMilliseconds($average)
                    ExecuteOnlyTotal = [prettytimespan]::FromMilliseconds($totalWarm)
                    ExecuteOnlyAvg   = [prettytimespan]::FromMilliseconds($averageWarm)
                    NetworkOnlyTotal = [prettytimespan]::FromMilliseconds($totalTime - $totalWarm)
                } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, 'Count as ExecutionCount', Total, 'Avg as Average', ExecuteOnlyTotal, 'ExecuteOnlyAvg as ExecuteOnlyAverage', NetworkOnlyTotal #backwards compat
            } catch {
                Stop-Function -Message "Error occurred testing dba network latency: $_" -ErrorRecord $_ -Continue -Target $instance -FunctionName Test-DbaNetworkLatency
            }
        }
} $SqlInstance $SqlCredential $Query $Count $EnableException @__commonParameters 3>&1 2>&1
""";
}
