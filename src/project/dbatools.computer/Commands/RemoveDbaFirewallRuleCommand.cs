#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes the Windows firewall rules for SQL Server from the target computer. Port of
/// public/Remove-DbaFirewallRule.ps1; surface pinned by migration/baselines/Remove-DbaFirewallRule.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaFirewallRule", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "NonPipeline")]
[OutputType(typeof(PSObject))]
public sealed class RemoveDbaFirewallRuleCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance(s).</summary>
    [Parameter(ParameterSetName = "NonPipeline", Mandatory = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternate Windows credential for the target computer.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    public PSCredential? Credential { get; set; }

    /// <summary>Which rule types to remove. Defaults to Engine and DAC.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [ValidateSet("Engine", "Browser", "DAC", "DatabaseMirroring", "AllInstance")]
    public string[] Type { get; set; } = new[] { "Engine", "DAC" };

    /// <summary>Firewall rule objects from Get-DbaFirewallRule, for pipeline removal.</summary>
    [Parameter(ParameterSetName = "Pipeline", Mandatory = true, ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

    /// <summary>By default, dbatools handles errors as friendly warnings. This switch enables terminating exceptions instead.</summary>
    // The PS function declares EnableException explicitly PER SET ([Parameter(ParameterSetName)] x2),
    // so the baseline records it in {NonPipeline, Pipeline} - the inherited set-less declaration lands
    // in __AllParameterSets and fails the surface diff. The override carries the per-set attributes
    // (the binder reads the most-derived declaration) while the base StopFunction/WriteMessage read
    // the bound value through virtual dispatch.
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public override SwitchParameter EnableException { get; set; }

    // Verbatim Invoke-Command2 scriptblock: Remove-NetFirewallRule by name, returns an envelope.
    private const string RemoveScript = @"
            # This scriptblock will be processed by Invoke-Command2.
            # Since only rules that were previously determined with Get-NetFirewallRule are deleted, there should be no problems.
            $firewallRuleName = $args[0]

            try {
                $successful = $true
                $null = Remove-NetFirewallRule -Name $firewallRuleName -WarningVariable warn -ErrorVariable err -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                if ($warn.Count -gt 0) {
                    $successful = $false
                } else {
                    $warn = $null
                }
                if ($err.Count -gt 0) {
                    $successful = $false
                } else {
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

    private static readonly string[] DisplaySet = { "ComputerName", "InstanceName", "SqlInstance", "DisplayName", "Type", "IsRemoved", "Status" };

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // PS: foreach ($instance in $SqlInstance) { $InputObject += Get-DbaFirewallRule ... }
        //     then foreach ($rule in $InputObject) { ... }. The two param sets are mutually
        //     exclusive, so only one source populates the rule list.
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
            string? computerName = rule.Properties["ComputerName"]?.Value?.ToString();
            string? ruleName = rule.Properties["Name"]?.Value?.ToString();
            PSCredential? ruleCredential = rule.Properties["Credential"]?.Value as PSCredential;

            // PS: if ($PSCmdlet.ShouldProcess($rule.ComputerName, "Removing firewall rule $($rule.Name)"))
            if (!ShouldProcess(computerName, $"Removing firewall rule {ruleName}"))
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
                    ScriptText = RemoveScript,
                    ArgumentList = new object?[] { ruleName }!,
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

            StringBuilder status = new(LanguagePrimitives.IsTrue(successful) ? "The rule was successfully removed." : "Failure.");
            if (LanguagePrimitives.IsTrue(warning))
            {
                WriteMessage(MessageLevel.Verbose, $"commandResult.Warning: {warning}.");
                status.Append($" Warning: {warning}.");
            }
            if (LanguagePrimitives.IsTrue(error))
            {
                WriteMessage(MessageLevel.Verbose, $"commandResult.Error: {error}.");
                status.Append($" Error: {error}.");
            }
            if (LanguagePrimitives.IsTrue(exception))
            {
                WriteMessage(MessageLevel.Verbose, $"commandResult.Exception: {exception}.");
                status.Append($" Exception: {exception}.");
            }

            PSObject output = new();
            output.Properties.Add(new PSNoteProperty("ComputerName", rule.Properties["ComputerName"]?.Value));
            output.Properties.Add(new PSNoteProperty("InstanceName", rule.Properties["InstanceName"]?.Value));
            output.Properties.Add(new PSNoteProperty("SqlInstance", rule.Properties["SqlInstance"]?.Value));
            output.Properties.Add(new PSNoteProperty("DisplayName", rule.Properties["DisplayName"]?.Value));
            output.Properties.Add(new PSNoteProperty("Type", rule.Properties["Type"]?.Value));
            output.Properties.Add(new PSNoteProperty("IsRemoved", successful));
            output.Properties.Add(new PSNoteProperty("Status", status.ToString()));
            OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
            WriteObject(output);
        }
    }
}
