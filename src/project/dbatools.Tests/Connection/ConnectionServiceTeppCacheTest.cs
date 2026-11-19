using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.TabExpansion;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Connection.Test
{
    /// <summary>
    /// ConnectionService.AddTeppInstanceName against the pinned private Add-DbaTeppInstanceName (upstream 63a9dee51).
    /// The cache is process-wide, so each test saves and restores it and the class never runs in parallel.
    /// </summary>
    [TestClass]
    [DoNotParallelize]
    public class ConnectionServiceTeppCacheTest
    {
        private object savedCache;

        [TestInitialize]
        public void SaveCache()
        {
            savedCache = TabExpansionHost.Cache["sqlinstance"];
        }

        [TestCleanup]
        public void RestoreCache()
        {
            TabExpansionHost.Cache["sqlinstance"] = savedCache;
        }

        [TestMethod]
        public void EmptyCacheBecomesAnArrayOfTheTrimmedLowerCasedName()
        {
            TabExpansionHost.Cache["sqlinstance"] = null;
            ConnectionService.AddTeppInstanceName("  SQL01\\Named ");
            CollectionAssert.AreEqual(new object[] { "sql01\\named" }, (object[])TabExpansionHost.Cache["sqlinstance"]);
        }

        [TestMethod]
        public void StringCacheFromTheOldAppendBecomesAnArray()
        {
            // $null += "x" left a string behind before upstream 63a9dee51.
            TabExpansionHost.Cache["sqlinstance"] = "sql01";
            ConnectionService.AddTeppInstanceName("sql02");
            CollectionAssert.AreEqual(new object[] { "sql01", "sql02" }, (object[])TabExpansionHost.Cache["sqlinstance"]);
        }

        [TestMethod]
        public void KnownNameIsNotAddedAgainInAnyCase()
        {
            TabExpansionHost.Cache["sqlinstance"] = new object[] { "sql01" };
            ConnectionService.AddTeppInstanceName("SQL01");
            CollectionAssert.AreEqual(new object[] { "sql01" }, (object[])TabExpansionHost.Cache["sqlinstance"]);
        }

        [TestMethod]
        public void EmptyEntriesAndNamesAreDropped()
        {
            TabExpansionHost.Cache["sqlinstance"] = new object[] { "", null, "sql01" };
            ConnectionService.AddTeppInstanceName(null, "", "   ", "sql02");
            CollectionAssert.AreEqual(new object[] { "sql01", "sql02" }, (object[])TabExpansionHost.Cache["sqlinstance"]);
        }
    }
}
