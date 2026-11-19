using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    // Coverage for the BP-105 WQL value-escaping helper (migration/specs/best-practices.md).
    // Order is significant: backslash is escaped first ('\' -> '\\'), then single quote ('\'' -> '\\'').
    [TestClass]
    public class WqlHelperTest
    {
        [TestMethod]
        public void EscapeValue_PlainName_ReturnsUnchanged()
        {
            // A value with no quote or backslash must come back byte-for-byte identical.
            Assert.AreEqual("MSSQLSERVER", WqlHelper.EscapeValue("MSSQLSERVER"));
        }

        [TestMethod]
        public void EscapeValue_EmbeddedSingleQuote_IsBackslashEscaped()
        {
            // O'Brien -> O\'Brien
            Assert.AreEqual("O\\'Brien", WqlHelper.EscapeValue("O'Brien"));
        }

        [TestMethod]
        public void EscapeValue_EmbeddedBackslash_IsDoubled()
        {
            // C:\Temp -> C:\\Temp
            Assert.AreEqual("C:\\\\Temp", WqlHelper.EscapeValue("C:\\Temp"));
        }

        [TestMethod]
        public void EscapeValue_BackslashAndQuoteCombined_EscapesBackslashFirst()
        {
            // Logical input : a \ b ' c
            // After escape  : a \\ b \' c   (backslash doubled, then quote prefixed)
            Assert.AreEqual("a\\\\b\\'c", WqlHelper.EscapeValue("a\\b'c"));
        }

        [TestMethod]
        public void EscapeValue_EmptyString_ReturnsEmpty()
        {
            Assert.AreEqual(string.Empty, WqlHelper.EscapeValue(string.Empty));
        }

        [TestMethod]
        public void EscapeValue_Null_ReturnsNull()
        {
            // Null passes through unchanged per BP-105 (documented helper contract).
            Assert.IsNull(WqlHelper.EscapeValue(null));
        }
    }
}
