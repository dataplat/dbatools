using System;
using System.Collections.Generic;
using System.Management.Automation;
using Sqlcollaborative.Dbatools.Connection;

namespace Sqlcollaborative.Dbatools.Parameter
{
        
    /// <summary>
    /// Input converter for Computer Management Information
    /// </summary>
    public class DbaCmConnectionParameter
    {
        #region Fields of contract
        /// <summary>
        /// The resolved connection object
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory | ParameterContractBehavior.Conditional)]
        public ManagementConnection Connection;

        /// <summary>
        /// Whether input processing was successful
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory | ParameterContractBehavior.Arbiter)]
        public bool Success;

        /// <summary>
        /// The object actually passed to the class
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public object InputObject;
        #endregion Fields of contract

        /// <summary>
        /// Implicitly convert all connection parameter objects to the connection-type
        /// </summary>
        /// <param name="Input">The parameter object to convert</param>
        [ParameterContract(ParameterContractType.Operator, ParameterContractBehavior.Conversion)]
        public static implicit operator ManagementConnection(DbaCmConnectionParameter Input)
        {
            return Input.Connection;
        }

        /// <summary>
        /// Creates a new DbaWmConnectionParameter based on an input-name
        /// </summary>
        /// <param name="ComputerName">The name of the computer the connection is stored for.</param>
        public DbaCmConnectionParameter(string ComputerName)
        {
            InputObject = ComputerName;
            if (!Utility.Validation.IsValidComputerTarget(ComputerName))
            {
                Success = false;
                return;
            }


            bool test = false;
            try { test = ConnectionHost.Connections[ComputerName.ToLower()] != null; }
            catch { }

            if (test)
            {
                Connection = ConnectionHost.Connections[ComputerName.ToLower()];
            }

            else
            {
                Connection = new ManagementConnection(ComputerName.ToLower());
                ConnectionHost.Connections[Connection.ComputerName] = Connection;
            }

            Success = true;
        }

        /// <summary>
        /// Creates a new DbaWmConnectionParameter based on an already existing connection object.
        /// </summary>
        /// <param name="Connection">The connection to accept</param>
        public DbaCmConnectionParameter(ManagementConnection Connection)
        {
            InputObject = Connection;

            this.Connection = Connection;

            Success = true;
        }

        /// <summary>
        /// Tries to convert a generic input object into a true input.
        /// </summary>
        /// <param name="Input">Any damn object in the world</param>
        public DbaCmConnectionParameter(object Input)
        {
            InputObject = Input;
            PSObject tempInput = new PSObject(Input);
            string typeName = "";

            try { typeName = tempInput.TypeNames[0].ToLower(); }
            catch
            {
                Success = false;
                return;
            }

            switch (typeName)
            {
                case "Sqlcollaborative.Dbatools.connection.managementconnection":
                    try
                    {
                        ManagementConnection con = new ManagementConnection();
                        con.ComputerName = (string)tempInput.Properties["ComputerName"].Value;

                        con.CimRM = (ManagementConnectionProtocolState)tempInput.Properties["CimRM"].Value;
                        con.LastCimRM = (DateTime)tempInput.Properties["LastCimRM"].Value;
                        con.CimDCOM = (ManagementConnectionProtocolState)tempInput.Properties["CimDCOM"].Value;
                        con.LastCimDCOM = (DateTime)tempInput.Properties["LastCimDCOM"].Value;
                        con.Wmi = (ManagementConnectionProtocolState)tempInput.Properties["Wmi"].Value;
                        con.LastWmi = (DateTime)tempInput.Properties["LastWmi"].Value;
                        con.PowerShellRemoting = (ManagementConnectionProtocolState)tempInput.Properties["PowerShellRemoting"].Value;
                        con.LastPowerShellRemoting = (DateTime)tempInput.Properties["LastPowerShellRemoting"].Value;

                        con.Credentials = (PSCredential)tempInput.Properties["Credentials"].Value;
                        con.OverrideExplicitCredential = (bool)tempInput.Properties["OverrideExplicitCredential"].Value;
                        con.KnownBadCredentials = (List<PSCredential>)tempInput.Properties["KnownBadCredentials"].Value;
                        con.WindowsCredentialsAreBad = (bool)tempInput.Properties["WindowsCredentialsAreBad"].Value;
                        con.UseWindowsCredentials = (bool)tempInput.Properties["UseWindowsCredentials"].Value;

                        con.DisableBadCredentialCache = (bool)tempInput.Properties["DisableBadCredentialCache"].Value;
                        con.DisableCimPersistence = (bool)tempInput.Properties["DisableCimPersistence"].Value;
                        con.DisableCredentialAutoRegister = (bool)tempInput.Properties["DisableCredentialAutoRegister"].Value;
                        con.EnableCredentialFailover = (bool)tempInput.Properties["EnableCredentialFailover"].Value;

                    }
                    catch
                    {
                        Success = false;
                    }
                    break;

                default:
                    Success = false;
                    break;
            }
        }

        /// <summary>
        /// Creates a new DbaCmConnectionParameter based on an instance parameter
        /// </summary>
        /// <param name="Instance">The instance to interpret</param>
        public DbaCmConnectionParameter(DbaInstanceParameter Instance)
            : this(Instance.ComputerName)
        {

        }
    }
}