#nullable enable
#pragma warning disable CA1416 // Windows-only command

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes the network (TLS) certificate configured for a SQL Server instance by clearing the
/// Certificate value in the SuperSocketNetLib registry key. Port of
/// public/Remove-DbaNetworkCertificate.ps1; surface pinned by
/// migration/baselines/Remove-DbaNetworkCertificate.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaNetworkCertificate", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Default")]
[OutputType(typeof(PSObject))]
public sealed class RemoveDbaNetworkCertificateCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; } = DefaultSqlInstance();

    /// <summary>Alternate Windows credential for the target computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS scriptblock, verbatim: clears the Certificate reg value and returns the removed thumbprint.
    private const string RemoveScript = @"
                $regRoot = $args[0]
                $serviceAccount = $args[1]
                $instanceName = $args[2]
                $vsname = $args[3]

                $regPath = ""Registry::HKEY_LOCAL_MACHINE\$($regRoot)\MSSQLServer\SuperSocketNetLib""
                $thumbprint = (Get-ItemProperty -Path $regPath -Name Certificate).Certificate
                Set-ItemProperty -Path $regPath -Name Certificate -Value $null

                [PSCustomObject]@{
                    ComputerName      = $env:COMPUTERNAME
                    InstanceName      = $instanceName
                    SqlInstance       = $vsname
                    ServiceAccount    = $serviceAccount
                    RemovedThumbprint = $thumbprint
                }";

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
            WriteMessage(MessageLevel.VeryVerbose, $"Processing {instance}", target: instance);

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
                StopFunction($"Can't resolve {instance}", target: instance, category: ErrorCategory.InvalidArgument, continueLoop: true);
                continue;
            }

            // PS uses $resolved.FQDN for the ManagedComputer and Invoke-Command2 target.
            string fqdn = resolved.FQDN;
            ForceEncryptionResolver.Outcome outcome = ForceEncryptionResolver.Resolve(fqdn, instance, new PSCredentialWrap(Credential), out ForceEncryptionResolver.Resolution res, out Exception? accessEx);
            if (outcome == ForceEncryptionResolver.Outcome.AccessFailed)
            {
                StopFunction($"Failed to access {instance}", target: instance, exception: accessEx, continueLoop: true);
                continue;
            }
            if (outcome == ForceEncryptionResolver.Outcome.InstanceNotFound)
            {
                StopFunction($"Can't find instance {res.Vsname} on {instance}", target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            // PS: if ([String]::IsNullOrEmpty($vsname)) { $vsname = $instance }
            object vsnameArg = string.IsNullOrEmpty(res.Vsname) ? (object)instance : res.Vsname!;

            WriteMessage(MessageLevel.Verbose, $"Regroot: {res.RegRoot}", target: instance);
            WriteMessage(MessageLevel.Verbose, $"ServiceAcct: {res.ServiceAccount}", target: instance);
            WriteMessage(MessageLevel.Verbose, $"InstanceName: {res.InstanceName}", target: instance);
            WriteMessage(MessageLevel.Verbose, $"VSNAME: {vsnameArg}", target: instance);

            // PS: ShouldProcess("local", "Connecting to $ComputerName to remove the cert") - $ComputerName
            // is UNDEFINED in the PS source (the param is $SqlInstance), so it interpolates to empty.
            if (!ShouldProcess("local", "Connecting to  to remove the cert"))
            {
                continue;
            }

            try
            {
                RemoteExecutionService.RemoteCommandRequest request = new()
                {
                    ComputerName = new DbaInstanceParameter(fqdn),
                    Credential = Credential,
                    ScriptText = RemoveScript,
                    ArgumentList = new object?[] { res.RegRoot, res.ServiceAccount, res.InstanceName, vsnameArg }!
                };
                RemoteExecutionService.RemoteCommandResult result = RemoteExecutionService.InvokeCommand(this, request);
                if (result.Errors.Count > 0)
                {
                    StopFunction($"Failed to connect to {fqdn} using PowerShell remoting.", target: instance, errorRecord: result.Errors[0], continueLoop: true);
                    continue;
                }
                foreach (PSObject output in result.Output)
                {
                    if (output is not null)
                    {
                        WriteObject(output);
                    }
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                StopFunction($"Failed to connect to {fqdn} using PowerShell remoting.", target: instance, errorRecord: rex.ErrorRecord, continueLoop: true);
                continue;
            }
            catch (Exception ex)
            {
                StopFunction($"Failed to connect to {fqdn} using PowerShell remoting.", target: instance, exception: ex, continueLoop: true);
                continue;
            }
        }
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
