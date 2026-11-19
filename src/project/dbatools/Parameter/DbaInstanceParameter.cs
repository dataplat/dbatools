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
    /// <summary>
    /// Input converter for instance information
    /// </summary>
    public partial class DbaInstanceParameter
    {
        /// <summary>
        /// Name of the computer as resolvable by DNS
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public string ComputerName
        {
            get
            {
                // Pretend to be localhost for all non-sql functions
                if (_ComputerName == "(localdb)")
                    return "localhost";
                return _ComputerName;
            }
        }

        /// <summary>
        /// Name of the instance on the target server
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Optional)]
        public string InstanceName
        {
            get
            {
                if (String.IsNullOrEmpty(_InstanceName))
                    return "MSSQLSERVER";
                return _InstanceName;
            }
        }

        /// <summary>
        /// The port over which to connect to the server. Only present if non-default
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Optional)]
        public int Port
        {
            get
            {
                if (_Port == 0 && String.IsNullOrEmpty(_InstanceName))
                    return 1433;
                return _Port;
            }
        }

        /// <summary>
        /// The network protocol to connect over
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public SqlConnectionProtocol NetworkProtocol
        {
            get
            {
                return _NetworkProtocol;
            }
        }

        /// <summary>
        /// Verifies, whether the specified computer is localhost or not.
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public bool IsLocalHost
        {
            get
            {
                // Pretend to be localhost for all non-sql functions
                if (_ComputerName == "(localdb)")
                    return true;
                return Utility.Validation.IsLocalhost(_ComputerName);
            }
        }

        /// <summary>
        /// Full name of the instance, including the server-name
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public string FullName
        {
            get
            {
                if (!String.IsNullOrEmpty(_NamedPipePath)) { return _NamedPipePath; }
                string temp = _ComputerName;
                if (_Port > 0) { temp += (":" + _Port); }
                if (!String.IsNullOrEmpty(_InstanceName)) { temp += ("\\" + _InstanceName); }
                return temp;
            }
        }

        /// <summary>
        /// Full name of the instance, including the server-name, used when connecting via SMO
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public string FullSmoName
        {
            get
            {
                if (!String.IsNullOrEmpty(_NamedPipePath)) { return "NP:" + _NamedPipePath; }
                string temp = _ComputerName;
                if (_NetworkProtocol == SqlConnectionProtocol.NP) { temp = "NP:" + temp; }
                if (_NetworkProtocol == SqlConnectionProtocol.TCP) { temp = "TCP:" + temp; }
                if (!String.IsNullOrEmpty(_InstanceName) && _Port > 0) { return String.Format(@"{0}\{1},{2}", temp, _InstanceName, _Port); }
                if (_Port > 0) { return temp + "," + _Port; }
                if (!String.IsNullOrEmpty(_InstanceName)) { return temp + "\\" + _InstanceName; }
                return temp;
            }
        }

        /// <summary>
        /// Full name of the instance sanitized for use in file names.
        /// Replaces all Windows invalid filename characters (including : \ / | ? * " &lt; &gt;) with underscores.
        /// Safe to use as part of a filename or path component.
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public string FileNameFriendly
        {
            get
            {
                string temp = _ComputerName;
                if (!String.IsNullOrEmpty(_NamedPipePath))
                {
                    Match pipeSegment = Regex.Match(_NamedPipePath, @"\\pipe\\([^\\]+)\\", RegexOptions.IgnoreCase);
                    if (pipeSegment.Success && !String.IsNullOrEmpty(pipeSegment.Groups[1].Value))
                    {
                        temp = temp + "_" + pipeSegment.Groups[1].Value;
                    }
                    // If a future pipe shape has no pipe segment to extract, keep the server name fallback compact and safe.
                    return SanitizeFileName("NP_" + temp);
                }

                if (_NetworkProtocol == SqlConnectionProtocol.NP) { temp = "NP_" + temp; }
                if (_NetworkProtocol == SqlConnectionProtocol.TCP) { temp = "TCP_" + temp; }

                string result;
                if (!String.IsNullOrEmpty(_InstanceName) && _Port > 0)
                {
                    result = String.Format(@"{0}_{1}_{2}", temp, _InstanceName, _Port);
                }
                else if (_Port > 0)
                {
                    result = temp + "_" + _Port;
                }
                else if (!String.IsNullOrEmpty(_InstanceName))
                {
                    result = temp + "_" + _InstanceName;
                }
                else
                {
                    result = temp;
                }

                return SanitizeFileName(result);
            }
        }

        /// <summary>
        /// Name of the computer as used in an SQL Statement
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public string SqlComputerName
        {
            get { return "[" + ComputerName + "]"; }
        }

        /// <summary>
        /// Name of the instance as used in an SQL Statement
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public string SqlInstanceName
        {
            get
            {
                if (String.IsNullOrEmpty(_InstanceName))
                    return "[MSSQLSERVER]";
                return "[" + _InstanceName + "]";
            }
        }

        /// <summary>
        /// Full name of the instance, including the server-name as used in an SQL statement
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public string SqlFullName
        {
            get
            {
                if (String.IsNullOrEmpty(_InstanceName)) { return "[" + _ComputerName + "]"; }
                return "[" + _ComputerName + "\\" + _InstanceName + "]";
            }
        }

        /// <summary>
        /// Whether the input is a connection string
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public bool IsConnectionString { get; private set; }

        /// <summary>
        /// The original object passed to the parameter class.
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public object InputObject;

        private string _ComputerName;
        private string _InstanceName;
        private string _NamedPipePath;
        private int _Port;
        private SqlConnectionProtocol _NetworkProtocol = SqlConnectionProtocol.Any;
        private static readonly char[] InvalidFileNameChars = Path.GetInvalidFileNameChars()
            .Concat(new char[] { '<', '>', ':', '"', '/', '\\', '|', '?', '*' })
            .Distinct()
            .ToArray();

        private static string SanitizeFileName(string value)
        {
            char[] chars = value.ToCharArray();
            for (int i = 0; i < chars.Length; i++)
            {
                if (Array.IndexOf(InvalidFileNameChars, chars[i]) >= 0)
                    chars[i] = '_';
            }

            return new string(chars);
        }

        /// <summary>
        /// What kind of object was bound to the parameter class? For efficiency's purposes.
        /// </summary>
        public DbaInstanceInputType Type
        {
            get
            {
                try
                {
                    PSObject tempObject = new PSObject(InputObject);
                    string typeName = tempObject.TypeNames[0].ToLower();

                    switch (typeName)
                    {
                        case "microsoft.sqlserver.management.smo.server":
                            return DbaInstanceInputType.Server;
                        case "microsoft.sqlserver.management.smo.linkedserver":
                            return DbaInstanceInputType.Linked;
                        case "microsoft.sqlserver.management.registeredservers.registeredserver":
                            return DbaInstanceInputType.RegisteredServer;
                        case "microsoft.data.sqlclient.sqlconnection":
                            return DbaInstanceInputType.SqlConnection;
                        default:
                            return DbaInstanceInputType.Default;
                    }
                }
                catch { return DbaInstanceInputType.Default; }
            }
        }

        /// <summary>
        /// Returns, whether a live SMO object was bound for the purpose of accessing LinkedServer functionality
        /// </summary>
        public bool LinkedLive
        {
            get
            {
                return (((DbaInstanceInputType.Linked | DbaInstanceInputType.Server) & Type) != 0);
            }
        }

        /// <summary>
        /// Returns the available Linked Server objects from live objects only
        /// </summary>
        public object LinkedServer
        {
            get
            {
                switch (Type)
                {
                    case DbaInstanceInputType.Linked:
                        return InputObject;
                    case DbaInstanceInputType.Server:
                        PSObject tempObject = new PSObject(InputObject);
                        return SmoServerExtensions.ReadPSProperty(tempObject, "LinkedServers");
                    default:
                        return null;
                }
            }
        }

        /// <summary>
        /// Converts the parameter class to its full name
        /// </summary>
        /// <param name="Input">The parameter class object to convert</param>
        [ParameterContract(ParameterContractType.Operator, ParameterContractBehavior.Conversion)]
        public static implicit operator string(DbaInstanceParameter Input)
        {
            return Input.FullName;
        }

    }
}
