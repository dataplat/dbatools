#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes an availability group.
/// Port of public/Remove-DbaAvailabilityGroup.ps1; surface pinned by
/// migration/baselines/Remove-DbaAvailabilityGroup.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaAvailabilityGroup", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaAvailabilityGroupCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability group.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability group or groups to remove.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>Remove every availability group on the instance.</summary>
    [Parameter]
    public SwitchParameter AllAvailabilityGroups { get; set; }

    /// <summary>Availability group objects piped from Get-DbaAvailabilityGroup.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Remove-DbaAvailabilityGroup");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop, fourth of the Remove-DbaAg* family.
        //
        // NO PARAMETER CARRY: the only process-block parameter mutation is
        // `$InputObject += Get-DbaAvailabilityGroup ...`, and $InputObject is the
        // ValueFromPipeline parameter, which the binder RE-BINDS every record. Nothing here is
        // sticky, so the sentinel carries prompt state only.
        //
        // FOUR carried bound flags, because this row has TWO multi-name Test-Bound forms rather
        // than the family's usual one:
        //   :101  Test-Bound -Not SqlInstance, InputObject                      -> NEITHER bound
        //   :106  (Test-Bound SqlInstance) -and
        //         (Test-Bound -Not AvailabilityGroup, AllAvailabilityGroups)    -> SqlInstance
        //         bound AND neither of the other two bound
        // Both -Not forms mean NEITHER, per Test-Bound's own logic (Min=1, Max=length,
        // `return ((-not $Not) -eq $test)`).
        //
        // $AllAvailabilityGroups DELIBERATELY DOES NOT RIDE THE HOP. The source references it
        // ONLY inside that Test-Bound call - never as a value - so once the guard becomes a
        // carried bound flag the parameter itself has no remaining use inside the body. Passing
        // it anyway would drag a [switch] into the hop param block, which is exactly the Class
        // #7/#8 switch-shift trap (a typed [switch] there is excluded from positional binding and
        // silently shifts every parameter after it). Omitting it sidesteps that entirely rather
        // than working around it.
        //
        // W3-082 PROMPT-STATE TRANSPLANT applies as with the siblings: VFP + per-record +
        // inner-$Pscmdlet gate + ConfirmImpact High, and here the gated action is a DROP of an
        // entire availability group - the most destructive action in this family - so losing
        // Yes/No-to-All between piped records is the divergence that matters most.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4048State"))
            {
                _state = sentinel["__w4048State"] as Hashtable;
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
            SqlInstance, SqlCredential, AvailabilityGroup, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
            TestBound(nameof(AvailabilityGroup)), TestBound(nameof(AllAvailabilityGroups)),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 101-129 after stripping three -FunctionName appends and reversing the two Test-Bound
    // rewrites (SOURCE comments). The source's "# avoid enumeration issues" comment rides
    // untouched. The ShouldProcess gate uses the inner block's own $Pscmdlet; the dot-block
    // preserves the source's two early returns. Bracketing the body: only the W3-082 prompt-state
    // transplant, injected before any gate and harvested by the tail - no parameter carry.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundAvailabilityGroup, $__boundAllAvailabilityGroups, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$AvailabilityGroup, [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundAvailabilityGroup, $__boundAllAvailabilityGroups, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified). No parameter carry on this
    # row - the only process-block param mutation targets the VFP $InputObject, which the
    # binder re-binds every record.
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Remove-DbaAvailabilityGroup: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Remove-DbaAvailabilityGroup
            return
        }

        if ($__boundSqlInstance -and (-not ($__boundAvailabilityGroup -or $__boundAllAvailabilityGroups))) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName AvailabilityGroup, AllAvailabilityGroups)) {
            Stop-Function -Message "You must specify AllAvailabilityGroups groups or AvailabilityGroups when using the SqlInstance parameter." -FunctionName Remove-DbaAvailabilityGroup
            return
        }
        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }
        foreach ($ag in $InputObject) {
            if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Removing availability group $ag")) {
                # avoid enumeration issues
                try {
                    $null = $ag.Parent.Query("DROP AVAILABILITY GROUP $ag")
                    [PSCustomObject]@{
                        ComputerName      = $ag.ComputerName
                        InstanceName      = $ag.InstanceName
                        SqlInstance       = $ag.SqlInstance
                        AvailabilityGroup = $ag.Name
                        Status            = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Remove-DbaAvailabilityGroup
                }
            }
        }
    }

    @{ __w4048State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $AvailabilityGroup $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__boundAvailabilityGroup $__boundAllAvailabilityGroups $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
