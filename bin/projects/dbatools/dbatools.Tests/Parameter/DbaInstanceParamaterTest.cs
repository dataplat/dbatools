using System;
using System.Net;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Sqlcollaborative.Dbatools.Connection;
using Sqlcollaborative.Dbatools.Exceptions;

namespace Sqlcollaborative.Dbatools.Parameter
{
    [TestClass]
    public class DbaInstanceParamaterTest
    {
        [TestMethod]
        public void TestStringConstructor()
        {
            var dbaInstanceParamater = new DbaInstanceParameter("someMachine");

            Assert.AreEqual("someMachine", dbaInstanceParamater.FullName);
            Assert.AreEqual("someMachine", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual(SqlConnectionProtocol.Any, dbaInstanceParamater.NetworkProtocol);
            Assert.IsFalse(dbaInstanceParamater.IsLocalHost);
            Assert.IsFalse(dbaInstanceParamater.IsConnectionString);
        }

        [ExpectedException(typeof(BloodyHellGiveMeSomethingToWorkWithException), "Bloody hell! Don't give me an empty string for an instance name!")]
        [TestMethod]
        public void TestEmptyString()
        {
            var dbaInstanceParamater = new DbaInstanceParameter("\t");
        }

        [TestMethod]
        public void TestConnectionString()
        {
            var dbaInstanceParamater = new DbaInstanceParameter("Server=tcp:server.database.windows.net;Database=myDataBase;User ID =[LoginForDb]@[serverName]; Password = myPassword; Trusted_Connection = False;Encrypt = True; ");
            Assert.IsTrue(dbaInstanceParamater.IsConnectionString);
        }

        [ExpectedException(typeof(ArgumentException))]
        [TestMethod]
        public void TestConnectionStringBadKey()
        {
            new DbaInstanceParameter("Server=tcp:server.database.windows.net;Database=myDataBase;Trusted_Connection = True;Wrong=true");
        }

        [ExpectedException(typeof(FormatException))]
        [TestMethod]
        public void TestConnectionStringBadValue()
        {
            new DbaInstanceParameter("Server=tcp:server.database.windows.net;Database=myDataBase;Trusted_Connection=weird");
        }

        /// <summary>
        /// Checks that localhost\instancename is treated as a localhost connection
        /// </summary>
        [TestMethod]
        public void TestLocalhostNamedInstance()
        {
            var dbaInstanceParamater = new DbaInstanceParameter("localhost\\sql2008r2sp2");

            Assert.AreEqual("localhost\\sql2008r2sp2", dbaInstanceParamater.FullName);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
            Assert.AreEqual("localhost\\sql2008r2sp2", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual(SqlConnectionProtocol.Any, dbaInstanceParamater.NetworkProtocol);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
            Assert.IsFalse(dbaInstanceParamater.IsConnectionString);
        }

        /// <summary>
        /// Checks that . is treated as a localhost connection
        /// </summary>
        [TestMethod]
        public void TestDotHostname()
        {
            var dbaInstanceParamater = new DbaInstanceParameter(".");

            Assert.AreEqual(".", dbaInstanceParamater.FullName);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
            Assert.AreEqual("NP:.", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual(SqlConnectionProtocol.NP, dbaInstanceParamater.NetworkProtocol);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
            Assert.IsFalse(dbaInstanceParamater.IsConnectionString);
        }

        /// <summary>
        /// Checks that 127.0.0.1 is treated as a localhost connection
        /// </summary>
        [TestMethod]
        public void TestLocalhostIPConstructor()
        {
            var dbaInstanceParamater = new DbaInstanceParameter(IPAddress.Loopback);

            Assert.AreEqual("127.0.0.1", dbaInstanceParamater.FullName);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
        }

        /// <summary>
        /// Checks that ::1 is treated as a localhost connection
        /// </summary>
        [TestMethod]
        public void TestLocalhostIPv6Constructor()
        {
            var dbaInstanceParamater = new DbaInstanceParameter(IPAddress.IPv6Loopback);

            Assert.AreEqual("::1", dbaInstanceParamater.FullName);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
        }
    }
}
