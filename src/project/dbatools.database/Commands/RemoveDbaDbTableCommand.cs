#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes tables from one or more databases. Port of public/Remove-DbaDbTable.ps1 (W2-170); the
/// workflow remains a module-scoped PowerShell compatibility hop.
///
/// Same three-block accumulate-then-drop family as W2-172 Remove-DbaDbUdf and W3-072
/// Remove-DbaCredential: begin inits the collection, process reassigns or appends per record, END
/// drops. This port deliberately SYNTHESISES the best of the two independent implementations of that
/// family (mine and E's, diffed head-to-head on W2-172):
///
///   ADOPTED FROM E, because E's mechanics were measurably better than my W2-172 port:
///     * The state sentinel is emitted from a `finally`, so the accumulator survives an exception in
///       the body. My W2-172 port emitted at end-of-body and declared the loss as an accepted
///       residual - closing it is strictly better than rationalising it.
///     * InvokeScopedStreaming rather than InvokeScoped. The source's end block emits each $output as
///       it drops each table, so output STREAMS; a buffered invocation collects the whole block first,
///       which is observably different for a downstream `| Select-Object -First 1`.
///
///   AVOIDED FROM E, because measurement found it broken there:
///     * The end-block restore is GUARDED. E's W2-172 wrote `$tables = @( $__carriedTables )`
///       unguarded, and `@($null)` has Count 1, not 0 - so an EMPTY pipeline iterated once over
///       $null and emitted a bogus failure object where the source emits nothing. Measured: E's port
///       1 object + spurious warning, legacy 0. Here the restore is
///       `if ($null -eq $__carriedTables) { @( ) } else { @( $__carriedTables ) }` in BOTH hops.
///
/// TWO $PSBoundParameters reads, and BOTH must be substituted - this is the row's real hazard,
/// because inside a hop `$PSBoundParameters` is the SCRIPTBLOCK's, not the cmdlet's:
///     1. The guard `if (-not $PSBoundParameters.SqlInstance -and -not $PSBoundParameters.InputObject)`
///        tests the TRUTHINESS OF THE BOUND VALUE - it is NOT a was-it-supplied test, despite looking
///        like one. CORRECTED after the carrier-semantics sweep: I first carried it as
///        $__boundSqlInstance / $__boundInputObject, i.e. BOUNDNESS, and that diverges exactly where
///        it matters - a bound-but-falsy `-SqlInstance @( )` or `-InputObject @( )` makes the SOURCE
///        take the guard path while a boundness carrier lets the port sail past it into the drop loop.
///        The correct substitution needs NO carrier at all: the hop already receives the values, so
///        the guard tests `-not $SqlInstance -and -not $InputObject` directly, which is precisely what
///        the source does. Contrast case 2 below and the Test-Bound rows elsewhere in this satellite -
///        there is no universally right carrier form, only reproducing the source's own test.
///     2. `$params = $PSBoundParameters` is splatted into Get-DbaDbTable. It rides as a per-record
///        Hashtable clone of THIS cmdlet's bound parameters, and the verbatim Remove('WhatIf') /
///        Remove('Confirm') lines then run against that clone. Note the source mutates the LIVE
///        dictionary (a hashtable is a reference and $params is not a copy); the clone re-supplies the
///        keys each record and removes them again before its only use, which is behaviourally
///        identical for identical invocations.
///
/// The process block's early exit is a plain `return`, reproduced by a return inside the hop
/// scriptblock, so NO continue-guard wrapper is involved.
///
/// ShouldProcess is real at HIGH impact, gated once in end, so $PSCmdlet.ShouldProcess becomes
/// $__realCmdlet.ShouldProcess with target and action byte-for-byte; the end hop carries
/// -WhatIf/-Confirm explicitly. The private Get-ErrorMessage helper resolves via module scope.
///
/// PRESERVED SOURCE BUG: the drop failure message says "Failed removing the VIEW ..." inside a TABLE
/// command - a copy/paste slip from the sibling Remove-DbaDbView. Reproduced verbatim per the
/// verbatim-source-bugs law and logged upstream; it is user-visible text on the error path.
///
/// Pre-port DEF-012 detector returns clean, and as on W2-172 that is EXPECTED rather than reassuring:
/// the tool reads the process block only while this accumulator is consumed in `end`. The carry here
/// was found by reading the block structure, which is the only way this shape is ever found.
///
/// Surface pinned by migration/baselines/Remove-DbaDbTable.json
/// (sourceSha256 6cb4fa3494ba3a115287b4e8ac706aba25353ff2b610e6e2e8ac527094adfad9): DefaultParameterSetName
/// "Default" with NO per-parameter sets; SqlInstance 0, SqlCredential 1, Database 2, Table 3 (alias
/// Name), InputObject 4 ValueFromPipeline; outputType empty. Positions declared explicitly per the
/// positional-binding-loss class.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbTable", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "Default")]
public sealed class RemoveDbaDbTableCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The table(s) to remove.</summary>
    [Parameter(Position = 3)]
    [Alias("Name")]
    public string[]? Table { get; set; }

    /// <summary>Table object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.Table[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The cross-block $tables accumulator (begin inits, process accumulates per record, end drops).
    private object? _tables;

    protected override void ProcessRecord()
    {

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item is not null && LanguagePrimitives.IsTrue(item.Properties["__removeDbaDbTableState"]?.Value))
            {
                _tables = item.Properties["Tables"]?.Value;
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
            SqlInstance, SqlCredential, Database, Table, InputObject, EnableException.ToBool(),
            _tables, BoundParametersForSplat(),
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
            _tables, EnableException.ToBool(), this,
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

    // PS: the process body VERBATIM per record. Substitutions: the two $PSBoundParameters property
    // reads in the guard -> the hop's own $SqlInstance / $InputObject VALUES (truthiness parity per
    // the class doc above - no boundness carrier), and $PSBoundParameters -> the carried
    // $__boundParams clone (the verbatim Remove lines then run against it). The accumulator restores from the carry and is emitted from a finally so it
    // survives an exception in the body.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Table, $InputObject, $EnableException, $__carriedTables, $__boundParams, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Table, [Microsoft.SqlServer.Management.Smo.Table[]]$InputObject, $EnableException, $__carriedTables, $__boundParams, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    try {
        # The begin block's "$tables = @( )" runs ONCE for the whole invocation, so every record
        # after the first restores the accumulated collection instead of re-initialising it.
        # TWO separate statements, NOT "$tables = if (...) { @( ) } else { @( $__carriedTables ) }".
        # An if-EXPRESSION unrolls its output on assignment: a one-element @( ) collapses to the bare
        # element and an empty one collapses to $null, after which "$tables += $InputObject" fails
        # with op_Addition on the SMO type and only the last record's table survives. Measured - the
        # 3-test suite passes either way, a 3-record pipeline drops 1 of 3.
        # GUARDED too: @( $null ) has Count 1, not 0, and would inject a phantom element.
        $tables = @( )
        if ($null -ne $__carriedTables) { $tables = @( $__carriedTables ) }

        if (-not $SqlInstance -and -not $InputObject) {
            Stop-Function -Message "You must specify either SqlInstance or InputObject" -FunctionName Remove-DbaDbTable
            return
        }
        if ($SqlInstance) {
            $params = $__boundParams
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $tables = Get-DbaDbTable @params
        } else {
            $tables += $InputObject
        }
    } finally {
        # Emitted from finally so the carry survives an exception in the body, and PLAIN rather than
        # unary-comma wrapped, which would collapse the collection to a single nested element.
        [pscustomobject]@{
            __removeDbaDbTableState = $true
            Tables                  = $tables
        }
    }
} $SqlInstance $SqlCredential $Database $Table $InputObject $EnableException $__carriedTables $__boundParams $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM. Substitutions: $PSCmdlet -> $__realCmdlet and -FunctionName
    // Remove-DbaDbTable on the Stop-Function site. The "Failed removing the view" wording is the
    // source's own copy/paste bug and is preserved deliberately.
    private const string EndScript = """
param($__carriedTables, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($__carriedTables, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # GUARDED restore, in TWO statements - see the class remarks. Unguarded, @( $__carriedTables )
    # turns "nothing accumulated" into one $null element and emits a bogus failure row on an empty
    # pipeline; written as a single if-EXPRESSION, the assignment unrolls and collapses the
    # collection. This form avoids both.
    $tables = @( )
    if ($null -ne $__carriedTables) { $tables = @( $__carriedTables ) }

    # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbTable.
    foreach ($tableItem in $tables) {
        if ($__realCmdlet.ShouldProcess($tableItem.Parent.Parent.Name, "Removing the table $($tableItem.Schema).$($tableItem.Name) in the database $($tableItem.Parent.Name) on $($tableItem.Parent.Parent.Name)")) {
            $output = [PSCustomObject]@{
                ComputerName = $tableItem.Parent.Parent.ComputerName
                InstanceName = $tableItem.Parent.Parent.ServiceName
                SqlInstance  = $tableItem.Parent.Parent.DomainInstanceName
                Database     = $tableItem.Parent.Name
                Table        = "$($tableItem.Schema).$($tableItem.Name)"
                TableName    = $tableItem.Name
                TableSchema  = $tableItem.Schema
                Status       = $null
                IsRemoved    = $false
            }
            try {
                $tableItem.Drop()
                $output.Status = "Dropped"
                $output.IsRemoved = $true
            } catch {
                Stop-Function -Message "Failed removing the view $($tableItem.Schema).$($tableItem.Name) in the database $($tableItem.Parent.Name) on $($tableItem.Parent.Parent.Name)" -ErrorRecord $_ -FunctionName Remove-DbaDbTable
                $output.Status = (Get-ErrorMessage -Record $_)
                $output.IsRemoved = $false
            }
            $output
        }
    }
} $__carriedTables $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
