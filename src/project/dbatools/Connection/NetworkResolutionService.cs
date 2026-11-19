using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>
    /// Compiled core of public/Resolve-DbaNetworkName.ps1 (Wave 5): DNS resolution, the
    /// ping-selected IP address, the CIM computer-identity read and the remote registry DNS-suffix
    /// probe. Ported computer commands consume
    /// FullComputerName from here exactly like the PS sources consumed the function's
    /// output object; a future Resolve-DbaNetworkName cmdlet port wraps this service.
    /// </summary>
    public static class NetworkResolutionService
    {
        /// <summary>
        /// The Resolve-DbaNetworkName output object, field for field. See the PS help for
        /// the semantics of each name form; FullComputerName is the one callers should use.
        /// </summary>
        public sealed class NetworkResolutionResult
        {
            /// <summary>Whatever has been passed in.</summary>
            public object InputName;

            /// <summary>Hostname only, uppercased.</summary>
            public string ComputerName;

            /// <summary>The IP address that responded to connectivity tests.</summary>
            public string IPAddress;

            /// <summary>Hostname only, coming strictly from DNS.</summary>
            public string DNSHostname;

            /// <summary>Domain only, coming strictly from DNS.</summary>
            public string DNSDomain;

            /// <summary>Domain only, coming from the computer account (AD).</summary>
            public string Domain;

            /// <summary>Full name as returned by Dns.GetHostEntry.</summary>
            public string DNSHostEntry;

            /// <summary>Legacy ComputerName-dot-Domain notation.</summary>
            public string FQDN;

            /// <summary>Full name as configured from within the computer - the only secure match between AD and DNS.</summary>
            public string FullComputerName;
        }

        /// <summary>
        /// Resolves one computer with Resolve-DbaNetworkName's exact sequence. Returns
        /// null when the initial DNS lookup fails - the PS source Stop-Function -Continue
        /// path - so callers emit the "DNS name ... not found" warning and skip, exactly
        /// like consuming the PS function without EnableException did.
        /// </summary>
        /// <param name="host">The cmdlet making this request.</param>
        /// <param name="computer">The computer to resolve.</param>
        /// <param name="credential">Optional credential for the CIM and remoting probes.</param>
        /// <param name="turbo">DNS-only resolution; forced on non-Windows platforms like the PS source.</param>
        /// <returns>The resolution result, or null when DNS cannot resolve the input.</returns>
        public static NetworkResolutionResult Resolve(PSCmdlet host, DbaInstanceParameter computer, PSCredential credential, bool turbo)
        {
            return Resolve(host, computer, credential, turbo, null);
        }

        /// <summary>
        /// Resolve, with an observer of the win32_ComputerSystem read Resolve-DbaNetworkName makes through
        /// Get-DbaCmObject, so a caller can report that nested command's failure as the PS source shows it.
        /// </summary>
        /// <param name="host">The cmdlet making this request.</param>
        /// <param name="computer">The computer to resolve.</param>
        /// <param name="credential">Optional credential for the CIM and remoting probes.</param>
        /// <param name="turbo">DNS-only resolution; forced on non-Windows platforms like the PS source.</param>
        /// <param name="identityObserver">Sees the identity read's run; null changes nothing.</param>
        /// <returns>The resolution result, or null when DNS cannot resolve the input.</returns>
        public static NetworkResolutionResult Resolve(PSCmdlet host, DbaInstanceParameter computer, PSCredential credential, bool turbo, CimService.CmObjectObserver identityObserver)
        {
            if (computer == null)
                throw new ArgumentNullException("computer");

            // PS: commands.resolve-dbanetworkname.bypass echoes the input straight back -
            // every field carries the input parameter, whose string form is the FullName
            // (instance/port decorations included), not the bare host name (cross-model
            // review 2026-07-06 pm2 finding 3). Callers that feed a field into a
            // host-scoped consumer re-bind through DbaInstanceParameter, like the PS
            // binder did.
            if (GetConfigTruthy("commands.resolve-dbanetworkname.bypass"))
            {
                NetworkResolutionResult bypass = new NetworkResolutionResult();
                bypass.InputName = computer;
                bypass.ComputerName = computer.FullName;
                bypass.IPAddress = computer.FullName;
                bypass.DNSHostname = computer.FullName;
                bypass.DNSDomain = computer.FullName;
                bypass.Domain = computer.FullName;
                bypass.DNSHostEntry = computer.FullName;
                bypass.FQDN = computer.FullName;
                bypass.FullComputerName = computer.FullName;
                return bypass;
            }

            // PS: non-Windows clients force Turbo (DNS resolution only).
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                turbo = true;

            string cName = computer.IsLocalHost ? Environment.MachineName : computer.ComputerName;

            IPHostEntry resolved;
            IPAddress[] ipAddresses;
            string ipAddress;
            try
            {
                resolved = Dns.GetHostEntry(cName);
                // PS: Sort-Object -Property AddressFamily prioritizes IPv4; Sort-Object is a
                // stable sort, so use a stable ordering here too.
                ipAddresses = System.Linq.Enumerable.ToArray(
                    System.Linq.Enumerable.OrderBy(resolved.AddressList, delegate (IPAddress address) { return (int)address.AddressFamily; }));
                ipAddress = ipAddresses[0].ToString();
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                // PS: Stop-Function -Message "DNS name $cName not found" -Continue
                return null;
            }

            string fqdn;
            try
            {
                fqdn = Dns.GetHostEntry(ipAddresses[0]).HostName;
            }
            catch
            {
                fqdn = resolved.HostName;
            }

            string dnsDomain = GetComputerDomainName(fqdn, cName);
            if (fqdn.IndexOf('.') < 0 && !String.IsNullOrEmpty(dnsDomain))
                fqdn = fqdn + "." + dnsDomain;
            string hostname = fqdn.Split('.')[0];

            NetworkResolutionResult result = new NetworkResolutionResult();
            result.InputName = computer;
            result.ComputerName = hostname.ToUpper();
            result.IPAddress = ipAddress;
            result.DNSHostname = hostname;
            result.DNSDomain = dnsDomain;
            result.Domain = dnsDomain;
            result.DNSHostEntry = fqdn;
            result.FQDN = fqdn;
            result.FullComputerName = cName;

            if (turbo)
                return result;

            // PS: the first IP to answer a 1000ms ping is the one to use.
            using (Ping ping = new Ping())
            {
                foreach (IPAddress candidate in ipAddresses)
                {
                    try
                    {
                        PingReply reply = ping.Send(candidate, 1000);
                        if (reply != null && reply.Status == IPStatus.Success)
                        {
                            ipAddress = candidate.ToString();
                            break;
                        }
                    }
                    catch (PingException)
                    {
                        // an unreachable family (e.g. IPv6 without a route) just does not win
                    }
                }
            }
            result.IPAddress = ipAddress;

            // PS: re-try the DNS reverse zone lookup if the IP to use is not the first one.
            if (ipAddresses[0].ToString() != ipAddress)
            {
                try
                {
                    fqdn = Dns.GetHostEntry(System.Net.IPAddress.Parse(ipAddress)).HostName;
                    dnsDomain = GetComputerDomainName(fqdn, cName);
                    if (fqdn.IndexOf('.') < 0 && !String.IsNullOrEmpty(dnsDomain))
                        fqdn = fqdn + "." + dnsDomain;
                    hostname = fqdn.Split('.')[0];

                    result.ComputerName = hostname.ToUpper();
                    result.DNSHostname = hostname;
                    result.DNSDomain = dnsDomain;
                    result.Domain = dnsDomain;
                    result.DNSHostEntry = fqdn;
                    result.FQDN = fqdn;
                }
                catch
                {
                    // PS: "Failed to obtain a new name from $ipaddress, re-using $fqdn"
                }
            }

            try
            {
                CimService.CmObjectRequest identityRequest = new CimService.CmObjectRequest();
                identityRequest.ComputerName = cName;
                identityRequest.Credential = credential;
                identityRequest.ClassName = "win32_ComputerSystem";
                identityRequest.DoNotUse = ManagementConnectionType.PowerShellRemoting;
                identityRequest.Observer = identityObserver;
                CimService.CmObjectResult identity = CimService.GetCmObject(host, identityRequest);

                if (identity.Instances.Count > 0)
                {
                    PSObject conn = identity.Instances[0];
                    string connName = GetPropertyString(conn, "Name");
                    string dnsHostname = GetPropertyString(conn, "DNSHostname");
                    string adDomain = GetPropertyString(conn, "Domain");
                    result.ComputerName = connName;
                    result.FQDN = (dnsHostname + "." + adDomain).TrimEnd('.');
                    result.DNSHostname = dnsHostname;
                    result.Domain = adDomain;
                }

                try
                {
                    // PS: Invoke-Command2 -ScriptBlock { [IPGlobalProperties]::GetIPGlobalProperties().DomainName } -Raw
                    string dnsSuffix = ReadPrimaryDnsSuffix(cName, credential);
                    result.DNSDomain = dnsSuffix;
                    if (!String.IsNullOrEmpty(dnsSuffix))
                        result.FullComputerName = result.DNSHostname + "." + dnsSuffix;
                    else
                        result.FullComputerName = result.DNSHostname;
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch
                {
                    // PS: "Unable to get DNS domain information from $($cParams.ComputerName)"
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                // PS: "Unable to get domain name from $($cParams.ComputerName)"
            }

            try
            {
                result.DNSHostEntry = Dns.GetHostEntry(result.FullComputerName).HostName;
            }
            catch
            {
                // PS: ".NET.Dns GetHostEntry failed for $($result.FullComputerName)"
            }

            return result;
        }

        private static string ReadPrimaryDnsSuffix(string computerName, PSCredential credential)
        {
#pragma warning disable CA1416 // Called only after the Windows platform gate in Resolve.
            System.Management.ConnectionOptions options = new System.Management.ConnectionOptions();
            options.Authentication = System.Management.AuthenticationLevel.PacketPrivacy;
            options.Impersonation = System.Management.ImpersonationLevel.Impersonate;
            if (credential != null)
            {
                options.Username = credential.UserName;
                options.SecurePassword = credential.Password;
            }
            System.Management.ManagementScope scope = new System.Management.ManagementScope(
                String.Format(@"\\{0}\root\default", computerName), options);
            scope.Connect();
            using (System.Management.ManagementClass registry = new System.Management.ManagementClass(
                scope, new System.Management.ManagementPath("StdRegProv"), null))
            {
                foreach (string name in new string[] { "Domain", "NV Domain" })
                {
                    using (System.Management.ManagementBaseObject input = registry.GetMethodParameters("GetStringValue"))
                    {
                        input["hDefKey"] = 0x80000002u;
                        input["sSubKeyName"] = @"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters";
                        input["sValueName"] = name;
                        using (System.Management.ManagementBaseObject output = registry.InvokeMethod("GetStringValue", input, null))
                        {
                            uint status = Convert.ToUInt32(output["ReturnValue"]);
                            if (status == 2u)
                                continue;
                            if (status != 0u)
                                throw new System.ComponentModel.Win32Exception(unchecked((int)status));
                            string suffix = output["sValue"] as string;
                            if (!String.IsNullOrEmpty(suffix))
                                return suffix;
                        }
                    }
                }
            }
            return String.Empty;
#pragma warning restore CA1416
        }

        private static string GetComputerDomainName(string fqdn, string computerName)
        {
            // PS begin-block helper: deduce the domain name based on resolved name + original request.
            if (fqdn.IndexOf('.') < 0)
            {
                if (computerName.IndexOf('.') >= 0)
                    return computerName.Substring(computerName.IndexOf('.') + 1);
                string userDnsDomain = Environment.GetEnvironmentVariable("USERDNSDOMAIN");
                return (userDnsDomain == null ? String.Empty : userDnsDomain).ToLowerInvariant();
            }
            return fqdn.Substring(fqdn.IndexOf('.') + 1);
        }

        private static string GetPropertyString(PSObject instance, string name)
        {
            PSPropertyInfo property = instance.Properties[name];
            if (property == null || property.Value == null)
                return null;
            return property.Value.ToString();
        }

        private static bool GetConfigTruthy(string fullName)
        {
            Config config;
            if (ConfigurationHost.Configurations.TryGetValue(fullName, out config) && config != null && config.Value != null)
                return LanguagePrimitives.IsTrue(config.Value);
            return false;
        }
    }
}
