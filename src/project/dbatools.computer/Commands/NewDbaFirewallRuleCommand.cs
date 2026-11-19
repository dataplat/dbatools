#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates Windows firewall rules for SQL Server instances, Browser, DAC and DatabaseMirroring on
/// the target computer. Port of public/New-DbaFirewallRule.ps1; surface pinned by
/// migration/baselines/New-DbaFirewallRule.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaFirewallRule", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed class NewDbaFirewallRuleCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance(s).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = Array.Empty<DbaInstanceParameter>();

    /// <summary>Alternate Windows credential for the target computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Which rule types to create. When omitted, Engine (+ Browser/DAC as needed) are created.</summary>
    [Parameter(Position = 2)]
    [ValidateSet("Engine", "Browser", "DAC", "DatabaseMirroring")]
    public string[]? Type { get; set; }

    /// <summary>Program (default, targets the executable) or Port (targets TCP/UDP ports).</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    [ValidateSet("Program", "Port")]
    public string RuleType { get; set; } = "Program";

    /// <summary>Extra New-NetFirewallRule settings; Name/DisplayName/Group are reserved and removed.</summary>
    [Parameter(Position = 4)]
    public Hashtable? Configuration { get; set; }

    /// <summary>Delete and recreate a rule that already exists.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - it has no ParameterSetName so it belongs to
    // __AllParameterSets, matching the baseline; never redeclared.

    // Verbatim Invoke-Command2 scriptblock: creates the rule via New-NetFirewallRule (splatting the
    // config passed as $args[0], honoring $args[1] as -Force) and returns an envelope.
    private const string CreateScript = @"
            # This scriptblock will be processed by Invoke-Command2.
            $firewallRuleParameters = $args[0]
            $force = $args[1]

            try {
                if (-not (Get-Command -Name New-NetFirewallRule -ErrorAction SilentlyContinue)) {
                    throw 'The module NetSecurity with the command New-NetFirewallRule is missing on the target computer, so New-DbaFirewallRule is not supported.'
                }
                $successful = $true
                if ($force) {
                    $null = Remove-NetFirewallRule -Name $firewallRuleParameters.Name -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                }
                $cimInstance = New-NetFirewallRule @firewallRuleParameters -WarningVariable warn -ErrorVariable err -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                if ($warn.Count -gt 0) {
                    $successful = $false
                } else {
                    # Change from an empty System.Collections.ArrayList to $null for better readability
                    $warn = $null
                }
                if ($err.Count -gt 0) {
                    $successful = $false
                } else {
                    # Change from an empty System.Collections.ArrayList to $null for better readability
                    $err = $null
                }
                [PSCustomObject]@{
                    Successful  = $successful
                    CimInstance = $cimInstance
                    Warning     = $warn
                    Error       = $err
                    Exception   = $null
                }
            } catch {
                [PSCustomObject]@{
                    Successful  = $false
                    CimInstance = $null
                    Warning     = $null
                    Error       = $null
                    Exception   = $_
                }
            }";

    // Verbatim Invoke-Command2 -Raw scriptblock: reads the last DAC listener line from ERRORLOG.
    private const string DacScript = @"
                        Get-Content -Path $args[0] |
                            Select-String -Pattern 'Dedicated admin connection support was established for listening.+' |
                            Select-Object -Last 1 |
                            ForEach-Object { $_.Matches.Value }";

    private static readonly string[] DisplaySet = { "ComputerName", "InstanceName", "SqlInstance", "DisplayName", "Type", "Successful", "Status", "Protocol", "LocalPort", "Program" };

    // PS -match is case-insensitive; sqlservr.exe / sqlbrowser.exe path extraction, $Matches[1] = group 1.
    private static readonly Regex EngineProgramRegex = new Regex("^\"?(.+sqlservr\\.exe)(?:\\s|\"|$)", RegexOptions.IgnoreCase);
    private static readonly Regex BrowserProgramRegex = new Regex("^\"?(.+sqlbrowser\\.exe)(?:\\s|\"|$)", RegexOptions.IgnoreCase);
    private static readonly Regex DacPortRegex = new Regex("^.* (\\d+).$");

    // Holds a rule to be created: its Type, InstanceName/SqlInstance for the output, and the config bag
    // that gets splatted into New-NetFirewallRule and emitted as RuleConfig.
    private sealed class RuleSpec
    {
        public string Type = string.Empty;
        public object? InstanceName;
        public object? SqlInstance;
        public Hashtable Config = new Hashtable(NewDbaFirewallRuleCommand.NewConfigComparer());   // edition-appropriate, current-culture per instance; always replaced via NewConfig()
    }

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // PS begin: strip the reserved keys from Configuration once.
        if (Configuration is not null)
        {
            foreach (string notAllowedKey in new[] { "Name", "DisplayName", "Group" })
            {
                if (Configuration.ContainsKey(notAllowedKey))
                {
                    WriteMessage(MessageLevel.Verbose, $"Key {notAllowedKey} is not allowed in Configuration and will be removed.");
                    Configuration.Remove(notAllowedKey);
                }
            }
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (instance is null)
            {
                continue;
            }

            List<RuleSpec> rules = new();
            bool browserNeeded = false;
            bool typeBound = Type is not null && Type.Length > 0;
            bool browserOptional = !typeBound;

            // ===== Create rule for instance (Engine) =====
            if (!typeBound || ContainsType("Engine"))
            {
                Hashtable config = NewConfig();
                config["Group"] = "SQL Server";
                config["Enabled"] = "True";
                config["Direction"] = "Inbound";
                config["Protocol"] = "TCP";

                object? engineSqlInstance;
                if (string.Equals(instance.InstanceName, "MSSQLSERVER", StringComparison.OrdinalIgnoreCase))
                {
                    config["DisplayName"] = "SQL Server default instance";
                    config["Name"] = "SQL Server default instance";
                    engineSqlInstance = instance.ComputerName;
                }
                else
                {
                    config["DisplayName"] = $"SQL Server instance {instance.InstanceName}";
                    config["Name"] = $"SQL Server instance {instance.InstanceName}";
                    engineSqlInstance = instance.ComputerName + "\\" + instance.InstanceName;
                    browserNeeded = true;
                }

                // Get information about IP addresses for LocalPort.
                List<PSObject> tcpIpAddresses = new();
                try
                {
                    Hashtable netSplat = new()
                    {
                        { "SqlInstance", instance },
                        { "Credential", Credential },
                        { "OutputType", "TcpIpAddresses" },
                        { "EnableException", true }
                    };
                    foreach (PSObject r in NestedCommand.Invoke(this, "Get-DbaNetworkConfiguration", netSplat))
                    {
                        if (r is not null) { tcpIpAddresses.Add(r); }
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    StopFunction("Failed.", target: instance, errorRecord: rex.ErrorRecord, continueLoop: true);
                    continue;
                }
                catch (Exception ex)
                {
                    StopFunction("Failed.", target: instance, exception: ex, continueLoop: true);
                    continue;
                }

                if (tcpIpAddresses.Count > 1)
                {
                    // I would have to test this, so I better not support this in the first version.
                    StopFunction($"SQL Server instance {instance} listens on more than one IP addresses. This is currently not supported by this command.", continueLoop: true);
                    continue;
                }

                string? tcpPort = tcpIpAddresses.Count > 0 ? GetProp(tcpIpAddresses[0], "TcpPort")?.ToString() : null;

                // Determine whether to use Program or Port based on RuleType parameter.
                if (string.Equals(RuleType, "Program", StringComparison.OrdinalIgnoreCase))
                {
                    // Try to get the program path for executable-based rule.
                    try
                    {
                        Hashtable svcSplat = new()
                        {
                            { "ComputerName", instance.ComputerName },
                            { "InstanceName", instance.InstanceName },
                            { "Credential", Credential },
                            { "Type", "Engine" },
                            { "EnableException", true }
                        };
                        string? binaryPath = null;
                        foreach (PSObject r in NestedCommand.Invoke(this, "Get-DbaService", svcSplat))
                        {
                            if (r is not null) { binaryPath = GetProp(r, "BinaryPath")?.ToString(); break; }
                        }
                        Match m = binaryPath is null ? Match.Empty : EngineProgramRegex.Match(binaryPath);
                        if (m.Success)
                        {
                            config["Program"] = m.Groups[1].Value;
                            WriteMessage(MessageLevel.Verbose, $"Creating program-based firewall rule targeting: {m.Groups[1].Value}");
                        }
                        else
                        {
                            WriteMessage(MessageLevel.Warning, $"Could not determine executable path for instance {instance}. Falling back to port-based rule.");
                        }
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception)
                    {
                        WriteMessage(MessageLevel.Warning, $"Failed to get service information for instance {instance}. Falling back to port-based rule.");
                    }

                    // If we couldn't get the program path, fall back to port-based rule.
                    if (!config.ContainsKey("Program") || !LanguagePrimitives.IsTrue(config["Program"]))
                    {
                        if (!string.Equals(tcpPort, string.Empty))
                        {
                            config["LocalPort"] = tcpPort;
                            WriteMessage(MessageLevel.Verbose, $"Fallback: Creating port-based firewall rule on port: {tcpPort}");
                        }
                        else
                        {
                            StopFunction($"Cannot create firewall rule for instance {instance}. No port configured and executable path unavailable.", continueLoop: true);
                            continue;
                        }
                    }
                }
                else
                {
                    // RuleType is 'Port' - use port-based rule.
                    if (!string.Equals(tcpPort, string.Empty))
                    {
                        config["LocalPort"] = tcpPort;
                        WriteMessage(MessageLevel.Verbose, $"Creating port-based firewall rule on port: {tcpPort}");
                    }
                    else
                    {
                        StopFunction($"Cannot create port-based firewall rule for instance {instance}. Instance is configured for dynamic ports. Use -RuleType Program instead.", continueLoop: true);
                        continue;
                    }
                }

                // Determine if Browser rule is needed (for named instances or non-default ports).
                if (!string.Equals(tcpPort, string.Empty) && !string.Equals(tcpPort, "1433"))
                {
                    browserNeeded = true;
                }

                rules.Add(new RuleSpec { Type = "Engine", InstanceName = instance.InstanceName, SqlInstance = engineSqlInstance, Config = config });
            }

            // ===== Create rule for Browser =====
            if ((!typeBound && browserNeeded) || ContainsType("Browser"))
            {
                Hashtable config = NewConfig();
                config["DisplayName"] = "SQL Server Browser";
                config["Name"] = "SQL Server Browser";
                config["Group"] = "SQL Server";
                config["Enabled"] = "True";
                config["Direction"] = "Inbound";
                config["Protocol"] = "UDP";

                if (string.Equals(RuleType, "Program", StringComparison.OrdinalIgnoreCase))
                {
                    try
                    {
                        Hashtable bsvcSplat = new()
                        {
                            { "ComputerName", instance.ComputerName },
                            { "Credential", Credential },
                            { "Type", "Browser" },
                            { "EnableException", true }
                        };
                        string? bpath = null;
                        foreach (PSObject r in NestedCommand.Invoke(this, "Get-DbaService", bsvcSplat))
                        {
                            if (r is not null) { bpath = GetProp(r, "BinaryPath")?.ToString(); break; } // Select-Object -First 1
                        }
                        Match m = bpath is null ? Match.Empty : BrowserProgramRegex.Match(bpath);
                        if (m.Success)
                        {
                            config["Program"] = m.Groups[1].Value;
                            config["Protocol"] = "Any";
                            WriteMessage(MessageLevel.Verbose, $"Creating program-based firewall rule for Browser targeting: {m.Groups[1].Value}");
                        }
                        else
                        {
                            WriteMessage(MessageLevel.Warning, "Could not determine SQL Browser executable path. Falling back to port-based rule.");
                            config["LocalPort"] = "1434";
                        }
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception)
                    {
                        WriteMessage(MessageLevel.Warning, "Failed to get SQL Browser service information. Falling back to port-based rule.");
                        config["LocalPort"] = "1434";
                    }
                }
                else
                {
                    // RuleType is 'Port' - use port-based rule.
                    config["LocalPort"] = "1434";
                    WriteMessage(MessageLevel.Verbose, "Creating port-based firewall rule for Browser on UDP port: 1434");
                }

                rules.Add(new RuleSpec { Type = "Browser", InstanceName = null, SqlInstance = null, Config = config });
            }

            // ===== Create rule for the dedicated admin connection (DAC) =====
            if (!typeBound || ContainsType("DAC"))
            {
                string? dacMessage = null;
                try
                {
                    Hashtable spSplat = new()
                    {
                        { "SqlInstance", instance },
                        { "Credential", Credential },
                        { "Simple", true },
                        { "EnableException", true }
                    };
                    string? errorLogPath = null;
                    foreach (PSObject r in NestedCommand.Invoke(this, "Get-DbaStartupParameter", spSplat))
                    {
                        if (r is not null) { errorLogPath = GetProp(r, "ErrorLog")?.ToString(); break; }
                    }

                    // The DAC ERRORLOG scan runs without -Credential, matching the PS function verbatim.
                    RemoteExecutionService.RemoteCommandRequest dacReq = new()
                    {
                        ComputerName = new DbaInstanceParameter(instance.ComputerName),
                        ScriptText = DacScript,
                        ArgumentList = new object?[] { errorLogPath }!,
                        Raw = true
                    };
                    RemoteExecutionService.RemoteCommandResult dacRes = RemoteExecutionService.InvokeCommand(this, dacReq);
                    foreach (PSObject o in dacRes.Output)
                    {
                        if (o is not null) { dacMessage = o.BaseObject?.ToString() ?? o.ToString(); break; }
                    }
                    WriteMessage(MessageLevel.Debug, $"Last DAC message in ERRORLOG: '{dacMessage}'");
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    StopFunction($"Failed to execute command to get information for DAC on {instance.ComputerName} for instance {instance.InstanceName}.", target: instance, errorRecord: rex.ErrorRecord, continueLoop: true);
                    continue;
                }
                catch (Exception ex)
                {
                    StopFunction($"Failed to execute command to get information for DAC on {instance.ComputerName} for instance {instance.InstanceName}.", target: instance, exception: ex, continueLoop: true);
                    continue;
                }

                if (string.IsNullOrEmpty(dacMessage))
                {
                    WriteMessage(MessageLevel.Warning, $"No information about the dedicated admin connection (DAC) found in ERRORLOG, cannot create firewall rule for DAC. Use 'Set-DbaSpConfigure -SqlInstance '{instance}' -Name RemoteDacConnectionsEnabled -Value 1' to enable remote DAC and try again.");
                }
                else if (Regex.IsMatch(dacMessage, "locally", RegexOptions.IgnoreCase))
                {
                    WriteMessage(MessageLevel.Verbose, "Dedicated admin connection is only listening locally, so no firewall rule is needed.");
                }
                else
                {
                    string dacPort = DacPortRegex.Replace(dacMessage, "$1");
                    WriteMessage(MessageLevel.Verbose, $"Dedicated admin connection is listening remotely on port {dacPort}.");

                    Hashtable config = NewConfig();
                    config["Group"] = "SQL Server";
                    config["Enabled"] = "True";
                    config["Direction"] = "Inbound";
                    config["Protocol"] = "TCP";
                    config["LocalPort"] = dacPort;

                    object? dacSqlInstance;
                    if (string.Equals(instance.InstanceName, "MSSQLSERVER", StringComparison.OrdinalIgnoreCase))
                    {
                        config["DisplayName"] = "SQL Server default instance (DAC)";
                        config["Name"] = "SQL Server default instance (DAC)";
                        dacSqlInstance = instance.ComputerName;
                    }
                    else
                    {
                        config["DisplayName"] = $"SQL Server instance {instance.InstanceName} (DAC)";
                        config["Name"] = $"SQL Server instance {instance.InstanceName} (DAC)";
                        dacSqlInstance = instance.ComputerName + "\\" + instance.InstanceName;
                    }

                    rules.Add(new RuleSpec { Type = "DAC", InstanceName = instance.InstanceName, SqlInstance = dacSqlInstance, Config = config });
                }
            }

            // ===== Create rule for database mirroring or Availability Groups =====
            if (ContainsType("DatabaseMirroring"))
            {
                Hashtable config = NewConfig();
                config["Group"] = "SQL Server";
                config["Enabled"] = "True";
                config["Direction"] = "Inbound";
                config["Protocol"] = "TCP";
                config["LocalPort"] = "5022";

                object? dbmSqlInstance;
                if (string.Equals(instance.InstanceName, "MSSQLSERVER", StringComparison.OrdinalIgnoreCase))
                {
                    config["DisplayName"] = "SQL Server default instance (DatabaseMirroring)";
                    config["Name"] = "SQL Server default instance (DatabaseMirroring)";
                    dbmSqlInstance = instance.ComputerName;
                }
                else
                {
                    config["DisplayName"] = $"SQL Server instance {instance.InstanceName} (DatabaseMirroring)";
                    config["Name"] = $"SQL Server instance {instance.InstanceName} (DatabaseMirroring)";
                    dbmSqlInstance = instance.ComputerName + "\\" + instance.InstanceName;
                }

                rules.Add(new RuleSpec { Type = "DatabaseMirroring", InstanceName = instance.InstanceName, SqlInstance = dbmSqlInstance, Config = config });
            }

            foreach (RuleSpec rule in rules)
            {
                // Apply the given configuration.
                if (Configuration is not null)
                {
                    foreach (DictionaryEntry entry in Configuration)
                    {
                        rule.Config[entry.Key] = entry.Value;
                    }
                }

                // Run the command for the instance.
                if (ShouldProcess(instance.ToString(), $"Creating firewall rule for instance {instance.InstanceName} on {instance.ComputerName}"))
                {
                    PSObject? commandResult = null;
                    try
                    {
                        RemoteExecutionService.RemoteCommandRequest request = new()
                        {
                            ComputerName = new DbaInstanceParameter(instance.ComputerName),
                            Credential = Credential,
                            ScriptText = CreateScript,
                            ArgumentList = new object?[] { rule.Config, Force.IsPresent }!,
                            Raw = false
                        };
                        RemoteExecutionService.RemoteCommandResult res = RemoteExecutionService.InvokeCommand(this, request);
                        foreach (PSObject o in res.Output)
                        {
                            if (o is not null) { commandResult = o; break; }
                        }
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (RuntimeException rex)
                    {
                        StopFunction($"Failed to execute command on {instance.ComputerName} for instance {instance.InstanceName}.", target: instance, errorRecord: rex.ErrorRecord, continueLoop: true);
                        continue;
                    }
                    catch (Exception ex)
                    {
                        StopFunction($"Failed to execute command on {instance.ComputerName} for instance {instance.InstanceName}.", target: instance, exception: ex, continueLoop: true);
                        continue;
                    }

                    // Determine the status message, mutating commandResult so Details mirrors PS.
                    List<object?> errorList = ToList(GetProp(commandResult, "Error"));
                    string? status;
                    bool alreadyExists = errorList.Count == 1
                        && errorList[0] is not null
                        && Regex.IsMatch(errorList[0]!.ToString() ?? string.Empty, "Cannot create a file when that file already exists", RegexOptions.IgnoreCase);
                    if (alreadyExists)
                    {
                        status = "The desired rule already exists. Use -Force to remove and recreate the rule.";
                        SetProp(commandResult, "Error", null);
                        if (string.Equals(rule.Type, "Browser", StringComparison.OrdinalIgnoreCase) && browserOptional)
                        {
                            SetProp(commandResult, "Successful", true);
                        }
                    }
                    else
                    {
                        object? cimStatus = GetProp(GetProp(commandResult, "CimInstance"), "Status");
                        if (cimStatus is not null && Regex.IsMatch(cimStatus.ToString() ?? string.Empty, "The rule was parsed successfully from the store", RegexOptions.IgnoreCase))
                        {
                            status = "The rule was successfully created.";
                        }
                        else
                        {
                            status = cimStatus?.ToString();
                        }
                    }

                    object? warnAppend = GetProp(commandResult, "Warning");
                    if (LanguagePrimitives.IsTrue(warnAppend))
                    {
                        WriteMessage(MessageLevel.Verbose, $"commandResult.Warning: {PsStr(warnAppend)}.");
                        status += $" Warning: {PsStr(warnAppend)}.";
                    }
                    object? errAppend = GetProp(commandResult, "Error");
                    if (LanguagePrimitives.IsTrue(errAppend))
                    {
                        WriteMessage(MessageLevel.Verbose, $"commandResult.Error: {PsStr(errAppend)}.");
                        status += $" Error: {PsStr(errAppend)}.";
                    }
                    object? excAppend = GetProp(commandResult, "Exception");
                    if (LanguagePrimitives.IsTrue(excAppend))
                    {
                        WriteMessage(MessageLevel.Verbose, $"commandResult.Exception: {PsStr(excAppend)}.");
                        status += $" Exception: {PsStr(excAppend)}.";
                    }

                    // Output information.
                    PSObject output = new();
                    output.Properties.Add(new PSNoteProperty("ComputerName", instance.ComputerName));
                    output.Properties.Add(new PSNoteProperty("InstanceName", rule.InstanceName));
                    output.Properties.Add(new PSNoteProperty("SqlInstance", rule.SqlInstance));
                    output.Properties.Add(new PSNoteProperty("DisplayName", rule.Config["DisplayName"]));
                    output.Properties.Add(new PSNoteProperty("Name", rule.Config["Name"]));
                    output.Properties.Add(new PSNoteProperty("Type", rule.Type));
                    output.Properties.Add(new PSNoteProperty("Protocol", rule.Config["Protocol"]));
                    output.Properties.Add(new PSNoteProperty("LocalPort", rule.Config["LocalPort"]));
                    output.Properties.Add(new PSNoteProperty("Program", rule.Config["Program"]));
                    output.Properties.Add(new PSNoteProperty("RuleConfig", rule.Config));
                    output.Properties.Add(new PSNoteProperty("Successful", GetProp(commandResult, "Successful")));
                    output.Properties.Add(new PSNoteProperty("Status", status));
                    output.Properties.Add(new PSNoteProperty("Details", commandResult));
                    OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
                    WriteObject(output);
                }
            }
        }
    }

    // @{}'s key comparer is EDITION-DEPENDENT (empirically verified): net472/WinPS 5.1 = a CultureAware
    // comparer bound to the CURRENT culture, net8.0/PS7 = OrdinalIgnoreCase. Build the edition-appropriate
    // comparer PER CALL (NOT a cached static): on net472 StringComparer.CurrentCultureIgnoreCase snapshots
    // CultureInfo.CurrentCulture at READ time, so a config bag built now matches an @{} built now even when
    // the thread culture changed since type-load (Turkish/Azeri I/i: a static comparer captured under en-US
    // would keep collapsing DIRECTION/Direction after a switch to tr-TR, where a fresh @{} keeps them
    // distinct). On net8.0 OrdinalIgnoreCase is a culture-independent singleton, so per-call == static.
    // CurrentCultureIgnoreCase is ALSO required for net472 @{} bag-order parity (W5-014).
    private static System.Collections.IEqualityComparer NewConfigComparer() =>
#if NET8_0_OR_GREATER
        StringComparer.OrdinalIgnoreCase;
#else
        StringComparer.CurrentCultureIgnoreCase;
#endif
    private static Hashtable NewConfig() => new Hashtable(NewConfigComparer());

    private bool ContainsType(string candidate)
    {
        if (Type is null) { return false; }
        foreach (string t in Type)
        {
            if (string.Equals(t, candidate, StringComparison.OrdinalIgnoreCase)) { return true; }
        }
        return false;
    }

    private static object? GetProp(object? obj, string name)
    {
        if (obj is null) { return null; }
        PSObject pso = obj as PSObject ?? new PSObject(obj);
        return pso.Properties[name]?.Value;
    }

    // PS "$value" string interpolation: a COLLECTION joins its elements with $OFS, NOT the collection's
    // ToString (which a C# interpolated string would call - e.g. "System.Object[]"). Matches the PS
    // function's "$($commandResult.Warning)"/Error for the ArrayList that -WarningVariable/-ErrorVariable
    // yields; a scalar (Exception's ErrorRecord) stringifies via ToString either way. Instance (not static)
    // so it can read the caller's $OFS from session state - the separator is the caller's $OFS, not a
    // hardcoded space, to match PS exactly when the session overrides $OFS.
    private string PsStr(object? value)
    {
        if (value is null) { return string.Empty; }
        object baseObject = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (baseObject is string s) { return s; }
        if (baseObject is System.Collections.IEnumerable enumerable)
        {
            List<string> parts = new();
            foreach (object? item in enumerable) { parts.Add(item?.ToString() ?? string.Empty); }
            return string.Join(Ofs(), parts);
        }
        return baseObject.ToString() ?? string.Empty;
    }

    // The session's $OFS (Output Field Separator) used to join a collection in "$collection". PS
    // (ParserOps.GetSeparator): an UNSET or $null $OFS means the default single space; any other value
    // (including "") is used verbatim via PS string conversion. Reading it per call - not caching - so a
    // mid-pipeline $OFS change is honored exactly as PS would.
    private string Ofs()
    {
        object? ofs = SessionState?.PSVariable?.GetValue("OFS");
        return ofs is null ? " " : (LanguagePrimitives.ConvertTo<string>(ofs) ?? string.Empty);
    }

    private static void SetProp(PSObject? obj, string name, object? value)
    {
        if (obj is null) { return; }
        PSPropertyInfo? prop = obj.Properties[name];
        if (prop is not null && prop.IsSettable)
        {
            prop.Value = value;
        }
        else
        {
            obj.Properties.Remove(name);
            obj.Properties.Add(new PSNoteProperty(name, value));
        }
    }

    private static List<object?> ToList(object? value)
    {
        List<object?> result = new();
        if (value is null) { return result; }
        object baseObject = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (baseObject is string) { result.Add(value); return result; }
        if (baseObject is IEnumerable enumerable)
        {
            foreach (object? item in enumerable) { result.Add(item); }
            return result;
        }
        result.Add(value);
        return result;
    }
}
