#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes instances from the user-maintained autocomplete list. Port of
/// public/Remove-DbaInstanceList.ps1 (W3-076). Full begin/process/end lifecycle: the
/// begin hop reads the current TabExpansion.KnownInstances config value and initializes
/// the $toRemove accumulator (the W3-063 begin-state shape); per-record process hops run
/// the verbatim trim/lower/dedup accumulation, threading state through the __w3076State
/// sentinel; the end hop runs the verbatim finalization ($PSCmdlet.ShouldProcess routed
/// to the REAL cmdlet, default ConfirmImpact Medium, Set-DbatoolsConfig +
/// TabExpansionHost cache rewrite + optional Register-DbatoolsConfig). RARE SURFACE
/// QUIRK: the source declares NO EnableException parameter - the virtual base property
/// is overridden WITHOUT a [Parameter] attribute, removing it from the parameter surface
/// (the binder reads the most-derived declaration's attributes; verified against the
/// baseline post-build) while StopFunction/WriteMessage virtual dispatch keeps reading
/// the always-false value. NO WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Remove-DbaInstanceList.json (SqlInstance string[] Mandatory pos0
/// ValueFromPipeline + ValueFromPipelineByPropertyName, Scope ConfigScope pos1 default
/// UserDefault, Register switch, NO EnableException).
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaInstanceList", SupportsShouldProcess = true)]
public sealed class RemoveDbaInstanceListCommand : DbaBaseCmdlet
{
    /// <summary>The instance name(s) to remove from the autocomplete list.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ValueFromPipelineByPropertyName = true, Position = 0)]
    [PsStringArrayCast]
    public string[] SqlInstance { get; set; } = null!;

    /// <summary>Persists the updated list to disk for future sessions.</summary>
    [Parameter]
    public SwitchParameter Register { get; set; }

    /// <summary>Where the persistent configuration is stored when registering.</summary>
    [Parameter(Position = 1)]
    public Dataplat.Dbatools.Configuration.ConfigScope Scope { get; set; } =
        Dataplat.Dbatools.Configuration.ConfigScope.UserDefault;

    /// <summary>NOT a parameter here: the source declares no EnableException, so the
    /// virtual base declaration is overridden with NO [Parameter] attribute to remove it
    /// from the surface (always false; StopFunction virtual dispatch still reads it).</summary>
    public override SwitchParameter EnableException { get; set; }

    // begin-scope $current and the cross-record $toRemove accumulator.
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3076State"))
            {
                _state = sentinel["__w3076State"] as Hashtable;
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

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, _state,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3076State"))
            {
                _state = sentinel["__w3076State"] as Hashtable;
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

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript,
            Register.ToBool(), Scope, _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // PS: the begin block VERBATIM; $current and the empty $toRemove return through the
    // sentinel for the process hops.
    private const string BeginScript = """
param($__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $current = @(Get-DbatoolsConfigValue -FullName "TabExpansion.KnownInstances" -Fallback @())
    $toRemove = @()
    @{ __w3076State = @{ current = $current; toRemove = $toRemove } }
} $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM per record; the accumulator threads through the
    // sentinel.
    private const string ProcessScript = """
param($SqlInstance, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string[]]$SqlInstance, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $current = $__state.current
    $toRemove = $__state.toRemove

    foreach ($instance in $SqlInstance) {
        $lower = $instance.Trim().ToLowerInvariant()
        if (-not $lower) { continue }
        if ($toRemove -notcontains $lower) {
            $toRemove += $lower
        }
    }

    @{ __w3076State = @{ current = $current; toRemove = $toRemove } }
} $SqlInstance $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM. Substitutions only: $PSCmdlet -> $__realCmdlet; the
    // nested Set-DbatoolsConfig / TabExpansionHost cache rewrite / Register-DbatoolsConfig
    // ride the hop.
    private const string EndScript = """
param($Register, $Scope, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param($Register, [Dataplat.Dbatools.Configuration.ConfigScope]$Scope, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $current = $__state.current
    $toRemove = $__state.toRemove

    if ($toRemove.Count -gt 0) {
        if ($__realCmdlet.ShouldProcess("instance list", "Remove $($toRemove -join ', ')")) {
            $updated = $current | Where-Object { $toRemove -notcontains $_ }
            if ($null -eq $updated) { $updated = @() }
            Set-DbatoolsConfig -FullName "TabExpansion.KnownInstances" -Value @($updated)

            $cache = @([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"])
            if ($cache.Count -gt 0) {
                $cache = $cache | Where-Object { $toRemove -notcontains $_ }
                [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] = @($cache)
            }

            if ($Register) {
                Register-DbatoolsConfig -FullName "TabExpansion.KnownInstances" -Scope $Scope
            }
        }
    }
} $Register $Scope $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
