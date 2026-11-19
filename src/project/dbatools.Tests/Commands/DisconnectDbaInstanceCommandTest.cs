using System;
using System.Collections;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    public sealed class DisconnectDbaInstanceThrowingContext
    {
        public void Disconnect()
        {
            throw new InvalidOperationException("disconnect-test");
        }
    }

    public sealed class DisconnectDbaInstanceThrowingServer
    {
        public string Name => "disconnect-test";
        public DisconnectDbaInstanceThrowingContext ConnectionContext { get; } = new DisconnectDbaInstanceThrowingContext();
    }

    [TestClass]
    public class DisconnectDbaInstanceCommandTest
    {
        private sealed class Result
        {
            internal int ErrorVariableCount;
            internal int GlobalErrorCount;
            internal int EmittedErrorRecordCount;
            internal bool TargetIsNull;
        }

        private static Result Invoke(bool bindErrorVariable)
        {
            InitialSessionState state = InitialSessionState.CreateDefault2();
            state.Commands.Add(new SessionStateCmdletEntry("Disconnect-DbaInstance", typeof(DisconnectDbaInstanceCommand), null));
            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(state))
            {
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddCommand("Disconnect-DbaInstance")
                        .AddParameter("InputObject", new DisconnectDbaInstanceThrowingServer())
                        .AddParameter("Confirm", false);
                    if (bindErrorVariable)
                        shell.AddParameter("ErrorVariable", "disconnectErrors");
                    var stream = shell.Invoke();
                    ArrayList errorVariable = runspace.SessionStateProxy.GetVariable("disconnectErrors") as ArrayList;
                    ArrayList globalError = runspace.SessionStateProxy.GetVariable("Error") as ArrayList;
                    ErrorRecord record = globalError[0] as ErrorRecord;
                    return new Result
                    {
                        ErrorVariableCount = errorVariable == null ? 0 : errorVariable.Count,
                        GlobalErrorCount = globalError == null ? 0 : globalError.Count,
                        EmittedErrorRecordCount = shell.Streams.Error.Count,
                        TargetIsNull = record != null && record.TargetObject == null
                    };
                }
            }
        }

        [TestMethod]
        public void CatchPathCapturesSilentErrorAndKeepsSourceTarget()
        {
            Result result = Invoke(true);
            Assert.AreEqual(1, result.ErrorVariableCount, "-ErrorVariable must capture the silent StopFunction record");
            Assert.AreEqual(1, result.GlobalErrorCount, "the catch must still bookkeep exactly one error");
            Assert.AreEqual(0, result.EmittedErrorRecordCount, "the source contract keeps this error off the error stream");
            Assert.IsTrue(result.TargetIsNull, "the source Stop-Function call has no explicit target");
        }

        [TestMethod]
        public void CatchPathWithoutErrorVariableStillKeepsSilentBookkeeping()
        {
            Result result = Invoke(false);
            Assert.AreEqual(0, result.ErrorVariableCount);
            Assert.AreEqual(1, result.GlobalErrorCount);
            Assert.AreEqual(0, result.EmittedErrorRecordCount);
        }
    }
}
