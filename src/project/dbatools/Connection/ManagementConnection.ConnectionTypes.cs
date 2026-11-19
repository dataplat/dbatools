using System;
using System.Collections.Generic;
using System.Management.Automation;
using Microsoft.Management.Infrastructure;
using Microsoft.Management.Infrastructure.Options;

namespace Dataplat.Dbatools.Connection
{
    public partial class ManagementConnection
    {

        /// <summary>
        /// Returns the next connection type to try.
        /// </summary>
        /// <param name="ExcludedTypes">Exclude any type already tried and failed</param>
        /// <param name="Force">Overrides the timeout on bad connections</param>
        /// <returns>The next type to try.</returns>
        public ManagementConnectionType GetConnectionType(ManagementConnectionType ExcludedTypes, bool Force)
        {
            ManagementConnectionType temp = ExcludedTypes | DisabledConnectionTypes;


            if (((ManagementConnectionType.CimRM & temp) == 0) &&
                ((CimRM & ManagementConnectionProtocolState.Success) != 0))
                return ManagementConnectionType.CimRM;

            if (((ManagementConnectionType.CimDCOM & temp) == 0) &&
                ((CimDCOM & ManagementConnectionProtocolState.Success) != 0))
                return ManagementConnectionType.CimDCOM;

            if (((ManagementConnectionType.Wmi & temp) == 0) && ((Wmi & ManagementConnectionProtocolState.Success) != 0))
                return ManagementConnectionType.Wmi;

            if (((ManagementConnectionType.PowerShellRemoting & temp) == 0) &&
                ((PowerShellRemoting & ManagementConnectionProtocolState.Success) != 0))
                return ManagementConnectionType.PowerShellRemoting;



            if (((ManagementConnectionType.CimRM & temp) == 0) &&
                ((CimRM & ManagementConnectionProtocolState.Unknown) != 0))
                return ManagementConnectionType.CimRM;

            if (((ManagementConnectionType.CimDCOM & temp) == 0) &&
                ((CimDCOM & ManagementConnectionProtocolState.Unknown) != 0))
                return ManagementConnectionType.CimDCOM;

            if (((ManagementConnectionType.Wmi & temp) == 0) && ((Wmi & ManagementConnectionProtocolState.Unknown) != 0))
                return ManagementConnectionType.Wmi;

            if (((ManagementConnectionType.PowerShellRemoting & temp) == 0) &&
                ((PowerShellRemoting & ManagementConnectionProtocolState.Unknown) != 0))
                return ManagementConnectionType.PowerShellRemoting;



            if (((ManagementConnectionType.CimRM & temp) == 0) &&
                ((CimRM & ManagementConnectionProtocolState.Error) != 0) &&
                ((LastCimRM + ConnectionHost.BadConnectionTimeout < DateTime.Now) | Force))
                return ManagementConnectionType.CimRM;

            if (((ManagementConnectionType.CimDCOM & temp) == 0) &&
                ((CimDCOM & ManagementConnectionProtocolState.Error) != 0) &&
                ((LastCimDCOM + ConnectionHost.BadConnectionTimeout < DateTime.Now) | Force))
                return ManagementConnectionType.CimDCOM;

            if (((ManagementConnectionType.Wmi & temp) == 0) && ((Wmi & ManagementConnectionProtocolState.Error) != 0) &&
                ((LastWmi + ConnectionHost.BadConnectionTimeout < DateTime.Now) | Force))
                return ManagementConnectionType.Wmi;

            if (((ManagementConnectionType.PowerShellRemoting & temp) == 0) &&
                ((PowerShellRemoting & ManagementConnectionProtocolState.Error) != 0) &&
                ((LastPowerShellRemoting + ConnectionHost.BadConnectionTimeout < DateTime.Now) | Force))
                return ManagementConnectionType.PowerShellRemoting;


            // Do not try to use disabled protocols

            throw new PSInvalidOperationException("Multiple protocol connections were attempted, but no successful connections could be established with the specified computer.");
        }

        /// <summary>
        /// Returns a list of all available connection types whose inherent timeout has expired.
        /// </summary>
        /// <param name="Timestamp">All last connection failures older than this point in time are considered to be expired</param>
        /// <returns>A list of all valid connection types</returns>
        public List<ManagementConnectionType> GetConnectionTypesTimed(DateTime Timestamp)
        {
            List<ManagementConnectionType> types = new List<ManagementConnectionType>();

            if (((DisabledConnectionTypes & ManagementConnectionType.CimRM) == 0) &&
                ((CimRM == ManagementConnectionProtocolState.Success) || (LastCimRM < Timestamp)))
                types.Add(ManagementConnectionType.CimRM);

            if (((DisabledConnectionTypes & ManagementConnectionType.CimDCOM) == 0) &&
                ((CimDCOM == ManagementConnectionProtocolState.Success) || (LastCimDCOM < Timestamp)))
                types.Add(ManagementConnectionType.CimDCOM);

            if (((DisabledConnectionTypes & ManagementConnectionType.Wmi) == 0) &&
                ((Wmi == ManagementConnectionProtocolState.Success) || (LastWmi < Timestamp)))
                types.Add(ManagementConnectionType.Wmi);

            if (((DisabledConnectionTypes & ManagementConnectionType.PowerShellRemoting) == 0) &&
                ((PowerShellRemoting == ManagementConnectionProtocolState.Success) ||
                 (LastPowerShellRemoting < Timestamp)))
                types.Add(ManagementConnectionType.PowerShellRemoting);

            return types;
        }

        /// <summary>
        /// Returns a list of all available connection types whose inherent timeout has expired.
        /// </summary>
        /// <param name="Timespan">All last connection failures older than this far back into the past are considered to be expired</param>
        /// <returns>A list of all valid connection types</returns>
        public List<ManagementConnectionType> GetConnectionTypesTimed(TimeSpan Timespan)
        {
            return GetConnectionTypesTimed(DateTime.Now - Timespan);
        }



        internal void CopyTo(ManagementConnection Connection)
        {
            Connection.ComputerName = ComputerName;

            Connection.CimRM = CimRM;
            Connection.LastCimRM = LastCimRM;
            Connection.CimDCOM = CimDCOM;
            Connection.LastCimDCOM = LastCimDCOM;
            Connection.Wmi = Wmi;
            Connection.LastWmi = LastWmi;
            Connection.PowerShellRemoting = PowerShellRemoting;
            Connection.LastPowerShellRemoting = LastPowerShellRemoting;

            Connection.Credentials = Credentials;
            Connection.OverrideExplicitCredential = OverrideExplicitCredential;
            Connection.KnownBadCredentials = KnownBadCredentials;
            Connection.WindowsCredentialsAreBad = WindowsCredentialsAreBad;
        }



        /// <summary>
        /// Creates a new, empty connection object. Necessary for serialization.
        /// </summary>
        public ManagementConnection()
        {

        }

        /// <summary>
        /// Creates a new default connection object, containing only its computer's name and default results.
        /// </summary>
        /// <param name="ComputerName">The computer targeted. Will be forced to lowercase.</param>
        public ManagementConnection(string ComputerName)
        {
            this.ComputerName = ComputerName.ToLower();
            if (Utility.Validation.IsLocalhost(ComputerName))
                CimRM = ManagementConnectionProtocolState.Disabled;
        }

    }
}
