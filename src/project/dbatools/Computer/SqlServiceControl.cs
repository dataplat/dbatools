using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Management;
using System.Management.Automation;
using System.Threading;

namespace Dataplat.Dbatools.Computer
{
    /// <summary>
    /// One SQL Server Windows service as Update-ServiceStatus handles it: the Win32_Service it
    /// controls plus the Status and Message the helper adds to the service object.
    /// </summary>
    public sealed class SqlServiceControlItem
    {
        /// <summary>The computer the service runs on.</summary>
        public string ComputerName;

        /// <summary>The Windows service name, e.g. MSSQLSERVER or SQLAgent$INST1.</summary>
        public string ServiceName;

        /// <summary>The dbatools service type (Engine or Agent).</summary>
        public string ServiceType;

        /// <summary>The SQL Server instance name.</summary>
        public string InstanceName;

        /// <summary>Get-DbaService's ServicePriority: 200 for the engine, 100 for the others.</summary>
        public int ServicePriority;

        /// <summary>The Win32_Service State, refreshed after a control request.</summary>
        public string State;

        /// <summary>The Win32_Service StartMode.</summary>
        public string StartMode;

        /// <summary>Successful, "Successful " (exit code 10) or Failed.</summary>
        public string Status;

        /// <summary>The Update-ServiceStatus message for the outcome.</summary>
        public string Message;

        /// <summary>The control request's exit code: the Win32_Service return value, or -1 (timed out), -2 (failed after the request), -3 (state unreadable).</summary>
        public int ExitCode;
    }

    /// <summary>
    /// Native core of private/functions/Update-ServiceStatus.ps1 for SQL Server services, used by
    /// the Agent-aware engine restart of Enable/Disable-DbaAgHadr and reusable by Stop-, Start- and
    /// Restart-DbaService. It keeps the helper's order (stop ascending ServicePriority, start
    /// descending), its skip rules, its 60 second timeout with 200 ms polling, its exit codes and its
    /// Status and Message text. Win32_Service is reached with System.Management (DCOM), the transport
    /// the helper prefers for its CIM session.
    /// </summary>
    public static class SqlServiceControl
    {
        /// <summary>
        /// The services of one instance with the given types, as Get-DbaService -ComputerName
        /// -InstanceName -Type returns them, read from Win32_Service. Types other than Engine and
        /// Agent are not supported here. A type the instance lacks (the Agent of an Express
        /// instance) is simply absent.
        /// </summary>
        /// <param name="computerName">The target computer.</param>
        /// <param name="credential">The Windows credential, or null for the current identity.</param>
        /// <param name="instanceName">The SQL Server instance name.</param>
        /// <param name="types">Engine and/or Agent.</param>
        /// <returns>The services found, in the order of <paramref name="types"/>.</returns>
        public static List<SqlServiceControlItem> GetInstanceServices(string computerName, PSCredential credential, string instanceName, params string[] types)
        {
            ManagementScope scope = Connect(computerName, credential);
            List<SqlServiceControlItem> result = new List<SqlServiceControlItem>();
            foreach (string type in types)
            {
                string serviceName = GetServiceName(instanceName, type);
                ManagementObject service = QueryService(scope, serviceName, "*");
                if (service == null)
                    continue;
                SqlServiceControlItem item = new SqlServiceControlItem();
                item.ComputerName = computerName;
                item.ServiceName = Convert.ToString(service["Name"]);
                item.ServiceType = String.Equals(type, "Engine", StringComparison.OrdinalIgnoreCase) ? "Engine" : "Agent";
                item.InstanceName = instanceName;
                item.ServicePriority = item.ServiceType == "Engine" ? 200 : 100;
                item.State = Convert.ToString(service["State"]);
                item.StartMode = Convert.ToString(service["StartMode"]);
                result.Add(item);
            }
            return result;
        }

        /// <summary>
        /// Runs Update-ServiceStatus -Action stop|start over the services and returns the ones it
        /// sent a request to, which are the objects the helper outputs. Services already in the
        /// wanted state, and disabled services asked to start, get their Status and Message set but
        /// are not returned, as in the helper.
        /// </summary>
        /// <param name="computerName">The computer the services run on.</param>
        /// <param name="credential">The Windows credential, or null for the current identity.</param>
        /// <param name="services">The services to control.</param>
        /// <param name="action">stop or start.</param>
        /// <param name="timeoutSeconds">Seconds to wait for each priority group; 0 waits forever.</param>
        /// <param name="cancellation">Stops the wait when the pipeline is stopped.</param>
        /// <returns>The services a request was sent to, with Status, Message, State and ExitCode set.</returns>
        public static List<SqlServiceControlItem> Update(string computerName, PSCredential credential, IList<SqlServiceControlItem> services, string action, int timeoutSeconds, CancellationToken cancellation)
        {
            ManagementScope scope = Connect(computerName, credential);
            bool stop = String.Equals(action, "stop", StringComparison.OrdinalIgnoreCase);
            if (!stop && !String.Equals(action, "start", StringComparison.OrdinalIgnoreCase))
                throw new ArgumentException("action is stop or start", "action");
            string actionText = stop ? "stopped" : "started";
            string methodName = stop ? "StopService" : "StartService";
            string desiredState = stop ? "Stopped" : "Running";
            string undesiredState = stop ? "Running" : "Stopped";
            string[] errorCodes = ServiceErrorMessages.Resolve(0);

            // PS: Sort-Object ServicePriority, descending unless the action is stop.
            List<int> priorities = new List<int>();
            foreach (SqlServiceControlItem service in services)
            {
                if (!priorities.Contains(service.ServicePriority))
                    priorities.Add(service.ServicePriority);
            }
            priorities.Sort();
            if (!stop)
                priorities.Reverse();

            List<SqlServiceControlItem> output = new List<SqlServiceControlItem>();
            foreach (int priority in priorities)
            {
                List<SqlServiceControlItem> pending = new List<SqlServiceControlItem>();
                List<SqlServiceControlItem> acted = new List<SqlServiceControlItem>();
                // PS: _CimObject (the last Win32_Service read) and ServiceState (the state the wait last saw).
                Dictionary<SqlServiceControlItem, string> currentState = new Dictionary<SqlServiceControlItem, string>();
                Dictionary<SqlServiceControlItem, string> observed = new Dictionary<SqlServiceControlItem, string>();
                foreach (SqlServiceControlItem service in services)
                {
                    if (service.ServicePriority != priority)
                        continue;
                    if ((service.State == "Running" && !stop) || (service.State == "Stopped" && stop))
                    {
                        service.Status = "Successful";
                        service.Message = String.Format("The service is already {0}, no action required", actionText);
                        continue;
                    }
                    if (service.StartMode == "Disabled" && !stop)
                    {
                        service.Status = "Failed";
                        service.Message = String.Format("The service is disabled and cannot be {0}", actionText);
                        continue;
                    }

                    // PS: a fresh Win32_Service instance, then Invoke-CimMethod.
                    ManagementObject fresh = QueryService(scope, service.ServiceName, "*");
                    if (fresh == null)
                        throw new InvalidOperationException(String.Format("Failed to retrieve service name {0} from the CIM object collection - the service will not be processed", service.ServiceName));
                    currentState[service] = Convert.ToString(fresh["State"]);
                    ManagementBaseObject invokeResult = fresh.InvokeMethod(methodName, null, null);
                    service.ExitCode = Convert.ToInt32(invokeResult["ReturnValue"]);
                    // PS: ServiceState starts as the invoke result's State, which is empty.
                    observed[service] = null;
                    acted.Add(service);
                    pending.Add(service);
                }

                Stopwatch elapsed = Stopwatch.StartNew();
                while (pending.Count > 0)
                {
                    foreach (SqlServiceControlItem service in pending.ToArray())
                    {
                        try
                        {
                            ManagementObject refreshed = QueryService(scope, service.ServiceName, "State");
                            // PS: an empty refresh keeps the previous CIM object, and with it the previous state.
                            if (refreshed != null)
                                currentState[service] = Convert.ToString(refreshed["State"]);
                            observed[service] = currentState[service];
                        }
                        catch (Exception)
                        {
                            // PS: any refresh failure ends the wait for this service as exit code -3.
                            service.ExitCode = -3;
                            observed[service] = "Unknown";
                            pending.Remove(service);
                            continue;
                        }

                        // Failed or succeeded
                        if (service.ExitCode != 0 || observed[service] == desiredState)
                        {
                            pending.Remove(service);
                            continue;
                        }
                        // PS: "Failed after being in the Pending state" - checked on every refresh.
                        if (observed[service] == undesiredState)
                        {
                            service.ExitCode = -2;
                            pending.Remove(service);
                            continue;
                        }
                        // Timed out
                        if (timeoutSeconds > 0 && elapsed.Elapsed.TotalSeconds > timeoutSeconds)
                        {
                            service.ExitCode = -1;
                            pending.Remove(service);
                        }
                    }
                    if (pending.Count > 0 && cancellation.WaitHandle.WaitOne(200))
                        throw new OperationCanceledException(cancellation);
                }

                foreach (SqlServiceControlItem service in acted)
                {
                    if (service.ExitCode == 0)
                        service.Status = "Successful";
                    else if (service.ExitCode == 10)
                        service.Status = "Successful "; // Already running - FullText service is started automatically
                    else
                        service.Status = "Failed";

                    string errorMessage = service.ExitCode >= 0 && service.ExitCode < errorCodes.Length ? errorCodes[service.ExitCode] : "Unknown error.";
                    if (service.ExitCode == -2)
                        service.Message = String.Format("The service failed to {0}.", action.ToLowerInvariant());
                    else if (service.ExitCode == -1)
                        service.Message = String.Format("The attempt to {0} the service has timed out.", action.ToLowerInvariant());
                    else if (service.ExitCode == 0)
                        service.Message = String.Format("Service was successfully {0}.", actionText);
                    else
                        service.Message = String.Format("The attempt to {0} the service returned the following error: {1}", action.ToLowerInvariant(), errorMessage);
                    // PS: Refresh service state for the object
                    if (!String.IsNullOrEmpty(observed[service]))
                        service.State = observed[service];
                    output.Add(service);
                }
            }
            return output;
        }

        /// <summary>The Windows service name of an instance's engine or Agent.</summary>
        /// <param name="instanceName">The SQL Server instance name.</param>
        /// <param name="type">Engine or Agent.</param>
        /// <returns>MSSQLSERVER, MSSQL$name, SQLSERVERAGENT or SQLAgent$name.</returns>
        public static string GetServiceName(string instanceName, string type)
        {
            bool isDefault = String.IsNullOrEmpty(instanceName) || String.Equals(instanceName, "MSSQLSERVER", StringComparison.OrdinalIgnoreCase);
            if (String.Equals(type, "Engine", StringComparison.OrdinalIgnoreCase))
                return isDefault ? "MSSQLSERVER" : "MSSQL$" + instanceName;
            if (String.Equals(type, "Agent", StringComparison.OrdinalIgnoreCase))
                return isDefault ? "SQLSERVERAGENT" : "SQLAgent$" + instanceName;
            throw new ArgumentException("type is Engine or Agent", "type");
        }

        private static ManagementScope Connect(string computerName, PSCredential credential)
        {
            ConnectionOptions options = new ConnectionOptions();
            if (credential != null)
            {
                // The WMI connection API takes the password as text; it has no SecureString form.
                System.Net.NetworkCredential netCredential = credential.GetNetworkCredential();
                options.Username = String.IsNullOrEmpty(netCredential.Domain) ? netCredential.UserName : netCredential.Domain + "\\" + netCredential.UserName;
                options.Password = netCredential.Password;
            }
            ManagementScope scope = new ManagementScope(String.Format("\\\\{0}\\root\\cimv2", computerName), options);
            scope.Connect();
            return scope;
        }

        private static ManagementObject QueryService(ManagementScope scope, string serviceName, string properties)
        {
            // WQL string literals escape the backslash first, then the single quote.
            string escaped = serviceName.Replace("\\", "\\\\").Replace("'", "\\'");
            ObjectQuery query = new ObjectQuery(String.Format("SELECT {0} FROM Win32_Service WHERE Name = '{1}'", properties, escaped));
            using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(scope, query))
            {
                foreach (ManagementObject service in searcher.Get())
                    return service;
            }
            return null;
        }
    }
}
