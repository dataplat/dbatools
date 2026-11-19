#pragma warning disable CA1416 // Windows-only: SQL WMI ManagedComputer and the WMI registry provider

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Net;
using System.Security;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>
    /// The shared native body of the read-only SuperSocketNetLib commands, Get-DbaForceNetworkEncryption and
    /// Get-DbaHideInstance. Their pinned functions are the same text except for the values the remote scriptblock reads and
    /// the hashtable it returns: resolve the computer, find the SQL service through SQL WMI, read its REGROOT and VSNAME,
    /// then read the instance's SuperSocketNetLib values on the target. Each command keeps its own parameters and help and
    /// supplies its read through <see cref="ReadSetting"/>; every message, warning and record carries the command's own name.
    /// </summary>
    public abstract class NetworkSettingReaderCmdlet : DbaBaseCmdlet
    {
        /// <summary>
        /// Reads the command's registry values for one instance and returns the object the pinned [PSCustomObject] cast of the
        /// scriptblock's hashtable gives. A failed read throws; the caller reports it as the pin's remoting Stop-Function.
        /// </summary>
        /// <param name="computerName">The resolved full computer name.</param>
        /// <param name="service">The SQL service's REGROOT and instance name.</param>
        /// <param name="identity">The pin's $vsname: the VSNAME value, or the instance when it is empty.</param>
        /// <param name="credential">The command's -Credential.</param>
        /// <returns>The object to emit.</returns>
        protected abstract PSObject ReadSetting(string computerName, ForceEncryptionResolver.Resolution service, object identity, PSCredential credential);

        /// <summary>The pinned process block: one pass of the foreach body per element.</summary>
        /// <param name="targets">The bound -SqlInstance; not null.</param>
        /// <param name="credential">The command's -Credential.</param>
        protected void ProcessInstances(DbaInstanceParameter[] targets, PSCredential credential)
        {
            foreach (DbaInstanceParameter instance in targets)
            {
                ProcessInstance(instance, credential);
            }
        }

        // One pass of the pinned foreach body; each early return is a Stop-Function -Continue.
        private void ProcessInstance(DbaInstanceParameter instance, PSCredential credential)
        {
            // String.Format expands the instance as PowerShell does (its ToString); "+" would take DbaInstanceParameter's implicit
            // string conversion, which reads FullName and fails on a null element.
            WriteMessage(MessageLevel.VeryVerbose, String.Format("Processing {0}", instance), target: instance);

            // PS: $null = Test-ElevationRequirement -ComputerName $instance -Continue. Only the local computer without an elevated
            // console fails; its Stop-Function names the caller and passes no -Target.
            if (instance != null && !ForceEncryptionResolver.RequireElevationSatisfied(instance))
            {
                StopFunction("Console not elevated, but elevation is required to perform some actions on localhost for this command.", continueLoop: true);
                return;
            }

            WriteMessage(MessageLevel.Verbose, "Resolving hostname.");
            string computerName = ResolveComputer(instance, credential);
            if (computerName == null)
            {
                StopFunction(String.Format("Can't resolve {0}", instance), target: instance, category: ErrorCategory.InvalidArgument, continueLoop: true);
                return;
            }

            ForceEncryptionResolver.Resolution service;
            RuntimeException failure;
            ForceEncryptionResolver.Outcome outcome = DiscoverService(computerName, instance, credential, out service, out failure);
            switch (outcome)
            {
                case ForceEncryptionResolver.Outcome.AccessFailed:
                    // PS: catch { Stop-Function -Message "Failed to access $instance" -Target $instance -Continue -ErrorRecord $_ },
                    // where $_ is the record of Invoke-ManagedComputerCommand's throw "<text>": the text as its id and target,
                    // OperationStopped (pin probe d2823ea6).
                    ErrorRecord caughtThrow = new ErrorRecord(failure, failure.Message, ErrorCategory.OperationStopped, failure.Message);
                    StopFunction(String.Format("Failed to access {0}", instance), target: instance, errorRecord: caughtThrow, continueLoop: true);
                    return;
                case ForceEncryptionResolver.Outcome.InstanceNotFound:
                    StopFunction(String.Format("Can't find instance {0} on {1}", service.Vsname, instance), target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                    return;
            }

            // PS: if ([System.String]::IsNullOrEmpty($vsname)) { $vsname = $instance }
            object identity = String.IsNullOrEmpty(service.Vsname) ? (object)instance : service.Vsname;
            WriteMessage(MessageLevel.Verbose, "Regroot: " + service.RegRoot, target: instance);
            WriteMessage(MessageLevel.Verbose, "ServiceAcct: " + service.ServiceAccount, target: instance);
            WriteMessage(MessageLevel.Verbose, "InstanceName: " + service.InstanceName, target: instance);
            WriteMessage(MessageLevel.Verbose, "VSNAME: " + identity, target: instance);

            // PS: Invoke-Command2 -ComputerName $resolved.FullComputerName -ArgumentList $regRoot, $vsname, $instanceName -ScriptBlock
            // { Get-ItemProperty ... } -ErrorAction Stop -Raw. The port reads the same registry values through the WMI registry provider,
            // always with -Credential, as the pin does when it opens its session (New-PSSession -Credential; derived from the pinned
            // Invoke-Command2). Invoke-Command2 caches that session per runspace and computer, not per credential, so in a runspace
            // that already holds one the pin reuses it and ignores -Credential (probe 6f29852d); the port keeps no session to reuse
            // (each command's correction registry-credential).
            PSObject report;
            try
            {
                report = ReadSetting(computerName, service, identity, credential);
            }
            catch (Exception readFailure) when (!(readFailure is PipelineStoppedException))
            {
                // PS: Stop-Function ... -ErrorRecord $_ takes the caught record's category: a key the caller may not open is
                // PermissionDenied, a missing value Get-ItemProperty's InvalidArgument.
                ErrorCategory category = readFailure is SecurityException ? ErrorCategory.PermissionDenied
                    : readFailure is PSArgumentException ? ErrorCategory.InvalidArgument : ErrorCategory.NotSpecified;
                ErrorRecord caught = new ErrorRecord(readFailure, readFailure.GetType().Name, category, null);
                StopFunction("Failed to connect to " + computerName + " using PowerShell remoting", target: instance, errorRecord: caught, continueLoop: true);
                return;
            }

            WriteObject(report);
        }

        // PS: Invoke-ManagedComputerCommand -ComputerName $resolved.FullComputerName -ScriptBlock { $wmi.Services } -Credential
        // $Credential. It first runs New-Object ManagedComputer $ipaddr and $wmi.Initialize() in this process, as the caller, for
        // the address Resolve-DbaNetworkName -Turbo gives. When that throws it runs the same work on the target through
        // Invoke-Command2 -ComputerName -Credential $Credential, and when that fails too it throws "Failed to connect to SQL WMI on
        // <computer>. Local connection attempt failed with: <local> | Last remote connection attempt (version 8) failed with:
        // <remote>" (pin probe d2823ea6, both editions). The port's second attempt reaches the target's SQL WMI provider by its
        // full name, as -Credential when given, so <remote> is that attempt's own failure: the pin's names its remote New-Object,
        // which the port does not make.
        private ForceEncryptionResolver.Outcome DiscoverService(string computerName, DbaInstanceParameter instance, PSCredential credential, out ForceEncryptionResolver.Resolution service, out RuntimeException failure)
        {
            failure = null;
            WriteMessage(MessageLevel.Verbose, String.Format("Connecting to SQL WMI on {0}.", computerName));

            // PS: $resolved = Resolve-DbaNetworkName -ComputerName $computer -Turbo; $ipaddr = $resolved.IpAddress
            string ipAddress = null;
            try
            {
                DbaInstanceParameter target = new DbaInstanceParameter(computerName);
                NetworkResolutionService.NetworkResolutionResult address = NetworkResolutionService.Resolve(this, target, null, true);
                if (address == null)
                {
                    string name = target.IsLocalHost ? Environment.MachineName : target.ComputerName;
                    WarnNestedStopFunction("Resolve-DbaNetworkName", "DNS name " + name + " not found", errorRecord: DnsFailure(name));
                }
                ipAddress = address == null ? null : address.IPAddress;
            }
            catch (Exception addressFailure) when (!(addressFailure is PipelineStoppedException))
            {
                WriteMessage(MessageLevel.Debug, String.Format("Resolving {0} failed: {1}", computerName, addressFailure.Message));
            }

            string localText;
            ForceEncryptionResolver.Outcome outcome;
            if (ipAddress == null)
            {
                // The pin's New-Object with a $null address would read the local computer instead; a missing address is a failed
                // attempt here, as in ManagedComputerService (correction unresolved-name-local-computer).
                service = new ForceEncryptionResolver.Resolution();
                localText = new ArgumentNullException("ipAddress").Message;
            }
            else
            {
                outcome = ReadServices(ipAddress, instance, new PSCredentialWrap(null), out service, out localText);
                if (outcome != ForceEncryptionResolver.Outcome.AccessFailed)
                {
                    return outcome;
                }
            }

            WriteMessage(MessageLevel.Verbose, String.Format("Local connection attempt to {0} failed | {1}. Connecting remotely.", computerName, localText));
            string remoteText;
            outcome = ReadServices(computerName, instance, new PSCredentialWrap(credential), out service, out remoteText);
            if (outcome != ForceEncryptionResolver.Outcome.AccessFailed)
            {
                return outcome;
            }

            WriteMessage(MessageLevel.Verbose, String.Format("Connecting remotely to: '{0}' failed. | {1}", computerName, remoteText));
            failure = new RuntimeException(String.Format("Failed to connect to SQL WMI on {0}. Local connection attempt failed with: {1} | Last remote connection attempt (version 8) failed with: {2}", computerName, localText, remoteText));
            return ForceEncryptionResolver.Outcome.AccessFailed;
        }

        // One attempt: $wmi.Initialize(), then the services. A failed Initialize() reads as PowerShell reports a failed method call,
        // 'Exception calling "Initialize" with "0" argument(s): "<message>"' (pin probe d2823ea6).
        private static ForceEncryptionResolver.Outcome ReadServices(string machine, DbaInstanceParameter instance, PSCredentialWrap credential, out ForceEncryptionResolver.Resolution service, out string failureText)
        {
            service = new ForceEncryptionResolver.Resolution();
            failureText = "";
            try
            {
                Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer wmi;
                if (credential.HasValue && !Dataplat.Dbatools.Utility.Validation.IsLocalhost(machine))
                {
                    // ManagedComputer takes the password as text; the WMI connection API has no SecureString form.
                    NetworkCredential network = credential.GetNetworkCredential();
                    wmi = new Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer(machine, String.IsNullOrEmpty(network.Domain) ? network.UserName : String.Concat(network.Domain, @"\", network.UserName), network.Password);
                }
                else
                {
                    wmi = new Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer(machine);
                }
                wmi.Initialize();
            }
            catch (Exception initializeFailure) when (!(initializeFailure is PipelineStoppedException))
            {
                failureText = String.Format("Exception calling \"Initialize\" with \"0\" argument(s): \"{0}\"", initializeFailure.Message);
                return ForceEncryptionResolver.Outcome.AccessFailed;
            }

            Exception readFailure;
            ForceEncryptionResolver.Outcome outcome = ForceEncryptionResolver.Resolve(machine, instance, credential, out service, out readFailure);
            if (outcome == ForceEncryptionResolver.Outcome.AccessFailed)
            {
                failureText = readFailure == null ? "" : readFailure.Message;
            }
            return outcome;
        }

        // PS: try { Resolve-DbaNetworkName -ComputerName $instance -Credential $Credential -EnableException }
        //     catch { Resolve-DbaNetworkName -ComputerName $instance -Credential $Credential -Turbo }
        // The library returns null where the pinned lookup fails at DNS. Each of the two calls then runs Resolve-DbaNetworkName's
        // Stop-Function "DNS name <name> not found", which warns under its name with or without -EnableException (the first call
        // throws after it, the -Turbo call returns nothing), so an unresolvable computer warns twice (probe 6f29852d, both editions).
        private string ResolveComputer(DbaInstanceParameter instance, PSCredential credential)
        {
            if (instance == null)
            {
                // PS: Resolve-DbaNetworkName's foreach over a null -ComputerName looks nothing up and returns nothing.
                return null;
            }

            string name = instance.IsLocalHost ? Environment.MachineName : instance.ComputerName;
            foreach (bool turbo in new[] { false, true })
            {
                try
                {
                    CimService.CmObjectFailure identityFailure = null;
                    CimService.CmObjectObserver identityObserver = new CimService.CmObjectObserver();
                    identityObserver.Failure = delegate (CimService.CmObjectFailure observed) { identityFailure = observed; };
                    NetworkResolutionService.NetworkResolutionResult resolution = NetworkResolutionService.Resolve(this, instance, credential, turbo, identityObserver);
                    WarnIdentityFailure(name, identityFailure);
                    if (resolution != null)
                    {
                        return resolution.FullComputerName;
                    }
                    WarnNestedStopFunction("Resolve-DbaNetworkName", "DNS name " + name + " not found", errorRecord: DnsFailure(name));
                }
                catch (Exception attemptFailure) when (!(attemptFailure is PipelineStoppedException))
                {
                    WriteMessage(MessageLevel.Debug, String.Format("Resolving {0} failed: {1}", instance, attemptFailure.Message), target: instance);
                }
            }

            return null;
        }

        // PS: Resolve-DbaNetworkName reads win32_ComputerSystem through Get-DbaCmObject -Credential $Credential, which is not given
        // -EnableException; a credential the target refuses makes it warn "[<computer>] Invalid connection credentials" under its
        // own name, and resolution goes on (pin probe d2823ea6, both editions).
        // Its record in $Error carries the warning text: the pin's wraps the refused enumeration of a call the port does not make.
        private void WarnIdentityFailure(string name, CimService.CmObjectFailure failure)
        {
            if (failure == null || (failure.Kind != CimService.CmObjectFailureKind.CimBadCredentials && failure.Kind != CimService.CmObjectFailureKind.WmiBadCredentials))
            {
                return;
            }

            string computer = name.ToLowerInvariant();
            WarnNestedStopFunction("Get-DbaCmObject", String.Concat("[", computer, "] Invalid connection credentials"), target: computer, category: ErrorCategory.InvalidOperation);
        }

        // Resolve-DbaNetworkName's record holds the failed Dns.GetHostEntry call; the library returns null without it, so the
        // lookup is repeated only to carry that failure. A lookup that now succeeds leaves the warning without a record.
        private static ErrorRecord DnsFailure(string name)
        {
            try
            {
                Dns.GetHostEntry(name);
                return null;
            }
            catch (Exception lookupFailure) when (!(lookupFailure is PipelineStoppedException))
            {
                return new ErrorRecord(lookupFailure, lookupFailure.GetType().Name, ErrorCategory.NotSpecified, null);
            }
        }

        /// <summary>
        /// PS: [PSCustomObject]$result over the hashtable literal the pinned scriptblock returns, whose properties follow the
        /// hashtable's enumeration order. A hashtable literal is new Hashtable(count, StringComparer.CurrentCultureIgnoreCase) filled
        /// in source order; the local computer runs the scriptblock in process. For another computer Invoke-Command2 goes through
        /// PowerShell remoting: Windows PowerShell on the host enumerates the literal, and this process's deserializer refills a new
        /// Hashtable(StringComparer.CurrentCultureIgnoreCase) in that order. The refill is repeated here in the host's measured
        /// order, so under PowerShell 7, whose string hashing changes per process, the order is the one the pin gives in the same
        /// process.
        /// </summary>
        /// <param name="computerName">The resolved full computer name.</param>
        /// <param name="literalNames">The literal's keys in source order.</param>
        /// <param name="literalValues">The values, in the same order as <paramref name="literalNames"/>.</param>
        /// <param name="hostOrder">The keys in the order Windows PowerShell enumerates the literal on the host.</param>
        /// <returns>The object the pinned cast gives.</returns>
        protected static PSObject ReturnedObject(string computerName, string[] literalNames, object[] literalValues, string[] hostOrder)
        {
            Hashtable returned;
            if (new DbaInstanceParameter(computerName).IsLocalHost)
            {
                returned = new Hashtable(literalNames.Length, StringComparer.CurrentCultureIgnoreCase);
                for (int index = 0; index < literalNames.Length; index++)
                {
                    returned.Add(literalNames[index], literalValues[index]);
                }
            }
            else
            {
                returned = new Hashtable(StringComparer.CurrentCultureIgnoreCase);
                foreach (string name in hostOrder)
                {
                    returned.Add(name, literalValues[Array.IndexOf(literalNames, name)]);
                }
            }

            PSObject report = new PSObject();
            foreach (DictionaryEntry entry in returned)
            {
                report.Properties.Add(new PSNoteProperty((string)entry.Key, entry.Value));
            }
            return report;
        }

        /// <summary>
        /// PS: $value -eq $true. A scalar compares as PowerShell's -eq does (the right side converted to the left side's type); a
        /// list value filters to its matching elements.
        /// </summary>
        /// <param name="value">The registry value read.</param>
        /// <returns>The comparison's result.</returns>
        protected static object EqualsTrue(object value)
        {
            IList list = value as IList;
            if (list != null && !(value is string))
            {
                List<object> matches = new List<object>();
                foreach (object element in list)
                {
                    if (LanguagePrimitives.Equals(element, true, true, CultureInfo.InvariantCulture))
                    {
                        matches.Add(element);
                    }
                }
                return matches.ToArray();
            }
            return LanguagePrimitives.Equals(value, true, true, CultureInfo.InvariantCulture);
        }

        /// <summary>PS: [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME</summary>
        /// <returns>The local computer as the default -SqlInstance, or null when the variable is empty.</returns>
        protected static DbaInstanceParameter[] LocalComputer()
        {
            string machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
            return String.IsNullOrEmpty(machine) ? null : new[] { new DbaInstanceParameter(machine) };
        }
    }
}
