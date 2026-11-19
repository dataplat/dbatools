#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Formats PowerShell files to dbatools OTBS standards through PSScriptAnalyzer's
/// Invoke-Formatter. Port of public/Invoke-DbatoolsFormatter.ps1; the PSScriptAnalyzer
/// commands (Get-Command probe, Remove-Module/Import-Module pin, Invoke-Formatter) and
/// Resolve-Path/Get-Content ride the REAL commands nested. Surface pinned by
/// migration/baselines/Invoke-DbatoolsFormatter.json (Path position 0 pipeline, alias
/// "FullName)" - the source's typo, preserved verbatim). The command calls
/// Test-FunctionInterrupt, so ProcessRecord guards on Interrupted.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbatoolsFormatter")]
public sealed class InvokeDbatoolsFormatterCommand : DbaBaseCmdlet
{
    /// <summary>The .ps1 files to format; accepts pipeline input.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [Alias("FullName)")]
    public object[] Path { get; set; } = null!;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private static readonly Regex CbhRex = new("(?smi)\\s+\\<\\#[^#]*\\#\\>");
    private static readonly Regex CbhStartRex = new("(?<spaces>[ ]+)\\<\\#");
    private static readonly Regex CbhEndRex = new("(?<spaces>[ ]*)\\#\\>");

    private const string ScriptAnalyzerCorrectVersion = "1.18.2";

    // PS: $OSEOL is computed once in begin and DOWNGRADED to LF by the first CR-less file,
    // sticking for every later file in the invocation (quirk preserved as a field).
    private string _osEol = "\n";

    protected override void BeginProcessing()
    {
        // PS: (Get-Command Invoke-Formatter -ErrorAction SilentlyContinue).Version
        Hashtable getCommandParams = new();
        getCommandParams["Name"] = "Invoke-Formatter";
        getCommandParams["ErrorAction"] = "SilentlyContinue";
        Collection<PSObject> commandInfo = NestedCommand.Invoke(this, "Get-Command", getCommandParams);
        object? invokeFormatterVersion = commandInfo.Count > 0 ? PsProperty.Get(commandInfo[0], "Version") : null;
        bool hasInvokeFormatter = invokeFormatterVersion is not null;

        if (!hasInvokeFormatter)
        {
            StopFunction("You need PSScriptAnalyzer version " + ScriptAnalyzerCorrectVersion + " installed");
            WriteMessage(MessageLevel.Warning, "     Install-Module -Name PSScriptAnalyzer -RequiredVersion '" + ScriptAnalyzerCorrectVersion + "'");
        }
        else
        {
            if (!PsOps.Eq(invokeFormatterVersion, ScriptAnalyzerCorrectVersion))
            {
                Hashtable removeParams = new();
                removeParams["Name"] = "PSScriptAnalyzer";
                PropagateBoundPreference(removeParams);
                NestedCommand.Invoke(this, "Remove-Module", removeParams);
                try
                {
                    Hashtable importParams = new();
                    importParams["Name"] = "PSScriptAnalyzer";
                    importParams["RequiredVersion"] = ScriptAnalyzerCorrectVersion;
                    importParams["ErrorAction"] = "Stop";
                    PropagateBoundPreference(importParams);
                    NestedCommand.Invoke(this, "Import-Module", importParams);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch
                {
                    StopFunction("Please install PSScriptAnalyzer " + ScriptAnalyzerCorrectVersion);
                    WriteMessage(MessageLevel.Warning, "     Install-Module -Name PSScriptAnalyzer -RequiredVersion '" + ScriptAnalyzerCorrectVersion + "'");
                }
            }
        }

        // PS: $psVersionTable.Platform -ne 'Unix' (5.1 has no Platform; 7 reports Win32NT here)
        object? psVersionTable = SessionState.PSVariable.GetValue("PSVersionTable");
        object? platform = psVersionTable is IDictionary table ? table["Platform"] : null;
        _osEol = "\n";
        if (!PsOps.Eq(platform, "Unix"))
            _osEol = "\r\n";
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        foreach (object? p in Path)
        {
            // PS: $realPath = (Resolve-Path -Path $p -ErrorAction Stop).Path - the value
            // STAYS an array for a multi-match wildcard (codex r1 F2): the array reaches
            // Get-Content intact and only METHOD calls binder-join it with spaces.
            List<string> paths = new();
            try
            {
                Hashtable resolveParams = new();
                resolveParams["Path"] = p;
                resolveParams["ErrorAction"] = "Stop";
                Collection<PSObject> resolved = NestedCommand.Invoke(this, "Resolve-Path", resolveParams);
                foreach (PSObject pathInfo in resolved)
                    paths.Add(PsText(PsProperty.Get(pathInfo, "Path")));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception)
            {
                // PS passes no -ErrorRecord here: the message IS the record text.
                StopFunction("Cannot find or resolve " + PsText(p), continueLoop: true);
                continue;
            }
            object realPathValue = paths.Count == 1 ? paths[0] : (object)paths.ToArray();
            string realPathJoined = string.Join(" ", paths);

            // PS: Get-Content -Path $realPath -Raw -Encoding UTF8 - the function-local
            // $ErrorActionPreference from the caller's bound -ErrorAction reaches this call
            // in PS, so a read failure under -ErrorAction Stop terminates BEFORE the write
            // (codex r1 F1); the bound value rides the nested call explicitly.
            Hashtable contentParams = new();
            contentParams["Path"] = realPathValue;
            contentParams["Raw"] = new SwitchParameter(true);
            contentParams["Encoding"] = "UTF8";
            PropagateBoundPreference(contentParams, includeErrorAction: true);
            Collection<PSObject> rawContent = NestedCommand.Invoke(this, "Get-Content", contentParams);
            // PS $content: null for no output, scalar for one file, array for many (-Raw
            // emits one string per matched file).
            List<string> contents = new();
            foreach (PSObject rawItem in rawContent)
            {
                if (rawItem?.BaseObject is string rawText)
                    contents.Add(rawText);
            }

            if (_osEol == "\r\n")
            {
                // See #5830, we are in Windows territory here
                // Is the file containing at least one `r ?
                // (PS: ($content -split "`r").Length - an ARRAY flattens per-element splits,
                // so two CR-less files still count 2 and containsCR stays true.)
                int crSplitTotal = 0;
                foreach (string contentItem in contents)
                    crSplitTotal += contentItem.Split('\r').Length;
                if (contents.Count == 0)
                    crSplitTotal = 1; // $null -split "`r" yields one element
                bool containsCR = crSplitTotal > 1;
                if (!containsCR)
                {
                    // If not, maybe even on Windows the user is using Unix-style endings, which are supported
                    _osEol = "\n";
                }
            }

            //strip ending empty lines (element-wise on an array, "" for $null - PS -replace)
            List<string> strippedContents = new();
            if (contents.Count == 0)
            {
                strippedContents.Add("");
            }
            else
            {
                foreach (string contentItem in contents)
                    strippedContents.Add(Regex.Replace(contentItem, "(?s)" + _osEol + "\\s*$", ""));
            }
            string? content;

            try
            {
                Hashtable formatParams = new();
                // The REAL parameter binder space-joins an array bound to the [string]
                // -ScriptDefinition, exactly like the function's call.
                formatParams["ScriptDefinition"] = strippedContents.Count == 1 ? strippedContents[0] : (object)strippedContents.ToArray();
                formatParams["Settings"] = "CodeFormattingOTBS";
                formatParams["ErrorAction"] = "Stop";
                PropagateBoundPreference(formatParams);
                Collection<PSObject> formatted = NestedCommand.Invoke(this, "Invoke-Formatter", formatParams);
                content = formatted.Count > 0 ? PsText(formatted.Count == 1 ? formatted[0] : (object)formatted) : null;
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                WriteMessage(MessageLevel.Warning, "Unable to format " + PsText(p));
                // PS: $content keeps the pre-format value; the next METHOD call
                // (regex Match / Replace / Split) binder-joins an array with spaces.
                content = string.Join(" ", strippedContents);
            }

            //match the ending indentation of CBH with the starting one, see #4373
            string cbh = CbhRex.Match(content ?? "").Value;
            if (!string.IsNullOrEmpty(cbh))
            {
                //get starting spaces
                Group startSpaces = CbhStartRex.Match(cbh).Groups["spaces"];
                // PS: if ($startSpaces) - a Group object is always truthy, matched or not.
                //get end
                string newCbh = CbhEndRex.Replace(cbh, startSpaces.Value + "#>");
                if (!string.IsNullOrEmpty(newCbh))
                {
                    //replace the CBH
                    content = content!.Replace(cbh, newCbh);
                }
            }

            System.Text.UTF8Encoding utf8NoBomEncoding = new(false);
            List<string> realContent = new();
            //trim whitespace lines
            foreach (string line in (content ?? "").Split('\n'))
                realContent.Add(line.Replace("\t", "    ").TrimEnd());
            // PS: [System.IO.File]::WriteAllText($realPath, ...) - the METHOD binder
            // space-joins an array path, so a multi-match write targets the joined name,
            // and a .NET failure surfaces as the MethodInvocationException wrapper.
            try
            {
                System.IO.File.WriteAllText(realPathJoined, string.Join(_osEol, realContent), utf8NoBomEncoding);
            }
            catch (Exception ex)
            {
                throw new MethodInvocationException(
                    "Exception calling \"WriteAllText\" with \"3\" argument(s): \"" + ex.Message + "\"", ex);
            }
        }
    }

    /// <summary>
    /// PS preference inheritance for nested calls: the function-local $VerbosePreference /
    /// $ErrorActionPreference established by the caller's bound common parameters reached
    /// every nested command; the nested-invoke path passes the bound values explicitly
    /// (codex r1 F1/F3).
    /// </summary>
    private void PropagateBoundPreference(Hashtable parameters, bool includeErrorAction = false)
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            parameters["Verbose"] = verbose;
        if (includeErrorAction)
        {
            object? errorAction;
            if (MyInvocation.BoundParameters.TryGetValue("ErrorAction", out errorAction))
                parameters["ErrorAction"] = errorAction;
        }
    }

    /// <summary>PS string interpolation of an arbitrary token.</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }
}
