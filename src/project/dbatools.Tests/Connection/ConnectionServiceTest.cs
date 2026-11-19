using System;
using System.Management.Automation;
using System.Security;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Connection.Test
{
    [TestClass]
    public class ConnectionServiceTest
    {
        private static PSCredential BuildCredential(string userName)
        {
            SecureString password = new SecureString();
            password.AppendChar('x');
            password.MakeReadOnly();
            return new PSCredential(userName, password);
        }

        [TestMethod]
        public void BuildCacheKey_IntegratedAuthority()
        {
            SmoConnectionRequest request = new SmoConnectionRequest();
            request.Instance = new DbaInstanceParameter("Sql01");
            string key = ConnectionService.BuildCacheKey(request.Instance, request);
            StringAssert.Contains(key, "|integrated|");
            StringAssert.StartsWith(key, "sql01");
        }

        [TestMethod]
        public void BuildCacheKey_SqlLoginAuthority()
        {
            SmoConnectionRequest request = new SmoConnectionRequest();
            request.Instance = new DbaInstanceParameter("sql01\\dev,50000");
            request.SqlCredential = BuildCredential("sa");
            string key = ConnectionService.BuildCacheKey(request.Instance, request);
            StringAssert.Contains(key, "|sql|sa|");
        }

        [TestMethod]
        public void BuildCacheKey_WindowsCredentialAuthority()
        {
            SmoConnectionRequest request = new SmoConnectionRequest();
            request.Instance = new DbaInstanceParameter("sql01");
            request.SqlCredential = BuildCredential("LAB\\cl");
            string key = ConnectionService.BuildCacheKey(request.Instance, request);
            StringAssert.Contains(key, "|ad|lab\\cl|");
        }

        [TestMethod]
        public void BuildCacheKey_DatabaseAndIntentAreKeyed()
        {
            SmoConnectionRequest request = new SmoConnectionRequest();
            request.Instance = new DbaInstanceParameter("sql01");
            request.Database = "Master";
            request.ApplicationIntent = "ReadOnly";
            string key = ConnectionService.BuildCacheKey(request.Instance, request);
            Assert.AreEqual("sql01|master|integrated|readonly", key);
        }
    }
}
