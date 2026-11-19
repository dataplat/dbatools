#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Net;
using System.Net.Sockets;
using Dataplat.Dbatools.Computer;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

// Native port of public/Disable-DbaAgHadr.ps1 with its private helpers Test-ElevationRequirement,
// Get-WmiHadr and Invoke-ManagedComputerCommand, and the Get-, Stop- and Start-DbaService restart
// (Update-ServiceStatus) in the shared Dataplat.Dbatools.Computer services.

/// <summary>
/// Disables High Availability Disaster Recovery (HADR) capability on SQL Server instances.
/// </summary>
[Cmdlet(VerbsLifecycle.Disable, "DbaAgHadr", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class DisableDbaAgHadrCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Connect to the Windows server as a different user.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Restarts Engine and Agent services to apply the change immediately.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS: Stop-, Start- and Get-DbaService run with their default -Timeout of 60 seconds.
    private const int ServiceTimeoutSeconds = 60;

    private sealed class HadrState
    {
        public string? ComputerName;
        public string? InstanceName;
        public string? SqlInstance;
        public bool IsHadrEnabled;
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || SqlInstance is null)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            string computer = instance.ComputerName;
            string computerFullName = computer;
            string instanceName = instance.InstanceName;

            // PS: if (-not (Test-ElevationRequirement -ComputerName $instance)) { return }. The helper's
            // Stop-Function sets its stop flag in this command's scope, which nothing reads, so later
            // pipeline input is still processed; the return ends this record.
            if (!ElevationRequirement.IsSatisfied(instance))
            {
                StopFunction(ElevationRequirement.NotElevatedMessage, interruptCallerScope: false);
                return;
            }

            WriteMessage(MessageLevel.Verbose, String.Format("Checking current Hadr setting for {0}", computer));
            HadrState? currentState = GetWmiHadr(instance);

            string isHadrEnabled = currentState is null ? "" : currentState.IsHadrEnabled.ToString();
            WriteMessage(MessageLevel.InternalComment, String.Format("{0} Hadr current value: {1}", instance, isHadrEnabled));

            if (ShouldProcessForced(instance.ToString(), String.Format("Changing Hadr from {0} to 0 for {1}", isHadrEnabled, instance)))
            {
                try
                {
                    InvokeManagedComputer(instance, (address, fullComputerName) =>
                    {
                        ManagedComputerService.ChangeHadrServiceSetting(computerFullName, address, fullComputerName, Credential, instanceName, false, ManagedComputerVerbose);
                        return true;
                    });
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception)
                {
                    // PS: Stop-Function -Continue without -ErrorRecord: the message alone.
                    StopFunction(String.Format("Failure on {0} | This may be because AlwaysOn Availability Groups feature requires the x86(non-WOW) or x64 Enterprise Edition of SQL Server 2012 (or later version) running on Windows Server 2008 (or later version) with WSFC hotfix KB 2494036 installed.", instance.FullName), continueLoop: true);
                    continue;
                }
            }

            if (RestartRequested)
            {
                if (ShouldProcessForced(instance.ToString(), String.Format("Force provided, restarting the Engine service, and the Agent service if it is running, for {0} on {1}", instance, computerFullName)))
                {
                    try
                    {
                        RestartEngine(computerFullName, instanceName);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        StopFunction(String.Format("Issue restarting {0}", instance), target: instance, errorRecord: new ErrorRecord(ex, "dbatools_Disable-DbaAgHadr", ErrorCategory.NotSpecified, instance), continueLoop: true);
                        continue;
                    }
                }
            }

            HadrState? newState = GetWmiHadr(instance);

            if (!RestartRequested)
            {
                WriteMessage(MessageLevel.Warning, "You must restart the SQL Server for it to take effect.");
            }

            PSObject result = new PSObject();
            result.Properties.Add(new PSNoteProperty("ComputerName", newState?.ComputerName)); // style-ok: cs-output-props the source copies Get-WmiHadr's fields, null when that read failed
            result.Properties.Add(new PSNoteProperty("InstanceName", newState?.InstanceName)); // style-ok: cs-output-props the source copies Get-WmiHadr's fields, null when that read failed
            result.Properties.Add(new PSNoteProperty("SqlInstance", newState?.SqlInstance)); // style-ok: cs-output-props the source copies Get-WmiHadr's fields, null when that read failed
            result.Properties.Add(new PSNoteProperty("IsHadrEnabled", false));
            WriteObject(result);
        }
    }

    // PS: if (Test-Bound 'Force') and if (Test-Bound -Not -ParameterName Force). Correction
    // force-false-restarts: Test-Bound is true for -Force:$false too, which restarted the services and
    // dropped the restart warning; the switch's value decides.
    private bool RestartRequested => Force.ToBool();

    // PS: begin { if ($Force) { $ConfirmPreference = 'none' } } - binary cmdlets share the caller's
    // preference scope, so the suppression is applied around each ShouldProcess call instead.
    private bool ShouldProcessForced(string target, string action)
    {
        if (!Force.ToBool())
        {
            return ShouldProcess(target, action);
        }

        object? previousPreference = SessionState.PSVariable.GetValue("ConfirmPreference");
        try
        {
            SessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
            return ShouldProcess(target, action);
        }
        finally
        {
            SessionState.PSVariable.Set("ConfirmPreference", previousPreference);
        }
    }

    // PS: Get-WmiHadr. Its catch is Stop-Function -Message "Failure connecting to $computer"
    // -Category ConnectionError -ErrorRecord $_ under Get-WmiHadr's own, never bound, EnableException:
    // a warning and no output, never a throw, so the command carries on with an empty state.
    private HadrState? GetWmiHadr(DbaInstanceParameter instance)
    {
        string computer = instance.ComputerName;
        string instanceName = instance.InstanceName;
        bool? isEnabled;
        try
        {
            isEnabled = InvokeManagedComputer(instance, (address, fullComputerName) =>
                ManagedComputerService.GetHadrEnabled(computer, address, fullComputerName, Credential, instanceName, ManagedComputerVerbose));
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            // PS: $_ is the record of Invoke-ManagedComputerCommand's throw "<text>", category
            // OperationStopped, which Stop-Function keeps over its -Category argument.
            WriteHelperStop("Get-WmiHadr", String.Format("Failure connecting to {0}", computer), ex, ErrorCategory.OperationStopped, instance);
            return null;
        }

        return new HadrState
        {
            ComputerName = computer,
            InstanceName = instanceName,
            SqlInstance = instance.FullName,
            IsHadrEnabled = isEnabled ?? false
        };
    }

    // PS: Invoke-ManagedComputerCommand resolves the target with Resolve-DbaNetworkName -Turbo first.
    private T InvokeManagedComputer<T>(DbaInstanceParameter instance, Func<string?, string?, T> work)
    {
        string computer = instance.ComputerName;
        NetworkResolutionService.NetworkResolutionResult? resolved = NetworkResolutionService.Resolve(this, new DbaInstanceParameter(computer), null, true);
        if (resolved is null)
        {
            // Resolve-DbaNetworkName's own Stop-Function -Continue -ErrorRecord $_ (it is called without
            // EnableException): a warning and no result. Correction unresolved-name-local-computer: the
            // helper then built ManagedComputer from the missing address, $null, which is the local
            // computer, and read or changed SQL WMI there. The named computer is asked instead, so the
            // work reaches that computer or fails.
            WriteDnsFailure(computer);
            return work(computer, computer);
        }
        return work(resolved.IPAddress, resolved.FullComputerName);
    }

    // PS: Resolve-DbaNetworkName's "DNS name $cName not found" with the [System.Net.Dns]::GetHostEntry
    // failure as its record. The shared resolver returns only null, so the lookup is repeated to get
    // that failure.
    private void WriteDnsFailure(string computer)
    {
        DbaInstanceParameter parameter = new DbaInstanceParameter(computer);
        string cName = parameter.IsLocalHost ? Environment.MachineName : parameter.ComputerName;
        Exception failure;
        try
        {
            Dns.GetHostEntry(cName);
            failure = new SocketException((int)SocketError.HostNotFound);
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            failure = ex;
        }
        WriteHelperStop("Resolve-DbaNetworkName", String.Format("DNS name {0} not found", cName), failure, ErrorCategory.NotSpecified, null);
    }

    // PS: Stop-Function called inside a private helper that runs without EnableException: a warning
    // attributed to the helper, the record logged and added to $error, never a throw, whatever this
    // command's -EnableException says.
    private void WriteHelperStop(string functionName, string message, Exception exception, ErrorCategory category, object? target)
    {
        MessageService.MessageRequest request = new MessageService.MessageRequest
        {
            FunctionName = functionName,
            ModuleName = "dbatools",
            Level = MessageLevel.Warning,
            Message = message,
            EnableException = false,
            FromStopFunction = true,
            File = MyInvocation.ScriptName,
            Line = MyInvocation.ScriptLineNumber
        };
        object? displayTarget = target is null ? null : MessageService.CollapseTarget(MessageService.ResolveTarget(this, request, target));
        Exception resolvedException = MessageService.ResolveException(this, request, exception);
        string errorId = "dbatools_" + functionName;
        ErrorRecord input = new ErrorRecord(resolvedException, errorId, category, displayTarget);
        ErrorRecord record = new ErrorRecord(new Exception(MessageService.GetErrorMessage(input), resolvedException), errorId, category, displayTarget);
        request.Target = displayTarget;
        request.ErrorRecord = new[] { record };
        MessageService.Write(this, request);

        try
        {
            // PS: Stop-Function's $null = Write-Error ... 2>&1 still lands in the global $error.
            if (SessionState.PSVariable.GetValue("global:Error") is ArrayList errors)
            {
                errors.Insert(0, record);
                if (!Int32.TryParse(Convert.ToString(SessionState.PSVariable.GetValue("MaximumErrorCount"), CultureInfo.InvariantCulture), out int maximum))
                {
                    maximum = 256;
                }
                if (maximum >= 0 && errors.Count > maximum)
                {
                    errors.RemoveRange(maximum, errors.Count - maximum);
                }
            }
        }
        catch (Exception)
        {
            // $error is decoration only; a restricted session state must not replace the warning.
        }
    }

    private void ManagedComputerVerbose(string message)
    {
        WriteAttributedMessage("Invoke-ManagedComputerCommand", MessageLevel.Verbose, message);
    }

    // PS: the Agent depends on the engine, so it is stopped with it, but it is only started again if it
    // was running before. A refused stop or start only shows as Status "Failed" on the returned
    // objects, so they are checked and reported as one failure.
    private void RestartEngine(string computerFullName, string instanceName)
    {
        // PS: (Get-DbaService -Type Agent).State -eq "Running". The pinned restart passes no -Credential.
        bool agentWasRunning = false;
        foreach (SqlServiceControlItem agent in SqlServiceControl.GetInstanceServices(computerFullName, null!, instanceName, "Agent"))
        {
            if (string.Equals(agent.State, "Running", StringComparison.OrdinalIgnoreCase))
            {
                agentWasRunning = true;
            }
        }

        List<SqlServiceControlItem> restartResults = new List<SqlServiceControlItem>();
        restartResults.AddRange(ControlServices(computerFullName, instanceName, "stop", "Agent", "Engine"));
        if (agentWasRunning)
        {
            restartResults.AddRange(ControlServices(computerFullName, instanceName, "start", "Agent", "Engine"));
        }
        else
        {
            restartResults.AddRange(ControlServices(computerFullName, instanceName, "start", "Engine"));
        }

        List<string> failures = new List<string>();
        foreach (SqlServiceControlItem result in restartResults)
        {
            if (result.Status is null || !result.Status.StartsWith("Successful", StringComparison.OrdinalIgnoreCase))
            {
                failures.Add(String.Format("{0}: {1}", result.ServiceName, result.Message));
            }
        }
        if (failures.Count > 0)
        {
            throw new InvalidOperationException(String.Join(" | ", failures));
        }
    }

    // PS: Stop-DbaService / Start-DbaService -ComputerName -InstanceName -Type ... -EnableException:
    // Get-DbaService, then Update-ServiceStatus, whose warnings name each failed service.
    private List<SqlServiceControlItem> ControlServices(string computerFullName, string instanceName, string action, params string[] types)
    {
        List<SqlServiceControlItem> services = SqlServiceControl.GetInstanceServices(computerFullName, null!, instanceName, types);
        if (services.Count == 0)
        {
            throw new InvalidOperationException("No SQL Server services found with current parameters.");
        }

        List<SqlServiceControlItem> results = SqlServiceControl.Update(computerFullName, null!, services, action, ServiceTimeoutSeconds, CancellationToken);
        foreach (SqlServiceControlItem result in results)
        {
            if (result.ExitCode != 0)
            {
                string target = String.Format("{0} on {1}", result.ServiceName, result.ComputerName);
                WriteAttributedMessage("Update-ServiceStatus", MessageLevel.Warning, String.Format("({0}) {1}", target, result.Message), target: target);
                if (result.ServiceType == "Engine" && result.ExitCode == 3)
                {
                    WriteAttributedMessage("Update-ServiceStatus", MessageLevel.Warning, String.Format("({0}) Run the command with '-Force' switch to force the restart of dependent services (SQL Agent, PolyBase)", target), target: target);
                }
            }
        }
        return results;
    }
}
