using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// Command-level coverage for the absorbed Test-ExportDirectory helper
    /// (ExportDbaScriptCommand.TestExportDirectory). The helper runs in the command's
    /// begin block BEFORE any pipeline object is scripted, so piping a dummy object and
    /// pointing -Path at a real filesystem target exercises the helper directly without
    /// any SMO input. Behavior ground-truthed against the PS source Test-ExportDirectory
    /// on PS 5.1 and 7.6 (probe 2026-07-17, identical both editions): a missing path is
    /// created as a directory; an existing directory is a no-op; an existing FILE stops
    /// with "must be a directory". The two runtime pins below drive the real compiled
    /// command for the create-missing and reject-file branches. Documented minor
    /// divergence, unreachable for normal export dirs: ProviderPathExists writes an error
    /// for any provider exception where Test-Path would silently return false (malformed
    /// path / bad drive); the happy branches match.
    /// </summary>
    [TestClass]
    public class TestExportDirectoryTest
    {
        private static System.Management.Automation.Runspaces.Runspace NewRunspace()
        {
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry("Export-DbaScript", typeof(ExportDbaScriptCommand), null));
            System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss);
            runspace.Open();
            return runspace;
        }

        [TestMethod]
        public void TestExportDirectory_MissingPathIsCreated()
        {
            string dir = Path.Combine(Path.GetTempPath(), "ted-" + Guid.NewGuid().ToString("N"));
            Assert.IsFalse(Directory.Exists(dir), "precondition: path does not exist");
            try
            {
                using (System.Management.Automation.Runspaces.Runspace runspace = NewRunspace())
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    // A dummy pipeline object satisfies the mandatory VFP InputObject; the
                    // begin-block Test-ExportDirectory runs first and creates the directory.
                    // Any downstream failure scripting the dummy string is irrelevant here.
                    shell.AddScript("'x' | Export-DbaScript -Path $args[0]").AddArgument(dir);
                    shell.Invoke();
                }
                Assert.IsTrue(Directory.Exists(dir), "the missing -Path was created as a directory");
            }
            finally
            {
                if (Directory.Exists(dir))
                    Directory.Delete(dir, recursive: true);
            }
        }

        [TestMethod]
        public void TestExportDirectory_ExistingFileStopsWithMessage()
        {
            string file = Path.Combine(Path.GetTempPath(), "ted-" + Guid.NewGuid().ToString("N") + ".txt");
            File.WriteAllText(file, "x");
            try
            {
                using (System.Management.Automation.Runspaces.Runspace runspace = NewRunspace())
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    // An in-PowerShell try/catch proves the begin-block Stop-Function under
                    // -EnableException actually TERMINATED (a non-terminating error would fall
                    // to NO-CATCH and fail the assertion). The dummy is never scripted because
                    // the interrupt fires first.
                    shell.AddScript(
                        "try { 'x' | Export-DbaScript -Path $args[0] -EnableException; 'NO-CATCH' } " +
                        "catch { 'CAUGHT:' + $_.Exception.Message }").AddArgument(file);
                    Collection<PSObject> output = shell.Invoke();
                    Assert.AreEqual(1, output.Count, "the script emits exactly one outcome record");
                    string outcome = (string)output[0].BaseObject;
                    StringAssert.StartsWith(outcome, "CAUGHT:", "the -EnableException stop must terminate and be caught");
                    StringAssert.Contains(outcome, "must be a directory", "the stop reports the directory requirement");
                }
            }
            finally
            {
                File.Delete(file);
            }
        }

        /// <summary>
        /// Friendly mode (no -EnableException) against an existing FILE must WARN AND CONTINUE,
        /// not stop. Stop-Function writes its flag with Set-Variable -Scope 1 — the scope of
        /// Test-ExportDirectory, the helper — while Test-FunctionInterrupt reads -Scope 1 from
        /// Export-DbaScript's scope. The flag is therefore written where nobody reads it and
        /// dies with the helper, so begin finishes and process runs. Absorbing the helper into
        /// a C# method erased that scope boundary and the instance-level flag halted the
        /// command (the bug this pins). The distinguishing signal is the SECOND warning: the
        /// non-SMO 'x' can only reach the "not a SQL Management Object" branch in the process
        /// block if the command survived begin. A latched interrupt yields only the first.
        /// </summary>
        [TestMethod]
        public void TestExportDirectory_ExistingFileFriendlyModeWarnsAndContinues()
        {
            string file = Path.Combine(Path.GetTempPath(), "ted-" + Guid.NewGuid().ToString("N") + ".txt");
            File.WriteAllText(file, "x");
            try
            {
                using (System.Management.Automation.Runspaces.Runspace runspace = NewRunspace())
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddScript("'x' | Export-DbaScript -Path $args[0]").AddArgument(file);
                    shell.Invoke();

                    string warnings = string.Join("\n", shell.Streams.Warning);
                    StringAssert.Contains(warnings, "must be a directory",
                        "friendly mode still reports the directory requirement");
                    StringAssert.Contains(warnings, "not a SQL Management Object",
                        "process MUST run: the helper's stop flag dies in the helper's scope, so " +
                        "the command continues past begin and reaches the non-SMO branch");
                }
            }
            finally
            {
                File.Delete(file);
            }
        }

        /// <summary>
        /// -WhatIf must create NOTHING. The source creates the directory with New-Item, which
        /// supports ShouldProcess, and $WhatIfPreference propagates from the SupportsShouldProcess
        /// caller into the helper's scope — so under -WhatIf New-Item only reports. The port used
        /// a bare Directory.CreateDirectory, which has no such gate and created the directory the
        /// source merely described (the bug this pins). Asserted as the ABSENCE of the side
        /// effect, not as an output string.
        /// </summary>
        [TestMethod]
        public void TestExportDirectory_WhatIfCreatesNothing()
        {
            string dir = Path.Combine(Path.GetTempPath(), "ted-" + Guid.NewGuid().ToString("N"));
            Assert.IsFalse(Directory.Exists(dir), "precondition: path does not exist");
            try
            {
                using (System.Management.Automation.Runspaces.Runspace runspace = NewRunspace())
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddScript("'x' | Export-DbaScript -Path $args[0] -WhatIf").AddArgument(dir);
                    shell.Invoke();
                }
                Assert.IsFalse(Directory.Exists(dir),
                    "-WhatIf must not create the export directory; New-Item honors WhatIfPreference");
            }
            finally
            {
                if (Directory.Exists(dir))
                    Directory.Delete(dir, recursive: true);
            }
        }
    }
}
