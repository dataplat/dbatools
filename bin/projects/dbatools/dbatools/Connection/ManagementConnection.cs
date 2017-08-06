using System;
using System.Collections.Generic;
using System.Management.Automation;
using Microsoft.Management.Infrastructure;
using Microsoft.Management.Infrastructure.Options;

namespace Sqlcollaborative.Dbatools.Connection
{
    /// <summary>
    /// Contains management connection information for a windows server
    /// </summary>
    [Serializable]
    public class ManagementConnection
    {
        /// <summary>
        /// The computer to connect to
        /// </summary>
        public string ComputerName { get; set; }

        #region Configuration

        /// <summary>
        /// Locally disables the caching of bad credentials
        /// </summary>
        public bool DisableBadCredentialCache
        {
            get
            {
                switch (_disableBadCredentialCache)
                {
                    case -1:
                        return false;
                    case 1:
                        return true;
                    default:
                        return ConnectionHost.DisableBadCredentialCache;
                }
            }
            set {
                _disableBadCredentialCache = value ? 1 : -1;
            }
        }

        private int _disableBadCredentialCache;

        /// <summary>
        /// Locally disables the caching of working credentials
        /// </summary>
        public bool DisableCredentialAutoRegister
        {
            get
            {
                switch (_disableCredentialAutoRegister)
                {
                    case -1:
                        return false;
                    case 1:
                        return true;
                    default:
                        return ConnectionHost.DisableCredentialAutoRegister;
                }
            }
            set
            {
                _disableCredentialAutoRegister = value ? 1 : -1;
            }
        }

        private int _disableCredentialAutoRegister;

        /// <summary>
        /// Locally overrides explicit credentials with working ones that were cached
        /// </summary>
        public bool OverrideExplicitCredential
        {
            get
            {
                switch (_overrideExplicitCredential)
                {
                    case -1:
                        return false;
                    case 1:
                        return true;
                    default:
                        return ConnectionHost.OverrideExplicitCredential;
                }
            }
            set
            {
                _overrideExplicitCredential = value ? 1 : -1;
                
            }
        }

        private int _overrideExplicitCredential;

        /// <summary>
        /// Locally enables automatic failover to working credentials, when passed credentials either are known, or turn out to not work.
        /// </summary>
        public bool EnableCredentialFailover
        {
            get
            {
                switch (_enableCredentialFailover)
                {
                    case -1:
                        return false;
                    case 1:
                        return true;
                    default:
                        return ConnectionHost.EnableCredentialFailover;
                }
            }
            set
            {
                _enableCredentialFailover = value ? 1 : -1;
            }
        }

        private int _enableCredentialFailover;

        /// <summary>
        /// Locally disables the persistence of Cim sessions used to connect to a target system.
        /// </summary>
        public bool DisableCimPersistence
        {
            get
            {
                switch (_disableCimPersistence)
                {
                    case -1:
                        return false;
                    case 1:
                        return true;
                    default:
                        return ConnectionHost.DisableCimPersistence;
                }
            }
            set
            {
                _disableCimPersistence = value ? 1 : -1;
            }
        }

        private int _disableCimPersistence;

        /// <summary>
        /// Connectiontypes that will never be used
        /// </summary>
        public ManagementConnectionType DisabledConnectionTypes
        {
            get
            {
                ManagementConnectionType temp = ManagementConnectionType.None;
                if (CimRM == ManagementConnectionProtocolState.Disabled)
                {
                    temp = temp | ManagementConnectionType.CimRM;
                }
                if (CimDCOM == ManagementConnectionProtocolState.Disabled)
                {
                    temp = temp | ManagementConnectionType.CimDCOM;
                }
                if (Wmi == ManagementConnectionProtocolState.Disabled)
                {
                    temp = temp | ManagementConnectionType.Wmi;
                }
                if (PowerShellRemoting == ManagementConnectionProtocolState.Disabled)
                {
                    temp = temp | ManagementConnectionType.PowerShellRemoting;
                }
                return temp;
            }
            set
            {
                if ((value & ManagementConnectionType.CimRM) != 0)
                {
                    CimRM = ManagementConnectionProtocolState.Disabled;
                }
                else if ((CimRM & ManagementConnectionProtocolState.Disabled) != 0)
                {
                    CimRM = ManagementConnectionProtocolState.Unknown;
                }
                if ((value & ManagementConnectionType.CimDCOM) != 0)
                {
                    CimDCOM = ManagementConnectionProtocolState.Disabled;
                }
                else if ((CimDCOM & ManagementConnectionProtocolState.Disabled) != 0)
                {
                    CimDCOM = ManagementConnectionProtocolState.Unknown;
                }
                if ((value & ManagementConnectionType.Wmi) != 0)
                {
                    Wmi = ManagementConnectionProtocolState.Disabled;
                }
                else if ((Wmi & ManagementConnectionProtocolState.Disabled) != 0)
                {
                    Wmi = ManagementConnectionProtocolState.Unknown;
                }
                if ((value & ManagementConnectionType.PowerShellRemoting) != 0)
                {
                    PowerShellRemoting = ManagementConnectionProtocolState.Disabled;
                }
                else if ((PowerShellRemoting & ManagementConnectionProtocolState.Disabled) != 0)
                {
                    PowerShellRemoting = ManagementConnectionProtocolState.Unknown;
                }
            }
        }

        /// <summary>
        /// Restores all deviations from public policy back to default
        /// </summary>
        public void RestoreDefaultConfiguration()
        {
            _disableBadCredentialCache = 0;
            _disableCredentialAutoRegister = 0;
            _overrideExplicitCredential = 0;
            _disableCimPersistence = 0;
            _enableCredentialFailover = 0;
            OverrideConnectionPolicy = false;
        }

        #endregion Configuration

        #region Connection Stats
        /// <summary>
        /// Whether this connection adhers to the global connection lockdowns or not
        /// </summary>
        public bool OverrideConnectionPolicy = false;

        /// <summary>
        /// Did the last connection attempt using CimRM work?
        /// </summary>
        public ManagementConnectionProtocolState CimRM
        {
            get
            {
                if (!OverrideConnectionPolicy && ConnectionHost.DisableConnectionCimRM)
                    return ManagementConnectionProtocolState.Disabled;
                else
                    return _CimRM;
            }
            set { _CimRM = value; }
        }
        private ManagementConnectionProtocolState _CimRM = ManagementConnectionProtocolState.Unknown;

        /// <summary>
        /// When was the last connection attempt using CimRM?
        /// </summary>
        public DateTime LastCimRM;

        /// <summary>
        /// Did the last connection attempt using CimDCOM work?
        /// </summary>
        public ManagementConnectionProtocolState CimDCOM
        {
            get
            {
                if (!OverrideConnectionPolicy && ConnectionHost.DisableConnectionCimDCOM)
                    return ManagementConnectionProtocolState.Disabled;
                else
                    return _CimDCOM;
            }
            set { _CimDCOM = value; }
        }
        private ManagementConnectionProtocolState _CimDCOM = ManagementConnectionProtocolState.Unknown;

        /// <summary>
        /// When was the last connection attempt using CimRM?
        /// </summary>
        public DateTime LastCimDCOM;

        /// <summary>
        /// Did the last connection attempt using Wmi work?
        /// </summary>
        public ManagementConnectionProtocolState Wmi
        {
            get
            {
                if (!OverrideConnectionPolicy && ConnectionHost.DisableConnectionWMI)
                    return ManagementConnectionProtocolState.Disabled;
                else
                    return _Wmi;
            }
            set { _Wmi = value; }
        }
        private ManagementConnectionProtocolState _Wmi = ManagementConnectionProtocolState.Unknown;

        /// <summary>
        /// When was the last connection attempt using CimRM?
        /// </summary>
        public DateTime LastWmi;

        /// <summary>
        /// Did the last connection attempt using PowerShellRemoting work?
        /// </summary>
        public ManagementConnectionProtocolState PowerShellRemoting
        {
            get
            {
                if (!OverrideConnectionPolicy && ConnectionHost.DisableConnectionPowerShellRemoting)
                    return ManagementConnectionProtocolState.Disabled;
                else
                    return _PowerShellRemoting;
            }
            set { _PowerShellRemoting = value; }
        }
        private ManagementConnectionProtocolState _PowerShellRemoting = ManagementConnectionProtocolState.Unknown;

        /// <summary>
        /// When was the last connection attempt using CimRM?
        /// </summary>
        public DateTime LastPowerShellRemoting;

        /// <summary>
        /// Report the successful connection against the computer of this connection
        /// </summary>
        /// <param name="Type">What connection type succeeded?</param>
        public void ReportSuccess(ManagementConnectionType Type)
        {
            switch (Type)
            {
                case ManagementConnectionType.CimRM:
                    CimRM = ManagementConnectionProtocolState.Success;
                    LastCimRM = DateTime.Now;
                    break;

                case ManagementConnectionType.CimDCOM:
                    CimDCOM = ManagementConnectionProtocolState.Success;
                    LastCimDCOM = DateTime.Now;
                    break;

                case ManagementConnectionType.Wmi:
                    Wmi = ManagementConnectionProtocolState.Success;
                    LastWmi = DateTime.Now;
                    break;

                case ManagementConnectionType.PowerShellRemoting:
                    PowerShellRemoting = ManagementConnectionProtocolState.Success;
                    LastPowerShellRemoting = DateTime.Now;
                    break;
            }
        }

        /// <summary>
        /// Report the failure of connecting to the target computer
        /// </summary>
        /// <param name="Type">What connection type failed?</param>
        public void ReportFailure(ManagementConnectionType Type)
        {
            switch (Type)
            {
                case ManagementConnectionType.CimRM:
                    CimRM = ManagementConnectionProtocolState.Error;
                    LastCimRM = DateTime.Now;
                    break;

                case ManagementConnectionType.CimDCOM:
                    CimDCOM = ManagementConnectionProtocolState.Error;
                    LastCimDCOM = DateTime.Now;
                    break;

                case ManagementConnectionType.Wmi:
                    Wmi = ManagementConnectionProtocolState.Error;
                    LastWmi = DateTime.Now;
                    break;

                case ManagementConnectionType.PowerShellRemoting:
                    PowerShellRemoting = ManagementConnectionProtocolState.Error;
                    LastPowerShellRemoting = DateTime.Now;
                    break;
            }
        }

        #endregion Connection Stats

        #region Credential Management

        /// <summary>
        /// Any registered credentials to use on the connection.
        /// </summary>
        public PSCredential Credentials;

        /// <summary>
        /// Whether the default windows credentials are known to not work against the target.
        /// </summary>
        public bool WindowsCredentialsAreBad;

        /// <summary>
        /// Whether windows credentials are known to be good. Do not build conditions on them being false, just on true.
        /// </summary>
        public bool UseWindowsCredentials;

        /// <summary>
        /// Credentials known to not work. They will not be used when specified.
        /// </summary>
        public List<PSCredential> KnownBadCredentials = new List<PSCredential>();

        /// <summary>
        /// Adds a credentials object to the list of credentials known to not work.
        /// </summary>
        /// <param name="Credential">The bad credential that must be punished</param>
        public void AddBadCredential(PSCredential Credential)
        {
            if (DisableBadCredentialCache)
                return;

            if (Credential == null)
            {
                WindowsCredentialsAreBad = true;
                UseWindowsCredentials = false;
                return;
            }

            // If previously good credentials have been revoked, better remove them from the list
            if ((Credentials != null) && (Credentials.UserName.ToLower() == Credential.UserName.ToLower()))
            {
                if (Credentials.GetNetworkCredential().Password == Credential.GetNetworkCredential().Password)
                    Credentials = null;
            }

            foreach (PSCredential cred in KnownBadCredentials)
            {
                if (cred.UserName.ToLower() == Credential.UserName.ToLower())
                {
                    if (cred.GetNetworkCredential().Password == Credential.GetNetworkCredential().Password)
                        return;
                }
            }
            KnownBadCredentials.Add(Credential);
        }

        /// <summary>
        /// Reports a credentials object as being legit.
        /// </summary>
        /// <param name="Credential">The functioning credential that we may want to use again</param>
        public void AddGoodCredential(PSCredential Credential)
        {
            if (!DisableCredentialAutoRegister)
            {
                Credentials = Credential;
                if (Credential == null)
                {
                    UseWindowsCredentials = true;
                }
            }
        }

        /// <summary>
        /// Calculates, which credentials to use. Will consider input, compare it with know not-working credentials or use the configured working credentials for that.
        /// </summary>
        /// <param name="Credential">Any credential object a user may have explicitly specified.</param>
        /// <returns>The Credentials to use</returns>
        public PSCredential GetCredential(PSCredential Credential)
        {
            // If nothing was bound, return whatever is available
            // If something was bound, however explicit override is in effect AND either we have a good credential OR know Windows Credentials are good to use, use the cached credential
            // Without the additional logic conditions, OverrideExplicitCredential would override all input, even if we haven't found a working credential yet.
            if (OverrideExplicitCredential && (UseWindowsCredentials || (Credentials != null)))
            {
                return Credentials;
            }

            // Handle Windows authentication
            if (Credential == null)
            {
                if (WindowsCredentialsAreBad)
                {
                    if (EnableCredentialFailover && (Credentials != null))
                        return Credentials;
                    throw new PSArgumentException("Windows authentication was used, but is known to not work!",
                        "Credential");
                }
                return null;
            }

            // Compare with bad credential cache
            if (!DisableBadCredentialCache)
            {
                foreach (PSCredential cred in KnownBadCredentials)
                {
                    if (cred.UserName.ToLower() == Credential.UserName.ToLower())
                    {
                        if (cred.GetNetworkCredential().Password == Credential.GetNetworkCredential().Password)
                        {
                            if (EnableCredentialFailover)
                            {
                                if ((Credentials != null) || !WindowsCredentialsAreBad)
                                    return Credentials;
                                throw new PSArgumentException(
                                    "Specified credentials are known to not work! Credential failover is enabled but there are no known working credentials.",
                                    "Credential");
                            }
                            throw new PSArgumentException("Specified credentials are known to not work!",
                                "Credential");
                        }
                    }
                }
            }

            // Return unknown credential, so it may be tried out
            return Credential;
        }

        /// <summary>
        /// Tests whether the input credential is on the list known, bad credentials
        /// </summary>
        /// <param name="Credential">The credential to test</param>
        /// <returns>True if the credential is known to not work, False if it is not yet known to not work</returns>
        public bool IsBadCredential(PSCredential Credential)
        {
            if (Credential == null)
            {
                return WindowsCredentialsAreBad;
            }

            foreach (PSCredential cred in KnownBadCredentials)
            {
                if (cred.UserName.ToLower() == Credential.UserName.ToLower())
                {
                    if (cred.GetNetworkCredential().Password == Credential.GetNetworkCredential().Password)
                        return true;
                }
            }

            return false;
        }

        /// <summary>
        /// Removes an item from the list of known bad credentials
        /// </summary>
        /// <param name="Credential">The credential to remove</param>
        public void RemoveBadCredential(PSCredential Credential)
        {
            if (Credential == null)
            {
                return;
            }

            foreach (PSCredential cred in KnownBadCredentials)
            {
                if (cred.UserName.ToLower() == Credential.UserName.ToLower())
                {
                    if (cred.GetNetworkCredential().Password == Credential.GetNetworkCredential().Password)
                    {
                        KnownBadCredentials.Remove(cred);
                    }
                }
            }
        }

        #endregion Credential Management

        #region Connection Types

        /// <summary>
        /// Returns the next connection type to try.
        /// </summary>
        /// <param name="ExcludedTypes">Exclude any type already tried and failed</param>
        /// <param name="Force">Overrides the timeout on bad connections</param>
        /// <returns>The next type to try.</returns>
        public ManagementConnectionType GetConnectionType(ManagementConnectionType ExcludedTypes, bool Force)
        {
            ManagementConnectionType temp = ExcludedTypes | DisabledConnectionTypes;

            #region Use working connections first

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

            #endregion Use working connections first

            #region Then prefer unknown connections

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

            #endregion Then prefer unknown connections

            #region Finally try what would not work previously

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

            #endregion Finally try what would not work previously

            // Do not try to use disabled protocols

            throw new PSInvalidOperationException("No connectiontypes left to try.");
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

        #endregion Connection Types

        #region Internals

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

        #endregion Internals

        #region Constructors

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

        #endregion Constructors

        #region CIM Execution

        #region WinRM

        /// <summary>
        /// The options ot use when establishing a CIM Session
        /// </summary>
        public WSManSessionOptions CimWinRMOptions
        {
            get
            {
                if (_CimWinRMOptions == null)
                {
                    return null;
                }
                return new WSManSessionOptions(_CimWinRMOptions);
            }
            set
            {
                cimWinRMSession = null;
                _CimWinRMOptions = value;
            }
        }

        private WSManSessionOptions _CimWinRMOptions;

        private CimSession cimWinRMSession;
        private PSCredential cimWinRMSessionLastCredential;

        private CimSession GetCimWinRMSession(PSCredential Credential)
        {
            // Prepare the last session if any
            CimSession tempSession = cimWinRMSession;

            // If we use different credentials than last time, now's the time to interrupt
            if (!(cimWinRMSessionLastCredential == null && Credential == null))
            {
                if (cimWinRMSessionLastCredential == null || Credential == null)
                    tempSession = null;
                else if (cimWinRMSessionLastCredential.UserName != Credential.UserName)
                    tempSession = null;
                else if (cimWinRMSessionLastCredential.GetNetworkCredential().Password !=
                         Credential.GetNetworkCredential().Password)
                    tempSession = null;
            }

            if (tempSession == null)
            {
                WSManSessionOptions options;
                if (CimWinRMOptions == null)
                {
                    options = GetDefaultCimWsmanOptions();
                }
                else
                {
                    options = CimWinRMOptions;
                }
                if (Credential != null)
                {
                    options.AddDestinationCredentials(new CimCredential(PasswordAuthenticationMechanism.Default,
                        Credential.GetNetworkCredential().Domain, Credential.GetNetworkCredential().UserName,
                        Credential.Password));
                }

                try
                {
                    tempSession = CimSession.Create(ComputerName, options);
                }
                catch (Exception e)
                {
                    bool testBadCredential = false;
                    try
                    {
                        string tempMessageId = ((CimException) (e.InnerException)).MessageId;
                        if (tempMessageId == "HRESULT 0x8007052e")
                            testBadCredential = true;
                        else if (tempMessageId == "HRESULT 0x80070005")
                            testBadCredential = true;
                    }
                    catch
                    {
                    }

                    if (testBadCredential)
                    {
                        throw new UnauthorizedAccessException("Invalid credentials!", e);
                    }
                    throw;
                }

                cimWinRMSessionLastCredential = Credential;
            }

            return tempSession;
        }

        /// <summary>
        /// Returns the default wsman options object
        /// </summary>
        /// <returns>Something very default-y</returns>
        private WSManSessionOptions GetDefaultCimWsmanOptions()
        {
            WSManSessionOptions options = new WSManSessionOptions();
            options.DestinationPort = 0;
            options.MaxEnvelopeSize = 0;
            options.CertCACheck = true;
            options.CertCNCheck = true;
            options.CertRevocationCheck = true;
            options.UseSsl = false;
            options.PacketEncoding = PacketEncoding.Utf8;
            options.NoEncryption = false;
            options.EncodePortInServicePrincipalName = false;

            return options;
        }

        /// <summary>
        /// Get all cim instances of the appropriate class using WinRM
        /// </summary>
        /// <param name="Credential">The credentiuls to use for the connection.</param>
        /// <param name="Class">The class to query.</param>
        /// <param name="Namespace">The namespace to look in (defaults to root\cimv2).</param>
        /// <returns>Hopefully a mountainload of CimInstances</returns>
        public object GetCimRMInstance(PSCredential Credential, string Class, string Namespace = @"root\cimv2")
        {
            CimSession tempSession;
            IEnumerable<CimInstance> result;

            tempSession = GetCimWinRMSession(Credential);
            result = tempSession.EnumerateInstances(Namespace, Class);
            
            if (DisableCimPersistence)
            {
                try
                {
                    tempSession.Close();
                }
                catch
                {
                }
                cimWinRMSession = null;
            }
            else
            {
                cimWinRMSession = tempSession;
            }
            return result;
        }

        /// <summary>
        /// Get all cim instances matching the query using WinRM
        /// </summary>
        /// <param name="Credential">The credentiuls to use for the connection.</param>
        /// <param name="Query">The query to use requesting information.</param>
        /// <param name="Dialect">Defaults to WQL.</param>
        /// <param name="Namespace">The namespace to look in (defaults to root\cimv2).</param>
        /// <returns></returns>
        public object QueryCimRMInstance(PSCredential Credential, string Query, string Dialect = "WQL",
            string Namespace = @"root\cimv2")
        {
            CimSession tempSession;
            IEnumerable<CimInstance> result = new List<CimInstance>();

            try
            {
                tempSession = GetCimWinRMSession(Credential);
                result = tempSession.QueryInstances(Namespace, Dialect, Query);
                result.GetEnumerator().MoveNext();
            }
            catch (Exception e)
            {
                bool testBadCredential = false;
                try
                {
                    string tempMessageId = ((CimException) e).MessageId;
                    if (tempMessageId == "HRESULT 0x8007052e")
                        testBadCredential = true;
                    else if (tempMessageId == "HRESULT 0x80070005")
                        testBadCredential = true;
                }
                catch
                {
                }

                if (testBadCredential)
                {
                    throw new UnauthorizedAccessException("Invalid credentials!", e);
                }
                throw;
            }

            if (DisableCimPersistence)
            {
                try
                {
                    tempSession.Close();
                }
                catch
                {
                }
                cimWinRMSession = null;
            }
            else
            {
                if (cimWinRMSession != tempSession)
                    cimWinRMSession = tempSession;
            }
            return result;
        }

        #endregion WinRM

        #region DCOM

        /// <summary>
        /// The options ot use when establishing a CIM Session
        /// </summary>
        public DComSessionOptions CimDComOptions
        {
            get
            {
                if (_CimDComOptions == null)
                {
                    return null;
                }
                DComSessionOptions options = new DComSessionOptions();
                options.PacketPrivacy = _CimDComOptions.PacketPrivacy;
                options.PacketIntegrity = _CimDComOptions.PacketIntegrity;
                options.Impersonation = _CimDComOptions.Impersonation;
                return options;
            }
            set
            {
                _CimDComOptions = null;
                _CimDComOptions = value;
            }
        }

        private DComSessionOptions _CimDComOptions;

        private CimSession cimDComSession;
        private PSCredential cimDComSessionLastCredential;

        private CimSession GetCimDComSession(PSCredential Credential)
        {
            // Prepare the last session if any
            CimSession tempSession = cimDComSession;

            // If we use different credentials than last time, now's the time to interrupt
            if (!(cimDComSessionLastCredential == null && Credential == null))
            {
                if (cimDComSessionLastCredential == null || Credential == null)
                    tempSession = null;
                else if (cimDComSessionLastCredential.UserName != Credential.UserName)
                    tempSession = null;
                else if (cimDComSessionLastCredential.GetNetworkCredential().Password !=
                         Credential.GetNetworkCredential().Password)
                    tempSession = null;
            }

            if (tempSession == null)
            {
                DComSessionOptions options = null;
                if (CimWinRMOptions == null)
                {
                    options = GetDefaultCimDcomOptions();
                }
                else
                {
                    options = CimDComOptions;
                }
                if (Credential != null)
                {
                    options.AddDestinationCredentials(new CimCredential(PasswordAuthenticationMechanism.Default,
                        Credential.GetNetworkCredential().Domain, Credential.GetNetworkCredential().UserName,
                        Credential.Password));
                }

                try
                {
                    tempSession = CimSession.Create(ComputerName, options);
                }
                catch (Exception e)
                {
                    bool testBadCredential = false;
                    try
                    {
                        string tempMessageId = ((CimException) (e.InnerException)).MessageId;
                        if (tempMessageId == "HRESULT 0x8007052e")
                            testBadCredential = true;
                        else if (tempMessageId == "HRESULT 0x80070005")
                            testBadCredential = true;
                    }
                    catch
                    {
                    }

                    if (testBadCredential)
                    {
                        throw new UnauthorizedAccessException("Invalid credentials!", e);
                    }
                    throw;
                }

                cimDComSessionLastCredential = Credential;
            }

            return tempSession;
        }

        /// <summary>
        /// Returns the default DCom options object
        /// </summary>
        /// <returns>Something very default-y</returns>
        private DComSessionOptions GetDefaultCimDcomOptions()
        {
            DComSessionOptions options = new DComSessionOptions();
            options.PacketPrivacy = true;
            options.PacketIntegrity = true;
            options.Impersonation = ImpersonationType.Impersonate;

            return options;
        }

        /// <summary>
        /// Get all cim instances of the appropriate class using DCOM
        /// </summary>
        /// <param name="Credential">The credentiuls to use for the connection.</param>
        /// <param name="Class">The class to query</param>
        /// <param name="Namespace">The namespace to look in (defaults to root\cimv2)</param>
        /// <returns>Hopefully a mountainload of CimInstances</returns>
        public object GetCimDComInstance(PSCredential Credential, string Class, string Namespace = @"root\cimv2")
        {
            CimSession tempSession;
            IEnumerable<CimInstance> result = new List<CimInstance>();

            tempSession = GetCimDComSession(Credential);
            result = tempSession.EnumerateInstances(Namespace, Class);

            if (DisableCimPersistence)
            {
                try
                {
                    tempSession.Close();
                }
                catch
                {
                }
                cimDComSession = null;
            }
            else
            {
                if (cimDComSession != tempSession)
                    cimDComSession = tempSession;
            }
            return result;
        }

        /// <summary>
        /// Get all cim instances matching the query using DCOM
        /// </summary>
        /// <param name="Credential">The credentiuls to use for the connection.</param>
        /// <param name="Query">The query to use requesting information.</param>
        /// <param name="Dialect">Defaults to WQL.</param>
        /// <param name="Namespace">The namespace to look in (defaults to root\cimv2).</param>
        /// <returns></returns>
        public object QueryCimDCOMInstance(PSCredential Credential, string Query, string Dialect = "WQL",
            string Namespace = @"root\cimv2")
        {
            CimSession tempSession;
            IEnumerable<CimInstance> result = new List<CimInstance>();

            tempSession = GetCimDComSession(Credential);
            result = tempSession.QueryInstances(Namespace, Dialect, Query);
            result.GetEnumerator().MoveNext();

            if (DisableCimPersistence)
            {
                try
                {
                    tempSession.Close();
                }
                catch
                {
                }
                cimDComSession = null;
            }
            else
            {
                if (cimDComSession != tempSession)
                    cimDComSession = tempSession;
            }
            return result;
        }

        #endregion DCOM

        #endregion CIM Execution

        /// <summary>
        /// Simple string representation
        /// </summary>
        /// <returns>Returns the computerName it is connection for</returns>
        public override string ToString()
        {
            return ComputerName;
        }
    }
}