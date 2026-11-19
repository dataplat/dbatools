#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoOperator = Microsoft.SqlServer.Management.Smo.Agent.Operator;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes SQL Server Agent operators.
/// </summary>
/// <remarks>
/// The operator lookup (Get-DbaAgentOperator), the confirmation gate, the Drop, and the result-object
/// shaping all run the original dbatools PowerShell body inside the dbatools module scope rather than
/// being reimplemented in C#, so the engine decides the observable details.
///
/// The function collects every operator across the whole pipeline in its begin/process blocks and only
/// drops them in end, to avoid "Collection was modified" when piped directly from Get-DbaAgentOperator.
/// The accumulator ($dbOperators) is pipeline-spanning state a per-record hop scope cannot hold, so it
/// lives in C#: begin seeds an empty list, each process record contributes its operators (a
/// Get-DbaAgentOperator lookup when -SqlInstance is supplied, or the bound InputObject otherwise), and
/// the end hop receives the full list to drop.
///
/// The SqlInstance path reproduces the source's "$params = $PSBoundParameters; remove WhatIf/Confirm;
/// Get-DbaAgentOperator @params" by receiving this cmdlet's own MyInvocation.BoundParameters and
/// splatting it, so the lookup sees exactly the bound Operator/ExcludeOperator/SqlCredential/
/// EnableException supplied.
///
/// The end hop streams: it emits a result object per operator as each Drop runs, before a later Drop may
/// throw under -EnableException, so buffering would hide operators that were actually dropped. The
/// process hop is buffered - Get-DbaAgentOperator is read-only, the mutation is entirely in end.
///
/// This cmdlet supplies the real ShouldProcess runtime to the end hop (ConfirmImpact High, no -Force).
/// Surface pinned by migration/baselines/Remove-DbaAgentOperator.json.
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaAgentOperator", SupportsShouldProcess = true, DefaultParameterSetName = "Default", ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaAgentOperatorCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only remove these named operators.</summary>
    [Parameter]
    public string[]? Operator { get; set; }

    /// <summary>Remove all operators except these named ones.</summary>
    [Parameter]
    public string[]? ExcludeOperator { get; set; }

    /// <summary>Agent operator objects piped in from Get-DbaAgentOperator.</summary>
    [Parameter(ParameterSetName = "Pipeline", Mandatory = true, ValueFromPipeline = true)]
    public SmoOperator[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared. With no ParameterSetName it
    // belongs to every set, matching the source's plain [switch] declaration.

    // The pipeline-spanning accumulator: the source's begin "$dbOperators = @()", filled across process
    // records, drained in end.
    private List<PSObject> _dbOperators = null!;

    protected override void BeginProcessing()
    {
        _dbOperators = new List<PSObject>();
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Reproduce "$params = $PSBoundParameters" faithfully: this cmdlet's own bound parameters.
        Hashtable bound = new Hashtable(MyInvocation.BoundParameters);

        List<PSObject> recordItems = new List<PSObject>();
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, InputObject, bound,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            if (item is not null)
            {
                recordItems.Add(item);
            }
        }

        // Match the source's assignment semantics: the SqlInstance branch does "$dbOperators = Get-..."
        // (REPLACE), the InputObject branch does "$dbOperators += $InputObject" (APPEND). When -SqlInstance
        // is combined with piped records the lookup runs per record and replaces each time, so appending
        // would accumulate duplicate operators and Drop() them repeatedly.
        if (SqlInstance != null && SqlInstance.Length > 0)
        {
            _dbOperators = recordItems;
        }
        else
        {
            _dbOperators.AddRange(recordItems);
        }
    }

    protected override void EndProcessing()
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
            }
            else
            {
                WriteObject(item);
            }
        }, EndScript,
            _dbOperators.ToArray(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block. The source assigns/appends to $dbOperators; here it EMITS the operators and
    // the C# accumulates them, because the accumulator must span the pipeline (which a per-record hop
    // scope cannot). The SqlInstance branch splats the caller's bound parameters (minus WhatIf/Confirm) to
    // Get-DbaAgentOperator exactly as the source's $PSBoundParameters re-splat did.
    private const string ProcessScript = """
param($SqlInstance, $InputObject, $__bound, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [Microsoft.SqlServer.Management.Smo.Agent.Operator[]]$InputObject, [hashtable]$__bound)

    if ($SqlInstance) {
        $params = $__bound
        $null = $params.Remove('WhatIf')
        $null = $params.Remove('Confirm')
        Get-DbaAgentOperator @params
    } else {
        $InputObject
    }
} $SqlInstance $InputObject $__bound @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess and
    // -FunctionName Remove-DbaAgentOperator on the direct Stop-Function. $dbOperators is the accumulated
    // list the C# collected. EnableException is bound so Stop-Function's scope-walking default inherits
    // the caller's value (a Drop failure under -EnableException must throw).
    private const string EndScript = """
param($dbOperators, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($dbOperators, $EnableException, $__realCmdlet)

    # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaAgentOperator.
    foreach ($dbOperator in $dbOperators) {
        if ($__realCmdlet.ShouldProcess($dbOperator.Parent.Parent.Name, "Removing the SQL Agent operator $($dbOperator.Name) on $($dbOperator.Parent.Parent.Name)")) {
            $output = [PSCustomObject]@{
                ComputerName = $dbOperator.Parent.Parent.ComputerName
                InstanceName = $dbOperator.Parent.Parent.ServiceName
                SqlInstance  = $dbOperator.Parent.Parent.DomainInstanceName
                Name         = $dbOperator.Name
                Status       = $null
                IsRemoved    = $false
            }
            try {
                $dbOperator.Drop()
                $output.Status = "Dropped"
                $output.IsRemoved = $true
            } catch {
                Stop-Function -Message "Failed removing the SQL Agent operator $($dbOperator.Name) on $($dbOperator.Parent.Parent.Name)" -ErrorRecord $_ -FunctionName Remove-DbaAgentOperator
                $output.Status = (Get-ErrorMessage -Record $_)
                $output.IsRemoved = $false
            }
            $output
        }
    }
} $dbOperators $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
