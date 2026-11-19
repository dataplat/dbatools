using System;
using System.Net;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Exceptions;


namespace Dataplat.Dbatools.Parameter
{
    public partial class DbaInstanceParamaterTest
    {
        /// <summary>
        /// Tests that FileNameFriendly returns valid filenames for various connection types
        /// </summary>
        [TestMethod]
        public void TestFileNameFriendly()
        {
            // Test with named pipes using dot notation
            var npDot = new DbaInstanceParameter(".");
            Assert.AreEqual("NP_.", npDot.FileNameFriendly);
            Assert.IsFalse(npDot.FileNameFriendly.Contains(":"));

            // Test with named pipes using dot notation with instance
            var npDotInstance = new DbaInstanceParameter(@".\SQLSERVER");
            Assert.AreEqual("NP_._SQLSERVER", npDotInstance.FileNameFriendly);
            Assert.IsFalse(npDotInstance.FileNameFriendly.Contains(":"));
            Assert.IsFalse(npDotInstance.FileNameFriendly.Contains("\\"));

            // Test with TCP protocol
            var tcpInstance = new DbaInstanceParameter("TCP:server\\instance");
            Assert.AreEqual("TCP_server_instance", tcpInstance.FileNameFriendly);
            Assert.IsFalse(tcpInstance.FileNameFriendly.Contains(":"));
            Assert.IsFalse(tcpInstance.FileNameFriendly.Contains("\\"));

            // Test with port number
            var withPort = new DbaInstanceParameter("server,1433");
            Assert.AreEqual("server_1433", withPort.FileNameFriendly);
            Assert.IsFalse(withPort.FileNameFriendly.Contains(","));

            // Test with regular instance name (no protocol)
            var regular = new DbaInstanceParameter("server\\instance");
            Assert.AreEqual("server_instance", regular.FileNameFriendly);
            Assert.IsFalse(regular.FileNameFriendly.Contains("\\"));

            // Test that all results contain no invalid filename characters
            AssertFileNameFriendlySafe(npDot.FileNameFriendly);
            AssertFileNameFriendlySafe(npDotInstance.FileNameFriendly);
            AssertFileNameFriendlySafe(tcpInstance.FileNameFriendly);
            AssertFileNameFriendlySafe(withPort.FileNameFriendly);
            AssertFileNameFriendlySafe(regular.FileNameFriendly);
        }

        /// <summary>
        /// Tests that FileNameFriendly handles edge cases including IPv6 addresses
        /// </summary>
        [TestMethod]
        public void TestFileNameFriendlyEdgeCases()
        {
            // Test with IPv6 address (contains colons and brackets)
            var ipv6 = new DbaInstanceParameter("::1");
            AssertFileNameFriendlySafe(ipv6.FileNameFriendly);

            // Test with IPv6 address and port
            var ipv6Port = new DbaInstanceParameter("[::1]:1433");
            AssertFileNameFriendlySafe(ipv6Port.FileNameFriendly);

            // Test with regular IPv6 address
            var ipv6Full = new DbaInstanceParameter("2001:0db8:85a3:0000:0000:8a2e:0370:7334");
            AssertFileNameFriendlySafe(ipv6Full.FileNameFriendly);

            // Test with IPv4 address and port (contains colon)
            var ipv4Port = new DbaInstanceParameter("192.168.1.1:1433");
            AssertFileNameFriendlySafe(ipv4Port.FileNameFriendly);

            // Test that the results are not empty
            Assert.IsFalse(string.IsNullOrWhiteSpace(ipv6.FileNameFriendly));
            Assert.IsFalse(string.IsNullOrWhiteSpace(ipv6Port.FileNameFriendly));
            Assert.IsFalse(string.IsNullOrWhiteSpace(ipv6Full.FileNameFriendly));
            Assert.IsFalse(string.IsNullOrWhiteSpace(ipv4Port.FileNameFriendly));
        }

        private static void AssertFileNameFriendlySafe(string fileNameFriendly)
        {
            foreach (char c in System.IO.Path.GetInvalidFileNameChars())
            {
                Assert.IsFalse(fileNameFriendly.IndexOf(c) >= 0,
                    String.Format("FileNameFriendly contains invalid character U+{0:X4} in '{1}'", (int)c, fileNameFriendly));
            }

            foreach (char c in "<>:\"/\\|?*")
            {
                Assert.IsFalse(fileNameFriendly.IndexOf(c) >= 0,
                    String.Format("FileNameFriendly contains reserved filename character U+{0:X4} in '{1}'", (int)c, fileNameFriendly));
            }
        }
    }
}
