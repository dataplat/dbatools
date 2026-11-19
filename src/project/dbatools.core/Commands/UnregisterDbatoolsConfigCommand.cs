#nullable enable

using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes persisted configuration entries from the registry scopes and psf_config.json
/// files. Port of public/Unregister-DbatoolsConfig.ps1 (W1-041), the mirror of W1-032
/// Register. The begin-block store collection, the three per-record removal regions, and
/// the end-block file flush run as VERBATIM module-scoped PS (the store paths, provider
/// semantics - including the 5.1-throws / 7+-false Test-Path-null edition split under the
/// blanked-variable harness - and the Where-Object filters all come from the engine). The
/// collected $registryProperties/$pathProperties arrays live as cmdlet state between hops;
/// the file-config elements are the SAME PSObjects across hops, so the process-region
/// mutations ($fileConfig.Properties reassignment, Changed flag) persist into the end
/// flush exactly like function scope. Bind-time coercions follow the W1-032/W1-035 class:
/// null [string]/[string[]] values coerce to "" BEFORE validation via the Ps*Cast
/// transforms. No positional bindings (explicit parameter sets suppress the implicit
/// numbering); DefaultParameterSetName Pipeline.
/// Surface pinned by migration/baselines/Unregister-DbatoolsConfig.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Unregister, "DbatoolsConfig", DefaultParameterSetName = "Pipeline")]
public sealed class UnregisterDbatoolsConfigCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared. The function has
    // no such parameter; its single Stop-Function site reads the ambient (unbound) value.

    [Parameter(ValueFromPipeline = true, ParameterSetName = "Pipeline")]
    public Config[]? ConfigurationItem { get; set; }

    [Parameter(ValueFromPipeline = true, ParameterSetName = "Pipeline")]
    [PsStringArrayCast]
    public string[]? FullName { get; set; }

    [Parameter(Mandatory = true, ParameterSetName = "Module")]
    [PsStringCast]
    public string? Module { get; set; }

    [Parameter(ParameterSetName = "Module")]
    [PsStringCast]
    public string? Name { get; set; } = "*";

    [Parameter]
    public ConfigScope Scope { get; set; } = ConfigScope.UserDefault;

    private PSObject? _registryProperties;
    private PSObject? _pathProperties;

    protected override void BeginProcessing()
    {
        // PS: if (($PSVersionTable.PSVersion.Major -ge 6) -and ($PSVersionTable.OS -notlike "*Windows*") -and ($Scope -band 15))
        object? versionTable = SessionState.PSVariable.GetValue("PSVersionTable");
        object? psVersion = GetTableEntry(versionTable, "PSVersion");
        int major = (int)LanguagePrimitives.ConvertTo(PsProperty.Get(psVersion, "Major") ?? 0, typeof(int), System.Globalization.CultureInfo.InvariantCulture);
        string osText = GetTableEntry(versionTable, "OS") is { } os ? PSObject.AsPSObject(os).ToString() : "";
        bool notWindows = !new WildcardPattern("*Windows*", WildcardOptions.IgnoreCase).IsMatch(osText);
        if (major >= 6 && notWindows && (((int)Scope) & 15) != 0)
        {
            StopFunction("Cannot unregister configurations from registry on non-windows machines.", category: ErrorCategory.ResourceUnavailable, tag: new[] { "NotSupported" });
            return;
        }

        // The verbatim begin-block collection; the returned bag carries the two arrays.
        foreach (PSObject item in NestedCommand.InvokeScoped(this, BeginCollectScript, (int)Scope))
        {
            _registryProperties = PsProperty.Get(item, "registryProperties") is { } reg ? PSObject.AsPSObject(reg) : null;
            _pathProperties = PsProperty.Get(item, "pathProperties") is { } path ? PSObject.AsPSObject(path) : null;
        }
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        // PS: if (-not ($pathProperties -or $registryProperties)) { return } - collection
        // truthiness through the engine's IsTrue.
        bool hasPath = _pathProperties is not null && LanguagePrimitives.IsTrue(_pathProperties.BaseObject);
        bool hasRegistry = _registryProperties is not null && LanguagePrimitives.IsTrue(_registryProperties.BaseObject);
        if (!hasPath && !hasRegistry)
            return;

        List<object?> arguments = new List<object?>
        {
            _registryProperties,
            _pathProperties,
            ConfigurationItem,
            FullName,
            Module,
            Name,
        };
        foreach (PSObject item in NestedCommand.InvokeScoped(this, ProcessRegionsScript, arguments.ToArray()))
            WriteObject(item);
    }

    protected override void EndProcessing()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        foreach (PSObject item in NestedCommand.InvokeScoped(this, EndFlushScript, _pathProperties))
            WriteObject(item);
    }

    /// <summary>Hashtable key access the way the PS dot operator reads $PSVersionTable.</summary>
    private static object? GetTableEntry(object? table, string key)
    {
        if (PsAssignment.Unwrap(table) is System.Collections.IDictionary dictionary)
            return dictionary[key];
        return PsProperty.Get(table, key);
    }

    private const string BeginCollectScript = """
param($__scope)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__scope)
    $Scope = [Dataplat.Dbatools.Configuration.ConfigScope]$__scope

    #region Initialize Collection
    $registryProperties = @()
    if ($Scope -band 1) {
        if (Test-Path $script:path_RegistryUserDefault) { $registryProperties += Get-ItemProperty -Path $script:path_RegistryUserDefault }
    }
    if ($Scope -band 2) {
        if (Test-Path $script:path_RegistryUserEnforced) { $registryProperties += Get-ItemProperty -Path $script:path_RegistryUserEnforced }
    }
    if ($Scope -band 4) {
        if (Test-Path $script:path_RegistryMachineDefault) { $registryProperties += Get-ItemProperty -Path $script:path_RegistryMachineDefault }
    }
    if ($Scope -band 8) {
        if (Test-Path $script:path_RegistryMachineEnforced) { $registryProperties += Get-ItemProperty -Path $script:path_RegistryMachineEnforced }
    }
    $pathProperties = @()
    if ($Scope -band 16) {
        $fileUserLocalSettings = @()
        if (Test-Path (Join-Path $script:path_FileUserLocal "psf_config.json")) { $fileUserLocalSettings = Get-Content (Join-Path $script:path_FileUserLocal "psf_config.json") -Encoding UTF8 | ConvertFrom-Json }
        if ($fileUserLocalSettings) {
            $pathProperties += [PSCustomObject]@{
                Path       = (Join-Path $script:path_FileUserLocal "psf_config.json")
                Properties = $fileUserLocalSettings
                Changed    = $false
            }
        }
    }
    if ($Scope -band 32) {
        $fileUserSharedSettings = @()
        if (Test-Path (Join-Path $script:path_FileUserShared "psf_config.json")) { $fileUserSharedSettings = Get-Content (Join-Path $script:path_FileUserShared "psf_config.json") -Encoding UTF8 | ConvertFrom-Json }
        if ($fileUserSharedSettings) {
            $pathProperties += [PSCustomObject]@{
                Path       = (Join-Path $script:path_FileUserShared "psf_config.json")
                Properties = $fileUserSharedSettings
                Changed    = $false
            }
        }
    }
    if ($Scope -band 64) {
        $fileSystemSettings = @()
        if (Test-Path (Join-Path $script:path_FileSystem "psf_config.json")) { $fileSystemSettings = Get-Content (Join-Path $script:path_FileSystem "psf_config.json") -Encoding UTF8 | ConvertFrom-Json }
        if ($fileSystemSettings) {
            $pathProperties += [PSCustomObject]@{
                Path       = (Join-Path $script:path_FileSystem "psf_config.json")
                Properties = $fileSystemSettings
                Changed    = $false
            }
        }
    }
    #endregion Initialize Collection

    [PSCustomObject]@{
        registryProperties = $registryProperties
        pathProperties     = $pathProperties
    }
} $__scope
""";

    private const string ProcessRegionsScript = """
param($__registryProperties, $__pathProperties, $__configurationItem, $__fullName, $__module, $__name)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__registryProperties, $__pathProperties, $__configurationItem, $__fullName, $__module, $__name)
    $registryProperties = $__registryProperties
    $pathProperties = $__pathProperties
    $ConfigurationItem = $__configurationItem
    $FullName = $__fullName
    $Module = $__module
    $Name = $__name
    $common = 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider'

    foreach ($item in $ConfigurationItem) {
        # Registry
        foreach ($hive in ($registryProperties | Where-Object { $_.PSObject.Properties.Name -eq $item.FullName })) {
            Remove-ItemProperty -Path $hive.PSPath -Name $item.FullName
        }
        # Prepare file
        foreach ($fileConfig in ($pathProperties | Where-Object { $_.Properties.FullName -contains $item.FullName })) {
            $fileConfig.Properties = $fileConfig.Properties | Where-Object FullName -NE $item.FullName
            $fileConfig.Changed = $true
        }
    }

    foreach ($item in $FullName) {
        # Ignore string-casted configurations
        if ($item -ceq "Dataplat.Dbatools.Configuration.Config") { continue }

        # Registry
        foreach ($hive in ($registryProperties | Where-Object { $_.PSObject.Properties.Name -eq $item })) {
            Remove-ItemProperty -Path $hive.PSPath -Name $item
        }
        # Prepare file
        foreach ($fileConfig in ($pathProperties | Where-Object { $_.Properties.FullName -contains $item })) {
            $fileConfig.Properties = $fileConfig.Properties | Where-Object FullName -NE $item
            $fileConfig.Changed = $true
        }
    }

    if ($Module) {
        $compoundName = "{0}.{1}" -f $Module, $Name

        # Registry
        foreach ($hive in ($registryProperties | Where-Object { $_.PSObject.Properties.Name -like $compoundName })) {
            foreach ($propName in $hive.PSObject.Properties.Name) {
                if ($propName -in $common) { continue }

                if ($propName -like $compoundName) {
                    Remove-ItemProperty -Path $hive.PSPath -Name $propName
                }
            }
        }
        # Prepare file
        foreach ($fileConfig in ($pathProperties | Where-Object { $_.Properties.FullName -like $compoundName })) {
            $fileConfig.Properties = $fileConfig.Properties | Where-Object FullName -NotLike $compoundName
            $fileConfig.Changed = $true
        }
    }
} $__registryProperties $__pathProperties $__configurationItem $__fullName $__module $__name 3>&1
""";

    private const string EndFlushScript = """
param($__pathProperties)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__pathProperties)
    $pathProperties = $__pathProperties
    foreach ($fileConfig in $pathProperties) {
        if (-not $fileConfig.Changed) { continue }

        if ($fileConfig.Properties) {
            $fileConfig.Properties | ConvertTo-Json | Set-Content -Path $fileConfig.Path -Encoding UTF8
        } else {
            Remove-Item $fileConfig.Path
        }
    }
} $__pathProperties 3>&1
""";
}
