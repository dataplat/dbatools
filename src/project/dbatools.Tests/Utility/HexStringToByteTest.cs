using System;
using CollectionAssert = Microsoft.VisualStudio.TestTools.UnitTesting.CollectionAssert;
using Dataplat.Dbatools.Utility;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Utility.Test
{
    /// <summary>
    /// TB-015 coverage for ByteHex.ToBytes, the C# parity port of
    /// private/functions/Convert-HexStringToByte.ps1 (sole live caller New-DbaLogin:255,
    /// Sid). Expected values ground-truthed against the PS helper on both editions (probe
    /// 2026-07-16). The load-bearing quirk: TrimStart("0x") strips the CHARACTER SET
    /// {'0','x'}, not the prefix - leading zero bytes are silently destroyed, and inputs
    /// consisting entirely of 0/x characters strip to empty and CRASH in the PS
    /// descending-range Substring. A "fixed" prefix-only strip fails these pins.
    /// </summary>
    [TestClass]
    public class HexStringToByteTest
    {
        [TestMethod]
        public void ToBytes_DocExamplesHold()
        {
            // "0x01641736" survives ONLY because the odd-length pad re-adds the zero the
            // char-set trim stripped ("0x0" gone, "1641736" is odd, pad -> "01641736").
            CollectionAssert.AreEqual(new byte[] { 1, 100, 23, 54 }, ByteHex.ToBytes("0x01641736"));
            CollectionAssert.AreEqual(new byte[] { 18, 52 }, ByteHex.ToBytes("1234"));
        }

        [TestMethod]
        public void ToBytes_TheCharSetTrimDestroysLeadingZeroBytes()
        {
            // A prefix-only strip yields {0,5,1} / {0,100,23,54} and fails here - the
            // preserved bug is the pin (flagged to the W2 security row for the compiled
            // New-DbaLogin to decide deliberately).
            CollectionAssert.AreEqual(new byte[] { 5, 1 }, ByteHex.ToBytes("0x000501"));
            CollectionAssert.AreEqual(new byte[] { 100, 23, 54 }, ByteHex.ToBytes("0x00641736"));
            CollectionAssert.AreEqual(new byte[] { 18 }, ByteHex.ToBytes("0012"), "bare leading zeros strip too");
            CollectionAssert.AreEqual(new byte[] { 18, 52 }, ByteHex.ToBytes("x1234"), "a lone x strips");
        }

        [TestMethod]
        public void ToBytes_OddLengthPadsAndParseIsFlexible()
        {
            CollectionAssert.AreEqual(new byte[] { 10, 188 }, ByteHex.ToBytes("ABC"), "odd length left-pads with 0");
            CollectionAssert.AreEqual(new byte[] { 255 }, ByteHex.ToBytes("ff"), "lowercase hex parses");
            // HexNumber tolerates leading/trailing whitespace within a two-char pair.
            CollectionAssert.AreEqual(new byte[] { 1, 35 }, ByteHex.ToBytes("1 23"));
        }

        [TestMethod]
        public void ToBytes_AllTrimmableInputsCrashLikeThePsDescendingRange()
        {
            // PS: the stripped-empty string makes 0..(0/2-1) the descending range {0,-1}
            // and Substring(0,2) throws (MethodInvocationException wrapping
            // ArgumentOutOfRangeException). Empty, null (the [string] binder's empty),
            // bare "0x"/"0" and - most dangerous - an ALL-ZERO hex like "0x0000" all die.
            Assert.ThrowsException<ArgumentOutOfRangeException>(() => ByteHex.ToBytes(""));
            Assert.ThrowsException<ArgumentOutOfRangeException>(() => ByteHex.ToBytes(null));
            Assert.ThrowsException<ArgumentOutOfRangeException>(() => ByteHex.ToBytes("0x"));
            Assert.ThrowsException<ArgumentOutOfRangeException>(() => ByteHex.ToBytes("0"));
            Assert.ThrowsException<ArgumentOutOfRangeException>(() => ByteHex.ToBytes("0x0000"));
        }

        [TestMethod]
        public void ToBytes_NonHexAndUppercaseXThrowFormatException()
        {
            Assert.ThrowsException<FormatException>(() => ByteHex.ToBytes("0xZZ"));
            // The trim set is case-SENSITIVE: "0X1234" loses only its leading 0, the X
            // stays; "X1234" is odd so it pads back to "0X1234" and the first pair "0X"
            // throws FormatException in Parse. Probed both editions.
            Assert.ThrowsException<FormatException>(() => ByteHex.ToBytes("0X1234"));
        }
    }
}
