using System.Management.Automation;
using System.Security;

namespace Dataplat.Dbatools.Utility
{
    /// <summary>
    /// private/functions/ConvertFrom-SecurePass.ps1 parity (TB-016): the cross-platform
    /// SecureString-to-plaintext trick (PSCredential with a throwaway "fake" user name,
    /// then NetworkCredential.Password - works on Linux/Windows/OSX where the BSTR
    /// marshal route does not). Ten live public callers across the certificate, master
    /// key, linked-server and login families plus the retired Connect-DbaInstance
    /// (helper retained); the compiled connect path's ConnectionService.ConvertFromSecurePass
    /// DELEGATES here (opus TB-016 - its earlier NetworkCredential-only variant returned ""
    /// for a null SecureString where this helper throws; unreachable at its null-guarded
    /// call sites, unified anyway). A third variant remains in
    /// AddDbaComputerCertificateCommand.SecureToPlain (Marshal.SecureStringToGlobalAllocUnicode
    /// + PtrToStringUni; Windows-only command; noted to the tracker, not unified in this
    /// row). Probed 5.1 + 7.6: an empty SecureString yields ""
    /// and unicode incl. surrogate pairs roundtrips exactly; a NULL SecureString throws
    /// from the PSCredential ctor ("password is null") - PS callers see that wrapped as
    /// MethodInvocationException, direct C# callers get the ctor's PSArgumentNullException
    /// unwrapped. This port deliberately calls the SAME PSCredential chain the helper
    /// does, so the null contract and marshalling are parity by construction.
    /// </summary>
    public static class SecurePass
    {
        /// <summary>The helper's body: PSCredential("fake", input).GetNetworkCredential().Password.</summary>
        public static string ToPlainText(SecureString inputObject)
        {
            return new PSCredential("fake", inputObject).GetNetworkCredential().Password;
        }
    }
}
