#nullable enable
#pragma warning disable CA1416 // Windows-only command

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Shared native registry implementation of Enable- and Disable-DbaHideInstance.
/// </summary>
public abstract class HideInstanceCmdlet : DbaBaseCmdlet
{
    protected abstract bool EnableHiding { get; }

    /// <summary>The target SQL Server instance(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; } = DefaultSqlInstance();

    /// <summary>Alternate Windows credential for the target computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (SqlInstance is null)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (instance is null)
            {
                continue;
            }
            WriteMessage(MessageLevel.VeryVerbose, String.Format("Processing {0}.", instance), target: instance);

            if (!ForceEncryptionResolver.RequireElevationSatisfied(instance))
            {
                StopFunction("Console not elevated, but elevation is required to perform some actions on localhost for this command.", target: instance, continueLoop: true);
                continue;
            }

            NetworkResolutionService.NetworkResolutionResult? resolved;
            try
            {
                resolved = NetworkResolutionService.Resolve(this, instance, Credential, turbo: false);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                try
                {
                    resolved = NetworkResolutionService.Resolve(this, instance, Credential, turbo: true);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch
                {
                    StopFunction(String.Format("Issue resolving {0}", instance), target: instance, category: ErrorCategory.InvalidArgument, continueLoop: true);
                    continue;
                }
            }
            if (resolved is null)
            {
                StopFunction(String.Format("Issue resolving {0}", instance), target: instance, category: ErrorCategory.InvalidArgument, continueLoop: true);
                continue;
            }

            string fullComputerName = resolved.FullComputerName;
            ForceEncryptionResolver.Resolution? res = ResolveService(fullComputerName, instance);
            if (res is null)
            {
                continue;
            }

            object vsnameArg = string.IsNullOrEmpty(res.Vsname) ? (object)instance : res.Vsname!;

            WriteMessage(MessageLevel.Verbose, String.Format("Regroot: {0}", res.RegRoot), target: instance);
            WriteMessage(MessageLevel.Verbose, String.Format("ServiceAcct: {0}", res.ServiceAccount), target: instance);
            WriteMessage(MessageLevel.Verbose, String.Format("InstanceName: {0}", res.InstanceName), target: instance);
            WriteMessage(MessageLevel.Verbose, String.Format("VSNAME: {0}", vsnameArg), target: instance);

            if (!ShouldProcess("local", String.Format("Connecting to {0} to modify the HideInstance value in {1} for {2}", instance, res.RegRoot, instance.InstanceName)))
            {
                continue;
            }

            try
            {
                WriteObject(SetRegistryHiding(fullComputerName, res, vsnameArg));
                WriteMessage(MessageLevel.Critical, String.Format(EnableHiding
                    ? "HideInstance was successfully set on {0} for the {1} instance. The change takes effect immediately for new connections."
                    : "HideInstance was successfully disabled on {0} for the {1} instance. The change takes effect immediately for new connections.", fullComputerName, res.InstanceName), target: instance);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                StopFunction(String.Format("Failed to connect to {0} using PowerShell remoting", fullComputerName), target: instance, errorRecord: rex.ErrorRecord, continueLoop: true);
                continue;
            }
            catch (Exception ex)
            {
                StopFunction(String.Format("Failed to connect to {0} using PowerShell remoting", fullComputerName), target: instance, exception: ex, continueLoop: true);
                continue;
            }
        }
    }

    private ForceEncryptionResolver.Resolution? ResolveService(string computerName, DbaInstanceParameter instance)
    {
        ForceEncryptionResolver.Outcome outcome = ForceEncryptionResolver.Resolve(computerName, instance,
            new PSCredentialWrap(Credential), out ForceEncryptionResolver.Resolution resolution, out Exception? accessError);
        switch (outcome)
        {
            case ForceEncryptionResolver.Outcome.AccessFailed:
                StopFunction(String.Format("Failed to access {0}", instance), target: instance, exception: accessError, continueLoop: true);
                return null;
            case ForceEncryptionResolver.Outcome.InstanceNotFound:
                StopFunction(String.Format("Can't find instance {0} on {1}.", resolution.Vsname, instance), target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                return null;
            default:
                return resolution;
        }
    }

    private PSObject SetRegistryHiding(string computerName,
        ForceEncryptionResolver.Resolution resolution, object sqlInstance)
    {
        ForceEncryptionResolver.NetworkFlagResult values = ForceEncryptionResolver.SetNetworkFlag(
            computerName, resolution.RegRoot, "HideInstance", EnableHiding ? 1u : 0u, Credential, false);
        PSObject output = new();
        // OutputHelper's instance overload requires a SQL connection; this command uses the target Windows identity.
        output.Properties.Add(new PSNoteProperty("ComputerName", values.ComputerName)); // style-ok: cs-output-props pinned Windows target identity; no SMO connection exists.
        output.Properties.Add(new PSNoteProperty("InstanceName", resolution.InstanceName)); // style-ok: cs-output-props pinned Windows service identity; no SMO connection exists.
        output.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstance)); // style-ok: cs-output-props pinned VSNAME value retains its input object type.
        output.Properties.Add(new PSNoteProperty("HideInstance", values.Value == 1u));
        if (EnableHiding)
        {
            output.TypeNames.Insert(0, "Selected.System.Management.Automation.PSCustomObject");
        }
        return output;
    }

    private static DbaInstanceParameter[]? DefaultSqlInstance()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(machine))
        {
            return null;
        }
        return new[] { new DbaInstanceParameter(machine) };
    }
}
