#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoProxyAccount = Microsoft.SqlServer.Management.Smo.Agent.ProxyAccount;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes SQL Server Agent proxies.
/// </summary>
/// <remarks>
/// The proxy lookup (Get-DbaAgentProxy), the confirmation gate, the Drop, and the result-object shaping
/// all run the original dbatools PowerShell body inside the dbatools module scope rather than being
/// reimplemented in C#, so the engine decides the observable details.
///
/// The function collects every proxy across the whole pipeline in its begin/process blocks and only
/// drops them in end, to avoid "Collection was modified" when piped directly from Get-DbaAgentProxy. The
/// accumulator ($dbProxies) is pipeline-spanning state a per-record hop scope cannot hold, so it lives in
/// C#: begin seeds an empty list, each process record contributes its proxies (a Get-DbaAgentProxy lookup
/// when -SqlInstance is supplied, or the bound InputObject otherwise), and the end hop receives the full
/// list to drop.
///
/// The SqlInstance path reproduces the source's "$params = $PSBoundParameters; remove WhatIf/Confirm;
/// Get-DbaAgentProxy @params" by receiving this cmdlet's own MyInvocation.BoundParameters and splatting
/// it, so the lookup sees exactly the bound Proxy/ExcludeProxy/SqlCredential supplied.
///
/// The end hop streams: it emits a result object per proxy as each Drop runs, before a later Drop may
/// throw under -EnableException, so buffering would hide proxies that were actually dropped. The process
/// hop is buffered - Get-DbaAgentProxy is read-only, the mutation is entirely in end.
///
/// This cmdlet supplies the real ShouldProcess runtime to the end hop (ConfirmImpact High, no -Force).
/// Surface pinned by migration/baselines/Remove-DbaAgentProxy.json.
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaAgentProxy", SupportsShouldProcess = true, DefaultParameterSetName = "Default", ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaAgentProxyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only remove these named proxies.</summary>
    [Parameter]
    public string[]? Proxy { get; set; }

    /// <summary>Remove all proxies except these named ones.</summary>
    [Parameter]
    public string[]? ExcludeProxy { get; set; }

    /// <summary>Agent proxy objects piped in from Get-DbaAgentProxy.</summary>
    [Parameter(ParameterSetName = "Pipeline", Mandatory = true, ValueFromPipeline = true)]
    public SmoProxyAccount[]? InputObject { get; set; }

    /// <summary>By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message. Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.</summary>
    // EnableException is inherited from DbaBaseCmdlet (virtual); the source declares it ONLY in the
    // Pipeline set, so it is overridden here with that single per-set [Parameter] attribute to match the
    // baseline exactly (the inherited bare declaration would reflect as __AllParameterSets and diverge).
    [Parameter(ParameterSetName = "Pipeline")]
    public override SwitchParameter EnableException { get; set; }

    // The pipeline-spanning accumulator: the source's begin "$dbProxies = @()", filled across process
    // records, drained in end.
    private List<PSObject> _dbProxies = null!;

    protected override void BeginProcessing()
    {
        _dbProxies = new List<PSObject>();
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

        // Match the source's assignment semantics: the SqlInstance branch does "$dbProxies = Get-..."
        // (REPLACE), the InputObject branch does "$dbProxies += $InputObject" (APPEND). When -SqlInstance
        // is combined with piped records the lookup runs per record and replaces each time, so appending
        // would accumulate duplicate proxies and Drop() them repeatedly.
        if (SqlInstance != null && SqlInstance.Length > 0)
        {
            _dbProxies = recordItems;
        }
        else
        {
            _dbProxies.AddRange(recordItems);
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
            _dbProxies.ToArray(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block. The source assigns/appends to $dbProxies; here it EMITS the proxies and the
    // C# accumulates them, because the accumulator must span the pipeline (which a per-record hop scope
    // cannot). The SqlInstance branch splats the caller's bound parameters (minus WhatIf/Confirm) to
    // Get-DbaAgentProxy exactly as the source's $PSBoundParameters re-splat did.
    private const string ProcessScript = """
param($SqlInstance, $InputObject, $__bound, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [Microsoft.SqlServer.Management.Smo.Agent.ProxyAccount[]]$InputObject, [hashtable]$__bound)

    if ($SqlInstance) {
        $params = $__bound
        $null = $params.Remove('WhatIf')
        $null = $params.Remove('Confirm')
        Get-DbaAgentProxy @params
    } else {
        $InputObject
    }
} $SqlInstance $InputObject $__bound @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess and
    // -FunctionName Remove-DbaAgentProxy on the direct Stop-Function. $dbProxies is the accumulated list
    // the C# collected. EnableException is bound so Stop-Function's scope-walking default inherits the
    // caller's value (a Drop failure under -EnableException must throw).
    private const string EndScript = """
param($dbProxies, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($dbProxies, $EnableException, $__realCmdlet)

    # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaAgentProxy.
    foreach ($dbProxy in $dbProxies) {
        if ($__realCmdlet.ShouldProcess($dbProxy.Parent.Parent.Name, "Removing the SQL Agent proxy $($dbProxy.Name) on $($dbProxy.Parent.Parent.Name)")) {
            $output = [PSCustomObject]@{
                ComputerName = $dbProxy.Parent.Parent.ComputerName
                InstanceName = $dbProxy.Parent.Parent.ServiceName
                SqlInstance  = $dbProxy.Parent.Parent.DomainInstanceName
                Name         = $dbProxy.Name
                Status       = $null
                IsRemoved    = $false
            }
            try {
                $dbProxy.Drop()
                $output.Status = "Dropped"
                $output.IsRemoved = $true
            } catch {
                Stop-Function -Message "Failed removing the SQL Agent proxy $($dbProxy.Name) on $($dbProxy.Parent.Parent.Name)" -ErrorRecord $_ -FunctionName Remove-DbaAgentProxy
                $output.Status = (Get-ErrorMessage -Record $_)
                $output.IsRemoved = $false
            }
            $output
        }
    }
} $dbProxies $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
