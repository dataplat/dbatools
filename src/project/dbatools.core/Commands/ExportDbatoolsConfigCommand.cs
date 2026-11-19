#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports dbatools configuration items to json. Port of public/Export-DbatoolsConfig.ps1 with
/// its dependencies absorbed: the Get-DbatoolsConfig filters run directly over
/// ConfigurationHost, while Write-DbatoolsConfigFile keeps every provider and serializer touch
/// (Split-Path/Test-Path/New-Item/Get-Content/ConvertFrom-Json/ConvertTo-Json/Set-Content) on
/// the REAL engine cmdlets through NestedCommand, so per-edition json formatting, provider
/// wildcard semantics and binding errors match the function byte-for-byte. Surface pinned by
/// migration/baselines/Export-DbatoolsConfig.json (4 named sets, default FullName).
/// Ambient dry-run does NOT match, and this is the one place it cannot: see the note on
/// WriteConfigFile.
/// </summary>
[Cmdlet(VerbsData.Export, "DbatoolsConfig", DefaultParameterSetName = "FullName")]
public sealed class ExportDbatoolsConfigCommand : DbaBaseCmdlet
{
    /// <summary>The full name (module.name) of the setting(s) to export.</summary>
    [Parameter(ParameterSetName = "FullName", Mandatory = true)]
    [PsStringCast]
    public string? FullName { get; set; }

    /// <summary>The module whose settings are exported.</summary>
    [Parameter(ParameterSetName = "Module", Mandatory = true)]
    [PsStringCast]
    public string? Module { get; set; }

    /// <summary>The setting name filter within the module.</summary>
    [Parameter(ParameterSetName = "Module", Position = 1)]
    public string Name { get; set; } = "*";

    /// <summary>Configuration objects to export, piped from Get-DbatoolsConfig.</summary>
    [Parameter(ParameterSetName = "Config", Mandatory = true, ValueFromPipeline = true)]
    public Config[]? Config { get; set; }

    /// <summary>Exports the module cache for this module name.</summary>
    [Parameter(ParameterSetName = "ModuleName", Mandatory = true)]
    [PsStringCast]
    public string? ModuleName { get; set; }

    /// <summary>The module cache version.</summary>
    [Parameter(ParameterSetName = "ModuleName")]
    public int ModuleVersion { get; set; } = 1;

    /// <summary>The module cache scope(s) to write.</summary>
    [Parameter(ParameterSetName = "ModuleName")]
    public ConfigScope Scope { get; set; } = ConfigScope.FileUserShared;

    /// <summary>The json file to export to.</summary>
    [Parameter(Position = 1, Mandatory = true, ParameterSetName = "Config")]
    [Parameter(Position = 1, Mandatory = true, ParameterSetName = "FullName")]
    [Parameter(Position = 2, Mandatory = true, ParameterSetName = "Module")]
    [PsStringCast]
    public string? OutPath { get; set; }

    /// <summary>Skips settings that still carry their initial default value.</summary>
    [Parameter]
    public SwitchParameter SkipUnchanged { get; set; }

    private List<Config?> _items = null!;

    protected override void BeginProcessing()
    {
        // PS: Write-Message -Level InternalComment -Message "Bound parameters: ..." -Tag 'debug','start','param'
        WriteMessage(MessageLevel.InternalComment, $"Bound parameters: {string.Join(", ", MyInvocation.BoundParameters.Keys)}", tag: new[] { "debug", "start", "param" });

        _items = new List<Config?>();

        // PS: if (($Scope -band 15) -and ($ModuleName)) { stop }
        if (((int)Scope & 15) != 0 && PsOps.IsTrue(ModuleName))
        {
            StopFunction("Cannot export modulecache to registry! Please pick a file scope for your export destination",
                category: ErrorCategory.InvalidArgument,
                tag: new[] { "fail", "scope", "registry" });
            return;
        }
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
        {
            return;
        }

        if (!PsOps.IsTrue(ModuleName))
        {
            // PS: foreach ($item in $Config) { $items += $item } — a null Config iterates zero
            // times; explicit null ELEMENTS accumulate like the PS array append did.
            if (Config is not null)
            {
                foreach (Config? item in Config)
                {
                    _items.Add(item);
                }
            }
            // PS: if ($FullName) / if ($Module) REPLACE the accumulated list.
            if (PsOps.IsTrue(FullName))
            {
                _items = GetConfigsByFullName(FullName!, force: false);
            }
            if (PsOps.IsTrue(Module))
            {
                _items = GetConfigsByModule(Module!, Name, force: false);
            }
        }
    }

    protected override void EndProcessing()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
        {
            return;
        }

        if (!PsOps.IsTrue(ModuleName))
        {
            try
            {
                // PS: $items | Where-Object { -not $SkipUnchanged -or -not $_.Unchanged } —
                // a null element reads $null.Unchanged as $null, so -not keeps it.
                List<Config?> selected = new List<Config?>();
                foreach (Config? item in _items)
                {
                    if (!SkipUnchanged.ToBool() || !PsOps.IsTrue(item?.Unchanged))
                    {
                        selected.Add(item);
                    }
                }
                WriteConfigFile(selected, OutPath, replace: true);
            }
            catch (Exception ex)
            {
                // PS: Stop-Function -Message "Failed to export to file" -EnableException $EnableException -ErrorRecord $_
                StopFunction("Failed to export to file",
                    errorRecord: ToCaughtRecord(ex),
                    tag: new[] { "fail", "export" });
                return;
            }
        }
        else
        {
            int scopeValue = (int)Scope;
            if ((scopeValue & 16) != 0)
            {
                WriteModuleCache("path_FileUserLocal");
            }
            if ((scopeValue & 32) != 0)
            {
                WriteModuleCache("path_FileUserShared");
            }
            if ((scopeValue & 64) != 0)
            {
                WriteModuleCache("path_FileSystem");
            }
        }
    }

    /// <summary>
    /// PS: Write-DbatoolsConfigFile -Config (Get-DbatoolsConfig -Module $ModuleName -Force |
    /// Where ModuleExport | Where Unchanged -NE $true) -Path (Join-Path $script:path_X
    /// "name-version.json") — the config pipeline is re-evaluated fresh per scope branch and
    /// runs BEFORE the Join-Path (PS argument order); no -Replace, so existing files merge.
    /// </summary>
    private void WriteModuleCache(string pathVariable)
    {
        List<Config?> items = GetModuleCacheItems();
        // PS: "$($ModuleName.ToLowerInvariant())-$($ModuleVersion).json" — interpolation
        // renders the int through LanguagePrimitives = invariant culture (W1-006 lab fact).
        string fileName = ModuleName!.ToLowerInvariant() + "-" + ModuleVersion.ToString(CultureInfo.InvariantCulture) + ".json";
        Hashtable joinParams = new Hashtable();
        joinParams["Path"] = GetModulePathVariable(pathVariable);
        joinParams["ChildPath"] = fileName;
        // A null module path variable fails Join-Path's binder exactly like the PS statement;
        // the ModuleName branch has no try/catch, so it terminates the command the same way.
        Collection<PSObject> joined = NestedCommand.Invoke(this, "Join-Path", joinParams);
        string? target = (string?)LanguagePrimitives.ConvertTo(joined.Count > 0 ? (object?)joined[0] : null, typeof(string), CultureInfo.InvariantCulture);
        WriteConfigFile(items, target, replace: false);
    }

    private List<Config?> GetModuleCacheItems()
    {
        List<Config?> result = new List<Config?>();
        foreach (Config? config in GetConfigsByModule(ModuleName!, "*", force: true))
        {
            // PS: | Where-Object ModuleExport | Where-Object Unchanged -NE $true (the
            // dictionary never yields nulls).
            if (config!.ModuleExport && config.Unchanged != true)
            {
                result.Add(config);
            }
        }
        return result;
    }

    /// <summary>Absorbed Get-DbatoolsConfig FullName mode: "{Module}.{Name}" -like filter (no
    /// lowering, unlike Module mode) + Sort-Object Module, Name.</summary>
    private static List<Config?> GetConfigsByFullName(string fullName, bool force)
    {
        WildcardPattern pattern = WildcardPattern.Get(fullName, WildcardOptions.IgnoreCase);
        return ConfigurationHost.Configurations.Values
            .Where(c => pattern.IsMatch($"{c.Module}.{c.Name}") && (!c.Hidden || force))
            .OrderBy(c => c.Module, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(c => c.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList<Config?>();
    }

    /// <summary>Absorbed Get-DbatoolsConfig Module mode: lowered Name/Module -like filters +
    /// Sort-Object Module, Name.</summary>
    private static List<Config?> GetConfigsByModule(string module, string name, bool force)
    {
        WildcardPattern namePattern = WildcardPattern.Get(name.ToLowerInvariant(), WildcardOptions.IgnoreCase);
        WildcardPattern modulePattern = WildcardPattern.Get(module.ToLowerInvariant(), WildcardOptions.IgnoreCase);
        return ConfigurationHost.Configurations.Values
            .Where(c => namePattern.IsMatch(c.Name) && modulePattern.IsMatch(c.Module) && (!c.Hidden || force))
            .OrderBy(c => c.Module, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(c => c.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList<Config?>();
    }

    /// <summary>
    /// Absorbed private helper Write-DbatoolsConfigFile. Every provider/serializer statement
    /// runs on the real engine cmdlet through NestedCommand so the function's observable edges
    /// survive verbatim: the bare-filename Test-Path "" binding failure, New-Item's
    /// non-terminating drive errors, wildcard-char path semantics, per-edition
    /// Get-Content/Set-Content -Encoding UTF8 handling, per-edition ConvertTo-Json formatting
    /// and depth warnings, and the empty-pipe empty-file write.
    /// Only the property-bag construction is native: edition-comparer hashtables reproduce the
    /// [pscustomobject]$datum bucket order (the bag-parity convention).
    ///
    /// One edge does NOT survive, and running the statements on the real cmdlets is what causes
    /// it. This command has no ShouldProcess of its own, so nothing here was ever gated except
    /// by whatever dry-run state the nested New-Item/Set-Content resolved for themselves. In the
    /// function world they resolved it through the MODULE's scope chain, where a caller-local or
    /// wrapper-inherited $WhatIfPreference does not exist - so an ambient dry run wrote the file
    /// for real. NestedCommand runs them in the CALLER's scope instead, so they see it and
    /// suppress. Measured both editions, both worlds, 2026-07-24: control writes, ambient and
    /// wrapper write in the function world and do not here. Deviating toward doing nothing under
    /// a dry run, on a command whose entire purpose is to write that one file, is the safe side
    /// of this divergence; forcing parity would mean defeating a dry run the user asked for.
    /// </summary>
    private void WriteConfigFile(List<Config?> configs, string? path, bool replace)
    {
        // PS: $parent = Split-Path -Path $Path (a Split-Path failure leaves $parent null and
        // surfaces its own non-terminating error, both reproduced by the real cmdlet).
        Hashtable splitParams = new Hashtable();
        splitParams["Path"] = path;
        Collection<PSObject> parentResult = NestedCommand.Invoke(this, "Split-Path", splitParams);
        object? parent = parentResult.Count > 0 ? (object?)parentResult[0] : null;

        // PS: if (-not (Test-Path $parent)) { $null = New-Item $parent -ItemType Directory -Force }
        Hashtable testParentParams = new Hashtable();
        testParentParams["Path"] = parent;
        if (!IsTruthy(NestedCommand.Invoke(this, "Test-Path", testParentParams)))
        {
            Hashtable newItemParams = new Hashtable();
            newItemParams["Path"] = parent;
            newItemParams["ItemType"] = "Directory";
            newItemParams["Force"] = true;
            NestedCommand.Invoke(this, "New-Item", newItemParams);
        }

        // PS: $data = @{ } — the edition-appropriate case-insensitive comparer.
        Hashtable data = NewBag();

        // PS: if ((Test-Path $Path) -and (-not $Replace)) — Test-Path always evaluates first.
        Hashtable testPathParams = new Hashtable();
        testPathParams["Path"] = path;
        bool targetExists = IsTruthy(NestedCommand.Invoke(this, "Test-Path", testPathParams));
        if (targetExists && !replace)
        {
            // PS: foreach ($item in (Get-Content -Path $Path -Encoding UTF8 | ConvertFrom-Json))
            Hashtable getParams = new Hashtable();
            getParams["Path"] = path;
            getParams["Encoding"] = "UTF8";
            Collection<PSObject> lines = NestedCommand.Invoke(this, "Get-Content", getParams);
            Collection<PSObject> parsed = NestedCommand.Invoke(this, "ConvertFrom-Json", new Hashtable(), lines);
            // foreach over a SCALAR null iterates zero times; a 5.1 single array emission
            // enumerates its elements (nulls included, which then fail the null index below).
            if (parsed.Count != 1 || parsed[0] is not null)
            {
                foreach (PSObject? wrapper in parsed)
                {
                    if (wrapper?.BaseObject is object[] inner)
                    {
                        foreach (object? element in inner)
                        {
                            AddExisting(data, element);
                        }
                    }
                    else
                    {
                        AddExisting(data, wrapper);
                    }
                }
            }
        }

        foreach (Config? item in configs)
        {
            // PS: $datum = @{ Version = 1; FullName = $item.FullName } (+ export shape), then
            // [pscustomobject]$datum — a runtime-hashtable cast emits properties in BUCKET
            // order, which the PSObject below reproduces by enumerating the same hashtable.
            // Null elements read their members as $null (non-strict PS member access).
            Hashtable datum = NewBag();
            datum["Version"] = 1;
            datum["FullName"] = item?.FullName;
            if (PsOps.IsTrue(item?.SimpleExport))
            {
                datum["Data"] = item!.Value;
            }
            else
            {
                ConfigurationValue persisted = ConfigurationHost.ConvertToPersistedValue(item?.Value!);
                datum["Value"] = persisted.PersistedValue;
                datum["Type"] = persisted.PersistedType;
                datum["Style"] = "default";
            }

            PSObject bag = new PSObject();
            foreach (DictionaryEntry entry in datum)
            {
                bag.Properties.Add(new PSNoteProperty((string)entry.Key, entry.Value));
            }

            // PS: $data[$item.FullName] = [pscustomobject]$datum — a null index throws after
            // the bag is built.
            if (item?.FullName is null)
            {
                throw new RuntimeException("Index operation failed; the array index evaluated to null.");
            }
            data[item.FullName] = bag;
        }

        // PS: $data.Values | ConvertTo-Json | Set-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
        // — an empty value set stays a native empty pipe (ConvertTo-Json emits nothing,
        // Set-Content still runs), exactly like the function's pipeline.
        List<object?> values = new List<object?>();
        foreach (object? value in data.Values)
        {
            values.Add(value);
        }
        Collection<PSObject> json = NestedCommand.Invoke(this, "ConvertTo-Json", new Hashtable(), values);
        Hashtable setParams = new Hashtable();
        setParams["Path"] = path;
        setParams["Encoding"] = "UTF8";
        setParams["ErrorAction"] = "Stop";
        NestedCommand.Invoke(this, "Set-Content", setParams, json);
    }

    /// <summary>
    /// PS: $data[$item.FullName] = $item over the parsed existing file — the indexer unwraps a
    /// PSObject key to its base object, and a missing/null FullName throws the PS null-index
    /// error (caught by the OutPath branch as "Failed to export to file").
    /// </summary>
    private static void AddExisting(Hashtable data, object? element)
    {
        object? key = PsProperty.Get(element, "FullName");
        if (key is null)
        {
            throw new RuntimeException("Index operation failed; the array index evaluated to null.");
        }
        data[key] = element;
    }

    /// <summary>
    /// PS: $script:path_FileUserLocal / path_FileUserShared / path_FileSystem — computed by
    /// private/configurations/configuration.ps1 at import into the dbatools SCRIPT module's
    /// script scope; satellite cmdlets run in the caller's session state, so read the live
    /// variable off the module's own SessionState (no module-scope scriptblock injection).
    /// </summary>
    private object? GetModulePathVariable(string variableName)
    {
        Hashtable getModuleParams = new Hashtable();
        getModuleParams["Name"] = "dbatools";
        foreach (PSObject wrapped in NestedCommand.Invoke(this, "Get-Module", getModuleParams))
        {
            if (wrapped?.BaseObject is PSModuleInfo module && module.ModuleType == ModuleType.Script)
            {
                return module.SessionState.PSVariable.GetValue("script:" + variableName);
            }
        }
        return null;
    }

    /// <summary>PS truthiness over a nested pipeline's result (single bool for Test-Path).</summary>
    private static bool IsTruthy(Collection<PSObject> result)
    {
        return LanguagePrimitives.IsTrue(result.Count == 1 ? result[0] : (object)result);
    }

    /// <summary>
    /// PS: catch { $_ } — a nested terminating error carries the original failing record
    /// (RuntimeException.ErrorRecord); anything else wraps like the landed W1 ports.
    /// </summary>
    private static ErrorRecord ToCaughtRecord(Exception ex)
    {
        if (ex is RuntimeException runtime && runtime.ErrorRecord is not null)
        {
            return runtime.ErrorRecord;
        }
        return new ErrorRecord(ex, "Export-DbatoolsConfig", ErrorCategory.NotSpecified, null);
    }

    // @{}'s key comparer is EDITION-DEPENDENT (empirically verified, W5-030): net472/WinPS 5.1
    // = a CultureAware comparer bound to the CURRENT culture at creation, net8.0/PS7 =
    // OrdinalIgnoreCase. Built per call, never cached (Turkish/Azeri I/i).
    private static IEqualityComparer NewComparer() =>
#if NET8_0_OR_GREATER
        StringComparer.OrdinalIgnoreCase;
#else
        StringComparer.CurrentCultureIgnoreCase;
#endif

    private static Hashtable NewBag() => new Hashtable(NewComparer());
}
