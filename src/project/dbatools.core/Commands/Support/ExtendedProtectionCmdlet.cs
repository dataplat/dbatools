#nullable enable
#pragma warning disable CA1416 // Windows-only command

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The per-instance flow Get-DbaExtendedProtection and Set-DbaExtendedProtection share: elevation check, name
/// resolution, the SQL service's REGROOT and VSNAME, the verbose trail, confirmation, then the registry work the
/// command supplies, reported in the pinned five-property shape.
/// </summary>
public abstract class ExtendedProtectionCmdlet : DbaBaseCmdlet
{
    // Each command declares SqlInstance and Credential itself, so each keeps its own pinned help text.
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>The command's -SqlInstance value.</summary>
    protected abstract DbaInstanceParameter[]? Targets { get; }

    /// <summary>The command's -Credential value.</summary>
    protected abstract PSCredential? WindowsCredential { get; }

    /// <summary>The ShouldProcess action, formatted with the instance, the registry root and the instance name.</summary>
    protected abstract string ConfirmAction { get; }

    /// <summary>Extra verbose lines after VSNAME, in the pinned order.</summary>
    /// <param name="instance">The instance being processed.</param>
    protected virtual void WriteSettingMessages(DbaInstanceParameter instance)
    {
    }

    /// <summary>Does the command's registry work and returns the values read back afterwards.</summary>
    /// <param name="computerName">The resolved full computer name.</param>
    /// <param name="regRoot">The instance registry root.</param>
    /// <returns>The values read back.</returns>
    protected abstract ExtendedProtectionRegistry.Settings Apply(string computerName, string regRoot);

    /// <summary>Runs after the output is written, as the pinned function's trailing message does.</summary>
    /// <param name="computerName">The resolved full computer name.</param>
    /// <param name="instanceName">The SQL service instance name.</param>
    /// <param name="instance">The instance being processed.</param>
    protected virtual void Applied(string computerName, string? instanceName, DbaInstanceParameter instance)
    {
    }

    protected override void ProcessRecord()
    {
        DbaInstanceParameter[]? targets = Targets;
        if (Interrupted || targets is null)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in targets)
        {
            if (instance is not null)
            {
                ProcessInstance(instance);
            }
        }
    }

    // One pass of the pinned foreach body; each early return is a Stop-Function -Continue.
    private void ProcessInstance(DbaInstanceParameter instance)
    {
        WriteMessage(MessageLevel.VeryVerbose, String.Format("Processing {0}.", instance), target: instance);
        if (!ForceEncryptionResolver.RequireElevationSatisfied(instance))
        {
            StopFunction("Console not elevated, but elevation is required to perform some actions on localhost for this command.", target: instance, continueLoop: true);
            return;
        }

        string? computerName = ResolveComputer(instance);
        if (computerName is null)
        {
            StopFunction(String.Format("Issue resolving {0}", instance), target: instance, category: ErrorCategory.InvalidArgument, continueLoop: true);
            return;
        }

        ForceEncryptionResolver.Resolution service;
        Exception? failure;
        switch (ForceEncryptionResolver.Resolve(computerName, instance, new PSCredentialWrap(WindowsCredential), out service, out failure))
        {
            case ForceEncryptionResolver.Outcome.AccessFailed:
                StopFunction(String.Format("Failed to access {0}", instance), target: instance, exception: failure, continueLoop: true);
                return;
            case ForceEncryptionResolver.Outcome.InstanceNotFound:
                StopFunction(String.Format("Can't find instance {0} on {1}.", service.Vsname, instance), target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                return;
        }

        // PS: if ([string]::IsNullOrEmpty($vsname)) { $vsname = $instance }
        object identity = String.IsNullOrEmpty(service.Vsname) ? (object)instance : service.Vsname!;
        string regRoot = service.RegRoot;
        string? serviceName = service.InstanceName;
        WriteMessage(MessageLevel.Verbose, "Regroot: " + regRoot, target: instance);
        WriteMessage(MessageLevel.Verbose, "ServiceAcct: " + service.ServiceAccount, target: instance);
        WriteMessage(MessageLevel.Verbose, "InstanceName: " + serviceName, target: instance);
        WriteMessage(MessageLevel.Verbose, "VSNAME: " + identity, target: instance);
        WriteSettingMessages(instance);

        if (!ShouldProcess("local", String.Format(ConfirmAction, instance, regRoot, instance.InstanceName)))
        {
            return;
        }

        ExtendedProtectionRegistry.Settings settings;
        try
        {
            settings = Apply(computerName, regRoot);
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception remoteFailure)
        {
            // PS: Stop-Function ... -ErrorRecord $_ takes the category of the caught record. The registry provider records a key the caller may not
            // open as PermissionDenied; ExtendedProtectionRegistry raises that denial as the same SecurityException.
            ErrorCategory category = remoteFailure is System.Security.SecurityException ? ErrorCategory.PermissionDenied : ErrorCategory.NotSpecified;
            ErrorRecord caught = new ErrorRecord(remoteFailure, remoteFailure.GetType().Name, category, null);
            StopFunction(String.Format("Failed to connect to {0} using PowerShell remoting", computerName), target: instance, errorRecord: caught, continueLoop: true);
            return;
        }
        WriteObject(Report(settings, serviceName, identity));
        Applied(computerName, serviceName, instance);
    }

    // PS: Resolve-DbaNetworkName -EnableException, then once more with -Turbo when the first attempt fails.
    private string? ResolveComputer(DbaInstanceParameter instance)
    {
        foreach (bool turbo in new[] { false, true })
        {
            try
            {
                NetworkResolutionService.NetworkResolutionResult? resolution = NetworkResolutionService.Resolve(this, instance, WindowsCredential, turbo);
                if (resolution is not null)
                {
                    return resolution.FullComputerName;
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception attemptFailure)
            {
                // The pinned catch moves on to the next attempt; the last failure becomes "Issue resolving".
                WriteMessage(MessageLevel.Debug, String.Format("Resolving {0} failed: {1}", instance, attemptFailure.Message), target: instance);
            }
        }
        return null;
    }

    // PS: the remote scriptblock's [PSCustomObject], passed through Select-Object -Property * -ExcludeProperty ...
    private static PSObject Report(ExtendedProtectionRegistry.Settings settings, string? serviceName, object identity)
    {
        PSObject report = new PSObject();
        // OutputHelper's instance overload needs a SQL connection; this command reports the target's Windows identity.
        report.Properties.Add(new PSNoteProperty("ComputerName", settings.ComputerName)); // style-ok: cs-output-props pinned $env:COMPUTERNAME of the target; no SMO connection exists.
        report.Properties.Add(new PSNoteProperty("InstanceName", serviceName)); // style-ok: cs-output-props pinned SQL service instance name; no SMO connection exists.
        report.Properties.Add(new PSNoteProperty("SqlInstance", identity)); // style-ok: cs-output-props pinned VSNAME value retains its input object type.
        report.Properties.Add(new PSNoteProperty("ExtendedProtection", ProtectionText(settings.ExtendedProtection)));
        report.Properties.Add(new PSNoteProperty("AcceptedSpns", SpnList(settings.AcceptedSpns)));
        report.TypeNames.Insert(0, "Selected.System.Management.Automation.PSCustomObject");
        return report;
    }

    /// <summary>
    /// The ExtendedProtection property text for a raw registry value:
    /// "$extendedProtection - $(switch ($extendedProtection) { 0 { "Off" } 1 { "Allowed" } 2 { "Required" } })".
    /// </summary>
    /// <param name="value">The raw value, or null when absent.</param>
    /// <returns>The text the pinned function reports.</returns>
    public static string ProtectionText(object? value)
    {
        List<string> names = new List<string>();
        foreach (object? element in Elements(value))
        {
            if (element is null)
            {
                // A null case value matches none of the numeric clauses.
                continue;
            }
            if (LanguagePrimitives.Equals(element, 0, true, CultureInfo.InvariantCulture))
            {
                names.Add("Off");
            }
            else if (LanguagePrimitives.Equals(element, 1, true, CultureInfo.InvariantCulture))
            {
                names.Add("Allowed");
            }
            else if (LanguagePrimitives.Equals(element, 2, true, CultureInfo.InvariantCulture))
            {
                names.Add("Required");
            }
        }
        return Expand(value) + " - " + String.Join(" ", names);
    }

    /// <summary>
    /// The AcceptedSpns property for a raw registry value:
    /// @($settings.AcceptedSPNs -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($PSItem) }).
    /// </summary>
    /// <param name="value">The raw value, or null when absent.</param>
    /// <returns>The non-blank names, untrimmed, in registry order.</returns>
    public static object[] SpnList(object? value)
    {
        List<object> spns = new List<object>();
        IEnumerable<object?> sources = value is null ? new object?[] { String.Empty } : Elements(value);
        foreach (object? source in sources)
        {
            foreach (string part in Expand(source).Split(';'))
            {
                if (!String.IsNullOrWhiteSpace(part))
                {
                    spns.Add(part);
                }
            }
        }
        return spns.ToArray();
    }

    // The items PowerShell enumerates for a value: an array's elements, otherwise the value itself.
    private static IEnumerable<object?> Elements(object? value)
    {
        if (value is IEnumerable sequence && value is not string)
        {
            foreach (object? element in sequence)
            {
                yield return element;
            }
            yield break;
        }
        yield return value;
    }

    // PowerShell's string expansion of a value: an array joins its elements with a space ($OFS default).
    private static string Expand(object? value)
    {
        if (value is null)
        {
            return String.Empty;
        }
        if (value is IEnumerable && value is not string)
        {
            List<string> parts = new List<string>();
            foreach (object? element in Elements(value))
            {
                parts.Add(Expand(element));
            }
            return String.Join(" ", parts);
        }
        return LanguagePrimitives.ConvertTo<string>(value) ?? String.Empty;
    }

    /// <summary>The pinned -SqlInstance default, $env:COMPUTERNAME.</summary>
    /// <returns>The local computer as the one target, or null when the variable is unset.</returns>
    protected static DbaInstanceParameter[]? LocalComputer()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        return String.IsNullOrEmpty(machine) ? null : new[] { new DbaInstanceParameter(machine) };
    }
}
