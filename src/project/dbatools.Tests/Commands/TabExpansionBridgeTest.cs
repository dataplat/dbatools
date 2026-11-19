using System;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Dataplat.Dbatools.TabExpansion;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.TabExpansion.Test
{
    /// <summary>
    /// A minimal binary cmdlet exposing a -Database parameter. This is the command shape every
    /// flipped dbatools command now ships as, and the exact shape a FunctionInfo-typed command
    /// list used to exclude from tab completion.
    /// </summary>
    [Cmdlet("Test", "DbaTeppProbe")]
    public sealed class TestDbaTeppProbeCommand : PSCmdlet
    {
        [Parameter]
        public string Database { get; set; }

        protected override void ProcessRecord() { }
    }

    /// <summary>
    /// Direct MSTest coverage for the TabExpansionHost bridge. CalculateTabExpansion walks
    /// DbatoolsCommands to build the parameter -> TEPP script assignments that drive dbatools
    /// tab completion. When that list was typed List&lt;FunctionInfo&gt;, a CmdletInfo could never
    /// enter it, so no flipped binary cmdlet ever received a completer. Typed List&lt;CommandInfo&gt;,
    /// both binary cmdlets and legacy script functions resolve. These tests feed one of each
    /// through the real static engine and assert the assignment lands.
    /// </summary>
    [TestClass]
    public class TabExpansionBridgeTest
    {
        private static CommandInfo GetCommand(System.Management.Automation.Runspaces.Runspace runspace, string name)
        {
            using (PowerShell shell = PowerShell.Create())
            {
                shell.Runspace = runspace;
                shell.AddCommand("Get-Command").AddArgument(name);
                Collection<PSObject> result = shell.Invoke();
                return result.Count > 0 ? result[0].BaseObject as CommandInfo : null;
            }
        }

        [TestMethod]
        public void CalculateTabExpansion_AssignsCompleter_ForCmdletsAndFunctions()
        {
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry("Test-DbaTeppProbe", typeof(TestDbaTeppProbeCommand), null));
            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss))
            {
                runspace.Open();

                // A binary cmdlet - the shape every flipped dbatools command now ships as.
                CommandInfo cmdlet = GetCommand(runspace, "Test-DbaTeppProbe");
                // A legacy script function - the shape the bridge already handled.
                using (PowerShell define = PowerShell.Create())
                {
                    define.Runspace = runspace;
                    define.AddScript("function Test-DbaTeppFn { param($Database) }");
                    define.Invoke();
                }
                CommandInfo function = GetCommand(runspace, "Test-DbaTeppFn");

                Assert.IsInstanceOfType(cmdlet, typeof(CmdletInfo), "the probe must resolve as a binary cmdlet");
                Assert.IsInstanceOfType(function, typeof(FunctionInfo), "the control must resolve as a script function");

                // Isolate the shared static TEPP state so the assertion is deterministic.
                TabExpansionHost.DbatoolsCommands.Clear();
                TabExpansionHost.TabCompletionSets.Clear();

                ScriptContainer container = new ScriptContainer();
                container.Name = "TestDatabaseTepp";
                TabExpansionHost.Scripts["TestDatabaseTepp"] = container;
                TabExpansionHost.TabCompletionSets.Add(new TabCompletionSet("*", "Database", "TestDatabaseTepp"));

                // The crux: a CmdletInfo can only enter this list once it is typed CommandInfo.
                TabExpansionHost.DbatoolsCommands.Add(cmdlet);
                TabExpansionHost.DbatoolsCommands.Add(function);

                TabExpansionHost.CalculateTabExpansion();

                Assert.IsNotNull(TabExpansionHost.GetTeppScript("Test-DbaTeppProbe", "Database"),
                    "a flipped binary cmdlet's -Database parameter must receive a TEPP assignment");
                Assert.IsNotNull(TabExpansionHost.GetTeppScript("Test-DbaTeppFn", "Database"),
                    "a legacy script function's -Database parameter must still receive a TEPP assignment");
                Assert.IsNull(TabExpansionHost.GetTeppScript("Test-DbaTeppProbe", "SqlInstance"),
                    "a parameter with no registered completion set must not receive an assignment");
            }
        }
    }
}
