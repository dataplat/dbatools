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
                        throw new UnauthorizedAccessException("Invalid credentials", e);
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
                    throw new UnauthorizedAccessException("Invalid credentials", e);
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

        /// <summary>
        /// Enumerate instances associated with the source CIM instance using WinRM.
        /// Mirrors Get-CimAssociatedInstance -ResultClassName on the CimRM rung.
        /// </summary>
        /// <param name="Credential">The credentials to use for the connection.</param>
        /// <param name="source">The source CIM instance to traverse from.</param>
        /// <param name="resultClassName">The result class name filter (equivalent to -ResultClassName).</param>
        /// <param name="Namespace">The namespace to look in (defaults to root\cimv2).</param>
        /// <returns>The associated CIM instances as an enumerable.</returns>
        public object GetCimRMAssociatedInstances(PSCredential Credential, CimInstance source, string resultClassName, string Namespace)
        {
            CimSession tempSession = GetCimWinRMSession(Credential);
            // Parameter order is (namespaceName, sourceInstance, associationClassName, resultClassName,
            // sourceRole, resultRole): the result class filter rides in the FOURTH slot. Passing it as
            // the association class returns zero instances (cross-model review 2026-07-07 finding 1,
            // proven live against MSCluster_Resource -> MSCluster_Disk on the lab WSFC).
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
                cimWinRMSession = null;
            }
            else
            {
                cimWinRMSession = tempSession;
            }
            return result;
        }

    }
}
