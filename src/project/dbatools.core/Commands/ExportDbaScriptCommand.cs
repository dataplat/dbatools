#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports scripts from SQL Server Management Objects (SMO). Port of
/// public/Export-DbaScript.ps1 with its private helpers Test-ExportDirectory and
/// Get-ExportFilePath absorbed (the Get-DbatoolsConfigValue reads ride ConfigurationHost);
/// surface pinned by migration/baselines/Export-DbaScript.json (positions 0-5, no OutputType
/// attribute).
/// </summary>
[Cmdlet(VerbsData.Export, "DbaScript", SupportsShouldProcess = true)]
public sealed class ExportDbaScriptCommand : DbaBaseCmdlet
{
    /// <summary>The SMO object(s) to script, piped or bound.</summary>
    [Parameter(Position = 0, Mandatory = true, ValueFromPipeline = true)]
    public object[] InputObject { get; set; } = null!;

    /// <summary>An SMO ScriptingOptions object customizing the output (New-DbaScriptingOption).</summary>
    [Parameter(Position = 1)]
    [Alias("ScriptingOptionObject")]
    public ScriptingOptions? ScriptingOptionsObject { get; set; }

    /// <summary>The directory for auto-named output files (defaults to the Path.DbatoolsExport config).</summary>
    [Parameter(Position = 2)]
    public string? Path { get; set; }

    /// <summary>The exact output file path (overrides Path).</summary>
    [Parameter(Position = 3)]
    [Alias("OutFile", "FileName")]
    public string? FilePath { get; set; }

    /// <summary>The output encoding for Out-File.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    [ValidateSet("ASCII", "BigEndianUnicode", "Byte", "String", "Unicode", "UTF7", "UTF8", "Unknown")]
    public string Encoding { get; set; } = "UTF8";

    /// <summary>The batch separator (defaults to the Formatting.BatchSeparator config, normally GO).</summary>
    [Parameter(Position = 5)]
    public string? BatchSeparator { get; set; }

    /// <summary>Suppresses the generated header comment.</summary>
    [Parameter]
    public SwitchParameter NoPrefix { get; set; }

    /// <summary>Emits the script text to the pipeline instead of a file.</summary>
    [Parameter]
    public SwitchParameter Passthru { get; set; }

    /// <summary>Refuses to overwrite an existing file.</summary>
    [Parameter]
    public SwitchParameter NoClobber { get; set; }

    /// <summary>Appends to an existing file.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    private string _executingUser = "";
    private string _commandName = "";
    private List<string> _prefixArray = null!;
    private bool _appendToScript;
    private bool _soAppendToFile;
    private bool _soToFileOnly;
    private string? _soFileName;
    private string _eol = "";

    protected override void BeginProcessing()
    {
        // PS parameter defaults: (Get-DbatoolsConfigValue -FullName '...') evaluate at
        // invocation only when the parameter is unbound.
        if (!TestBound("Path"))
        {
            Path = GetConfigString("Path.DbatoolsExport");
        }
        if (!TestBound("BatchSeparator"))
        {
            BatchSeparator = GetConfigString("Formatting.BatchSeparator");
        }

        // PS: $null = Test-ExportDirectory -Path $Path (absorbed helper).
        // NO interrupt check here, deliberately: the source has none, and it could not work if
        // it did. Test-ExportDirectory's Stop-Function writes its flag with Set-Variable
        // -Scope 1 (the HELPER's scope), while Test-FunctionInterrupt reads -Scope 1 from the
        // COMMAND's scope — so the flag dies with the helper and begin continues.
        TestExportDirectory(Path);

        // PS: $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name (the
        // $IsLinux/$IsMacOs branch reads $env:USER).
#if NETFRAMEWORK
        _executingUser = System.Security.Principal.WindowsIdentity.GetCurrent().Name;
#else
        if (System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(System.Runtime.InteropServices.OSPlatform.Windows))
        {
            _executingUser = System.Security.Principal.WindowsIdentity.GetCurrent().Name;
        }
        else
        {
            _executingUser = Environment.GetEnvironmentVariable("USER") ?? "";
        }
#endif
        _commandName = MyInvocation.MyCommand.Name;
        _prefixArray = new List<string>();

        // PS: -Append (or -Append:$true) sets $appendToScript.
        _appendToScript = Append.ToBool();

        if (ScriptingOptionsObject is not null)
        {
            // PS: warn when ScriptBatchTerminator is combined with an empty separator.
            if (ScriptingOptionsObject.ScriptBatchTerminator && string.IsNullOrWhiteSpace(BatchSeparator))
            {
                WriteMessage(MessageLevel.Warning, "Setting ScriptBatchTerminator to true and also having BatchSeperarator as an empty or null string may produce unintended results.");
            }
            // PS: save the properties mutated in process so finally can restore them.
            _soAppendToFile = ScriptingOptionsObject.AppendToFile;
            _soToFileOnly = ScriptingOptionsObject.ToFileOnly;
            _soFileName = ScriptingOptionsObject.FileName;
        }

        _eol = Environment.NewLine;
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
        {
            return;
        }

        if (InputObject is null)
        {
            return;
        }

        foreach (object? inputElement in InputObject)
        {
            object? element = inputElement;

            // PS: $typename = $object.GetType().ToString() — method-on-null throws into
            // nothing here (no enclosing try yet): a null element makes the whole pipeline
            // fail in PS; keep the same terminating behavior.
            object? elementBase = element is PSObject wrapped ? wrapped.BaseObject : element;
            if (elementBase is null)
            {
                throw new PSInvalidOperationException("You cannot call a method on a null-valued expression.");
            }
            string typename = elementBase.GetType().ToString();

            string shorttype;
            if (typename.StartsWith("Microsoft.SqlServer."))
            {
                string[] typeParts = typename.Split('.');
                shorttype = typeParts[typeParts.Length - 1];
            }
            else
            {
                // PS: Stop-Function ... -Category InvalidData -Target $object -Continue
                StopFunction($"InputObject is of type {typename} which is not a SQL Management Object. Only SMO objects are supported.",
                    target: element,
                    category: ErrorCategory.InvalidData,
                    continueLoop: true);
                continue;
            }

            if (PsString.In(shorttype, "LinkedServer", "Credential", "Login"))
            {
                WriteMessage(MessageLevel.Warning, $"Support for {shorttype} is limited at this time. No passwords, hashed or otherwise, will be exported if they exist.");
            }

            // Just gotta add the stuff that Nic Cain added to his script
            if (PsString.Eq(shorttype, "Configuration"))
            {
                WriteMessage(MessageLevel.Warning, $"Support for {shorttype} is limited at this time.");
            }

            string? dagScript = null;
            if (PsString.Eq(shorttype, "AvailabilityGroup"))
            {
                PSObject elementPs = PSObject.AsPSObject(element!);
                bool hasDagMember = elementPs.Members["IsDistributedAvailabilityGroup"] is not null;
                if (hasDagMember && PsOps.IsTrue(GetPsValue(element, "IsDistributedAvailabilityGroup")))
                {
                    WriteMessage(MessageLevel.Verbose, $"Detected Distributed Availability Group '{PsText(GetPsValue(element, "Name"))}'. Generating T-SQL script manually as SMO scripting does not support Distributed AGs.");
                    string escapedDagName = PsText(GetPsValue(element, "Name")).Replace("]", "]]");
                    List<string> dagReplicaScripts = new List<string>();
                    object? replicas = GetPsValue(element, "AvailabilityReplicas");
                    if (replicas is not null && LanguagePrimitives.GetEnumerable(replicas) is IEnumerable replicaItems)
                    {
                        foreach (object? replica in replicaItems)
                        {
                            string availMode = PsOps.Eq(GetPsValue(replica, "AvailabilityMode"), "SynchronousCommit") ? "SYNCHRONOUS_COMMIT" : "ASYNCHRONOUS_COMMIT";
                            string seedMode = PsOps.Eq(GetPsValue(replica, "SeedingMode"), "Automatic") ? "AUTOMATIC" : "MANUAL";
                            string escapedReplicaName = PsText(GetPsValue(replica, "Name")).Replace("'", "''");
                            string escapedEndpointUrl = PsText(GetPsValue(replica, "EndpointUrl")).Replace("'", "''");
                            dagReplicaScripts.Add($"   N'{escapedReplicaName}' WITH{_eol}   ({_eol}      LISTENER_URL = N'{escapedEndpointUrl}',{_eol}      AVAILABILITY_MODE = {availMode},{_eol}      FAILOVER_MODE = MANUAL,{_eol}      SEEDING_MODE = {seedMode}{_eol}   )");
                        }
                    }
                    dagScript = $"CREATE AVAILABILITY GROUP [{escapedDagName}]{_eol}   WITH (DISTRIBUTED){_eol}   AVAILABILITY GROUP ON{_eol}" + string.Join($",{_eol}", dagReplicaScripts) + ";";
                }
                else
                {
                    WriteMessage(MessageLevel.Verbose, "Invoking .Script() as a workaround for https://github.com/dataplat/dbatools/issues/5913.");
                    try
                    {
                        // PS: $null = $InputObject.Script() — on the WHOLE ARRAY (methods do
                        // not member-enumerate), so this always fails and lands in the verbose
                        // catch; kept verbatim, latent-bug parity.
                        PSMethodInfo? scriptMethod = PSObject.AsPSObject(InputObject).Methods["Script"];
                        if (scriptMethod is null)
                        {
                            throw new PSInvalidOperationException($"Method invocation failed because [{InputObject.GetType().FullName}] does not contain a method named 'Script'.");
                        }
                        scriptMethod.Invoke();
                    }
                    catch (Exception scriptEx)
                    {
                        WriteMessage(MessageLevel.Verbose, $"Invoking .Script() failed: {scriptEx.Message}");
                    }
                }
            }

            // PS: walk $object.parent until the Server node (or null).
            object? parent = GetPsValue(element, "Parent");
            do
            {
                if (!PsOps.Eq(GetPsValue(GetPsValue(parent, "Urn"), "Type"), "Server"))
                {
                    parent = GetPsValue(parent, "Parent");
                }
            }
            while (!(PsOps.Eq(GetPsValue(GetPsValue(parent, "Urn"), "Type"), "Server") || parent is null));

            if (parent is null && PSObject.AsPSObject(element!).Members["ScriptCreate"] is null)
            {
                StopFunction($"Failed to find valid SMO server object in input: {PsText(element)}.",
                    target: element,
                    category: ErrorCategory.InvalidData,
                    continueLoop: true);
                continue;
            }

            object? server = parent;
            string serverNameForCatch = "";
            try
            {
                // PS: $server.Name.Replace('\', '$') — a null Name (parentless ScriptCreate
                // fallback) is a method-on-null failure into the catch, not an empty string.
                object? serverNameValue = GetPsValue(server, "Name");
                if (serverNameValue is null)
                {
                    throw new PSInvalidOperationException("You cannot call a method on a null-valued expression.");
                }
                serverNameForCatch = PsText(serverNameValue);
                string serverName = serverNameForCatch.Replace('\\', '$');

                object? serverBase = server is PSObject serverWrapped ? serverWrapped.BaseObject : server;
                Scripter scripter = new Scripter(serverBase as Server);
                bool scriptBatchTerminator = false;
                if (ScriptingOptionsObject is not null)
                {
                    scripter.Options = ScriptingOptionsObject;
                    scriptBatchTerminator = ScriptingOptionsObject.ScriptBatchTerminator;
                }

                string scriptPath;
                if (!Passthru.ToBool())
                {
                    scriptPath = GetExportFilePath(TestBound("Path") ? Path : null, TestBound("FilePath") ? FilePath : null, "sql", serverName);
                }
                else
                {
                    scriptPath = "Console";
                }

                string? prefix;
                if (NoPrefix.ToBool())
                {
                    prefix = null;
                }
                else
                {
                    // PS: $(Get-Date) interpolation renders the INVARIANT-culture general text
                    // (lab-proven: "07/11/2026 12:54:11" — LanguagePrimitives conversion).
                    prefix = $"/*{_eol}\tCreated by {_executingUser} using dbatools {_commandName} for objects on {serverName} at {PsText(DateTime.Now)}{_eol}\tSee https://dbatools.io/{_commandName} for more information{_eol}*/";
                }

                if (Passthru.ToBool())
                {
                    if (prefix is not null)
                    {
                        // PS: $prefix | Out-String — the emitted string carries ONE trailing newline.
                        WriteObject(prefix + _eol);
                    }
                }
                else
                {
                    if (!ListContains(_prefixArray, scriptPath))
                    {
                        if (ProviderPathExists(scriptPath) && NoClobber.ToBool())
                        {
                            StopFunction("File already exists. If you want to overwrite it remove the -NoClobber parameter. If you want to append data, please Use -Append parameter.",
                                target: scriptPath,
                                continueLoop: true);
                            continue;
                        }
                        // Only at the first output we use the passed variables Append & NoClobber. For this execution the next ones need to use -Append
                        // Empty $prefix will clean file in case $appendToScript is not set.
                        WriteMessage(MessageLevel.Verbose, $"Writing (maybe empty) prefix to file {scriptPath}");
                        WriteOutFile(scriptPath, prefix is null ? new List<string?>() : new List<string?> { prefix }, _appendToScript, NoClobber.ToBool());
                        _prefixArray.Add(scriptPath);
                    }
                }

                if (ShouldProcess(Environment.GetEnvironmentVariable("COMPUTERNAME") ?? "", $"Exporting {PsText(element)} from {PsText(server)} to {scriptPath}"))
                {
                    WriteMessage(MessageLevel.Verbose, $"Exporting {PsText(element)}");

                    if (Passthru.ToBool())
                    {
                        if (ScriptingOptionsObject is not null)
                        {
                            ScriptingOptionsObject.FileName = null;
                            foreach (string scriptPartRaw in EnumScriptParts(dagScript, scripter, elementBase))
                            {
                                string scriptPart = scriptPartRaw;
                                if (scriptBatchTerminator)
                                {
                                    scriptPart = $"{scriptPart}{_eol}{BatchSeparator}{_eol}";
                                }
                                WriteObject(scriptPart + _eol);
                            }
                        }
                        else
                        {
                            foreach (string scriptPartRaw in EnumScriptParts(dagScript, scripter, elementBase))
                            {
                                string scriptPart = scriptPartRaw;
                                if (PsOps.IsTrue(BatchSeparator))
                                {
                                    scriptPart = $"{scriptPart}{_eol}{BatchSeparator}{_eol}";
                                }
                                else
                                {
                                    scriptPart = $"{scriptPart}{_eol}";
                                }
                                WriteObject(scriptPart + _eol);
                            }
                        }
                    }
                    else
                    {
                        if (ScriptingOptionsObject is not null)
                        {
                            if (scriptBatchTerminator)
                            {
                                // Option to script batch terminator via ScriptingOptionsObject needs to write to file only
                                ScriptingOptionsObject.AppendToFile = true;
                                ScriptingOptionsObject.ToFileOnly = true;
                                if (!PsOps.IsTrue(ScriptingOptionsObject.FileName))
                                {
                                    ScriptingOptionsObject.FileName = scriptPath;
                                }
                                if (dagScript is not null)
                                {
                                    WriteOutFile(ScriptingOptionsObject.FileName, new List<string?> { $"{dagScript}{_eol}{BatchSeparator}{_eol}" }, append: true, noClobber: false);
                                }
                                else
                                {
                                    // PS: $null = $object.Script($ScriptingOptionsObject)
                                    InvokeScriptWithOptions(element!, ScriptingOptionsObject);
                                }
                            }
                            else
                            {
                                ScriptingOptionsObject.FileName = null;
                                List<string?> scriptInFull = new List<string?>();
                                foreach (string scriptPartRaw in EnumScriptParts(dagScript, scripter, elementBase))
                                {
                                    if (PsOps.IsTrue(BatchSeparator))
                                    {
                                        scriptInFull.Add($"{scriptPartRaw}{_eol}{BatchSeparator}{_eol}");
                                    }
                                    else
                                    {
                                        scriptInFull.Add($"{scriptPartRaw}{_eol}");
                                    }
                                }
                                WriteOutFile(scriptPath, scriptInFull, append: true, noClobber: false);
                            }
                        }
                        else
                        {
                            List<string?> scriptInFull = new List<string?>();
                            foreach (string scriptPartRaw in EnumScriptParts(dagScript, scripter, elementBase))
                            {
                                if (PsOps.IsTrue(BatchSeparator))
                                {
                                    scriptInFull.Add($"{scriptPartRaw}{_eol}{BatchSeparator}{_eol}");
                                }
                                else
                                {
                                    scriptInFull.Add($"{scriptPartRaw}{_eol}");
                                }
                            }
                            WriteOutFile(scriptPath, scriptInFull, append: true, noClobber: false);
                        }
                    }

                    if (!Passthru.ToBool())
                    {
                        WriteMessage(MessageLevel.Verbose, $"Exported {PsText(element)} on {PsText(GetPsValue(server, "Name"))} to {scriptPath}");
                        // PS: Get-ChildItem -Path $scriptPath — emits the PROVIDER-DECORATED
                        // FileInfo (PSPath/PSDrive/... note properties); a missing path is a
                        // NON-terminating ObjectNotFound error, not a catch-bound failure.
                        try
                        {
                            foreach (PSObject childItem in SessionState.InvokeProvider.ChildItem.Get(scriptPath, false))
                            {
                                WriteObject(childItem);
                            }
                        }
                        catch (ItemNotFoundException notFound)
                        {
                            WriteError(new ErrorRecord(notFound, "PathNotFound", ErrorCategory.ObjectNotFound, scriptPath));
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                // PS: $message = $_.Exception.InnerException.InnerException.InnerException.Message
                //     (falls back to the exception itself when the chain is short).
                string? message = ex.InnerException?.InnerException?.InnerException?.Message;
                if (string.IsNullOrEmpty(message))
                {
                    message = ex.ToString();
                }
                StopFunction($"Failure on {serverNameForCatch} | {message}", target: server);
            }
            finally
            {
                // Reset the changed values of the $ScriptingOptionsObject in case it is reused later
                if (ScriptingOptionsObject is not null)
                {
                    ScriptingOptionsObject.AppendToFile = _soAppendToFile;
                    ScriptingOptionsObject.ToFileOnly = _soToFileOnly;
                    ScriptingOptionsObject.FileName = _soFileName;
                }
            }
        }
    }

    /// <summary>PS: @(if ($dagScript) { $dagScript } else { $scripter.EnumScript($object) }).</summary>
    private static IEnumerable<string> EnumScriptParts(string? dagScript, Scripter scripter, object smoObject)
    {
        if (dagScript is not null)
        {
            yield return dagScript;
            yield break;
        }
        foreach (string? part in scripter.EnumScript(new SqlSmoObject[] { (SqlSmoObject)smoObject }))
        {
            yield return part ?? "";
        }
    }

    /// <summary>PS: $object.Script($ScriptingOptionsObject) via the member binder.</summary>
    private static void InvokeScriptWithOptions(object element, ScriptingOptions options)
    {
        PSMethodInfo? method = PSObject.AsPSObject(element).Methods["Script"];
        if (method is null)
        {
            object baseTarget = element is PSObject wrapped ? wrapped.BaseObject : element;
            throw new PSInvalidOperationException($"Method invocation failed because [{baseTarget.GetType().FullName}] does not contain a method named 'Script'.");
        }
        method.Invoke(options);
    }

    /// <summary>
    /// Absorbed private helper Test-ExportDirectory: create the directory when missing;
    /// stop when the path exists but is not a directory.
    /// </summary>
    private void TestExportDirectory(string? path)
    {
        // PS provider semantics: relative paths resolve against the POWERSHELL location, not
        // the process working directory.
        string resolved;
        try
        {
            resolved = SessionState.Path.GetUnresolvedProviderPathFromPSPath(path ?? "");
        }
        catch
        {
            resolved = path ?? "";
        }
        if (!ProviderPathExists(path))
        {
            // PS: New-Item -ItemType Directory supports ShouldProcess, and $WhatIfPreference
            // propagates from the SupportsShouldProcess caller into the helper's scope — so
            // -WhatIf creates nothing. Directory.CreateDirectory has no such gate; without
            // this the port creates the directory the source only reported.
            if (!ShouldProcess(resolved, "Create Directory"))
            {
                return;
            }
            try
            {
                Directory.CreateDirectory(resolved);
            }
            catch (Exception ex)
            {
                // PS: a failing New-Item is statement-terminating in begin (error record,
                // processing continues) — surface the record and proceed.
                WriteError(new ErrorRecord(ex, "Export-DbaScript", ErrorCategory.WriteError, path));
            }
        }
        else
        {
            // PS: (Get-Item $Path -ErrorAction Ignore) -isnot [System.IO.DirectoryInfo] —
            // Get-Item expands wildcards; a single directory match passes, anything else
            // (file, multi-match array, failed get) stops.
            bool isDirectory = false;
            try
            {
                System.Collections.ObjectModel.Collection<PSObject> matches = SessionState.InvokeProvider.Item.Get(path);
                isDirectory = matches.Count == 1 && matches[0].BaseObject is DirectoryInfo;
            }
            catch
            {
                isDirectory = false;
            }
            if (!isDirectory)
            {
                // interruptCallerScope: false — the source's stop flag lands in the helper's
                // scope, so friendly mode is warn-and-continue; EnableException still throws.
                StopFunction($"Path ({path}) must be a directory", interruptCallerScope: false);
            }
        }
    }

    /// <summary>
    /// Absorbed private helper Get-ExportFilePath (the branches this caller reaches):
    /// a bound -FilePath wins verbatim; otherwise the path (bound or config) gains an
    /// auto-generated "server-timestamp-script.sql" name using the Formatting.UFormat config.
    /// </summary>
    private string GetExportFilePath(string? boundPath, string? boundFilePath, string type, string serverName)
    {
        if (PsOps.IsTrue(boundFilePath))
        {
            return SessionState.Path.GetUnresolvedProviderPathFromPSPath(boundFilePath);
        }

        string? path = boundPath;
        if (!PsOps.IsTrue(path))
        {
            path = GetConfigString("Path.DbatoolsExport");
        }

        string lowerType = type.ToLower();

        if (!PsOps.IsTrue(serverName))
        {
            serverName = "sqlinstance";
        }
        serverName = serverName.Replace('\\', '$');

        string prefix = serverName;

        // PS: (Get-Date -uformat (Get-DbatoolsConfigValue -FullName 'Formatting.UFormat')) —
        // the config default is %Y%m%d%H%M%S.
        string timenow = FormatUFormat(DateTime.Now, GetConfigString("Formatting.UFormat") ?? "%Y%m%d%H%M%S");

        // PS: (Get-PSCallStack)[1].Command.Replace("Export-Dba", "").ToLower() — the absorbed
        // helper's caller is always this cmdlet, so the caller token is the constant "script".
        string caller = "script";

        string finalpath = System.IO.Path.Combine(path ?? "", $"{prefix}-{timenow}-{caller}.{lowerType}");
        return SessionState.Path.GetUnresolvedProviderPathFromPSPath(finalpath);
    }

    /// <summary>Get-Date -UFormat token subset covering the shipped Formatting.UFormat values.
    /// Only Y y m d H M S and %% are implemented (the default config is %Y%m%d%H%M%S). Any other
    /// token is emitted literally with its % - which diverges from Get-Date -UFormat, both for
    /// tokens PowerShell knows (%Z, %A, %j expand there) and for ones it does not (%Q renders as
    /// "Q" there, the % dropped). Reachable only through a customized Formatting.UFormat.</summary>
    internal static string FormatUFormat(DateTime moment, string format)
    {
        StringBuilder output = new StringBuilder();
        for (int i = 0; i < format.Length; i++)
        {
            if (format[i] != '%' || i + 1 >= format.Length)
            {
                output.Append(format[i]);
                continue;
            }
            i++;
            switch (format[i])
            {
                case 'Y': output.Append(moment.ToString("yyyy", CultureInfo.InvariantCulture)); break;
                case 'y': output.Append(moment.ToString("yy", CultureInfo.InvariantCulture)); break;
                case 'm': output.Append(moment.ToString("MM", CultureInfo.InvariantCulture)); break;
                case 'd': output.Append(moment.ToString("dd", CultureInfo.InvariantCulture)); break;
                case 'H': output.Append(moment.ToString("HH", CultureInfo.InvariantCulture)); break;
                case 'M': output.Append(moment.ToString("mm", CultureInfo.InvariantCulture)); break;
                case 'S': output.Append(moment.ToString("ss", CultureInfo.InvariantCulture)); break;
                case '%': output.Append('%'); break;
                default:
                    output.Append('%');
                    output.Append(format[i]);
                    break;
            }
        }
        return output.ToString();
    }

    /// <summary>
    /// PS: Out-File — writes each item followed by a newline with the EDITION'S encoding
    /// name semantics (5.1: utf8 carries a BOM, String/Unknown mean Unicode; 7+: utf8 has no
    /// BOM and Byte/String/Unknown are invalid names). An invalid name throws into the
    /// enclosing try exactly like Out-File's parameter failure.
    /// </summary>
    private void WriteOutFile(string? path, List<string?> lines, bool append, bool noClobber)
    {
        Encoding encoding = ResolveOutFileEncoding(Encoding);
        // PS: Out-File -FilePath resolves relative paths against the PowerShell location.
        string target;
        try
        {
            target = SessionState.Path.GetUnresolvedProviderPathFromPSPath(path ?? "");
        }
        catch
        {
            target = path ?? "";
        }
        // PS: Out-File itself supports ShouldProcess — under -WhatIf it prints
        // 'What if: Performing the operation "Output to File" on target "<path>".' and
        // writes nothing (lab-proven: the prefix write outside the main gate no-ops).
        if (!ShouldProcess(target, "Output to File"))
        {
            return;
        }
        if (noClobber && !append && File.Exists(target))
        {
            throw new IOException($"The file '{target}' already exists.");
        }
        StringBuilder content = new StringBuilder();
        foreach (string? line in lines)
        {
            content.Append(line);
            content.Append(_eol);
        }
        if (append && File.Exists(target))
        {
            File.AppendAllText(target, content.ToString(), encoding);
        }
        else
        {
            File.WriteAllText(target, content.ToString(), encoding);
        }
    }

    private static Encoding ResolveOutFileEncoding(string name)
    {
#if NETFRAMEWORK
        if (name.Equals("ASCII", StringComparison.OrdinalIgnoreCase)) { return System.Text.Encoding.ASCII; }
        if (name.Equals("BigEndianUnicode", StringComparison.OrdinalIgnoreCase)) { return System.Text.Encoding.BigEndianUnicode; }
        if (name.Equals("Unicode", StringComparison.OrdinalIgnoreCase)) { return System.Text.Encoding.Unicode; }
#pragma warning disable SYSLIB0001
        if (name.Equals("UTF7", StringComparison.OrdinalIgnoreCase)) { return System.Text.Encoding.UTF7; }
#pragma warning restore SYSLIB0001
        if (name.Equals("UTF8", StringComparison.OrdinalIgnoreCase)) { return new UTF8Encoding(true); }
        if (name.Equals("String", StringComparison.OrdinalIgnoreCase)) { return System.Text.Encoding.Unicode; }
        if (name.Equals("Unknown", StringComparison.OrdinalIgnoreCase)) { return System.Text.Encoding.Unicode; }
        // 'Byte' is in the ValidateSet but Windows PowerShell Out-File rejects it.
        throw new PSArgumentException($"Cannot validate argument on parameter 'Encoding'. The argument \"{name}\" does not belong to the set \"unknown;string;unicode;bigendianunicode;utf8;utf7;utf32;ascii;default;oem\" specified by the ValidateSet attribute.");
#else
        if (name.Equals("ASCII", StringComparison.OrdinalIgnoreCase)) { return System.Text.Encoding.ASCII; }
        if (name.Equals("BigEndianUnicode", StringComparison.OrdinalIgnoreCase)) { return System.Text.Encoding.BigEndianUnicode; }
        if (name.Equals("Unicode", StringComparison.OrdinalIgnoreCase)) { return System.Text.Encoding.Unicode; }
#pragma warning disable SYSLIB0001
        if (name.Equals("UTF7", StringComparison.OrdinalIgnoreCase)) { return System.Text.Encoding.UTF7; }
#pragma warning restore SYSLIB0001
        if (name.Equals("UTF8", StringComparison.OrdinalIgnoreCase)) { return new UTF8Encoding(false); }
        // PowerShell 7's Out-File rejects Byte/String/Unknown encoding names.
        throw new PSArgumentException($"Cannot process argument transformation on parameter 'Encoding'. Cannot convert value \"{name}\" to type \"System.Text.Encoding\".");
#endif
    }

    /// <summary>PS: Test-Path through the provider (wildcards honored; failures read false).</summary>
    private bool ProviderPathExists(string? path)
    {
        if (string.IsNullOrEmpty(path))
        {
            return false;
        }
        try
        {
            return SessionState.InvokeProvider.Item.Exists(path);
        }
        catch (Exception ex)
        {
            WriteError(new ErrorRecord(ex, "Export-DbaScript", ErrorCategory.ObjectNotFound, path));
            return false;
        }
    }

    private string? GetConfigString(string key)
    {
        object? raw = ConnectionService.GetConfigurationValue(key);
        if (raw is null)
        {
            return null;
        }
        // PS: the [string] parameter conversion is the language conversion (invariant
        // numerics), not a current-culture ToString.
        return (string)LanguagePrimitives.ConvertTo(raw, typeof(string), CultureInfo.InvariantCulture);
    }

    /// <summary>PS dot-access (null-safe, binder unwrap for non-bag PSObjects).</summary>
    private static object? GetPsValue(object? item, string name)
    {
        if (item is null)
        {
            return null;
        }
        PSPropertyInfo? property = PSObject.AsPSObject(item).Properties[name];
        if (property is null)
        {
            return null;
        }
        object? value = property.Value;
        if (value is PSObject wrapped && wrapped.BaseObject is not PSCustomObject)
        {
            return wrapped.BaseObject;
        }
        return value;
    }

    /// <summary>
    /// PS expandable-string rendering: LanguagePrimitives conversion (invariant numerics,
    /// bag rendering), enumerables joined with the session $OFS, null empty.
    /// </summary>
    private string PsText(object? value)
    {
        return Dataplat.Dbatools.Utility.PowerShellText.Expand(value, SessionState);
    }

    /// <summary>PS: $prefixArray -notcontains $scriptPath (case-insensitive -contains).</summary>
    private static bool ListContains(List<string> list, string value)
    {
        foreach (string entry in list)
        {
            if (PsString.Eq(entry, value))
            {
                return true;
            }
        }
        return false;
    }
}
