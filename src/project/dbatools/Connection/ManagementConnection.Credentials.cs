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
        /// Any registered credentials to use on the connection.
        /// </summary>
        public PSCredential Credentials;

        /// <summary>
        /// Whether the default windows credentials failed against the target.
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
                    throw new PSArgumentException("Windows authentication was used, but failed",
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
                                    "Specified credentials are invalid. Credential failover is enabled but there are no known working credentials.",
                                    "Credential");
                            }
                            throw new PSArgumentException("Specified credentials failed",
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
                        return;
                    }
                }
            }
        }

    }
}
