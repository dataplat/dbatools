using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>Exercises buffered and streaming script-module guard carriers.</summary>
    [Cmdlet("Test", "DbaHopScriptModuleGuard")]
    public sealed class TestDbaHopScriptModuleGuardCommand : DbaBaseCmdlet
    {
        [Parameter(Mandatory = true)]
        public string Mode { get; set; }

        [Parameter(Mandatory = true)]
        public string Body { get; set; }

        protected override void ProcessRecord()
        {
            if (string.Equals(Mode, "Streaming", StringComparison.OrdinalIgnoreCase))
            {
                NestedCommand.InvokeScopedStreaming(this, item => WriteObject(item), Body);
                return;
            }

            foreach (PSObject item in NestedCommand.InvokeScoped(this, Body))
                WriteObject(item);
        }
    }

    [TestClass]
    public class HopScriptModuleGuardTest
    {
        private const string StandardBody =
            "$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1; " +
            "& $__dbatoolsModule { 'payload' }";
        private const string ModuleFreeBody = "'payload'";
        private const string ExpectedError =
            "The dbatools script module is not loaded; Import-Module dbatools before calling Test-DbaHopScriptModuleGuard.";

        private sealed class HopResult
        {
            internal readonly List<string> Output = new List<string>();
            internal readonly List<ErrorRecord> Errors = new List<ErrorRecord>();
            internal int ErrorVariableCount;
        }

        private static HopResult Run(string mode, string body, bool importScriptModule)
        {
            HopResult result = new HopResult();
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry(
                "Test-DbaHopScriptModuleGuard",
                typeof(TestDbaHopScriptModuleGuardCommand),
                null));

            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss))
            {
                runspace.Open();
                if (importScriptModule)
                {
                    using (PowerShell importer = PowerShell.Create())
                    {
                        importer.Runspace = runspace;
                        importer.AddScript("New-Module -Name dbatools -ScriptBlock { } | Import-Module");
                        importer.Invoke();
                        Assert.AreEqual(0, importer.Streams.Error.Count, "dummy script-module import failed");
                    }
                }

                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddCommand("Test-DbaHopScriptModuleGuard")
                        .AddParameter("Mode", mode)
                        .AddParameter("Body", body)
                        .AddParameter("ErrorVariable", "guardErrors");
                    try
                    {
                        foreach (PSObject item in shell.Invoke())
                            result.Output.Add(item == null ? null : item.ToString());
                    }
                    catch (RuntimeException exception)
                    {
                        if (shell.Streams.Error.Count == 0 && exception.ErrorRecord != null)
                            result.Errors.Add(exception.ErrorRecord);
                    }
                    foreach (ErrorRecord error in shell.Streams.Error)
                        result.Errors.Add(error);
                }

                object guardErrors = runspace.SessionStateProxy.GetVariable("guardErrors");
                if (guardErrors is IList list)
                    result.ErrorVariableCount = list.Count;
                else if (guardErrors != null)
                    result.ErrorVariableCount = 1;
            }

            return result;
        }

        [DataTestMethod]
        [DataRow("Buffered")]
        [DataRow("Streaming")]
        public void StandardBodyWithoutScriptModuleThrowsActionableError(string mode)
        {
            HopResult result = Run(mode, StandardBody, false);
            Assert.AreEqual(0, result.Output.Count, "guarded body emitted payload");
            Assert.AreEqual(1, result.Errors.Count, "guard failure did not produce exactly one error");
            Assert.AreEqual(ExpectedError, result.Errors[0].Exception.Message);
            Assert.AreEqual(1, result.ErrorVariableCount, "-ErrorVariable did not contain exactly one record");
        }

        [DataTestMethod]
        [DataRow("Buffered")]
        [DataRow("Streaming")]
        public void StandardBodyRunsWithScriptModule(string mode)
        {
            HopResult result = Run(mode, StandardBody, true);
            CollectionAssert.AreEqual(new List<string> { "payload" }, result.Output);
            Assert.AreEqual(0, result.Errors.Count);
        }

        [DataTestMethod]
        [DataRow("Buffered")]
        [DataRow("Streaming")]
        public void ModuleFreeBodyRunsWithoutScriptModule(string mode)
        {
            HopResult result = Run(mode, ModuleFreeBody, false);
            CollectionAssert.AreEqual(new List<string> { "payload" }, result.Output);
            Assert.AreEqual(0, result.Errors.Count);
        }
    }
}
