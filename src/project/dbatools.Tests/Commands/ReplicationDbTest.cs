using System;
using Dataplat.Dbatools.Commands;
using Dataplat.Dbatools.Message;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using DbaMessageLevel = Dataplat.Dbatools.Message.MessageLevel;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// TB-007 coverage for ReplicationDb.Connect, the C# parity port of
    /// private/functions/Connect-ReplicationDB.ps1. The helper is almost entirely live
    /// behavior (LoadProperties is a server round-trip), so the offline tests pin what is
    /// offline-observable: faults propagate UNCAUGHT (the helper has no try/catch - an
    /// unconnected ConnectionContext faults identically in both worlds) and the verbose
    /// message callback stays silent on the fault path (the helper messages only on a
    /// false return, which requires a live connection). Success and properties-not-loaded
    /// legs belong to the lab gate, like TB-003's live replication behavior.
    /// </summary>
    [TestClass]
    public class ReplicationDbTest
    {
        [TestMethod]
        public void Connect_OfflineFaultPropagatesUncaughtAndCallbackStaysSilent()
        {
            Server offline = new Server("dbatools-tests-replicationdb-offline");
            offline.ConnectionContext.ConnectTimeout = 1;
            Microsoft.SqlServer.Management.Smo.Database database = new Microsoft.SqlServer.Management.Smo.Database(offline, "dbatools_tests_repdb");
            int messages = 0;
            Action<DbaMessageLevel, string> sink = delegate (DbaMessageLevel level, string message) { messages++; };

            Exception caught = null;
            try
            {
                ReplicationDb.Connect(offline, database, sink);
            }
            catch (Exception ex)
            {
                // PS parity: the helper faults identically against an unreachable server -
                // the fault propagates uncaught in both worlds.
                caught = ex;
            }
            Assert.IsNotNull(caught, "an offline fault must propagate uncaught");
            Assert.IsFalse(caught is NullReferenceException, "the fault must be the connection failure, not a member-access bug");
            Assert.AreEqual(0, messages, "the verbose message fires only on a false LoadProperties return, never on a fault");
        }

        [TestMethod]
        public void Connect_NullArgumentsFlowLikeNonStrictPsUntilTheSharedFault()
        {
            // PS non-strict member access turns $null.Name / $null.ConnectionContext into
            // nulls; the call then faults before returning (in both worlds), with the
            // callback silent throughout. The NRE exclusion below is the discriminating
            // assertion: deleting the port's null-conditionals would surface a
            // NullReferenceException - exactly the PS-divergent outcome - and fail here.
            int messages = 0;
            Action<DbaMessageLevel, string> sink = delegate (DbaMessageLevel level, string message) { messages++; };

            Exception caught = null;
            try
            {
                ReplicationDb.Connect(null, null, sink);
            }
            catch (Exception ex)
            {
                caught = ex;
            }
            Assert.IsNotNull(caught, "a null-argument call must fault before returning in both worlds");
            Assert.IsFalse(caught is NullReferenceException, "null arguments must flow through like PS non-strict member access, not fault on member access");
            Assert.AreEqual(0, messages, "no message on the fault path");
        }
    }
}
