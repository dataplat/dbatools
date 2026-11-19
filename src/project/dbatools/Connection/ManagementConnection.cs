using System;
using System.Collections.Generic;
using System.Management.Automation;
using Microsoft.Management.Infrastructure;
using Microsoft.Management.Infrastructure.Options;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>
    /// Contains management connection information for a windows server
    /// </summary>
    [Serializable]
    public partial class ManagementConnection
    {
        /// <summary>
        /// The computer to connect to
        /// </summary>
        public string ComputerName { get; set; }


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

    }
}
