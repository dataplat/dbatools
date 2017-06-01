
#region Test whether the module had already been imported
if (([System.Management.Automation.PSTypeName]'SqlCollective.Dbatools.Configuration.Config').Type)
{
    # No need to load the library again, if the module was once already imported.
    $ImportLibrary = $false
}
else
{
    $ImportLibrary = $true
}
#endregion Test whether the module had already been imported

if ($ImportLibrary)
{
    #region Source Code
    $source = @'
using System;

namespace Sqlcollective.Dbatools
{
    namespace Configuration
    {
        using System.Collections;

        /// <summary>
        /// Configuration Manager as well as individual configuration object.
        /// </summary>
        [Serializable]
        public class Config
        {
            /// <summary>
            /// The central configuration store 
            /// </summary>
            public static Hashtable Cfg = new Hashtable();

            /// <summary>
            /// The hashtable containing the configuration handler scriptblocks.
            /// When registering a value to a configuration element, that value is stored in a hashtable.
            /// However these lookups can be expensive when done repeatedly.
            /// For greater performance, the most frequently stored values are stored in static fields instead.
            /// In order to facilitate this, an event can be reigstered - which is stored in this hashtable - that will accept the input value and copy it to the target field.
            /// </summary>
            public static Hashtable ConfigHandler = new Hashtable();

            /// <summary>
            /// The Name of the setting
            /// </summary>
            public string Name;

            /// <summary>
            /// The module of the setting. Helps being able to group configurations.
            /// </summary>
            public string Module;

            /// <summary>
            /// A description of the specific setting
            /// </summary>
            public string Description;

            /// <summary>
            /// The data type of the value stored in the configuration element.
            /// </summary>
            public string Type
            {
                get
                {
                    try { return Value.GetType().FullName; }
                    catch { return null; }
                }
                set { }
            }

            /// <summary>
            /// The value stored in the configuration element
            /// </summary>
            public Object Value;

            /// <summary>
            /// Setting this to true will cause the element to not be discovered unless using the '-Force' parameter on "Get-DbaConfig"
            /// </summary>
            public bool Hidden = false;
        }
    }

    namespace Connection
    {
        using System.Collections.Generic;
        using System.Management.Automation;
        using Microsoft.Management.Infrastructure;
        using Microsoft.Management.Infrastructure.Options;

        /// <summary>
        /// Provides static tools for managing connections
        /// </summary>
        public static class ConnectionHost
        {
            /// <summary>
            /// List of all registered connections.
            /// </summary>
            public static Dictionary<string, ManagementConnection> Connections = new Dictionary<string, ManagementConnection>();

            #region Configuration
            /// <summary>
            /// The time interval that must pass, before a connection using a known to not work connection protocol is reattempted
            /// </summary>
            public static TimeSpan BadConnectionTimeout = new TimeSpan(0, 15, 0);

            /// <summary>
            /// Globally disables all caching done by the Computer Management functions.
            /// </summary>
            public static bool DisableCache = false;

            /// <summary>
            /// Disables the caching of bad credentials. dbatools caches bad logon credentials for wmi/cim and will not reuse them.
            /// </summary>
            public static bool DisableBadCredentialCache = false;

            /// <summary>
            /// Disables the automatic registration of working credentials. dbatools will caches the last working credential when connecting using wmi/cim and will use those rather than using known bad credentials
            /// </summary>
            public static bool DisableCredentialAutoRegister = false;

            /// <summary>
            /// Enabling this will force the use of the last credentials known to work, rather than even trying explicit credentials.
            /// </summary>
            public static bool OverrideExplicitCredential = false;

            /// <summary>
            /// Enables automatic failover to working credentials, when passed credentials either are known, or turn out to not work.
            /// </summary>
            public static bool EnableCredentialFailover = false;

            /// <summary>
            /// Globally disables the persistence of Cim sessions used to connect to a target system.
            /// </summary>
            public static bool DisableCimPersistence = false;
            #endregion Configuration
        }

        /// <summary>
        /// Contains management connection information for a windows server
        /// </summary>
        [Serializable]
        public class ManagementConnection
        {
            /// <summary>
            /// The computer to connect to
            /// </summary>
            public string ComputerName;

            #region Configuration
            /// <summary>
            /// Locally disables the caching of bad credentials
            /// </summary>
            public bool DisableBadCredentialCache
            {
                get
                {
                    switch (_DisableBadCredentialCache)
                    {
                        case -1:
                            return false;
                        case 1:
                            return true;
                        default:
                            return ConnectionHost.DisableBadCredentialCache;
                    }
                }
                set
                {
                    if (value) { _DisableBadCredentialCache = 1; }
                    else { _DisableBadCredentialCache = -1; }
                }
            }
            private int _DisableBadCredentialCache = 0;

            /// <summary>
            /// Locally disables the caching of working credentials
            /// </summary>
            public bool DisableCredentialAutoRegister
            {
                get
                {
                    switch (_DisableCredentialAutoRegister)
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
                    if (value) { _DisableCredentialAutoRegister = 1; }
                    else { _DisableCredentialAutoRegister = -1; }
                }
            }
            private int _DisableCredentialAutoRegister = 0;

            /// <summary>
            /// Locally overrides explicit credentials with working ones that were cached
            /// </summary>
            public bool OverrideExplicitCredential
            {
                get
                {
                    switch (_OverrideExplicitCredential)
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
                    if (value) { _OverrideExplicitCredential = 1; }
                    else { _OverrideExplicitCredential = -1; }
                }
            }
            private int _OverrideExplicitCredential = 0;

            /// <summary>
            /// Locally enables automatic failover to working credentials, when passed credentials either are known, or turn out to not work.
            /// </summary>
            public bool EnableCredentialFailover
            {
                get
                {
                    switch (_EnableCredentialFailover)
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
                    if (value) { _EnableCredentialFailover = 1; }
                    else { _EnableCredentialFailover = -1; }
                }
            }
            private int _EnableCredentialFailover = 0;

            /// <summary>
            /// Locally disables the persistence of Cim sessions used to connect to a target system.
            /// </summary>
            public bool DisableCimPersistence
            {
                get
                {
                    switch (_DisableCimPersistence)
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
                    if (value) { _DisableCimPersistence = 1; }
                    else { _DisableCimPersistence = -1; }
                }
            }
            private int _DisableCimPersistence = 0;

            /// <summary>
            /// Connectiontypes that will never be used
            /// </summary>
            public ManagementConnectionType DisabledConnectionTypes
            {
                get
                {
                    ManagementConnectionType temp = ManagementConnectionType.None;
                    if (CimRM == ManagementConnectionProtocolState.Disabled) { temp = temp | ManagementConnectionType.CimRM; }
                    if (CimDCOM == ManagementConnectionProtocolState.Disabled) { temp = temp | ManagementConnectionType.CimDCOM; }
                    if (Wmi == ManagementConnectionProtocolState.Disabled) { temp = temp | ManagementConnectionType.Wmi; }
                    if (PowerShellRemoting == ManagementConnectionProtocolState.Disabled) { temp = temp | ManagementConnectionType.PowerShellRemoting; }
                    return temp;
                }
                set
                {
                    if ((value & ManagementConnectionType.CimRM) != 0) { CimRM = ManagementConnectionProtocolState.Disabled; }
                    else if ((CimRM & ManagementConnectionProtocolState.Disabled) != 0) { CimRM = ManagementConnectionProtocolState.Unknown; }
                    if ((value & ManagementConnectionType.CimDCOM) != 0) { CimDCOM = ManagementConnectionProtocolState.Disabled; }
                    else if ((CimDCOM & ManagementConnectionProtocolState.Disabled) != 0) { CimDCOM = ManagementConnectionProtocolState.Unknown; }
                    if ((value & ManagementConnectionType.Wmi) != 0) { Wmi = ManagementConnectionProtocolState.Disabled; }
                    else if ((Wmi & ManagementConnectionProtocolState.Disabled) != 0) { Wmi = ManagementConnectionProtocolState.Unknown; }
                    if ((value & ManagementConnectionType.PowerShellRemoting) != 0) { PowerShellRemoting = ManagementConnectionProtocolState.Disabled; }
                    else if ((PowerShellRemoting & ManagementConnectionProtocolState.Disabled) != 0) { PowerShellRemoting = ManagementConnectionProtocolState.Unknown; }
                }
            }

            /// <summary>
            /// Restores all deviations from public policy back to default
            /// </summary>
            public void RestoreDefaultConfiguration()
            {
                _DisableBadCredentialCache = 0;
                _DisableCredentialAutoRegister = 0;
                _OverrideExplicitCredential = 0;
                _DisableCimPersistence = 0;
                _EnableCredentialFailover = 0;
            }
            #endregion Configuration

            #region Connection Stats
            /// <summary>
            /// Did the last connection attempt using CimRM work?
            /// </summary>
            public ManagementConnectionProtocolState CimRM = ManagementConnectionProtocolState.Unknown;

            /// <summary>
            /// When was the last connection attempt using CimRM?
            /// </summary>
            public DateTime LastCimRM;

            /// <summary>
            /// Did the last connection attempt using CimDCOM work?
            /// </summary>
            public ManagementConnectionProtocolState CimDCOM = ManagementConnectionProtocolState.Unknown;

            /// <summary>
            /// When was the last connection attempt using CimRM?
            /// </summary>
            public DateTime LastCimDCOM;

            /// <summary>
            /// Did the last connection attempt using Wmi work?
            /// </summary>
            public ManagementConnectionProtocolState Wmi = ManagementConnectionProtocolState.Unknown;

            /// <summary>
            /// When was the last connection attempt using CimRM?
            /// </summary>
            public DateTime LastWmi;

            /// <summary>
            /// Did the last connection attempt using PowerShellRemoting work?
            /// </summary>
            public ManagementConnectionProtocolState PowerShellRemoting = ManagementConnectionProtocolState.Unknown;

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

                    default:
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

                    default:
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
                    if (Credential == null) { UseWindowsCredentials = true; }
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
                if (OverrideExplicitCredential && (UseWindowsCredentials || (Credentials != null))) { return Credentials; }

                // Handle Windows authentication
                if (Credential == null)
                {
                    if (WindowsCredentialsAreBad)
                    {
                        if (EnableCredentialFailover && (Credentials != null))
                            return Credentials;
                        else
                            throw new PSArgumentException("Windows authentication was used, but is known to not work!", "Credential");
                    }
                    else
                    {
                        return null;
                    }
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
                                    else
                                        throw new PSArgumentException("Specified credentials are known to not work! Credential failover is enabled but there are no known working credentials.", "Credential");
                                }
                                else
                                {
                                    throw new PSArgumentException("Specified credentials are known to not work!", "Credential");
                                }
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
                if (Credential == null) { return WindowsCredentialsAreBad; }

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
                if (Credential == null) { return; }

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

                return;
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
                if (((ManagementConnectionType.CimRM & temp) == 0) && ((CimRM & ManagementConnectionProtocolState.Success) != 0))
                    return ManagementConnectionType.CimRM;

                if (((ManagementConnectionType.CimDCOM & temp) == 0) && ((CimDCOM & ManagementConnectionProtocolState.Success) != 0))
                    return ManagementConnectionType.CimDCOM;

                if (((ManagementConnectionType.Wmi & temp) == 0) && ((Wmi & ManagementConnectionProtocolState.Success) != 0))
                    return ManagementConnectionType.Wmi;

                if (((ManagementConnectionType.PowerShellRemoting & temp) == 0) && ((PowerShellRemoting & ManagementConnectionProtocolState.Success) != 0))
                    return ManagementConnectionType.PowerShellRemoting;
                #endregion Use working connections first

                #region Then prefer unknown connections
                if (((ManagementConnectionType.CimRM & temp) == 0) && ((CimRM & ManagementConnectionProtocolState.Unknown) != 0))
                    return ManagementConnectionType.CimRM;

                if (((ManagementConnectionType.CimDCOM & temp) == 0) && ((CimDCOM & ManagementConnectionProtocolState.Unknown) != 0))
                    return ManagementConnectionType.CimDCOM;

                if (((ManagementConnectionType.Wmi & temp) == 0) && ((Wmi & ManagementConnectionProtocolState.Unknown) != 0))
                    return ManagementConnectionType.Wmi;

                if (((ManagementConnectionType.PowerShellRemoting & temp) == 0) && ((PowerShellRemoting & ManagementConnectionProtocolState.Unknown) != 0))
                    return ManagementConnectionType.PowerShellRemoting;
                #endregion Then prefer unknown connections

                #region Finally try what would not work previously
                if (((ManagementConnectionType.CimRM & temp) == 0) && ((CimRM & ManagementConnectionProtocolState.Error) != 0) && ((LastCimRM + ConnectionHost.BadConnectionTimeout < DateTime.Now) | Force))
                    return ManagementConnectionType.CimRM;

                if (((ManagementConnectionType.CimDCOM & temp) == 0) && ((CimDCOM & ManagementConnectionProtocolState.Error) != 0) && ((LastCimDCOM + ConnectionHost.BadConnectionTimeout < DateTime.Now) | Force))
                    return ManagementConnectionType.CimDCOM;

                if (((ManagementConnectionType.Wmi & temp) == 0) && ((Wmi & ManagementConnectionProtocolState.Error) != 0) && ((LastWmi + ConnectionHost.BadConnectionTimeout < DateTime.Now) | Force))
                    return ManagementConnectionType.Wmi;

                if (((ManagementConnectionType.PowerShellRemoting & temp) == 0) && ((PowerShellRemoting & ManagementConnectionProtocolState.Error) != 0) && ((LastPowerShellRemoting + ConnectionHost.BadConnectionTimeout < DateTime.Now) | Force))
                    return ManagementConnectionType.PowerShellRemoting;
                #endregion Finally try what would not work previously

                // Do not try to use disabled protocols

                throw new PSInvalidOperationException("No connectiontypes left to try!");
            }

            /// <summary>
            /// Returns a list of all available connection types whose inherent timeout has expired.
            /// </summary>
            /// <param name="Timestamp">All last connection failures older than this point in time are considered to be expired</param>
            /// <returns>A list of all valid connection types</returns>
            public List<ManagementConnectionType> GetConnectionTypesTimed(DateTime Timestamp)
            {
                List<ManagementConnectionType> types = new List<ManagementConnectionType>();

                if (((DisabledConnectionTypes & ManagementConnectionType.CimRM) == 0) && ((CimRM == ManagementConnectionProtocolState.Success) || (LastCimRM < Timestamp)))
                    types.Add(ManagementConnectionType.CimRM);

                if (((DisabledConnectionTypes & ManagementConnectionType.CimDCOM) == 0) && ((CimDCOM == ManagementConnectionProtocolState.Success) || (LastCimDCOM < Timestamp)))
                    types.Add(ManagementConnectionType.CimDCOM);

                if (((DisabledConnectionTypes & ManagementConnectionType.Wmi) == 0) && ((Wmi == ManagementConnectionProtocolState.Success) || (LastWmi < Timestamp)))
                    types.Add(ManagementConnectionType.Wmi);

                if (((DisabledConnectionTypes & ManagementConnectionType.PowerShellRemoting) == 0) && ((PowerShellRemoting == ManagementConnectionProtocolState.Success) || (LastPowerShellRemoting < Timestamp)))
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
                    if (_CimWinRMOptions == null) { return null; }
                    return new WSManSessionOptions(_CimWinRMOptions); ;
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
                    else if (cimWinRMSessionLastCredential.GetNetworkCredential().Password != Credential.GetNetworkCredential().Password)
                        tempSession = null;
                }

                if (tempSession == null)
                {
                    WSManSessionOptions options = null;
                    if (CimWinRMOptions == null)
                    {
                        options = GetDefaultCimWsmanOptions();
                    }
                    else { options = CimWinRMOptions; }
                    if (Credential != null) { options.AddDestinationCredentials(new CimCredential(PasswordAuthenticationMechanism.Default, Credential.GetNetworkCredential().Domain, Credential.GetNetworkCredential().UserName, Credential.Password)); }

                    try { tempSession = CimSession.Create(ComputerName, options); }
                    catch (Exception e)
                    {
                        bool testBadCredential = false;
                        try
                        {
                            string tempMessageId = ((CimException)(e.InnerException)).MessageId;
                            if (tempMessageId == "HRESULT 0x8007052e")
                                testBadCredential = true;
                            else if (tempMessageId == "HRESULT 0x80070005")
                                testBadCredential = true;
                        }
                        catch { }

                        if (testBadCredential) { throw new UnauthorizedAccessException("Invalid credentials!", e); }
                        else { throw e; }
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
                IEnumerable<CimInstance> result = new List<CimInstance>();

                try
                {
                    tempSession = GetCimWinRMSession(Credential);
                    result = tempSession.EnumerateInstances(Namespace, Class);
                    result.GetEnumerator().MoveNext();
                }
                catch (Exception e)
                {
                    bool testBadCredential = false;
                    try
                    {
                        string tempMessageId = ((CimException)e).MessageId;
                        if (tempMessageId == "HRESULT 0x8007052e")
                            testBadCredential = true;
                        else if (tempMessageId == "HRESULT 0x80070005")
                            testBadCredential = true;
                    }
                    catch { }

                    if (testBadCredential) { throw new UnauthorizedAccessException("Invalid credentials!", e); }
                    else { throw e; }
                }

                if (DisableCimPersistence)
                {
                    try { tempSession.Close(); }
                    catch { }
                    cimWinRMSession = null;
                }
                else
                {
                    if (cimWinRMSession != tempSession)
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
            public object QueryCimRMInstance(PSCredential Credential, string Query, string Dialect = "WQL", string Namespace = @"root\cimv2")
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
                        string tempMessageId = ((CimException)e).MessageId;
                        if (tempMessageId == "HRESULT 0x8007052e")
                            testBadCredential = true;
                        else if (tempMessageId == "HRESULT 0x80070005")
                            testBadCredential = true;
                    }
                    catch { }

                    if (testBadCredential) { throw new UnauthorizedAccessException("Invalid credentials!", e); }
                    else { throw e; }
                }

                if (DisableCimPersistence)
                {
                    try { tempSession.Close(); }
                    catch { }
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
                    if (_CimDComOptions == null) { return null; }
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
                    else if (cimDComSessionLastCredential.GetNetworkCredential().Password != Credential.GetNetworkCredential().Password)
                        tempSession = null;
                }

                if (tempSession == null)
                {
                    DComSessionOptions options = null;
                    if (CimWinRMOptions == null)
                    {
                        options = GetDefaultCimDcomOptions();
                    }
                    else { options = CimDComOptions; }
                    if (Credential != null) { options.AddDestinationCredentials(new CimCredential(PasswordAuthenticationMechanism.Default, Credential.GetNetworkCredential().Domain, Credential.GetNetworkCredential().UserName, Credential.Password)); }

                    try { tempSession = CimSession.Create(ComputerName, options); }
                    catch (Exception e)
                    {
                        bool testBadCredential = false;
                        try
                        {
                            string tempMessageId = ((CimException)(e.InnerException)).MessageId;
                            if (tempMessageId == "HRESULT 0x8007052e")
                                testBadCredential = true;
                            else if (tempMessageId == "HRESULT 0x80070005")
                                testBadCredential = true;
                        }
                        catch { }

                        if (testBadCredential) { throw new UnauthorizedAccessException("Invalid credentials!", e); }
                        else { throw e; }
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

                try
                {
                    tempSession = GetCimDComSession(Credential);
                    result = tempSession.EnumerateInstances(Namespace, Class);
                    result.GetEnumerator().MoveNext();
                }
                catch (Exception e)
                {
                    bool testBadCredential = false;
                    try
                    {
                        string tempMessageId = ((CimException)e).MessageId;
                        if (tempMessageId == "HRESULT 0x8007052e")
                            testBadCredential = true;
                        else if (tempMessageId == "HRESULT 0x80070005")
                            testBadCredential = true;
                    }
                    catch { }

                    if (testBadCredential) { throw new UnauthorizedAccessException("Invalid credentials!", e); }
                    else { throw e; }
                }

                if (DisableCimPersistence)
                {
                    try { tempSession.Close(); }
                    catch { }
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
            public object QueryCimDCOMInstance(PSCredential Credential, string Query, string Dialect = "WQL", string Namespace = @"root\cimv2")
            {
                CimSession tempSession;
                IEnumerable<CimInstance> result = new List<CimInstance>();

                try
                {
                    tempSession = GetCimDComSession(Credential);
                    result = tempSession.QueryInstances(Namespace, Dialect, Query);
                    result.GetEnumerator().MoveNext();
                }
                catch (Exception e)
                {
                    bool testBadCredential = false;
                    try
                    {
                        string tempMessageId = ((CimException)e).MessageId;
                        if (tempMessageId == "HRESULT 0x8007052e")
                            testBadCredential = true;
                        else if (tempMessageId == "HRESULT 0x80070005")
                            testBadCredential = true;
                    }
                    catch { }

                    if (testBadCredential) { throw new UnauthorizedAccessException("Invalid credentials!", e); }
                    else { throw e; }
                }

                if (DisableCimPersistence)
                {
                    try { tempSession.Close(); }
                    catch { }
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

        /// <summary>
        /// The various types of state a connection-protocol may have
        /// </summary>
        public enum ManagementConnectionProtocolState
        {
            /// <summary>
            /// The default initial state, before any tests are performed
            /// </summary>
            Unknown = 1,

            /// <summary>
            /// A successful connection was last established
            /// </summary>
            Success = 2,

            /// <summary>
            /// Connecting using the relevant protocol failed last it was tried
            /// </summary>
            Error = 3,

            /// <summary>
            /// The relevant protocol has been disabled and should not be used
            /// </summary>
            Disabled = 4
        }

        /// <summary>
        /// The various ways to connect to a windows server fopr management purposes.
        /// </summary>
        [Flags]
        public enum ManagementConnectionType
        {
            /// <summary>
            /// No Connection-Type
            /// </summary>
            None = 0,

            /// <summary>
            /// Cim over a WinRM connection
            /// </summary>
            CimRM = 1,

            /// <summary>
            /// Cim over a DCOM connection
            /// </summary>
            CimDCOM = 2,

            /// <summary>
            /// WMI Connection
            /// </summary>
            Wmi = 4,

            /// <summary>
            /// Connecting with PowerShell remoting and performing WMI queries locally
            /// </summary>
            PowerShellRemoting = 8
        }

        /// <summary>
        /// The protocol to connect over via SMO
        /// </summary>
        public enum SqlConnectionProtocol
        {
            /// <summary>
            /// Connect using any protocol available
            /// </summary>
            Any = 1,

            /// <summary>
            /// Connect using TCP/IP
            /// </summary>
            TCP = 2,

            /// <summary>
            /// Connect using named pipes or shared memory
            /// </summary>
            NP = 3,
        }
    }

    namespace Database
    {
        using System.Numerics;
        using Utility;

        /// <summary>
        /// Object containing the information about the history of mankind ... or a database backup. WHo knows.
        /// </summary>
        public class BackupHistory
        {
            /// <summary>
            /// The name of the computer running MSSQL Server
            /// </summary>
            public string ComputerName;

            /// <summary>
            /// The Instance that was queried
            /// </summary>
            public string InstanceName;

            /// <summary>
            /// The full Instance name as seen from outside
            /// </summary>
            public string SqlInstance;

            /// <summary>
            /// The Database that was backed up
            /// </summary>
            public string Database;

            /// <summary>
            /// The user that is running the backup
            /// </summary>
            public string UserName;

            /// <summary>
            /// When was the backup started
            /// </summary>
            public DateTime Start;

            /// <summary>
            /// When did the backup end
            /// </summary>
            public DateTime End;

            /// <summary>
            /// What was the longest duration among the backups
            /// </summary>
            public DbaTimeSpan Duration;

            /// <summary>
            /// Where is the backup stored
            /// </summary>
            public string[] Path;

            /// <summary>
            /// What is the total size of the backup
            /// </summary>
            public Size TotalSize;

            /// <summary>
            /// The kind of backup this was
            /// </summary>
            public string Type;

            /// <summary>
            /// The ID for the Backup job
            /// </summary>
            public string BackupSetId;

            /// <summary>
            /// What kind of backup-device was the backup stored to
            /// </summary>
            public string DeviceType;

            /// <summary>
            /// What is the name of the backup software?
            /// </summary>
            public string Software;

            /// <summary>
            /// The full name of the backup
            /// </summary>
            public string[] FullName;

            /// <summary>
            /// The files that are part of this backup
            /// </summary>
            public object FileList;

            /// <summary>
            /// The position of the backup
            /// </summary>
            public int Position;

            /// <summary>
            /// The first Log Sequence Number
            /// </summary>
            public BigInteger FirstLsn;

            /// <summary>
            /// The Log Squence Number that marks the beginning of the backup
            /// </summary>
            public BigInteger DatabaseBackupLsn;

            /// <summary>
            /// The checkpoint's Log Sequence Number
            /// </summary>
            public BigInteger CheckpointLsn;

            /// <summary>
            /// The last Log Sequence Number
            /// </summary>
            public BigInteger LastLsn;

            /// <summary>
            /// The primary version number of the Sql Server
            /// </summary>
            public int SoftwareVersionMajor;
        }

        /// <summary>
        /// Class containing all dependency information over a database object
        /// </summary>
        [Serializable]
        public class Dependency
        {
            /// <summary>
            /// The name of the SQL server from whence the query came
            /// </summary>
            public string ComputerName;

            /// <summary>
            /// Name of the service running the database containing the dependency
            /// </summary>
            public string ServiceName;

            /// <summary>
            /// The Instance the database containing the dependency is running in.
            /// </summary>
            public string SqlInstance;

            /// <summary>
            /// The name of the dependent
            /// </summary>
            public string Dependent;

            /// <summary>
            /// The kind of object the dependent is
            /// </summary>
            public string Type;

            /// <summary>
            /// The owner of the dependent (usually the Database)
            /// </summary>
            public string Owner;

            /// <summary>
            /// Whether the dependency is Schemabound. If it is, then the creation statement order is of utmost importance.
            /// </summary>
            public bool IsSchemaBound;

            /// <summary>
            /// The immediate parent of the dependent. Useful in multi-tier dependencies.
            /// </summary>
            public string Parent;

            /// <summary>
            /// The type of object the immediate parent is.
            /// </summary>
            public string ParentType;

            /// <summary>
            /// The script used to create the object.
            /// </summary>
            public string Script;

            /// <summary>
            /// The tier in the dependency hierarchy tree. Used to determine, which dependency must be applied in which order.
            /// </summary>
            public int Tier;

            /// <summary>
            /// The smo object of the dependent.
            /// </summary>
            public object Object;

            /// <summary>
            /// The Uniform Resource Name of the dependent.
            /// </summary>
            public object Urn;

            /// <summary>
            /// The object of the original resource, from which the dependency hierachy has been calculated.
            /// </summary>
            public object OriginalResource;
        }
    }

    namespace dbaSystem
    {
        using System.Collections;
        using System.Collections.Concurrent;
        using System.Collections.Generic;
        using System.Management.Automation;
        using System.Threading;

        /// <summary>
        /// An error record written by dbatools
        /// </summary>
        [Serializable]
        public class DbaErrorRecord
        {
            /// <summary>
            /// The category of the error
            /// </summary>
            public ErrorCategoryInfo CategoryInfo;

            /// <summary>
            /// The details on the error
            /// </summary>
            public ErrorDetails ErrorDetails;

            /// <summary>
            /// The actual exception thrown
            /// </summary>
            public Exception Exception;

            /// <summary>
            /// The specific error identity, used to identify the target
            /// </summary>
            public string FullyQualifiedErrorId;

            /// <summary>
            /// The details of how this was called.
            /// </summary>
            public object InvocationInfo;

            /// <summary>
            /// The script's stacktrace
            /// </summary>
            public string ScriptStackTrace;

            /// <summary>
            /// The object being processed
            /// </summary>
            public object TargetObject;

            /// <summary>
            /// The name of the function throwing the error
            /// </summary>
            public string FunctionName;

            /// <summary>
            /// When was the error thrown
            /// </summary>
            public DateTime Timestamp;

            /// <summary>
            /// The message that was written in a userfriendly manner
            /// </summary>
            public string Message;

            /// <summary>
            /// The runspace the error occured on.
            /// </summary>
            public Guid Runspace;

            /// <summary>
            /// Create an empty record
            /// </summary>
            public DbaErrorRecord()
            {

            }

            /// <summary>
            /// Create a filled out error record
            /// </summary>
            /// <param name="Record">The original error record</param>
            /// <param name="FunctionName">The function that wrote the error</param>
            /// <param name="Timestamp">When was the error generated</param>
            /// <param name="Message">What message was passed when writing the error</param>
            public DbaErrorRecord(ErrorRecord Record, string FunctionName, DateTime Timestamp, string Message)
            {
                this.FunctionName = FunctionName;
                this.Timestamp = Timestamp;
                this.Message = Message;

                CategoryInfo = Record.CategoryInfo;
                ErrorDetails = Record.ErrorDetails;
                Exception = Record.Exception;
                FullyQualifiedErrorId = Record.FullyQualifiedErrorId;
                InvocationInfo = Record.InvocationInfo;
                ScriptStackTrace = Record.ScriptStackTrace;
                TargetObject = Record.TargetObject;
            }

            /// <summary>
            /// Create a filled out error record
            /// </summary>
            /// <param name="Record">The original error record</param>
            /// <param name="FunctionName">The function that wrote the error</param>
            /// <param name="Timestamp">When was the error generated</param>
            /// <param name="Message">What message was passed when writing the error</param>
            /// <param name="Runspace">The ID of the runspace writing the error. Used to separate output between different runspaces in the same process.</param>
            public DbaErrorRecord(ErrorRecord Record, string FunctionName, DateTime Timestamp, string Message, Guid Runspace)
            {
                this.FunctionName = FunctionName;
                this.Timestamp = Timestamp;
                this.Message = Message;
                this.Runspace = Runspace;

                CategoryInfo = Record.CategoryInfo;
                ErrorDetails = Record.ErrorDetails;
                Exception = Record.Exception;
                FullyQualifiedErrorId = Record.FullyQualifiedErrorId;
                InvocationInfo = Record.InvocationInfo;
                ScriptStackTrace = Record.ScriptStackTrace;
                TargetObject = Record.TargetObject;
            }
        }

        /// <summary>
        /// Wrapper class that can emulate any exception for purpose of serialization without blowing up the storage space consumed
        /// </summary>
        [Serializable]
        public class DbatoolsException
        {
            private Exception _Exception;
            /// <summary>
            /// Returns the original exception object that we interpreted. This is on purpose not a property, as we want to avoid messing with serialization size.
            /// </summary>
            /// <returns>The original exception that got thrown</returns>
            public Exception GetException()
            {
                return _Exception;
            }

            #region Properties & Fields
            #region Wrapper around 'official' properties
            /// <summary>
            /// The actual Exception Message
            /// </summary>
            public string Message;

            /// <summary>
            /// The original source of the Exception
            /// </summary>
            public string Source;

            /// <summary>
            /// Where on the callstack did the exception occur?
            /// </summary>
            public string StackTrace;

            /// <summary>
            /// What was the target site on the code that caused it. This property has been altered to avoid export issues, if a string representation is not sufficient, access the original exception using GetException()
            /// </summary>
            public string TargetSite;

            /// <summary>
            /// The HResult of the exception. Useful in debugging native code errors.
            /// </summary>
            public int HResult;

            /// <summary>
            /// Link to a proper help article.
            /// </summary>
            public string HelpLink;

            /// <summary>
            /// Additional data that has been appended
            /// </summary>
            public IDictionary Data;

            /// <summary>
            /// The inner exception in a chain of exceptions.
            /// </summary>
            public DbatoolsException InnerException;
            #endregion Wrapper around 'official' properties

            #region Custom properties for exception abstraction
            /// <summary>
            /// The full namespace name of the exception that has been wrapped.
            /// </summary>
            public string ExceptionTypeName;

            /// <summary>
            /// Contains additional properties other exceptions might contain.
            /// </summary>
            public Hashtable ExceptionData = new Hashtable();
            #endregion Custom properties for exception abstraction

            #region ErrorRecord Data
            /// <summary>
            /// The category of the error
            /// </summary>
            public ErrorCategoryInfo CategoryInfo;

            /// <summary>
            /// The details on the error
            /// </summary>
            public ErrorDetails ErrorDetails;

            /// <summary>
            /// The specific error identity, used to identify the target
            /// </summary>
            public string FullyQualifiedErrorId;

            /// <summary>
            /// The details of how this was called.
            /// </summary>
            public object InvocationInfo;

            /// <summary>
            /// The script's stacktrace
            /// </summary>
            public string ScriptStackTrace;

            /// <summary>
            /// The object being processed
            /// </summary>
            public object TargetObject;

            /// <summary>
            /// The name of the function throwing the error
            /// </summary>
            public string FunctionName;

            /// <summary>
            /// When was the error thrown
            /// </summary>
            public DateTime Timestamp;

            /// <summary>
            /// The runspace the error occured on.
            /// </summary>
            public Guid Runspace;
            #endregion ErrRecord Data
            #endregion Properties & Fields

            #region Constructors
            /// <summary>
            /// Creates an empty exception object. Mostly for serialization support
            /// </summary>
            public DbatoolsException()
            {

            }

            /// <summary>
            /// Creates an exception based on an original exception object
            /// </summary>
            /// <param name="Except">The exception to wrap around</param>
            public DbatoolsException(Exception Except)
            {
                _Exception = Except;

                Message = Except.Message;
                Source = Except.Source;
                StackTrace = Except.StackTrace;
                try { TargetSite = Except.TargetSite.ToString(); }
                catch { }
                HResult = Except.HResult;
                HelpLink = Except.HelpLink;
                Data = Except.Data;
                if (Except.InnerException != null) { InnerException = new DbatoolsException(Except.InnerException); }

                ExceptionTypeName = Except.GetType().FullName;

                PSObject tempObject = new PSObject(Except);
                List<string> defaultPropertyNames = new List<string>();
                defaultPropertyNames.Add("Data");
                defaultPropertyNames.Add("HelpLink");
                defaultPropertyNames.Add("HResult");
                defaultPropertyNames.Add("InnerException");
                defaultPropertyNames.Add("Message");
                defaultPropertyNames.Add("Source");
                defaultPropertyNames.Add("StackTrace");
                defaultPropertyNames.Add("TargetSite");

                foreach (PSPropertyInfo member in tempObject.Properties)
                {
                    if (!defaultPropertyNames.Contains(member.Name))
                        ExceptionData[member.Name] = member.Value;
                }
            }

            /// <summary>
            /// Creates a rich information exception object based on a full error record as recorded by PowerShell
            /// </summary>
            /// <param name="Record">The error record to copy from</param>
            public DbatoolsException(ErrorRecord Record)
                : this(Record.Exception)
            {
                CategoryInfo = Record.CategoryInfo;
                ErrorDetails = Record.ErrorDetails;
                FullyQualifiedErrorId = Record.FullyQualifiedErrorId;
                InvocationInfo = Record.InvocationInfo;
                ScriptStackTrace = Record.ScriptStackTrace;
                TargetObject = Record.TargetObject;
            }

            /// <summary>
            /// Creates a new exception object with rich meta information from the Dbatools runtime.
            /// </summary>
            /// <param name="Except">The exception thrown</param>
            /// <param name="FunctionName">The name of the function in which the error occured</param>
            /// <param name="Timestamp">When did the error occur</param>
            /// <param name="Message">The message to add to the exception</param>
            /// <param name="Runspace">The ID of the runspace from which the exception was thrown. Useful in multi-runspace scenarios.</param>
            public DbatoolsException(Exception Except, string FunctionName, DateTime Timestamp, string Message, Guid Runspace)
                : this(Except)
            {
                this.Runspace = Runspace;
                this.FunctionName = FunctionName;
                this.Timestamp = Timestamp;
                this.Message = Message;
            }

            /// <summary>
            /// Creates a new exception object with rich meta information from the Dbatools runtime.
            /// </summary>
            /// <param name="Record">The error record written</param>
            /// <param name="FunctionName">The name of the function in which the error occured</param>
            /// <param name="Timestamp">When did the error occur</param>
            /// <param name="Message">The message to add to the exception</param>
            /// <param name="Runspace">The ID of the runspace from which the exception was thrown. Useful in multi-runspace scenarios.</param>
            public DbatoolsException(ErrorRecord Record, string FunctionName, DateTime Timestamp, string Message, Guid Runspace)
                : this(Record)
            {
                this.Runspace = Runspace;
                this.FunctionName = FunctionName;
                this.Timestamp = Timestamp;
                this.Message = Message;
            }
            #endregion Constructors

            /// <summary>
            /// Returns a string representation of the exception.
            /// </summary>
            /// <returns></returns>
            public override string ToString()
            {
                return Message;
            }
        }

        /// <summary>
        /// Carrier class, designed to hold an arbitrary number of exceptions. Used for exporting to XML in nice per-incident packages.
        /// </summary>
        [Serializable]
        public class DbatoolsExceptionRecord
        {
            /// <summary>
            /// Runspace where shit happened.
            /// </summary>
            public Guid Runspace;

            /// <summary>
            /// When did things go bad?
            /// </summary>
            public DateTime Timestamp;

            /// <summary>
            /// Name of the function, where fail happened.
            /// </summary>
            public string FunctionName;

            /// <summary>
            /// The message the poor user was shown.
            /// </summary>
            public string Message;

            /// <summary>
            /// Displays the name of the exception, the make scanning exceptions easier.
            /// </summary>
            public string ExceptionType
            {
                get
                {
                    try
                    {
                        if (Exceptions.Count > 0)
                        {
                            if ((Exceptions[0].GetException().GetType().FullName == "System.Exception") && (Exceptions[0].InnerException != null))
                                return Exceptions[0].InnerException.GetException().GetType().Name;

                            return Exceptions[0].GetException().GetType().Name;
                        }
                    }
                    catch { }

                    return "";
                }
                set
                {

                }
            }

            /// <summary>
            /// The target object of the first exception in the list, if any
            /// </summary>
            public object TargetObject
            {
                get
                {
                    if (Exceptions.Count > 0)
                        return Exceptions[0].TargetObject;
                    else
                        return null;
                }
                set
                {

                }
            }

            /// <summary>
            /// List of Exceptions that are part of the incident (usually - but not always - only one).
            /// </summary>
            public List<DbatoolsException> Exceptions = new List<DbatoolsException>();

            /// <summary>
            /// Creates an empty container. Ideal for the homeworker who loves doing it all himself.
            /// </summary>
            public DbatoolsExceptionRecord()
            {

            }

            /// <summary>
            /// Creates a container filled with the first exception.
            /// </summary>
            /// <param name="Exception"></param>
            public DbatoolsExceptionRecord(DbatoolsException Exception)
            {
                Runspace = Exception.Runspace;
                Timestamp = Exception.Timestamp;
                FunctionName = Exception.FunctionName;
                Message = Exception.Message;
            }

            /// <summary>
            /// Creates a container filled with the meta information but untouched by exceptions
            /// </summary>
            /// <param name="Runspace">The runspace where it all happened</param>
            /// <param name="Timestamp">When did it happen?</param>
            /// <param name="FunctionName">Where did it happen?</param>
            /// <param name="Message">What did the witness have to say?</param>
            public DbatoolsExceptionRecord(Guid Runspace, DateTime Timestamp, string FunctionName, string Message)
            {
                this.Runspace = Runspace;
                this.Timestamp = Timestamp;
                this.FunctionName = FunctionName;
                this.Message = Message;
            }
        }

        /// <summary>
        /// Hosts static debugging values and methods
        /// </summary>
        public static class DebugHost
        {
            #region Defines
            /// <summary>
            /// The maximum numbers of error records maintained in-memory.
            /// </summary>
            public static int MaxErrorCount = 128;

            /// <summary>
            /// The maximum number of messages that can be maintained in the in-memory message queue
            /// </summary>
            public static int MaxMessageCount = 1024;

            /// <summary>
            /// The maximum size of a given logfile. When reaching this limit, the file will be abandoned and a new log created. Set to 0 to not limit the size.
            /// </summary>
            public static int MaxMessagefileBytes = 5242880; // 5MB

            /// <summary>
            /// The maximum number of logfiles maintained at a time. Exceeding this number will cause the oldest to be culled. Set to 0 to disable the limit.
            /// </summary>
            public static int MaxMessagefileCount = 5;

            /// <summary>
            /// The maximum size all error files combined may have. When this number is exceeded, the oldest entry is culled.
            /// </summary>
            public static int MaxErrorFileBytes = 20971520; // 20MB

            /// <summary>
            /// This is the upper limit of length all items in the log folder may have combined across all processes.
            /// </summary>
            public static int MaxTotalFolderSize = 104857600; // 100MB

            /// <summary>
            /// Path to where the logfiles live.
            /// </summary>
            public static string LoggingPath;

            /// <summary>
            /// Any logfile older than this will automatically be cleansed
            /// </summary>
            public static TimeSpan MaxLogFileAge = new TimeSpan(7, 0, 0, 0);

            /// <summary>
            /// Governs, whether a log file for the system messages is written
            /// </summary>
            public static bool MessageLogFileEnabled = true;

            /// <summary>
            /// Governs, whether a log of recent messages is kept in memory
            /// </summary>
            public static bool MessageLogEnabled = true;

            /// <summary>
            /// Governs, whether log files for errors are written
            /// </summary>
            public static bool ErrorLogFileEnabled = true;

            /// <summary>
            /// Governs, whether a log of recent errors is kept in memory
            /// </summary>
            public static bool ErrorLogEnabled = true;

            /// <summary>
            /// Enables the developer mode. In this additional information and logs are written, in order to make it easier to troubleshoot issues.
            /// </summary>
            public static bool DeveloperMode = false;
            #endregion Defines

            #region Queues
            private static ConcurrentQueue<DbatoolsExceptionRecord> ErrorRecords = new ConcurrentQueue<DbatoolsExceptionRecord>();

            private static ConcurrentQueue<LogEntry> LogEntries = new ConcurrentQueue<LogEntry>();

            /// <summary>
            /// The outbound queue for errors. These will be processed and written to xml
            /// </summary>
            public static ConcurrentQueue<DbatoolsExceptionRecord> OutQueueError = new ConcurrentQueue<DbatoolsExceptionRecord>();

            /// <summary>
            /// The outbound queue for logs. These will be processed and written to logfile
            /// </summary>
            public static ConcurrentQueue<LogEntry> OutQueueLog = new ConcurrentQueue<LogEntry>();
            #endregion Queues

            #region Access Queues
            /// <summary>
            /// Retrieves a copy of the Error stack
            /// </summary>
            /// <returns>All errors thrown by dbatools functions</returns>
            public static DbatoolsExceptionRecord[] GetErrors()
            {
                DbatoolsExceptionRecord[] temp = new DbatoolsExceptionRecord[ErrorRecords.Count];
                ErrorRecords.CopyTo(temp, 0);
                return temp;
            }

            /// <summary>
            /// Retrieves a copy of the message log
            /// </summary>
            /// <returns>All messages logged this session.</returns>
            public static LogEntry[] GetLog()
            {
                LogEntry[] temp = new LogEntry[LogEntries.Count];
                LogEntries.CopyTo(temp, 0);
                return temp;
            }

            /// <summary>
            /// Write an error record to the log
            /// </summary>
            /// <param name="Record">The actual error record as powershell wrote it</param>
            /// <param name="FunctionName">The name of the function writing the error</param>
            /// <param name="Timestamp">When was the error written</param>
            /// <param name="Message">What message was passed to the user</param>
            /// <param name="Runspace">The runspace the message was written from</param>
            public static void WriteErrorEntry(ErrorRecord[] Record, string FunctionName, DateTime Timestamp, string Message, Guid Runspace)
            {
                DbatoolsExceptionRecord tempRecord = new DbatoolsExceptionRecord(Runspace, Timestamp, FunctionName, Message);
                foreach (ErrorRecord rec in Record)
                {
                    tempRecord.Exceptions.Add(new DbatoolsException(rec, FunctionName, Timestamp, Message, Runspace));
                }

                if (ErrorLogFileEnabled) { OutQueueError.Enqueue(tempRecord); }
                if (ErrorLogEnabled) { ErrorRecords.Enqueue(tempRecord); }

                DbatoolsExceptionRecord tmp;
                while ((MaxErrorCount > 0) && (ErrorRecords.Count > MaxErrorCount))
                {
                    ErrorRecords.TryDequeue(out tmp);
                }
            }

            /// <summary>
            /// Write a new entry to the log
            /// </summary>
            /// <param name="Message">The message to log</param>
            /// <param name="Type">The type of the message logged</param>
            /// <param name="Timestamp">When was the message generated</param>
            /// <param name="FunctionName">What function wrote the message</param>
            /// <param name="Level">At what level was the function written</param>
            /// <param name="Runspace">The runspace the message is coming from</param>
            /// <param name="TargetObject">The object associated with a given message.</param>
            public static void WriteLogEntry(string Message, LogEntryType Type, DateTime Timestamp, string FunctionName, MessageLevel Level, Guid Runspace, object TargetObject = null)
            {
                LogEntry temp = new LogEntry(Message, Type, Timestamp, FunctionName, Level, Runspace, TargetObject);
                if (MessageLogFileEnabled) { OutQueueLog.Enqueue(temp); }
                if (MessageLogEnabled) { LogEntries.Enqueue(temp); }

                LogEntry tmp;
                while ((MaxMessageCount > 0) && (LogEntries.Count > MaxMessageCount))
                {
                    LogEntries.TryDequeue(out tmp);
                }
            }
            #endregion Access Queues
        }

        /// <summary>
        /// An individual entry for the message log
        /// </summary>
        [Serializable]
        public class LogEntry
        {
            /// <summary>
            /// The message logged
            /// </summary>
            public string Message;

            /// <summary>
            /// What kind of entry was this?
            /// </summary>
            public LogEntryType Type;

            /// <summary>
            /// When was the message logged?
            /// </summary>
            public DateTime Timestamp;

            /// <summary>
            /// What function wrote the message
            /// </summary>
            public string FunctionName;

            /// <summary>
            /// What level was the message?
            /// </summary>
            public MessageLevel Level;

            /// <summary>
            /// What runspace was the message written from?
            /// </summary>
            public Guid Runspace;

            /// <summary>
            /// The object that was the focus of this message.
            /// </summary>
            public object TargetObject;

            /// <summary>
            /// Creates an empty log entry
            /// </summary>
            public LogEntry()
            {

            }

            /// <summary>
            /// Creates a filled out log entry
            /// </summary>
            /// <param name="Message">The message that was logged</param>
            /// <param name="Type">The type(s) of message written</param>
            /// <param name="Timestamp">When was the message logged</param>
            /// <param name="FunctionName">What function wrote the message</param>
            /// <param name="Level">What level was the message written at.</param>
            public LogEntry(string Message, LogEntryType Type, DateTime Timestamp, string FunctionName, MessageLevel Level)
            {
                this.Message = Message;
                this.Type = Type;
                this.Timestamp = Timestamp;
                this.FunctionName = FunctionName;
                this.Level = Level;
            }

            /// <summary>
            /// Creates a filled out log entry
            /// </summary>
            /// <param name="Message">The message that was logged</param>
            /// <param name="Type">The type(s) of message written</param>
            /// <param name="Timestamp">When was the message logged</param>
            /// <param name="FunctionName">What function wrote the message</param>
            /// <param name="Level">What level was the message written at.</param>
            /// <param name="Runspace">The ID of the runspace that wrote the message.</param>
            /// <param name="TargetObject">The object this message was all about.</param>
            public LogEntry(string Message, LogEntryType Type, DateTime Timestamp, string FunctionName, MessageLevel Level, Guid Runspace, object TargetObject)
            {
                this.Message = Message;
                this.Type = Type;
                this.Timestamp = Timestamp;
                this.FunctionName = FunctionName;
                this.Level = Level;
                this.Runspace = Runspace;
                this.TargetObject = TargetObject;
            }
        }

        /// <summary>
        /// The kind of information the logged entry was.
        /// </summary>
        [Flags]
        public enum LogEntryType
        {
            /// <summary>
            /// This entry wasn't written to any stream
            /// </summary>
            None = 0,

            /// <summary>
            /// A message that was written to the current host equivalent, if available also to the information stream
            /// </summary>
            Information = 1,

            /// <summary>
            /// A message that was written to the verbose stream
            /// </summary>
            Verbose = 2,

            /// <summary>
            /// A message that was written to the Debug stream
            /// </summary>
            Debug = 4,

            /// <summary>
            /// A message written to the warning stream
            /// </summary>
            Warning = 8
        }

        /// <summary>
        /// Hosts all functionality of the log writer
        /// </summary>
        public static class LogWriterHost
        {
            #region Logwriter
            private static ScriptBlock LogWritingScript;

            private static PowerShell LogWriter;

            /// <summary>
            /// Setting this to true should cause the script running in the runspace to selfterminate, allowing a graceful selftermination.
            /// </summary>
            public static bool LogWriterStopper
            {
                get { return _LogWriterStopper; }
            }
            private static bool _LogWriterStopper = false;

            /// <summary>
            /// Set the script to use as part of the log writer
            /// </summary>
            /// <param name="Script">The script to use</param>
            public static void SetScript(ScriptBlock Script)
            {
                LogWritingScript = Script;
            }

            /// <summary>
            /// Starts the logwriter.
            /// </summary>
            public static void Start()
            {
                if ((DebugHost.ErrorLogFileEnabled || DebugHost.MessageLogFileEnabled) && (LogWriter == null))
                {
                    _LogWriterStopper = false;
                    LogWriter = PowerShell.Create();
                    LogWriter.AddScript(LogWritingScript.ToString());
                    LogWriter.BeginInvoke();
                }
            }

            /// <summary>
            /// Gracefully stops the logwriter
            /// </summary>
            public static void Stop()
            {
                _LogWriterStopper = true;

                int i = 0;

                // Wait up to 30 seconds for the running script to notice and kill itself
                while ((LogWriter.Runspace.RunspaceAvailability != System.Management.Automation.Runspaces.RunspaceAvailability.Available) && (i < 300))
                {
                    i++;
                    Thread.Sleep(100);
                }

                Kill();
            }

            /// <summary>
            /// Very ungracefully kills the logwriter. Use only in the most dire emergency.
            /// </summary>
            public static void Kill()
            {
                LogWriter.Runspace.Close();
                LogWriter.Dispose();
                LogWriter = null;
            }
            #endregion Logwriter
        }

        /// <summary>
        /// Provides static resources to the messaging subsystem
        /// </summary>
        public static class MessageHost
        {
            #region Defines
            /// <summary>
            /// The maximum message level to still display to the user directly.
            /// </summary>
            public static int MaximumInformation = 3;

            /// <summary>
            /// The maxium message level where verbose information is still written.
            /// </summary>
            public static int MaximumVerbose = 6;

            /// <summary>
            /// The maximum message level where debug information is still written.
            /// </summary>
            public static int MaximumDebug = 9;

            /// <summary>
            /// The minimum required message level for messages that will be shown to the user.
            /// </summary>
            public static int MinimumInformation = 1;

            /// <summary>
            /// The minimum required message level where verbose information is written.
            /// </summary>
            public static int MinimumVerbose = 4;

            /// <summary>
            /// The minimum required message level where debug information is written.
            /// </summary>
            public static int MinimumDebug = 1;

            /// <summary>
            /// The color stuff gets written to the console in
            /// </summary>
            public static ConsoleColor InfoColor = ConsoleColor.Cyan;

            /// <summary>
            /// The color stuff gets written to the console in, when developer mode is enabled and the message would not have been written after all
            /// </summary>
            public static ConsoleColor DeveloperColor = ConsoleColor.Gray;
            #endregion Defines
        }

        /// <summary>
        /// The various levels of verbosity available.
        /// </summary>
        public enum MessageLevel
        {
            /// <summary>
            /// Very important message, should be shown to the user as a high priority
            /// </summary>
            Critical = 1,

            /// <summary>
            /// Important message, the user should read this
            /// </summary>
            Important = 2,

            /// <summary>
            /// Important message, the user should read this
            /// </summary>
            Output = 2,

            /// <summary>
            /// Message relevant to the user.
            /// </summary>
            Significant = 3,

            /// <summary>
            /// Not important to the regular user, still of some interest to the curious
            /// </summary>
            VeryVerbose = 4,

            /// <summary>
            /// Background process information, in case the user wants some detailed information on what is currently happening.
            /// </summary>
            Verbose = 5,

            /// <summary>
            /// A footnote in current processing, rarely of interest to the user
            /// </summary>
            SomewhatVerbose = 6,

            /// <summary>
            /// A message of some interest from an internal system persepctive, but largely irrelevant to the user.
            /// </summary>
            System = 7,

            /// <summary>
            /// Something only of interest to a debugger
            /// </summary>
            Debug = 8,

            /// <summary>
            /// This message barely made the cut from being culled. Of purely development internal interest, and even there is 'interest' a strong word for it.
            /// </summary>
            InternalComment = 9,

            /// <summary>
            /// This message is a warning, sure sign something went badly wrong
            /// </summary>
            Warning = 666
        }
    }

    namespace General
    {
        /// <summary>
        /// What kind of mode do you want to run a command in?
        /// This allows the user to choose how a dbatools function handles a bump in the execution where terminating directly may not be actually mandated.
        /// </summary>
        public enum ExecutionMode
        {
            /// <summary>
            /// When encountering issues, terminate, or skip the currently processed input, rather than continue.
            /// </summary>
            Strict,

            /// <summary>
            /// Continue as able with a best-effort attempt. Simple verbose output should do the rest.
            /// </summary>
            Lazy,

            /// <summary>
            /// Continue, but provide output that can be used to identify the operations that had issues.
            /// </summary>
            Report
        }
    }

    namespace Parameter
    {
        using Connection;
        using System.Collections.Generic;
        using System.Management.Automation;
        using System.Text.RegularExpressions;

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
                    case "sqlcollective.dbatools.connection.managementconnection":
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
        }

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
                get { return _ComputerName; }
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
                    else { return "[" + _InstanceName + "]"; }
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
                    else { return "[" + _ComputerName + "\\" + _InstanceName + "]"; }
                }
            }

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

                if (Name == ".")
                {
                    _ComputerName = Name;
                    _NetworkProtocol = SqlConnectionProtocol.NP;
                    return;
                }

                string tempString = Name;

                // Handle and clear protocols. Otherwise it'd make port detection unneccessarily messy
                if (Regex.IsMatch(tempString, "^TCP:", RegexOptions.IgnoreCase))
                {
                    _NetworkProtocol = SqlConnectionProtocol.TCP;
                    tempString = tempString.Substring(4);
                }
                if (Regex.IsMatch(tempString, "^NP:", RegexOptions.IgnoreCase))
                {
                    _NetworkProtocol = SqlConnectionProtocol.NP;
                    tempString = tempString.Substring(3);
                }

                // Case: Default instance | Instance by port
                if (tempString.Split('\\').Length == 1)
                {
                    if (Regex.IsMatch(tempString, @"[:,]\d{1,5}$") && !Regex.IsMatch(tempString, Utility.RegexHelper.IPv6) && ((tempString.Split(':').Length == 2) || (tempString.Split(',').Length == 2)))
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
                else if (Name.Split('\\').Length == 2)
                {
                    string tempComputerName = Name.Split('\\')[0];
                    string tempInstanceName = Name.Split('\\')[1];

                    if (Regex.IsMatch(tempComputerName, @"[:,]\d{1,5}$") && !Regex.IsMatch(tempComputerName, Utility.RegexHelper.IPv6))
                    {
                        throw new PSArgumentException("Both port and instancename detected! This is redundant and bad practice, specify only one: " + Name);
                    }

                    if (Utility.Validation.IsValidComputerTarget(tempComputerName) && Utility.Validation.IsValidInstanceName(tempInstanceName))
                    {
                        _ComputerName = tempComputerName;
                        _InstanceName = tempInstanceName;
                    }

                    else
                    {
                        throw new PSArgumentException("Failed to parse instance name: " + Name);
                    }
                }

                // Case: Bad input
                else { throw new PSArgumentException("Failed to parse instance name: " + Name); }
            }

            /// <summary>
            /// Creates a DBA Instance Parameter from an IPAddress
            /// </summary>
            /// <param name="Address"></param>
            public DbaInstanceParameter(System.Net.IPAddress Address)
            {
                _ComputerName = Address.ToString();
            }

            /// <summary>
            /// Creates a DBA Instance Parameter from the reply to a ping
            /// </summary>
            /// <param name="Ping">The result of a ping</param>
            public DbaInstanceParameter(System.Net.NetworkInformation.PingReply Ping)
            {
                _ComputerName = Ping.Address.ToString();
            }

            /// <summary>
            /// Creates a DBA Instance Parameter from the result of a dns resolution
            /// </summary>
            /// <param name="Entry">The result of a dns resolution, to be used for targetting the default instance</param>
            public DbaInstanceParameter(System.Net.IPHostEntry Entry)
            {
                _ComputerName = Entry.HostName;
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
                    throw new PSArgumentException("Failed to interpret input as Instance: " + Input.ToString());
                }

                typeName = typeName.Replace("Deserialized.", "");

                switch (typeName)
                {
                    case "microsoft.sqlserver.management.smo.server":
                        try
                        {
                            _ComputerName = (string)tempInput.Properties["NetName"].Value;
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
                            throw new PSArgumentException("Failed to interpret input as Instance: " + Input.ToString() + " : " + e.Message, e);
                        }
                        break;
                    case "microsoft.sqlserver.management.smo.linkedserver":
                        try
                        {
                            _ComputerName = (string)tempInput.Properties["Name"].Value;
                        }
                        catch (Exception e)
                        {
                            throw new PSArgumentException("Failed to interpret input as Instance: " + Input.ToString(), e);
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
                            throw new PSArgumentException("Failed to interpret input as Instance: " + Input.ToString(), e);
                        }
                        break;
                    default:
                        throw new PSArgumentException("Failed to interpret input as Instance: " + Input.ToString());
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

        #region Auxilliary Tools
        /// <summary>
        /// What kind of object was bound to the parameter class?
        /// </summary>
        public enum DbaInstanceInputType
        {
            /// <summary>
            /// Anything, really. An unspecific not reusable type was bound
            /// </summary>
            Default,

            /// <summary>
            /// A live smo linked server object was bound
            /// </summary>
            Linked,

            /// <summary>
            /// A live smo server object was bound
            /// </summary>
            Server,
        }
        #endregion Auxilliary Tools

        #region ParameterClass Interna
        /// <summary>
        /// The attribute used to define the elements of a ParameterClass contract
        /// </summary>
        [AttributeUsage(AttributeTargets.All)]
        public class ParameterContractAttribute : Attribute
        {
            private ParameterContractType type;
            private ParameterContractBehavior behavior;

            /// <summary>
            /// Returns the type of the element this attribute is supposed to be attached to.
            /// </summary>
            public ParameterContractType Type
            {
                get
                {
                    return type;
                }
            }

            /// <summary>
            /// Returns the behavior to expect from the contracted element. This sets the expectations on how this element is likely to act.
            /// </summary>
            public ParameterContractBehavior Behavior
            {
                get
                {
                    return behavior;
                }
            }

            /// <summary>
            /// Ceates a perfectly common parameter contract attribute. For use with all parameter classes' public elements.
            /// </summary>
            /// <param name="Type"></param>
            /// <param name="Behavior"></param>
            public ParameterContractAttribute(ParameterContractType Type, ParameterContractBehavior Behavior)
            {
                type = Type;
                behavior = Behavior;
            }
        }

        /// <summary>
        /// Defines how this element will behave
        /// </summary>
        [Flags]
        public enum ParameterContractBehavior
        {
            /// <summary>
            /// This elements is not actually part of the contract. Generally you wouldn't want to add the attribute at all in that case. However, in some places it helps avoiding confusion.
            /// </summary>
            NotContracted = 0,

            /// <summary>
            /// This element may never be null and must be considered in all assignments. Even if the element is de facto not nullable, all constructors must assign it.
            /// </summary>
            Mandatory = 1,

            /// <summary>
            /// This element may contain data, but is not required to. In case of a method, it may simply do nothing
            /// </summary>
            Optional = 2,

            /// <summary>
            /// This method may throw an error when executing and should always be handled with try/catch. Use this on methods that use external calls.
            /// </summary>
            Failable = 4,

            /// <summary>
            /// The content of the thus marked field determines the dependent's state. Generally, only if the arbiter is true, will the dependent elements be mandatory. This behavior may only be assigned to boolean fields.
            /// </summary>
            Arbiter = 8,

            /// <summary>
            /// This behavior can be assigned together with the 'Mandatory' behavior. It means the field is only mandatory if an arbiter field is present and set to true.
            /// </summary>
            Conditional = 16,

            /// <summary>
            /// Converts content. Generally applied only to operators, but some methods may also convert information.
            /// </summary>
            Conversion = 32
        }

        /// <summary>
        /// Defines what kind of element is granted the contract
        /// </summary>
        public enum ParameterContractType
        {
            /// <summary>
            /// The contracted element is a field containing a value
            /// </summary>
            Field,

            /// <summary>
            /// The contracted element is a method, performing an action
            /// </summary>
            Method,

            /// <summary>
            /// The contracted element is an operator, facilitating type conversion. Generally into a dedicated object type this parameterclass abstracts.
            /// </summary>
            Operator
        }
        #endregion ParameterClass Interna
    }

    namespace TabExpansion
    {
        using System.Collections.Concurrent;
        using System.Collections;
        using System.Management.Automation;

        /// <summary>
        /// Class that handles the static fields supporting the dbatools TabExpansion implementation
        /// </summary>
        public static class TabExpansionHost
        {
            /// <summary>
            /// Field containing the scripts that were registered.
            /// </summary>
            public static ConcurrentDictionary<string, ScriptContainer> Scripts = new ConcurrentDictionary<string, ScriptContainer>();
            
            /// <summary>
            /// The cache used by scripts utilizing TabExpansionPlusPlus in dbatools
            /// </summary>
            public static Hashtable Cache = new Hashtable();
        }

        /// <summary>
        /// Regular container to store scripts in, that are used in TEPP
        /// </summary>
        public class ScriptContainer
        {
            /// <summary>
            /// The name of the scriptblock
            /// </summary>
            public string Name;

            /// <summary>
            /// The scriptblock doing the logic
            /// </summary>
            public ScriptBlock ScriptBlock;

            /// <summary>
            /// The last time the scriptblock was called. Must be updated by the scriptblock itself
            /// </summary>
            public DateTime LastExecution;

            /// <summary>
            /// The time it took to run the last time
            /// </summary>
            public TimeSpan LastDuration;
        }
    }

    namespace Utility
    {
        using System.Management.Automation;
        using System.Net;
        using System.Net.NetworkInformation;
        using System.Text.RegularExpressions;

        /// <summary>
        /// Extends DateTime
        /// </summary>
        public static class DateTimeExtension
        {
            /// <summary>
            /// Adds a compareTo method to DateTime to compare with DbaDateTimeBase
            /// </summary>
            /// <param name="Base">The extended DateTime object</param>
            /// <param name="comparedTo">The DbaDateTimeBase to compare with</param>
            /// <returns></returns>
            public static int CompareTo(this DateTime Base, DbaDateTimeBase comparedTo)
            {
                return Base.CompareTo(comparedTo);
            }
        }

        /// <summary>
        /// Base class for wrapping around a DateTime object
        /// </summary>
        public class DbaDateTimeBase : IComparable, IComparable<DateTime>, IEquatable<DateTime> // IFormattable,
        {
            #region Properties
            /// <summary>
            /// The core resource, containing the actual timestamp
            /// </summary>
            internal DateTime _timestamp;

            /// <summary>
            /// Gets the date component of this instance.
            /// </summary>
            public DateTime Date
            {
                get { return _timestamp.Date; }
            }

            /// <summary>
            /// Gets the day of the month represented by this instance.
            /// </summary>
            public int Day
            {
                get { return _timestamp.Day; }
            }

            /// <summary>
            /// Gets the day of the week represented by this instance.
            /// </summary>
            public DayOfWeek DayOfWeek
            {
                get { return _timestamp.DayOfWeek; }
            }

            /// <summary>
            /// Gets the day of the year represented by this instance.
            /// </summary>
            public int DayOfYear
            {
                get { return _timestamp.DayOfYear; }
            }

            /// <summary>
            /// Gets the hour component of the date represented by this instance.
            /// </summary>
            public int Hour
            {
                get { return _timestamp.Hour; }
            }

            /// <summary>
            /// Gets a value that indicates whether the time represented by this instance is based on local time, Coordinated Universal Time (UTC), or neither.
            /// </summary>
            public DateTimeKind Kind
            {
                get { return _timestamp.Kind; }
            }

            /// <summary>
            /// Gets the milliseconds component of the date represented by this instance.
            /// </summary>
            public int Millisecond
            {
                get { return _timestamp.Millisecond; }
            }

            /// <summary>
            /// Gets the minute component of the date represented by this instance.
            /// </summary>
            public int Minute
            {
                get { return _timestamp.Minute; }
            }

            /// <summary>
            /// Gets the month component of the date represented by this instance.
            /// </summary>
            public int Month
            {
                get { return _timestamp.Month; }
            }

            /// <summary>
            /// Gets the seconds component of the date represented by this instance.
            /// </summary>
            public int Second
            {
                get { return _timestamp.Second; }
            }

            /// <summary>
            /// Gets the number of ticks that represent the date and time of this instance.
            /// </summary>
            public long Ticks
            {
                get { return _timestamp.Ticks; }
            }

            /// <summary>
            /// Gets the time of day for this instance.
            /// </summary>
            public TimeSpan TimeOfDay
            {
                get { return _timestamp.TimeOfDay; }
            }

            /// <summary>
            /// Gets the year component of the date represented by this instance.
            /// </summary>
            public int Year
            {
                get { return _timestamp.Year; }
            }
            #endregion Properties

            #region Constructors
            /// <summary>
            /// Constructor that should never be called, since this class should never be instantiated. It's there for implicit calls on child classes.
            /// </summary>
            public DbaDateTimeBase()
            {

            }

            /// <summary>
            /// Constructs a generic timestamp object wrapper from an input timestamp object.
            /// </summary>
            /// <param name="Timestamp">The timestamp to wrap</param>
            public DbaDateTimeBase(DateTime Timestamp)
            {
                _timestamp = Timestamp;
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="ticks"></param>
            public DbaDateTimeBase(long ticks)
            {
                _timestamp = new DateTime(ticks);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="ticks"></param>
            /// <param name="kind"></param>
            public DbaDateTimeBase(long ticks, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(ticks, kind);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            public DbaDateTimeBase(int year, int month, int day)
            {
                _timestamp = new DateTime(year, month, day);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="calendar"></param>
            public DbaDateTimeBase(int year, int month, int day, System.Globalization.Calendar calendar)
            {
                _timestamp = new DateTime(year, month, day, calendar);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="kind"></param>
            public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, kind);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="calendar"></param>
            public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, System.Globalization.Calendar calendar)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, calendar);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, int millisecond)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            /// <param name="kind"></param>
            public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, int millisecond, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, kind);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            /// <param name="calendar"></param>
            public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, calendar);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            /// <param name="calendar"></param>
            /// <param name="kind"></param>
            public DbaDateTimeBase(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, calendar, kind);
            }
            #endregion Constructors

            #region Methods
            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public DateTime Add(TimeSpan value)
            {
                return _timestamp.Add(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public DateTime AddDays(double value)
            {
                return _timestamp.AddDays(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public DateTime AddHours(double value)
            {
                return _timestamp.AddHours(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public DateTime AddMilliseconds(double value)
            {
                return _timestamp.AddMilliseconds(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public DateTime AddMinutes(double value)
            {
                return _timestamp.AddMinutes(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="months"></param>
            /// <returns></returns>
            public DateTime AddMonths(int months)
            {
                return _timestamp.AddMonths(months);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public DateTime AddSeconds(double value)
            {
                return _timestamp.AddSeconds(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public DateTime AddTicks(long value)
            {
                return _timestamp.AddTicks(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public DateTime AddYears(int value)
            {
                return _timestamp.AddYears(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public int CompareTo(System.Object value)
            {
                return _timestamp.CompareTo(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public int CompareTo(DateTime value)
            {
                return _timestamp.CompareTo(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public override bool Equals(System.Object value)
            {
                return _timestamp.Equals(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public bool Equals(DateTime value)
            {
                return _timestamp.Equals(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public string[] GetDateTimeFormats()
            {
                return _timestamp.GetDateTimeFormats();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="provider"></param>
            /// <returns></returns>
            public string[] GetDateTimeFormats(System.IFormatProvider provider)
            {
                return _timestamp.GetDateTimeFormats(provider);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="format"></param>
            /// <returns></returns>
            public string[] GetDateTimeFormats(char format)
            {
                return _timestamp.GetDateTimeFormats(format);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="format"></param>
            /// <param name="provider"></param>
            /// <returns></returns>
            public string[] GetDateTimeFormats(char format, System.IFormatProvider provider)
            {
                return _timestamp.GetDateTimeFormats(format, provider);
            }

            /// <summary>
            /// Retrieve base DateTime object, this is a wrapper for
            /// </summary>
            /// <returns>Base DateTime object</returns>
            public DateTime GetBaseObject()
            {
                return _timestamp;
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public override int GetHashCode()
            {
                return _timestamp.GetHashCode();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public System.TypeCode GetTypeCode()
            {
                return _timestamp.GetTypeCode();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public bool IsDaylightSavingTime()
            {
                return _timestamp.IsDaylightSavingTime();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public TimeSpan Subtract(DateTime value)
            {
                return _timestamp.Subtract(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public DateTime Subtract(TimeSpan value)
            {
                return _timestamp.Subtract(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public long ToBinary()
            {
                return _timestamp.ToBinary();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public long ToFileTime()
            {
                return _timestamp.ToFileTime();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public long ToFileTimeUtc()
            {
                return _timestamp.ToFileTimeUtc();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public DateTime ToLocalTime()
            {
                return _timestamp.ToLocalTime();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public string ToLongDateString()
            {
                return _timestamp.ToLongDateString();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public string ToLongTimeString()
            {
                return _timestamp.ToLongTimeString();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public double ToOADate()
            {
                return _timestamp.ToOADate();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public string ToShortDateString()
            {
                return _timestamp.ToShortDateString();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public string ToShortTimeString()
            {
                return _timestamp.ToShortTimeString();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="format"></param>
            /// <returns></returns>
            public string ToString(string format)
            {
                return _timestamp.ToString(format);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="provider"></param>
            /// <returns></returns>
            public string ToString(System.IFormatProvider provider)
            {
                return _timestamp.ToString(provider);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="format"></param>
            /// <param name="provider"></param>
            /// <returns></returns>
            public string ToString(string format, System.IFormatProvider provider)
            {
                return _timestamp.ToString(format, provider);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public DateTime ToUniversalTime()
            {
                return _timestamp.ToUniversalTime();
            }


            #endregion Methods

            #region Operators
            /// <summary>
            /// 
            /// </summary>
            /// <param name="Timestamp"></param>
            /// <param name="Duration"></param>
            /// <returns></returns>
            public static DbaDateTimeBase operator +(DbaDateTimeBase Timestamp, TimeSpan Duration)
            {
                return Timestamp.Add(Duration);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="Timestamp"></param>
            /// <param name="Duration"></param>
            /// <returns></returns>
            public static DbaDateTimeBase operator -(DbaDateTimeBase Timestamp, TimeSpan Duration)
            {
                return Timestamp.Subtract(Duration);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="Timestamp1"></param>
            /// <param name="Timestamp2"></param>
            /// <returns></returns>
            public static bool operator ==(DbaDateTimeBase Timestamp1, DbaDateTimeBase Timestamp2)
            {
                return (Timestamp1.GetBaseObject().Equals(Timestamp2.GetBaseObject()));
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="Timestamp1"></param>
            /// <param name="Timestamp2"></param>
            /// <returns></returns>
            public static bool operator !=(DbaDateTimeBase Timestamp1, DbaDateTimeBase Timestamp2)
            {
                return (!Timestamp1.GetBaseObject().Equals(Timestamp2.GetBaseObject()));
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="Timestamp1"></param>
            /// <param name="Timestamp2"></param>
            /// <returns></returns>
            public static bool operator >(DbaDateTimeBase Timestamp1, DbaDateTimeBase Timestamp2)
            {
                return Timestamp1.GetBaseObject() > Timestamp2.GetBaseObject();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="Timestamp1"></param>
            /// <param name="Timestamp2"></param>
            /// <returns></returns>
            public static bool operator <(DbaDateTimeBase Timestamp1, DbaDateTimeBase Timestamp2)
            {
                return Timestamp1.GetBaseObject() < Timestamp2.GetBaseObject();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="Timestamp1"></param>
            /// <param name="Timestamp2"></param>
            /// <returns></returns>
            public static bool operator >=(DbaDateTimeBase Timestamp1, DbaDateTimeBase Timestamp2)
            {
                return Timestamp1.GetBaseObject() >= Timestamp2.GetBaseObject();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="Timestamp1"></param>
            /// <param name="Timestamp2"></param>
            /// <returns></returns>
            public static bool operator <=(DbaDateTimeBase Timestamp1, DbaDateTimeBase Timestamp2)
            {
                return Timestamp1.GetBaseObject() <= Timestamp2.GetBaseObject();
            }
            #endregion Operators

            #region Implicit Conversions
            /// <summary>
            /// Implicitly convert DbaDateTimeBase to DateTime
            /// </summary>
            /// <param name="Base">The source object to convert</param>
            public static implicit operator DateTime(DbaDateTimeBase Base)
            {
                return Base.GetBaseObject();
            }

            /// <summary>
            /// Implicitly convert DateTime to DbaDateTimeBase
            /// </summary>
            /// <param name="Base">The object to convert</param>
            public static implicit operator DbaDateTimeBase(DateTime Base)
            {
                return new DbaDateTimeBase(Base.Ticks, Base.Kind);
            }
            #endregion Implicit Conversions
        }

        /// <summary>
        /// A dbatools-internal datetime wrapper for neater display
        /// </summary>
        public class DbaDate : DbaDateTimeBase
        {
            #region Constructors
            /// <summary>
            /// Constructs a generic timestamp object wrapper from an input timestamp object.
            /// </summary>
            /// <param name="Timestamp">The timestamp to wrap</param>
            public DbaDate(DateTime Timestamp)
            {
                _timestamp = Timestamp;
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="ticks"></param>
            public DbaDate(long ticks)
            {
                _timestamp = new DateTime(ticks);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="ticks"></param>
            /// <param name="kind"></param>
            public DbaDate(long ticks, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(ticks, kind);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            public DbaDate(int year, int month, int day)
            {
                _timestamp = new DateTime(year, month, day);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="calendar"></param>
            public DbaDate(int year, int month, int day, System.Globalization.Calendar calendar)
            {
                _timestamp = new DateTime(year, month, day, calendar);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            public DbaDate(int year, int month, int day, int hour, int minute, int second)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="kind"></param>
            public DbaDate(int year, int month, int day, int hour, int minute, int second, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, kind);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="calendar"></param>
            public DbaDate(int year, int month, int day, int hour, int minute, int second, System.Globalization.Calendar calendar)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, calendar);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            public DbaDate(int year, int month, int day, int hour, int minute, int second, int millisecond)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            /// <param name="kind"></param>
            public DbaDate(int year, int month, int day, int hour, int minute, int second, int millisecond, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, kind);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            /// <param name="calendar"></param>
            public DbaDate(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, calendar);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            /// <param name="calendar"></param>
            /// <param name="kind"></param>
            public DbaDate(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, calendar, kind);
            }
            #endregion Constructors

            /// <summary>
            /// Provids the default-formated string, using the defined default formatting.
            /// </summary>
            /// <returns>Formatted datetime-string</returns>
            public override string ToString()
            {
                if (UtilityHost.DisableCustomDateTime) { return _timestamp.ToString(); }
                return _timestamp.ToString(UtilityHost.FormatDate);
            }

            #region Implicit Conversions
            /// <summary>
            /// Implicitly convert to DateTime
            /// </summary>
            /// <param name="Base">The source object to convert</param>
            public static implicit operator DateTime(DbaDate Base)
            {
                return Base.GetBaseObject();
            }

            /// <summary>
            /// Implicitly convert from DateTime
            /// </summary>
            /// <param name="Base">The object to convert</param>
            public static implicit operator DbaDate(DateTime Base)
            {
                return new DbaDate(Base);
            }

            /// <summary>
            /// Implicitly convert to DbaDate
            /// </summary>
            /// <param name="Base">The source object to convert</param>
            public static implicit operator DbaDateTime(DbaDate Base)
            {
                return new DbaDateTime(Base.GetBaseObject());
            }

            /// <summary>
            /// Implicitly convert to DbaTime
            /// </summary>
            /// <param name="Base">The source object to convert</param>
            public static implicit operator DbaTime(DbaDate Base)
            {
                return new DbaTime(Base.GetBaseObject());
            }
            #endregion Implicit Conversions

            #region Statics
            /// <summary>
            /// Generates a DbaDate object based off DateTime object. Will be null if Base is the start value (Tickes == 0).
            /// </summary>
            /// <param name="Base">The Datetime to base it off</param>
            /// <returns>The object to generate (or null)</returns>
            public static DbaDate Generate(DateTime Base)
            {
                if (Base.Ticks == 0)
                    return null;
                else
                    return new DbaDate(Base);
            }
            #endregion Statics
        }

        /// <summary>
        /// A dbatools-internal datetime wrapper for neater display
        /// </summary>
        public class DbaDateTime : DbaDateTimeBase
        {
            #region Constructors
            /// <summary>
            /// Constructs a generic timestamp object wrapper from an input timestamp object.
            /// </summary>
            /// <param name="Timestamp">The timestamp to wrap</param>
            public DbaDateTime(DateTime Timestamp)
            {
                _timestamp = Timestamp;
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="ticks"></param>
            public DbaDateTime(long ticks)
            {
                _timestamp = new DateTime(ticks);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="ticks"></param>
            /// <param name="kind"></param>
            public DbaDateTime(long ticks, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(ticks, kind);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            public DbaDateTime(int year, int month, int day)
            {
                _timestamp = new DateTime(year, month, day);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="calendar"></param>
            public DbaDateTime(int year, int month, int day, System.Globalization.Calendar calendar)
            {
                _timestamp = new DateTime(year, month, day, calendar);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            public DbaDateTime(int year, int month, int day, int hour, int minute, int second)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="kind"></param>
            public DbaDateTime(int year, int month, int day, int hour, int minute, int second, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, kind);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="calendar"></param>
            public DbaDateTime(int year, int month, int day, int hour, int minute, int second, System.Globalization.Calendar calendar)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, calendar);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            public DbaDateTime(int year, int month, int day, int hour, int minute, int second, int millisecond)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            /// <param name="kind"></param>
            public DbaDateTime(int year, int month, int day, int hour, int minute, int second, int millisecond, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, kind);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            /// <param name="calendar"></param>
            public DbaDateTime(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, calendar);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            /// <param name="calendar"></param>
            /// <param name="kind"></param>
            public DbaDateTime(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, calendar, kind);
            }
            #endregion Constructors

            /// <summary>
            /// Provids the default-formated string, using the defined default formatting.
            /// </summary>
            /// <returns>Formatted datetime-string</returns>
            public override string ToString()
            {
                if (UtilityHost.DisableCustomDateTime) { return _timestamp.ToString(); }
                return _timestamp.ToString(UtilityHost.FormatDateTime);
            }

            #region Implicit Conversions
            /// <summary>
            /// Implicitly convert to DateTime
            /// </summary>
            /// <param name="Base">The source object to convert</param>
            public static implicit operator DateTime(DbaDateTime Base)
            {
                return Base.GetBaseObject();
            }

            /// <summary>
            /// Implicitly convert from DateTime
            /// </summary>
            /// <param name="Base">The object to convert</param>
            public static implicit operator DbaDateTime(DateTime Base)
            {
                return new DbaDateTime(Base);
            }

            /// <summary>
            /// Implicitly convert to DbaDate
            /// </summary>
            /// <param name="Base">The source object to convert</param>
            public static implicit operator DbaDate(DbaDateTime Base)
            {
                return new DbaDate(Base.GetBaseObject());
            }

            /// <summary>
            /// Implicitly convert to DbaTime
            /// </summary>
            /// <param name="Base">The source object to convert</param>
            public static implicit operator DbaTime(DbaDateTime Base)
            {
                return new DbaTime(Base.GetBaseObject());
            }
            #endregion Implicit Conversions

            #region Statics
            /// <summary>
            /// Generates a DbaDateTime object based off DateTime object. Will be null if Base is the start value (Tickes == 0).
            /// </summary>
            /// <param name="Base">The Datetime to base it off</param>
            /// <returns>The object to generate (or null)</returns>
            public static DbaDateTime Generate(DateTime Base)
            {
                if (Base.Ticks == 0)
                    return null;
                else
                    return new DbaDateTime(Base);
            }
            #endregion Statics
        }

        /// <summary>
        /// A dbatools-internal datetime wrapper for neater display
        /// </summary>
        public class DbaTime : DbaDateTimeBase
        {
            #region Constructors
            /// <summary>
            /// Constructs a generic timestamp object wrapper from an input timestamp object.
            /// </summary>
            /// <param name="Timestamp">The timestamp to wrap</param>
            public DbaTime(DateTime Timestamp)
            {
                _timestamp = Timestamp;
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="ticks"></param>
            public DbaTime(long ticks)
            {
                _timestamp = new DateTime(ticks);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="ticks"></param>
            /// <param name="kind"></param>
            public DbaTime(long ticks, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(ticks, kind);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            public DbaTime(int year, int month, int day)
            {
                _timestamp = new DateTime(year, month, day);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="calendar"></param>
            public DbaTime(int year, int month, int day, System.Globalization.Calendar calendar)
            {
                _timestamp = new DateTime(year, month, day, calendar);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            public DbaTime(int year, int month, int day, int hour, int minute, int second)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="kind"></param>
            public DbaTime(int year, int month, int day, int hour, int minute, int second, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, kind);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="calendar"></param>
            public DbaTime(int year, int month, int day, int hour, int minute, int second, System.Globalization.Calendar calendar)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, calendar);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            public DbaTime(int year, int month, int day, int hour, int minute, int second, int millisecond)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            /// <param name="kind"></param>
            public DbaTime(int year, int month, int day, int hour, int minute, int second, int millisecond, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, kind);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            /// <param name="calendar"></param>
            public DbaTime(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, calendar);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="year"></param>
            /// <param name="month"></param>
            /// <param name="day"></param>
            /// <param name="hour"></param>
            /// <param name="minute"></param>
            /// <param name="second"></param>
            /// <param name="millisecond"></param>
            /// <param name="calendar"></param>
            /// <param name="kind"></param>
            public DbaTime(int year, int month, int day, int hour, int minute, int second, int millisecond, System.Globalization.Calendar calendar, System.DateTimeKind kind)
            {
                _timestamp = new DateTime(year, month, day, hour, minute, second, millisecond, calendar, kind);
            }
            #endregion Constructors

            /// <summary>
            /// Provids the default-formated string, using the defined default formatting.
            /// </summary>
            /// <returns>Formatted datetime-string</returns>
            public override string ToString()
            {
                if (UtilityHost.DisableCustomDateTime) { return _timestamp.ToString(); }
                return _timestamp.ToString(UtilityHost.FormatTime);
            }

            #region Implicit Conversions
            /// <summary>
            /// Implicitly convert to DateTime
            /// </summary>
            /// <param name="Base">The source object to convert</param>
            public static implicit operator DateTime(DbaTime Base)
            {
                return Base.GetBaseObject();
            }

            /// <summary>
            /// Implicitly convert from DateTime
            /// </summary>
            /// <param name="Base">The object to convert</param>
            public static implicit operator DbaTime(DateTime Base)
            {
                return new DbaTime(Base);
            }

            /// <summary>
            /// Implicitly convert to DbaDate
            /// </summary>
            /// <param name="Base">The source object to convert</param>
            public static implicit operator DbaDate(DbaTime Base)
            {
                return new DbaDate(Base.GetBaseObject());
            }

            /// <summary>
            /// Implicitly convert to DbaTime
            /// </summary>
            /// <param name="Base">The source object to convert</param>
            public static implicit operator DbaDateTime(DbaTime Base)
            {
                return new DbaDateTime(Base.GetBaseObject());
            }

            /// <summary>
            /// Implicitly convert to string
            /// </summary>
            /// <param name="Base">Object to convert</param>
            public static implicit operator string(DbaTime Base)
            {
                return Base.ToString();
            }
            #endregion Implicit Conversions

            #region Statics
            /// <summary>
            /// Generates a DbaDateTime object based off DateTime object. Will be null if Base is the start value (Tickes == 0).
            /// </summary>
            /// <param name="Base">The Datetime to base it off</param>
            /// <returns>The object to generate (or null)</returns>
            public static DbaTime Generate(DateTime Base)
            {
                if (Base.Ticks == 0)
                    return null;
                else
                    return new DbaTime(Base);
            }
            #endregion Statics
        }

        /// <summary>
        /// A wrapper class, encapsuling a regular TimeSpan object. Used to provide custom timespan display.
        /// </summary>
        public class DbaTimeSpan : IComparable, IComparable<TimeSpan>, IComparable<DbaTimeSpan>, IEquatable<TimeSpan>
        {
            internal TimeSpan _timespan;

            #region Properties
            /// <summary>
            /// Gets the days component of the time interval represented by the current TimeSpan structure.
            /// </summary>
            public int Days
            {
                get
                {
                    return _timespan.Days;
                }
            }

            /// <summary>
            /// Gets the hours component of the time interval represented by the current TimeSpan structure.
            /// </summary>
            public int Hours
            {
                get
                {
                    return _timespan.Hours;
                }
            }

            /// <summary>
            /// Gets the milliseconds component of the time interval represented by the current TimeSpan structure.
            /// </summary>
            public int Milliseconds
            {
                get
                {
                    return _timespan.Milliseconds;
                }
            }

            /// <summary>
            /// Gets the minutes component of the time interval represented by the current TimeSpan structure.
            /// </summary>
            public int Minutes
            {
                get
                {
                    return _timespan.Minutes;
                }
            }

            /// <summary>
            /// Gets the seconds component of the time interval represented by the current TimeSpan structure.
            /// </summary>
            public int Seconds
            {
                get
                {
                    return _timespan.Seconds;
                }
            }

            /// <summary>
            /// Gets the number of ticks that represent the value of the current TimeSpan structure.
            /// </summary>
            public long Ticks
            {
                get
                {
                    return _timespan.Ticks;
                }
            }

            /// <summary>
            /// Gets the value of the current TimeSpan structure expressed in whole and fractional days.
            /// </summary>
            public double TotalDays
            {
                get
                {
                    return _timespan.TotalDays;
                }
            }

            /// <summary>
            /// Gets the value of the current TimeSpan structure expressed in whole and fractional hours.
            /// </summary>
            public double TotalHours
            {
                get
                {
                    return _timespan.TotalHours;
                }
            }

            /// <summary>
            /// Gets the value of the current TimeSpan structure expressed in whole and fractional milliseconds.
            /// </summary>
            public double TotalMilliseconds
            {
                get
                {
                    return _timespan.TotalMilliseconds;
                }
            }

            /// <summary>
            /// Gets the value of the current TimeSpan structure expressed in whole and fractional minutes.
            /// </summary>
            public double TotalMinutes
            {
                get
                {
                    return _timespan.TotalMinutes;
                }
            }

            /// <summary>
            /// Gets the value of the current TimeSpan structure expressed in whole and fractional seconds.
            /// </summary>
            public double TotalSeconds
            {
                get
                {
                    return _timespan.TotalSeconds;
                }
            }
            #endregion Properties

            #region Constructors
            /// <summary>
            /// 
            /// </summary>
            /// <param name="Timespan"></param>
            public DbaTimeSpan(TimeSpan Timespan)
            {
                _timespan = Timespan;
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="ticks"></param>
            public DbaTimeSpan(long ticks)
            {
                _timespan = new TimeSpan(ticks);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="hours"></param>
            /// <param name="minutes"></param>
            /// <param name="seconds"></param>
            public DbaTimeSpan(int hours, int minutes, int seconds)
            {
                _timespan = new TimeSpan(hours, minutes, seconds);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="days"></param>
            /// <param name="hours"></param>
            /// <param name="minutes"></param>
            /// <param name="seconds"></param>
            public DbaTimeSpan(int days, int hours, int minutes, int seconds)
            {
                _timespan = new TimeSpan(days, hours, minutes, seconds);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="days"></param>
            /// <param name="hours"></param>
            /// <param name="minutes"></param>
            /// <param name="seconds"></param>
            /// <param name="milliseconds"></param>
            public DbaTimeSpan(int days, int hours, int minutes, int seconds, int milliseconds)
            {
                _timespan = new TimeSpan(days, hours, minutes, seconds, milliseconds);
            }
            #endregion Constructors

            #region Methods
            /// <summary>
            /// 
            /// </summary>
            /// <param name="ts"></param>
            /// <returns></returns>
            public TimeSpan Add(TimeSpan ts)
            {
                return _timespan.Add(ts);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public int CompareTo(System.Object value)
            {
                return _timespan.CompareTo(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public int CompareTo(TimeSpan value)
            {
                return _timespan.CompareTo(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public int CompareTo(DbaTimeSpan value)
            {
                return _timespan.CompareTo(value.GetBaseObject());
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public TimeSpan Duration()
            {
                return _timespan.Duration();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="value"></param>
            /// <returns></returns>
            public override bool Equals(System.Object value)
            {
                return _timespan.Equals(value);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="obj"></param>
            /// <returns></returns>
            public bool Equals(TimeSpan obj)
            {
                return _timespan.Equals(obj);
            }

            /// <summary>
            /// Returns the wrapped base object
            /// </summary>
            /// <returns>The base object</returns>
            public TimeSpan GetBaseObject()
            {
                return _timespan;
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public override int GetHashCode()
            {
                return _timespan.GetHashCode();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <returns></returns>
            public TimeSpan Negate()
            {
                return _timespan.Negate();
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="ts"></param>
            /// <returns></returns>
            public TimeSpan Subtract(TimeSpan ts)
            {
                return _timespan.Subtract(ts);
            }

            /// <summary>
            /// Returns the default string representation of the TimeSpan object
            /// </summary>
            /// <returns>The string representation of the DbaTimeSpan object</returns>
            public override string ToString()
            {
                if (UtilityHost.DisableCustomTimeSpan) { return _timespan.ToString(); }
                else if (_timespan.Ticks % 10000000 == 0) { return _timespan.ToString(); }
                else
                {
                    string temp = _timespan.ToString();

                    if (_timespan.TotalSeconds < 10) { temp = temp.Substring(0, temp.LastIndexOf(".") + 3); }
                    else if (_timespan.TotalSeconds < 100) { temp = temp.Substring(0, temp.LastIndexOf(".") + 2); }
                    else { temp = temp.Substring(0, temp.LastIndexOf(".")); }

                    return temp;
                }
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="format"></param>
            /// <returns></returns>
            public string ToString(string format)
            {
                return _timespan.ToString(format);
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="format"></param>
            /// <param name="formatProvider"></param>
            /// <returns></returns>
            public string ToString(string format, System.IFormatProvider formatProvider)
            {
                return _timespan.ToString(format, formatProvider);
            }
            #endregion Methods

            #region Implicit Operators
            /// <summary>
            /// Implicitly converts a DbaTimeSpan object into a TimeSpan object
            /// </summary>
            /// <param name="Base">The original object to revert</param>
            public static implicit operator TimeSpan(DbaTimeSpan Base)
            {
                try { return Base.GetBaseObject(); }
                catch { }
                return new TimeSpan();
            }

            /// <summary>
            /// Implicitly converts a TimeSpan object into a DbaTimeSpan object
            /// </summary>
            /// <param name="Base">The original object to wrap</param>
            public static implicit operator DbaTimeSpan(TimeSpan Base)
            {
                return new DbaTimeSpan(Base);
            }
            #endregion Implicit Operators
        }

        /// <summary>
        /// Makes timespan great again
        /// </summary>
        public class DbaTimeSpanPretty : DbaTimeSpan
        {
            #region Methods
            /// <summary>
            /// Creates a new, pretty timespan object from milliseconds
            /// </summary>
            /// <param name="Milliseconds">The milliseconds to convert from.</param>
            /// <returns>A pretty timespan object</returns>
            public static DbaTimeSpanPretty FromMilliseconds(double Milliseconds)
            {
                return new DbaTimeSpanPretty((long)(Milliseconds * 10000));
            }
            #endregion Methods

            #region Constructors
            /// <summary>
            /// 
            /// </summary>
            /// <param name="Timespan"></param>
            public DbaTimeSpanPretty(TimeSpan Timespan)
                :base(Timespan)
            {
                
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="ticks"></param>
            public DbaTimeSpanPretty(long ticks)
                :base(ticks)
            {
                
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="hours"></param>
            /// <param name="minutes"></param>
            /// <param name="seconds"></param>
            public DbaTimeSpanPretty(int hours, int minutes, int seconds)
                :base(hours, minutes, seconds)
            {
                
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="days"></param>
            /// <param name="hours"></param>
            /// <param name="minutes"></param>
            /// <param name="seconds"></param>
            public DbaTimeSpanPretty(int days, int hours, int minutes, int seconds)
                :base(days, hours, minutes, seconds)
            {
                
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="days"></param>
            /// <param name="hours"></param>
            /// <param name="minutes"></param>
            /// <param name="seconds"></param>
            /// <param name="milliseconds"></param>
            public DbaTimeSpanPretty(int days, int hours, int minutes, int seconds, int milliseconds)
                :base(days, hours, minutes, seconds, milliseconds)
            {
                
            }
            #endregion Constructors

            /// <summary>
            /// Creates extra-nice timespan formats
            /// </summary>
            /// <returns>Humanly readable timespans</returns>
            public override string ToString()
            {
                if (UtilityHost.DisableCustomTimeSpan) { return _timespan.ToString(); }

                string temp = "";

                if (_timespan.TotalSeconds < 1)
                {
                    temp = Math.Round(_timespan.TotalMilliseconds, 2).ToString() + "ms";
                }
                else if (_timespan.TotalSeconds <= 60)
                {
                    temp = _timespan.Seconds + "s";
                    if (_timespan.Milliseconds > 0)
                        temp = temp + ", " + _timespan.Milliseconds + "ms";
                }
                else
                {
                    if (_timespan.Ticks % 10000000 == 0) { return _timespan.ToString(); }
                    else
                    {
                        temp = _timespan.ToString();

                        temp = temp.Substring(0, temp.LastIndexOf("."));

                        return temp;
                    }
                }

                return temp;
            }
        }

        /// <summary>
        /// Static class that holds useful regex patterns, ready for use
        /// </summary>
        public static class RegexHelper
        {
            /// <summary>
            /// Pattern that checks for a valid hostname
            /// </summary>
            public static string HostName = @"^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-_]{0,61}[a-zA-Z0-9])(\.([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-_]{0,61}[a-zA-Z0-9]))*$";

            /// <summary>
            /// Pattern that checks for valid hostnames within a larger text
            /// </summary>
            public static string HostNameEx = @"([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-_]{0,61}[a-zA-Z0-9])(\.([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-_]{0,61}[a-zA-Z0-9]))*";

            /// <summary>
            /// Pattern that checks for a valid IPv4 address
            /// </summary>
            public static string IPv4 = @"^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}$";

            /// <summary>
            /// Pattern that checks for valid IPv4 addresses within a larger text
            /// </summary>
            public static string IPv4Ex = @"(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}";

            /// <summary>
            /// Will match a valid IPv6 address
            /// </summary>
            public static string IPv6 = @"^(?:^|(?<=\s))(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))(?=\s|$)$";

            /// <summary>
            /// Will match any IPv6 address within a larger text
            /// </summary>
            public static string IPv6Ex = @"(?:^|(?<=\s))(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))(?=\s|$)";

            /// <summary>
            /// Will match any string that in its entirety represents a valid target for dns- or ip-based targeting. Combination of HostName, IPv4 and IPv6
            /// </summary>
            public static string ComputerTarget = @"^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-_]{0,61}[a-zA-Z0-9])(\.([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-_]{0,61}[a-zA-Z0-9]))*$|^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}$|^(?:^|(?<=\s))(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))(?=\s|$)$";

            /// <summary>
            /// Will match a valid Guid
            /// </summary>
            public static string Guid = @"^(\{{0,1}([0-9a-fA-F]){8}-([0-9a-fA-F]){4}-([0-9a-fA-F]){4}-([0-9a-fA-F]){4}-([0-9a-fA-F]){12}\}{0,1})$";

            /// <summary>
            /// Will match any number of valid Guids in a larger text
            /// </summary>
            public static string GuidEx = @"(\{{0,1}([0-9a-fA-F]){8}-([0-9a-fA-F]){4}-([0-9a-fA-F]){4}-([0-9a-fA-F]){4}-([0-9a-fA-F]){12}\}{0,1})";

            /// <summary>
            /// Will match a mostly valid instance name.
            /// </summary>
            public static string InstanceName = @"^[\p{L}&_#][\p{L}\d\$#_]{1,15}$";

            /// <summary>
            /// Will match any instance of a mostly valid instance name.
            /// </summary>
            public static string InstanceNameEx = @"[\p{L}&_#][\p{L}\d\$#_]{1,15}";

            /// <summary>
            /// Matches a word against the list of officially reserved keywords
            /// </summary>
            public static string SqlReservedKeyword = @"^ADD$|^ALL$|^ALTER$|^AND$|^ANY$|^AS$|^ASC$|^AUTHORIZATION$|^BACKUP$|^BEGIN$|^BETWEEN$|^BREAK$|^BROWSE$|^BULK$|^BY$|^CASCADE$|^CASE$|^CHECK$|^CHECKPOINT$|^CLOSE$|^CLUSTERED$|^COALESCE$|^COLLATE$|^COLUMN$|^COMMIT$|^COMPUTE$|^CONSTRAINT$|^CONTAINS$|^CONTAINSTABLE$|^CONTINUE$|^CONVERT$|^CREATE$|^CROSS$|^CURRENT$|^CURRENT_DATE$|^CURRENT_TIME$|^CURRENT_TIMESTAMP$|^CURRENT_USER$|^CURSOR$|^DATABASE$|^DBCC$|^DEALLOCATE$|^DECLARE$|^DEFAULT$|^DELETE$|^DENY$|^DESC$|^DISK$|^DISTINCT$|^DISTRIBUTED$|^DOUBLE$|^DROP$|^DUMP$|^ELSE$|^END$|^ERRLVL$|^ESCAPE$|^EXCEPT$|^EXEC$|^EXECUTE$|^EXISTS$|^EXIT$|^EXTERNAL$|^FETCH$|^FILE$|^FILLFACTOR$|^FOR$|^FOREIGN$|^FREETEXT$|^FREETEXTTABLE$|^FROM$|^FULL$|^FUNCTION$|^GOTO$|^GRANT$|^GROUP$|^HAVING$|^HOLDLOCK$|^IDENTITY$|^IDENTITY_INSERT$|^IDENTITYCOL$|^IF$|^IN$|^INDEX$|^INNER$|^INSERT$|^INTERSECT$|^INTO$|^IS$|^JOIN$|^KEY$|^KILL$|^LEFT$|^LIKE$|^LINENO$|^LOAD$|^MERGE$|^NATIONAL$|^NOCHECK$|^NONCLUSTERED$|^NOT$|^NULL$|^NULLIF$|^OF$|^OFF$|^OFFSETS$|^ON$|^OPEN$|^OPENDATASOURCE$|^OPENQUERY$|^OPENROWSET$|^OPENXML$|^OPTION$|^OR$|^ORDER$|^OUTER$|^OVER$|^PERCENT$|^PIVOT$|^PLAN$|^PRECISION$|^PRIMARY$|^PRINT$|^PROC$|^PROCEDURE$|^PUBLIC$|^RAISERROR$|^READ$|^READTEXT$|^RECONFIGURE$|^REFERENCES$|^REPLICATION$|^RESTORE$|^RESTRICT$|^RETURN$|^REVERT$|^REVOKE$|^RIGHT$|^ROLLBACK$|^ROWCOUNT$|^ROWGUIDCOL$|^RULE$|^SAVE$|^SCHEMA$|^SECURITYAUDIT$|^SELECT$|^SEMANTICKEYPHRASETABLE$|^SEMANTICSIMILARITYDETAILSTABLE$|^SEMANTICSIMILARITYTABLE$|^SESSION_USER$|^SET$|^SETUSER$|^SHUTDOWN$|^SOME$|^STATISTICS$|^SYSTEM_USER$|^TABLE$|^TABLESAMPLE$|^TEXTSIZE$|^THEN$|^TO$|^TOP$|^TRAN$|^TRANSACTION$|^TRIGGER$|^TRUNCATE$|^TRY_CONVERT$|^TSEQUAL$|^UNION$|^UNIQUE$|^UNPIVOT$|^UPDATE$|^UPDATETEXT$|^USE$|^USER$|^VALUES$|^VARYING$|^VIEW$|^WAITFOR$|^WHEN$|^WHERE$|^WHILE$|^WITH$|^WITHIN GROUP$|^WRITETEXT$";

            /// <summary>
            /// Will match any reserved keyword in a larger text
            /// </summary>
            public static string SqlReservedKeywordEx = @"ADD|ALL|ALTER|AND|ANY|AS|ASC|AUTHORIZATION|BACKUP|BEGIN|BETWEEN|BREAK|BROWSE|BULK|BY|CASCADE|CASE|CHECK|CHECKPOINT|CLOSE|CLUSTERED|COALESCE|COLLATE|COLUMN|COMMIT|COMPUTE|CONSTRAINT|CONTAINS|CONTAINSTABLE|CONTINUE|CONVERT|CREATE|CROSS|CURRENT|CURRENT_DATE|CURRENT_TIME|CURRENT_TIMESTAMP|CURRENT_USER|CURSOR|DATABASE|DBCC|DEALLOCATE|DECLARE|DEFAULT|DELETE|DENY|DESC|DISK|DISTINCT|DISTRIBUTED|DOUBLE|DROP|DUMP|ELSE|END|ERRLVL|ESCAPE|EXCEPT|EXEC|EXECUTE|EXISTS|EXIT|EXTERNAL|FETCH|FILE|FILLFACTOR|FOR|FOREIGN|FREETEXT|FREETEXTTABLE|FROM|FULL|FUNCTION|GOTO|GRANT|GROUP|HAVING|HOLDLOCK|IDENTITY|IDENTITY_INSERT|IDENTITYCOL|IF|IN|INDEX|INNER|INSERT|INTERSECT|INTO|IS|JOIN|KEY|KILL|LEFT|LIKE|LINENO|LOAD|MERGE|NATIONAL|NOCHECK|NONCLUSTERED|NOT|NULL|NULLIF|OF|OFF|OFFSETS|ON|OPEN|OPENDATASOURCE|OPENQUERY|OPENROWSET|OPENXML|OPTION|OR|ORDER|OUTER|OVER|PERCENT|PIVOT|PLAN|PRECISION|PRIMARY|PRINT|PROC|PROCEDURE|PUBLIC|RAISERROR|READ|READTEXT|RECONFIGURE|REFERENCES|REPLICATION|RESTORE|RESTRICT|RETURN|REVERT|REVOKE|RIGHT|ROLLBACK|ROWCOUNT|ROWGUIDCOL|RULE|SAVE|SCHEMA|SECURITYAUDIT|SELECT|SEMANTICKEYPHRASETABLE|SEMANTICSIMILARITYDETAILSTABLE|SEMANTICSIMILARITYTABLE|SESSION_USER|SET|SETUSER|SHUTDOWN|SOME|STATISTICS|SYSTEM_USER|TABLE|TABLESAMPLE|TEXTSIZE|THEN|TO|TOP|TRAN|TRANSACTION|TRIGGER|TRUNCATE|TRY_CONVERT|TSEQUAL|UNION|UNIQUE|UNPIVOT|UPDATE|UPDATETEXT|USE|USER|VALUES|VARYING|VIEW|WAITFOR|WHEN|WHERE|WHILE|WITH|WITHIN GROUP|WRITETEXT";

            /// <summary>
            /// Matches a word against the list of officially reserved keywords for odbc
            /// </summary>
            public static string SqlReservedKeywordOdbc = @"^ABSOLUTE$|^ACTION$|^ADA$|^ADD$|^ALL$|^ALLOCATE$|^ALTER$|^AND$|^ANY$|^ARE$|^AS$|^ASC$|^ASSERTION$|^AT$|^AUTHORIZATION$|^AVG$|^BEGIN$|^BETWEEN$|^BIT$|^BIT_LENGTH$|^BOTH$|^BY$|^CASCADE$|^CASCADED$|^CASE$|^CAST$|^CATALOG$|^CHAR$|^CHAR_LENGTH$|^CHARACTER$|^CHARACTER_LENGTH$|^CHECK$|^CLOSE$|^COALESCE$|^COLLATE$|^COLLATION$|^COLUMN$|^COMMIT$|^CONNECT$|^CONNECTION$|^CONSTRAINT$|^CONSTRAINTS$|^CONTINUE$|^CONVERT$|^CORRESPONDING$|^COUNT$|^CREATE$|^CROSS$|^CURRENT$|^CURRENT_DATE$|^CURRENT_TIME$|^CURRENT_TIMESTAMP$|^CURRENT_USER$|^CURSOR$|^DATE$|^DAY$|^DEALLOCATE$|^DEC$|^DECIMAL$|^DECLARE$|^DEFAULT$|^DEFERRABLE$|^DEFERRED$|^DELETE$|^DESC$|^DESCRIBE$|^DESCRIPTOR$|^DIAGNOSTICS$|^DISCONNECT$|^DISTINCT$|^DOMAIN$|^DOUBLE$|^DROP$|^ELSE$|^END$|^END-EXEC$|^ESCAPE$|^EXCEPT$|^EXCEPTION$|^EXEC$|^EXECUTE$|^EXISTS$|^EXTERNAL$|^EXTRACT$|^FALSE$|^FETCH$|^FIRST$|^FLOAT$|^FOR$|^FOREIGN$|^FORTRAN$|^FOUND$|^FROM$|^FULL$|^GET$|^GLOBAL$|^GO$|^GOTO$|^GRANT$|^GROUP$|^HAVING$|^HOUR$|^IDENTITY$|^IMMEDIATE$|^IN$|^INCLUDE$|^INDEX$|^INDICATOR$|^INITIALLY$|^INNER$|^INPUT$|^INSENSITIVE$|^INSERT$|^INT$|^INTEGER$|^INTERSECT$|^INTERVAL$|^INTO$|^IS$|^ISOLATION$|^JOIN$|^KEY$|^LANGUAGE$|^LAST$|^LEADING$|^LEFT$|^LEVEL$|^LIKE$|^LOCAL$|^LOWER$|^MATCH$|^MAX$|^MIN$|^MINUTE$|^MODULE$|^MONTH$|^NAMES$|^NATIONAL$|^NATURAL$|^NCHAR$|^NEXT$|^NO$|^NONE$|^NOT$|^NULL$|^NULLIF$|^NUMERIC$|^OCTET_LENGTH$|^OF$|^ON$|^ONLY$|^OPEN$|^OPTION$|^OR$|^ORDER$|^OUTER$|^OUTPUT$|^OVERLAPS$|^PAD$|^PARTIAL$|^PASCAL$|^POSITION$|^PRECISION$|^PREPARE$|^PRESERVE$|^PRIMARY$|^PRIOR$|^PRIVILEGES$|^PROCEDURE$|^PUBLIC$|^READ$|^REAL$|^REFERENCES$|^RELATIVE$|^RESTRICT$|^REVOKE$|^RIGHT$|^ROLLBACK$|^ROWS$|^SCHEMA$|^SCROLL$|^SECOND$|^SECTION$|^SELECT$|^SESSION$|^SESSION_USER$|^SET$|^SIZE$|^SMALLINT$|^SOME$|^SPACE$|^SQL$|^SQLCA$|^SQLCODE$|^SQLERROR$|^SQLSTATE$|^SQLWARNING$|^SUBSTRING$|^SUM$|^SYSTEM_USER$|^TABLE$|^TEMPORARY$|^THEN$|^TIME$|^TIMESTAMP$|^TIMEZONE_HOUR$|^TIMEZONE_MINUTE$|^TO$|^TRAILING$|^TRANSACTION$|^TRANSLATE$|^TRANSLATION$|^TRIM$|^TRUE$|^UNION$|^UNIQUE$|^UNKNOWN$|^UPDATE$|^UPPER$|^USAGE$|^USER$|^USING$|^VALUE$|^VALUES$|^VARCHAR$|^VARYING$|^VIEW$|^WHEN$|^WHENEVER$|^WHERE$|^WITH$|^WORK$|^WRITE$|^YEAR$|^ZONE$";

            /// <summary>
            /// Will match any reserved odbc-keyword in a larger text
            /// </summary>
            public static string SqlReservedKeywordOdbcEx = @"ABSOLUTE|ACTION|ADA|ADD|ALL|ALLOCATE|ALTER|AND|ANY|ARE|AS|ASC|ASSERTION|AT|AUTHORIZATION|AVG|BEGIN|BETWEEN|BIT|BIT_LENGTH|BOTH|BY|CASCADE|CASCADED|CASE|CAST|CATALOG|CHAR|CHAR_LENGTH|CHARACTER|CHARACTER_LENGTH|CHECK|CLOSE|COALESCE|COLLATE|COLLATION|COLUMN|COMMIT|CONNECT|CONNECTION|CONSTRAINT|CONSTRAINTS|CONTINUE|CONVERT|CORRESPONDING|COUNT|CREATE|CROSS|CURRENT|CURRENT_DATE|CURRENT_TIME|CURRENT_TIMESTAMP|CURRENT_USER|CURSOR|DATE|DAY|DEALLOCATE|DEC|DECIMAL|DECLARE|DEFAULT|DEFERRABLE|DEFERRED|DELETE|DESC|DESCRIBE|DESCRIPTOR|DIAGNOSTICS|DISCONNECT|DISTINCT|DOMAIN|DOUBLE|DROP|ELSE|END|END-EXEC|ESCAPE|EXCEPT|EXCEPTION|EXEC|EXECUTE|EXISTS|EXTERNAL|EXTRACT|FALSE|FETCH|FIRST|FLOAT|FOR|FOREIGN|FORTRAN|FOUND|FROM|FULL|GET|GLOBAL|GO|GOTO|GRANT|GROUP|HAVING|HOUR|IDENTITY|IMMEDIATE|IN|INCLUDE|INDEX|INDICATOR|INITIALLY|INNER|INPUT|INSENSITIVE|INSERT|INT|INTEGER|INTERSECT|INTERVAL|INTO|IS|ISOLATION|JOIN|KEY|LANGUAGE|LAST|LEADING|LEFT|LEVEL|LIKE|LOCAL|LOWER|MATCH|MAX|MIN|MINUTE|MODULE|MONTH|NAMES|NATIONAL|NATURAL|NCHAR|NEXT|NO|NONE|NOT|NULL|NULLIF|NUMERIC|OCTET_LENGTH|OF|ON|ONLY|OPEN|OPTION|OR|ORDER|OUTER|OUTPUT|OVERLAPS|PAD|PARTIAL|PASCAL|POSITION|PRECISION|PREPARE|PRESERVE|PRIMARY|PRIOR|PRIVILEGES|PROCEDURE|PUBLIC|READ|REAL|REFERENCES|RELATIVE|RESTRICT|REVOKE|RIGHT|ROLLBACK|ROWS|SCHEMA|SCROLL|SECOND|SECTION|SELECT|SESSION|SESSION_USER|SET|SIZE|SMALLINT|SOME|SPACE|SQL|SQLCA|SQLCODE|SQLERROR|SQLSTATE|SQLWARNING|SUBSTRING|SUM|SYSTEM_USER|TABLE|TEMPORARY|THEN|TIME|TIMESTAMP|TIMEZONE_HOUR|TIMEZONE_MINUTE|TO|TRAILING|TRANSACTION|TRANSLATE|TRANSLATION|TRIM|TRUE|UNION|UNIQUE|UNKNOWN|UPDATE|UPPER|USAGE|USER|USING|VALUE|VALUES|VARCHAR|VARYING|VIEW|WHEN|WHENEVER|WHERE|WITH|WORK|WRITE|YEAR|ZONE";

            /// <summary>
            /// Matches a word against the list of keywords that are likely to become reserved in the future
            /// </summary>
            public static string SqlReservedKeywordFuture = @"^ABSOLUTE$|^ACTION$|^ADMIN$|^AFTER$|^AGGREGATE$|^ALIAS$|^ALLOCATE$|^ARE$|^ARRAY$|^ASENSITIVE$|^ASSERTION$|^ASYMMETRIC$|^AT$|^ATOMIC$|^BEFORE$|^BINARY$|^BIT$|^BLOB$|^BOOLEAN$|^BOTH$|^BREADTH$|^CALL$|^CALLED$|^CARDINALITY$|^CASCADED$|^CAST$|^CATALOG$|^CHAR$|^CHARACTER$|^CLASS$|^CLOB$|^COLLATION$|^COLLECT$|^COMPLETION$|^CONDITION$|^CONNECT$|^CONNECTION$|^CONSTRAINTS$|^CONSTRUCTOR$|^CORR$|^CORRESPONDING$|^COVAR_POP$|^COVAR_SAMP$|^CUBE$|^CUME_DIST$|^CURRENT_CATALOG$|^CURRENT_DEFAULT_TRANSFORM_GROUP$|^CURRENT_PATH$|^CURRENT_ROLE$|^CURRENT_SCHEMA$|^CURRENT_TRANSFORM_GROUP_FOR_TYPE$|^CYCLE$|^DATA$|^DATE$|^DAY$|^DEC$|^DECIMAL$|^DEFERRABLE$|^DEFERRED$|^DEPTH$|^DEREF$|^DESCRIBE$|^DESCRIPTOR$|^DESTROY$|^DESTRUCTOR$|^DETERMINISTIC$|^DIAGNOSTICS$|^DICTIONARY$|^DISCONNECT$|^DOMAIN$|^DYNAMIC$|^EACH$|^ELEMENT$|^END-EXEC$|^EQUALS$|^EVERY$|^EXCEPTION$|^FALSE$|^FILTER$|^FIRST$|^FLOAT$|^FOUND$|^FREE$|^FULLTEXTTABLE$|^FUSION$|^GENERAL$|^GET$|^GLOBAL$|^GO$|^GROUPING$|^HOLD$|^HOST$|^HOUR$|^IGNORE$|^IMMEDIATE$|^INDICATOR$|^INITIALIZE$|^INITIALLY$|^INOUT$|^INPUT$|^INT$|^INTEGER$|^INTERSECTION$|^INTERVAL$|^ISOLATION$|^ITERATE$|^LANGUAGE$|^LARGE$|^LAST$|^LATERAL$|^LEADING$|^LESS$|^LEVEL$|^LIKE_REGEX$|^LIMIT$|^LN$|^LOCAL$|^LOCALTIME$|^LOCALTIMESTAMP$|^LOCATOR$|^MAP$|^MATCH$|^MEMBER$|^METHOD$|^MINUTE$|^MOD$|^MODIFIES$|^MODIFY$|^MODULE$|^MONTH$|^MULTISET$|^NAMES$|^NATURAL$|^NCHAR$|^NCLOB$|^NEW$|^NEXT$|^NO$|^NONE$|^NORMALIZE$|^NUMERIC$|^OBJECT$|^OCCURRENCES_REGEX$|^OLD$|^ONLY$|^OPERATION$|^ORDINALITY$|^OUT$|^OUTPUT$|^OVERLAY$|^PAD$|^PARAMETER$|^PARAMETERS$|^PARTIAL$|^PARTITION$|^PATH$|^PERCENT_RANK$|^PERCENTILE_CONT$|^PERCENTILE_DISC$|^POSITION_REGEX$|^POSTFIX$|^PREFIX$|^PREORDER$|^PREPARE$|^PRESERVE$|^PRIOR$|^PRIVILEGES$|^RANGE$|^READS$|^REAL$|^RECURSIVE$|^REF$|^REFERENCING$|^REGR_AVGX$|^REGR_AVGY$|^REGR_COUNT$|^REGR_INTERCEPT$|^REGR_R2$|^REGR_SLOPE$|^REGR_SXX$|^REGR_SXY$|^REGR_SYY$|^RELATIVE$|^RELEASE$|^RESULT$|^RETURNS$|^ROLE$|^ROLLUP$|^ROUTINE$|^ROW$|^ROWS$|^SAVEPOINT$|^SCOPE$|^SCROLL$|^SEARCH$|^SECOND$|^SECTION$|^SENSITIVE$|^SEQUENCE$|^SESSION$|^SETS$|^SIMILAR$|^SIZE$|^SMALLINT$|^SPACE$|^SPECIFIC$|^SPECIFICTYPE$|^SQL$|^SQLEXCEPTION$|^SQLSTATE$|^SQLWARNING$|^START$|^STATE$|^STATEMENT$|^STATIC$|^STDDEV_POP$|^STDDEV_SAMP$|^STRUCTURE$|^SUBMULTISET$|^SUBSTRING_REGEX$|^SYMMETRIC$|^SYSTEM$|^TEMPORARY$|^TERMINATE$|^THAN$|^TIME$|^TIMESTAMP$|^TIMEZONE_HOUR$|^TIMEZONE_MINUTE$|^TRAILING$|^TRANSLATE_REGEX$|^TRANSLATION$|^TREAT$|^TRUE$|^UESCAPE$|^UNDER$|^UNKNOWN$|^UNNEST$|^USAGE$|^USING$|^VALUE$|^VAR_POP$|^VAR_SAMP$|^VARCHAR$|^VARIABLE$|^WHENEVER$|^WIDTH_BUCKET$|^WINDOW$|^WITHIN$|^WITHOUT$|^WORK$|^WRITE$|^XMLAGG$|^XMLATTRIBUTES$|^XMLBINARY$|^XMLCAST$|^XMLCOMMENT$|^XMLCONCAT$|^XMLDOCUMENT$|^XMLELEMENT$|^XMLEXISTS$|^XMLFOREST$|^XMLITERATE$|^XMLNAMESPACES$|^XMLPARSE$|^XMLPI$|^XMLQUERY$|^XMLSERIALIZE$|^XMLTABLE$|^XMLTEXT$|^XMLVALIDATE$|^YEAR$|^ZONE$";

            /// <summary>
            /// Will match against the list of keywords that are likely to become reserved in the future and are used in a larger text
            /// </summary>
            public static string SqlReservedKeywordFutureEx = @"ABSOLUTE|ACTION|ADMIN|AFTER|AGGREGATE|ALIAS|ALLOCATE|ARE|ARRAY|ASENSITIVE|ASSERTION|ASYMMETRIC|AT|ATOMIC|BEFORE|BINARY|BIT|BLOB|BOOLEAN|BOTH|BREADTH|CALL|CALLED|CARDINALITY|CASCADED|CAST|CATALOG|CHAR|CHARACTER|CLASS|CLOB|COLLATION|COLLECT|COMPLETION|CONDITION|CONNECT|CONNECTION|CONSTRAINTS|CONSTRUCTOR|CORR|CORRESPONDING|COVAR_POP|COVAR_SAMP|CUBE|CUME_DIST|CURRENT_CATALOG|CURRENT_DEFAULT_TRANSFORM_GROUP|CURRENT_PATH|CURRENT_ROLE|CURRENT_SCHEMA|CURRENT_TRANSFORM_GROUP_FOR_TYPE|CYCLE|DATA|DATE|DAY|DEC|DECIMAL|DEFERRABLE|DEFERRED|DEPTH|DEREF|DESCRIBE|DESCRIPTOR|DESTROY|DESTRUCTOR|DETERMINISTIC|DIAGNOSTICS|DICTIONARY|DISCONNECT|DOMAIN|DYNAMIC|EACH|ELEMENT|END-EXEC|EQUALS|EVERY|EXCEPTION|FALSE|FILTER|FIRST|FLOAT|FOUND|FREE|FULLTEXTTABLE|FUSION|GENERAL|GET|GLOBAL|GO|GROUPING|HOLD|HOST|HOUR|IGNORE|IMMEDIATE|INDICATOR|INITIALIZE|INITIALLY|INOUT|INPUT|INT|INTEGER|INTERSECTION|INTERVAL|ISOLATION|ITERATE|LANGUAGE|LARGE|LAST|LATERAL|LEADING|LESS|LEVEL|LIKE_REGEX|LIMIT|LN|LOCAL|LOCALTIME|LOCALTIMESTAMP|LOCATOR|MAP|MATCH|MEMBER|METHOD|MINUTE|MOD|MODIFIES|MODIFY|MODULE|MONTH|MULTISET|NAMES|NATURAL|NCHAR|NCLOB|NEW|NEXT|NO|NONE|NORMALIZE|NUMERIC|OBJECT|OCCURRENCES_REGEX|OLD|ONLY|OPERATION|ORDINALITY|OUT|OUTPUT|OVERLAY|PAD|PARAMETER|PARAMETERS|PARTIAL|PARTITION|PATH|PERCENT_RANK|PERCENTILE_CONT|PERCENTILE_DISC|POSITION_REGEX|POSTFIX|PREFIX|PREORDER|PREPARE|PRESERVE|PRIOR|PRIVILEGES|RANGE|READS|REAL|RECURSIVE|REF|REFERENCING|REGR_AVGX|REGR_AVGY|REGR_COUNT|REGR_INTERCEPT|REGR_R2|REGR_SLOPE|REGR_SXX|REGR_SXY|REGR_SYY|RELATIVE|RELEASE|RESULT|RETURNS|ROLE|ROLLUP|ROUTINE|ROW|ROWS|SAVEPOINT|SCOPE|SCROLL|SEARCH|SECOND|SECTION|SENSITIVE|SEQUENCE|SESSION|SETS|SIMILAR|SIZE|SMALLINT|SPACE|SPECIFIC|SPECIFICTYPE|SQL|SQLEXCEPTION|SQLSTATE|SQLWARNING|START|STATE|STATEMENT|STATIC|STDDEV_POP|STDDEV_SAMP|STRUCTURE|SUBMULTISET|SUBSTRING_REGEX|SYMMETRIC|SYSTEM|TEMPORARY|TERMINATE|THAN|TIME|TIMESTAMP|TIMEZONE_HOUR|TIMEZONE_MINUTE|TRAILING|TRANSLATE_REGEX|TRANSLATION|TREAT|TRUE|UESCAPE|UNDER|UNKNOWN|UNNEST|USAGE|USING|VALUE|VAR_POP|VAR_SAMP|VARCHAR|VARIABLE|WHENEVER|WIDTH_BUCKET|WINDOW|WITHIN|WITHOUT|WORK|WRITE|XMLAGG|XMLATTRIBUTES|XMLBINARY|XMLCAST|XMLCOMMENT|XMLCONCAT|XMLDOCUMENT|XMLELEMENT|XMLEXISTS|XMLFOREST|XMLITERATE|XMLNAMESPACES|XMLPARSE|XMLPI|XMLQUERY|XMLSERIALIZE|XMLTABLE|XMLTEXT|XMLVALIDATE|YEAR|ZONE";
        }

        /// <summary>
        /// Class that reports File size.
        /// </summary>
        [Serializable]
        public class Size : IComparable<Size>, IComparable
        {
            /// <summary>
            /// Number of bytes contained in whatever object uses this object as a property
            /// </summary>
            public long Byte
            {
                get
                {
                    return _Byte;
                }
                set
                {
                    _Byte = value;
                }
            }
            private long _Byte = -1;

            /// <summary>
            /// Kilobyte representation of the bytes
            /// </summary>
            public double Kilobyte
            {
                get
                {
                    return ((double)_Byte / (double)1024);
                }
                set
                {

                }
            }

            /// <summary>
            /// Megabyte representation of the bytes
            /// </summary>
            public double Megabyte
            {
                get
                {
                    return ((double)_Byte / (double)1048576);
                }
                set
                {

                }
            }

            /// <summary>
            /// Gigabyte representation of the bytes
            /// </summary>
            public double Gigabyte
            {
                get
                {
                    return ((double)_Byte / (double)1073741824);
                }
                set
                {

                }
            }

            /// <summary>
            /// Terabyte representation of the bytes
            /// </summary>
            public double Terabyte
            {
                get
                {
                    return ((double)_Byte / (double)1099511627776);
                }
                set
                {

                }
            }

            /// <summary>
            /// Number if digits behind the dot.
            /// </summary>
            public int Digits
            {
                get
                {
                    return _Digits;
                }
                set
                {
                    if (value < 0) { _Digits = 0; }
                    else { _Digits = value; }
                }
            }
            private int _Digits = 2;

            /// <summary>
            /// Shows the default string representation of size
            /// </summary>
            /// <returns></returns>
            public override string ToString()
            {
                string format = "{0:N" + _Digits + "}";

                if (Terabyte > 1)
                {
                    return (String.Format(format, Terabyte) + " TB");
                }
                else if (Gigabyte > 1)
                {
                    return (String.Format(format, Gigabyte) + " GB");
                }
                else if (Megabyte > 1)
                {
                    return (String.Format(format, Megabyte) + " MB");
                }
                else if (Kilobyte > 1)
                {
                    return (String.Format(format, Kilobyte) + " KB");
                }
                else if (Byte > -1)
                {
                    return (String.Format(format, Byte) + " B");
                }
                else if (Byte == -1)
                    return "Unlimited";
                else { return ""; }
            }

            /// <summary>
            /// Simple equality test
            /// </summary>
            /// <param name="obj">The object to test it against</param>
            /// <returns>True if equal, false elsewise</returns>
            public override bool Equals(object obj)
            {
                return ((obj != null) && (obj is Size) && (this.Byte == ((Size)obj).Byte));
            }

            /// <summary>
            /// Meaningless, but required
            /// </summary>
            /// <returns>Some meaningless output</returns>
            public override int GetHashCode()
            {
                return this.Byte.GetHashCode();
            }

            /// <summary>
            /// Creates an empty size.
            /// </summary>
            public Size()
            {

            }

            /// <summary>
            /// Creates a size with some content
            /// </summary>
            /// <param name="Byte">The length in bytes to set the size to</param>
            public Size(long Byte)
            {
                this.Byte = Byte;
            }

            /// <summary>
            /// Some more interface implementation. Used to sort the object
            /// </summary>
            /// <param name="obj">The object to compare to</param>
            /// <returns>Something</returns>
            public int CompareTo(Size obj)
            {
                if (this.Byte == obj.Byte) { return 0; }
                if (this.Byte < obj.Byte) { return -1; }

                return 1;
            }

            /// <summary>
            /// Some more interface implementation. Used to sort the object
            /// </summary>
            /// <param name="obj">The object to compare to</param>
            /// <returns>Something</returns>
            public int CompareTo(Object obj)
            {
                try
                {
                    if (this.Byte == ((Size)obj).Byte) { return 0; }
                    if (this.Byte < ((Size)obj).Byte) { return -1; }

                    return 1;
                }
                catch { return 0; }
            }

            #region Operators
            /// <summary>
            /// Adds two sizes
            /// </summary>
            /// <param name="a">The first size to add</param>
            /// <param name="b">The second size to add</param>
            /// <returns>The sum of both sizes</returns>
            public static Size operator +(Size a, Size b)
            {
                return new Size(a.Byte + b.Byte);
            }

            /// <summary>
            /// Substracts two sizes
            /// </summary>
            /// <param name="a">The first size to substract</param>
            /// <param name="b">The second size to substract</param>
            /// <returns>The difference between both sizes</returns>
            public static Size operator -(Size a, Size b)
            {
                return new Size(a.Byte - b.Byte);
            }

            /// <summary>
            /// Implicitly converts int to size
            /// </summary>
            /// <param name="a">The number to convert</param>
            public static implicit operator Size(int a)
            {
                return new Size(a);
            }

            /// <summary>
            /// Implicitly converts size to int
            /// </summary>
            /// <param name="a">The size to convert</param>
            public static implicit operator Int32(Size a)
            {
                return (Int32)a._Byte;
            }

            /// <summary>
            /// Implicitly converts long to size
            /// </summary>
            /// <param name="a">The number to convert</param>
            public static implicit operator Size(long a)
            {
                return new Size(a);
            }

            /// <summary>
            /// Implicitly converts size to long
            /// </summary>
            /// <param name="a">The size to convert</param>
            public static implicit operator Int64(Size a)
            {
                return a._Byte;
            }

            /// <summary>
            /// Implicitly converts string to size
            /// </summary>
            /// <param name="a">The string to convert</param>
            public static implicit operator Size(String a)
            {
                return new Size(Int64.Parse(a));
            }

            /// <summary>
            /// Implicitly converts double to size
            /// </summary>
            /// <param name="a">The number to convert</param>
            public static implicit operator Size(double a)
            {
                return new Size((long)a);
            }

            /// <summary>
            /// Implicitly converts size to double
            /// </summary>
            /// <param name="a">The size to convert</param>
            public static implicit operator double(Size a)
            {
                return a._Byte;
            }
            #endregion Operators
        }

        /// <summary>
        /// Provides static resources to utility-namespaced stuff
        /// </summary>
        public static class UtilityHost
        {
            /// <summary>
            /// Restores all DateTime objects to their default display behavior
            /// </summary>
            public static bool DisableCustomDateTime = false;

            /// <summary>
            /// Restores all timespan objects to their default display behavior.
            /// </summary>
            public static bool DisableCustomTimeSpan = false;

            /// <summary>
            /// Formating string for date-style datetime objects.
            /// </summary>
            public static string FormatDate = "dd MMM yyyy";

            /// <summary>
            /// Formating string for datetime-style datetime objects
            /// </summary>
            public static string FormatDateTime = "yyyy-MM-dd HH:mm:ss.fff";

            /// <summary>
            /// Formating string for time-style datetime objects
            /// </summary>
            public static string FormatTime = "HH:mm:ss";

            /// <summary>
            /// The Version of the dbatools Library. Used to compare with import script to determine out-of-date libraries
            /// </summary>
            public readonly static Version LibraryVersion = new Version(1, 0, 1, 11);
        }

        /// <summary>
        /// Provides helper methods that aid in validating stuff.
        /// </summary>
        public static class Validation
        {
            /// <summary>
            /// Tests whether a given string is the local host.
            /// Does NOT use DNS resolution, DNS aliases will NOT be recognized!
            /// </summary>
            /// <param name="Name">The name to test for being local host</param>
            /// <returns>Whether the name is localhost</returns>
            public static bool IsLocalhost(string Name)
            {
                #region Handle IP Addresses
                try
                {
                    IPAddress tempAddress;
                    IPAddress.TryParse(Name, out tempAddress);
                    if (IPAddress.IsLoopback(tempAddress))
                        return true;

                    foreach (NetworkInterface netInterface in NetworkInterface.GetAllNetworkInterfaces())
                    {
                        IPInterfaceProperties ipProps = netInterface.GetIPProperties();
                        foreach (UnicastIPAddressInformation addr in ipProps.UnicastAddresses)
                        {
                            if (tempAddress.ToString() == addr.Address.ToString())
                                return true;
                        }
                    }
                }
                catch { }
                #endregion Handle IP Addresses

                #region Handle Names
                try
                {
                    if (Name == ".")
                        return true;
                    if (Name.ToLower() == "localhost")
                        return true;
                    if (Name.ToLower() == Environment.MachineName.ToLower())
                        return true;
                    if (Name.ToLower() == (Environment.MachineName + "." + Environment.GetEnvironmentVariable("USERDNSDOMAIN")).ToLower())
                        return true;
                }
                catch { }
                #endregion Handle Names
                return false;
            }

            /// <summary>
            /// Tests whether a given string is a recommended instance name. Recommended names musst be legal, nbot on the ODBC list and not on the list of words likely to become reserved keywords in the future.
            /// </summary>
            /// <param name="InstanceName">The name to test. MAY contain server name, but will NOT test the server.</param>
            /// <returns>Whether the name is recommended</returns>
            public static bool IsRecommendedInstanceName(string InstanceName)
            {
                string temp;
                if (InstanceName.Split('\\').Length == 1) { temp = InstanceName; }
                else if (InstanceName.Split('\\').Length == 2) { temp = InstanceName.Split('\\')[1]; }
                else { return false; }

                if (Regex.IsMatch(temp, RegexHelper.SqlReservedKeyword, RegexOptions.IgnoreCase)) { return false; }
                if (Regex.IsMatch(temp, RegexHelper.SqlReservedKeywordFuture, RegexOptions.IgnoreCase)) { return false; }
                if (Regex.IsMatch(temp, RegexHelper.SqlReservedKeywordOdbc, RegexOptions.IgnoreCase)) { return false; }

                if (temp.ToLower() == "default") { return false; }
                if (temp.ToLower() == "mssqlserver") { return false; }

                if (!Regex.IsMatch(temp, RegexHelper.InstanceName, RegexOptions.IgnoreCase)) { return false; }

                return true;
            }

            /// <summary>
            /// Tests whether a given string is a valid target for targeting as a computer. Will first convert from idn name.
            /// </summary>
            public static bool IsValidComputerTarget(string ComputerName)
            {
                try
                {
                    System.Globalization.IdnMapping mapping = new System.Globalization.IdnMapping();
                    string temp = mapping.GetAscii(ComputerName);
                    return Regex.IsMatch(temp, RegexHelper.ComputerTarget);
                }
                catch { return false; }
            }

            /// <summary>
            /// Tests whether a given string is a valid instance name.
            /// </summary>
            /// <param name="InstanceName">The name to test. MAY contain server name, but will NOT test the server.</param>
            /// <returns>Whether the name is legal</returns>
            public static bool IsValidInstanceName(string InstanceName)
            {
                string temp;
                if (InstanceName.Split('\\').Length == 1) { temp = InstanceName; }
                else if (InstanceName.Split('\\').Length == 2) { temp = InstanceName.Split('\\')[1]; }
                else { return false; }

                if (Regex.IsMatch(temp, RegexHelper.SqlReservedKeyword, RegexOptions.IgnoreCase)) { return false; }

                if (temp.ToLower() == "default") { return false; }
                if (temp.ToLower() == "mssqlserver") { return false; }

                if (!Regex.IsMatch(temp, RegexHelper.InstanceName, RegexOptions.IgnoreCase)) { return false; }

                return true;
            }
        }
    }

    namespace Validation
    {
        /// <summary>
        /// The results of testing linked server connectivity as seen from the server that was linked to.
        /// </summary>
        [Serializable]
        public class LinkedServerResult
        {
            /// <summary>
            /// The name of the server running the tests
            /// </summary>
            public string ComputerName;

            /// <summary>
            /// The name of the instance running the tests
            /// </summary>
            public string InstanceName;

            /// <summary>
            /// The full name of the instance running the tests
            /// </summary>
            public string SqlInstance;

            /// <summary>
            /// The name of the linked server, the connectivity with whom was tested
            /// </summary>
            public string LinkedServerName;

            /// <summary>
            /// The name of the remote computer running the linked server.
            /// </summary>
            public string RemoteServer;

            /// <summary>
            /// The test result
            /// </summary>
            public bool Connectivity;

            /// <summary>
            /// Text interpretation of the result. Contains error messages if the test failed.
            /// </summary>
            public string Result;

            /// <summary>
            /// Creates an empty object
            /// </summary>
            public LinkedServerResult()
            {

            }

            /// <summary>
            /// Creates a test result with prefilled values
            /// </summary>
            /// <param name="ComputerName">The name of the server running the tests</param>
            /// <param name="InstanceName">The name of the instance running the tests</param>
            /// <param name="SqlInstance">The full name of the instance running the tests</param>
            /// <param name="LinkedServerName">The name of the linked server, the connectivity with whom was tested</param>
            /// <param name="RemoteServer">The name of the remote computer running the linked server.</param>
            /// <param name="Connectivity">The test result</param>
            /// <param name="Result">Text interpretation of the result. Contains error messages if the test failed.</param>
            public LinkedServerResult(string ComputerName, string InstanceName, string SqlInstance, string LinkedServerName, string RemoteServer, bool Connectivity, string Result)
            {
                this.ComputerName = ComputerName;
                this.InstanceName = InstanceName;
                this.SqlInstance = SqlInstance;
                this.LinkedServerName = LinkedServerName;
                this.RemoteServer = RemoteServer;
                this.Connectivity = Connectivity;
                this.Result = Result;
            }
        }
    }
}
'@
    #endregion Source Code
    
    #region Add Code
    try
    {
        $paramAddType = @{
            TypeDefinition = $source
            ErrorAction = 'Stop'
            ReferencedAssemblies = ([appdomain]::CurrentDomain.GetAssemblies() | Where-Object FullName -match "^Microsoft\.Management\.Infrastructure, |^System\.Numerics, " | Where-Object Location).Location
        }
        
        Add-Type @paramAddType
        
        #region PowerShell TypeData
        Update-TypeData -TypeName "SqlCollective.Dbatools.dbaSystem.DbatoolsException" -SerializationDepth 2 -ErrorAction Ignore
        Update-TypeData -TypeName "SqlCollective.Dbatools.dbaSystem.DbatoolsExceptionRecord" -SerializationDepth 2 -ErrorAction Ignore
        #endregion PowerShell TypeData
    }
    catch
    {
        #region Warning
        Write-Warning @'
Dear User,

in the name of the dbatools team I apologize for the inconvenience.
Generally, when something goes wrong we try to handle and interpret in an
understandable manner. Unfortunately, something went awry with importing
our main library, so all the systems making this possible would not be initialized
yet. We have taken great pains to avoid this issue but this notification indicates
we have failed.

Please, in order to help us prevent this from happening again, visit us at:
https://github.com/sqlcollaborative/dbatools/issues
and tell us about this failure. All information will be appreciated, but 
especially valuable are:
- Exports of the exception: $Error | Export-Clixml error.xml -Depth 4
- Screenshots
- Environment information (Operating System, Hardware Stats, .NET Version,
  PowerShell Version and whatever else you may consider of potential impact.)

Again, I apologize for the inconvenience and hope we will be able to speedily
resolve the issue.

Best Regards,
Friedrich Weinmann
aka "The guy who made most of The Library that Failed to import"

'@
        throw
        #endregion Warning
    }
    #endregion Add Code
}

#region Version Warning
$LibraryVersion = New-Object System.Version(1, 0, 1, 11)
if ($LibraryVersion -ne ([Sqlcollective.Dbatools.Utility.UtilityHost]::LibraryVersion))
{
    Write-Warning @"
A version missmatch between the dbatools library loaded and the one expected by
this module. This usually happens when you update the dbatools module and use
Remove-Module / Import-Module in order to load the latest version without
starting a new PowerShell instance.

Please restart the console to apply the library update, or unexpected behavior will likely occur.
"@
}
#endregion Version Warning