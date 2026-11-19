using System;
using System.Net;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Exceptions;

namespace Dataplat.Dbatools.Parameter
{
    [TestClass]
    public partial class DbaInstanceParamaterTest
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
        [TestMethod]
        public void TestEmptyString(string whitespace)
        {
            var ex = Assert.ThrowsException<BloodyHellGiveMeSomethingToWorkWithException>(() => new DbaInstanceParameter(whitespace));
            Assert.AreEqual("DbaInstanceParameter", ex.ParameterClass);
        }

        [TestMethod]
        public void TestConnectionString()
        {
            var dbaInstanceParamater = new DbaInstanceParameter("Server=tcp:server.database.windows.net;Database=myDataBase;User ID =[LoginForDb]@[serverName]; Password = myPassword; Trusted_Connection = False;Encrypt = True; ");
            Assert.IsTrue(dbaInstanceParamater.IsConnectionString);
        }

        [TestMethod]
        public void TestWidNamedPipe()
        {
            var dbaInstanceParamater = new DbaInstanceParameter(@"np:\\.\pipe\MICROSOFT##WID\tsql\query");

            Assert.AreEqual(".", dbaInstanceParamater.ComputerName);
            Assert.AreEqual("MSSQLSERVER", dbaInstanceParamater.InstanceName);
            Assert.AreEqual(@"\\.\pipe\MICROSOFT##WID\tsql\query", dbaInstanceParamater.FullName);
            Assert.AreEqual(@"NP:\\.\pipe\MICROSOFT##WID\tsql\query", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual(@"NP_._MICROSOFT##WID", dbaInstanceParamater.FileNameFriendly);
            AssertFileNameFriendlySafe(dbaInstanceParamater.FileNameFriendly);
            Assert.AreEqual(SqlConnectionProtocol.NP, dbaInstanceParamater.NetworkProtocol);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
            Assert.IsFalse(dbaInstanceParamater.IsConnectionString);
        }

        [TestMethod]
        public void TestWidNamedPipeWithoutProtocolPrefix()
        {
            var dbaInstanceParamater = new DbaInstanceParameter(@"\\.\pipe\MICROSOFT##WID\tsql\query");

            Assert.AreEqual(".", dbaInstanceParamater.ComputerName);
            Assert.AreEqual("MSSQLSERVER", dbaInstanceParamater.InstanceName);
            Assert.AreEqual(@"\\.\pipe\MICROSOFT##WID\tsql\query", dbaInstanceParamater.FullName);
            Assert.AreEqual(@"NP:\\.\pipe\MICROSOFT##WID\tsql\query", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual(@"NP_._MICROSOFT##WID", dbaInstanceParamater.FileNameFriendly);
            AssertFileNameFriendlySafe(dbaInstanceParamater.FileNameFriendly);
            Assert.AreEqual(SqlConnectionProtocol.NP, dbaInstanceParamater.NetworkProtocol);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
            Assert.IsFalse(dbaInstanceParamater.IsConnectionString);
        }

        [TestMethod]
        public void TestWidNamedPipeConnectionString()
        {
            var dbaInstanceParamater = new DbaInstanceParameter(@"server=\\.\pipe\MICROSOFT##WID\tsql\query;database=SUSDB;trusted_connection=true;");
            var connectionString = new Microsoft.Data.SqlClient.SqlConnectionStringBuilder((string)dbaInstanceParamater.InputObject);

            Assert.AreEqual(".", dbaInstanceParamater.ComputerName);
            Assert.AreEqual("MSSQLSERVER", dbaInstanceParamater.InstanceName);
            Assert.AreEqual(@"\\.\pipe\MICROSOFT##WID\tsql\query", dbaInstanceParamater.FullName);
            Assert.AreEqual(@"NP:\\.\pipe\MICROSOFT##WID\tsql\query", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual(@"NP:\\.\pipe\MICROSOFT##WID\tsql\query", connectionString.DataSource);
            Assert.AreEqual(@"NP_._MICROSOFT##WID", dbaInstanceParamater.FileNameFriendly);
            AssertFileNameFriendlySafe(dbaInstanceParamater.FileNameFriendly);
            Assert.AreEqual(SqlConnectionProtocol.NP, dbaInstanceParamater.NetworkProtocol);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
            Assert.IsTrue(dbaInstanceParamater.IsConnectionString);
        }

        [TestMethod]
        public void TestRemoteWidNamedPipe()
        {
            var dbaInstanceParamater = new DbaInstanceParameter(@"np:\\server\pipe\MICROSOFT##WID\tsql\query");

            Assert.AreEqual("server", dbaInstanceParamater.ComputerName);
            Assert.AreEqual("MSSQLSERVER", dbaInstanceParamater.InstanceName);
            Assert.AreEqual(@"\\server\pipe\MICROSOFT##WID\tsql\query", dbaInstanceParamater.FullName);
            Assert.AreEqual(@"NP:\\server\pipe\MICROSOFT##WID\tsql\query", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual(@"NP_server_MICROSOFT##WID", dbaInstanceParamater.FileNameFriendly);
            AssertFileNameFriendlySafe(dbaInstanceParamater.FileNameFriendly);
            Assert.AreEqual(SqlConnectionProtocol.NP, dbaInstanceParamater.NetworkProtocol);
            Assert.IsFalse(dbaInstanceParamater.IsLocalHost);
            Assert.IsFalse(dbaInstanceParamater.IsConnectionString);
        }

        [TestMethod]
        public void TestNamedInstancePipeWithProtocolPrefix()
        {
            var dbaInstanceParamater = new DbaInstanceParameter(@"np:\\server\pipe\MSSQL$inst\sql\query");

            Assert.AreEqual("server", dbaInstanceParamater.ComputerName);
            Assert.AreEqual("inst", dbaInstanceParamater.InstanceName);
            Assert.AreEqual(@"server\inst", dbaInstanceParamater.FullName);
            Assert.AreEqual(@"NP:server\inst", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual("NP_server_inst", dbaInstanceParamater.FileNameFriendly);
            AssertFileNameFriendlySafe(dbaInstanceParamater.FileNameFriendly);
            Assert.AreEqual(SqlConnectionProtocol.NP, dbaInstanceParamater.NetworkProtocol);
            Assert.IsFalse(dbaInstanceParamater.IsLocalHost);
            Assert.IsFalse(dbaInstanceParamater.IsConnectionString);
        }

        [TestMethod]
        public void TestConnectionStringBadKey()
        {
            Assert.ThrowsException<ArgumentException>(() => new DbaInstanceParameter("Server=tcp:server.database.windows.net;Database=myDataBase;Trusted_Connection = True;Wrong=true"));
        }

        [TestMethod]
        public void TestConnectionStringBadValue()
        {
            Assert.ThrowsException<FormatException>(() => new DbaInstanceParameter("Server=tcp:server.database.windows.net;Database=myDataBase;Trusted_Connection=weird"));
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
            Assert.AreEqual("NP_.", dbaInstanceParamater.FileNameFriendly);
            Assert.AreEqual(@"MSSQLSERVER", dbaInstanceParamater.InstanceName);
            Assert.AreEqual(@"[MSSQLSERVER]", dbaInstanceParamater.SqlInstanceName);
            Assert.AreEqual(@"[.]", dbaInstanceParamater.SqlFullName);
            Assert.AreEqual(SqlConnectionProtocol.NP, dbaInstanceParamater.NetworkProtocol);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
            Assert.IsFalse(dbaInstanceParamater.IsConnectionString);
        }

        /// <summary>
        /// Checks that . is treated as a localhost connection
        /// </summary>
        [TestMethod]
        public void TestDotHostnameWithInstance()
        {
            var dbaInstanceParamater = new DbaInstanceParameter(@".\instancename");

            Assert.AreEqual(".", dbaInstanceParamater.ComputerName);
            Assert.AreEqual("[.]", dbaInstanceParamater.SqlComputerName);
            Assert.AreEqual(@".\instancename", dbaInstanceParamater.FullName);
            Assert.IsTrue(dbaInstanceParamater.IsLocalHost);
            Assert.AreEqual(@"NP:.\instancename", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual(@"NP_._instancename", dbaInstanceParamater.FileNameFriendly);
            Assert.AreEqual(@"instancename", dbaInstanceParamater.InstanceName);
            Assert.AreEqual(@"[instancename]", dbaInstanceParamater.SqlInstanceName);
            Assert.AreEqual(@"[.\instancename]", dbaInstanceParamater.SqlFullName);
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

        /// <summary>
        /// Checks that instance names with dashes are properly parsed
        /// </summary>
        [TestMethod]
        public void TestInstanceNameWithDash()
        {
            var dbaInstanceParamater = new DbaInstanceParameter("My-Instance.domain.local\\My-TestInstance");

            Assert.AreEqual("My-Instance.domain.local", dbaInstanceParamater.ComputerName);
            Assert.AreEqual("My-TestInstance", dbaInstanceParamater.InstanceName);
            Assert.AreEqual("My-Instance.domain.local\\My-TestInstance", dbaInstanceParamater.FullName);
            Assert.AreEqual("My-Instance.domain.local\\My-TestInstance", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual("[My-Instance.domain.local]", dbaInstanceParamater.SqlComputerName);
            Assert.AreEqual("[My-TestInstance]", dbaInstanceParamater.SqlInstanceName);
            Assert.AreEqual("[My-Instance.domain.local\\My-TestInstance]", dbaInstanceParamater.SqlFullName);
            Assert.IsFalse(dbaInstanceParamater.IsConnectionString);
        }

        /// <summary>
        /// Checks that server names with dashes work correctly (regression test)
        /// </summary>
        [TestMethod]
        public void TestServerNameWithDash()
        {
            var dbaInstanceParamater = new DbaInstanceParameter("My-Instance.domain.local\\MyTestInstance");

            Assert.AreEqual("My-Instance.domain.local", dbaInstanceParamater.ComputerName);
            Assert.AreEqual("MyTestInstance", dbaInstanceParamater.InstanceName);
            Assert.AreEqual("My-Instance.domain.local\\MyTestInstance", dbaInstanceParamater.FullName);
            Assert.AreEqual("My-Instance.domain.local\\MyTestInstance", dbaInstanceParamater.FullSmoName);
            Assert.AreEqual("[My-Instance.domain.local]", dbaInstanceParamater.SqlComputerName);
            Assert.AreEqual("[MyTestInstance]", dbaInstanceParamater.SqlInstanceName);
            Assert.AreEqual("[My-Instance.domain.local\\MyTestInstance]", dbaInstanceParamater.SqlFullName);
            Assert.IsFalse(dbaInstanceParamater.IsConnectionString);
        }

    }
}
