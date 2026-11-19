#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoPartitionFunction = Microsoft.SqlServer.Management.Smo.PartitionFunction;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Merges or splits the range boundaries of an existing partition function and re-emits the refreshed function
/// decorated like Get-DbaDbPartitionFunction.
/// </summary>
/// <remarks>
/// PartitionFunction.Alter() can change nothing meaningful (its ScriptAlter body is empty - only extended
/// properties), so this command is operation-based: it drives MergeRangePartition / SplitRangePartition, which
/// SMO executes IMMEDIATELY via ExecuteNonQuery with no scripting pipeline. That means -WhatIf gets nothing from
/// SMO and the operation would fire regardless unless the cmdlet gates it itself - so each operation runs inside
/// a passed $__realCmdlet.ShouldProcess, and the -WhatIf test asserts NumberOfPartitions did not move.
///
/// The boundary parameters are singular System.Object (one boundary per call, matching the SMO methods) and are
/// mutually exclusive. A split creates a new partition that needs a filegroup, so it requires the dependent
/// scheme's NEXT USED filegroup to be set first (Set-DbaDbPartitionScheme -NextUsedFileGroup); this command does
/// not pick a filegroup on the caller's behalf and surfaces a message naming that command when the split fails.
///
/// ConfirmImpact is High (an upward deviation): MERGE RANGE destroys a boundary and moves every row in the
/// merged partition, slow and irreversible without a restore, so it matches Remove-DbaDbPartitionFunction.
/// Either -SqlInstance or a piped Get-DbaDbPartitionFunction object (the Test-Bound duality, no parameter sets).
/// </remarks>
[Cmdlet(VerbsCommon.Set, "DbaDbPartitionFunction", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(SmoPartitionFunction))]
public sealed class SetDbaDbPartitionFunctionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to look in when resolving functions by name.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The name(s) of the partition function(s) to modify (on the -SqlInstance path).</summary>
    [Parameter(Position = 3)]
    [Alias("Name")]
    public string[]? PartitionFunction { get; set; }

    /// <summary>The boundary value to merge (removes that boundary). Mutually exclusive with -SplitRangePartition.</summary>
    [Parameter(Position = 4)]
    public object? MergeRangePartition { get; set; }

    /// <summary>The boundary value to split (adds that boundary). Requires a NEXT USED filegroup on the scheme.</summary>
    [Parameter(Position = 5)]
    public object? SplitRangePartition { get; set; }

    /// <summary>Partition function object(s) piped in from Get-DbaDbPartitionFunction.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public SmoPartitionFunction[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the designed spec declares it in __AllParameterSets.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

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
            SqlInstance, SqlCredential, Database, PartitionFunction, MergeRangePartition, SplitRangePartition,
            InputObject, EnableException.ToBool(), this,
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), TestBound(nameof(PartitionFunction)),
            TestBound(nameof(MergeRangePartition)), TestBound(nameof(SplitRangePartition)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the module-scoped body. Functions come from -SqlInstance (resolved via Get-DbaDbPartitionFunction) or
    // piped -InputObject. Exactly one of -MergeRangePartition / -SplitRangePartition is required. Each operation
    // (which SMO executes immediately) runs inside a passed ShouldProcess so -WhatIf never touches the server. A
    // split needs the dependent scheme's NEXT USED filegroup first; when it fails, the message names
    // Set-DbaDbPartitionScheme. The refreshed function is re-emitted via Get-DbaDbPartitionFunction.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $PartitionFunction, $MergeRangePartition, $SplitRangePartition, $InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundPartitionFunction, $__boundMerge, $__boundSplit, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$PartitionFunction, $MergeRangePartition, $SplitRangePartition, [Microsoft.SqlServer.Management.Smo.PartitionFunction[]]$InputObject, $EnableException, $__realCmdlet, $__boundSqlInstance, $__boundInputObject, $__boundPartitionFunction, $__boundMerge, $__boundSplit)

    if (-not $__boundSqlInstance -and -not $__boundInputObject) {
        Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Set-DbaDbPartitionFunction
        return
    }

    if ($__boundMerge -and $__boundSplit) {
        Stop-Function -Message "-MergeRangePartition and -SplitRangePartition are mutually exclusive; specify only one." -FunctionName Set-DbaDbPartitionFunction
        return
    }

    if (-not $__boundMerge -and -not $__boundSplit) {
        Stop-Function -Message "You must specify either -MergeRangePartition or -SplitRangePartition." -FunctionName Set-DbaDbPartitionFunction
        return
    }

    $functionsToProcess = New-Object System.Collections.Generic.List[object]

    if ($__boundInputObject) {
        foreach ($piped in $InputObject) { $functionsToProcess.Add($piped) }
    }

    if ($__boundSqlInstance) {
        foreach ($instance in $SqlInstance) {
            try {
                $found = Get-DbaDbPartitionFunction -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -PartitionFunction $PartitionFunction -EnableException
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaDbPartitionFunction
                continue
            }
            foreach ($f in $found) { $functionsToProcess.Add($f) }
        }
    }

    foreach ($pf in $functionsToProcess) {
        $db = $pf.Parent
        $server = $db.Parent
        $emit = $false

        if ($__boundMerge) {
            if ($__realCmdlet.ShouldProcess($server.DomainInstanceName, "Merging range partition $MergeRangePartition in partition function $($pf.Name) in database $($db.Name)")) {
                try {
                    $pf.MergeRangePartition($MergeRangePartition)
                    $emit = $true
                } catch {
                    Stop-Function -Message "Failed to merge range partition $MergeRangePartition in partition function $($pf.Name) in database $($db.Name) on $($server.DomainInstanceName)." -ErrorRecord $_ -Target $pf -Continue -FunctionName Set-DbaDbPartitionFunction
                    continue
                }
            }
        }

        if ($__boundSplit) {
            if ($__realCmdlet.ShouldProcess($server.DomainInstanceName, "Splitting range partition $SplitRangePartition in partition function $($pf.Name) in database $($db.Name)")) {
                try {
                    $pf.SplitRangePartition($SplitRangePartition)
                    $emit = $true
                } catch {
                    Stop-Function -Message "Failed to split range partition $SplitRangePartition in partition function $($pf.Name) in database $($db.Name) on $($server.DomainInstanceName). A split needs a NEXT USED filegroup on the dependent scheme - run Set-DbaDbPartitionScheme -NextUsedFileGroup first." -ErrorRecord $_ -Target $pf -Continue -FunctionName Set-DbaDbPartitionFunction
                    continue
                }
            }
        }

        if ($emit) {
            $pf.Refresh()
            Get-DbaDbPartitionFunction -SqlInstance $server -Database $db.Name -PartitionFunction $pf.Name
        }
    }
} $SqlInstance $SqlCredential $Database $PartitionFunction $MergeRangePartition $SplitRangePartition $InputObject $EnableException $__realCmdlet $__boundSqlInstance $__boundInputObject $__boundPartitionFunction $__boundMerge $__boundSplit @__commonParameters 3>&1 2>&1
""";
}
