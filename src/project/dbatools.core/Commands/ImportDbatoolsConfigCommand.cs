#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Imports dbatools configuration settings from JSON files, web links, raw JSON strings or
/// the persisted module-configuration locations. Port of public/Import-DbatoolsConfig.ps1
/// with the private helpers Read-DbatoolsConfigFile and Read-DbatoolsConfigPersisted (and
/// their inner New-ConfigItem/Get-WebContent/Read-Registry helpers) absorbed; Resolve-DbaPath
/// and Set-DbatoolsConfig ride the REAL commands via NestedCommand so their warnings bubble
/// and the kill-switch keeps working. Surface pinned by
/// migration/baselines/Import-DbatoolsConfig.json (two named sets, no positions).
/// </summary>
[Cmdlet(VerbsData.Import, "DbatoolsConfig", DefaultParameterSetName = "Path")]
public sealed class ImportDbatoolsConfigCommand : DbaBaseCmdlet
{
    /// <summary>Paths to JSON configuration files, web links or raw JSON strings.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "Path")]
    public string[] Path { get; set; } = null!;

    /// <summary>The module whose persisted configuration settings are imported.</summary>
    [Parameter(ParameterSetName = "ModuleName", Mandatory = true)]
    [PsStringCast]
    public string ModuleName { get; set; } = null!;

    /// <summary>The configuration version of the module-settings to load.</summary>
    [Parameter(ParameterSetName = "ModuleName")]
    public int ModuleVersion { get; set; } = 1;

    /// <summary>Where to search for persisted module configuration.</summary>
    [Parameter(ParameterSetName = "ModuleName")]
    public ConfigScope Scope { get; set; } = ConfigScope.FileUserLocal | ConfigScope.FileUserShared | ConfigScope.FileSystem;

    /// <summary>Wildcard patterns an item must match to be imported.</summary>
    [Parameter(ParameterSetName = "Path")]
    public string[]? IncludeFilter { get; set; }

    /// <summary>Wildcard patterns that exclude matching items from the import.</summary>
    [Parameter(ParameterSetName = "Path")]
    public string[]? ExcludeFilter { get; set; }

    /// <summary>Returns the would-be imports without applying them.</summary>
    [Parameter(ParameterSetName = "Path")]
    public SwitchParameter Peek { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void BeginProcessing()
    {
        WriteMessage(MessageLevel.InternalComment,
            "Bound parameters: " + string.Join(", ", MyInvocation.BoundParameters.Keys),
            tag: new[] { "debug", "start", "param" });
    }

    protected override void ProcessRecord()
    {
        #region Explicit Path
        if (Path is not null)
        {
            foreach (string item in Path)
            {
                List<PSObject> data;
                try
                {
                    if (PsLike(item, "http*"))
                    {
                        data = ReadDbatoolsConfigFile(weblink: item);
                    }
                    else
                    {
                        // PS: try { Resolve-DbaPath -Path $item -SingleItem -Provider FileSystem } catch { }
                        // Resolve-DbaPath hardcodes -EnableException $true, so its failure
                        // warning (display-suppressed, capture-visible) must survive the throw.
                        string? pathItem = null;
                        Hashtable resolveParams = new();
                        resolveParams["Path"] = item;
                        resolveParams["SingleItem"] = new SwitchParameter(true);
                        resolveParams["Provider"] = "FileSystem";
                        Collection<PSObject> resolved = InvokeNestedPreservingWarnings("Resolve-DbaPath", resolveParams, out ErrorRecord? resolveFailure);
                        if (resolveFailure is null && resolved.Count > 0)
                        {
                            object? resolvedValue = resolved.Count == 1 ? resolved[0] : (object)resolved;
                            pathItem = (string)LanguagePrimitives.ConvertTo(resolvedValue, typeof(string), CultureInfo.InvariantCulture);
                        }
                        if (LanguagePrimitives.IsTrue(pathItem))
                            data = ReadDbatoolsConfigFile(path: pathItem);
                        else
                            data = ReadDbatoolsConfigFile(rawJson: item);
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    StopFunction("Failed to import " + item, target: item, errorRecord: ToCaughtRecord(ex), tag: new[] { "fail", "import" }, continueLoop: true);
                    continue;
                }

                foreach (PSObject element in data)
                {
                    object? fullNameValue = PsProperty.Get(element, "FullName");
                    string fullNameText = PsText(fullNameValue);

                    #region Exclude Filter
                    bool excluded = false;
                    if (ExcludeFilter is not null)
                    {
                        foreach (string exclusion in ExcludeFilter)
                        {
                            if (PsLikeTruthy(fullNameValue, exclusion))
                            {
                                excluded = true;
                                break;
                            }
                        }
                    }
                    if (excluded)
                        continue;
                    #endregion Exclude Filter

                    #region Include Filter
                    if (LanguagePrimitives.IsTrue(IncludeFilter))
                    {
                        bool isIncluded = false;
                        foreach (string inclusion in IncludeFilter!)
                        {
                            if (PsLikeTruthy(fullNameValue, inclusion))
                            {
                                isIncluded = true;
                                break;
                            }
                        }
                        if (!isIncluded)
                            continue;
                    }
                    #endregion Include Filter

                    if (Peek.IsPresent)
                    {
                        WriteObject(element);
                    }
                    else
                    {
                        ErrorRecord? setFailure;
                        if (!LanguagePrimitives.IsTrue(PsProperty.Get(element, "KeepPersisted")))
                        {
                            Hashtable setParams = new();
                            setParams["FullName"] = fullNameValue;
                            setParams["Value"] = PsProperty.Get(element, "Value");
                            // PS: -EnableException (hardcoded switch, not the caller's value)
                            setParams["EnableException"] = new SwitchParameter(true);
                            EmitAll(InvokeNestedPreservingWarnings("Set-DbatoolsConfig", setParams, out setFailure));
                        }
                        else
                        {
                            Hashtable setParams = new();
                            setParams["FullName"] = fullNameValue;
                            setParams["PersistedValue"] = PsProperty.Get(element, "Value");
                            setParams["PersistedType"] = PsProperty.Get(element, "Type");
                            EmitAll(InvokeNestedPreservingWarnings("Set-DbatoolsConfig", setParams, out setFailure));
                        }
                        if (setFailure is not null)
                        {
                            StopFunction("Failed to set '" + fullNameText + "'", target: item, errorRecord: setFailure, tag: new[] { "fail", "import" }, continueLoop: true);
                            continue;
                        }
                    }
                }
            }
        }
        #endregion Explicit Path

        if (LanguagePrimitives.IsTrue(ModuleName))
        {
            Hashtable data = ReadDbatoolsConfigPersisted(ModuleName, Scope, ModuleVersion);

            foreach (object? value in data.Values)
            {
                object? fullName = PsProperty.Get(value, "FullName");
                ErrorRecord? moduleSetFailure;
                if (!LanguagePrimitives.IsTrue(PsProperty.Get(value, "KeepPersisted")))
                {
                    Hashtable setParams = new();
                    setParams["FullName"] = fullName;
                    setParams["Value"] = PsProperty.Get(value, "Value");
                    setParams["EnableException"] = EnableException.ToBool();
                    EmitAll(InvokeNestedPreservingWarnings("Set-DbatoolsConfig", setParams, out moduleSetFailure));
                }
                else
                {
                    Hashtable setParams = new();
                    setParams["FullName"] = fullName;
                    setParams["Value"] = ConfigurationHost.ConvertFromPersistedValue(
                        (string)LanguagePrimitives.ConvertTo(PsProperty.Get(value, "Value"), typeof(string), CultureInfo.InvariantCulture),
                        (ConfigurationValueType)LanguagePrimitives.ConvertTo(PsProperty.Get(value, "Type"), typeof(ConfigurationValueType), CultureInfo.InvariantCulture));
                    setParams["EnableException"] = EnableException.ToBool();
                    EmitAll(InvokeNestedPreservingWarnings("Set-DbatoolsConfig", setParams, out moduleSetFailure));
                }
                // PS: these Set calls have no try/catch - a terminating failure propagates.
                if (moduleSetFailure is not null)
                    ThrowTerminatingError(moduleSetFailure);
            }
        }
    }

    /// <summary>PS -like (case-insensitive wildcard match).</summary>
    private static bool PsLike(string? value, string pattern)
    {
        return WildcardPattern.Get(pattern, WildcardOptions.IgnoreCase).IsMatch(value ?? "");
    }

    /// <summary>PS -eq truthiness over a possibly-array left operand: an enumerable LHS
    /// filters per element and is truthy when ANY element matches (codex r2 F3).</summary>
    private static bool PsEqTruthy(object? left, object? right)
    {
        IEnumerable? enumerable = LanguagePrimitives.GetEnumerable(left);
        if (enumerable is null)
            return PsOps.Eq(left, right);
        foreach (object? element in enumerable)
        {
            if (PsOps.Eq(element, right))
                return true;
        }
        return false;
    }

    /// <summary>PS -like truthiness over a possibly-array left operand: an enumerable LHS
    /// filters per element and is truthy when ANY element matches (codex r1 F4).</summary>
    private static bool PsLikeTruthy(object? value, string pattern)
    {
        IEnumerable? enumerable = LanguagePrimitives.GetEnumerable(value);
        if (enumerable is null)
            return PsLike(value is null ? "" : PsText(value), pattern);
        foreach (object? element in enumerable)
        {
            if (PsLike(PsText(element), pattern))
                return true;
        }
        return false;
    }

    /// <summary>PS: an unassigned Set-DbatoolsConfig statement lets its output (e.g. a
    /// PSDefaultParameterValues-injected -PassThru Config object) flow to the pipeline
    /// (codex r2 F2).</summary>
    private void EmitAll(Collection<PSObject> results)
    {
        foreach (PSObject item in results)
            WriteObject(item);
    }

    /// <summary>PS string interpolation of an arbitrary token.</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }

    /// <summary>
    /// PS: catch { $_ } — a nested terminating error carries the original failing record
    /// (RuntimeException.ErrorRecord); anything else wraps like the landed W1 ports.
    /// </summary>
    private static ErrorRecord ToCaughtRecord(Exception ex)
    {
        if (ex is RuntimeException runtime && runtime.ErrorRecord is not null)
            return runtime.ErrorRecord;
        return new ErrorRecord(ex, "Import-DbatoolsConfig", ErrorCategory.NotSpecified, null);
    }

    /// <summary>
    /// Runs a nested command with PS-bubbling warning parity: the script-side try/catch
    /// returns the outcome as data so warnings written BEFORE a terminating failure still
    /// reach this cmdlet, which re-emits them display-suppressed (the MessageService
    /// WarningPreference-swap trick) purely for caller -WarningVariable capture — the nested
    /// runtime already displayed any non-suppressed ones. Same pattern as ImportDbaCsvCommand's
    /// ConnectViaCommand (shared-promotion is an owner hand-back). PSDefaultParameterValues is
    /// shielded to the global table for the nested window, like NestedCommand.
    /// </summary>
    private Collection<PSObject> InvokeNestedPreservingWarnings(string commandName, Hashtable parameters, out ErrorRecord? failure)
    {
        // PS: a bound -WarningAction on the outer command sets the preference the nested
        // call inherits (display suppression; -WarningVariable still captures) - codex r1 F1.
        ScriptBlock script = ScriptBlock.Create(
            "param($__params, $__wp) if ($null -ne $__wp) { $WarningPreference = $__wp } try { $__r = & " + commandName + " @__params -WarningVariable __nestedWarnings; @{ ok = $true; result = $__r; warnings = $__nestedWarnings } } catch { @{ ok = $false; record = $_; warnings = $__nestedWarnings } }");
        object? boundWarningAction;
        MyInvocation.BoundParameters.TryGetValue("WarningAction", out boundWarningAction);

        Collection<PSObject> raw;
        // Empty-table shield: module-internal calls never saw caller-local OR global
        // defaults (lab-proven via the PassThru-injection probe).
        object? effectiveDefaults = SessionState.PSVariable.GetValue("PSDefaultParameterValues");
        bool shielded = effectiveDefaults is not null;
        if (shielded)
            SessionState.PSVariable.Set("PSDefaultParameterValues", new DefaultParameterDictionary());
        try
        {
            raw = InvokeCommand.InvokeScript(true, script, null, parameters, boundWarningAction);
        }
        finally
        {
            if (shielded)
                SessionState.PSVariable.Set("PSDefaultParameterValues", effectiveDefaults);
        }

        Hashtable outcome = (Hashtable)raw[0].BaseObject;

        object? warnings = outcome["warnings"];
        if (warnings is not null)
        {
            IEnumerable? enumerable = LanguagePrimitives.GetEnumerable(warnings);
            if (enumerable is not null)
            {
                foreach (object? warningItem in enumerable)
                {
                    object? unwrapped = warningItem is PSObject wrappedWarning ? wrappedWarning.BaseObject : warningItem;
                    string text = unwrapped is WarningRecord warningRecord ? warningRecord.Message : PsText(unwrapped);
                    object? oldPreference = SessionState.PSVariable.GetValue("WarningPreference");
                    try
                    {
                        SessionState.PSVariable.Set("WarningPreference", ActionPreference.SilentlyContinue);
                        WriteWarning(text);
                    }
                    finally
                    {
                        SessionState.PSVariable.Set("WarningPreference", oldPreference);
                    }
                }
            }
        }

        if (!LanguagePrimitives.IsTrue(outcome["ok"]))
        {
            object? record = outcome["record"];
            if (record is PSObject wrappedRecord)
                record = wrappedRecord.BaseObject;
            failure = (ErrorRecord)record!;
            return new Collection<PSObject>();
        }

        failure = null;
        Collection<PSObject> results = new();
        object? resultValue = outcome["result"];
        if (resultValue is not null)
        {
            IEnumerable? resultEnumerable = LanguagePrimitives.GetEnumerable(resultValue);
            if (resultEnumerable is null)
            {
                results.Add(PSObject.AsPSObject(resultValue));
            }
            else
            {
                foreach (object? element in resultEnumerable)
                {
                    if (element is not null)
                        results.Add(PSObject.AsPSObject(element));
                }
            }
        }
        return results;
    }

    /// <summary>The absorbed New-ConfigItem helper: an ORDERED pscustomobject literal.</summary>
    private static PSObject NewConfigItem(object? fullName, object? value, object? type = null, bool keepPersisted = false, bool enforced = false, bool policy = false)
    {
        PSObject item = new();
        item.Properties.Add(new PSNoteProperty("FullName", fullName));
        item.Properties.Add(new PSNoteProperty("Value", value));
        item.Properties.Add(new PSNoteProperty("Type", type));
        item.Properties.Add(new PSNoteProperty("KeepPersisted", new SwitchParameter(keepPersisted)));
        item.Properties.Add(new PSNoteProperty("Enforced", new SwitchParameter(enforced)));
        item.Properties.Add(new PSNoteProperty("Policy", new SwitchParameter(policy)));
        return item;
    }

    /// <summary>Replicates PS pipeline-assignment + foreach shaping over a nested result
    /// (a single array output enumerates its elements; $null enumerates nothing).</summary>
    private static IEnumerable<object?> PsForeach(Collection<PSObject> raw)
    {
        object? value = raw.Count == 0 ? null : raw.Count == 1 ? raw[0] : (object)raw;
        if (value is null)
            yield break;
        IEnumerable? enumerable = LanguagePrimitives.GetEnumerable(value);
        if (enumerable is null)
        {
            yield return value;
            yield break;
        }
        foreach (object? element in enumerable)
            yield return element;
    }

    /// <summary>
    /// Absorbed private/functions/configuration/Read-DbatoolsConfigFile.ps1. ConvertFrom-Json
    /// rides the REAL engine cmdlet (edition-faithful JSON shapes); missing files return
    /// nothing without error.
    /// </summary>
    private List<PSObject> ReadDbatoolsConfigFile(string? path = null, string? weblink = null, string? rawJson = null)
    {
        Collection<PSObject> parsed = new();
        if (path is not null)
        {
            if (!System.IO.File.Exists(path))
                return new List<PSObject>();
            string text = System.IO.File.ReadAllText(path);
            parsed = ConvertFromJson(text);
        }
        if (weblink is not null)
        {
            // PS: New-Object System.Net.WebClient with UTF8 encoding, DownloadString
#pragma warning disable SYSLIB0014
            System.Net.WebClient webClient = new();
#pragma warning restore SYSLIB0014
            webClient.Encoding = System.Text.Encoding.UTF8;
            string content = webClient.DownloadString(weblink);
            parsed = ConvertFromJson(content);
        }
        if (rawJson is not null)
        {
            parsed = ConvertFromJson(rawJson);
        }

        List<PSObject> results = new();
        foreach (object? item in PsForeach(parsed))
        {
            object? version = PsProperty.Get(item, "Version");

            #region No Version
            if (!LanguagePrimitives.IsTrue(version))
            {
                results.Add(NewConfigItem(
                    PsProperty.Get(item, "FullName"),
                    ConfigurationHost.ConvertFromPersistedValue(
                        (string)LanguagePrimitives.ConvertTo(PsProperty.Get(item, "Value"), typeof(string), CultureInfo.InvariantCulture),
                        (ConfigurationValueType)LanguagePrimitives.ConvertTo(PsProperty.Get(item, "Type"), typeof(ConfigurationValueType), CultureInfo.InvariantCulture))));
            }
            #endregion No Version

            #region Version One
            if (PsEqTruthy(version, 1))
            {
                object? style = PsProperty.Get(item, "Style");
                if (!LanguagePrimitives.IsTrue(style) || PsEqTruthy(style, "Simple"))
                {
                    results.Add(NewConfigItem(PsProperty.Get(item, "FullName"), PsProperty.Get(item, "Data")));
                }
                else
                {
                    object? type = PsProperty.Get(item, "Type");
                    if (PsEqTruthy(type, "Object") || PsEqTruthy(type, 12))
                    {
                        results.Add(NewConfigItem(PsProperty.Get(item, "FullName"), PsProperty.Get(item, "Value"), "Object", keepPersisted: true));
                    }
                    else
                    {
                        results.Add(NewConfigItem(
                            PsProperty.Get(item, "FullName"),
                            ConfigurationHost.ConvertFromPersistedValue(
                                (string)LanguagePrimitives.ConvertTo(PsProperty.Get(item, "Value"), typeof(string), CultureInfo.InvariantCulture),
                                (ConfigurationValueType)LanguagePrimitives.ConvertTo(type, typeof(ConfigurationValueType), CultureInfo.InvariantCulture))));
                    }
                }
            }
            #endregion Version One
        }
        return results;
    }

    /// <summary>PS: ... | ConvertFrom-Json -ErrorAction Stop — the REAL engine cmdlet.</summary>
    private Collection<PSObject> ConvertFromJson(string text)
    {
        Hashtable jsonParams = new();
        jsonParams["ErrorAction"] = "Stop";
        return NestedCommand.Invoke(this, "ConvertFrom-Json", jsonParams, pipelineInput: text);
    }

    /// <summary>
    /// Absorbed private/functions/configuration/Read-DbatoolsConfigPersisted.ps1: reads the
    /// scoped persisted config files and registry policies in the mandated override order.
    /// Module-scope path variables read LIVE off the dbatools script module's SessionState.
    /// </summary>
    private Hashtable ReadDbatoolsConfigPersisted(string module, ConfigScope scope, int moduleVersion)
    {
        // PS @{} literal (edition-split comparer, capacity 0).
        Hashtable results = PsHashtable.Literal(0);
        string filename = module.ToLowerInvariant() + "-" + moduleVersion.ToString(CultureInfo.InvariantCulture) + ".json";
        int scopeValue = (int)scope;
        bool noRegistry = LanguagePrimitives.IsTrue(GetModuleVariable("NoRegistry"));

        //region File - Computer Wide
        if ((scopeValue & 64) != 0)
            MergePersisted(results, ReadPersistedFile("path_FileSystem", filename));
        //endregion File - Computer Wide

        //region Registry - Computer Wide
        if ((scopeValue & 4) != 0 && !noRegistry)
            MergePersisted(results, ReadRegistry(GetModuleVariableText("path_RegistryMachineDefault"), enforced: false));
        //endregion Registry - Computer Wide

        //region File - User Shared
        if ((scopeValue & 32) != 0)
            MergePersisted(results, ReadPersistedFile("path_FileUserShared", filename));
        //endregion File - User Shared

        //region Registry - User Shared
        if ((scopeValue & 1) != 0 && !noRegistry)
            MergePersisted(results, ReadRegistry(GetModuleVariableText("path_RegistryUserDefault"), enforced: false));
        //endregion Registry - User Shared

        //region File - User Local
        if ((scopeValue & 16) != 0)
            MergePersisted(results, ReadPersistedFile("path_FileUserLocal", filename));
        //endregion File - User Local

        //region Registry - User Enforced
        if ((scopeValue & 2) != 0 && !noRegistry)
            MergePersisted(results, ReadRegistry(GetModuleVariableText("path_RegistryUserEnforced"), enforced: true));
        //endregion Registry - User Enforced

        //region Registry - System Enforced
        if ((scopeValue & 8) != 0 && !noRegistry)
            MergePersisted(results, ReadRegistry(GetModuleVariableText("path_RegistryMachineEnforced"), enforced: true));
        //endregion Registry - System Enforced

        return results;
    }

    /// <summary>The caller never passes -Default, so existing keys are overwritten. A null
    /// FullName faults the index assignment exactly like PS (codex r2 F4).</summary>
    private static void MergePersisted(Hashtable results, List<PSObject> items)
    {
        foreach (PSObject item in items)
        {
            object? fullName = PsProperty.Get(item, "FullName");
            if (fullName is null)
                throw new RuntimeException("Index operation failed; the array index evaluated to null.");
            results[PsText(fullName)] = item;
        }
    }

    private List<PSObject> ReadPersistedFile(string pathVariable, string filename)
    {
        object? root = GetModuleVariable(pathVariable);
        // PS: [IO.Path]::Combine($script:path_X, $filename) — a null root fails the method
        // binder statement-terminating, exactly like the PS call.
        string combined = System.IO.Path.Combine((string)LanguagePrimitives.ConvertTo(root, typeof(string), CultureInfo.InvariantCulture), filename);
        return ReadDbatoolsConfigFile(path: combined);
    }

    /// <summary>Absorbed Read-Registry helper: Test-Path + Get-ItemProperty ride the REAL
    /// provider cmdlets; policy values decode through ConvertFromPersistedValue.</summary>
    private List<PSObject> ReadRegistry(string path, bool enforced)
    {
        List<PSObject> results = new();
        if (path.StartsWith("HK", StringComparison.Ordinal))
        {
            path = path.Replace("HKLM:\\SOFTWARE", "Registry::HKEY_Local_Machine\\SOFTWARE");
            path = path.Replace("HKCU:\\SOFTWARE", "Registry::HKEY_Current_User\\SOFTWARE");
        }

        // test-path required for registry checks
        Hashtable testParams = new();
        testParams["Path"] = path;
        Collection<PSObject> exists = NestedCommand.Invoke(this, "Test-Path", testParams);
        if (!LanguagePrimitives.IsTrue(exists.Count == 1 ? exists[0] : (object)exists))
            return results;

        string[] common = { "PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider" };

        Hashtable itemParams = new();
        itemParams["Path"] = path;
        itemParams["ErrorAction"] = "Ignore";
        Collection<PSObject> properties = NestedCommand.Invoke(this, "Get-ItemProperty", itemParams);
        foreach (object? propertyBag in PsForeach(properties))
        {
            if (propertyBag is null)
                continue;
            foreach (PSPropertyInfo property in PSObject.AsPSObject(propertyBag).Properties)
            {
                if (PsString.In(property.Name, common))
                    continue;
                object? propertyValue;
                try
                {
                    propertyValue = property.Value;
                }
                catch
                {
                    continue;
                }
                string valueText = PsText(propertyValue);
                if (PsLike(valueText, "Object:*"))
                {
                    string[] split = valueText.Split(new[] { ':' }, 2);
                    results.Add(NewConfigItem(property.Name, split[1], split[0], keepPersisted: true, enforced: enforced, policy: true));
                }
                else
                {
                    try
                    {
                        results.Add(NewConfigItem(property.Name, ConfigurationHost.ConvertFromPersistedValue(valueText), policy: true));
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        WriteMessage(MessageLevel.Warning, "Failed to load configuration from Registry: " + property.Name, target: path + " : " + property.Name, exception: ex);
                    }
                }
            }
        }
        return results;
    }

    /// <summary>Reads a $script:-scoped variable LIVE off the dbatools script module.</summary>
    private object? GetModuleVariable(string variableName)
    {
        Hashtable getModuleParams = new();
        getModuleParams["Name"] = "dbatools";
        foreach (PSObject wrapped in NestedCommand.Invoke(this, "Get-Module", getModuleParams))
        {
            if (wrapped?.BaseObject is PSModuleInfo module && module.ModuleType == ModuleType.Script)
                return module.SessionState.PSVariable.GetValue("script:" + variableName);
        }
        return null;
    }

    private string GetModuleVariableText(string variableName)
    {
        return (string)LanguagePrimitives.ConvertTo(GetModuleVariable(variableName), typeof(string), CultureInfo.InvariantCulture);
    }
}
