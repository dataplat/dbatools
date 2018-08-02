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

        [DataRow(null)]
        [DataRow("")]
        [DataRow(" ")]
        [DataRow("\n")]
        [DataRow(" \n \t")]
        [DataRow(" \v\t\t ")]
        [DataRow(null)]
        [ExpectedException(typeof(BloodyHellGiveMeSomethingToWorkWithException), "Bloody hell! Don't give me an empty string for an instance name!")]
        [TestMethod]
        public void TestEmptyString(string whitespace)
        {
            try
            {
                new DbaInstanceParameter(whitespace);
            }
            catch (BloodyHellGiveMeSomethingToWorkWithException ex)
            {
                Assert.AreEqual("DbaInstanceParameter", ex.ParameterClass);
                throw;
            }
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
            Assert.AreEqual("[localhost\\sql2008r2sp2]", dbaInstanceParamater.SqlFullName);
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

            Assert.AreEqual(".", dbaInstanceParamater.ComputerName);
            Assert.AreEqual("[.]", dbaInstanceParamater.SqlComputerName);
            Assert.AreEqual(".", dbaInstanceParamater.FullName);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
            Assert.AreEqual("NP:.", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual(@"MSSQLSERVER", dbaInstanceParamater.InstanceName);
            Assert.AreEqual(@"[MSSQLSERVER]", dbaInstanceParamater.SqlInstanceName);
            Assert.AreEqual(@"[.]", dbaInstanceParamater.SqlFullName);
            Assert.AreEqual(SqlConnectionProtocol.NP, dbaInstanceParamater.NetworkProtocol);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
            Assert.IsFalse(dbaInstanceParamater.IsConnectionString);
        }

        /// <summary>
        /// Checks that localdb named instances
        /// </summary>
        [TestMethod]
        //[Ignore()]
        public void TestLocalDb()
        {
            var dbaInstanceParamater = new DbaInstanceParameter(@"(LocalDb)\MSSQLLocalDB");

            Assert.AreEqual("localhost", dbaInstanceParamater.ComputerName);
            Assert.AreEqual("[localhost]", dbaInstanceParamater.SqlComputerName);
            Assert.AreEqual(@"(localdb)\MSSQLLocalDB", dbaInstanceParamater.FullName);
            Assert.AreEqual(@"(localdb)\MSSQLLocalDB", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual(@"MSSQLLocalDB", dbaInstanceParamater.InstanceName);
            Assert.AreEqual(@"[MSSQLLocalDB]", dbaInstanceParamater.SqlInstanceName);
            Assert.AreEqual(SqlConnectionProtocol.Any, dbaInstanceParamater.NetworkProtocol);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
            Assert.IsFalse(dbaInstanceParamater.IsConnectionString);
        }

        /// <summary>
        /// Checks parsing of a localdb connectionstring
        /// </summary>
        [TestMethod]
        public void TestLocalDbConnectionString()
        {
            var dbaInstanceParamater = new DbaInstanceParameter(@"Data Source=(LocalDb)\MSSQLLocalDB;Initial Catalog=aspnet-MvcMovie;Integrated Security=SSPI;AttachDBFilename=|DataDirectory|\Movies.mdf");

            Assert.AreEqual("localhost", dbaInstanceParamater.ComputerName);
            Assert.AreEqual("[localhost]", dbaInstanceParamater.SqlComputerName);
            Assert.AreEqual(@"localhost\MSSQLLocalDB", dbaInstanceParamater.FullName);
            Assert.AreEqual(@"localhost\MSSQLLocalDB", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual(@"localhost\MSSQLLocalDB", dbaInstanceParamater.ToString());
            Assert.AreEqual(@"MSSQLLocalDB", dbaInstanceParamater.InstanceName);
            Assert.AreEqual(SqlConnectionProtocol.Any, dbaInstanceParamater.NetworkProtocol);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
            Assert.IsTrue(dbaInstanceParamater.IsConnectionString);
        }

        /// <summary>
        /// Checks that 127.0.0.1 is treated as a localhost connection
        /// </summary>
        [DataRow("127.0.0.1")]
        [DataRow("::1")]
        [DataRow("0.0.0.0")]
        [DataRow("192.168.1.1")]
        [DataTestMethod]
        [TestMethod]
        public void TestIpAddressConstructor(string ipStr)
        {
            var ip = IPAddress.Parse(ipStr);
            var dbaInstanceParamater = new DbaInstanceParameter(ip);

            Assert.AreEqual(ip.ToString(), dbaInstanceParamater.FullName);
            Assert.AreEqual('[' + ip.ToString() + ']', dbaInstanceParamater.SqlFullName);
            Assert.AreEqual(ip.ToString(), dbaInstanceParamater.FullSmoName);
            Assert.AreEqual(ip.ToString(), dbaInstanceParamater.ToString());
            Assert.AreEqual(SqlConnectionProtocol.Any, dbaInstanceParamater.NetworkProtocol);
        }

        /// <summary>
        /// Checks that 127.0.0.1 is treated as a localhost connection
        /// </summary>
        [DataRow("127.0.0.1")]
        [DataRow("::1")]
        [DataRow("localhost")]
        [DataTestMethod]
        [TestMethod]
        public void TestLocalhost(string localhost)
        {
            var dbaInstanceParamater = new DbaInstanceParameter(localhost);

            Assert.AreEqual(localhost, dbaInstanceParamater.FullName);
            Assert.AreEqual('[' + localhost + ']', dbaInstanceParamater.SqlFullName);
            Assert.AreEqual(localhost, dbaInstanceParamater.FullSmoName);
            Assert.AreEqual(localhost, dbaInstanceParamater.ToString());
            Assert.AreEqual(SqlConnectionProtocol.Any, dbaInstanceParamater.NetworkProtocol);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
        }
    }
}
