#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoMailProfile = Microsoft.SqlServer.Management.Smo.Mail.MailProfile;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes database mail profiles.
/// </summary>
/// <remarks>
/// The profile lookup (Get-DbaDbMailProfile), the confirmation gate, the Drop, and the result-object
/// shaping all run the original dbatools PowerShell body inside the dbatools module scope rather than
/// being reimplemented in C#, so the engine decides the observable details.
///
/// The function collects every profile across the whole pipeline in its begin/process blocks and only
/// drops them in end, to avoid "Collection was modified" when piped directly from Get-DbaDbMailProfile.
/// The accumulator ($dbMailProfiles) is pipeline-spanning state a per-record hop scope cannot hold, so it
/// lives in C#: begin seeds an empty list, each process record contributes its profiles (a
/// Get-DbaDbMailProfile lookup in the SqlInstance parameter set, or the bound InputObject in the pipeline
/// set), and the end hop receives the full list to drop.
///
/// The SqlInstance path reproduces the source's "$params = $PSBoundParameters; remove WhatIf/Confirm;
/// Get-DbaDbMailProfile @params" by receiving this cmdlet's own MyInvocation.BoundParameters and splatting
/// it, so the lookup sees exactly the bound Profile/ExcludeProfile/SqlCredential/EnableException supplied.
/// The two parameter sets are mutually exclusive (SqlInstance is not pipeline-bound), so the SqlInstance
/// lookup runs at most once - appending its single result equals the source's assignment.
///
/// The end hop streams: it emits a result object per profile as each Drop runs, before a later Drop may
/// throw under -EnableException, so buffering would hide profiles that were actually dropped. The process
/// hop is buffered - Get-DbaDbMailProfile is read-only, the mutation is entirely in end.
///
/// This cmdlet supplies the real ShouldProcess runtime to the end hop (ConfirmImpact High, no -Force).
/// Surface pinned by migration/baselines/Remove-DbaDbMailProfile.json.
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaDbMailProfile", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaDbMailProfileCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ParameterSetName = "NonPipeline", Mandatory = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only remove these named database mail profiles.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    public string[]? Profile { get; set; }

    /// <summary>Remove all database mail profiles except these named ones.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    public string[]? ExcludeProfile { get; set; }

    /// <summary>Database mail profile objects piped in from Get-DbaDbMailProfile.</summary>
    [Parameter(ParameterSetName = "Pipeline", Mandatory = true, ValueFromPipeline = true)]
    public SmoMailProfile[]? InputObject { get; set; }

    /// <summary>By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message. Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.</summary>
    // EnableException is inherited from DbaBaseCmdlet (virtual); the source declares it in BOTH named
    // sets explicitly, so it is overridden here with the per-set [Parameter] attributes to match that
    // surface exactly (the inherited bare declaration would reflect as __AllParameterSets and diverge).
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public override SwitchParameter EnableException { get; set; }

    // The pipeline-spanning accumulator: the source's begin "$dbMailProfiles = @()", filled across process
    // records, drained in end.
    private List<PSObject> _dbMailProfiles = null!;

    protected override void BeginProcessing()
    {
        _dbMailProfiles = new List<PSObject>();
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Reproduce "$params = $PSBoundParameters" faithfully: this cmdlet's own bound parameters.
        Hashtable bound = new Hashtable(MyInvocation.BoundParameters);

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
                _dbMailProfiles.Add(item);
            }
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
            _dbMailProfiles.ToArray(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block. The source assigns/appends to $dbMailProfiles; here it EMITS the profiles and
    // the C# accumulates them, because the accumulator must span the pipeline. The SqlInstance branch
    // splats the caller's bound parameters (minus WhatIf/Confirm) to Get-DbaDbMailProfile exactly as the
    // source's $PSBoundParameters re-splat did.
    private const string ProcessScript = """
param($SqlInstance, $InputObject, $__bound, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [Microsoft.SqlServer.Management.Smo.Mail.MailProfile[]]$InputObject, [hashtable]$__bound)

    if ($SqlInstance) {
        $params = $__bound
        $null = $params.Remove('WhatIf')
        $null = $params.Remove('Confirm')
        Get-DbaDbMailProfile @params
    } else {
        $InputObject
    }
} $SqlInstance $InputObject $__bound @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess and
    // -FunctionName Remove-DbaDbMailProfile on the direct Stop-Function. $dbMailProfiles is the accumulated
    // list. EnableException is bound so Stop-Function's scope-walking default inherits the caller's value.
    private const string EndScript = """
param($dbMailProfiles, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($dbMailProfiles, $EnableException, $__realCmdlet)

    # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbMailProfile.
    foreach ($dbMailProfile in $dbMailProfiles) {
        if ($__realCmdlet.ShouldProcess($dbMailProfile.Parent.Parent.Name, "Removing the database mail profile $($dbMailProfile.Name) on $($dbMailProfile.Parent.Parent.Name)")) {
            $output = [PSCustomObject]@{
                ComputerName = $dbMailProfile.Parent.Parent.ComputerName
                InstanceName = $dbMailProfile.Parent.Parent.ServiceName
                SqlInstance  = $dbMailProfile.Parent.Parent.DomainInstanceName
                Name         = $dbMailProfile.Name
                Status       = $null
                IsRemoved    = $false
            }
            try {
                $dbMailProfile.Drop()
                $output.Status = "Dropped"
                $output.IsRemoved = $true
            } catch {
                Stop-Function -Message "Failed removing the database mail profile $($dbMailProfile.Name) on $($dbMailProfile.Parent.Parent.Name)" -ErrorRecord $_ -FunctionName Remove-DbaDbMailProfile
                $output.Status = (Get-ErrorMessage -Record $_)
                $output.IsRemoved = $false
            }
            $output
        }
    }
} $dbMailProfiles $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
