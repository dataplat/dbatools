#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Management.Infrastructure;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaFirewallRule.ps1. The pinned function runs Get-NetFirewallRule -Group 'SQL Server'
// with Get-NetFirewallPortFilter and Get-NetFirewallApplicationFilter on the target; those are CDXML
// cmdlets over the MSFT_NetFirewallRule, MSFT_NetProtocolPortFilter and MSFT_NetApplicationFilter
// classes in root\StandardCimv2, which this port reads over CIM directly.

/// <summary>
/// Retrieves Windows firewall rules for SQL Server components from target computers for network troubleshooting and security auditing.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaFirewallRule")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaFirewallRuleCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance(s).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = Array.Empty<DbaInstanceParameter>();

    /// <summary>Alternate Windows credential for the target computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Which rule types to return.</summary>
    [Parameter(Position = 2)]
    [ValidateSet("Engine", "Browser", "DAC", "DatabaseMirroring", "AllInstance")]
    public string[]? Type { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private const string FirewallNamespace = @"root\StandardCimv2";

    // Get-NetFirewallRule -Group 'SQL Server' filters MSFT_NetFirewallRule on its RuleGroup property
    // (NetFirewallRule.cmdletDefinition.cdxml); no caller text enters the query.
    private const string RuleQuery = "SELECT * FROM MSFT_NetFirewallRule WHERE RuleGroup = 'SQL Server'";

    private const string MissingModuleMessage = "The module NetSecurity with the command Get-NetFirewallRule is missing on the target computer, so Get-DbaFirewallRule is not supported.";

    // The cmdletization not-found error Get-NetFirewallRule -Group writes when the group has no rule
    // (Microsoft.PowerShell.Commands.Management resources, "No {2} objects found with property '{0}' equal to '{1}'.  Verify the value of the property and retry.").
    private const string NotFoundMessage = "No MSFT_NetFirewallRule objects found with property 'RuleGroup' equal to 'SQL Server'.  Verify the value of the property and retry.";

    private static readonly string[] ErrorDisplaySet = { "ComputerName", "Warning", "Error", "Exception" };
    private static readonly string[] RuleDisplaySet = { "ComputerName", "InstanceName", "SqlInstance", "DisplayName", "Type", "Protocol", "LocalPort", "Program" };

    private static readonly Regex DacPattern = new(@"SQL Server instance .+ \(DAC\)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    // \Z is the pinned -replace pattern's $ (no Multiline: the end, or before a final newline).
    private static readonly Regex DacName = new(@"^SQL Server instance (.+) \(DAC\)\Z", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex MirroringPattern = new(@"SQL Server instance .+ \(DatabaseMirroring\)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex MirroringName = new(@"^SQL Server instance (.+) \(DatabaseMirroring\)\Z", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex EnginePattern = new(@"SQL Server instance .+", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex EngineName = new(@"^SQL Server instance (.+)\Z", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    /// <summary>One rule as the pinned scriptblock collects it: the rule and its two filters' values.</summary>
    private sealed class RuleReading
    {
        public object? DisplayName;
        public string Name = string.Empty;
        public object? Protocol;
        public object? LocalPort;
        public object? Program;
        public PSObject? Rule;
    }

    /// <summary>The pinned scriptblock's result envelope: Successful, Rules, Verbose, Warning, Error, Exception.</summary>
    private sealed class Reading
    {
        public bool Successful;
        public List<RuleReading>? Rules;
        public object[]? Verbose;
        public object? Error;
        public object? Exception;
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

            // Get all rules for SQL Server from target computer and filter later
            Reading reading;
            try
            {
                WriteMessage(MessageLevel.Debug, "Executing Invoke-Command2 with ComputerName = " + instance.ComputerName + ".");
                reading = ReadRules(instance);
                if (reading.Verbose is not null)
                {
                    foreach (object message in reading.Verbose)
                    {
                        WriteMessage(MessageLevel.Verbose, message?.ToString() ?? string.Empty);
                    }
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                // PS: Stop-Function -ErrorRecord $_, the record of Invoke-Command2 failing to open the
                // connection to the computer (category OpenError, target the computer).
                ErrorRecord failed = new(ex, ex.GetType().Name, ErrorCategory.OpenError, instance.ComputerName);
                StopFunction("Failed to execute command on " + instance.ComputerName + " for instance " + instance.InstanceName + ".", target: instance, errorRecord: failed, continueLoop: true);
                continue;
            }

            // If command was not successful, just output messages and continue with next SqlInstance
            if (!reading.Successful)
            {
                PSObject envelope = BuildEnvelope(reading);
                PSObject errorObject = new();
                errorObject.Properties.Add(new PSNoteProperty("ComputerName", instance.ComputerName)); // style-ok: cs-output-props the pinned [PSCustomObject] property order; the value is the target computer, not an SMO server
                errorObject.Properties.Add(new PSNoteProperty("Warning", null));
                errorObject.Properties.Add(new PSNoteProperty("Error", reading.Error));
                errorObject.Properties.Add(new PSNoteProperty("Exception", reading.Exception));
                errorObject.Properties.Add(new PSNoteProperty("Details", envelope));
                OutputHelper.SetDefaultDisplayPropertySet(errorObject, ErrorDisplaySet);
                WriteObject(errorObject);
                continue;
            }

            // Add more information to the rules
            List<PSObject> rules = new();
            foreach (RuleReading rule in reading.Rules ?? new List<RuleReading>())
            {
                // Correction unmatched-rule-carries-previous-type: the pin sets these only in its matching
                // branches, so a rule whose name matches no pattern took the previous rule's values.
                string? typeName = null;
                string? instanceName = null;
                string? sqlInstanceName = null;
                string ruleName = rule.Name;
                if (string.Equals(ruleName, "SQL Server Browser", StringComparison.OrdinalIgnoreCase))
                {
                    typeName = "Browser";
                    instanceName = null;
                    sqlInstanceName = null;
                }
                else if (string.Equals(ruleName, "SQL Server default instance (DAC)", StringComparison.OrdinalIgnoreCase))
                {
                    typeName = "DAC";
                    instanceName = "MSSQLSERVER";
                    sqlInstanceName = instance.ComputerName;
                }
                else if (string.Equals(ruleName, "SQL Server default instance (DatabaseMirroring)", StringComparison.OrdinalIgnoreCase))
                {
                    typeName = "DatabaseMirroring";
                    instanceName = "MSSQLSERVER";
                    sqlInstanceName = instance.ComputerName;
                }
                else if (string.Equals(ruleName, "SQL Server default instance", StringComparison.OrdinalIgnoreCase))
                {
                    typeName = "Engine";
                    instanceName = "MSSQLSERVER";
                    sqlInstanceName = instance.ComputerName;
                }
                else if (DacPattern.IsMatch(ruleName))
                {
                    typeName = "DAC";
                    instanceName = DacName.Replace(ruleName, "$1");
                    sqlInstanceName = instance.ComputerName + "\\" + instanceName;
                }
                else if (MirroringPattern.IsMatch(ruleName))
                {
                    typeName = "DatabaseMirroring";
                    instanceName = MirroringName.Replace(ruleName, "$1");
                    sqlInstanceName = instance.ComputerName + "\\" + instanceName;
                }
                else if (EnginePattern.IsMatch(ruleName))
                {
                    typeName = "Engine";
                    instanceName = EngineName.Replace(ruleName, "$1");
                    sqlInstanceName = instance.ComputerName + "\\" + instanceName;
                }

                PSObject detail = new();
                detail.Properties.Add(new PSNoteProperty("ComputerName", instance.ComputerName)); // style-ok: cs-output-props the pinned [PSCustomObject] property order; the value is the target computer, not an SMO server
                detail.Properties.Add(new PSNoteProperty("InstanceName", instanceName)); // style-ok: cs-output-props the pinned [PSCustomObject] property order; the value comes from the rule name
                detail.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstanceName)); // style-ok: cs-output-props the pinned [PSCustomObject] property order; the value comes from the rule name
                detail.Properties.Add(new PSNoteProperty("DisplayName", rule.DisplayName));
                detail.Properties.Add(new PSNoteProperty("Name", ruleName));
                detail.Properties.Add(new PSNoteProperty("Type", typeName));
                detail.Properties.Add(new PSNoteProperty("Protocol", rule.Protocol));
                detail.Properties.Add(new PSNoteProperty("LocalPort", rule.LocalPort));
                detail.Properties.Add(new PSNoteProperty("Program", rule.Program));
                detail.Properties.Add(new PSNoteProperty("Rule", rule.Rule));
                detail.Properties.Add(new PSNoteProperty("Credential", Credential));
                rules.Add(detail);
            }

            // What rules should we output?
            List<PSObject> outputRules = new();
            if (ContainsType("AllInstance"))
            {
                WriteMessage(MessageLevel.Verbose, "Returning all rules for target computer");
                outputRules.AddRange(rules);
            }
            else if (Type is null)
            {
                WriteMessage(MessageLevel.Verbose, "Returning rule for instance, DAC and maybe for Browser");
                // Get the rule for the instance
                outputRules.AddRange(rules.FindAll(r => (RuleType(r) == "Engine" || RuleType(r) == "DAC") && InstanceEq(r, instance.InstanceName)));
                if (outputRules.Count == 0)
                {
                    WriteMessage(MessageLevel.Verbose, "No rule found for instance");
                }
                else if (AnyLocalPort1433(outputRules))
                {
                    WriteMessage(MessageLevel.Verbose, "No rule for Browser needed");
                }
                else
                {
                    outputRules.AddRange(rules.FindAll(r => RuleType(r) == "Browser"));
                }
            }
            else
            {
                WriteMessage(MessageLevel.Verbose, "Returning specific rules");
                if (ContainsType("Engine"))
                {
                    WriteMessage(MessageLevel.Verbose, "Returning rule for instance");
                    outputRules.AddRange(rules.FindAll(r => RuleType(r) == "Engine" && InstanceEq(r, instance.InstanceName)));
                }
                if (ContainsType("Browser"))
                {
                    WriteMessage(MessageLevel.Verbose, "Returning rule for Browser");
                    outputRules.AddRange(rules.FindAll(r => RuleType(r) == "Browser"));
                }
                if (ContainsType("DAC"))
                {
                    WriteMessage(MessageLevel.Verbose, "Returning rule for DAC");
                    outputRules.AddRange(rules.FindAll(r => RuleType(r) == "DAC" && InstanceEq(r, instance.InstanceName)));
                }
                if (ContainsType("DatabaseMirroring"))
                {
                    WriteMessage(MessageLevel.Verbose, "Returning rule for DatabaseMirroring");
                    outputRules.AddRange(rules.FindAll(r => RuleType(r) == "DatabaseMirroring" && InstanceEq(r, instance.InstanceName)));
                }
            }

            foreach (PSObject row in outputRules)
            {
                OutputHelper.SetDefaultDisplayPropertySet(row, RuleDisplaySet);
                WriteObject(row);
            }
        }
    }

    // The pinned scriptblock: read the 'SQL Server' rules and, per rule, its port and application filter.
    // A failure to reach the computer throws (Invoke-Command2 failing); a failure of the query itself on a
    // reached computer comes back as an unsuccessful envelope, as Get-NetFirewallRule's error does.
    private Reading ReadRules(DbaInstanceParameter instance)
    {
        string computer = instance.ComputerName;

        // PS: Invoke-Command2 runs the scriptblock in-process without a credential on the local computer.
        PSCredential? credential = instance.IsLocalHost ? null : Credential;

        // Only the CIM rungs: the filters are reached through the rule's CIM associations
        // (MSFT_NetFirewallRuleFilterByProtocolPort, MSFT_NetFirewallRuleFilterByApplication), and Rule
        // is the CimInstance Get-NetFirewallRule returns. The WMI rung's ManagementObject is another
        // type, and the PowerShell Remoting rung's deserialized rules carry no association to traverse,
        // so a rule read there would come back without its filters. With both CIM rungs unavailable the
        // computer counts as not reached.
        CimService.CmObjectFailure? failure = null;
        CimService.CmObjectRequest request = new()
        {
            ComputerName = computer,
            Credential = credential,
            Query = RuleQuery,
            Namespace = FirewallNamespace,
            DoNotUse = ManagementConnectionType.Wmi | ManagementConnectionType.PowerShellRemoting,
            Observer = new CimService.CmObjectObserver { Failure = f => failure = f }
        };

        CimService.CmObjectResult result;
        try
        {
            result = CimService.GetCmObject(this, request);
        }
        catch (Exception) when (failure is not null && IsQueryFailure(failure))
        {
            return QueryFailed(failure!, computer);
        }

        if (result.PassthroughErrors.Count > 0)
        {
            return new Reading { Successful = false, Verbose = Array.Empty<object>(), Error = new ArrayList(result.PassthroughErrors) };
        }

        List<object> verbose = new();
        if (result.Instances.Count == 0)
        {
            verbose.Add("No objects found. Detailed error message: " + NotFoundMessage);
        }
        verbose.Add("Get-NetFirewallRule was successful, we have " + result.Instances.Count.ToString(System.Globalization.CultureInfo.InvariantCulture) + " rules.");

        List<RuleReading> rules = new();
        foreach (PSObject rule in result.Instances)
        {
            List<PSObject> portFilters = Associated(computer, credential, rule, "MSFT_NetProtocolPortFilter");
            List<PSObject> applicationFilters = Associated(computer, credential, rule, "MSFT_NetApplicationFilter");
            // NetSecurity.types.ps1xml gives Get-NetFirewallRule's objects Name (an alias of InstanceID) and
            // DisplayName, and the filters Protocol, LocalPort and Program (AppPath) through
            // Formatter.FormatNullableString and FormatNullableStringArray, which turn null or empty into
            // "Any" and @("Any"). The CIM instances here carry the class's own properties only.
            rules.Add(new RuleReading
            {
                DisplayName = rule.Properties["DisplayName"]?.Value,
                Name = rule.Properties["InstanceID"]?.Value?.ToString() ?? string.Empty,
                Protocol = MemberValue(portFilters, p => FormatNullableString(p.Properties["Protocol"]?.Value)),
                LocalPort = MemberValue(portFilters, p => FormatNullableStringArray(p.Properties["LocalPort"]?.Value)),
                Program = MemberValue(applicationFilters, p => FormatNullableString(p.Properties["AppPath"]?.Value)),
                Rule = rule
            });
        }

        return new Reading { Successful = true, Rules = rules, Verbose = verbose.ToArray() };
    }

    // CimError means the computer answered and the query failed there; every other failure kind means
    // the computer was not reached.
    private static bool IsQueryFailure(CimService.CmObjectFailure failure)
    {
        return failure.Kind == CimService.CmObjectFailureKind.CimError;
    }

    private static Reading QueryFailed(CimService.CmObjectFailure failure, string computer)
    {
        CimException? cimError = failure.Error as CimException ?? failure.Error?.InnerException as CimException;
        bool missingClass = cimError is not null && (cimError.NativeErrorCode == NativeErrorCode.InvalidClass || cimError.NativeErrorCode == NativeErrorCode.InvalidNamespace);
        if (missingClass)
        {
            // PS: throw '<message>' inside the scriptblock's try; its catch returns the record as Exception.
            ErrorRecord thrown = new(new RuntimeException(MissingModuleMessage), MissingModuleMessage, ErrorCategory.OperationStopped, MissingModuleMessage);
            return new Reading { Successful = false, Exception = thrown };
        }

        Exception error = failure.Error ?? new InvalidOperationException(failure.Message);
        string errorId = cimError?.MessageId ?? error.GetType().Name;
        ErrorRecord record = new(error, errorId, ErrorCategory.NotSpecified, computer);
        return new Reading { Successful = false, Verbose = Array.Empty<object>(), Error = new ArrayList { record } };
    }

    // PS: $rule | Get-NetFirewallPortFilter / Get-NetFirewallApplicationFilter. A failed traversal is a
    // non-terminating error of the remote command, which Invoke-Command2 passes on.
    private List<PSObject> Associated(string computer, PSCredential? credential, PSObject rule, string resultClassName)
    {
        CimService.CmAssociationRequest request = new()
        {
            ComputerName = computer,
            Credential = credential,
            SourceObject = rule,
            ResultClassName = resultClassName,
            Namespace = FirewallNamespace
        };
        CimService.CmObjectResult result = CimService.GetAssociatedCmObjects(request);
        foreach (ErrorRecord record in result.PassthroughErrors)
        {
            WriteError(record);
        }
        return result.Instances;
    }

    // Formatter.FormatNullableString: null or empty is "Any".
    private static string FormatNullableString(object? value)
    {
        string? text = value?.ToString();
        return string.IsNullOrEmpty(text) ? "Any" : text!;
    }

    // Formatter.FormatNullableStringArray: a null or empty array is @("Any").
    private static string[] FormatNullableStringArray(object? value)
    {
        object? baseValue = value is PSObject wrapped ? wrapped.BaseObject : value;
        List<string> items = new();
        if (baseValue is string single)
        {
            items.Add(single);
        }
        else if (baseValue is IEnumerable many)
        {
            foreach (object? element in many)
            {
                items.Add(element?.ToString() ?? string.Empty);
            }
        }
        return items.Count == 0 ? new[] { "Any" } : items.ToArray();
    }

    // PS member access on the filter output: one object gives its value, several give every value.
    private static object? MemberValue(List<PSObject> objects, Func<PSObject, object?> read)
    {
        if (objects.Count == 0)
        {
            return null;
        }
        if (objects.Count == 1)
        {
            return read(objects[0]);
        }
        List<object?> values = new();
        foreach (PSObject item in objects)
        {
            object? value = read(item);
            if (value is not string && value is IEnumerable many)
            {
                foreach (object? element in many)
                {
                    values.Add(element);
                }
            }
            else
            {
                values.Add(value);
            }
        }
        return values.ToArray();
    }

    // The envelope Invoke-Command2 returned, as Details shows it (Select-Object -Property * -ExcludeProperty ...).
    private static PSObject BuildEnvelope(Reading reading)
    {
        PSObject envelope = new();
        envelope.Properties.Add(new PSNoteProperty("Successful", reading.Successful));
        envelope.Properties.Add(new PSNoteProperty("Rules", null));
        envelope.Properties.Add(new PSNoteProperty("Verbose", reading.Verbose));
        envelope.Properties.Add(new PSNoteProperty("Warning", null));
        envelope.Properties.Add(new PSNoteProperty("Error", reading.Error));
        envelope.Properties.Add(new PSNoteProperty("Exception", reading.Exception));
        envelope.TypeNames.Insert(0, "Selected.System.Management.Automation.PSCustomObject");
        return envelope;
    }

    private bool ContainsType(string candidate)
    {
        if (Type is null)
        {
            return false;
        }
        foreach (string t in Type)
        {
            if (string.Equals(t, candidate, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    private static string? RuleType(PSObject rule) => rule.Properties["Type"]?.Value as string;

    private static bool InstanceEq(PSObject rule, string? instanceName)
    {
        return LanguagePrimitives.Equals(rule.Properties["InstanceName"]?.Value, instanceName, ignoreCase: true);
    }

    // PS: $outputRules.LocalPort -eq '1433' - member enumeration unrolls every rule's LocalPort array,
    // so it is true when any collected port equals '1433'.
    private static bool AnyLocalPort1433(List<PSObject> rules)
    {
        foreach (PSObject r in rules)
        {
            object? value = r.Properties["LocalPort"]?.Value;
            object? baseValue = value is PSObject wrapped ? wrapped.BaseObject : value;
            if (baseValue is not string && baseValue is IEnumerable ports)
            {
                foreach (object? port in ports)
                {
                    if (port is not null && LanguagePrimitives.Equals(port, "1433", ignoreCase: true))
                    {
                        return true;
                    }
                }
            }
            else if (baseValue is not null && LanguagePrimitives.Equals(baseValue, "1433", ignoreCase: true))
            {
                return true;
            }
        }
        return false;
    }
}
