#nullable enable
#pragma warning disable CA1416 // Windows-only command

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Shared native Windows registry implementation for the force-network-encryption commands.
/// </summary>
public abstract class ForceNetworkEncryptionCmdlet : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; } = DefaultSqlInstance();

    /// <summary>Alternate Windows credential for the target computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    protected abstract bool EnableEncryption { get; }

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

            WriteMessage(MessageLevel.Verbose, "Resolving hostname.");
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
                resolved = NetworkResolutionService.Resolve(this, instance, Credential, turbo: true);
            }
            if (resolved is null)
            {
                StopFunction(String.Format("Can't resolve {0}.", instance), target: instance, category: ErrorCategory.InvalidArgument, continueLoop: true);
                continue;
            }

            string fullComputerName = resolved.FullComputerName;
            ForceEncryptionResolver.Outcome outcome = ForceEncryptionResolver.Resolve(fullComputerName, instance, new PSCredentialWrap(Credential), out ForceEncryptionResolver.Resolution res, out Exception? accessEx);
            if (outcome == ForceEncryptionResolver.Outcome.AccessFailed)
            {
                StopFunction(String.Format(EnableEncryption ? "Failed to access {0}" : "Failed to access {0}.", instance), target: instance, exception: accessEx, continueLoop: true);
                continue;
            }
            if (outcome == ForceEncryptionResolver.Outcome.InstanceNotFound)
            {
                StopFunction(String.Format("Can't find instance {0} on {1}.", res.Vsname, instance), target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            object vsnameArg = string.IsNullOrEmpty(res.Vsname) ? (object)instance : res.Vsname!;

            WriteMessage(MessageLevel.Verbose, String.Format("Regroot: {0}", res.RegRoot), target: instance);
            WriteMessage(MessageLevel.Verbose, String.Format("ServiceAcct: {0}", res.ServiceAccount), target: instance);
            WriteMessage(MessageLevel.Verbose, String.Format("InstanceName: {0}", res.InstanceName), target: instance);
            WriteMessage(MessageLevel.Verbose, String.Format("VSNAME: {0}", vsnameArg), target: instance);

            if (!ShouldProcess("local", String.Format("Connecting to {0} to modify the ForceEncryption value in {1} for {2}", instance, res.RegRoot, instance.InstanceName)))
            {
                continue;
            }

            try
            {
                WriteObject(SetRegistryEncryption(fullComputerName, res, vsnameArg));
                WriteMessage(MessageLevel.Critical, String.Format("Force encryption was successfully set on {0} for the {1} instance. You must now restart the SQL Server for changes to take effect.", fullComputerName, res.InstanceName), target: instance);
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

    private PSObject SetRegistryEncryption(string computerName,
        ForceEncryptionResolver.Resolution resolution, object sqlInstance)
    {
        ForceEncryptionResolver.NetworkFlagResult values = ForceEncryptionResolver.SetNetworkFlag(
            computerName, resolution.RegRoot, "ForceEncryption", EnableEncryption ? 1u : 0u, Credential, true);
        PSObject output = new();
        // OutputHelper's instance overload requires a SQL connection; this command uses the target Windows identity.
        output.Properties.Add(new PSNoteProperty("ComputerName", values.ComputerName)); // style-ok: cs-output-props pinned Windows target identity; no SMO connection exists.
        output.Properties.Add(new PSNoteProperty("InstanceName", resolution.InstanceName)); // style-ok: cs-output-props pinned Windows service identity; no SMO connection exists.
        output.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstance)); // style-ok: cs-output-props pinned VSNAME value retains its input object type.
        output.Properties.Add(new PSNoteProperty("ForceEncryption", values.Value == 1u));
        output.Properties.Add(new PSNoteProperty("CertificateThumbprint", values.Certificate));
        output.TypeNames.Insert(0, "Selected.System.Management.Automation.PSCustomObject");
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
