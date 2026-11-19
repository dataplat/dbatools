using System;
using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    [TestClass]
    public class GetDbaServiceCommandTest
    {
        [TestMethod]
        public void MapServiceType_KnownId_ReturnsName()
        {
            Assert.AreEqual("Engine",    GetDbaServiceCommand.MapServiceType(1));
            Assert.AreEqual("Agent",     GetDbaServiceCommand.MapServiceType(2));
            Assert.AreEqual("FullText",  GetDbaServiceCommand.MapServiceType(3));
            Assert.AreEqual("FullText",  GetDbaServiceCommand.MapServiceType(9));
            Assert.AreEqual("SSIS",      GetDbaServiceCommand.MapServiceType(4));
            Assert.AreEqual("SSAS",      GetDbaServiceCommand.MapServiceType(5));
            Assert.AreEqual("SSRS",      GetDbaServiceCommand.MapServiceType(6));
            Assert.AreEqual("Browser",   GetDbaServiceCommand.MapServiceType(7));
            Assert.AreEqual("PolyBase",  GetDbaServiceCommand.MapServiceType(10));
            Assert.AreEqual("PolyBase",  GetDbaServiceCommand.MapServiceType(11));
            Assert.AreEqual("Launchpad", GetDbaServiceCommand.MapServiceType(12));
            Assert.AreEqual("Unknown",   GetDbaServiceCommand.MapServiceType(8));
        }

        [TestMethod]
        public void MapServiceType_UnknownId_ReturnsUnknown()
        {
            Assert.AreEqual("Unknown", GetDbaServiceCommand.MapServiceType(99));
            Assert.AreEqual("Unknown", GetDbaServiceCommand.MapServiceType(0));
        }

        [TestMethod]
        public void MapState_KnownValues_ReturnMappedStrings()
        {
            Assert.AreEqual("Stopped",       GetDbaServiceCommand.MapState(1));
            Assert.AreEqual("Start Pending", GetDbaServiceCommand.MapState(2));
            Assert.AreEqual("Stop Pending",  GetDbaServiceCommand.MapState(3));
            Assert.AreEqual("Running",       GetDbaServiceCommand.MapState(4));
        }

        [TestMethod]
        public void MapState_UnmappedValue_ReturnsNull()
        {
            // PS switch has no default: an unmapped state (e.g. 7 = Paused, 5/6, 0) yields $null.
            Assert.IsNull(GetDbaServiceCommand.MapState(7));
            Assert.IsNull(GetDbaServiceCommand.MapState(5));
            Assert.IsNull(GetDbaServiceCommand.MapState(0));
        }

        [TestMethod]
        public void MapStartMode_KnownValues_ReturnMappedStrings()
        {
            Assert.AreEqual("Unknown",   GetDbaServiceCommand.MapStartMode(1));
            Assert.AreEqual("Automatic", GetDbaServiceCommand.MapStartMode(2));
            Assert.AreEqual("Manual",    GetDbaServiceCommand.MapStartMode(3));
            Assert.AreEqual("Disabled",  GetDbaServiceCommand.MapStartMode(4));
        }

        [TestMethod]
        public void MapStartMode_UnmappedValue_ReturnsNull()
        {
            // PS switch has no default: an unmapped start mode (e.g. 0, 5) yields $null.
            Assert.IsNull(GetDbaServiceCommand.MapStartMode(0));
            Assert.IsNull(GetDbaServiceCommand.MapStartMode(5));
        }

        [TestMethod]
        public void ServiceIdMap_ContainsAllExpectedEntries()
        {
            // Verify the map covers all expected SQL service types
            int expectedCount = 10; // Engine, Agent, FullText, SSIS, SSAS, SSRS, Browser, PolyBase, Launchpad, Unknown
            Assert.AreEqual(expectedCount, GetDbaServiceCommand.ServiceIdMap.Length);
        }

        [TestMethod]
        public void ServiceIdMap_FullTextHasTwoIds()
        {
            // FullText covers WMI type 3 and 9 (older SQL Search service)
            foreach (var (name, ids) in GetDbaServiceCommand.ServiceIdMap)
            {
                if (name == "FullText")
                {
                    Assert.AreEqual(2, ids.Length);
                    Assert.IsTrue(Array.IndexOf(ids, 3) >= 0);
                    Assert.IsTrue(Array.IndexOf(ids, 9) >= 0);
                    return;
                }
            }
            Assert.Fail("FullText entry not found in ServiceIdMap");
        }

        [TestMethod]
        public void ServiceIdMap_PolyBaseHasTwoIds()
        {
            // PolyBase covers WMI type 10 (DataMovement) and 11 (Engine)
            foreach (var (name, ids) in GetDbaServiceCommand.ServiceIdMap)
            {
                if (name == "PolyBase")
                {
                    Assert.AreEqual(2, ids.Length);
                    Assert.IsTrue(Array.IndexOf(ids, 10) >= 0);
                    Assert.IsTrue(Array.IndexOf(ids, 11) >= 0);
                    return;
                }
            }
            Assert.Fail("PolyBase entry not found in ServiceIdMap");
        }
    }
}
