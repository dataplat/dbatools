using Dataplat.Dbatools.Utility;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Utility.Test
{
    /// <summary>
    /// TB-008 coverage for ByteHex.Convert, the C# parity port of
    /// private/functions/Convert-ByteToHexString.ps1: the helper's two documented examples
    /// verbatim, padding and uppercase behavior, the empty-array boundary, and the
    /// null-pipes-once "0x00" quirk.
    /// </summary>
    [TestClass]
    public class ByteHexTest
    {
        [TestMethod]
        public void Convert_MatchesTheHelperDocExamples()
        {
            // .EXAMPLE blocks of the PS helper, verbatim vectors.
            Assert.AreEqual("0x01641736", ByteHex.Convert(new byte[] { 1, 100, 23, 54 }));
            Assert.AreEqual("0x1234", ByteHex.Convert(new byte[] { 18, 52 }));
        }

        [TestMethod]
        public void Convert_PadsAndUppercasesEveryByte()
        {
            Assert.AreEqual("0x05", ByteHex.Convert(new byte[] { 5 }), "single low byte pads to two digits");
            Assert.AreEqual("0xFF", ByteHex.Convert(new byte[] { 255 }), "hex letters are uppercase like {0:X}");
            Assert.AreEqual("0x00AB10", ByteHex.Convert(new byte[] { 0, 171, 16 }));
        }

        [TestMethod]
        public void Convert_EmptyArrayYieldsBarePrefix()
        {
            // An empty array pipes zero times in PS: just the "0x" seed remains.
            Assert.AreEqual("0x", ByteHex.Convert(new byte[0]));
        }

        [TestMethod]
        public void Convert_NullPipesOnceLikePs()
        {
            // PS quirk: $null | ForEach-Object executes once; "{0:X}" -f $null is "" and
            // PadLeft(2, "0") turns it into "00" - so a null input is NOT the empty case.
            Assert.AreEqual("0x00", ByteHex.Convert(null));
        }
    }
}
