using System;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Net;
using System.Net.NetworkInformation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Exceptions;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Parameter
{
    public partial class DbaInstanceParameter
    {
        /// <summary>
        /// Creates a DBA Instance Parameter from string
        /// </summary>
        /// <param name="Name">The name of the instance</param>
        public DbaInstanceParameter(string Name)
        {
            InputObject = Name;

            if (string.IsNullOrWhiteSpace(Name))
                throw new BloodyHellGiveMeSomethingToWorkWithException("Please provide an instance name", "DbaInstanceParameter");

            if (Name == ".")
            {
                _ComputerName = Name;
                _NetworkProtocol = SqlConnectionProtocol.NP;
                return;
            }

            string tempString = Name.Trim();
            tempString = Regex.Replace(tempString, @"^\[(.*)\]$", "$1");

            if (UtilityHost.IsLike(tempString, @".\*"))
            {
                _ComputerName = ".";
                _NetworkProtocol = SqlConnectionProtocol.NP;

                string instanceName = tempString.Substring(2);

                if (!Utility.Validation.IsValidInstanceName(instanceName))
                    throw new ArgumentException(String.Format("Failed to interpret instance name: '{0}' is not a legal name", instanceName));

                _InstanceName = instanceName;

                return;
            }

            if (UtilityHost.IsLike(tempString, "*.WORKGROUP"))
                tempString = Regex.Replace(tempString, @"\.WORKGROUP$", "", RegexOptions.IgnoreCase);

            // Handle and clear protocols. Otherwise it'd make port detection unnecessarily messy
            if (Regex.IsMatch(tempString, "^TCP:", RegexOptions.IgnoreCase)) // TODO: Use case insensitive String.StartsWith()
            {
                _NetworkProtocol = SqlConnectionProtocol.TCP;
                tempString = tempString.Substring(4);
            }
            if (Regex.IsMatch(tempString, "^NP:", RegexOptions.IgnoreCase)) // TODO: Use case insensitive String.StartsWith()
            {
                _NetworkProtocol = SqlConnectionProtocol.NP;
                tempString = tempString.Substring(3);
            }

            // Named Pipe path notation interpretation
            if (Regex.IsMatch(tempString, @"^\\\\[^\\]+\\pipe\\([^\\]+\\){0,1}[t]{0,1}sql\\query$", RegexOptions.IgnoreCase))
            {
                try
                {
                    _NetworkProtocol = SqlConnectionProtocol.NP;

                    _ComputerName = Regex.Match(tempString, @"^\\\\([^\\]+)\\").Groups[1].Value;

                    Match namedPipeInstance = Regex.Match(tempString, @"\\MSSQL\$([^\\]+)\\", RegexOptions.IgnoreCase);
                    if (namedPipeInstance.Success)
                        _InstanceName = namedPipeInstance.Groups[1].Value;
                    // Non-standard pipes such as WID cannot be split into server + instance, so keep the full path.
                    else if (!Regex.IsMatch(tempString, @"^\\\\[^\\]+\\pipe\\[t]{0,1}sql\\query$", RegexOptions.IgnoreCase))
                    {
                        // Leave _InstanceName unset; InstanceName falls back to MSSQLSERVER for WID/default-instance pipes.
                        _NamedPipePath = tempString;
                    }
                }
                catch (Exception e)
                {
                    throw new ArgumentException(String.Format("Failed to interpret named pipe path notation: {0} | {1}", InputObject, e.Message), e);
                }

                return;
            }

            // Connection String interpretation
            try
            {
                Microsoft.Data.SqlClient.SqlConnectionStringBuilder connectionString =
                    new Microsoft.Data.SqlClient.SqlConnectionStringBuilder(tempString);
                DbaInstanceParameter tempParam = new DbaInstanceParameter(connectionString.DataSource);
                _ComputerName = tempParam.ComputerName;
                if (tempParam.InstanceName != "MSSQLSERVER")
                {
                    _InstanceName = tempParam.InstanceName;
                }
                if (tempParam.Port != 1433)
                {
                    _Port = tempParam.Port;
                }
                _NetworkProtocol = tempParam.NetworkProtocol;
                _NamedPipePath = tempParam._NamedPipePath;

                if (!String.IsNullOrEmpty(_NamedPipePath))
                {
                    connectionString.DataSource = FullSmoName;
                    InputObject = connectionString.ConnectionString;
                }

                if (UtilityHost.IsLike(tempString, @"(localdb)\*"))
                    _NetworkProtocol = SqlConnectionProtocol.NP;

                IsConnectionString = true;

                return;
            }
            catch (ArgumentException ex)
            {
                string name = "unknown";
                try
                {
                    name = ex.TargetSite.GetParameters()[0].Name;
                }
                catch
                {
                }
                if (name == "keyword")
                {
                    throw;
                }
            }
            catch (FormatException)
            {
                throw;
            }
            catch { }

            // Handle bracket-enclosed IPv6 with optional port, e.g. [::1]:1433 or [::1]
            if (tempString.StartsWith("["))
            {
                int closeBracket = tempString.IndexOf(']');
                if (closeBracket > 1)
                {
                    _ComputerName = tempString.Substring(1, closeBracket - 1);
                    string remainder = tempString.Substring(closeBracket + 1);
                    if (remainder.Length > 0 && (remainder[0] == ':' || remainder[0] == ','))
                    {
                        if (Int32.TryParse(remainder.Substring(1), out int port) && port <= 65535)
                        {
                            _Port = port;
                        }
                        else
                        {
                            throw new PSArgumentException(String.Format("Failed to parse instance name: {0}", Name));
                        }
                    }
                    else if (remainder.Length > 0)
                    {
                        throw new PSArgumentException(String.Format("Failed to parse instance name: {0}", Name));
                    }
                    return;
                }
            }

            // Case: Default instance | Instance by port
            if (tempString.Split('\\').Length == 1)
            {
                if (Regex.IsMatch(tempString, @"[:,]\d{1,5}$") && !Regex.IsMatch(tempString, RegexHelper.IPv6) && ((tempString.Split(':').Length == 2) || (tempString.Split(',').Length == 2)))
                {
                    char delimiter;
                    if (Regex.IsMatch(tempString, @"[:]\d{1,5}$"))
                        delimiter = ':';
                    else
                        delimiter = ',';

                    try
                    {
                        Int32.TryParse(tempString.Split(delimiter)[1], out _Port);
                        if (_Port > 65535) { throw new PSArgumentException("Failed to parse instance name: " + tempString); }
                        tempString = tempString.Split(delimiter)[0];
                    }
                    catch
                    {
                        throw new PSArgumentException("Failed to parse instance name: " + Name);
                    }
                }

                if (Utility.Validation.IsValidComputerTarget(tempString))
                {
                    _ComputerName = tempString;
                }

                else
                {
                    throw new PSArgumentException("Failed to parse instance name: " + Name);
                }
            }

            // Case: Named instance
            else if (tempString.Split('\\').Length == 2)
            {
                string tempComputerName = tempString.Split('\\')[0];
                string tempInstanceName = tempString.Split('\\')[1];

                if (Regex.IsMatch(tempComputerName, @"[:,]\d{1,5}$") && !Regex.IsMatch(tempComputerName, RegexHelper.IPv6))
                {
                    char delimiter;
                    if (Regex.IsMatch(tempComputerName, @"[:]\d{1,5}$"))
                        delimiter = ':';
                    else
                        delimiter = ',';

                    try
                    {
                        Int32.TryParse(tempComputerName.Split(delimiter)[1], out _Port);
                        if (_Port > 65535) { throw new PSArgumentException("Failed to parse instance name: " + Name); }
                        tempComputerName = tempComputerName.Split(delimiter)[0];
                    }
                    catch
                    {
                        throw new PSArgumentException("Failed to parse instance name: " + Name);
                    }
                }
                else if (Regex.IsMatch(tempInstanceName, @"[:,]\d{1,5}$") && !Regex.IsMatch(tempInstanceName, RegexHelper.IPv6))
                {
                    char delimiter;
                    if (Regex.IsMatch(tempString, @"[:]\d{1,5}$"))
                        delimiter = ':';
                    else
                        delimiter = ',';

                    try
                    {
                        Int32.TryParse(tempInstanceName.Split(delimiter)[1], out _Port);
                        if (_Port > 65535) { throw new PSArgumentException("Failed to parse instance name: " + Name); }
                        tempInstanceName = tempInstanceName.Split(delimiter)[0];
                    }
                    catch
                    {
                        throw new PSArgumentException("Failed to parse instance name: " + Name);
                    }
                }

                // LocalDBs mostly ignore regular Instance Name rules, so that validation is only relevant for regular connections
                if (UtilityHost.IsLike(tempComputerName, "(localdb)") || (Utility.Validation.IsValidComputerTarget(tempComputerName) && Utility.Validation.IsValidInstanceName(tempInstanceName, true)))
                {
                    if (UtilityHost.IsLike(tempComputerName, "(localdb)"))
                        _ComputerName = "(localdb)";
                    else
                        _ComputerName = tempComputerName;
                    if ((tempInstanceName.ToLower() != "default") && (tempInstanceName.ToLower() != "mssqlserver"))
                        _InstanceName = tempInstanceName;
                }

                else
                {
                    throw new PSArgumentException(string.Format("Failed to parse instance name: {0}. Computer Name: {1}, Instance {2}", Name, tempComputerName, tempInstanceName));
                }
            }

            // Case: Bad input
            else { throw new PSArgumentException("Failed to parse instance name: " + Name); }
        }

        /// <summary>
        /// Creates a DBA Instance Parameter from an IPAddress
        /// </summary>
        /// <param name="Address"></param>
    }
}
