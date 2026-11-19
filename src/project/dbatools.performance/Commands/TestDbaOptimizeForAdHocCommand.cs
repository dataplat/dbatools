#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests the optimize-for-ad-hoc-workloads server configuration. Port of
/// public/Test-DbaOptimizeForAdHoc.ps1 (W1-133). Begin-derived recommendation values are
/// retained for the cmdlet invocation, while the per-record body rides an advanced
/// module-scoped PowerShell hop so connection helpers, SMO/ETS member access, dynamic
/// continues, streams, and test mocks preserve the function's engine behavior. Surface
/// pinned by migration/baselines/Test-DbaOptimizeForAdHoc.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaOptimizeForAdHoc")]
public sealed class TestDbaOptimizeForAdHocCommand : DbaBaseCmdlet
{
    /// <summary>SQL Server instances to inspect.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative SQL credential.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private string _notesAdHocZero = null!;
    private string _notesAsRecommended = null!;
    private int _recommendedValue;

    protected override void BeginProcessing()
    {
        _notesAdHocZero = "Recommended configuration is 1 (enabled).";
        _notesAsRecommended = "Configuration is already set as recommended.";
        _recommendedValue = 1;
    }

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
            SqlInstance, SqlCredential, EnableException.ToBool(), _notesAdHocZero,
            _notesAsRecommended, _recommendedValue,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $EnableException, $notesAdHocZero, $notesAsRecommended, $recommendedValue, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($SqlInstance, $SqlCredential, $EnableException, $notesAdHocZero, $notesAsRecommended, $recommendedValue)

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaOptimizeForAdHoc
            }

            #Get current configured value
            $optimizeAdHoc = $server.Configuration.OptimizeAdhocWorkloads.ConfigValue

            #Setting notes for optimize adhoc value
            if ($optimizeAdHoc -eq $recommendedValue) {
                $notes = $notesAsRecommended
            } else {
                $notes = $notesAdHocZero
            }

            [PSCustomObject]@{
                ComputerName             = $server.ComputerName
                InstanceName             = $server.ServiceName
                SqlInstance              = $server.DomainInstanceName
                CurrentOptimizeAdHoc     = $optimizeAdHoc
                RecommendedOptimizeAdHoc = $recommendedValue
                Notes                    = $notes
            }
        }
} $SqlInstance $SqlCredential $EnableException $notesAdHocZero $notesAsRecommended $recommendedValue @__commonParameters 3>&1 2>&1
""";
}
