#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests computer power plans against the High performance best practice (or a custom plan).
/// Port of public/Test-DbaPowerPlan.ps1; surface pinned by
/// migration/baselines/Test-DbaPowerPlan.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaPowerPlan")]
[OutputType(typeof(PSObject))]
public sealed class TestDbaPowerPlanCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s) to test.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; }

    /// <summary>Alternate credential for connecting to the remote computer.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>A custom power plan to use as the best practice instead of High performance.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 2)]
    [Alias("CustomPowerPlan")]
    public string? PowerPlan { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS begin block: one mutable best-practice bag shared across every computer (mutations
    // persist, exactly like the function-scope object).
    private string? _bpInstanceId;
    private object? _bpPowerPlan;

    private static readonly string[] DisplaySet = new[] { "ComputerName", "ActivePowerPlan", "RecommendedPowerPlan", "IsBestPractice" };

    protected override void BeginProcessing()
    {
        _bpInstanceId = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c";
        _bpPowerPlan = null;
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (ComputerName is null)
        {
            return;
        }

        foreach (DbaInstanceParameter computer in ComputerName)
        {
            if (computer is null)
            {
                continue;
            }
            string computerText = computer.ToString();

            Collection<PSObject> powerPlans;
            try
            {
                WriteMessage(MessageLevel.Verbose, $"Getting Power Plans for {computerText}.");
                // PS: Get-DbaPowerPlan -ComputerName $computer -Credential $Credential -List
                //     -EnableException (ported cmdlet, nested via NestedCommand).
                Hashtable splatPowerPlan = new Hashtable
                {
                    { "ComputerName", computer },
                    { "Credential", Credential },
                    { "List", true },
                    { "EnableException", true }
                };
                powerPlans = NestedCommand.Invoke(this, "Get-DbaPowerPlan", splatPowerPlan);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                // PS: $_.Exception -match "namespace" / "credentials are known to not work" -
                // triage over the exception MESSAGE CHAIN (compiled stacks may carry namespace
                // frames a ToString() match would false-positive on).
                ErrorRecord? record = (ex as RuntimeException)?.ErrorRecord;
                if (MessageChainMatches(ex, "namespace"))
                {
                    StopFunction($"Can't get Power Plan Info for {computerText}. Unsupported operating system.", target: computer, errorRecord: record, exception: record is null ? ex : null, continueLoop: true);
                }
                else if (MessageChainMatches(ex, "credentials are known to not work"))
                {
                    StopFunction($"Can't get Power Plan Info for {computerText}. Login failure for {Credential?.UserName}.", target: computer, errorRecord: record, exception: record is null ? ex : null, continueLoop: true);
                }
                else
                {
                    StopFunction($"Can't get Power Plan Info for {computerText}. Check logs for more details.", target: computer, errorRecord: record, exception: record is null ? ex : null, continueLoop: true);
                }
                continue;
            }

            if (!string.IsNullOrEmpty(PowerPlan))
            {
                WriteMessage(MessageLevel.Verbose, $"Using Power Plan '{PowerPlan}' as best practice.");
                _bpPowerPlan = PowerPlan;
                // PS: $bpPowerPlan.InstanceID stays $null on no match ($null -eq check fires);
                // ConvertTo<string>(null) is "" and silently killed the unavailable-plan branch.
                object? bpInstanceIdMatch = GetMemberValueWhere(powerPlans, "PowerPlan", PowerPlan, "InstanceID");
                _bpInstanceId = bpInstanceIdMatch is null ? null : LanguagePrimitives.ConvertTo<string>(bpInstanceIdMatch);
                if (_bpInstanceId is null)
                {
                    WriteMessage(MessageLevel.Verbose, $"Unable to find Power Plan '{PowerPlan}' on {computerText}.");
                    _bpPowerPlan = $"You do not have the Power Plan '{PowerPlan}' installed on this machine.";
                }
            }
            else
            {
                _bpPowerPlan = GetMemberValueWhere(powerPlans, "InstanceID", _bpInstanceId, "PowerPlan");
                if (_bpPowerPlan is null)
                {
                    WriteMessage(MessageLevel.Verbose, $"Unable to find Power Plan 'High performance' on {computerText}.");
                    _bpPowerPlan = "You do not have the high performance plan installed on this machine.";
                }
            }

            // PS: $activePowerPlan = $powerPlans | Where-Object IsActive -eq 'True'
            PSObject? activePowerPlan = null;
            foreach (PSObject plan in powerPlans)
            {
                object? isActive = plan?.Properties["IsActive"]?.Value;
                if (LanguagePrimitives.Equals(isActive, "True", ignoreCase: true))
                {
                    activePowerPlan = plan;
                    break;
                }
            }

            object? activeInstanceId = activePowerPlan?.Properties["InstanceID"]?.Value;
            WriteMessage(MessageLevel.Verbose, $"Recommended GUID is {_bpInstanceId} and you have {LanguagePrimitives.ConvertTo<string>(activeInstanceId)}.");

            bool isBestPractice = LanguagePrimitives.Equals(activeInstanceId, _bpInstanceId, ignoreCase: true);

            PSObject output = new();
            output.Properties.Add(new PSNoteProperty("ComputerName", computer));
            output.Properties.Add(new PSNoteProperty("ActiveInstanceId", activeInstanceId));
            output.Properties.Add(new PSNoteProperty("ActivePowerPlan", activePowerPlan?.Properties["PowerPlan"]?.Value));
            output.Properties.Add(new PSNoteProperty("RecommendedInstanceId", _bpInstanceId));
            output.Properties.Add(new PSNoteProperty("RecommendedPowerPlan", _bpPowerPlan));
            output.Properties.Add(new PSNoteProperty("IsBestPractice", isBestPractice));
            output.Properties.Add(new PSNoteProperty("Credential", Credential));
            OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
            WriteObject(output);
        }
    }

    // PS: ($powerPlans | Where-Object <filterProp> -eq <value>).<resultProp> - case-insensitive
    // -eq filter then member enumeration (0 -> null, 1 -> scalar; multiple matches cannot occur
    // for plan GUIDs/names).
    private static object? GetMemberValueWhere(Collection<PSObject> items, string filterProperty, object? value, string resultProperty)
    {
        List<object?> values = new();
        foreach (PSObject item in items)
        {
            object? candidate = item?.Properties[filterProperty]?.Value;
            if (LanguagePrimitives.Equals(candidate, value, ignoreCase: true))
            {
                PSPropertyInfo? property = item!.Properties[resultProperty];
                if (property is not null)
                {
                    values.Add(property.Value);
                }
            }
        }
        if (values.Count == 0)
        {
            return null;
        }
        if (values.Count == 1)
        {
            return values[0];
        }
        return values.ToArray();
    }

    // PS -match over $_.Exception: walk the message chain (never ToString - compiled stack
    // frames can contain the needle).
    private static bool MessageChainMatches(Exception exception, string needle)
    {
        Exception? current = exception;
        while (current is not null)
        {
            if (current.Message is not null && current.Message.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return true;
            }
            current = current.InnerException;
        }
        return false;
    }
}
