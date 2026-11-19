#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Drops partition functions from one or more databases. Port of
/// public/Remove-DbaDbPartitionFunction.ps1 (W2-162); the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// The fourth row of the three-block accumulate-then-drop family in this satellite (after W2-172,
/// W2-170 and the W3-072 exemplar), and it uses the pattern those rows converged on rather than
/// re-deriving it:
///
///   * The $partfuns accumulator rides the __removeDbaDbPartitionFunctionState sentinel, because
///     begin, each process record and end are separate scoped invocations and the collection would
///     otherwise reset per record while the drop happens in end.
///   * The sentinel is emitted from a FINALLY, so the carry survives an exception in the body. That
///     mechanic came from E's W2-172 port, which closed a gap my own first version of this family had
///     merely rationalised as an accepted residual.
///   * The restore is TWO STATEMENTS and null-GUARDED:
///         $partfuns = @( )
///         if ($null -ne $__carriedPartfuns) { $partfuns = @( $__carriedPartfuns ) }
///     Both halves are load-bearing and each was learned from a measured bug. Written as a single
///     if-EXPRESSION the assignment UNROLLS - a one-element carry collapses to the bare SMO object and
///     `$partfuns += $InputObject` then fails with op_Addition, silently dropping all but one item
///     (my W2-170 bug, which the gate could not see). Written unguarded as `@( $carried )`, a null
///     carry becomes ONE $null element and an empty pipeline emits a bogus failure row (E's W2-172
///     bug, which I measured). Neither form is safe alone.
///   * InvokeScopedStreaming rather than InvokeScoped, so the end block's per-item output streams as
///     the source's does instead of being buffered until the block completes.
///
/// The process body's `$params = $PSBoundParameters` splat into Get-DbaDbPartitionFunction rides as a
/// per-record Hashtable CLONE of this cmdlet's own bound parameters; inside a hop
/// $PSBoundParameters is the scriptblock's, so a verbatim carry would splat the hop's own arguments
/// into the command. The verbatim Remove('WhatIf') / Remove('Confirm') lines then run against the
/// clone. Behaviourally identical for identical invocations, the source mutating the live dictionary
/// once where the clone re-supplies and re-removes per record.
///
/// PARAMETER SETS mirrored from the baseline: Default (the declared default) and Pipeline. The
/// unattributed parameters sit in __AllParameterSets and therefore appear in BOTH sets, which is what
/// the baseline records. -InputObject is Pipeline-only, Mandatory, ValueFromPipeline. -EnableException
/// is PIPELINE-SET-ONLY - a genuine source quirk, not an oversight: `-SqlInstance ... -EnableException`
/// resolves to the Pipeline set and then demands -InputObject. It is reproduced by OVERRIDING the
/// virtual base property with the per-set attribute, exactly as the W3-072 exemplar does, since the
/// binder reads the most-derived declaration. NO positions anywhere - the baseline records none.
///
/// ShouldProcess is real at HIGH impact, gated once in end, so $PSCmdlet.ShouldProcess becomes
/// $__realCmdlet.ShouldProcess with target and action byte-for-byte; the end hop carries
/// -WhatIf/-Confirm explicitly. The catch path calls Stop-Function WITHOUT -Continue and still falls
/// through to emit the failure status object - source-verbatim, deliberately not tidied. The private
/// Get-ErrorMessage helper resolves via module scope.
///
/// Pre-port DEF-012 check is clean, and as on the other rows of this family that is EXPECTED rather
/// than reassuring: the detector reads the process block only while this accumulator is consumed in
/// `end`. The carry was identified by reading the block structure.
///
/// Surface pinned by migration/baselines/Remove-DbaDbPartitionFunction.json
/// (sourceSha256 2b36c982022e35e84160dfc91185f8c5e695f58d9cd9bb46faf17be055336e87).
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbPartitionFunction", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "Default")]
public sealed class RemoveDbaDbPartitionFunctionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Partition function object(s) piped in.</summary>
    [Parameter(ParameterSetName = "Pipeline", Mandatory = true, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.PartitionFunction[]? InputObject { get; set; }

    /// <summary>Replaces friendly warnings with terminating exceptions. PIPELINE-SET-ONLY in the
    /// source; the virtual base declaration is overridden to carry that per-set attribute.</summary>
    [Parameter(ParameterSetName = "Pipeline")]
    public override SwitchParameter EnableException { get; set; }

    // The cross-block $partfuns accumulator (begin inits, process accumulates, end drops).
    private object? _partfuns;

    protected override void ProcessRecord()
    {

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item is not null && LanguagePrimitives.IsTrue(item.Properties["__removeDbaDbPartitionFunctionState"]?.Value))
            {
                _partfuns = item.Properties["Partfuns"]?.Value;
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
            SqlInstance, InputObject, EnableException.ToBool(),
            _partfuns, BoundParametersForSplat(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
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
        }, EndScript,
            _partfuns, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // A per-record clone of THIS cmdlet's bound parameters for the source's @params splat. Case
    // insensitive so the verbatim Remove('WhatIf')/Remove('Confirm') cannot miss on casing.
    private Hashtable BoundParametersForSplat()
    {
        Hashtable splat = new Hashtable(StringComparer.OrdinalIgnoreCase);
        foreach (System.Collections.Generic.KeyValuePair<string, object> pair in MyInvocation.BoundParameters)
            splat[pair.Key] = pair.Value;
        return splat;
    }

    // PS: the process body VERBATIM per record. Substitutions: $PSBoundParameters -> the carried
    // $__boundParams clone (the verbatim Remove lines then run against it), and the accumulator
    // restores from the carry and is emitted from a finally so it survives an exception.
    private const string ProcessScript = """
param($SqlInstance, $InputObject, $EnableException, $__carriedPartfuns, $__boundParams, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [Microsoft.SqlServer.Management.Smo.PartitionFunction[]]$InputObject, $EnableException, $__carriedPartfuns, $__boundParams, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    try {
        # The begin block's "$partfuns = @( )" runs ONCE for the whole invocation, so every record
        # after the first restores the accumulation instead of re-initialising it. TWO statements and
        # null-guarded, deliberately: a single if-EXPRESSION unrolls the collection (collapsing a
        # one-element carry to a bare object, after which += fails), and an unguarded @( $carried )
        # turns a null carry into one $null element.
        $partfuns = @( )
        if ($null -ne $__carriedPartfuns) { $partfuns = @( $__carriedPartfuns ) }

        if ($SqlInstance) {
            $params = $__boundParams
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $partfuns = Get-DbaDbPartitionFunction @params
        } else {
            $partfuns += $InputObject
        }
    } finally {
        # From finally so the carry survives an exception in the body, and PLAIN rather than
        # unary-comma wrapped, which would collapse the collection to a single nested element.
        [pscustomobject]@{
            __removeDbaDbPartitionFunctionState = $true
            Partfuns                            = $partfuns
        }
    }
} $SqlInstance $InputObject $EnableException $__carriedPartfuns $__boundParams $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM. Substitutions: $PSCmdlet -> $__realCmdlet and -FunctionName
    // Remove-DbaDbPartitionFunction on the Stop-Function site. The comment, and the fall-through that
    // still emits the failure status object after a Stop-Function with no -Continue, are the source's.
    private const string EndScript = """
param($__carriedPartfuns, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($__carriedPartfuns, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # Guarded, two statements - see the process hop's comment for why both halves matter.
    $partfuns = @( )
    if ($null -ne $__carriedPartfuns) { $partfuns = @( $__carriedPartfuns ) }

    # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbPartitionFunction.
    foreach ($partfunItem in $partfuns) {
        if ($__realCmdlet.ShouldProcess($partfunItem.Parent.Parent.Name, "Removing the partition function [$($partfunItem.Name)] in the database [$($partfunItem.Parent.Name)] on [$($partfunItem.Parent.Parent.Name)]")) {
            $output = [PSCustomObject]@{
                ComputerName          = $partfunItem.Parent.Parent.ComputerName
                InstanceName          = $partfunItem.Parent.Parent.ServiceName
                SqlInstance           = $partfunItem.Parent.Parent.DomainInstanceName
                Database              = $partfunItem.Parent.Name
                PartitionFunctionName = $partfunItem.Name
                Status                = $null
                IsRemoved             = $false
            }
            try {
                $partfunItem.Drop()
                $output.Status = "Dropped"
                $output.IsRemoved = $true
            } catch {
                Stop-Function -Message "Failed removing the partition function [$($partfunItem.Name)] in the database [$($partfunItem.Parent.Name)] on [$($partfunItem.Parent.Parent.Name)]" -ErrorRecord $_ -FunctionName Remove-DbaDbPartitionFunction
                $output.Status = (Get-ErrorMessage -Record $_)
                $output.IsRemoved = $false
            }
            $output
        }
    }
} $__carriedPartfuns $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
