using System;
using Dataplat.Dbatools.Commands;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// Coverage for RestoreUtility.GetPathSep, the C# parity port of
    /// private/functions/Get-DbaPathSep.ps1. Ground truth probed on both editions:
    /// PowerShell special-cases Length on $null (0 since v3), so a null server, a
    /// null PathSeparator and an empty PathSeparator all yield the default backslash
    /// there, matching this port's IsNullOrEmpty exactly; any non-empty separator
    /// passes through verbatim. Offline, two shapes are pinned: the null server
    /// (default applies) and the disconnected server (the separator read fails before
    /// the default logic - SMO's PathSeparator is read-only and needs a live
    /// connection, so a silent default here would mask a fetch failure PowerShell
    /// surfaces). The connected passthrough, including the forward slash on Linux
    /// instances, rides the integrator gate through the restore-family suites.
    /// </summary>
    [TestClass]
    public class RestoreUtilityPathSepTest
    {
        [TestMethod]
        public void PathSep_NullServerYieldsDefaultBackslash()
        {
            Assert.AreEqual("\\", RestoreUtility.GetPathSep(null));
        }

        [TestMethod]
        public void PathSep_DisconnectedServerFailsInsteadOfDefaulting()
        {
            // A defensive rewrite that catches the fetch failure and returns the
            // default would silently hand callers a backslash for a server whose real
            // separator was never read - PowerShell surfaces the same failure through
            // its property-getter wrapper. The concrete exception type belongs to SMO
            // and is deliberately not pinned.
            ServerConnection connection = new ServerConnection();
            connection.ServerInstance = "tcp:127.0.0.1,9";
            connection.ConnectTimeout = 1;
            Server server = new Server(connection);
            bool threw = false;
            try
            {
                RestoreUtility.GetPathSep(server);
            }
            catch (Exception)
            {
                threw = true;
            }
            Assert.IsTrue(threw, "a disconnected separator read must surface, never default");
        }
    }
}
