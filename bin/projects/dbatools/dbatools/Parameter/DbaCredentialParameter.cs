using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Net;
using System.Security;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Parameter
{
    /// <summary>
    /// Parameter class that handles the various kinds of credential input
    /// </summary>
    [System.ComponentModel.TypeConverter(typeof(TypeConversion.DbaCredentialParameterConverter))]
    public class DbaCredentialParameter : IConvertible
    {
        #region Fields of contract
        /// <summary>
        /// The credential object received
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public PSCredential Credential;

        /// <summary>
        /// The name of the credential object
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public string UserName
        {
            get { return Credential.UserName; }
        }

        /// <summary>
        /// The password of the credential object
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public SecureString Password
        {
            get { return Credential.Password; }
        }
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

        /// <summary>
        /// Creates a credential parameter from anything it nows how to handle
        /// </summary>
        /// <param name="Credential">The object to convert</param>
        public DbaCredentialParameter(object Credential)
        {
            if (Credential is NetworkCredential)
                this.Credential = (new DbaCredentialParameter((NetworkCredential)Credential)).Credential;
            else if (Credential is PSCredential)
                this.Credential = (PSCredential)Credential;

            else
                throw new PSArgumentException("Invalid input type");
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
        internal static Dictionary<string, PSCredential> CredentialStore = new Dictionary<string, PSCredential>();
        #endregion Utility

        #region Interface Implementation
        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public TypeCode GetTypeCode()
        {
            return TypeCode.Object;
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public bool ToBoolean(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public char ToChar(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public sbyte ToSByte(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public byte ToByte(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public short ToInt16(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public ushort ToUInt16(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public int ToInt32(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public uint ToUInt32(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public long ToInt64(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public ulong ToUInt64(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public Single ToSingle(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public double ToDouble(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public decimal ToDecimal(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public DateTime ToDateTime(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="Format"></param>
        /// <returns></returns>
        public string ToString(IFormatProvider Format)
        {
            throw new NotSupportedException();
        }

        /// <summary>
        /// Tries to convert the credential parameter to one of its supported types
        /// </summary>
        /// <param name="TargetType">The type to convert to</param>
        /// <param name="Format">Irrelevant</param>
        /// <returns></returns>
        public object ToType(Type TargetType, IFormatProvider Format)
        {
            if (TargetType.FullName == "System.Management.Automation.PSCredential")
                return Credential;
            if (TargetType.FullName == "System.Net.NetworkCredential")
                return GetNetworkCredential();

            throw new NotSupportedException(String.Format("Converting from {0} to {1} is not supported!", GetType().FullName, TargetType.FullName));
        }
        #endregion Interface Implementation
    }
}
