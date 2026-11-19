using System;
using System.Management.Automation;
using System.Security;
using Dataplat.Dbatools.Utility;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Utility.Test
{
    /// <summary>
    /// TB-016 coverage for SecurePass.ToPlainText, the C# parity port of
    /// private/functions/ConvertFrom-SecurePass.ps1. Expected values ground-truthed
    /// against the PS helper on both editions (probe 2026-07-16): plaintext, empty and
    /// unicode-with-surrogate-pair inputs roundtrip exactly; every null shape (named,
    /// unbound, pipeline) throws from the PSCredential ctor.
    /// </summary>
    [TestClass]
    public class SecurePassTest
    {
        private static SecureString Build(string plain)
        {
            SecureString secure = new SecureString();
            foreach (char ch in plain)
            {
                secure.AppendChar(ch);
            }
            return secure;
        }

        [TestMethod]
        public void ToPlainText_RoundtripsPlaintext()
        {
            Assert.AreEqual("s3cr3t!", SecurePass.ToPlainText(Build("s3cr3t!")));
        }

        [TestMethod]
        public void ToPlainText_EmptySecureStringIsEmptyString()
        {
            Assert.AreEqual("", SecurePass.ToPlainText(new SecureString()));
        }

        [TestMethod]
        public void ToPlainText_UnicodeIncludingSurrogatePairsRoundtripsExactly()
        {
            // a-umlaut + euro sign + U+1D11E (musical G clef, a surrogate pair) - the
            // pair pins UTF-16 fidelity through the SecureString marshal (probed: the PS
            // helper returns it verbatim, ordinal-equal, length 4).
            string plain = "ä€" + char.ConvertFromUtf32(0x1D11E);
            string roundtrip = SecurePass.ToPlainText(Build(plain));
            Assert.AreEqual(4, roundtrip.Length);
            Assert.IsTrue(string.Equals(plain, roundtrip, StringComparison.Ordinal));
        }

        [TestMethod]
        public void ToPlainText_NullThrowsFromThePsCredentialCtor()
        {
            // PS ground truth: -InputObject $null, the unbound call and $null piped all
            // throw MethodInvocationException wrapping the PSCredential ctor's
            // "password is null" complaint; the direct C# caller sees the ctor exception
            // unwrapped. PSArgumentNullException derives from ArgumentNullException -
            // assert the exact runtime type the ctor documents.
            Assert.ThrowsException<PSArgumentNullException>(() => SecurePass.ToPlainText(null));
        }
    }
}
