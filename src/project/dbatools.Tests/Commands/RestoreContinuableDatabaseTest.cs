using System;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Dataplat.Dbatools.Commands;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// Host cmdlet for RestoreUtility.GetRestoreContinuableDatabase. The helper takes a
    /// PSCmdlet but discards it (it emits no messages); the runspace host just supplies
    /// a real invocation context to satisfy the signature. It drives the helper against
    /// an unreachable server so the post-connection version read fails.
    /// </summary>
    [Cmdlet("Test", "RestoreContinuableHost")]
    public sealed class TestRestoreContinuableHostCommand : DbaBaseCmdlet
    {
        protected override void ProcessRecord()
        {
            ServerConnection connection = new ServerConnection();
            connection.ServerInstance = "tcp:127.0.0.1,9";
            connection.ConnectTimeout = 1;
            Server server = new Server(connection);
            try
            {
                object rows = RestoreUtility.GetRestoreContinuableDatabase(this, server);
                Array arr = rows as Array;
                WriteObject("ROWS:" + (arr == null ? "notarray" : arr.Length.ToString()));
            }
            catch (Exception ex)
            {
                WriteObject("THREW:" + ex.GetType().Name);
            }
        }
    }

    /// <summary>
    /// Coverage for RestoreUtility.GetRestoreContinuableDatabase, the C# parity port of
    /// private/functions/Get-RestoreContinuableDatabase.ps1 (databases holding a
    /// redo_start_lsn, i.e. in a state for further restores). Faithfulness verified by
    /// line-by-line diff: the modern (VersionMajor &gt;= 9) SELECT is byte-identical to
    /// the source; the SQL 2000 branch differs only in inert leading whitespace (a DDL
    /// CREATE TABLE that returns no rows in either world); the .Tables flatten matches
    /// the source's $dataset.Tables.Rows member enumeration. The source wraps ONLY its
    /// Connect-DbaInstance in try/catch (Stop-Function + return on failure); that connect
    /// and its catch are performed by the compiled caller (RestoreDbaDatabaseCommand),
    /// not by this absorbed helper, which ports the post-connection portion the source
    /// leaves unwrapped - so within the ported region every failure propagates raw. The
    /// pin below guards that no-added-mask contract offline (a disconnected server's
    /// version read throws and is NOT swallowed into an empty result); the live SQL
    /// selection and row flatten require a connected instance and ride the integrator
    /// gate through Restore-DbaDatabase.
    /// </summary>
    [TestClass]
    public class RestoreContinuableDatabaseTest
    {
        [TestMethod]
        public void RestoreContinuable_DisconnectedServerThrowsUnmasked()
        {
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry("Test-RestoreContinuableHost", typeof(TestRestoreContinuableHostCommand), null));
            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss))
            {
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddCommand("Test-RestoreContinuableHost");
                    Collection<PSObject> output = shell.Invoke();
                    Assert.AreEqual(1, output.Count, "host cmdlet emits exactly one outcome record");
                    string outcome = (string)output[0].BaseObject;
                    // No error mask: the unreachable version read must surface as a throw,
                    // never be swallowed into a ROWS:0 default. The concrete SMO type is
                    // deliberately not pinned.
                    StringAssert.StartsWith(outcome, "THREW:",
                        "an unreachable server must throw, not silently return no rows");
                }
            }
        }
    }
}
