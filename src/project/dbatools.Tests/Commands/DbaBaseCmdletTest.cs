using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// Host cmdlet exposing the DbaBaseCmdlet TestBound family plus the resolved
    /// EnableException value. Declares three real parameters so the binder populates
    /// MyInvocation.BoundParameters exactly as a live cmdlet would.
    /// </summary>
    [Cmdlet("Test", "DbaBaseBound")]
    public sealed class TestDbaBaseBoundCommand : DbaBaseCmdlet
    {
        [Parameter]
        public string Alpha { get; set; }

        [Parameter]
        public string Beta { get; set; }

        [Parameter]
        public SwitchParameter Gamma { get; set; }

        protected override void ProcessRecord()
        {
            WriteObject("BoundAlpha=" + TestBound("Alpha"));
            WriteObject("BoundMissing=" + TestBound("Missing"));
            WriteObject("AnyMissingOrBeta=" + TestBound("Missing", "Beta"));
            WriteObject("AllAlphaBeta=" + TestBoundAll("Alpha", "Beta"));
            WriteObject("AllAlphaMissing=" + TestBoundAll("Alpha", "Missing"));
            WriteObject("EnableException=" + EnableException.ToBool());
        }
    }

    /// <summary>
    /// Host cmdlet that drives StopFunction through each branch of the Stop-Function truth
    /// table (architecture.md section 2.3) selected by -Mode. Any record emitted AFTER the
    /// StopFunction call proves that call did NOT terminate; its absence proves it did.
    /// </summary>
    [Cmdlet("Test", "DbaBaseStop")]
    public sealed class TestDbaBaseStopCommand : DbaBaseCmdlet
    {
        [Parameter]
        public string Mode { get; set; }

        protected override void ProcessRecord()
        {
            switch (Mode)
            {
                case "plain":
                    StopFunction("boom");
                    break;
                case "continue":
                    StopFunction("boom", continueLoop: true);
                    break;
                case "absorbed":
                    StopFunction("boom", interruptCallerScope: false);
                    break;
                case "silentlyContinue":
                    StopFunction("boom", silentlyContinue: true);
                    break;
                default:
                    throw new ArgumentException("unknown mode " + Mode);
            }

            // Reached only when StopFunction RETURNED (did not throw a terminating error).
            WriteObject("Interrupted=" + Interrupted);

            ArrayList errorList = SessionState.PSVariable.GetValue("Error") as ArrayList;
            WriteObject("ErrorCount=" + (errorList == null ? -1 : errorList.Count));
        }
    }

    /// <summary>
    /// Direct MSTest coverage for DbaBaseCmdlet - the mandatory base of every ported cmdlet,
    /// which previously had none (only test-host stubs inheriting it to exercise other code).
    /// Each test registers a host cmdlet in a default runspace and invokes it, asserting on the
    /// emitted records, warning stream and error stream. Covers: TestBound/TestBound(any)/
    /// TestBoundAll, EnableException dispatch, and the StopFunction truth table - plain warn+
    /// set Interrupted+$error insertion, -Continue not interrupting, absorbed-helper scope not
    /// interrupting, EnableException terminating, and EnableException+SilentlyContinue writing a
    /// non-terminating error without interrupting.
    /// </summary>
    [TestClass]
    public class DbaBaseCmdletTest
    {
        private sealed class RunResult
        {
            public Collection<PSObject> Output = new Collection<PSObject>();
            public List<string> Warnings = new List<string>();
            public List<string> Errors = new List<string>();
            public bool HadErrors;
            public bool Threw;

            public bool HasRecord(string text)
            {
                foreach (PSObject item in Output)
                {
                    if (item != null && String.Equals(item.BaseObject as string, text, StringComparison.Ordinal))
                        return true;
                }
                return false;
            }

            public bool AnyRecordStartsWith(string prefix)
            {
                foreach (PSObject item in Output)
                {
                    string value = item == null ? null : item.BaseObject as string;
                    if (value != null && value.StartsWith(prefix, StringComparison.Ordinal))
                        return true;
                }
                return false;
            }
        }

        private static RunResult Invoke(Type cmdletType, string name, IDictionary<string, object> parameters)
        {
            RunResult result = new RunResult();
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry(name, cmdletType, null));
            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss))
            {
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddCommand(name);
                    if (parameters != null)
                    {
                        foreach (KeyValuePair<string, object> pair in parameters)
                        {
                            if (pair.Value is bool)
                            {
                                if ((bool)pair.Value)
                                    shell.AddParameter(pair.Key); // switch parameter
                            }
                            else
                            {
                                shell.AddParameter(pair.Key, pair.Value);
                            }
                        }
                    }
                    try
                    {
                        result.Output = shell.Invoke();
                    }
                    catch (Exception ex)
                    {
                        // A terminating error (ThrowTerminatingError) surfaces out of Invoke() as a
                        // thrown exception rather than landing in Streams.Error, so record it here.
                        result.Threw = true;
                        result.Errors.Add(ex.ToString());
                    }
                    result.HadErrors = shell.HadErrors;
                    foreach (WarningRecord warning in shell.Streams.Warning)
                        result.Warnings.Add(warning.Message);
                    foreach (ErrorRecord error in shell.Streams.Error)
                        result.Errors.Add(error.ToString());
                }
            }
            return result;
        }

        [TestMethod]
        public void TestBound_ReflectsExactlyTheBoundParameters()
        {
            RunResult result = Invoke(typeof(TestDbaBaseBoundCommand), "Test-DbaBaseBound",
                new Dictionary<string, object> { { "Alpha", "x" }, { "Beta", "y" } });

            Assert.IsFalse(result.Threw, "binding probe must not throw");
            Assert.IsTrue(result.HasRecord("BoundAlpha=True"), "Alpha was bound");
            Assert.IsTrue(result.HasRecord("BoundMissing=False"), "Missing was not bound");
            Assert.IsTrue(result.HasRecord("AnyMissingOrBeta=True"), "TestBound(any) true because Beta was bound");
            Assert.IsTrue(result.HasRecord("AllAlphaBeta=True"), "TestBoundAll true because both bound");
            Assert.IsTrue(result.HasRecord("AllAlphaMissing=False"), "TestBoundAll false because Missing unbound");
        }

        [TestMethod]
        public void EnableException_DefaultsFalse_WhenNotBound()
        {
            RunResult result = Invoke(typeof(TestDbaBaseBoundCommand), "Test-DbaBaseBound",
                new Dictionary<string, object> { { "Alpha", "x" } });

            Assert.IsTrue(result.HasRecord("EnableException=False"), "EnableException defaults to False");
        }

        [TestMethod]
        public void EnableException_TrueWhenBound()
        {
            RunResult result = Invoke(typeof(TestDbaBaseBoundCommand), "Test-DbaBaseBound",
                new Dictionary<string, object> { { "Alpha", "x" }, { "EnableException", true } });

            Assert.IsTrue(result.HasRecord("EnableException=True"), "EnableException reads the bound switch");
        }

        [TestMethod]
        public void StopFunction_Plain_WarnsSetsInterruptedAndInsertsError()
        {
            RunResult result = Invoke(typeof(TestDbaBaseStopCommand), "Test-DbaBaseStop",
                new Dictionary<string, object> { { "Mode", "plain" } });

            Assert.IsFalse(result.Threw, "without EnableException the plain path must warn-and-continue, not throw");
            Assert.IsTrue(result.HasRecord("Interrupted=True"), "the plain path sets the Interrupted flag");
            Assert.IsTrue(result.Warnings.Exists(w => w.Contains("boom")), "the failure surfaces on the warning stream");
            Assert.IsTrue(result.HasRecord("ErrorCount=1"), "the record is inserted into $error exactly once");
        }

        [TestMethod]
        public void StopFunction_ContinueLoop_DoesNotInterrupt()
        {
            RunResult result = Invoke(typeof(TestDbaBaseStopCommand), "Test-DbaBaseStop",
                new Dictionary<string, object> { { "Mode", "continue" } });

            Assert.IsFalse(result.Threw, "-Continue equivalent does not throw without EnableException");
            Assert.IsTrue(result.HasRecord("Interrupted=False"), "-Continue leaves Interrupted false so the loop proceeds");
        }

        [TestMethod]
        public void StopFunction_AbsorbedHelperScope_DoesNotInterrupt()
        {
            RunResult result = Invoke(typeof(TestDbaBaseStopCommand), "Test-DbaBaseStop",
                new Dictionary<string, object> { { "Mode", "absorbed" } });

            Assert.IsFalse(result.Threw, "an absorbed-helper StopFunction does not throw without EnableException");
            Assert.IsTrue(result.HasRecord("Interrupted=False"),
                "interruptCallerScope:false mirrors a helper writing its stop flag to a scope the command never reads");
        }

        [TestMethod]
        public void StopFunction_DirectAndAbsorbedHelperScopesLatchDifferently()
        {
            RunResult direct = Invoke(typeof(TestDbaBaseStopCommand), "Test-DbaBaseStop",
                new Dictionary<string, object> { { "Mode", "plain" } });
            RunResult absorbed = Invoke(typeof(TestDbaBaseStopCommand), "Test-DbaBaseStop",
                new Dictionary<string, object> { { "Mode", "absorbed" } });

            Assert.IsTrue(direct.HasRecord("Interrupted=True"),
                "a direct StopFunction call must latch the command");
            Assert.IsTrue(absorbed.HasRecord("Interrupted=False"),
                "interruptCallerScope:false must preserve the absorbed-helper boundary");
        }

        [TestMethod]
        public void StopFunction_EnableException_Terminates()
        {
            RunResult result = Invoke(typeof(TestDbaBaseStopCommand), "Test-DbaBaseStop",
                new Dictionary<string, object> { { "Mode", "plain" }, { "EnableException", true } });

            Assert.IsFalse(result.AnyRecordStartsWith("Interrupted="),
                "under EnableException the plain path throws a terminating error before any later record is emitted");
            Assert.IsTrue(result.Threw || result.HadErrors, "the terminating error surfaces to the caller");
            Assert.IsTrue(result.Errors.Exists(e => e.Contains("boom")), "the terminating error carries the failure message");
        }

        [TestMethod]
        public void StopFunction_EnableExceptionSilentlyContinue_WritesErrorWithoutTerminating()
        {
            RunResult result = Invoke(typeof(TestDbaBaseStopCommand), "Test-DbaBaseStop",
                new Dictionary<string, object> { { "Mode", "silentlyContinue" }, { "EnableException", true } });

            Assert.IsFalse(result.Threw, "EnableException + SilentlyContinue writes a non-terminating error and continues");
            Assert.IsTrue(result.HasRecord("Interrupted=False"), "the SilentlyContinue path leaves Interrupted false");
            Assert.IsTrue(result.Errors.Count >= 1, "a visible non-terminating error is written");
        }
    }
}
