using System;
using System.Collections.Generic;
using System.Management.Automation;
using Microsoft.SqlServer.Management.Smo.Wmi;

namespace Dataplat.Dbatools.Computer
{
    /// <summary>
    /// Native core of private/functions/Invoke-ManagedComputerCommand.ps1 and the SQL WMI script
    /// blocks its callers pass (Get-WmiHadr, Enable-DbaAgHadr, Disable-DbaAgHadr). The PS helper
    /// first builds an SMO ManagedComputer for the target's IP address in the current process
    /// (current Windows identity), and only when that fails runs the same work on the target over
    /// PowerShell remoting with -Credential. The native second attempt keeps that order and that
    /// credential, but reaches the target's SQL WMI provider directly by its full computer name
    /// (DCOM, Kerberos by name), so no PowerShell is carried or started. Callers resolve the
    /// address first (Resolve-DbaNetworkName -Turbo) and own the messages.
    /// </summary>
    public static class ManagedComputerService
    {
        /// <summary>
        /// Reads the HADR setting of one service, as Get-WmiHadr's script block
        /// <c>$wmi.Services[$args[0]] | Select-Object IsHadrEnabled</c> does: the service is looked
        /// up by key, so a key no service has yields null, which Get-WmiHadr reports as false.
        /// </summary>
        /// <param name="computer">The computer name the caller was given, for messages.</param>
        /// <param name="ipAddress">The resolved IP address (the in-process attempt).</param>
        /// <param name="fullComputerName">The resolved full computer name (the second attempt).</param>
        /// <param name="credential">The Windows credential for the second attempt, or null.</param>
        /// <param name="serviceKey">The ManagedComputer.Services key (Get-WmiHadr passes the instance name).</param>
        /// <param name="verbose">Receives the helper's verbose messages.</param>
        /// <returns>The service's IsHadrEnabled, or null when no service has that key.</returns>
        public static bool? GetHadrEnabled(string computer, string ipAddress, string fullComputerName, PSCredential credential, string serviceKey, Action<string> verbose)
        {
            return Invoke(computer, ipAddress, fullComputerName, credential, verbose, delegate (ManagedComputer wmi)
            {
                Service service = wmi.Services[serviceKey];
                if (service == null)
                    return (bool?)null;
                return (bool?)service.IsHadrEnabled;
            });
        }

        /// <summary>
        /// Changes the HADR setting of the instance's engine service, as the Enable/Disable-DbaAgHadr
        /// script block <c>$wmi.Services | Where-Object DisplayName -eq "SQL Server ($instance)"</c>
        /// followed by <c>ChangeHadrServiceSetting</c> does. A missing service is a failure there (a
        /// method call on $null), and stays one here.
        /// </summary>
        /// <param name="computer">The computer name the caller was given, for messages.</param>
        /// <param name="ipAddress">The resolved IP address (the in-process attempt).</param>
        /// <param name="fullComputerName">The resolved full computer name (the second attempt).</param>
        /// <param name="credential">The Windows credential for the second attempt, or null.</param>
        /// <param name="instanceName">The SQL Server instance name.</param>
        /// <param name="enable">The new HADR setting.</param>
        /// <param name="verbose">Receives the helper's verbose messages.</param>
        public static void ChangeHadrServiceSetting(string computer, string ipAddress, string fullComputerName, PSCredential credential, string instanceName, bool enable, Action<string> verbose)
        {
            Invoke(computer, ipAddress, fullComputerName, credential, verbose, delegate (ManagedComputer wmi)
            {
                string displayName = String.Format("SQL Server ({0})", instanceName);
                List<Service> matches = new List<Service>();
                foreach (Service service in wmi.Services)
                {
                    // PS: Where-Object DisplayName -eq is case-insensitive.
                    if (String.Equals(service.DisplayName, displayName, StringComparison.OrdinalIgnoreCase))
                        matches.Add(service);
                }
                if (matches.Count == 0)
                    throw new InvalidOperationException(String.Format("The SQL WMI provider on {0} lists no service named {1}.", computer, displayName));
                // PS: a method call on the Where-Object result runs on every match.
                foreach (Service service in matches)
                    service.ChangeHadrServiceSetting(enable);
                return true;
            });
        }

        private static T Invoke<T>(string computer, string ipAddress, string fullComputerName, PSCredential credential, Action<string> verbose, Func<ManagedComputer, T> work)
        {
            verbose(String.Format("Connecting to SQL WMI on {0}.", computer));

            Exception localException;
            try
            {
                // PS: New-Object ManagedComputer $ipaddr in the current process, current identity. A
                // $null address made New-Object call the parameterless constructor, the local computer;
                // callers pass the target's name instead (correction unresolved-name-local-computer),
                // and a missing address is refused rather than turned into the local computer.
                if (ipAddress == null)
                    throw new ArgumentNullException("ipAddress");
                return work(new ManagedComputer(ipAddress));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                localException = ex;
                verbose(String.Format("Local connection attempt to {0} failed | {1}. Connecting remotely.", computer, ex.Message));
            }

            try
            {
                // A missing name never falls back to the local computer.
                if (fullComputerName == null)
                    throw new ArgumentNullException("fullComputerName");
                ManagedComputer wmi;
                if (credential != null)
                {
                    // ManagedComputer takes the password as text; the WMI connection API has no SecureString form.
                    System.Net.NetworkCredential netCredential = credential.GetNetworkCredential();
                    string userName = String.IsNullOrEmpty(netCredential.Domain) ? netCredential.UserName : netCredential.Domain + "\\" + netCredential.UserName;
                    wmi = new ManagedComputer(fullComputerName, userName, netCredential.Password);
                }
                else
                {
                    wmi = new ManagedComputer(fullComputerName);
                }
                return work(wmi);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                verbose(String.Format("Connecting remotely to: '{0}' failed. | {1}", computer, ex.Message));
                // PS: throw "<text>", a RuntimeException without an inner exception, so the calling
                // command can tell the user what went wrong. The text keeps the helper's
                // "(version $MinVersion)", 8, though the native attempt loads no versioned assembly.
                throw new RuntimeException(String.Format("Failed to connect to SQL WMI on {0}. Local connection attempt failed with: {1} | Last remote connection attempt (version 8) failed with: {2}", computer, localException.Message, ex.Message));
            }
        }
    }
}
