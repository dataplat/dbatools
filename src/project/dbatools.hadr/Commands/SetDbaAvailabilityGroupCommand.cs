#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets properties on an availability group.
/// Port of public/Set-DbaAvailabilityGroup.ps1; surface pinned by
/// migration/baselines/Set-DbaAvailabilityGroup.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaAvailabilityGroup", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SetDbaAvailabilityGroupCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability group.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability group or groups to modify.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>Modify every availability group on the instance.</summary>
    [Parameter]
    public SwitchParameter AllAvailabilityGroups { get; set; }

    /// <summary>Enable DTC support.</summary>
    [Parameter]
    public SwitchParameter DtcSupportEnabled { get; set; }

    /// <summary>The cluster type.</summary>
    [Parameter(Position = 3)]
    [ValidateSet("External", "Wsfc", "None")]
    [PsStringCast]
    public string? ClusterType { get; set; }

    /// <summary>The automated backup preference.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("None", "Primary", "Secondary", "SecondaryOnly")]
    [PsStringCast]
    public string? AutomatedBackupPreference { get; set; }

    /// <summary>The failure condition level.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("OnAnyQualifiedFailureCondition", "OnCriticalServerErrors", "OnModerateServerErrors",
        "OnServerDown", "OnServerUnresponsive")]
    [PsStringCast]
    public string? FailureConditionLevel { get; set; }

    /// <summary>The health check timeout.</summary>
    [Parameter(Position = 6)]
    public int HealthCheckTimeout { get; set; }

    /// <summary>Mark the group as a basic availability group.</summary>
    [Parameter]
    public SwitchParameter BasicAvailabilityGroup { get; set; }

    /// <summary>Enable the database health trigger.</summary>
    [Parameter]
    public SwitchParameter DatabaseHealthTrigger { get; set; }

    /// <summary>Mark the group as a distributed availability group.</summary>
    [Parameter]
    public SwitchParameter IsDistributedAvailabilityGroup { get; set; }

    /// <summary>The cluster connection option (SQL Server 2025+).</summary>
    [Parameter(Position = 7)]
    public string? ClusterConnectionOption { get; set; }

    /// <summary>Availability group objects piped from Get-DbaAvailabilityGroup.</summary>
    [Parameter(ValueFromPipeline = true, Position = 8)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The nine names the source iterates at :185. Kept in SOURCE ORDER and including "Name",
    // which is NOT a parameter of this command - see BuildBoundPropertyMap.
    private static readonly string[] PropertyNames =
    {
        "Name", "AutomatedBackupPreference", "BasicAvailabilityGroup", "ClusterType",
        "DatabaseHealthTrigger", "DtcSupportEnabled", "FailureConditionLevel",
        "HealthCheckTimeout", "IsDistributedAvailabilityGroup"
    };

    private Hashtable? _state;

    /// <summary>
    /// Builds the propertyName -> was-it-bound map that replaces the source's DYNAMIC
    /// `Test-Bound -ParameterName $prop`.
    ///
    /// WHY A MAP AND NOT PER-NAME FLAGS. Every other row in this satellite rewrites Test-Bound
    /// into a static $__bound&lt;Name&gt; flag, because the parameter name is a literal. Here the
    /// name is a LOOP VARIABLE, so there is no static name to bind a flag to - the body must be
    /// able to ask "was THIS name bound?" at runtime.
    ///
    /// WHY IT CANNOT JUST CALL Test-Bound INSIDE THE HOP. Measured before porting: in the SOURCE,
    /// with only -ClusterType supplied, Test-Bound reports ClusterType=True and the others False.
    /// In a HOP, every parameter is passed positionally and is therefore BOUND BY CONSTRUCTION -
    /// unbound ones simply arrive as $null - so the same three report True/True/True. A verbatim
    /// port would take the assignment branch for ALL NINE properties and then call Alter(),
    /// writing values the caller never specified. Data-affecting, not cosmetic.
    ///
    /// WHY "Name" IS IN THE LIST AND MUST STAY FALSE. This command has NO -Name parameter
    /// (verified against Get-Command), so in the source Test-Bound -ParameterName Name is always
    /// False and the assignment is unreachable - dead code in the props list. Building the map
    /// from MyInvocation.BoundParameters reproduces that for free: "Name" is never a key, so it
    /// maps to false. This matters because the OBVIOUS alternative - giving the hop a parameter
    /// per prop name so Get-Variable resolves - would invent a $Name parameter, make it bound by
    /// construction like all the others, and assign $ag.Name = $null before Alter(), BLANKING THE
    /// AVAILABILITY GROUP'S NAME.
    /// </summary>
    private Hashtable BuildBoundPropertyMap()
    {
        Hashtable map = new Hashtable(StringComparer.OrdinalIgnoreCase);
        foreach (string name in PropertyNames)
        {
            map[name] = MyInvocation.BoundParameters.ContainsKey(name);
        }
        return map;
    }

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Set-DbaAvailabilityGroup");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop. No begin block, no Test-FunctionInterrupt, so no DEF-011 latch
        // exposure. NO PARAMETER CARRY: the only process-block mutation targets the VFP
        // $InputObject at :183, which the binder RE-BINDS every record.
        //
        // THE DYNAMIC Test-Bound at :191 becomes a lookup in the carried bound-property map (see
        // BuildBoundPropertyMap for why a map rather than flags, and why it is not merely
        // cosmetic). That is the only rewrite inside the property loop; :192's
        // `$ag.$prop = (Get-Variable -Name $prop -ValueOnly)` rides VERBATIM and resolves against
        // the hop's own parameters, which carry the same names.
        //
        // THE FOUR SWITCH PROPERTIES (DtcSupportEnabled, BasicAvailabilityGroup,
        // DatabaseHealthTrigger, IsDistributedAvailabilityGroup) ride the hop UNTYPED carrying
        // .ToBool() values, per the Class #7/#8 switch-shift rule - a typed [switch] in a hop
        // param block is excluded from positional binding and shifts everything after it. They
        // must still be resolvable by name for :192, which untyped parameters are.
        //
        // :197 ClusterConnectionOption is an ordinary STATIC Test-Bound and takes the usual single
        // carried flag.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4058State"))
            {
                _state = sentinel["__w4058State"] as Hashtable;
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
            SqlInstance, SqlCredential, AvailabilityGroup, AllAvailabilityGroups.ToBool(),
            DtcSupportEnabled.ToBool(), ClusterType, AutomatedBackupPreference, FailureConditionLevel,
            HealthCheckTimeout, BasicAvailabilityGroup.ToBool(), DatabaseHealthTrigger.ToBool(),
            IsDistributedAvailabilityGroup.ToBool(), ClusterConnectionOption, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
            TestBound(nameof(AvailabilityGroup)), TestBound(nameof(AllAvailabilityGroups)),
            TestBound(nameof(ClusterConnectionOption)),
            BuildBoundPropertyMap(),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 173-211 after appending three -FunctionName arguments and reversing FOUR Test-Bound
    // rewrites (SOURCE comments) - three static guards plus the DYNAMIC one at :191, which becomes
    // a map lookup. The source's ClusterConnectionOption comment rides untouched. Bracketing the
    // body: only the W3-082 prompt-state transplant; no parameter carry on this row.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $AllAvailabilityGroups, $DtcSupportEnabled, $ClusterType, $AutomatedBackupPreference, $FailureConditionLevel, $HealthCheckTimeout, $BasicAvailabilityGroup, $DatabaseHealthTrigger, $IsDistributedAvailabilityGroup, $ClusterConnectionOption, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundAvailabilityGroup, $__boundAllAvailabilityGroups, $__boundClusterConnectionOption, $__boundProps, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$AvailabilityGroup, $AllAvailabilityGroups, $DtcSupportEnabled, [string]$ClusterType, [string]$AutomatedBackupPreference, [string]$FailureConditionLevel, [int]$HealthCheckTimeout, $BasicAvailabilityGroup, $DatabaseHealthTrigger, $IsDistributedAvailabilityGroup, [string]$ClusterConnectionOption, [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundAvailabilityGroup, $__boundAllAvailabilityGroups, $__boundClusterConnectionOption, $__boundProps, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified). No parameter carry on this
    # row - the only process-block param mutation targets the VFP $InputObject, re-bound every
    # record - and no non-parameter cross-record leak (DEF-012 sub-class checked).
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Set-DbaAvailabilityGroup: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Set-DbaAvailabilityGroup
            return
        }

        if ($__boundSqlInstance -and (-not ($__boundAvailabilityGroup -or $__boundAllAvailabilityGroups))) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName AvailabilityGroup, AllAvailabilityGroups)) {
            Stop-Function -Message "You must specify AllAvailabilityGroups groups or AvailabilityGroups when using the SqlInstance parameter." -FunctionName Set-DbaAvailabilityGroup
            return
        }
        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }
        $props = "Name", "AutomatedBackupPreference", "BasicAvailabilityGroup", "ClusterType", "DatabaseHealthTrigger", "DtcSupportEnabled", "FailureConditionLevel", "HealthCheckTimeout", "IsDistributedAvailabilityGroup"

        foreach ($ag in $InputObject) {
            try {
                if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Seting properties on $ag")) {
                    foreach ($prop in $props) {
                        if ($__boundProps[$prop]) { # SOURCE: if (Test-Bound -ParameterName $prop) {
                            $ag.$prop = (Get-Variable -Name $prop -ValueOnly)
                        }
                    }

                    # ClusterConnectionOption requires SQL Server 2025+ (version 17)
                    if ($__boundClusterConnectionOption) { # SOURCE: if ((Test-Bound -ParameterName ClusterConnectionOption)) {
                        if ($ag.Parent.VersionMajor -ge 17) {
                            $ag.ClusterConnectionOptions = $ClusterConnectionOption
                        } else {
                            Write-Message -Level Warning -Message "ClusterConnectionOption is only supported in SQL Server 2025 and above. Skipping this setting on $($ag.Parent.Name)." -FunctionName Set-DbaAvailabilityGroup -ModuleName "dbatools"
                        }
                    }

                    $ag.Alter()
                    $ag
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Set-DbaAvailabilityGroup
            }
        }
    }

    @{ __w4058State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $AvailabilityGroup $AllAvailabilityGroups $DtcSupportEnabled $ClusterType $AutomatedBackupPreference $FailureConditionLevel $HealthCheckTimeout $BasicAvailabilityGroup $DatabaseHealthTrigger $IsDistributedAvailabilityGroup $ClusterConnectionOption $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__boundAvailabilityGroup $__boundAllAvailabilityGroups $__boundClusterConnectionOption $__boundProps $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
