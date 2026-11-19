#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Edits existing Windows firewall rules for SQL Server on the target computer. Wrapper around
/// Set-NetFirewallRule executed remotely via the RemoteExecutionService, completing the
/// New-/Get-/Remove-DbaFirewallRule family. Surface pinned by the signed designed spec.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaFirewallRule", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "NonPipeline")]
[OutputType(typeof(PSObject))]
public sealed class SetDbaFirewallRuleCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance(s).</summary>
    [Parameter(ParameterSetName = "NonPipeline", Mandatory = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternate Windows credential for the target computer.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    public PSCredential? Credential { get; set; }

    /// <summary>Which rule types to edit. Matches Get-/Remove- (includes AllInstance).</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [ValidateSet("Engine", "Browser", "DAC", "DatabaseMirroring", "AllInstance")]
    public string[]? Type { get; set; }

    /// <summary>Firewall rule objects from Get-DbaFirewallRule, for pipeline editing.</summary>
    [Parameter(ParameterSetName = "Pipeline", Mandatory = true, ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

    /// <summary>Extra Set-NetFirewallRule settings; Name/DisplayName/Group are reserved and removed.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public Hashtable? Configuration { get; set; }

    /// <summary>By default, dbatools handles errors as friendly warnings. This switch enables terminating exceptions instead.</summary>
    // The signed surface declares EnableException explicitly in BOTH sets, mirroring
    // Remove-DbaFirewallRule; the inherited set-less declaration would land in
    // __AllParameterSets and fail the surface diff, so it is overridden with per-set attributes.
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public override SwitchParameter EnableException { get; set; }

    // Verbatim remote scriptblock: edits the rule in place via Set-NetFirewallRule (splatting the
    // config passed as $args[1] onto the rule named $args[0]) and returns an envelope. Guards for the
    // NetSecurity module's absence the way the rest of the family does.
    private const string SetScript = @"
            # This scriptblock will be processed by Invoke-Command2.
            $firewallRuleName = $args[0]
            $firewallRuleParameters = $args[1]

            try {
                if (-not (Get-Command -Name Set-NetFirewallRule -ErrorAction SilentlyContinue)) {
                    throw 'The module NetSecurity with the command Set-NetFirewallRule is missing on the target computer, so Set-DbaFirewallRule is not supported.'
                }
                $successful = $true
                $null = Set-NetFirewallRule -Name $firewallRuleName @firewallRuleParameters -WarningVariable warn -ErrorVariable err -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
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
                    Successful = $successful
                    Warning    = $warn
                    Error      = $err
                    Exception  = $null
                }
            } catch {
                [PSCustomObject]@{
                    Successful = $false
                    Warning    = $null
                    Error      = $null
                    Exception  = $_
                }
            }";

    private static readonly string[] DisplaySet = { "ComputerName", "InstanceName", "SqlInstance", "DisplayName", "Type", "Successful", "Status", "Protocol", "LocalPort", "Program" };

    // Reserved keys that identify a rule and must never be pushed into Set-NetFirewallRule.
    private static readonly string[] ReservedKeys = { "Name", "DisplayName", "Group" };

    // The caller's Configuration, copied (never mutated in place) and stripped of the reserved keys.
    private Hashtable? _appliedConfig;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // Copy the caller's hashtable first, THEN strip the reserved keys - unlike New-DbaFirewallRule,
        // which removes them from the caller's own hashtable in place. The clone preserves the source
        // comparer so the caller's key semantics carry through unchanged.
        if (Configuration is not null)
        {
            Hashtable copy = (Hashtable)Configuration.Clone();
            foreach (string notAllowedKey in ReservedKeys)
            {
                if (copy.ContainsKey(notAllowedKey))
                {
                    WriteMessage(MessageLevel.Verbose, $"Key {notAllowedKey} is not allowed in Configuration and will be removed.");
                    copy.Remove(notAllowedKey);
                }
            }
            _appliedConfig = copy;
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // The two sets are mutually exclusive: the SqlInstance path resolves rules through
        // Get-DbaFirewallRule (which stamps ComputerName/Name/Credential onto each rule), the
        // Pipeline path takes rules already shaped that way. Both are handled uniformly below.
        List<PSObject> rules = new();

        if (SqlInstance is not null)
        {
            foreach (DbaInstanceParameter instance in SqlInstance)
            {
                if (instance is null)
                {
                    continue;
                }
                try
                {
                    WriteMessage(MessageLevel.Verbose, $"Get firewall rules from {instance.ComputerName}.");
                    Hashtable splat = new Hashtable
                    {
                        { "SqlInstance", instance },
                        { "Credential", Credential },
                        { "Type", Type },
                        { "EnableException", true }
                    };
                    foreach (PSObject r in NestedCommand.Invoke(this, "Get-DbaFirewallRule", splat))
                    {
                        if (r is not null) { rules.Add(r); }
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    StopFunction($"Failed to collect firewall rules from {instance.ComputerName}.", target: instance, errorRecord: rex.ErrorRecord, continueLoop: true);
                }
                catch (Exception ex)
                {
                    StopFunction($"Failed to collect firewall rules from {instance.ComputerName}.", target: instance, exception: ex, continueLoop: true);
                }
            }
        }

        if (InputObject is not null)
        {
            foreach (object o in InputObject)
            {
                if (o is null) { continue; }
                rules.Add(o as PSObject ?? new PSObject(o));
            }
        }

        foreach (PSObject rule in rules)
        {
            object? computerNameValue = rule.Properties["ComputerName"]?.Value;
            string? computerName = computerNameValue?.ToString();
            string? ruleName = rule.Properties["Name"]?.Value?.ToString();
            object? sqlInstanceValue = rule.Properties["SqlInstance"]?.Value;
            object? typeValue = rule.Properties["Type"]?.Value;
            // The credential rides on the object Get-DbaFirewallRule emitted, so piping from Get- with
            // an explicit -Credential keeps working; using -Credential on the Pipeline path would
            // silently ignore the object's own credential.
            PSCredential? ruleCredential = rule.Properties["Credential"]?.Value as PSCredential;

            if (!ShouldProcess(sqlInstanceValue?.ToString() ?? computerName, $"Setting firewall rule {typeValue} on {sqlInstanceValue}"))
            {
                continue;
            }

            PSObject? commandResult = null;
            try
            {
                WriteMessage(MessageLevel.Debug, $"Executing Invoke-Command2 with ComputerName = {computerName} and ArgumentList {ruleName}.");
                RemoteExecutionService.RemoteCommandRequest request = new()
                {
                    ComputerName = new DbaInstanceParameter(computerName),
                    Credential = ruleCredential,
                    ScriptText = SetScript,
                    ArgumentList = new object?[] { ruleName, _appliedConfig ?? new Hashtable() }!,
                    Raw = true
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
                StopFunction($"Failed to execute command on {computerName}.", errorRecord: rex.ErrorRecord, continueLoop: true);
                continue;
            }
            catch (Exception ex)
            {
                StopFunction($"Failed to execute command on {computerName}.", exception: ex, continueLoop: true);
                continue;
            }

            object? successful = commandResult?.Properties["Successful"]?.Value;
            object? warning = commandResult?.Properties["Warning"]?.Value;
            object? error = commandResult?.Properties["Error"]?.Value;
            object? exception = commandResult?.Properties["Exception"]?.Value;

            string status = LanguagePrimitives.IsTrue(successful) ? "The rule was successfully set." : "Failure.";
            if (LanguagePrimitives.IsTrue(warning))
            {
                WriteMessage(MessageLevel.Verbose, $"commandResult.Warning: {PsStr(warning)}.");
                status += $" Warning: {PsStr(warning)}.";
            }
            if (LanguagePrimitives.IsTrue(error))
            {
                WriteMessage(MessageLevel.Verbose, $"commandResult.Error: {PsStr(error)}.");
                status += $" Error: {PsStr(error)}.";
            }
            if (LanguagePrimitives.IsTrue(exception))
            {
                WriteMessage(MessageLevel.Verbose, $"commandResult.Exception: {PsStr(exception)}.");
                status += $" Exception: {PsStr(exception)}.";
            }

            PSObject output = new();
            output.Properties.Add(new PSNoteProperty("ComputerName", computerNameValue));
            output.Properties.Add(new PSNoteProperty("InstanceName", rule.Properties["InstanceName"]?.Value));
            output.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstanceValue));
            output.Properties.Add(new PSNoteProperty("DisplayName", rule.Properties["DisplayName"]?.Value));
            output.Properties.Add(new PSNoteProperty("Name", ruleName));
            output.Properties.Add(new PSNoteProperty("Type", typeValue));
            output.Properties.Add(new PSNoteProperty("Protocol", rule.Properties["Protocol"]?.Value));
            output.Properties.Add(new PSNoteProperty("LocalPort", rule.Properties["LocalPort"]?.Value));
            output.Properties.Add(new PSNoteProperty("Program", rule.Properties["Program"]?.Value));
            output.Properties.Add(new PSNoteProperty("RuleConfig", _appliedConfig));
            output.Properties.Add(new PSNoteProperty("Successful", successful));
            output.Properties.Add(new PSNoteProperty("Status", status));
            output.Properties.Add(new PSNoteProperty("Details", commandResult));
            OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
            WriteObject(output);
        }
    }

    // PS "$value" string interpolation: a COLLECTION joins its elements with $OFS, NOT the collection's
    // ToString (which a C# interpolated string would call). Matches the family's status-append fidelity
    // for the ArrayList that -WarningVariable/-ErrorVariable yields; a scalar stringifies either way.
    // Instance (not static) so it can read the caller's $OFS from session state.
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

    // The session's $OFS (Output Field Separator) used to join a collection in "$collection". PS: an
    // UNSET or $null $OFS means the default single space; any other value (including "") is used
    // verbatim. Read per call - not cached - so a mid-pipeline $OFS change is honored as PS would.
    private string Ofs()
    {
        object? ofs = SessionState?.PSVariable?.GetValue("OFS");
        return ofs is null ? " " : (LanguagePrimitives.ConvertTo<string>(ofs) ?? string.Empty);
    }
}
