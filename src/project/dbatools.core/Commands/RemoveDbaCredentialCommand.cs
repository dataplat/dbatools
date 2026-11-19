#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes SQL credentials. Port of public/Remove-DbaCredential.ps1 (W3-072). The source
/// accumulates targets across process records and DROPS IN THE END BLOCK (its own comment:
/// avoids "Collection was modified" when piped from Get-DbaCredential), so the port carries
/// the $dbCredentials accumulator through the __w3072State sentinel from per-record process
/// hops into one end hop. The process body's $PSBoundParameters splat-through to
/// Get-DbaCredential rides as a per-record Hashtable clone of this cmdlet's OWN bound
/// parameters (identical keys/values for identical invocations; the verbatim
/// Remove('WhatIf')/Remove('Confirm') happens inside the hop - the source mutates the live
/// dictionary, the clone re-supplies the keys each record and removes them again before the
/// only use, behaviorally identical). The end hop wraps the drop loop with the
/// $__realCmdlet.ShouldProcess gate (ConfirmImpact HIGH mirrored); its catch path calls
/// Stop-Function WITHOUT -Continue and STILL falls through to emit the failure status
/// object in non-EE mode - source-verbatim - and the private Get-ErrorMessage rides the
/// hop. PARAMETER SETS mirrored from the baseline: Default (default set) + Pipeline
/// {InputObject Mandatory VFP, EnableException} - EnableException is PIPELINE-SET-ONLY in
/// the source (its quirk: -SqlInstance ... -EnableException resolves to Pipeline and then
/// demands InputObject), reproduced by OVERRIDING the virtual base property with the
/// per-set attribute (the binder reads the most-derived declaration). NO positions (the
/// source's set surface has none). NO WarningAction carrier (codex W3-005 r3). Surface
/// pinned by migration/baselines/Remove-DbaCredential.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaCredential", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "Default")]
public sealed class RemoveDbaCredentialCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Credential names to remove (wildcards supported).</summary>
    [Parameter]
    public string[]? Credential { get; set; }

    /// <summary>Credential names to exclude from removal (wildcards supported).</summary>
    [Parameter]
    public string[]? ExcludeCredential { get; set; }

    /// <summary>Filter credentials by associated identity.</summary>
    [Parameter]
    public string[]? Identity { get; set; }

    /// <summary>Identities to exclude from removal.</summary>
    [Parameter]
    public string[]? ExcludeIdentity { get; set; }

    /// <summary>SMO Credential object(s) from Get-DbaCredential.</summary>
    [Parameter(ParameterSetName = "Pipeline", Mandatory = true, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.Credential[]? InputObject { get; set; }

    /// <summary>Replaces friendly warnings with terminating exceptions. PIPELINE-SET-ONLY
    /// in the source (the virtual base declaration is overridden to carry the per-set
    /// attribute; StopFunction reads the bound value via virtual dispatch).</summary>
    [Parameter(ParameterSetName = "Pipeline")]
    public override SwitchParameter EnableException { get; set; }

    // The cross-block $dbCredentials accumulator (begin inits, process appends, end drops).
    private Hashtable? _state;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, InputObject, new Hashtable(MyInvocation.BoundParameters),
            EnableException.ToBool(), _state,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3072State"))
            {
                _state = sentinel["__w3072State"] as Hashtable;
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

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
            EnableException.ToBool(), _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM per record. Substitutions only: $PSBoundParameters ->
    // the carried $__boundParameters clone (the verbatim Remove lines then run against it).
    // $dbCredentials restores from the sentinel ($null first record = the begin block's
    // @( ) init, which had no other effect) and returns through it.
    private const string ProcessScript = """
param($SqlInstance, $InputObject, $__boundParameters, $EnableException, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [Microsoft.SqlServer.Management.Smo.Credential[]]$InputObject, $__boundParameters, $EnableException, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin-block init on the first record; later records restore the accumulator
    if ($null -eq $__state) {
        $dbCredentials = @( )
    } else {
        $dbCredentials = $__state.dbCredentials
    }

    if ($SqlInstance) {
        $params = $__boundParameters
        $null = $params.Remove('WhatIf')
        $null = $params.Remove('Confirm')
        $dbCredentials = Get-DbaCredential @params
    } else {
        $dbCredentials += $InputObject
    }

    @{ __w3072State = @{ dbCredentials = $dbCredentials } }
} $SqlInstance $InputObject $__boundParameters $EnableException $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM. Substitutions only: $PSCmdlet -> $__realCmdlet and
    // explicit -FunctionName Remove-DbaCredential on Stop-Function (W1-090). The comment
    // and the fall-through after the no-Continue Stop-Function are the source's own.
    private const string EndScript = """
param($EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $dbCredentials = if ($null -eq $__state) { @( ) } else { $__state.dbCredentials }

    # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaCredential.
    foreach ($dbCredential in $dbCredentials) {
        if ($__realCmdlet.ShouldProcess($dbCredential.Parent.Name, "Removing the SQL credential $($dbCredential.Name) on $($dbCredential.Parent.Name)")) {
            $output = [PSCustomObject]@{
                ComputerName = $dbCredential.ComputerName
                InstanceName = $dbCredential.InstanceName
                SqlInstance  = $dbCredential.SqlInstance
                Name         = $dbCredential.Name
                Status       = $null
                IsRemoved    = $false
            }
            try {
                $dbCredential.Drop()
                $output.Status = "Dropped"
                $output.IsRemoved = $true
            } catch {
                Stop-Function -Message "Failed removing the SQL credential $($dbCredential.Name) on $($dbCredential.Parent.Name)" -ErrorRecord $_ -FunctionName Remove-DbaCredential
                $output.Status = (Get-ErrorMessage -Record $_)
                $output.IsRemoved = $false
            }
            $output
        }
    }
} $EnableException $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
