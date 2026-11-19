#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Modifies an existing sequence. Port of public/Set-DbaDbSequence.ps1; the workflow remains a
/// module-scoped PowerShell compatibility hop.
///
/// Test-Bound cannot ride the hop. It inspects the CALLER's bound parameters, and inside a hop the
/// caller is the scriptblock, not this cmdlet - every call would report the parameter unbound and
/// silently skip the property it guards. All eight call sites are therefore flag-substituted:
/// TestBound is evaluated here and crosses as a plain boolean per site.
///
/// $Cycle crosses as the SwitchParameter itself, NOT as a bool. The body reads $Cycle.IsPresent,
/// which exists on SwitchParameter and not on Boolean; passing a bool would make that expression
/// evaluate to $null and quietly disable cycling on every call. The inner param block leaves it
/// untyped, since declaring it [switch] there would skip positional binding and shift every later
/// argument.
///
/// The ShouldProcess gate is routed to the OUTER cmdlet ($Pscmdlet becomes $__realCmdlet). Beyond
/// attribution, -Confirm's "Yes to All" answer is held on the invoking runtime, so a gate owned by
/// the inner scriptblock would forget it between pipeline records and re-prompt for every database.
/// ConfirmImpact is High here, so that persistence matters more than usual.
///
/// The hop stays WHOLE-ARRAY rather than splitting per instance. The instance loop exists only to
/// accumulate into $InputObject ($InputObject += Get-DbaDatabase ...), which is cross-instance
/// state and is the per-element ruling's stated exemption.
///
/// No local needs a cross-record carry. $InputObject is re-bound from the pipeline on every record
/// before the accumulation runs, and $instance, $db and $sequenceObj are each assigned and read
/// within one iteration. The interrupt-latch hazard does not apply: the two guard Stop-Functions
/// return immediately from the record, and the rest are -Continue, which does not set the stop
/// latch; the source has no Test-FunctionInterrupt guard to short-circuit later records.
///
/// The hop streams rather than buffers. This command MUTATES server state and each emitted object
/// records a sequence that was actually altered, so a buffered invocation would discard the records
/// of already-altered sequences if a later database threw under -EnableException.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbSequence", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed class SetDbaDbSequenceCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database or databases holding the sequence.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The sequence or sequences to modify.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [Alias("Name")]
    public string[]? Sequence { get; set; }

    /// <summary>The schema holding the sequence.</summary>
    [Parameter(Position = 4)]
    public string Schema { get; set; } = "dbo";

    /// <summary>Restart the sequence at this value.</summary>
    [Parameter(Position = 5)]
    public long RestartWith { get; set; }

    /// <summary>The sequence increment.</summary>
    [Parameter(Position = 6)]
    public long IncrementBy { get; set; }

    /// <summary>The lowest value the sequence can generate.</summary>
    [Parameter(Position = 7)]
    public long MinValue { get; set; }

    /// <summary>The highest value the sequence can generate.</summary>
    [Parameter(Position = 8)]
    public long MaxValue { get; set; }

    /// <summary>Restart from the minimum (or maximum) value once the limit is reached.</summary>
    [Parameter]
    public SwitchParameter Cycle { get; set; }

    /// <summary>How many sequence values to pre-allocate; zero selects NoCache.</summary>
    [Parameter(Position = 9)]
    public int CacheSize { get; set; }

    /// <summary>SMO database object(s), typically from Get-DbaDatabase.</summary>
    [Parameter(Position = 10, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
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
        }, BodyScript,
            SqlInstance, SqlCredential, Database, Sequence, Schema, RestartWith, IncrementBy,
            MinValue, MaxValue, Cycle, CacheSize, InputObject, EnableException.ToBool(), this,
            TestBound(nameof(SqlInstance)), TestBound(nameof(Database)), TestBound(nameof(IncrementBy)),
            TestBound(nameof(RestartWith)), TestBound(nameof(MinValue)), TestBound(nameof(MaxValue)),
            TestBound(nameof(CacheSize)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source's process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet, the
    // eight Test-Bound call sites -> flags computed on the C# side, and -FunctionName on
    // Stop-Function/Write-Message.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Sequence, $Schema, $RestartWith, $IncrementBy, $MinValue, $MaxValue, $Cycle, $CacheSize, $InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundDatabase, $__boundIncrementBy, $__boundRestartWith, $__boundMinValue, $__boundMaxValue, $__boundCacheSize, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Sequence, [string]$Schema, [long]$RestartWith, [long]$IncrementBy, [long]$MinValue, [long]$MaxValue, $Cycle, [int32]$CacheSize, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundDatabase, $__boundIncrementBy, $__boundRestartWith, $__boundMinValue, $__boundMaxValue, $__boundCacheSize, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }


        if ($__boundSqlInstance -and (-not $__boundDatabase)) {
            Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName Set-DbaDbSequence
            return
        }

        if ($__boundIncrementBy -and ($IncrementBy -eq 0)) {
            Stop-Function -Message "IncrementBy cannot be zero" -FunctionName Set-DbaDbSequence
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {

            if ($__realCmdlet.ShouldProcess($db.Parent.Name, "Modifying the sequence $Sequence in the $Schema schema in the database $($db.Name) on $($db.Parent.Name)")) {
                try {
                    $sequenceObj = $db | Get-DbaDbSequence -Schema $Schema -Sequence $Sequence

                    if ($null -eq $sequenceObj) {
                        Stop-Function -Message "Unable to find sequence $Sequence in the $Schema schema in the database $($db.Name) on $($db.Parent.Name)" -Continue -FunctionName Set-DbaDbSequence
                    }

                    if ($__boundIncrementBy) {
                        $sequenceObj.IncrementValue = $IncrementBy
                    }

                    $sequenceObj.IsCycleEnabled = $Cycle.IsPresent

                    if ($__boundRestartWith) {
                        $sequenceObj.StartValue = $RestartWith # SMO does the restart logic when this value is changed and then Alter() is called (i.e. CurrentValue is also updated)
                    }

                    if ($__boundMinValue) {
                        $sequenceObj.MinValue = $MinValue
                    }

                    if ($__boundMaxValue) {
                        $sequenceObj.MaxValue = $MaxValue
                    }

                    if ($__boundCacheSize) {
                        if ($CacheSize -eq 0) {
                            $sequenceObj.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::NoCache
                        } else {
                            $sequenceObj.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::CacheWithSize
                            $sequenceObj.CacheSize = $CacheSize
                        }
                    } else {
                        $sequenceObj.SequenceCacheType = [Microsoft.SqlServer.Management.Smo.SequenceCacheType]::DefaultCache
                    }

                    $sequenceObj.Alter()
                    $db.Refresh()
                    $db.Sequences | Where-Object { $_.Schema -eq $Schema -and $_.Name -eq $Sequence }
                } catch {
                    Stop-Function -Message "Failure on $($db.Parent.Name) to modify the sequence $Sequence in the $Schema schema in the database $($db.Name)" -ErrorRecord $_ -Continue -FunctionName Set-DbaDbSequence
                }
            }
        }

} $SqlInstance $SqlCredential $Database $Sequence $Schema $RestartWith $IncrementBy $MinValue $MaxValue $Cycle $CacheSize $InputObject $EnableException $__realCmdlet $__boundSqlInstance $__boundDatabase $__boundIncrementBy $__boundRestartWith $__boundMinValue $__boundMaxValue $__boundCacheSize $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
