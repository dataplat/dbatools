using System;
using System.Management.Automation;
using System.Net;
using System.Net.NetworkInformation;
using System.Text.RegularExpressions;
using Sqlcollaborative.Dbatools.Connection;
using Sqlcollaborative.Dbatools.Exceptions;
using Sqlcollaborative.Dbatools.Utility;

namespace Sqlcollaborative.Dbatools.Parameter
{
    /// <summary>
    /// Input converter for instance information
    /// </summary>
    public class DbaInstanceParameter
    {
        #region Fields of contract
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
        /// Name of the computer as used in an SQL Statement
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public string SqlComputerName
        {
            get { return "[" + _ComputerName + "]"; }
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
        #endregion Fields of contract

        private string _ComputerName;
        private string _InstanceName;
        private int _Port;
        private SqlConnectionProtocol _NetworkProtocol = SqlConnectionProtocol.Any;

        #region Uncontracted properties
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
                        case "system.data.sqlclient.sqlconnection":
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
                        return tempObject.Properties["LinkedServers"].Value;
                    default:
                        return null;
                }
            }
        }
        #endregion Uncontracted properties

        /// <summary>
        /// Converts the parameter class to its full name
        /// </summary>
        /// <param name="Input">The parameter class object to convert</param>
        [ParameterContract(ParameterContractType.Operator, ParameterContractBehavior.Conversion)]
        public static implicit operator string(DbaInstanceParameter Input)
        {
            return Input.FullName;
        }

        #region Constructors
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
            if (UtilityHost.IsLike(tempString, "*.WORKGROUP"))
                tempString = Regex.Replace(tempString, @"\.WORKGROUP$", "", RegexOptions.IgnoreCase);

            // Named Pipe path notation interpretation
            if (Regex.IsMatch(tempString, @"^\\\\[^\\]+\\pipe\\([^\\]+\\){0,1}sql\\query$", RegexOptions.IgnoreCase))
            {
                try
                {
                    _NetworkProtocol = SqlConnectionProtocol.NP;

                    _ComputerName = Regex.Match(tempString, @"^\\\\([^\\]+)\\").Groups[1].Value;

                    if (Regex.IsMatch(tempString, @"\\MSSQL\$[^\\]+\\", RegexOptions.IgnoreCase))
                        _InstanceName = Regex.Match(tempString, @"\\MSSQL\$([^\\]+)\\", RegexOptions.IgnoreCase).Groups[1].Value;
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
                System.Data.SqlClient.SqlConnectionStringBuilder connectionString =
                    new System.Data.SqlClient.SqlConnectionStringBuilder(tempString);
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

            // Handle and clear protocols. Otherwise it'd make port detection unneccessarily messy
            if (Regex.IsMatch(tempString, "^TCP:", RegexOptions.IgnoreCase)) //TODO: Use case insinsitive String.BeginsWith()
            {
                _NetworkProtocol = SqlConnectionProtocol.TCP;
                tempString = tempString.Substring(4);
            }
            if (Regex.IsMatch(tempString, "^NP:", RegexOptions.IgnoreCase)) // TODO: Use case insinsitive String.BeginsWith()
            {
                _NetworkProtocol = SqlConnectionProtocol.NP;
                tempString = tempString.Substring(3);
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
        public DbaInstanceParameter(IPAddress Address)
        {
            _ComputerName = Address.ToString();
            InputObject = Address;
        }

        /// <summary>
        /// Creates a DBA Instance Parameter from the reply to a ping
        /// </summary>
        /// <param name="Ping">The result of a ping</param>
        public DbaInstanceParameter(PingReply Ping)
        {
            _ComputerName = Ping.Address.ToString();
            InputObject = Ping;
        }

        /// <summary>
        /// Creates a DBA Instance Parameter from the result of a dns resolution
        /// </summary>
        /// <param name="Entry">The result of a dns resolution, to be used for targetting the default instance</param>
        public DbaInstanceParameter(IPHostEntry Entry)
        {
            _ComputerName = Entry.HostName;
            InputObject = Entry;
        }

        /// <summary>
        /// Creates a DBA Instance Parameter from an established SQL Connection
        /// </summary>
        /// <param name="Connection">The connection to reuse</param>
        public DbaInstanceParameter(System.Data.SqlClient.SqlConnection Connection)
        {
            InputObject = Connection;
            DbaInstanceParameter tempParam = new DbaInstanceParameter(Connection.DataSource);

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
        }

        /// <summary>
        /// Accept and understand discovery reports.
        /// </summary>
        /// <param name="Report">The report to interpret</param>
        public DbaInstanceParameter(Discovery.DbaInstanceReport Report)
            : this(Report.SqlInstance)
        {
            InputObject = Report;
        }

        /// <summary>
        /// Creates a DBA Instance parameter from any object
        /// </summary>
        /// <param name="Input">Object to parse</param>
        public DbaInstanceParameter(object Input)
        {
            InputObject = Input;
            PSObject tempInput = new PSObject(Input);
            string typeName = "";

            try { typeName = tempInput.TypeNames[0].ToLower(); }
            catch
            {
                throw new PSArgumentException("Failed to interpret input as Instance: " + Input);
            }

            typeName = typeName.Replace("Deserialized.", "");

            switch (typeName)
            {
                case "microsoft.sqlserver.management.smo.server":
                    try
                    {
                        if (tempInput.Properties["ServerType"] != null && (string)tempInput.Properties["ServerType"].Value.ToString() == "SqlAzureDatabase")
                            _ComputerName = (new DbaInstanceParameter((string)tempInput.Properties["Name"].Value)).ComputerName;
                        else
                        { 
                            if (tempInput.Properties["NetName"] != null)
                                _ComputerName = (string)tempInput.Properties["NetName"].Value;
                            else
                                _ComputerName = (new DbaInstanceParameter((string)tempInput.Properties["DomainInstanceName"].Value)).ComputerName;
                        }
                        _InstanceName = (string)tempInput.Properties["InstanceName"].Value;
                        PSObject tempObject = new PSObject(tempInput.Properties["ConnectionContext"].Value);

                        string tempConnectionString = (string)tempObject.Properties["ConnectionString"].Value;
                        tempConnectionString = tempConnectionString.Split(';')[0].Split('=')[1].Trim().Replace(" ", "");

                        if (Regex.IsMatch(tempConnectionString, @",\d{1,5}$") && (tempConnectionString.Split(',').Length == 2))
                        {
                            try { Int32.TryParse(tempConnectionString.Split(',')[1], out _Port); }
                            catch (Exception e)
                            {
                                throw new PSArgumentException("Failed to parse port number on connection string: " + tempConnectionString, e);
                            }
                            if (_Port > 65535) { throw new PSArgumentException("Failed to parse port number on connection string: " + tempConnectionString); }
                        }
                    }
                    catch (Exception e)
                    {
                        throw new PSArgumentException("Failed to interpret input as Instance: " + Input + " : " + e.Message, e);
                    }
                    break;
                case "microsoft.sqlserver.management.smo.linkedserver":
                    try
                    {
                        _ComputerName = (string)tempInput.Properties["Name"].Value;
                    }
                    catch (Exception e)
                    {
                        throw new PSArgumentException("Failed to interpret input as Instance: " + Input, e);
                    }
                    break;
                case "microsoft.activedirectory.management.adcomputer":
                    try
                    {
                        _ComputerName = (string)tempInput.Properties["Name"].Value;

                        // We prefer using the dnshostname whenever possible
                        if (tempInput.Properties["DNSHostName"].Value != null)
                        {
                            if (!String.IsNullOrEmpty((string)tempInput.Properties["DNSHostName"].Value))
                                _ComputerName = (string)tempInput.Properties["DNSHostName"].Value;
                        }
                    }
                    catch (Exception e)
                    {
                        throw new PSArgumentException("Failed to interpret input as Instance: " + Input, e);
                    }
                    break;
                case "microsoft.sqlserver.management.registeredservers.registeredserver":
                    try
                    {
                        //Pass the ServerName property of the SMO object to the string constrtuctor, 
                        //so we don't have to re-invent the wheel on instance name / port parsing
                        DbaInstanceParameter parm =
                            new DbaInstanceParameter((string) tempInput.Properties["ServerName"].Value);
                        _ComputerName = parm.ComputerName;

                        if (parm.InstanceName != "MSSQLSERVER")
                            _InstanceName = parm.InstanceName;

                        if (parm.Port != 1433)
                            _Port = parm.Port;
                    }
                    catch (Exception e)
                    {
                        throw new PSArgumentException("Failed to interpret input as Instance: " + Input, e);
                    }
                    break;
                default:
                    throw new PSArgumentException("Failed to interpret input as Instance: " + Input);
            }
        }
        #endregion Constructors

        /// <summary>
        /// Overrides the regular tostring to show something pleasant and useful
        /// </summary>
        /// <returns>The full SMO name</returns>
        public override string ToString()
        {
            return FullSmoName;
        }
    }
}