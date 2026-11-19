#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a sequence in a database. Port of public/New-DbaDbSequence.ps1; the workflow remains a
/// module-scoped PowerShell compatibility hop.
///
/// PROCESS-ONLY, one hop. $InputObject is ValueFromPipeline, so process fires per piped database.
///
/// THIS ROW IS THE .IsPresent CLASS, and it is the reason -Cycle crosses as a SwitchParameter
/// OBJECT rather than as .ToBool(). Source :185 does "$newSequence.IsCycleEnabled = $Cycle.IsPresent".
/// A [switch] marshaled through .ToBool() arrives as a plain bool whose .IsPresent is '' - falsy -
/// so cycling would be SILENTLY DISABLED while every other check on that variable still behaved,
/// which is exactly why the class survives review. Per B's combined rule (2026-07-18): receive
/// switches UNTYPED in the hop param and pass the SwitchParameter OBJECT. Untyped is what avoids
/// the other half of the collision - a typed [switch] hop param is excluded from positional binding
/// and shifts every following argument. Object + untyped is safe on both axes. -EnableException
/// crosses the same way. Same treatment E applied to -Cycle on Set-DbaDbSequence (W2-187).
///
/// NO INTERRUPT BRIDGE, deliberately. The single guard at :152-155 ("Database is required when
/// SqlInstance is specified") is Stop-Function WITHOUT -Continue and does set the module latch, but
/// this source contains NO Test-FunctionInterrupt to read it back, so the guard re-warns on EVERY
/// record; bridging would emit ONE warning where the source emits N. Bridge only where the SOURCE
/// reads the latch back - contrast W2-145, which does and therefore does bridge.
///
/// NO CROSS-RECORD CARRY. Source :158 does "$InputObject += Get-DbaDatabase ..." but the mutated
/// variable IS THE PIPELINE-BOUND PARAMETER, which the binder rewrites before every record. Verified
/// mechanically as well as by reading: migration/tools/Find-AccumulatorCarry.ps1 reports zero
/// accumulator candidates. $newSequence (:182), $schemaObject (:174/:178), $tableParts (:188) and
/// the loop variables $instance and $db are each assigned before use within their own iteration.
///
/// SIX Test-Bound SITES BECOME CARRIED CALLER-BOUNDNESS FLAGS (Test-Bound never rides a hop):
/// SqlInstance and Database (:152), Schema (:173), MinValue (:201), MaxValue (:205), CacheSize
/// (:209). Two of them are load-bearing in ways a value test would get wrong:
///
///  - Schema carries a DEFAULT of "dbo" yet is Test-Bound gated, so the create-the-schema-if-missing
///    path at :173-180 runs ONLY when the caller passed -Schema explicitly. A property initializer
///    cannot express that: it makes the default indistinguishable from an explicit pass.
///  - CacheSize distinguishes BOUND-ZERO from UNBOUND: "-CacheSize 0" selects NoCache (:211) while
///    omitting it selects DefaultCache (:217). Testing the value for 0 or null would collapse those
///    two into one, silently changing the cache mode.
///
/// Both therefore come from MyInvocation.BoundParameters, which is the only source that reflects
/// what the CALLER actually passed.
///
/// STREAMING, NOT BUFFERED (DEF-001): sequences are created one at a time and each is re-read and
/// emitted at :221, so a buffered hop would discard the record of sequences already created when a
/// later failure terminated the hop under -EnableException.
///
/// The one $Pscmdlet.ShouldProcess gate at :171 routes to the real cmdlet via $__realCmdlet. The
/// three in-loop Stop-Function calls (:164 pre-2012 instance, :168 sequence exists, :223 create
/// failure) carry -Continue. In-hop Stop-Function calls carry -FunctionName. -Sequence is Mandatory
/// at position 3 and carries Alias("Name"), preserved on the C# property. Implicit positions 0-11
/// are made explicit per the W2-071 law and were CONFIRMED against the exported baseline; the two
/// switches carry none. Surface pinned by migration/baselines/New-DbaDbSequence.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDbSequence", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaDbSequenceCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) the sequence is created in.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The name(s) of the sequence(s) to create.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [Alias("Name")]
    [PsStringArrayCast]
    public string[] Sequence { get; set; } = null!;

    /// <summary>The schema that owns the sequence; the schema is created if missing, but only when this is passed explicitly.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string Schema { get; set; } = "dbo";

    /// <summary>The integer type backing the sequence.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string IntegerType { get; set; } = "bigint";

    /// <summary>The first value of the sequence.</summary>
    [Parameter(Position = 6)]
    public long StartWith { get; set; } = 1;

    /// <summary>The step between sequence values.</summary>
    [Parameter(Position = 7)]
    public long IncrementBy { get; set; } = 1;

    /// <summary>The minimum value; applied only when explicitly passed.</summary>
    [Parameter(Position = 8)]
    public long MinValue { get; set; }

    /// <summary>The maximum value; applied only when explicitly passed.</summary>
    [Parameter(Position = 9)]
    public long MaxValue { get; set; }

    /// <summary>Restart the sequence when it reaches its limit.</summary>
    [Parameter]
    public SwitchParameter Cycle { get; set; }

    /// <summary>Cache size; 0 selects NoCache, omitting the parameter selects DefaultCache.</summary>
    [Parameter(Position = 10)]
    public int CacheSize { get; set; }

    /// <summary>Databases piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 11)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {

        // Streaming, not buffered (DEF-001): sequences are created and emitted one at a time, so a
        // buffered hop would drop the audit trail of sequences already created.
        // NOTE: Cycle and EnableException are passed as SwitchParameter OBJECTS, never .ToBool() -
        // the body reads $Cycle.IsPresent at source :185.
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
            SqlInstance, SqlCredential, Database, Sequence, Schema, IntegerType, StartWith,
            IncrementBy, MinValue, MaxValue, Cycle, CacheSize, InputObject, EnableException,
            MyInvocation.BoundParameters.ContainsKey("SqlInstance"),
            MyInvocation.BoundParameters.ContainsKey("Database"),
            MyInvocation.BoundParameters.ContainsKey("Schema"),
            MyInvocation.BoundParameters.ContainsKey("MinValue"),
            MyInvocation.BoundParameters.ContainsKey("MaxValue"),
            MyInvocation.BoundParameters.ContainsKey("CacheSize"),
            this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM, dot-sourced so its early return exits only the body and not
    // the whole hop. Edits: the six Test-Bound probes become carried caller-boundness flags, the one
    // $Pscmdlet gate routes to $__realCmdlet, and -FunctionName is stamped on the four Stop-Function
    // calls. NO sentinel epilogue: this source never reads the interrupt latch back.
    //
    // $Cycle and $EnableException are received UNTYPED and arrive as SwitchParameter OBJECTS, so
    // "$Cycle.IsPresent" at source :185 keeps working. Typing them [switch] here would instead
    // exclude them from positional binding and shift every following argument.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Sequence, $Schema, $IntegerType, $StartWith, $IncrementBy, $MinValue, $MaxValue, $Cycle, $CacheSize, $InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__boundSchema, $__boundMinValue, $__boundMaxValue, $__boundCacheSize, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Sequence, [string]$Schema, [string]$IntegerType, [long]$StartWith, [long]$IncrementBy, [long]$MinValue, [long]$MaxValue, $Cycle, [int32]$CacheSize, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__boundSchema, $__boundMinValue, $__boundMaxValue, $__boundCacheSize, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {

        if (($__boundSqlInstance) -and (-not $__boundDatabase)) {
            Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName New-DbaDbSequence
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {

            if ($db.Parent.VersionMajor -lt 11) {
                Stop-Function -Message "This command only supports SQL Server 2012 and higher." -Continue -FunctionName New-DbaDbSequence
            }

            if (($db.Sequences | Where-Object { $_.Schema -eq $Schema -and $_.Name -eq $Sequence })) {
                Stop-Function -Message "Sequence $Sequence already exists in the $Schema schema in the database $($db.Name) on $($db.Parent.Name)" -Continue -FunctionName New-DbaDbSequence
            }

            if ($__realCmdlet.ShouldProcess($db.Parent.Name, "Creating the sequence $Sequence in the $Schema schema in the database $($db.Name) on $($db.Parent.Name)")) {
                try {
                    if ($__boundSchema) {
                        $schemaObject = $db | Get-DbaDbSchema -Schema $Schema -IncludeSystemSchemas

                        # if the schema does not exist then create it
                        if ($null -eq $schemaObject) {
                            $schemaObject = $db | New-DbaDbSchema -Schema $Schema
                        }
                    }

                    $newSequence = New-Object Microsoft.SqlServer.Management.Smo.Sequence -ArgumentList $db, $Sequence, $Schema
                    $newSequence.StartValue = $StartWith
                    $newSequence.IncrementValue = $IncrementBy
                    $newSequence.IsCycleEnabled = $Cycle.IsPresent

                    # support for user defined integer types
                    $tableParts = $IntegerType -Split "\."

                    if ($db.UserDefinedDataTypes[$IntegerType]) {
                        # check to see if the type is in the user defined types for this db
                        $newSequence.DataType = $db.UserDefinedDataTypes[$IntegerType]
                    } elseif ($tableParts.Count -eq 2) {
                        # custom type with the format "schema.typename"
                        $newSequence.DataType = $db.UserDefinedDataTypes | Where-Object { $_.Schema -eq $tableParts[0] -and $_.Name -eq $tableParts[1] }
                    } else {
                        # system integer type
                        $newSequence.DataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $IntegerType
                    }

                    if ($__boundMinValue) {
                        $newSequence.MinValue = $MinValue
                    }

                    if ($__boundMaxValue) {
                        $newSequence.MaxValue = $MaxValue
                    }

                    if ($__boundCacheSize) {
                        if ($CacheSize -eq 0) {
                            $newSequence.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::NoCache
                        } else {
                            $newSequence.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::CacheWithSize
                            $newSequence.CacheSize = $CacheSize
                        }
                    } else {
                        $newSequence.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::DefaultCache
                    }

                    $newSequence.Create()
                    $db | Get-DbaDbSequence -Sequence $newSequence.Name -Schema $newSequence.Schema
                } catch {
                    Stop-Function -Message "Failure on $($db.Parent.Name) to create the sequence $Sequence in the $Schema schema in the database $($db.Name)" -ErrorRecord $_ -Continue -FunctionName New-DbaDbSequence
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Database $Sequence $Schema $IntegerType $StartWith $IncrementBy $MinValue $MaxValue $Cycle $CacheSize $InputObject $EnableException $__boundSqlInstance $__boundDatabase $__boundSchema $__boundMinValue $__boundMaxValue $__boundCacheSize $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
