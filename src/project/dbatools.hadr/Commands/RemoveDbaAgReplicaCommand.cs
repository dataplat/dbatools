#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes a replica from an availability group.
/// Port of public/Remove-DbaAgReplica.ps1; surface pinned by
/// migration/baselines/Remove-DbaAgReplica.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaAgReplica", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaAgReplicaCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability group.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability group or groups to remove the replicas from.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>The replica or replicas to remove.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Replica { get; set; }

    /// <summary>Replica objects piped from Get-DbaAgReplica.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityReplica[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Remove-DbaAgReplica");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop, third of the Remove-DbaAg* family (W4-045 database, W4-046 listener).
        //
        // NO PARAMETER CARRY, for the same reason as W4-046: the only process-block parameter
        // mutation is `$InputObject += Get-DbaAgReplica ...`, and $InputObject is the
        // ValueFromPipeline parameter, which the binder RE-BINDS every record. Unlike the W4-045
        // sibling there is no `+=` onto a non-pipeline parameter, so nothing is sticky. The
        // sentinel carries prompt state only.
        //
        // IT DIFFERS FROM BOTH SIBLINGS IN ONE DETAIL WORTH THE ATTENTION: its second guard is a
        // VALUE test, `if ($SqlInstance -and -not $Replica)`, NOT a Test-Bound call. The siblings
        // use `Test-Bound -Not Listener` / `-Not Database` there, which key on BINDING and so had
        // to become carried $__bound flags. This one keys on VALUE and therefore rides VERBATIM -
        // substituting a bound flag here would CHANGE behaviour, because an explicitly bound but
        // empty -Replica passes a Test-Bound check yet correctly FAILS this value check. So this
        // row has exactly ONE Test-Bound site (:87, the multi-name -Not form meaning NEITHER
        // bound) and one untouched value guard.
        //
        // W3-082 PROMPT-STATE TRANSPLANT applies as with the siblings: VFP + per-record +
        // inner-$Pscmdlet gate + ConfirmImpact High over a data-loss drop.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4047State"))
            {
                _state = sentinel["__w4047State"] as Hashtable;
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
            SqlInstance, SqlCredential, AvailabilityGroup, Replica, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 87-117 after stripping three -FunctionName appends and reversing the SINGLE
    // Test-Bound rewrite (SOURCE comment) - the second guard is a value test and is untouched.
    // The ShouldProcess gate uses the inner block's own $Pscmdlet; the dot-block preserves the
    // source's two early returns. Bracketing the body: only the W3-082 prompt-state transplant,
    // injected before any gate and harvested by the tail - no parameter carry on this row.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $Replica, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$AvailabilityGroup, [string[]]$Replica, [Microsoft.SqlServer.Management.Smo.AvailabilityReplica[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified). No parameter carry on this
    # row - the only process-block param mutation targets the VFP $InputObject, which the
    # binder re-binds every record.
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Remove-DbaAgReplica: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Remove-DbaAgReplica
            return
        }

        if ($SqlInstance -and -not $Replica) {
            Stop-Function -Message "You must specify a replica when using the SqlInstance parameter." -FunctionName Remove-DbaAgReplica
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAgReplica -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Replica $Replica -AvailabilityGroup $AvailabilityGroup
        }

        foreach ($agreplica in $InputObject) {
            if ($Pscmdlet.ShouldProcess($agreplica.Parent.Parent.Name, "Removing availability group replica $agreplica")) {
                try {
                    $agreplica.Drop()
                    [PSCustomObject]@{
                        ComputerName      = $agreplica.ComputerName
                        InstanceName      = $agreplica.InstanceName
                        SqlInstance       = $agreplica.SqlInstance
                        AvailabilityGroup = $agreplica.Parent.AvailabilityGroup
                        Replica           = $agreplica.Name
                        Status            = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Remove-DbaAgReplica
                }
            }
        }
    }

    @{ __w4047State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $AvailabilityGroup $Replica $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
