#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets a computer's active power plan to the High performance best practice (or a custom plan).
/// Port of public/Set-DbaPowerPlan.ps1; surface pinned by
/// migration/baselines/Set-DbaPowerPlan.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaPowerPlan", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed class SetDbaPowerPlanCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s) to set.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; }

    /// <summary>Alternate credential for connecting to the remote computer.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>A custom power plan to set instead of High performance.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 2)]
    [Alias("CustomPowerPlan", "RecommendedPowerPlan")]
    public string? PowerPlan { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The Invoke-Command2 -Raw scriptblock, verbatim: P/Invoke PowerSetActiveScheme.
    private const string SetSchemeScript = @"
                        Param ($Guid)
                        $powerSetActiveSchemeDefinition = '[DllImport(""powrprof.dll"", CharSet = CharSet.Auto)] public static extern uint PowerSetActiveScheme(IntPtr RootPowerKey, Guid SchemeGuid);'
                        $powrprof = Add-Type -MemberDefinition $powerSetActiveSchemeDefinition -Name 'Win32PowerSetActiveScheme' -Namespace 'Win32Functions' -PassThru
                        $powrprof::PowerSetActiveScheme([System.IntPtr]::Zero, $Guid)
                    ";

    private static readonly string[] DisplaySet = new[] { "ComputerName", "PreviousPowerPlan", "ActivePowerPlan", "IsChanged" };

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

            // PS: $change = Test-DbaPowerPlan -ComputerName $computer -Credential $Credential
            //     -PowerPlan $PowerPlan -EnableException (the W5-043 ported cmdlet, nested).
            PSObject? change;
            try
            {
                WriteMessage(MessageLevel.Verbose, $"Getting and testing Power Plans on {computerText} using '{PowerPlan}' as best practice.");
                Hashtable splatTest = new Hashtable
                {
                    { "ComputerName", computer },
                    { "Credential", Credential },
                    { "PowerPlan", PowerPlan },
                    { "EnableException", true }
                };
                Collection<PSObject> tested = NestedCommand.Invoke(this, "Test-DbaPowerPlan", splatTest);
                change = tested.Count > 0 ? tested[0] : null;
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
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

            object? instanceId = change?.Properties["ActiveInstanceId"]?.Value;
            object? powerPlanActive = change?.Properties["ActivePowerPlan"]?.Value;
            object? instanceIdRequested = change?.Properties["RecommendedInstanceId"]?.Value;
            object? powerPlanRequested = change?.Properties["RecommendedPowerPlan"]?.Value;

            if (instanceIdRequested is null)
            {
                StopFunction($"You do not have the Power Plan '{PowerPlan}' installed on {computerText}. Skipping.", target: computer, continueLoop: true);
                continue;
            }

            PSObject output = new();
            output.Properties.Add(new PSNoteProperty("ComputerName", computer));
            output.Properties.Add(new PSNoteProperty("PreviousInstanceId", instanceId));
            output.Properties.Add(new PSNoteProperty("PreviousPowerPlan", powerPlanActive));
            output.Properties.Add(new PSNoteProperty("ActiveInstanceId", instanceId));
            output.Properties.Add(new PSNoteProperty("ActivePowerPlan", powerPlanActive));
            output.Properties.Add(new PSNoteProperty("IsChanged", false));

            bool isBestPractice = LanguagePrimitives.IsTrue(change?.Properties["IsBestPractice"]?.Value);
            if (isBestPractice)
            {
                if (ShouldProcess(computerText, $"Stating power plan is already set to {powerPlanRequested}, won't change."))
                {
                    WriteMessage(MessageLevel.Verbose, $"PowerPlan on {computerText} is already set to {powerPlanRequested}. Skipping.");
                    OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
                    WriteObject(output);
                }
            }
            else
            {
                if (ShouldProcess(computerText, $"Changing Power Plan from {powerPlanActive} to {powerPlanRequested}"))
                {
                    // PS: [System.Guid]$powerPlanGuid = $instanceIdRequested (always a real GUID
                    // string from the powercfg data).
                    Guid powerPlanGuid = LanguagePrimitives.ConvertTo<Guid>(instanceIdRequested);

                    // PS: try { Resolve -EnableException } catch { try { Resolve -Turbo
                    //     -EnableException } catch { $resolvedComputerName = $computer } } - the
                    // service returns null instead of throwing on DNS failure; either way the
                    // final fallback is the computer itself.
                    object resolvedComputerName;
                    try
                    {
                        NetworkResolutionService.NetworkResolutionResult? resolution = NetworkResolutionService.Resolve(this, computer, Credential, turbo: false);
                        if (resolution?.FullComputerName is null)
                        {
                            resolution = NetworkResolutionService.Resolve(this, computer, Credential, turbo: true);
                        }
                        resolvedComputerName = resolution?.FullComputerName ?? (object)computer;
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch
                    {
                        resolvedComputerName = computer;
                    }

                    try
                    {
                        RemoteExecutionService.RemoteCommandRequest request = new()
                        {
                            ComputerName = resolvedComputerName is DbaInstanceParameter direct ? direct : new DbaInstanceParameter((string)resolvedComputerName),
                            Credential = Credential,
                            ScriptText = SetSchemeScript,
                            ArgumentList = new object[] { powerPlanGuid },
                            Raw = true
                        };
                        RemoteExecutionService.RemoteCommandResult result = RemoteExecutionService.InvokeCommand(this, request);
                        foreach (ErrorRecord error in result.Errors)
                        {
                            WriteError(NestedCommand.PreserveErrorIdentity(error));
                        }
                        object? returnCode = result.Output.Count > 0 ? result.Output[0] : null;
                        // PS: if ($returnCode -ne 0)
                        if (!LanguagePrimitives.Equals(returnCode, 0, ignoreCase: false))
                        {
                            StopFunction($"Couldn't set the requested Power Plan '{powerPlanRequested}' on {computerText} (ReturnCode: {LanguagePrimitives.ConvertTo<string>(returnCode)}).", target: computer, category: ErrorCategory.ConnectionError, continueLoop: true);
                            continue;
                        }
                        SetNoteValue(output, "IsChanged", true);
                        SetNoteValue(output, "ActiveInstanceId", instanceIdRequested);
                        SetNoteValue(output, "ActivePowerPlan", powerPlanRequested);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (RuntimeException rex)
                    {
                        StopFunction($"Failed to connect to {computerText}.", target: computer, errorRecord: rex.ErrorRecord, continueLoop: true);
                        continue;
                    }
                    catch (Exception ex)
                    {
                        StopFunction($"Failed to connect to {computerText}.", target: computer, exception: ex, continueLoop: true);
                        continue;
                    }
                    OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
                    WriteObject(output);
                }
            }
        }
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

    private static void SetNoteValue(PSObject target, string name, object? value)
    {
        PSPropertyInfo? property = target.Properties[name];
        if (property is not null)
        {
            property.Value = value;
        }
        else
        {
            target.Properties.Add(new PSNoteProperty(name, value));
        }
    }
}
