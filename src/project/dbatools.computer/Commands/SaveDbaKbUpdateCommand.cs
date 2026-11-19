#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Net;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Downloads Microsoft KB updates to local storage. Port of public/Save-DbaKbUpdate.ps1; surface
/// pinned by migration/baselines/Save-DbaKbUpdate.json.
/// </summary>
[Cmdlet(VerbsData.Save, "DbaKbUpdate")]
public sealed class SaveDbaKbUpdateCommand : DbaBaseCmdlet
{
    /// <summary>The KB article number(s) to download, with or without the KB prefix.</summary>
    [Parameter(Position = 0)]
    public string[]? Name { get; set; }

    /// <summary>The directory downloaded KB files are saved to; defaults to the current directory.</summary>
    [Parameter(Position = 1)]
    public string Path { get; set; } = ".";

    /// <summary>An exact filename and path for the downloaded file, overriding the server-provided name.</summary>
    [Parameter(Position = 2)]
    public string? FilePath { get; set; }

    /// <summary>The CPU architecture of the files to download.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    [ValidateSet("x64", "x86", "ia64", "All")]
    public string Architecture { get; set; } = "x64";

    /// <summary>Filters downloads to a specific three-letter language code (e.g. enu).</summary>
    [Parameter(Position = 4)]
    public string? Language { get; set; }

    /// <summary>Pipeline input from Get-DbaKbUpdate.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public object[]? InputObject { get; set; }

    /// <summary>Forces Invoke-WebRequest instead of Start-BitsTransfer (non-interactive contexts).</summary>
    [Parameter]
    public SwitchParameter UseWebRequest { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // PS: $PSBoundParameters.FilePath etc. - the BOUND VALUE's truthiness, not just presence.
        object? boundFilePath = MyInvocation.BoundParameters.TryGetValue("FilePath", out object? fpv) ? fpv : null;
        object? boundInputObject = MyInvocation.BoundParameters.TryGetValue("InputObject", out object? iov) ? iov : null;
        object? boundName = MyInvocation.BoundParameters.TryGetValue("Name", out object? nv) ? nv : null;

        // PS: if ($Name.Count -gt 1 -and $PSBoundParameters.FilePath) - Stop-Function + return
        // (non-EE: warn and end THIS record; EE: throw).
        if ((Name?.Length ?? 0) > 1 && LanguagePrimitives.IsTrue(boundFilePath))
        {
            StopFunction("You can only specify one KB when using FilePath", continueLoop: true);
            return;
        }

        if (LanguagePrimitives.Equals(Architecture, "All", ignoreCase: true) && LanguagePrimitives.IsTrue(boundFilePath))
        {
            StopFunction("You can only specify one Architecture when using FilePath", continueLoop: true);
            return;
        }

        if (!LanguagePrimitives.IsTrue(boundInputObject) && !LanguagePrimitives.IsTrue(boundName))
        {
            StopFunction("You must specify a KB name or pipe in results from Get-DbaKbUpdate", continueLoop: true);
            return;
        }

        // PS: foreach ($kb in $Name) { $InputObject += Get-DbaKbUpdate -Name $kb }
        List<object?> inputObjects = new();
        if (InputObject is not null)
        {
            foreach (object? item in InputObject)
            {
                inputObjects.Add(item);
            }
        }
        foreach (string kb in Name ?? Array.Empty<string>())
        {
            Hashtable splatGetKb = new Hashtable { { "Name", kb } };
            foreach (PSObject item in NestedCommand.Invoke(this, "Get-DbaKbUpdate", splatGetKb))
            {
                inputObjects.Add(item);
            }
        }

        // PS: foreach ($link in $InputObject.Link) - engine member enumeration over the Link
        // property values (unwrapping array-valued Links exactly as PS does).
        // The explicit wrapper array matters: a bare object[] argument would be UNPACKED by the
        // params-array binding and only the FIRST input object would reach $__i.
        Collection<PSObject> linkValues = InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__i) $__i.Link"), null, new object?[] { inputObjects.ToArray() });

        foreach (PSObject? linkItem in linkValues)
        {
            string link = LanguagePrimitives.ConvertTo<string>(linkItem) ?? string.Empty;

            // PS: if ($Architecture -ne "All" -and $link -notmatch "$($Architecture)[-_]") { continue }
            if (!LanguagePrimitives.Equals(Architecture, "All", ignoreCase: true)
                && !System.Text.RegularExpressions.Regex.IsMatch(link, $"{Architecture}[-_]", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            {
                continue;
            }
            // PS: if ($Language -and $link -notmatch "-$($Language)_") { continue }
            if (!string.IsNullOrEmpty(Language)
                && !System.Text.RegularExpressions.Regex.IsMatch(link, $"-{Language}_", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            {
                continue;
            }

            // PS: $fileName = Split-Path -Path $link -Leaf (the engine's own semantics for URLs).
            Collection<PSObject> leafResult = InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__p) Split-Path -Path $__p -Leaf"), null, link);
            string fileName = leafResult.Count > 0 ? LanguagePrimitives.ConvertTo<string>(leafResult[0]) ?? string.Empty : string.Empty;

            string file = LanguagePrimitives.IsTrue(boundFilePath)
                ? FilePath!
                : $"{Path}{System.IO.Path.DirectorySeparatorChar}{fileName}";

            // PS: if (-not $UseWebRequest -and (Get-Command Start-BitsTransfer -ErrorAction Ignore))
            bool bitsAvailable = false;
            if (!UseWebRequest.ToBool())
            {
                using PowerShell probe = PowerShell.Create(RunspaceMode.CurrentRunspace);
                probe.AddCommand("Get-Command")
                    .AddParameter("Name", "Start-BitsTransfer")
                    .AddParameter("ErrorAction", "Ignore");
                Collection<PSObject> found = probe.Invoke();
                bitsAvailable = found.Count > 0 && LanguagePrimitives.IsTrue(found[0]);
            }

            if (bitsAvailable)
            {
                try
                {
                    using PowerShell bits = PowerShell.Create(RunspaceMode.CurrentRunspace);
                    bits.AddCommand("Start-BitsTransfer")
                        .AddParameter("Source", link)
                        .AddParameter("Destination", file)
                        .AddParameter("ErrorAction", "Stop");
                    bits.Invoke();
                    if (bits.Streams.Error.Count > 0)
                    {
                        ErrorRecord record = bits.Streams.Error[0];
                        throw new RuntimeException(record.Exception?.Message ?? "Start-BitsTransfer failed", record.Exception, record);
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    // PS: Write-Message -Level Verbose "Start-BitsTransfer failed, falling back to
                    //     Invoke-WebRequest: $PSItem" then the progress-wrapped fallback; a fallback
                    //     failure is TERMINATING (-ErrorAction Stop outside any try).
                    string detail = rex.ErrorRecord is not null ? LanguagePrimitives.ConvertTo<string>(rex.ErrorRecord) ?? rex.Message : rex.Message;
                    WriteMessage(MessageLevel.Verbose, $"Start-BitsTransfer failed, falling back to Invoke-WebRequest: {detail}");
                    WriteProgressRecord($"Downloading {fileName}", completed: false);
                    InvokeTlsWebRequest(link, file);
                    WriteProgressRecord($"Downloading {fileName}", completed: true);
                }
            }
            else
            {
                WriteProgressRecord($"Downloading {fileName}", completed: false);
                InvokeTlsWebRequest(link, file);
                WriteProgressRecord($"Downloading {fileName}", completed: true);
            }

            // PS: if (Test-Path -Path $file) { Get-ChildItem -Path $file } - the FileInfo output
            // comes from the REAL Get-ChildItem.
            using PowerShell emit = PowerShell.Create(RunspaceMode.CurrentRunspace);
            emit.AddScript("param($__f) if (Test-Path -Path $__f) { Get-ChildItem -Path $__f }", true);
            emit.AddParameter("__f", file);
            foreach (PSObject item in emit.Invoke())
            {
                WriteObject(item);
            }
        }
    }

    // PS private/functions/Invoke-TlsWebRequest.ps1 called as `-Uri $link -OutFile $file
    // -ErrorAction Stop`: TLS augmentation, config-gated auto-proxy pickup, progress-suppressed
    // Invoke-WebRequest; the TLS restore line sits AFTER the request, so a terminating failure
    // deliberately skips it (process-global state, quirk preserved).
    private void InvokeTlsWebRequest(string uri, string outFile)
    {
        SecurityProtocolType currentVersionTls = ServicePointManager.SecurityProtocol;
        int currentSupportable = Math.Max((int)currentVersionTls, (int)SecurityProtocolType.Tls);
        foreach (object value in Enum.GetValues(typeof(SecurityProtocolType)))
        {
            if ((int)value > currentSupportable)
            {
                ServicePointManager.SecurityProtocol |= (SecurityProtocolType)value;
            }
        }

        // PS: $Args -contains "-Proxy" - this call site never passes one.
        bool hasConfiguredProxy = false;
        IWebProxy? defaultWebProxy = WebRequest.DefaultWebProxy;
        if (defaultWebProxy is not null)
        {
            PSObject adapted = PSObject.AsPSObject(defaultWebProxy);
            PSPropertyInfo? addressProperty = adapted.Properties["Address"];
            if (addressProperty is not null && LanguagePrimitives.IsTrue(addressProperty.Value))
            {
                hasConfiguredProxy = true;
            }
            else if (LanguagePrimitives.IsTrue(adapted.Properties["Credentials"]?.Value))
            {
                hasConfiguredProxy = true;
            }
        }

        if (!GetConfigTruthy("commands.invoke-tlswebrequest.disableautoproxy") && !hasConfiguredProxy)
        {
            IWebProxy? systemProxy = WebRequest.GetSystemWebProxy();
            if (systemProxy is not null)
            {
                WebRequest.DefaultWebProxy = systemProxy;
                WebRequest.DefaultWebProxy.Credentials = CredentialCache.DefaultNetworkCredentials;
            }
        }

        object? saved = SessionState.PSVariable.GetValue("ProgressPreference");
        SessionState.PSVariable.Set("ProgressPreference", ActionPreference.SilentlyContinue);
        try
        {
            using PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace);
            shell.AddCommand("Invoke-WebRequest")
                .AddParameter("Uri", uri)
                .AddParameter("OutFile", outFile)
                .AddParameter("ErrorAction", "Stop");
            shell.Invoke();
            if (shell.Streams.Error.Count > 0)
            {
                ErrorRecord record = shell.Streams.Error[0];
                throw new RuntimeException(record.Exception?.Message ?? "Invoke-WebRequest failed", record.Exception, record);
            }
        }
        finally
        {
            SessionState.PSVariable.Set("ProgressPreference", saved ?? ActionPreference.Continue);
        }

        // PS: restore SecurityProtocol AFTER a successful request.
        ServicePointManager.SecurityProtocol = currentVersionTls;
    }

    // PS: Write-Progress -Activity "Downloading $fileName" -Id 1 [-Completed]
    private void WriteProgressRecord(string activity, bool completed)
    {
        // Write-Progress without -Status defaults the record's StatusDescription to "Processing".
        ProgressRecord record = new(1, activity, "Processing");
        if (completed)
        {
            record.RecordType = ProgressRecordType.Completed;
        }
        WriteProgress(record);
    }

    private static bool GetConfigTruthy(string fullName)
    {
        if (Dataplat.Dbatools.Configuration.ConfigurationHost.Configurations.TryGetValue(fullName, out Dataplat.Dbatools.Configuration.Config? config) && config != null && config.Value != null)
        {
            try
            {
                return LanguagePrimitives.IsTrue(config.Value);
            }
            catch
            {
                // malformed configuration values count as unset, like Get-DbatoolsConfigValue -Fallback
            }
        }
        return false;
    }
}
