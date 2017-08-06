using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Net;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Parameter
{
    /// <summary>
    /// Parameter class that handles the various kinds of credential input
    /// </summary>
    public class DbaCredentialParameter
    {
        #region Fields of contract
        /// <summary>
        /// The credential object received
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public PSCredential Credential;
        #endregion Fields of contract

        #region Constructors
        /// <summary>
        /// Creates a credential parameter from a PSCredential object
        /// </summary>
        /// <param name="Credential">A PSCredential object</param>
        public DbaCredentialParameter(PSCredential Credential)
        {
            this.Credential = Credential;
        }

        /// <summary>
        /// Creates a credential parameter from a NetworkCredential object
        /// </summary>
        /// <param name="Credential">The credentials to use</param>
        public DbaCredentialParameter(NetworkCredential Credential)
        {
            this.Credential = new PSCredential(String.Format("{0}\\{1}", Credential.Domain, Credential.UserName).Trim('\\'), Credential.SecurePassword);
        }

        /// <summary>
        /// Creates a credential parameter from a string only. Will prompt the user for the rest of the input. Will provide an option to remember the credential under the name provided
        /// </summary>
        /// <param name="UserName">The username (and domain name as may be the case) to put a credential around</param>
        public DbaCredentialParameter(string UserName)
        {
            if (CredentialStore.ContainsKey(UserName.ToLower()))
            {
                Credential = CredentialStore[UserName.ToLower()];
            }
            else if (dbaSystem.SystemHost.UnattendedMode)
                throw new InvalidOperationException("Cannot prompt for credentials in unattended mode!");
            else
                Credential = PromptForCredential(UserName);
        }
        #endregion Constructors

        #region Conversion
        /// <summary>
        /// Implicitly converts from DbaCredentialParameter to PSCredential
        /// </summary>
        /// <param name="Input">The DbaCredentialParameter to convert</param>
        [ParameterContract(ParameterContractType.Operator, ParameterContractBehavior.Conversion)]
        public static implicit operator PSCredential(DbaCredentialParameter Input)
        {
            return Input.Credential;
        }

        /// <summary>
        /// Implicitly converts a PSCredential object to DbaCredenitalParameter
        /// </summary>
        /// <param name="Input">The PSCredential to convert</param>
        public static implicit operator DbaCredentialParameter(PSCredential Input)
        {
            return new DbaCredentialParameter(Input);
        }

        /// <summary>
        /// Implicitly converts from DbaCredentialParameter to NetworkCredential
        /// </summary>
        /// <param name="Input">The DbaCredentialParameter to convert</param>
        [ParameterContract(ParameterContractType.Operator, ParameterContractBehavior.Conversion)]
        public static implicit operator NetworkCredential(DbaCredentialParameter Input)
        {
            return Input.Credential.GetNetworkCredential();
        }

        /// <summary>
        /// Implicitly converts a NetworkCredential object to DbaCredenitalParameter
        /// </summary>
        /// <param name="Input">The NetworkCredential to convert</param>
        public static implicit operator DbaCredentialParameter(NetworkCredential Input)
        {
            return new DbaCredentialParameter(Input);
        }
        #endregion Conversion

        #region Utility
        /// <summary>
        /// Legacy wrapper. While there exists implicit conversion, this allows using the object as before, avoiding errors for unknown method.
        /// </summary>
        /// <returns>A network credential object with the same credentials as the original object</returns>
        [ParameterContract(ParameterContractType.Method, ParameterContractBehavior.Conversion)]
        public NetworkCredential GetNetworkCredential()
        {
            return Credential.GetNetworkCredential();
        }

        /// <summary>
        /// Prompts the user for a password to complete a credentials object
        /// </summary>
        /// <param name="Name">The name of the user. If specified, this will be added to the prompt.</param>
        /// <returns>The finished PSCredential object</returns>
        public static PSCredential PromptForCredential(string Name = "")
        {
            Utility.CredentialPrompt prompt = Utility.CredentialPrompt.GetCredential(Name);
            if (prompt.Cancelled)
                throw new ArgumentException("No credentials specified!");

            PSCredential cred = new PSCredential(prompt.Username, prompt.Password);
            if (prompt.Remember)
                CredentialStore[cred.UserName.ToLower()] = cred;

            return cred;
        }

        /// <summary>
        /// Cached credentials, if the user stors them under a name.
        /// </summary>
        public static Dictionary<string, PSCredential> CredentialStore = new Dictionary<string, PSCredential>();
        #endregion Utility
    }
}
