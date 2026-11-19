using System;
using System.Linq;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Utility.Test
{
    [TestClass]
    public class OutputHelperTest
    {
        public sealed class MetadataValueFixture
        {
            public object Value { get; private set; }

            public MetadataValueFixture()
            {
                Value = new object();
            }

            public object Unreadable
            {
                get { throw new InvalidOperationException("Metadata getter is unavailable"); }
            }
        }

        [TestMethod]
        public void GetPSProperty_PreservesNoteReferenceAndNull()
        {
            PSObject obj = new PSObject();
            object value = new object();
            obj.Properties.Add(new PSNoteProperty("Value", value));
            obj.Properties.Add(new PSNoteProperty("Empty", null));

            Assert.AreSame(value, SmoServerExtensions.GetPSProperty(obj, "Value"));
            Assert.IsNull(SmoServerExtensions.GetPSProperty(obj, "Empty"));
        }

        [TestMethod]
        public void GetPSProperty_ReadsAdaptedClrAndKeepsUnreadableFallback()
        {
            MetadataValueFixture fixture = new MetadataValueFixture();

            Assert.AreSame(fixture.Value, SmoServerExtensions.GetPSProperty(fixture, "Value"));
            Assert.IsNull(SmoServerExtensions.GetPSProperty(fixture, "Unreadable"));
        }

        [TestMethod]
        public void GetPSProperty_ResolvesOrdinaryAndChainedAliases()
        {
            PSObject obj = new PSObject();
            object value = new object();
            obj.Properties.Add(new PSNoteProperty("Value", value));
            obj.Properties.Add(new PSAliasProperty("Alias", "Value"));
            obj.Properties.Add(new PSAliasProperty("ChainedAlias", "Alias"));

            Assert.AreSame(value, SmoServerExtensions.GetPSProperty(obj, "Alias"));
            Assert.AreSame(value, SmoServerExtensions.GetPSProperty(obj, "ChainedAlias"));
        }

        [TestMethod]
        public void GetPSProperty_PreservesAliasConversion()
        {
            PSObject obj = new PSObject();
            obj.Properties.Add(new PSNoteProperty("TextPort", "1433"));
            obj.Properties.Add(new PSAliasProperty("Port", "TextPort", typeof(int)));
            obj.Properties.Add(new PSNoteProperty("InvalidPort", "not-an-integer"));
            obj.Properties.Add(new PSAliasProperty("InvalidAlias", "InvalidPort", typeof(int)));

            object value = SmoServerExtensions.GetPSProperty(obj, "Port");
            Assert.IsInstanceOfType(value, typeof(int));
            Assert.AreEqual(1433, value);
            Assert.IsNull(SmoServerExtensions.GetPSProperty(obj, "InvalidAlias"));
        }

        [TestMethod]
        public void GetPSProperty_MissingAndDanglingMembersReturnNull()
        {
            PSObject obj = new PSObject();
            obj.Properties.Add(new PSAliasProperty("Dangling", "Absent"));

            Assert.IsNull(SmoServerExtensions.GetPSProperty(null, "Absent"));
            Assert.IsNull(SmoServerExtensions.GetPSProperty(obj, "Absent"));
            Assert.IsNull(SmoServerExtensions.GetPSProperty(obj, "Dangling"));
        }

        [TestMethod]
        public void GetPSProperty_AliasCycleReturnsNull()
        {
            PSObject obj = new PSObject();
            obj.Properties.Add(new PSAliasProperty("First", "Second"));
            obj.Properties.Add(new PSAliasProperty("Second", "First"));

            // PSAliasProperty.Value reports cycles as ExtendedTypeSystemException.
            Assert.IsNull(SmoServerExtensions.GetPSProperty(obj, "First"));
        }

        private static PSObject BuildObject()
        {
            PSObject obj = new PSObject();
            obj.Properties.Add(new PSNoteProperty("ComputerName", "server1"));
            obj.Properties.Add(new PSNoteProperty("InstanceName", "MSSQLSERVER"));
            obj.Properties.Add(new PSNoteProperty("SqlInstance", "server1"));
            obj.Properties.Add(new PSNoteProperty("Total", 4096));
            obj.Properties.Add(new PSNoteProperty("Server", "hidden"));
            return obj;
        }

        [TestMethod]
        public void SetDefaultDisplayPropertySet_AttachesCuratedColumns()
        {
            PSObject obj = BuildObject();
            OutputHelper.SetDefaultDisplayPropertySet(obj, "ComputerName", "InstanceName", "SqlInstance", "Total");

            PSMemberSet standardMembers = obj.Members["PSStandardMembers"] as PSMemberSet;
            Assert.IsNotNull(standardMembers, "PSStandardMembers member set must be attached");
            PSPropertySet displaySet = standardMembers.Members["DefaultDisplayPropertySet"] as PSPropertySet;
            Assert.IsNotNull(displaySet, "DefaultDisplayPropertySet must exist");
            CollectionAssert.AreEqual(new[] { "ComputerName", "InstanceName", "SqlInstance", "Total" }, displaySet.ReferencedPropertyNames.ToArray());
        }

        [TestMethod]
        public void SetDefaultDisplayPropertySet_FullObjectStaysAccessible()
        {
            PSObject obj = BuildObject();
            OutputHelper.SetDefaultDisplayPropertySet(obj, "ComputerName");
            Assert.AreEqual("hidden", obj.Properties["Server"].Value, "Non-display properties remain readable");
        }

        [TestMethod]
        public void SetDefaultDisplayPropertySetExcluding_OmitsOnlyExcluded()
        {
            PSObject obj = BuildObject();
            OutputHelper.SetDefaultDisplayPropertySetExcluding(obj, new[] { "Server" });

            PSMemberSet standardMembers = obj.Members["PSStandardMembers"] as PSMemberSet;
            PSPropertySet displaySet = standardMembers.Members["DefaultDisplayPropertySet"] as PSPropertySet;
            CollectionAssert.AreEqual(new[] { "ComputerName", "InstanceName", "SqlInstance", "Total" }, displaySet.ReferencedPropertyNames.ToArray());
        }

        [TestMethod]
        public void SetDefaultDisplayPropertySetExcluding_MatchesPinnedMemberKindsAndOrder()
        {
            PSObject obj = PSObject.AsPSObject(new System.Text.StringBuilder("abc"));
            obj.Properties.Add(new PSNoteProperty("Zebra", 1));
            obj.Properties.Add(new PSNoteProperty("Alpha", 2));
            obj.Properties.Add(new PSAliasProperty("Omega", "Length"));
            obj.Properties.Add(new PSCodeProperty("CodeValue", typeof(OutputHelperTest).GetMethod("GetDisplayProbeValue")));

            OutputHelper.SetDefaultDisplayPropertySetExcluding(obj, new[] { "Capacity", "MaxCapacity" });

            PSMemberSet standardMembers = (PSMemberSet)obj.Members["PSStandardMembers"];
            PSPropertySet displaySet = (PSPropertySet)standardMembers.Members["DefaultDisplayPropertySet"];
            // Pinned Get-Member filtering produces this sequence on Windows PowerShell 5.1 and 7.
            CollectionAssert.AreEqual(new[] { "Omega", "Alpha", "Zebra", "Length" }, displaySet.ReferencedPropertyNames.ToArray());
            Assert.IsNotNull(obj.Properties["CodeValue"], "Display filtering must not remove the property itself");
            Assert.AreEqual(PSMemberTypes.CodeProperty, obj.Properties["CodeValue"].MemberType);
            // ScriptProperty exclusion is covered by the positive kind mask and pinned Windows probes.
        }

        public static object GetDisplayProbeValue(PSObject value)
        {
            throw new InvalidOperationException("Display selection must not invoke property getters");
        }

        [TestMethod]
        public void SetDefaultDisplayPropertySetExcluding_DataRowExcludesInfrastructure()
        {
            System.Data.DataTable table = new System.Data.DataTable();
            table.Columns.Add("TraceFlag", typeof(int));
            System.Data.DataRow row = table.NewRow();
            row["TraceFlag"] = 3226;
            table.Rows.Add(row);

            PSObject obj = PSObject.AsPSObject(row);
            OutputHelper.SetDefaultDisplayPropertySetExcluding(obj, new string[0]);

            PSMemberSet standardMembers = obj.Members["PSStandardMembers"] as PSMemberSet;
            PSPropertySet displaySet = standardMembers.Members["DefaultDisplayPropertySet"] as PSPropertySet;
            Assert.IsFalse(displaySet.ReferencedPropertyNames.Contains("RowError"), "DataRow infrastructure properties are auto-excluded");
            Assert.IsTrue(displaySet.ReferencedPropertyNames.Contains("TraceFlag"));
        }

        [TestMethod]
        public void InsertTypeName_PrependsDbatoolsPrefixedName()
        {
            PSObject obj = BuildObject();
            OutputHelper.InsertTypeName(obj, "Example.Type");
            Assert.AreEqual("dbatools.Example.Type", obj.TypeNames[0]);
        }

        [TestMethod]
        public void AddAliasProperty_ResolvesThroughAlias()
        {
            PSObject obj = BuildObject();
            OutputHelper.AddAliasProperty(obj, "Memory", "Total");
            Assert.AreEqual(4096, obj.Properties["Memory"].Value);
        }

        // Facet (c): the ComputerName/InstanceName/SqlInstance instance-property triple.
        // AddInstanceProperties reads through SmoServerExtensions, which prefer the ETS note
        // properties Connect-DbaInstance attaches to the SMO Server (ComputerName,
        // DomainInstanceName) over live SMO reads - so a DISCONNECTED server carrying those notes
        // exercises the triple offline, no live instance required. server.ServiceName has no note
        // fallback and is unavailable on an unconnected server, so InstanceName lands null here,
        // which is exactly what distinguishes it from the two note-backed members.
        private static Server BuildDisconnectedServer(string name, string computerNameNote, string domainInstanceNote)
        {
            Server server = new Server(name);
            PSObject wrapped = PSObject.AsPSObject(server);
            if (computerNameNote != null)
                wrapped.Properties.Add(new PSNoteProperty("ComputerName", computerNameNote));
            if (domainInstanceNote != null)
                wrapped.Properties.Add(new PSNoteProperty("DomainInstanceName", domainInstanceNote));
            return server;
        }

        [TestMethod]
        public void AddInstanceProperties_AppendsTripleInOrder()
        {
            Server server = BuildDisconnectedServer("SQLPROD01", "SQLPROD01-NB", "SQLPROD01-NB\\INSTX");
            PSObject obj = new PSObject();
            OutputHelper.AddInstanceProperties(obj, server);

            string[] names = obj.Properties.Select(p => p.Name).ToArray();
            CollectionAssert.AreEqual(new[] { "ComputerName", "InstanceName", "SqlInstance" }, names,
                "AddInstanceProperties appends exactly ComputerName, InstanceName, SqlInstance in that order");
        }

        [TestMethod]
        public void AddInstanceProperties_ComputerNameHonorsNotePreference()
        {
            Server server = BuildDisconnectedServer("SQLPROD01", "SQLPROD01-NB", "SQLPROD01-NB\\INSTX");
            PSObject obj = new PSObject();
            OutputHelper.AddInstanceProperties(obj, server);
            // GetComputerName returns the ComputerName note ahead of server.Name/NetName.
            Assert.AreEqual("SQLPROD01-NB", obj.Properties["ComputerName"].Value);
        }

        [TestMethod]
        public void AddInstanceProperties_SqlInstanceHonorsDomainInstanceNote()
        {
            Server server = BuildDisconnectedServer("SQLPROD01", "SQLPROD01-NB", "SQLPROD01-NB\\INSTX");
            PSObject obj = new PSObject();
            OutputHelper.AddInstanceProperties(obj, server);
            // GetDomainInstanceName returns the DomainInstanceName note ahead of the composed fallback.
            Assert.AreEqual("SQLPROD01-NB\\INSTX", obj.Properties["SqlInstance"].Value);
        }

        [TestMethod]
        public void AddInstanceProperties_InstanceNameSourcedFromServiceName()
        {
            Server server = BuildDisconnectedServer("SQLPROD01", "SQLPROD01-NB", "SQLPROD01-NB\\INSTX");
            PSObject obj = new PSObject();
            OutputHelper.AddInstanceProperties(obj, server);
            // InstanceName is sourced from server.ServiceName, a distinct source from the two
            // note-backed members. An unconnected server reports no ServiceName, so it is null -
            // proving InstanceName is not being copied from ComputerName or SqlInstance.
            Assert.IsNull(obj.Properties["InstanceName"].Value);
            Assert.AreNotEqual(obj.Properties["ComputerName"].Value, obj.Properties["InstanceName"].Value);
        }

        [TestMethod]
        [ExpectedException(typeof(ArgumentNullException))]
        public void AddInstanceProperties_NullObjectThrows()
        {
            OutputHelper.AddInstanceProperties(null, new Server("SQLPROD01"));
        }

        [TestMethod]
        [ExpectedException(typeof(ArgumentNullException))]
        public void AddInstanceProperties_NullServerThrows()
        {
            OutputHelper.AddInstanceProperties(new PSObject(), null);
        }
    }
}
