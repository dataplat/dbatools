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
                options.Timeout = _CimDComOptions.Timeout;
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
                        throw new UnauthorizedAccessException("Invalid credentials", e);
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


        /// <summary>
        /// Enumerate instances associated with the source CIM instance using DCOM.
        /// Mirrors Get-CimAssociatedInstance -ResultClassName on the CimDCOM rung.
        /// </summary>
        /// <param name="Credential">The credentials to use for the connection.</param>
        /// <param name="source">The source CIM instance to traverse from.</param>
        /// <param name="resultClassName">The result class name filter (equivalent to -ResultClassName).</param>
        /// <param name="Namespace">The namespace to look in (defaults to root\cimv2).</param>
        /// <returns>The associated CIM instances as an enumerable.</returns>
        public object GetCimDComAssociatedInstances(PSCredential Credential, CimInstance source, string resultClassName, string Namespace)
        {
            CimSession tempSession = GetCimDComSession(Credential);
            // Parameter order is (namespaceName, sourceInstance, associationClassName, resultClassName,
            // sourceRole, resultRole): the result class filter rides in the FOURTH slot. Passing it as
            // the association class returns zero instances (cross-model review 2026-07-07 finding 1).
            IEnumerable<CimInstance> result = tempSession.EnumerateAssociatedInstances(Namespace, source, null, resultClassName, null, null);

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
        /// Generates a CIM session to the target computer.
        /// For use with other commands that expect a CIM session.
        /// </summary>
        /// <param name="Credential">Credential to use (if present)</param>
        /// <returns>A CIM Session to the target computer represented by this connection.</returns>
        /// <exception cref="Exception">When no CIM Session is available.</exception>
        public CimSession GetCimSession(PSCredential Credential = null)
        {
            Exception tempError = null;
            if ((DisabledConnectionTypes & ManagementConnectionType.CimRM) != ManagementConnectionType.CimRM)
            {
                try { return GetCimWinRMSession(Credential); }
                catch (Exception e) { tempError = e; }
            }

            if ((DisabledConnectionTypes & ManagementConnectionType.CimDCOM) != ManagementConnectionType.CimDCOM)
            {
                try { return GetCimDComSession(Credential); }
                catch (Exception e) { tempError = e; }
            }

            if (tempError != null)
                throw tempError;
            throw new Exception("No supporting connection type is enabled!");
        }


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
