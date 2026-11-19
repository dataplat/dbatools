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
    /// Host cmdlet that runs a one-line hop through NestedCommand.InvokeScopedStreaming so the
    /// merged information stream (6&gt;&amp;1) can be observed on the host's own channels.
    /// </summary>
    [Cmdlet("Test", "DbaHopInformation")]
    public sealed class TestDbaHopInformationCommand : DbaBaseCmdlet
    {
        [Parameter]
        public string Body { get; set; }

        protected override void ProcessRecord()
        {
            NestedCommand.InvokeScopedStreaming(this, item => WriteObject(item), Body);
        }
    }

    /// <summary>
    /// The hop relays a nested pipeline's information records to the host instead of letting them
    /// fall through to the output pipeline. The relay reaches WriteInformation by reflection
    /// because the type and the method both postdate the System.Management.Automation 3.0.0.0
    /// surface the net472 build targets, and a typed reference inside the stream handler would
    /// fail to jit the whole handler on a Windows PowerShell 3.0/4.0 host. These tests pin the
    /// PS 5+ behavior the reflection route has to keep identical.
    /// </summary>
    [TestClass]
    public class HopInformationStreamTest
    {
        private sealed class HopResult
        {
            internal List<string> Output = new List<string>();
            internal List<object> InformationMessages = new List<object>();
            internal List<List<string>> InformationTags = new List<List<string>>();
        }

        private static HopResult Run(string body)
        {
            HopResult result = new HopResult();
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry("Test-DbaHopInformation", typeof(TestDbaHopInformationCommand), null));
            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss))
            {
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddCommand("Test-DbaHopInformation").AddParameter("Body", body);
                    foreach (PSObject item in shell.Invoke())
                        result.Output.Add(item == null ? null : item.ToString());
                    foreach (InformationRecord record in shell.Streams.Information)
                    {
                        result.InformationMessages.Add(record.MessageData);
                        result.InformationTags.Add(new List<string>(record.Tags));
                    }
                }
            }

            return result;
        }

        [TestMethod]
        public void AnInformationRecordIsRelayedToTheHostInformationStream()
        {
            HopResult result = Run("Write-Information -MessageData 'hop-info' -Tags 'alpha'");
            Assert.AreEqual(1, result.InformationMessages.Count, "the hop's information record did not reach the host information stream");
            Assert.AreEqual("hop-info", result.InformationMessages[0].ToString());
        }

        [TestMethod]
        public void TheRecordsTagsSurviveTheRelay()
        {
            HopResult result = Run("Write-Information -MessageData 'tagged' -Tags 'alpha','beta'");
            Assert.AreEqual(1, result.InformationTags.Count);
            CollectionAssert.Contains(result.InformationTags[0], "alpha");
            CollectionAssert.Contains(result.InformationTags[0], "beta");
        }

        /// <summary>
        /// The nested run merges 6&gt;&amp;1, so without the relay the record would arrive as
        /// pipeline output and pollute the command's own result set.
        /// </summary>
        [TestMethod]
        public void AnInformationRecordDoesNotLeakIntoPipelineOutput()
        {
            HopResult result = Run("Write-Information -MessageData 'hop-info' -Tags 'alpha'; 'payload'");
            CollectionAssert.AreEqual(new List<string> { "payload" }, result.Output);
        }

        /// <summary>
        /// Write-Host is the information stream's most common producer, and it wraps a
        /// HostInformationMessage rather than the plain record - the relay probes the type
        /// hierarchy so a derived or wrapped payload still routes to the information channel.
        /// </summary>
        [TestMethod]
        public void WriteHostOutputIsRelayedRatherThanReturnedAsOutput()
        {
            HopResult result = Run("Write-Host 'from-write-host'; 'payload'");
            CollectionAssert.AreEqual(new List<string> { "payload" }, result.Output);
            Assert.AreEqual(1, result.InformationMessages.Count, "Write-Host's record did not reach the host information stream");
        }
    }
}
