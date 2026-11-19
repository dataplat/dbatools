#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Net;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves detailed metadata and download links for Microsoft KB updates from the update
/// catalog. Port of public/Get-DbaKbUpdate.ps1; surface pinned by
/// migration/baselines/Get-DbaKbUpdate.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaKbUpdate")]
public sealed class GetDbaKbUpdateCommand : DbaBaseCmdlet
{
    /// <summary>The KB article number(s) to search for, with or without the KB prefix.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public string[]? Name { get; set; }

    /// <summary>Returns only essential update information (skips the detailed scrape).</summary>
    [Parameter]
    public SwitchParameter Simple { get; set; }

    /// <summary>Filters results to a specific language when multiple language versions exist.</summary>
    [Parameter(Position = 1)]
    public string? Language { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS: $script:websession - module-scope state persisting ACROSS invocations (per process).
    private static PSObject? _websession;

    private static readonly string[] BaseProperties = new[]
    {
        "Title", "Description", "Architecture", "NameLevel", "SPLevel", "KBLevel", "CULevel",
        "BuildLevel", "SupportedUntil", "Language", "Classification", "SupportedProducts",
        "MSRCNumber", "MSRCSeverity", "Hotfix", "Size", "UpdateId", "RebootBehavior",
        "RequestsUserInput", "ExclusiveInstall", "NetworkRequired", "UninstallNotes",
        "UninstallSteps", "SupersededBy", "Supersedes", "LastModified", "Link"
    };

    protected override void BeginProcessing()
    {
        // PS: if (-not $script:websession) { $null = Invoke-KbTlsWebRequest -Uri catalog-root }
        // - an init failure is a TERMINATING -ErrorAction Stop error outside any try (the whole
        // command dies with the web error).
        if (_websession is null)
        {
            InvokeKbWebRequest("https://www.catalog.update.microsoft.com/", null, null);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (string kbName in Name ?? Array.Empty<string>())
        {
            try
            {
                // PS: $kb.Replace("KB", "").Replace("kb", "").Replace("Kb", "") - ordinal,
                // case-sensitive .NET replaces (deliberately leaves "kB" alone).
                string kb = (kbName ?? string.Empty).Replace("KB", "").Replace("kb", "").Replace("Kb", "");

                PSObject? results = InvokeKbWebRequest($"http://www.catalog.update.microsoft.com/Search.aspx?q=KB{kb}", null, null);

                // PS: $results.InputFields | Where-Object { $_.type -eq 'Button' -and $_.class -eq
                //     'flatBlueButtonDownload focus-only' } | Select-Object -ExpandProperty ID
                List<object?> kbids = new();
                foreach (object? field in EnumerateAny(GetProperty(results, "InputFields")))
                {
                    PSObject item = PSObject.AsPSObject(field);
                    if (LanguagePrimitives.Equals(item.Properties["type"]?.Value, "Button", ignoreCase: true)
                        && LanguagePrimitives.Equals(item.Properties["class"]?.Value, "flatBlueButtonDownload focus-only", ignoreCase: true))
                    {
                        kbids.Add(item.Properties["ID"]?.Value);
                    }
                }

                if (kbids.Count == 0)
                {
                    // PS: "No results found for $Name" - the ARRAY parameter, joined with the
                    // session $OFS, not the current $kb.
                    WriteMessage(MessageLevel.Warning, $"No results found for {PsJoin(Name)}");
                    // PS: return - exits the process block, skipping any REMAINING KBs too.
                    return;
                }

                WriteMessage(MessageLevel.Verbose, PsJoin(kbids));

                // PS: $results.Links | Where-Object ID -match '_link' |
                //     ForEach-Object { $_.id.replace('_link', '') } | Where-Object { $_ -in $kbids }
                List<string> guids = new();
                foreach (object? linkItem in EnumerateAny(GetProperty(results, "Links")))
                {
                    PSObject item = PSObject.AsPSObject(linkItem);
                    object? idValue = item.Properties["ID"]?.Value;
                    string idText = LanguagePrimitives.ConvertTo<string>(idValue) ?? string.Empty;
                    if (!Regex.IsMatch(idText, "_link", RegexOptions.IgnoreCase))
                    {
                        continue;
                    }
                    // PS: $_.id.replace('_link', '') - the ordinal .NET string replace.
                    string guid = idText.Replace("_link", "");
                    foreach (object? candidate in kbids)
                    {
                        if (LanguagePrimitives.Equals(guid, candidate, ignoreCase: true))
                        {
                            guids.Add(guid);
                            break;
                        }
                    }
                }

                foreach (string guid in guids)
                {
                    WriteMessage(MessageLevel.Verbose, $"Downloading information for {guid}");

                    // PS: $post = @{ size = 0; updateID = $guid; uidInfo = $guid } | ConvertTo-Json
                    //     -Compress - built VERBATIM in-engine so the edition's @{} key order (and
                    //     JSON shape) match exactly.
                    Collection<PSObject> postResult = InvokeCommand.InvokeScript(
                        false,
                        ScriptBlock.Create("param($__guid) @{ size = 0; updateID = $__guid; uidInfo = $__guid } | ConvertTo-Json -Compress"),
                        null,
                        guid);
                    string post = postResult.Count > 0 ? LanguagePrimitives.ConvertTo<string>(postResult[0]) ?? string.Empty : string.Empty;
                    Hashtable body = new Hashtable { { "updateIDs", $"[{post}]" } };

                    PSObject? downloadResponse = InvokeKbWebRequest("https://www.catalog.update.microsoft.com/DownloadDialog.aspx", "Post", body);
                    string downloaddialog = LanguagePrimitives.ConvertTo<string>(GetProperty(downloadResponse, "Content")) ?? string.Empty;

                    string? title = GetInfo(downloaddialog, "enTitle =");
                    string? arch = GetInfo(downloaddialog, "architectures =");
                    string? longlang = GetInfo(downloaddialog, "longLanguages =");
                    string? updateid = GetInfo(downloaddialog, "updateID =");
                    string? isHotfix = GetInfo(downloaddialog, "isHotFix =");

                    if (LanguagePrimitives.Equals(arch, "AMD64", ignoreCase: true))
                    {
                        arch = "x64";
                    }
                    bool titleHas64 = title is not null && Regex.IsMatch(title, "64-Bit", RegexOptions.IgnoreCase);
                    bool titleHas32 = title is not null && Regex.IsMatch(title, "32-Bit", RegexOptions.IgnoreCase);
                    if (titleHas64 && !titleHas32 && string.IsNullOrEmpty(arch))
                    {
                        arch = "x64";
                    }
                    if (!titleHas64 && titleHas32 && string.IsNullOrEmpty(arch))
                    {
                        arch = "x86";
                    }

                    string? description = null;
                    string? lastmodified = null;
                    string? size = null;
                    string? classification = null;
                    object? supportedproducts = null;
                    string? msrcnumber = null;
                    string? msrcseverity = null;
                    string? rebootbehavior = null;
                    string? requestuserinput = null;
                    string? exclusiveinstall = null;
                    string? networkrequired = null;
                    string? uninstallnotes = null;
                    string? uninstallsteps = null;
                    object? supersededby = null;
                    object? supersedes = null;

                    if (!Simple.ToBool())
                    {
                        WriteMessage(MessageLevel.Verbose, $"Downloading detailed information for updateid={updateid}");

                        // PS: the detail page is fetched as .Content (multi-byte safety note in the
                        // source) and re-fetched ONCE when the description is missing.
                        PSObject? detailResponse = InvokeKbWebRequest($"https://www.catalog.update.microsoft.com/ScopedViewInline.aspx?updateid={updateid}", null, null);
                        string detaildialog = LanguagePrimitives.ConvertTo<string>(GetProperty(detailResponse, "Content")) ?? string.Empty;
                        description = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_desc\">");
                        if (string.IsNullOrEmpty(description))
                        {
                            detailResponse = InvokeKbWebRequest($"https://www.catalog.update.microsoft.com/ScopedViewInline.aspx?updateid={updateid}", null, null);
                            detaildialog = LanguagePrimitives.ConvertTo<string>(GetProperty(detailResponse, "Content")) ?? string.Empty;
                            description = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_desc\">");
                            if (string.IsNullOrEmpty(description))
                            {
                                WriteMessage(MessageLevel.Warning, "The response from the webserver did not include the expected information. Please try again later if you need the detailed information.");
                            }
                        }
                        lastmodified = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_date\">");
                        size = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_size\">");
                        classification = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_labelClassification_Separator\" class=\"labelTitle\">");
                        supportedproducts = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_labelSupportedProducts_Separator\" class=\"labelTitle\">");
                        msrcnumber = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_labelSecurityBulliten_Separator\" class=\"labelTitle\">");
                        msrcseverity = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_msrcSeverity\">");
                        rebootbehavior = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_rebootBehavior\">");
                        requestuserinput = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_userInput\">");
                        exclusiveinstall = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_installationImpact\">");
                        networkrequired = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_connectivity\">");
                        uninstallnotes = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_labelUninstallNotes_Separator\" class=\"labelTitle\">");
                        uninstallsteps = GetInfo(detaildialog, "<span id=\"ScopedViewHandler_labelUninstallSteps_Separator\" class=\"labelTitle\">");
                        supersededby = GetSuperInfo(detaildialog, "<div id=\"supersededbyInfo\".*>");
                        supersedes = GetSuperInfo(detaildialog, "<div id=\"supersedesInfo\".*>");

                        // PS: $product = $supportedproducts -split ","; if ($product.Count -gt 1)
                        // { rebuild as trimmed non-empty ARRAY }
                        string[] product = Regex.Split(LanguagePrimitives.ConvertTo<string>(supportedproducts) ?? string.Empty, ",");
                        if (product.Length > 1)
                        {
                            List<string> rebuilt = new();
                            foreach (string line in product)
                            {
                                string clean = line.Trim();
                                if (!string.IsNullOrEmpty(clean))
                                {
                                    rebuilt.Add(clean);
                                }
                            }
                            supportedproducts = rebuilt.ToArray();
                        }
                    }

                    // PS: $downloaddialog | Select-String -AllMatches -Pattern "(http[s]?\://
                    //     [^/]*download\.windowsupdate\.com\/[^\'\"]*)" | Select-Object -Unique -
                    //     one input string yields at most ONE MatchInfo, so the foreach runs at
                    //     most once and Link carries the member-enumerated match VALUES.
                    MatchCollection linkMatches = Regex.Matches(downloaddialog, "(http[s]?\\://[^/]*download\\.windowsupdate\\.com\\/[^\\'\\\"]*)", RegexOptions.IgnoreCase);
                    if (linkMatches.Count == 0)
                    {
                        continue;
                    }
                    object? linkValue;
                    if (linkMatches.Count == 1)
                    {
                        linkValue = linkMatches[0].Value;
                    }
                    else
                    {
                        string[] values = new string[linkMatches.Count];
                        for (int i = 0; i < linkMatches.Count; i++)
                        {
                            values[i] = linkMatches[i].Value;
                        }
                        linkValue = values;
                    }

                    // PS: $build = Get-DbaBuild -Kb "KB$kb" -WarningAction SilentlyContinue -
                    // the bound WarningAction suppresses records from the warning STREAM at that
                    // boundary yet every enclosing -WarningVariable still CAPTURES them (verified
                    // live: the [Resolve-DbaBuild] warning lands in the caller's WarningVariable).
                    // A nested 3>&1 merge under a bound SilentlyContinue carries NOTHING to
                    // re-emit, so the port binds no WarningAction and re-emits the merged records
                    // - capture parity exactly; the record is merely visible on the console where
                    // PS hides it (accepted micro-deviation).
                    Hashtable splatBuild = new Hashtable
                    {
                        { "Kb", $"KB{kb}" }
                    };
                    Collection<PSObject> buildResult = NestedCommand.Invoke(this, "Get-DbaBuild", splatBuild);
                    object? build = ShapeOutput(buildResult);

                    List<string> properties = new(BaseProperties);
                    object? nameLevel = GetProperty(build, "NameLevel");
                    if (!LanguagePrimitives.IsTrue(nameLevel))
                    {
                        properties.RemoveAll(p => p is "NameLevel" or "SPLevel" or "KBLevel" or "CULevel" or "BuildLevel" or "SupportedUntil");
                    }
                    if (Simple.ToBool())
                    {
                        properties.RemoveAll(p => p is "LastModified" or "Description" or "Size" or "Classification" or "SupportedProducts" or "MSRCNumber" or "MSRCSeverity" or "RebootBehavior" or "RequestsUserInput" or "ExclusiveInstall" or "NetworkRequired" or "UninstallNotes" or "UninstallSteps" or "SupersededBy" or "Supersedes");
                    }

                    PSObject output = new();
                    output.Properties.Add(new PSNoteProperty("Title", title));
                    output.Properties.Add(new PSNoteProperty("NameLevel", nameLevel));
                    output.Properties.Add(new PSNoteProperty("SPLevel", GetProperty(build, "SPLevel")));
                    output.Properties.Add(new PSNoteProperty("KBLevel", GetProperty(build, "KBLevel")));
                    output.Properties.Add(new PSNoteProperty("CULevel", GetProperty(build, "CULevel")));
                    output.Properties.Add(new PSNoteProperty("BuildLevel", GetProperty(build, "BuildLevel")));
                    output.Properties.Add(new PSNoteProperty("SupportedUntil", GetProperty(build, "SupportedUntil")));
                    output.Properties.Add(new PSNoteProperty("Architecture", arch));
                    output.Properties.Add(new PSNoteProperty("Language", longlang));
                    output.Properties.Add(new PSNoteProperty("Hotfix", isHotfix));
                    output.Properties.Add(new PSNoteProperty("Description", description));
                    output.Properties.Add(new PSNoteProperty("LastModified", lastmodified));
                    output.Properties.Add(new PSNoteProperty("Size", size));
                    output.Properties.Add(new PSNoteProperty("Classification", classification));
                    output.Properties.Add(new PSNoteProperty("SupportedProducts", supportedproducts));
                    output.Properties.Add(new PSNoteProperty("MSRCNumber", msrcnumber));
                    output.Properties.Add(new PSNoteProperty("MSRCSeverity", msrcseverity));
                    output.Properties.Add(new PSNoteProperty("RebootBehavior", rebootbehavior));
                    output.Properties.Add(new PSNoteProperty("RequestsUserInput", requestuserinput));
                    output.Properties.Add(new PSNoteProperty("ExclusiveInstall", exclusiveinstall));
                    output.Properties.Add(new PSNoteProperty("NetworkRequired", networkrequired));
                    output.Properties.Add(new PSNoteProperty("UninstallNotes", uninstallnotes));
                    output.Properties.Add(new PSNoteProperty("UninstallSteps", uninstallsteps));
                    output.Properties.Add(new PSNoteProperty("UpdateId", updateid));
                    output.Properties.Add(new PSNoteProperty("Supersedes", supersedes));
                    output.Properties.Add(new PSNoteProperty("SupersededBy", supersededby));
                    output.Properties.Add(new PSNoteProperty("Link", linkValue));
                    OutputHelper.SetDefaultDisplayPropertySet(output, properties.ToArray());
                    WriteObject(output);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                // PS: Stop-Function "Failure" WITHOUT -Continue and WITHOUT return - non-EE warns
                // and the foreach proceeds to the next KB.
                StopFunction("Failure", errorRecord: rex.ErrorRecord, continueLoop: true);
            }
            catch (Exception ex)
            {
                StopFunction("Failure", exception: ex, continueLoop: true);
            }
        }
    }

    /// <summary>
    /// PS begin-block helper Invoke-KbTlsWebRequest: proxy pickup from HKCU, TLS protocol
    /// augmentation (process-global, deliberately NOT restored on failure - the PS restore lines
    /// sit after the terminating -ErrorAction Stop request), session/Accept-Language reuse, and
    /// the progress suppression that in PS was a helper-LOCAL preference (scoped here with a
    /// finally because the C# has no helper scope to evaporate).
    /// </summary>
    private PSObject? InvokeKbWebRequest(string uri, string? method, object? body)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            using Microsoft.Win32.RegistryKey? regproxy = Microsoft.Win32.Registry.CurrentUser.OpenSubKey("Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings");
            object? proxy = regproxy?.GetValue("ProxyServer");
            object? proxyEnable = regproxy?.GetValue("ProxyEnable");
            // PS: if ($proxy -and -not (...DefaultWebProxy).Address -and $regproxy.ProxyEnable) -
            // the Address read goes through the adapter (the default system proxy exposes none).
            if (LanguagePrimitives.IsTrue(proxy)
                && !LanguagePrimitives.IsTrue(GetProperty(WebRequest.DefaultWebProxy, "Address"))
                && LanguagePrimitives.IsTrue(proxyEnable))
            {
                WebProxy configured = new(LanguagePrimitives.ConvertTo<string>(proxy));
                configured.Credentials = CredentialCache.DefaultNetworkCredentials;
                WebRequest.DefaultWebProxy = configured;
            }
        }

        // PS: augment SecurityProtocol with every protocol above max(current, Tls); restore AFTER
        // the request (skipped when the request throws - process-global state, quirk preserved).
        SecurityProtocolType currentVersionTls = ServicePointManager.SecurityProtocol;
        int currentSupportable = Math.Max((int)currentVersionTls, (int)SecurityProtocolType.Tls);
        foreach (object value in Enum.GetValues(typeof(SecurityProtocolType)))
        {
            if ((int)value > currentSupportable)
            {
                ServicePointManager.SecurityProtocol |= (SecurityProtocolType)value;
            }
        }

        // PS: if (-not $Language) { $Language = "en-US;q=0.5,en;q=0.3" } - a helper-local
        // effective value; the bound parameter itself is never mutated.
        string effectiveLanguage = string.IsNullOrEmpty(Language) ? "en-US;q=0.5,en;q=0.3" : Language!;

        bool reuseSession = false;
        if (_websession is not null)
        {
            object? headers = GetProperty(_websession, "Headers");
            object? acceptLanguage = null;
            if (headers is not null)
            {
                PSObject headersObj = PSObject.AsPSObject(headers);
                acceptLanguage = headersObj.Properties["Accept-Language"]?.Value;
                if (acceptLanguage is null && headersObj.BaseObject is IDictionary dict)
                {
                    acceptLanguage = dict["Accept-Language"];
                }
            }
            reuseSession = LanguagePrimitives.Equals(acceptLanguage, effectiveLanguage, ignoreCase: true);
        }

        object? saved = SessionState.PSVariable.GetValue("ProgressPreference");
        SessionState.PSVariable.Set("ProgressPreference", ActionPreference.SilentlyContinue);
        try
        {
            using PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace);
            shell.AddCommand("Invoke-WebRequest").AddParameter("Uri", uri);
            if (method is not null)
            {
                shell.AddParameter("Method", method);
            }
            if (body is not null)
            {
                shell.AddParameter("Body", body);
            }
            if (reuseSession)
            {
                shell.AddParameter("WebSession", _websession);
            }
            else
            {
                // PS -SessionVariable news up a session and stores the request headers into it;
                // a pre-created WebRequestSession passed as -WebSession behaves identically and
                // avoids nested-scope variable plumbing.
                Collection<PSObject> fresh = InvokeCommand.InvokeScript(false, ScriptBlock.Create("[Microsoft.PowerShell.Commands.WebRequestSession]::new()"), null, null);
                PSObject session = fresh[0];
                shell.AddParameter("WebSession", session);
                Hashtable headers = new Hashtable { { "accept-language", effectiveLanguage } };
                shell.AddParameter("Headers", headers);
                _websession = session;
            }
            shell.AddParameter("UseBasicParsing", true);
            shell.AddParameter("ErrorAction", "Stop");

            Collection<PSObject> output = shell.Invoke();
            if (shell.Streams.Error.Count > 0)
            {
                // -ErrorAction Stop inside a nested pipeline surfaces as an error record; the PS
                // call site treated it as terminating - rethrow it that way.
                ErrorRecord record = shell.Streams.Error[0];
                throw new RuntimeException(record.Exception?.Message ?? "Invoke-WebRequest failed", record.Exception, record);
            }

            // PS: restore SecurityProtocol AFTER a successful request.
            ServicePointManager.SecurityProtocol = currentVersionTls;
            return output.Count > 0 ? output[0] : null;
        }
        finally
        {
            SessionState.PSVariable.Set("ProgressPreference", saved ?? ActionPreference.Continue);
        }
    }

    // PS begin-block helper Get-Info: regex -Split scraping with the labelTitle/span/default
    // branches; ANY failure lands in the catch -> verbose + null.
    private string? GetInfo(string? text, string pattern)
    {
        try
        {
            // PS -split treats a null LHS as empty string (one empty element), and indexing past
            // the end of a split result yields $null - so the span/default branches return an
            // EMPTY STRING when the pattern is absent, while the labelTitle branch dies on
            // null.Replace and lands in the catch.
            string[] info = Regex.Split(text ?? string.Empty, pattern, RegexOptions.IgnoreCase);
            string? second = At(info, 1);
            if (Regex.IsMatch(pattern, "labelTitle", RegexOptions.IgnoreCase))
            {
                string? part = At(PsSplit(second, "</span>"), 1);
                if (part is null)
                {
                    throw new RuntimeException("You cannot call a method on a null-valued expression.");
                }
                part = part.Replace("<div>", "");
                return PsSplit(part, "</div>")[0].Trim();
            }
            if (Regex.IsMatch(pattern, "span ", RegexOptions.IgnoreCase))
            {
                return PsSplit(second, "</span>")[0].Trim();
            }
            return PsSplit(second, ";")[0].Replace("'", "").Trim();
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch
        {
            WriteMessage(MessageLevel.Verbose, $"Failed to get info with pattern '{pattern}'");
            return null;
        }
    }

    // PS begin-block helper Get-SuperInfo: emits one cleaned line per non-empty markup-stripped
    // line; the caller's assignment takes the pipeline shape (null/scalar/array).
    private object? GetSuperInfo(string? text, string pattern)
    {
        try
        {
            string[] info = Regex.Split(text ?? string.Empty, pattern, RegexOptions.IgnoreCase);
            string? second = At(info, 1);
            string part;
            if (Regex.IsMatch(pattern, "supersededbyInfo", RegexOptions.IgnoreCase))
            {
                part = PsSplit(second, "<span id=\"ScopedViewHandler_labelSupersededUpdates_Separator\" class=\"labelTitle\">")[0];
            }
            else
            {
                part = PsSplit(second, "<div id=\"languageBox\" style=\"display: none\">")[0];
            }
            string nomarkup = Regex.Replace(part, "<[^>]+>", "", RegexOptions.IgnoreCase).Trim();
            // PS: the foreach emission shape - null/scalar/Object[] (never a typed string array).
            List<object?> lines = new();
            foreach (string line in Regex.Split(nomarkup, Regex.Escape(Environment.NewLine)))
            {
                string clean = line.Trim();
                if (!string.IsNullOrEmpty(clean))
                {
                    lines.Add(clean);
                }
            }
            if (lines.Count == 0)
            {
                return null;
            }
            if (lines.Count == 1)
            {
                return lines[0];
            }
            return lines.ToArray();
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch
        {
            WriteMessage(MessageLevel.Verbose, $"Failed to get superinfo with pattern '{pattern}'");
            return null;
        }
    }

    // PS -split on a null LHS yields one empty element; PS array indexing past the end yields null.
    private static string[] PsSplit(string? value, string pattern)
    {
        return Regex.Split(value ?? string.Empty, pattern, RegexOptions.IgnoreCase);
    }

    private static string? At(string[] array, int index)
    {
        return index < array.Length ? array[index] : null;
    }

    // PS "$array" interpolation joins with the session $OFS (default space), read per call.
    private string PsJoin(object? value)
    {
        if (value is null)
        {
            return string.Empty;
        }
        object? ofs = SessionState.PSVariable.GetValue("OFS");
        string separator = ofs is null ? " " : LanguagePrimitives.ConvertTo<string>(ofs) ?? " ";
        if (value is IEnumerable enumerable and not string)
        {
            List<string> parts = new();
            foreach (object? item in enumerable)
            {
                parts.Add(item is null ? string.Empty : LanguagePrimitives.ConvertTo<string>(item) ?? string.Empty);
            }
            return string.Join(separator, parts);
        }
        return LanguagePrimitives.ConvertTo<string>(value) ?? string.Empty;
    }

    private static object? GetProperty(object? source, string name)
    {
        if (source is null)
        {
            return null;
        }
        return PSObject.AsPSObject(source).Properties[name]?.Value;
    }

    private static IEnumerable<object?> EnumerateAny(object? value)
    {
        if (value is null)
        {
            yield break;
        }
        object unwrapped = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (unwrapped is string)
        {
            yield return value;
            yield break;
        }
        if (unwrapped is IEnumerable enumerable)
        {
            foreach (object? item in enumerable)
            {
                yield return item;
            }
            yield break;
        }
        yield return value;
    }

    // PS pipeline-assignment shape: empty -> null, one -> the scalar, many -> object[].
    private static object? ShapeOutput(Collection<PSObject> output)
    {
        if (output.Count == 0)
        {
            return null;
        }
        if (output.Count == 1)
        {
            return output[0];
        }
        object?[] many = new object?[output.Count];
        for (int i = 0; i < output.Count; i++)
        {
            many[i] = output[i];
        }
        return many;
    }
}
