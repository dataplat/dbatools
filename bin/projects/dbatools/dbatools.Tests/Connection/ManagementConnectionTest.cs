using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Sqlcollaborative.Dbatools.Connection
{
    //TODO: Add a reference to System.Management.Automation to the project so I can test PsCredential

    [TestClass]
    public class ManagementConnectionTest
    {
        [TestMethod]
        public void TestDefaults()
        {
            var mgmtCn = new ManagementConnection();
            Assert.IsNull(mgmtCn.ComputerName);
            Assert.IsFalse(mgmtCn.DisableBadCredentialCache);
            Assert.IsFalse(mgmtCn.DisableCimPersistence);
            Assert.IsFalse(mgmtCn.DisableCredentialAutoRegister);
            Assert.AreEqual(ManagementConnectionType.Wmi | ManagementConnectionType.PowerShellRemoting, mgmtCn.DisabledConnectionTypes);
            Assert.IsFalse(mgmtCn.EnableCredentialFailover);
            Assert.IsFalse(mgmtCn.OverrideExplicitCredential);
            Assert.IsFalse(mgmtCn.UseWindowsCredentials);
            Assert.IsFalse(mgmtCn.WindowsCredentialsAreBad);
            Assert.IsNull(mgmtCn.ToString());
        }

        [TestMethod]
        public void TestRestoreDefaultConfiguration()
        {
            var mgmtCn = new ManagementConnection();
            mgmtCn.DisableBadCredentialCache = true;
            mgmtCn.DisableCredentialAutoRegister = true;
            mgmtCn.OverrideExplicitCredential = true;
            mgmtCn.DisableCimPersistence = true;
            mgmtCn.EnableCredentialFailover = true;
            mgmtCn.RestoreDefaultConfiguration();

            Assert.IsFalse(mgmtCn.DisableBadCredentialCache);
            Assert.IsFalse(mgmtCn.DisableCimPersistence);
            Assert.IsFalse(mgmtCn.DisableCredentialAutoRegister);
            Assert.IsFalse(mgmtCn.EnableCredentialFailover);
            Assert.IsFalse(mgmtCn.OverrideExplicitCredential);
        }
    }
}
