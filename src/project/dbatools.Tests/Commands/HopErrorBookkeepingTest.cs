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
    /// Host cmdlet that drives dbatools.core's NestedCommand.RemoveDuplicateError against a
    /// $error list it seeds itself, so the de-dup rule can be exercised without a live hop.
    /// -Mode selects the shape; the emitted strings say what survived.
    /// </summary>
    [Cmdlet("Test", "DbaHopBookkeeping")]
    public sealed class TestDbaHopBookkeepingCommand : DbaBaseCmdlet
    {
        [Parameter]
        public string Mode { get; set; }

        protected override void ProcessRecord()
        {
            ArrayList errorList = SessionState.PSVariable.GetValue("Error") as ArrayList;
            errorList.Clear();

            // Two SEPARATE failures that happen to carry dbatools' bare "Failure" message -
            // the everyday case when two instances fail the same way in one pipeline.
            ErrorRecord bystander = new ErrorRecord(new Exception("Failure"), "dbatools_A", ErrorCategory.ConnectionError, "instanceA");
            ErrorRecord incoming = new ErrorRecord(new Exception("Failure"), "dbatools_B", ErrorCategory.ConnectionError, "instanceB");

            switch (Mode)
            {
                case "bufferedReal":
                    NestedCommand.InvokeScoped(
                        this,
                        "& { Write-Error 'BUFFER-A'; Write-Error 'BUFFER-B'; Write-Error 'BUFFER-C' } 2>&1");
                    WriteObject("InnerErrorCount=" + errorList.Count);
                    break;

                case "streamingReal":
                    NestedCommand.InvokeScopedStreaming(
                        this,
                        item => WriteObject(item),
                        "Write-Error 'STREAM-A'; Write-Error 'STREAM-B'; Write-Error 'STREAM-C'");
                    WriteObject("InnerErrorCount=" + errorList.Count);
                    break;

                case "unrelated":
                    // The hop produced NOTHING for this record, so $error[0] belongs to somebody
                    // else. Removing it would silently destroy an unrelated diagnostic.
                    errorList.Insert(0, bystander);
                    NestedCommand.RemoveDuplicateError(this, incoming);
                    break;

                case "sameRecord":
                    // The ordinary hop case: 2>&1 hands back the very object $error already holds.
                    errorList.Insert(0, incoming);
                    NestedCommand.RemoveDuplicateError(this, incoming);
                    break;

                case "sameException":
                    errorList.Insert(0, new ErrorRecord(incoming.Exception, "dbatools_B", ErrorCategory.ConnectionError, "instanceB"));
                    NestedCommand.RemoveDuplicateError(this, incoming);
                    break;

                case "rewrapped":
                    // Stop-Function rebuilds the record as new Exception(text, originalException),
                    // so identity survives one level down the chain.
                    errorList.Insert(0, new ErrorRecord(new Exception("Failure", incoming.Exception), "dbatools_B", ErrorCategory.ConnectionError, "instanceB"));
                    NestedCommand.RemoveDuplicateError(this, incoming);
                    break;

                case "empty":
                    NestedCommand.RemoveDuplicateError(this, incoming);
                    break;

                case "boundedEarlierRecord":
                    object boundary = new object();
                    errorList.Insert(0, boundary);
                    errorList.Insert(0, incoming);
                    errorList.Insert(0, bystander);
                    NestedCommand.RemoveHopEraDuplicateError(this, incoming, boundary);
                    break;

                case "boundedStopsAtBoundary":
                    ErrorRecord boundaryRecord = new ErrorRecord(incoming.Exception, "boundary", ErrorCategory.NotSpecified, null);
                    errorList.Insert(0, boundaryRecord);
                    errorList.Insert(0, bystander);
                    NestedCommand.RemoveHopEraDuplicateError(this, incoming, boundaryRecord);
                    break;

                case "boundedNullBaselineScansAll":
                    errorList.Insert(0, incoming);
                    errorList.Insert(0, bystander);
                    NestedCommand.RemoveHopEraDuplicateError(this, incoming, null);
                    break;

                case "boundedMissingBaselineScansAll":
                    errorList.Insert(0, incoming);
                    errorList.Insert(0, bystander);
                    NestedCommand.RemoveHopEraDuplicateError(this, incoming, new object());
                    break;

                case "boundedRemovesOnlyOne":
                    object oneBoundary = new object();
                    errorList.Insert(0, oneBoundary);
                    errorList.Insert(0, incoming);
                    errorList.Insert(0, new ErrorRecord(incoming.Exception, "duplicate", ErrorCategory.NotSpecified, null));
                    NestedCommand.RemoveHopEraDuplicateError(this, incoming, oneBoundary);
                    break;

                case "indexZeroFormUnchanged":
                    errorList.Insert(0, incoming);
                    errorList.Insert(0, bystander);
                    NestedCommand.RemoveDuplicateError(this, incoming);
                    break;
            }

            WriteObject("Count=" + errorList.Count);
            if (errorList.Count > 0)
            {
                ErrorRecord top = errorList[0] as ErrorRecord;
                WriteObject("TopId=" + (top == null ? "<none>" : top.FullyQualifiedErrorId));
                WriteObject("TopIsBystander=" + ReferenceEquals(top, bystander));
            }
        }
    }

    [TestClass]
    public class HopErrorBookkeepingTest
    {
        private static Collection<PSObject> Invoke(string mode)
        {
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry("Test-DbaHopBookkeeping", typeof(TestDbaHopBookkeepingCommand), null));
            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss))
            {
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddCommand("Test-DbaHopBookkeeping").AddParameter("Mode", mode);
                    return shell.Invoke();
                }
            }
        }

        private static List<string> Lines(string mode)
        {
            List<string> lines = new List<string>();
            foreach (PSObject item in Invoke(mode))
                lines.Add(item == null ? null : item.ToString());
            return lines;
        }

        private static List<string> StreamingLines(out int streamErrorCount, out int boundErrorCount)
        {
            return RealDrainLines("streamingReal", out streamErrorCount, out boundErrorCount);
        }

        private static List<string> RealDrainLines(string mode, out int streamErrorCount, out int boundErrorCount)
        {
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry("Test-DbaHopBookkeeping", typeof(TestDbaHopBookkeepingCommand), null));
            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss))
            {
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddCommand("Test-DbaHopBookkeeping")
                        .AddParameter("Mode", mode)
                        .AddParameter("ErrorVariable", "drainErrors")
                        .AddParameter("ErrorAction", ActionPreference.Continue);
                    Collection<PSObject> output = shell.Invoke();
                    streamErrorCount = shell.Streams.Error.Count;
                    ArrayList boundErrors = runspace.SessionStateProxy.GetVariable("drainErrors") as ArrayList;
                    boundErrorCount = boundErrors == null ? 0 : boundErrors.Count;
                    List<string> lines = new List<string>();
                    foreach (PSObject item in output)
                        lines.Add(item == null ? null : item.ToString());
                    return lines;
                }
            }
        }

        /// <summary>
        /// The regression this rule exists for. Message-text equality used to be the third match
        /// arm, so an unrelated record whose exception happened to read "Failure" was dequeued in
        /// place of the hop's own - the duplicate stayed and somebody else's diagnostic vanished.
        /// </summary>
        [TestMethod]
        public void UnrelatedRecordWithTheSameMessageIsNotRemoved()
        {
            List<string> lines = Lines("unrelated");
            CollectionAssert.Contains(lines, "Count=1");
            CollectionAssert.Contains(lines, "TopIsBystander=True");
            CollectionAssert.Contains(lines, "TopId=dbatools_A");
        }

        [TestMethod]
        public void TheHopsOwnRecordIsRemoved()
        {
            CollectionAssert.Contains(Lines("sameRecord"), "Count=0");
        }

        [TestMethod]
        public void ARecordSharingTheExceptionObjectIsRemoved()
        {
            CollectionAssert.Contains(Lines("sameException"), "Count=0");
        }

        [TestMethod]
        public void ARewrappedRecordIsStillRecognized()
        {
            CollectionAssert.Contains(Lines("rewrapped"), "Count=0");
        }

        [TestMethod]
        public void AnEmptyErrorListIsLeftAlone()
        {
            CollectionAssert.Contains(Lines("empty"), "Count=0");
        }

        [TestMethod]
        public void BoundedScanRemovesAnEarlierHopRecord()
        {
            CollectionAssert.Contains(Lines("boundedEarlierRecord"), "Count=2");
        }

        [TestMethod]
        public void BoundedScanStopsBeforeThePreHopHead()
        {
            CollectionAssert.Contains(Lines("boundedStopsAtBoundary"), "Count=2");
        }

        [TestMethod]
        public void NullBaselineScansTheWholeList()
        {
            CollectionAssert.Contains(Lines("boundedNullBaselineScansAll"), "Count=1");
        }

        [TestMethod]
        public void MissingBaselineScansTheWholeList()
        {
            CollectionAssert.Contains(Lines("boundedMissingBaselineScansAll"), "Count=1");
        }

        [TestMethod]
        public void BoundedScanRemovesOnlyOneDuplicate()
        {
            CollectionAssert.Contains(Lines("boundedRemovesOnlyOne"), "Count=2");
        }

        [TestMethod]
        public void ExistingIndexZeroHelperRemainsIndexZeroOnly()
        {
            CollectionAssert.Contains(Lines("indexZeroFormUnchanged"), "Count=2");
        }

        [TestMethod]
        public void RealStreamingDrainCharacterizesErrorBookkeeping()
        {
            List<string> lines = StreamingLines(out int streamErrorCount, out int boundErrorCount);
            CollectionAssert.Contains(lines, "InnerErrorCount=3");
            Assert.AreEqual(3, streamErrorCount);
            Assert.AreEqual(3, boundErrorCount);
        }

        [TestMethod]
        public void RealBufferedDrainDoesNotDoubleBookErrors()
        {
            List<string> lines = RealDrainLines("bufferedReal", out int streamErrorCount, out int boundErrorCount);
            Assert.AreEqual(3, streamErrorCount);
            Assert.AreEqual(3, boundErrorCount);
            Assert.IsTrue(lines.Contains("InnerErrorCount=3"), "output=" + string.Join("|", lines));
        }

        [TestMethod]
        public void IsSameFailureNeverMatchesOnMessageTextAlone()
        {
            ErrorRecord left = new ErrorRecord(new Exception("Failure"), "dbatools_A", ErrorCategory.ConnectionError, "a");
            ErrorRecord right = new ErrorRecord(new Exception("Failure"), "dbatools_B", ErrorCategory.ConnectionError, "b");
            Assert.IsFalse(NestedCommand.IsSameFailure(left, right));
        }

        [TestMethod]
        public void IsSameFailureMatchesEitherDirectionOfTheExceptionChain()
        {
            Exception inner = new Exception("Failure");
            ErrorRecord bare = new ErrorRecord(inner, "dbatools_A", ErrorCategory.ConnectionError, "a");
            ErrorRecord wrapped = new ErrorRecord(new Exception("Failure", inner), "dbatools_A", ErrorCategory.ConnectionError, "a");
            Assert.IsTrue(NestedCommand.IsSameFailure(bare, wrapped));
            Assert.IsTrue(NestedCommand.IsSameFailure(wrapped, bare));
        }

        /// <summary>
        /// The chain walk is bounded, so identity buried deeper than the bound reads as "not the
        /// same failure" rather than as an unbounded walk. Real hop rewrapping is one level deep;
        /// the bound exists so a pathological chain cannot make bookkeeping the slow part.
        /// </summary>
        [TestMethod]
        public void IsSameFailureStopsWalkingAtTheChainBound()
        {
            Exception target = new Exception("Failure");
            Exception chain = target;
            for (int depth = 0; depth < 64; depth++)
                chain = new Exception("wrap " + depth, chain);

            ErrorRecord deep = new ErrorRecord(chain, "dbatools_A", ErrorCategory.ConnectionError, "a");
            ErrorRecord shallow = new ErrorRecord(target, "dbatools_B", ErrorCategory.ConnectionError, "b");
            Assert.IsFalse(NestedCommand.IsSameFailure(deep, shallow));

            Exception oneDeep = new Exception("wrap", target);
            ErrorRecord wrapped = new ErrorRecord(oneDeep, "dbatools_A", ErrorCategory.ConnectionError, "a");
            Assert.IsTrue(NestedCommand.IsSameFailure(wrapped, shallow));
        }
    }
}
