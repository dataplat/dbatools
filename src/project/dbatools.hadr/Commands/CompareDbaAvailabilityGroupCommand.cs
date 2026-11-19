#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Orchestrates the four Compare-DbaAgReplica* commands (agent jobs, logins, credentials,
/// operators) across the replicas of availability groups, forwarding type-specific switches
/// to each. Port of public/Compare-DbaAvailabilityGroup.ps1; surface pinned by
/// migration/baselines/Compare-DbaAvailabilityGroup.json.
/// </summary>
[Cmdlet(VerbsData.Compare, "DbaAvailabilityGroup")]
public sealed class CompareDbaAvailabilityGroupCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability groups.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Restricts the comparison to these availability groups.</summary>
    [Parameter(Position = 2)]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>Object types to compare; All expands to the full set.</summary>
    [Parameter(Position = 3)]
    [ValidateSet("AgentJob", "Login", "Credential", "Operator", "All")]
    public string[] Type { get; set; } = new[] { "All" };

    /// <summary>Excludes system jobs from the agent-job comparison.</summary>
    [Parameter]
    public SwitchParameter ExcludeSystemJob { get; set; }

    /// <summary>Excludes system logins from the login comparison.</summary>
    [Parameter]
    public SwitchParameter ExcludeSystemLogin { get; set; }

    /// <summary>Also reports modification-date drift for jobs and logins.</summary>
    [Parameter]
    public SwitchParameter IncludeModifiedDate { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The function's process-scope $Type persists across pipeline records: an "All"
    // expansion at record 1 REBINDS the local so later records keep the expanded
    // array even if the caller mutates the originally bound array mid-pipeline,
    // while a never-expanded $Type stays the live caller reference. The carrier
    // reproduces that scoping: seeded from the bound parameter once, re-checked and
    // rebound per record exactly like the source's pre-loop expansion (codex r1).
    private string[]? _typeCarrier;
    private bool _typeCarrierSeeded;

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (!_typeCarrierSeeded)
        {
            _typeCarrier = Type;
            _typeCarrierSeeded = true;
        }
        if (_typeCarrier is not null && HasAllType(_typeCarrier))
        {
            _typeCarrier = new[] { "AgentJob", "Login", "Credential", "Operator" };
        }

        if (SqlInstance is null)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
                new DbaInstanceParameter[] { instance }, SqlCredential, AvailabilityGroup,
                _typeCarrier, ExcludeSystemJob.ToBool(), ExcludeSystemLogin.ToBool(),
                IncludeModifiedDate.ToBool(), EnableException.ToBool(),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
            {
                if (item?.BaseObject is ErrorRecord nestedError)
                {
                    NestedCommand.RemoveDuplicateError(this, nestedError);
                    WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                    continue;
                }
                WriteObject(item);
            }
        }
    }

    private static bool HasAllType(string[] types)
    {
        // Mirrors the source's `"All" -in $Type`: PowerShell -in compares
        // case-insensitively (and ValidateSet admits any casing), so `-Type all`
        // must latch the expansion exactly like `-Type All` (codex r2).
        foreach (string type in types)
        {
            if (string.Equals(type, "All", System.StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    // PS: the source process foreach VERBATIM. ONE structural substitution (codex
    // r3): the source's pre-loop Type expansion is EXCISED from the hop and lives
    // solely in the per-record _typeCarrier above - in the source it runs once per
    // process invocation, but a per-element hop would re-run it per SqlInstance
    // element. Restoring these source lines ahead of the foreach reproduces the
    // source bytes exactly:
    // SOURCE:  if ("All" -in $Type) {
    // SOURCE:      $Type = @("AgentJob", "Login", "Credential", "Operator")
    // SOURCE:  }
    // No other substitutions: no Stop-Function, no gates, no Test-Bound.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $Type, $ExcludeSystemJob, $ExcludeSystemLogin, $IncludeModifiedDate, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$AvailabilityGroup, [string[]]$Type, $ExcludeSystemJob, $ExcludeSystemLogin, $IncludeModifiedDate, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        foreach ($instance in $SqlInstance) {
            if ("AgentJob" -in $Type) {
                $splatAgentJob = @{
                    SqlInstance     = $instance
                    SqlCredential   = $SqlCredential
                    EnableException = $EnableException
                }

                if ($AvailabilityGroup) {
                    $splatAgentJob["AvailabilityGroup"] = $AvailabilityGroup
                }

                if ($ExcludeSystemJob) {
                    $splatAgentJob["ExcludeSystemJob"] = $true
                }

                if ($IncludeModifiedDate) {
                    $splatAgentJob["IncludeModifiedDate"] = $true
                }

                Compare-DbaAgReplicaAgentJob @splatAgentJob
            }

            if ("Login" -in $Type) {
                $splatLogin = @{
                    SqlInstance     = $instance
                    SqlCredential   = $SqlCredential
                    EnableException = $EnableException
                }

                if ($AvailabilityGroup) {
                    $splatLogin["AvailabilityGroup"] = $AvailabilityGroup
                }

                if ($ExcludeSystemLogin) {
                    $splatLogin["ExcludeSystemLogin"] = $true
                }

                if ($IncludeModifiedDate) {
                    $splatLogin["IncludeModifiedDate"] = $true
                }

                Compare-DbaAgReplicaLogin @splatLogin
            }

            if ("Credential" -in $Type) {
                $splatCredential = @{
                    SqlInstance     = $instance
                    SqlCredential   = $SqlCredential
                    EnableException = $EnableException
                }

                if ($AvailabilityGroup) {
                    $splatCredential["AvailabilityGroup"] = $AvailabilityGroup
                }

                Compare-DbaAgReplicaCredential @splatCredential
            }

            if ("Operator" -in $Type) {
                $splatOperator = @{
                    SqlInstance     = $instance
                    SqlCredential   = $SqlCredential
                    EnableException = $EnableException
                }

                if ($AvailabilityGroup) {
                    $splatOperator["AvailabilityGroup"] = $AvailabilityGroup
                }

                Compare-DbaAgReplicaOperator @splatOperator
            }
        }
} $SqlInstance $SqlCredential $AvailabilityGroup $Type $ExcludeSystemJob $ExcludeSystemLogin $IncludeModifiedDate $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
