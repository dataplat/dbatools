using System;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// Engine check for the shared StatementFault helper (harness-edits.md, "Operator decision: StatementFault.Surface
    /// required at caller-try sites (2026-11-02)", point 9(a)). Surface reads one engine-internal flag to tell a caller's
    /// try from a plain call, so a PowerShell release that renames it would quietly stop every caller's try from catching
    /// a port's record. These tests prove the read on both target frameworks: net472 against Windows PowerShell 5.1's
    /// engine, net8.0 against the referenced PowerShell SDK.
    /// </summary>
    [TestClass]
    public class StatementFaultEngineTest
    {
        private const string ProbeName = "Test-StatementFaultEngineProbe";

        [TestMethod]
        public void EngineFlagResolves()
        {
            Assert.IsTrue(StatementFault.EngineFlagAvailable(), "InternalCommand.Context and the engine's enclosing-try flag on its type resolve");
        }

        [TestMethod]
        public void CallerTryCatchesTheRecordAndGoesNoFurther()
        {
            Collection<PSObject> output;
            Collection<ErrorRecord> written;
            ErrorRecord surfaced;
            Run("try { " + ProbeName + "; 'after' } catch { $_ }", out output, out written, out surfaced);
            Assert.IsNotNull(surfaced, "the probe surfaced its record");
            Assert.AreEqual(1, output.Count, "the catch returns one object and 'after' never runs");
            ErrorRecord caught = output[0].BaseObject as ErrorRecord;
            Assert.IsNotNull(caught, "the catch receives an ErrorRecord");
            AssertIsTheProbeRecord(surfaced, caught);
        }

        [TestMethod]
        public void PlainCallWritesTheRecordAndGoesOn()
        {
            Collection<PSObject> output;
            Collection<ErrorRecord> written;
            ErrorRecord surfaced;
            Run(ProbeName + "; 'after'", out output, out written, out surfaced);
            Assert.IsNotNull(surfaced, "the probe surfaced its record");
            Assert.AreEqual(1, output.Count, "the next statement runs");
            Assert.AreEqual("after", output[0].BaseObject);
            Assert.AreEqual(1, written.Count, "exactly one error is written");
            AssertIsTheProbeRecord(surfaced, written[0]);
        }

        private static void AssertIsTheProbeRecord(ErrorRecord surfaced, ErrorRecord received)
        {
            Assert.AreSame(surfaced.Exception, received.Exception, "the record received is the record surfaced");
            StringAssert.StartsWith(received.FullyQualifiedErrorId, "StatementFaultEngineProbe");
            Assert.AreEqual(ErrorCategory.InvalidOperation, received.CategoryInfo.Category);
            Assert.AreEqual("probe-target", received.TargetObject);
        }

        // A runspace of its own: the script's top level is outside any try.
        private static void Run(string script, out Collection<PSObject> output, out Collection<ErrorRecord> written, out ErrorRecord surfaced)
        {
            InitialSessionState state = InitialSessionState.CreateDefault2();
            state.Commands.Add(new SessionStateCmdletEntry(ProbeName, typeof(StatementFaultEngineProbe), null));
            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(state))
            {
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddScript(script);
                    output = shell.Invoke();
                    written = shell.Streams.Error.ReadAll();
                }
                surfaced = runspace.SessionStateProxy.GetVariable(StatementFaultEngineProbe.RecordVariable) as ErrorRecord;
            }
        }
    }

    /// <summary>Surfaces one known record through the shared helper and keeps it in a variable for the test to compare.</summary>
    [Cmdlet(VerbsDiagnostic.Test, "StatementFaultEngineProbe")]
    public sealed class StatementFaultEngineProbe : PSCmdlet
    {
        internal const string RecordVariable = "StatementFaultEngineProbeRecord";

        protected override void ProcessRecord()
        {
            ErrorRecord record = new ErrorRecord(new InvalidOperationException("StatementFault engine probe"), "StatementFaultEngineProbe", ErrorCategory.InvalidOperation, "probe-target");
            SessionState.PSVariable.Set(new PSVariable(RecordVariable, record, ScopedItemOptions.None));
            StatementFault.Surface(this, record);
        }
    }
}
