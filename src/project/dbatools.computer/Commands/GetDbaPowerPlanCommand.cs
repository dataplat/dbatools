#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Principal;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Windows Power Plan configuration from SQL Server hosts to verify High Performance settings.
/// </summary>
// Port of public/Get-DbaPowerPlan.ps1; surface pinned by migration/baselines/Get-DbaPowerPlan.json.
[Cmdlet(VerbsCommon.Get, "DbaPowerPlan")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaPowerPlanCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server host computer(s) to check for power plan configuration.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] ComputerName { get; set; } = null!;

    /// <summary>Authenticate to the target computer(s) with alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Returns all available power plans on the target computers instead of just the active plan.</summary>
    [Parameter]
    public SwitchParameter List { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted || ComputerName is null)
        {
            return;
        }

        foreach (DbaInstanceParameter? computer in ComputerName)
        {
            // PS: $null = Test-ElevationRequirement -ComputerName $computer -Continue
            // (private/functions/flowcontrol/Test-ElevationRequirement.ps1 inlined: the test
            // only fails for a localhost target in a non-elevated process).
            if (computer is not null && !TestElevationRequirement(computer))
            {
                StopFunction("Console not elevated, but elevation is required to perform some actions on localhost for this command.", continueLoop: true);
                continue;
            }

            // The resolved identity can differ from the input alias. Use the shared resolver's
            // computer identity and DNS suffix reads, with the caller's Windows credential.
            string? computerResolved = ResolveFullComputerName(computer);

            if (string.IsNullOrEmpty(computerResolved))
            {
                StopFunction("Couldn't resolve hostname. Skipping.", continueLoop: true);
                continue;
            }

            WriteMessage(MessageLevel.Verbose, String.Format("Getting Power Plan information from {0}.", computer));

            List<PSObject> powerPlans;
            try
            {
                powerPlans = ReadPowerPlans(computerResolved!);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                // PS triage: $_.Exception -match "namespace" / "credentials are known to not work".
                // PS stringifies to the exception MESSAGE, so the port matches the message chain
                // only - ToString() would false-match "namespace" in MMI stack-frame signatures.
                ErrorRecord caught = ex is NestedPowerPlanFault nested ? nested.Record
                    : new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.NotSpecified, computer);
                string rendered = RenderMessages(caught.Exception);
                if (rendered.IndexOf("namespace", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    StopFunction(String.Format("Can't get Power Plan Info for {0}. Unsupported operating system.", computer), target: computer, errorRecord: caught, continueLoop: true);
                }
                else if (rendered.IndexOf("credentials are known to not work", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    StopFunction(String.Format("Can't get Power Plan Info for {0}. Login failure for {1}.", computer, Credential?.UserName), target: computer, errorRecord: caught, continueLoop: true);
                }
                else
                {
                    StopFunction(String.Format("Can't get Power Plan Info for {0}. Check logs for more details.", computer), target: computer, errorRecord: caught, continueLoop: true);
                }
                continue;
            }

            if (List.ToBool())
            {
                foreach (PSObject powerPlan in powerPlans)
                {
                    string? instanceId = ExtractInstanceGuid(GetInstanceProperty(powerPlan, "InstanceID") as string);
                    PSObject output = new();
                    output.Properties.Add(new PSNoteProperty("ComputerName", computer));
                    output.Properties.Add(new PSNoteProperty("InstanceId", instanceId));
                    output.Properties.Add(new PSNoteProperty("PowerPlan", GetInstanceProperty(powerPlan, "ElementName")));
                    output.Properties.Add(new PSNoteProperty("IsActive", GetInstanceProperty(powerPlan, "IsActive")));
                    output.Properties.Add(new PSNoteProperty("Credential", Credential));
                    OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "PowerPlan", "IsActive");
                    WriteObject(output);
                }
            }
            else
            {
                // PS: $powerPlans | Where-Object IsActive -eq 'True' (bool True survives the
                // string comparison via PS conversion).
                PSObject? activePlan = null;
                foreach (PSObject powerPlan in powerPlans)
                {
                    if (GetInstanceProperty(powerPlan, "IsActive") is bool isActive && isActive)
                    {
                        activePlan = powerPlan;
                        break;
                    }
                }

                string? instanceId = null;
                object? planName = null;
                if (activePlan is not null)
                {
                    instanceId = ExtractInstanceGuid(GetInstanceProperty(activePlan, "InstanceID") as string);
                    planName = GetInstanceProperty(activePlan, "ElementName");
                }
                if (instanceId is null)
                {
                    // PS: if ($null -eq $powerPlan.InstanceID) { $powerPlan.ElementName = "Unknown" }
                    // ACCEPTED DEVIATION: the PS source trips over null before this fallback can
                    // apply (method/property access on $null); the port honors the intended
                    // "Unknown" emission instead of reproducing the null-access errors.
                    planName = "Unknown";
                }

                PSObject output = new();
                output.Properties.Add(new PSNoteProperty("ComputerName", computer));
                output.Properties.Add(new PSNoteProperty("InstanceId", instanceId));
                output.Properties.Add(new PSNoteProperty("PowerPlan", planName));
                output.Properties.Add(new PSNoteProperty("Credential", Credential));
                OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "PowerPlan");
                WriteObject(output);
            }
        }
    }

    private bool TestElevationRequirement(DbaInstanceParameter computer)
    {
        // PS: Get-DbatoolsConfigValue -FullName commands.test-elevationrequirement.disable
        if (GetConfigTruthy("commands.test-elevationrequirement.disable"))
        {
            return true;
        }
        if (!computer.IsLocalHost)
        {
            return true;
        }
        // ACCEPTED DEVIATION: PS on non-Windows faults inside WindowsIdentity.GetCurrent();
        // the port passes the requirement through instead (elevation is meaningless there).
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            return true;
        }
        using WindowsIdentity identity = WindowsIdentity.GetCurrent();
        WindowsPrincipal principal = new(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    private string? ResolveFullComputerName(DbaInstanceParameter? computer)
    {
        if (computer is null)
        {
            return null;
        }

        if (GetConfigTruthy("commands.resolve-dbanetworkname.bypass"))
        {
            // The pin returns the original DbaInstanceParameter under bypass. The
            // downstream DbaCmConnectionParameter binder reads its ComputerName.
            return computer.ComputerName;
        }

        string cName = computer.IsLocalHost ? Environment.MachineName : computer.ComputerName;
        ManagementConnectionType lastRung = ManagementConnectionType.None;
        CimService.CmObjectFailure? identityFailure = null;
        CimService.CmObjectObserver observer = new()
        {
            Rung = (rung, step, error) => lastRung = rung,
            Failure = failure => identityFailure = failure
        };
        NetworkResolutionService.NetworkResolutionResult? resolved = NetworkResolutionService.Resolve(this, computer, Credential, false, observer);
        if (identityFailure is not null)
        {
            string key = cName.ToLowerInvariant();
            ConnectionHost.Connections.TryGetValue(key, out ManagementConnection? connection);
            CmObjectFailureRecord? report = CmObjectFailureRecord.Build(identityFailure, connection!, key, lastRung, true, "win32_ComputerSystem", @"root\cimv2");
            if (report is not null)
            {
                WarnNestedStopFunction("Get-DbaCmObject", report.Message, report.Target, report.Record, report.Category, report.OverrideExceptionMessage);
            }
        }

        if (resolved is not null)
        {
            return resolved.FullComputerName;
        }

        // The resolver returns null after DNS failure. Repeat only that read to retain the
        // method exception which the nested Resolve-DbaNetworkName Stop-Function receives.
        ErrorRecord? dnsError = null;
        try
        {
            Dns.GetHostEntry(cName);
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            string message = String.Format("Exception calling \"GetHostEntry\" with \"1\" argument(s): \"{0}\"", ex.Message);
            dnsError = new ErrorRecord(new MethodInvocationException(message, ex), ex.GetType().Name, ErrorCategory.NotSpecified, null);
        }
        WarnNestedStopFunction("Resolve-DbaNetworkName", "DNS name " + cName + " not found", errorRecord: dnsError);
        return null;
    }

    private List<PSObject> ReadPowerPlans(string resolvedComputer)
    {
        DbaCmConnectionParameter target = new(resolvedComputer);
        if (!target.Success)
        {
            // The pin reads the absent Input member, so both its target and displayed input are empty.
            throw new NestedPowerPlanFault(CaughtNestedStopFunction("Get-DbaCmObject", "Failed to interpret input: ", category: ErrorCategory.InvalidArgument));
        }
        string name = target.Connection.ComputerName.ToLowerInvariant();
        ManagementConnectionType lastRung = ManagementConnectionType.None;
        CimService.CmObjectFailure? failure = null;
        CimService.CmObjectRequest request = new()
        {
            ComputerName = name,
            Credential = TestBound(nameof(Credential)) ? Credential : null,
            ClassName = "Win32_PowerPlan",
            Namespace = @"root\cimv2\power",
            Observer = new CimService.CmObjectObserver
            {
                Rung = (rung, step, error) => lastRung = rung,
                Failure = reported => failure = reported
            }
        };

        CimService.CmObjectResult result;
        try
        {
            result = CimService.GetCmObject(this, request);
        }
        catch (Exception ex) when (ex is not PipelineStoppedException && failure is not null)
        {
            ConnectionHost.Connections.TryGetValue(name, out ManagementConnection? connection);
            CmObjectFailureRecord? report = CmObjectFailureRecord.Build(failure!, connection!, name, lastRung, true, request.ClassName, request.Namespace);
            if (report is null)
            {
                throw;
            }
            throw new NestedPowerPlanFault(CaughtNestedStopFunction("Get-DbaCmObject", report.Message, report.Target, report.Record, report.Category, report.OverrideExceptionMessage));
        }

        foreach (ErrorRecord record in result.PassthroughErrors)
        {
            WriteError(record);
        }
        return result.Instances;
    }

    private sealed class NestedPowerPlanFault : Exception
    {
        internal NestedPowerPlanFault(ErrorRecord record) : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        internal ErrorRecord Record { get; }
    }

    private static bool GetConfigTruthy(string fullName)
    {
        if (ConfigurationHost.Configurations.TryGetValue(fullName, out Config? config) && config is not null && config.Value is not null)
        {
            return LanguagePrimitives.IsTrue(config.Value);
        }
        return false;
    }

    private static object? GetInstanceProperty(PSObject instance, string name)
    {
        return instance.Properties[name]?.Value;
    }

    private static string RenderMessages(Exception exception)
    {
        List<string> messages = new();
        Exception? current = exception;
        while (current is not null && messages.Count < 10)
        {
            messages.Add(current.Message);
            current = current.InnerException;
        }
        return string.Join(" | ", messages);
    }

    private static string? ExtractInstanceGuid(string? rawInstanceId)
    {
        // PS: $powerPlan.InstanceID.Split('{')[1].Split('}')[0] - "Microsoft:PowerPlan\{gd}"
        // yields the bare guid. A brace-less value would null-fault in the PS source; the
        // port returns null and lets the "Unknown" fallback take over (accepted deviation).
        if (string.IsNullOrEmpty(rawInstanceId))
        {
            return null;
        }
        int open = rawInstanceId!.IndexOf('{');
        if (open < 0)
        {
            return null;
        }
        string tail = rawInstanceId.Substring(open + 1);
        int close = tail.IndexOf('}');
        return close < 0 ? tail : tail.Substring(0, close);
    }
}
