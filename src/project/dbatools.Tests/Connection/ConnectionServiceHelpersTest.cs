using System;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Connection.Test
{
    /// <summary>
    /// Pure-logic coverage for the W1-001 Connect-DbaInstance engine helpers: connection
    /// string normalization, retry edits, username normalization, error-message walking and
    /// Azure detection. Live connection behavior is covered by the lab integration gate.
    /// </summary>
    [TestClass]
    public class ConnectionServiceHelpersTest
    {
        [TestMethod]
        public void ConvertConnectionString_RewritesLegacySynonyms()
        {
            string legacy = "Data Source=sql01;Application Intent=ReadOnly;Multiple Active Result Sets=True;Trust Server Certificate=True;Connect Retry Count=3";
            string converted = ConnectionService.ConvertConnectionString(legacy);
            StringAssert.Contains(converted, "ApplicationIntent=ReadOnly");
            StringAssert.Contains(converted, "MultipleActiveResultSets=True");
            StringAssert.Contains(converted, "TrustServerCertificate=True");
            StringAssert.Contains(converted, "ConnectRetryCount=3");
            Assert.IsFalse(converted.Contains("Application Intent"));
        }

        [TestMethod]
        public void ConvertConnectionString_CoversAllSevenSynonymsExactlyLikeThePsHelper()
        {
            // TB-009: private/functions/Convert-ConnectionString.ps1 parity - the three
            // synonyms the original test did not pin, plus the exact String.Replace
            // semantics the PS helper relies on: ORDINAL and CASE-SENSITIVE (a lowercase
            // spelling is deliberately untouched in both worlds), every occurrence
            // replaced, and non-matching text byte-identical.
            string legacy = "Connect Retry Interval=10;Pool Blocking Period=Auto;Multiple Subnet Failover=True";
            string converted = ConnectionService.ConvertConnectionString(legacy);
            Assert.AreEqual("ConnectRetryInterval=10;PoolBlockingPeriod=Auto;MultiSubnetFailover=True", converted);

            Assert.AreEqual("application intent=ReadOnly", ConnectionService.ConvertConnectionString("application intent=ReadOnly"), "String.Replace is case-sensitive in both worlds - lowercase stays");
            Assert.AreEqual("A=ApplicationIntentApplicationIntent", ConnectionService.ConvertConnectionString("A=Application IntentApplication Intent"), "every occurrence is replaced, even mid-token");
            Assert.AreEqual("Data Source=sql01", ConnectionService.ConvertConnectionString("Data Source=sql01"), "non-matching strings pass through byte-identical");
            Assert.IsNull(ConnectionService.ConvertConnectionString(null), "the null early return is a documented divergence unreachable through the PS mandatory binder - pinned mechanically");
        }

        [TestMethod]
        public void NormalizeFailoverPartnerKey_RewritesCompactSpelling()
        {
            string normalized = ConnectionService.NormalizeFailoverPartnerKey("Data Source=sqlmirror;FailoverPartner=mirrorpartner");
            StringAssert.Contains(normalized, "Failover Partner=mirrorpartner");
            Assert.IsFalse(normalized.Contains("FailoverPartner="));
        }

        [TestMethod]
        public void EnsureInitialCatalogForFailoverPartner_AppendsMasterOnlyWithPartnerAndNoCatalog()
        {
            string withPartner = ConnectionService.EnsureInitialCatalogForFailoverPartner("Data Source=sqlmirror;Failover Partner=mirrorpartner");
            StringAssert.Contains(withPartner, ";Initial Catalog=master;");

            string trailingSemicolon = ConnectionService.EnsureInitialCatalogForFailoverPartner("Data Source=sqlmirror;Failover Partner=mirrorpartner;");
            StringAssert.EndsWith(trailingSemicolon, "Failover Partner=mirrorpartner;Initial Catalog=master;");

            string withCatalog = ConnectionService.EnsureInitialCatalogForFailoverPartner("Data Source=sqlmirror;Failover Partner=mirrorpartner;Initial Catalog=tempdb");
            Assert.IsFalse(withCatalog.Contains("master"));

            string noPartner = ConnectionService.EnsureInitialCatalogForFailoverPartner("Data Source=sql01");
            Assert.AreEqual("Data Source=sql01", noPartner);
        }

        [TestMethod]
        public void EnsureInitialCatalogMaster_AppendsWhenMissingRegardlessOfPartner()
        {
            string appended = ConnectionService.EnsureInitialCatalogMaster("Data Source=sqlmirror;Integrated Security=True");
            StringAssert.EndsWith(appended, ";Initial Catalog=master;");

            string keptDatabase = ConnectionService.EnsureInitialCatalogMaster("Data Source=sqlmirror;Database=tempdb");
            Assert.IsFalse(keptDatabase.Contains("master"));
        }

        [TestMethod]
        public void RemoveIntegratedSecurity_IsCaseInsensitive()
        {
            string removed = ConnectionService.RemoveIntegratedSecurity("Data Source=sql01;integrated security=true;Pooling=True");
            Assert.AreEqual("Data Source=sql01;Pooling=True", removed);
        }

        [TestMethod]
        public void ApplyTrustServerCertificate_FlipsFalseAndAppendsWhenAbsent()
        {
            string flipped = ConnectionService.ApplyTrustServerCertificate("Data Source=sql01;Trust Server Certificate=False");
            StringAssert.Contains(flipped, "Trust Server Certificate=True");
            Assert.IsFalse(flipped.Contains("Trust Server Certificate=False"));

            string appended = ConnectionService.ApplyTrustServerCertificate("Data Source=sql01");
            StringAssert.EndsWith(appended, ";Trust Server Certificate=True;");

            string appendedTrailing = ConnectionService.ApplyTrustServerCertificate("Data Source=sql01;");
            StringAssert.EndsWith(appendedTrailing, "Data Source=sql01;Trust Server Certificate=True;");
        }

        [TestMethod]
        public void NormalizeConnectUserName_TrimsLeadingBackslash()
        {
            string normalized = ConnectionService.NormalizeConnectUserName("\\sqladmin", "WORKGROUPBOX", "WORKGROUPBOX");
            Assert.AreEqual("sqladmin", normalized);
        }

        [TestMethod]
        public void NormalizeConnectUserName_RewritesDomainUserWhenDomainJoined()
        {
            // USERDOMAIN differs from COMPUTERNAME, so ad\username becomes username@ad
            string normalized = ConnectionService.NormalizeConnectUserName("LAB\\cl", "LAB", "WORKSTATION");
            Assert.AreEqual("cl@LAB", normalized);
        }

        [TestMethod]
        public void NormalizeConnectUserName_KeepsDomainUserOnWorkgroupHost()
        {
            // USERDOMAIN equals COMPUTERNAME (workgroup), so the name stays domain\user
            string normalized = ConnectionService.NormalizeConnectUserName("LAB\\cl", "MYBOX", "MYBOX");
            Assert.AreEqual("LAB\\cl", normalized);
        }

        [TestMethod]
        public void NormalizeConnectUserName_KeepsUpnUntouched()
        {
            string normalized = ConnectionService.NormalizeConnectUserName("cl@lab.local", "LAB", "WORKSTATION");
            Assert.AreEqual("cl@lab.local", normalized);
        }

        [TestMethod]
        public void GetDeepErrorMessage_ReturnsDeepestMessageWithinSixLevels()
        {
            Exception deep = new Exception("outer",
                new Exception("middle",
                    new Exception("deepest")));
            Assert.AreEqual("deepest", ConnectionService.GetDeepErrorMessage(deep));

            Assert.AreEqual("only", ConnectionService.GetDeepErrorMessage(new Exception("only")));
        }

        [TestMethod]
        public void HideConnectionString_MasksPassword()
        {
            string masked = ConnectionService.HideConnectionString("Data Source=sql01;User ID=sa;Password=dbatools.IO");
            StringAssert.Contains(masked, "********");
            Assert.IsFalse(masked.Contains("dbatools.IO"));
        }

        [TestMethod]
        public void HideConnectionString_ReportsUnparseableStrings()
        {
            string masked = ConnectionService.HideConnectionString("this is not; a =connection;;string==");
            Assert.AreEqual("Failed to mask the connection string", masked);
        }

        [TestMethod]
        public void IsAzureInstance_MatchesEscapedDomainSuffix()
        {
            DbaInstanceParameter azure = new DbaInstanceParameter("mydb.database.windows.net");
            Assert.IsTrue(ConnectionService.IsAzureInstance(azure, System.Text.RegularExpressions.Regex.Escape("database.windows.net")));

            DbaInstanceParameter local = new DbaInstanceParameter("sql01");
            Assert.IsFalse(ConnectionService.IsAzureInstance(local, System.Text.RegularExpressions.Regex.Escape("database.windows.net")));
        }

        [TestMethod]
        public void BuildUnsupportedVersionMessage_MatchesPullRequest10813WordForWord()
        {
            // dbatools PR 10813 (head d8d01159), Connect-DbaInstance.ps1: the name per major version, and the Windows
            // PowerShell 5.1 note below 9 only. The lab has SQL Server 2005 only, so 8 and 7 are covered here.
            Assert.AreEqual("[sql2005] runs SQL Server 2005, which dbatools no longer supports: since 2.8.3, dbatools uses SMO 181, which requires SQL Server 2008 or later. The last release that supports SQL Server 2005 is dbatools 2.8.2 with dbatools.library 2025.12.28. See https://github.com/dataplat/dbatools#sql-server-2000-and-2005",
                ConnectionService.BuildUnsupportedVersionMessage("[sql2005]", 9));
            Assert.AreEqual("[sql2000] runs SQL Server 2000, which dbatools no longer supports: since 2.8.3, dbatools uses SMO 181, which requires SQL Server 2008 or later. The last release that supports SQL Server 2000 is dbatools 2.8.2 with dbatools.library 2025.12.28, run from Windows PowerShell 5.1. See https://github.com/dataplat/dbatools#sql-server-2000-and-2005",
                ConnectionService.BuildUnsupportedVersionMessage("[sql2000]", 8));
            Assert.AreEqual("[sql7] runs SQL Server version 7, which dbatools no longer supports: since 2.8.3, dbatools uses SMO 181, which requires SQL Server 2008 or later. The last release that supports SQL Server version 7 is dbatools 2.8.2 with dbatools.library 2025.12.28, run from Windows PowerShell 5.1. See https://github.com/dataplat/dbatools#sql-server-2000-and-2005",
                ConnectionService.BuildUnsupportedVersionMessage("[sql7]", 7));
        }
    }
}
