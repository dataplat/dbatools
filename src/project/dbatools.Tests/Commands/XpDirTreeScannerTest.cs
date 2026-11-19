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
    /// Host cmdlet for XpDirTreeScanner.Scan. Drives the scanner with an s3:// path so the
    /// s3 branch decides the outcome. The disconnected server handed in is never actually
    /// reached: with EnableException the s3 Stop-Function throws first; without it, a
    /// deterministic Test-DbaPath stub (registered by the test) throws a unique marker at
    /// the first accessibility check, which sits AFTER the s3 branch and BEFORE any server
    /// I/O - so the marker proves the s3 guard was non-terminating without depending on the
    /// unreachable server's failure type.
    /// </summary>
    [Cmdlet("Test", "XpDirTreeScannerHost")]
    public sealed class TestXpDirTreeScannerHostCommand : DbaBaseCmdlet
    {
        [Parameter(Mandatory = true)]
        public string Path { get; set; }

        [Parameter]
        public SwitchParameter Enable { get; set; }

        protected override void ProcessRecord()
        {
            ServerConnection connection = new ServerConnection();
            connection.ServerInstance = "tcp:127.0.0.1,9";
            connection.ConnectTimeout = 1;
            Server server = new Server(connection);
            try
            {
                System.Collections.Generic.List<PSObject> rows =
                    XpDirTreeScanner.Scan(this, server, Path, noRecurse: false, enableException: Enable.IsPresent);
                WriteObject("ROWS:" + rows.Count);
            }
            catch (Exception ex)
            {
                string message = ex.Message.Split('\n')[0];
                WriteObject("THREW:" + ex.GetType().Name + ":" + message);
            }
        }
    }

    /// <summary>
    /// Coverage for XpDirTreeScanner.Scan, the C# parity port of
    /// private/functions/Get-XpDirTreeRestoreFile.ps1 (recursive xp_dirtree backup-file
    /// enumeration). Faithfulness verified by line-by-line diff: the path-separator
    /// branching (case-insensitive https?:// -&gt; "/", s3:// -&gt; reject, else the SMO
    /// PathSeparator) matches; the .bak/.trn suffix guard and trailing-separator append
    /// match; the source's doubled Test-DbaPath check is preserved; the version-branch SQL
    /// (&gt;=14 dm_os_enumerate_filesystem, &lt;9 xp_dirtree, else sys.xp_dirtree) matches
    /// with a sanctioned BP-101 change (the user path binds as a typed @path SqlParameter
    /// instead of the source's string interpolation - semantic parity, injection-hardened);
    /// a DBNull file flag is skipped, matching the source's Where-Object no-match; and the
    /// recursion drops EnableException and NoRecurse exactly as the source does. The live
    /// enumeration and recursion require a SQL instance and ride the integrator gate through
    /// Get-DbaBackupInformation. The offline pins below are method-specific and cover the
    /// s3 branch's terminating-vs-non-terminating contract without a live server.
    /// </summary>
    [TestClass]
    public class XpDirTreeScannerTest
    {
        // A Test-DbaPath stub that throws a marker, letting the tests observe whether
        // control reached the first accessibility check (which sits just after the s3
        // branch) independently of the unreachable server's failure type.
        private const string TestPathMarker = "XPDIR_REACHED_TESTDBAPATH";

        private static string Invoke(string path, bool enable)
        {
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry("Test-XpDirTreeScannerHost", typeof(TestXpDirTreeScannerHostCommand), null));
            iss.Commands.Add(new SessionStateFunctionEntry("Test-DbaPath",
                "param($SqlInstance, $Path) throw '" + TestPathMarker + "'"));
            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss))
            {
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddCommand("Test-XpDirTreeScannerHost").AddParameter("Path", path);
                    if (enable)
                        shell.AddParameter("Enable");
                    Collection<PSObject> output = shell.Invoke();
                    Assert.AreEqual(1, output.Count, "host cmdlet emits exactly one outcome record");
                    return (string)output[0].BaseObject;
                }
            }
        }

        [TestMethod]
        public void XpDirTree_S3WithEnableExceptionTerminatesAtGuardBeforeTestDbaPath()
        {
            // With EnableException the s3 Stop-Function throws immediately, before the
            // accessibility check. The outcome must carry the s3-specific message and must
            // NOT be the Test-DbaPath marker (control never reached it).
            string outcome = Invoke("s3://bucket/backups/", enable: true);
            StringAssert.StartsWith(outcome, "THREW:InnerCommandException:", "the s3 guard throws under EnableException");
            StringAssert.Contains(outcome, "S3 path enumeration not supported", "the terminating error is the s3 guard's");
            Assert.IsFalse(outcome.Contains(TestPathMarker), "the s3 guard must terminate before Test-DbaPath");
        }

        [TestMethod]
        public void XpDirTree_S3WithoutEnableExceptionFallsThroughToTestDbaPath()
        {
            // Without EnableException the s3 Stop-Function is non-terminating: execution
            // falls through the path-separator block (pathSep stays null, the append is
            // skipped) and reaches the first Test-DbaPath check, whose stub throws the
            // marker. Observing the marker proves the s3 guard did NOT terminate the scan
            // and that control advanced past it - independent of the server.
            string outcome = Invoke("s3://bucket/backups/", enable: false);
            StringAssert.Contains(outcome, TestPathMarker, "control must reach Test-DbaPath when EnableException is off");
        }
    }
}
