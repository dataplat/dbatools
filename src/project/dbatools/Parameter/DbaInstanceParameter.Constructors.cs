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
        public DbaInstanceParameter(Microsoft.Data.SqlClient.SqlConnection Connection)
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
            _NamedPipePath = tempParam._NamedPipePath;
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
                    // the extra checks break azure by enumerating, causing a new
                    // connection and sometimes altering the connection string
                    // so let's try to avoid that
                    try
                    {
                        if (tempInput.Properties["ComputerName"] != null)
                            _ComputerName = (string)SmoServerExtensions.ReadPSProperty(tempInput, "ComputerName");

                        if ((tempInput.Properties["NetPort"] != null) && ((Int32)SmoServerExtensions.ReadPSProperty(tempInput, "NetPort") != 1433))
                            _Port = (Int32)SmoServerExtensions.ReadPSProperty(tempInput, "NetPort");

                        if ((tempInput.Properties["DbaInstanceName"] != null) && ((string)SmoServerExtensions.ReadPSProperty(tempInput, "DbaInstanceName") != "MSSQLSERVER"))
                            _InstanceName = (string)SmoServerExtensions.ReadPSProperty(tempInput, "DbaInstanceName");

                        if (String.IsNullOrEmpty(_ComputerName))
                        {
                            if (tempInput.Properties["NetName"] != null)
                                _ComputerName = (string)SmoServerExtensions.ReadPSProperty(tempInput, "NetName");
                            else
                                _ComputerName = (new DbaInstanceParameter((string)SmoServerExtensions.ReadPSProperty(tempInput, "DomainInstanceName"))).ComputerName;
                            _InstanceName = (string)SmoServerExtensions.ReadPSProperty(tempInput, "InstanceName");
                            PSObject tempObject = new PSObject(SmoServerExtensions.ReadPSProperty(tempInput, "ConnectionContext"));
                            string tempConnectionString = (string)SmoServerExtensions.ReadPSProperty(tempObject, "ConnectionString");
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
                    }
                    catch (Exception e)
                    {
                        throw new PSArgumentException("Failed to interpret input as Instance: " + Input + " : " + e.Message, e);
                    }
                    if (String.IsNullOrEmpty(_ComputerName))
                        throw new PSArgumentException("Failed to interpret input as Instance, ComputerName empty: " + Input);
                    break;
                case "microsoft.sqlserver.management.smo.linkedserver":
                    try
                    {
                        _ComputerName = (string)SmoServerExtensions.ReadPSProperty(tempInput, "Name");
                    }
                    catch (Exception e)
                    {
                        throw new PSArgumentException("Failed to interpret input as Instance: " + Input, e);
                    }
                    break;
                case "microsoft.activedirectory.management.adcomputer":
                    try
                    {
                        _ComputerName = (string)SmoServerExtensions.ReadPSProperty(tempInput, "Name");

                        // We prefer using the dnshostname whenever possible
                        if (SmoServerExtensions.ReadPSProperty(tempInput, "DNSHostName") != null)
                        {
                            if (!String.IsNullOrEmpty((string)SmoServerExtensions.ReadPSProperty(tempInput, "DNSHostName")))
                                _ComputerName = (string)SmoServerExtensions.ReadPSProperty(tempInput, "DNSHostName");
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
                        DbaInstanceParameter parm = new DbaInstanceParameter((string)SmoServerExtensions.ReadPSProperty(tempInput, "ServerName"));
                        _ComputerName = parm.ComputerName;

                        if (parm.InstanceName != "MSSQLSERVER")
                            _InstanceName = parm.InstanceName;

                        if (parm.Port != 1433)
                            _Port = parm.Port;

                        _NetworkProtocol = parm.NetworkProtocol;
                        _NamedPipePath = parm._NamedPipePath;
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
    }
}
