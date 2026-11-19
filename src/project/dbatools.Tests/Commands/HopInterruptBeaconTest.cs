using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// Two-record host for the module-scoped interrupt handoff.
    /// </summary>
    [Cmdlet("Test", "DbaHopInterruptBeacon")]
    public sealed class TestDbaHopInterruptBeaconCommand : DbaBaseCmdlet
    {
        [Parameter(ValueFromPipeline = true)]
        public int Record { get; set; }

        protected override void ProcessRecord()
        {
            if (Interrupted)
            {
                WriteObject("blocked:" + Record);
                return;
            }

            NestedCommand.InvokeScopedStreaming(this, item => WriteObject(item), Body, Record);
        }

        private const string Body = @"
param($Record)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($Record)
    if ($Record -eq 1) {
        $beacon = Get-Variable -Name '__dbatools_nested_interrupt_beacon_q7N4v2' -Scope Script -ErrorAction Stop
        $beacon.Value['Interrupted'] = $true
        $beacon.Value['CallerCommand'] = '<ScriptBlock>'
        $beacon.Value['CallerHasBoundParameters'] = $true
    }
    'processed:' + $Record
} $Record
";
    }

    /// <summary>
    /// The first record's module-scoped stop must latch the real host before record two.
    /// </summary>
    [TestClass]
    public class HopInterruptBeaconTest
    {
        [TestMethod]
        public void AModuleScopedStopBlocksTheSecondPipelineRecord()
        {
            InitialSessionState state = InitialSessionState.CreateDefault2();
            state.Commands.Add(new SessionStateCmdletEntry(
                "Test-DbaHopInterruptBeacon",
                typeof(TestDbaHopInterruptBeaconCommand),
                null));

            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(state))
            {
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddScript("New-Module -Name dbatools -ScriptBlock { } | Import-Module");
                    shell.Invoke();
                    Assert.IsFalse(shell.HadErrors, "the test dbatools module failed to import");

                    shell.Commands.Clear();
                    shell.Streams.Error.Clear();
                    shell.AddScript("1, 2 | Test-DbaHopInterruptBeacon");
                    Collection<PSObject> output = shell.Invoke();

                    List<string> actual = new List<string>();
                    foreach (PSObject item in output)
                        actual.Add(item == null ? null : item.ToString());

                    CollectionAssert.AreEqual(
                        new List<string> { "processed:1", "blocked:2" },
                        actual,
                        "record two ran after record one's module-scoped stop");
                    Assert.IsFalse(shell.HadErrors, "the interrupt probe emitted an unexpected error");
                }
            }
        }
    }
}
