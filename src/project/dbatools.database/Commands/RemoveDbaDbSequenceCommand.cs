#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Drops sequences. Port of public/Remove-DbaDbSequence.ps1; the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// This is a genuine begin/process/END command and is ported as one. The source accumulates into
/// $sequences during process and does all the dropping in end, and that deferral is deliberate - the
/// source comment explains it: dropping while enumerating a collection piped straight from
/// Get-DbaDbSequence raises "Collection was modified; enumeration operation may not execute." So the
/// port keeps the work in EndProcessing rather than emitting per record. Emitting per record would
/// change both the output timing and the enumeration safety that comment exists to protect.
///
/// $sequences therefore accumulates ACROSS RECORDS, which a hop cannot do on its own: the process hop
/// reports the accumulated collection back through a sentinel, the cmdlet holds it between records,
/// and the end hop receives it once. The begin block is the single line "$sequences = @( )", so the
/// cmdlet's own empty starting state is that initialiser - it is not re-run per record, which would
/// discard everything an earlier record collected.
///
/// $PSBoundParameters cannot ride the hop. Inside one it is the HOP SCRIPTBLOCK's dictionary, not
/// the cmdlet's - probed directly, a hop reading it saw the internal carrier parameter alongside the
/// real ones. The source splats that dictionary straight into Get-DbaDbSequence, so shipping it verbatim
/// would pass hop plumbing as if it were user parameters. The real bound parameters are marshalled
/// in from here instead; the source's own Remove('WhatIf') / Remove('Confirm') lines then run
/// against it verbatim. This is the same family as Test-Bound and fails the same way: no error, just
/// wrong behaviour.
///
/// The ShouldProcess gate is routed to the OUTER cmdlet. ConfirmImpact is High, so this prompts by
/// default, and -Confirm's "Yes to All" answer lives on the invoking runtime - an inner-owned gate
/// would forget it and re-prompt for every view.
///
/// The two parameter sets are preserved exactly as the source declares them, including
/// -SqlInstance mandatory at position 0 in NonPipeline and -InputObject mandatory and pipeline-bound
/// in Pipeline.
///
/// No stop latch: the source has no Test-FunctionInterrupt guard. Note its Stop-Function in the drop
/// catch has NO -Continue and no return, so it falls through to assign $output.Status and emit the
/// failed record - that fall-through is the source's behaviour and ships unchanged.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbSequence", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed class RemoveDbaDbSequenceCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ParameterSetName = "NonPipeline", Mandatory = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database or databases holding the sequences.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    public string[]? Database { get; set; }

    /// <summary>The sequence or sequences to drop.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Alias("Name")]
    public string[]? Sequence { get; set; }

    /// <summary>The schema holding the sequences.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    public string[]? Schema { get; set; }

    /// <summary>SMO sequence object(s), typically from Get-DbaDbSequence.</summary>
    [Parameter(ParameterSetName = "Pipeline", Mandatory = true, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.Sequence[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The source's begin block is "$sequences = @( )", so this empty state IS that initialiser. It is
    // deliberately NOT reset per record: process accumulates across records and end consumes once.
    private object? _sequences;

    protected override void ProcessRecord()
    {

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__removeDbaDbSequenceState"]?.Value))
            {
                _sequences = item.Properties["Sequences"]?.Value;
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
            SqlInstance, SqlCredential, Database, Sequence, Schema, InputObject, EnableException.ToBool(),
            _sequences, BoundParametersForSplat(),
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
            _sequences, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // The cmdlet's REAL bound parameters, for the source's "Get-DbaDbSequence @params" splat. A hop's own
    // $PSBoundParameters would include the hop carrier parameters, so it cannot be used.
    private Hashtable BoundParametersForSplat()
    {
        Hashtable splat = new Hashtable(StringComparer.OrdinalIgnoreCase);
        foreach (System.Collections.Generic.KeyValuePair<string, object> pair in MyInvocation.BoundParameters)
            splat[pair.Key] = pair.Value;
        return splat;
    }

    // PS: the source's PROCESS body VERBATIM, with $sequences seeded from the carry and reported back.
    // Substitution: $PSBoundParameters -> $__boundParams (see the class remarks).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Sequence, $Schema, $InputObject, $EnableException, $__carriedSequences, $__boundParams, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Sequence, [string[]]$Schema, [Microsoft.SqlServer.Management.Smo.Sequence[]]$InputObject, $EnableException, $__carriedSequences, $__boundParams, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    try {
        # The begin block's "$sequences = @( )" runs ONCE for the whole invocation, so on every record
        # after the first the accumulated collection is restored instead of re-initialised.
        $sequences = @( )
        if ($null -ne $__carriedSequences) { $sequences = @( $__carriedSequences ) }

        if ($SqlInstance) {
            $params = $__boundParams
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $sequences = Get-DbaDbSequence @params
        } else {
            $sequences += $InputObject
        }

    } finally {
        # Emitted PLAIN, not as ", @( $sequences )". The unary-comma wrapping looks like the safe way to
        # preserve a collection, but measured over three records it collapses the carry to a single
        # element (the next hop's "@( $__carriedSequences )" unwraps the outer array and keeps only the
        # nested one), which silently loses every sequence but the last. Plain assignment round-trips the
        # whole collection.
        [pscustomobject]@{
            __removeDbaDbSequenceState = $true
            Sequences                = $sequences
        }
    }
} $SqlInstance $SqlCredential $Database $Sequence $Schema $InputObject $EnableException $__carriedSequences $__boundParams $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the source's END body VERBATIM. Substitution: $PSCmdlet -> $__realCmdlet so the gate is
    // owned by the outer cmdlet and -Confirm's Yes-to-All survives.
    private const string EndScript = """
param($__carriedSequences, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($__carriedSequences, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $sequences = @( )
    if ($null -ne $__carriedSequences) { $sequences = @( $__carriedSequences ) }

        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbSequence.
        foreach ($sequenceItem in $sequences) {
            if ($__realCmdlet.ShouldProcess($sequenceItem.Parent.Parent.Name, "Removing the sequence $($sequenceItem.Schema).$($sequenceItem.Name) in the database $($sequenceItem.Parent.Name) on $($sequenceItem.Parent.Parent.Name)")) {
                $output = [PSCustomObject]@{
                    ComputerName   = $sequenceItem.Parent.Parent.ComputerName
                    InstanceName   = $sequenceItem.Parent.Parent.ServiceName
                    SqlInstance    = $sequenceItem.Parent.Parent.DomainInstanceName
                    Database       = $sequenceItem.Parent.Name
                    Sequence       = "$($sequenceItem.Schema).$($sequenceItem.Name)"
                    SequenceName   = $sequenceItem.Name
                    SequenceSchema = $sequenceItem.Schema
                    Status         = $null
                    IsRemoved      = $false
                }
                try {
                    $sequenceItem.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the sequence $($sequenceItem.Schema).$($sequenceItem.Name) in the database $($sequenceItem.Parent.Name) on $($sequenceItem.Parent.Parent.Name)" -ErrorRecord $_ -FunctionName Remove-DbaDbSequence
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }

} $__carriedSequences $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
