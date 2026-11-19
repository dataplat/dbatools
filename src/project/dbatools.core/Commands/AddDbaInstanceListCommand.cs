#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Configuration;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Adds SQL Server instances to the user-maintained autocomplete list. Port of
/// public/Add-DbaInstanceList.ps1 (W3-001). The begin/process/end bodies ride verbatim
/// module-scoped hops sharing one Hashtable state bag by reference (the W1-106 lifecycle
/// pattern), so the nested compiled Get-DbatoolsConfigValue / Set-DbatoolsConfig /
/// Register-DbatoolsConfig dispatch, -notcontains coercion, += array growth (including the
/// stale-$lower statement-fault path for null elements), TEPP cache mutation, and
/// @($current) + @($toAdd) array-addition semantics are all decided by the engine exactly
/// as the function decided them. EnableException is deliberately hidden because the source
/// declares no such parameter. Surface pinned by migration/baselines/Add-DbaInstanceList.json
/// (SqlInstance mandatory pos0 VFP+VFPBPN; Scope pos1 default UserDefault; Register switch).
/// </summary>
[Cmdlet(VerbsCommon.Add, "DbaInstanceList")]
public sealed class AddDbaInstanceListCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance name or names to add to the autocomplete list.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true, ValueFromPipelineByPropertyName = true)]
    [PsStringArrayCast]
    public string[]? SqlInstance { get; set; }

    /// <summary>Persists the instance list to disk for future PowerShell sessions.</summary>
    [Parameter]
    public SwitchParameter Register { get; set; }

    /// <summary>Where the persistent configuration is stored when using -Register.</summary>
    [Parameter(Position = 1)]
    public ConfigScope Scope { get; set; } = ConfigScope.UserDefault;

    /// <summary>Not a parameter: the source does not expose EnableException, so this
    /// attribute-less override keeps the inherited helper off the command surface.</summary>
    public override SwitchParameter EnableException { get; set; }

    // begin/process/end share $current and $toAdd through this bag BY REFERENCE, exactly
    // like the function's shared function-scope locals (W1-106 lifecycle pattern).
    private readonly Hashtable _lifecycleState = new Hashtable();

    protected override void BeginProcessing()
    {
        foreach (PSObject item in NestedCommand.InvokeScoped(this, BeginScript, _lifecycleState))
            WriteObject(item);
    }

    protected override void ProcessRecord()
    {
        if (Interrupted) { return; }
        foreach (PSObject item in NestedCommand.InvokeScoped(this, ProcessScript, _lifecycleState, SqlInstance))
            WriteObject(item);
    }

    protected override void EndProcessing()
    {
        if (Interrupted) { return; }
        foreach (PSObject item in NestedCommand.InvokeScoped(this, EndScript, _lifecycleState, Register.ToBool(), Scope))
            WriteObject(item);
    }

    private const string BeginScript = """
param($__state)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__state)
    $current = Get-DbatoolsConfigValue -FullName "TabExpansion.KnownInstances" -Fallback @()
    $toAdd = @()
    $__state["current"] = $current
    $__state["toAdd"] = $toAdd
} $__state 3>&1
""";

    private const string ProcessScript = """
param($__state, $SqlInstance)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__state, $SqlInstance)
    $current = $__state["current"]
    $toAdd = $__state["toAdd"]
    foreach ($instance in $SqlInstance) {
        $lower = $instance.Trim().ToLowerInvariant()
        if (-not $lower) { continue }

        if ($current -notcontains $lower -and $toAdd -notcontains $lower) {
            $toAdd += $lower
        }

        # Update the TEPP cache immediately for this session
        if ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] -notcontains $lower) {
            [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Cache["sqlinstance"] += $lower
        }
    }
    $__state["toAdd"] = $toAdd
} $__state $SqlInstance 3>&1
""";

    private const string EndScript = """
param($__state, $Register, $Scope)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__state, $Register, $Scope)
    $current = $__state["current"]
    $toAdd = $__state["toAdd"]
    if ($toAdd.Count -gt 0) {
        $combined = @($current) + @($toAdd)
        Set-DbatoolsConfig -FullName "TabExpansion.KnownInstances" -Value $combined
    }
    if ($Register) {
        Register-DbatoolsConfig -FullName "TabExpansion.KnownInstances" -Scope $Scope
    }
} $__state $Register $Scope 3>&1
""";
}
