using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// TB-013 coverage for the absorbed Convert-DbaTimelineStatusColor helper inside
    /// ConvertToDbaTimelineCommand. Expected values ground-truthed against the PS helper
    /// on both editions (probe 2026-07-16): the five status colors are case-insensitive
    /// (PS switch semantics), everything else - including the British "Cancelled" and a
    /// padded " Failed " - falls to the magenta default, and the binding-rejection shapes
    /// (null, empty string, arrays even single-element) render the Style field EMPTY, the
    /// documented lab-proven behavior of the mandatory [string]$Status calculated-property
    /// call site. SCALAR paths (and the array early-return) touch no SessionState, so a
    /// bare instance suffices for those pins only; the collection $OFS-join pins drive the
    /// REAL sealed cmdlet end-to-end in a runspace - an AgentJobHistory-shaped input
    /// through the actual MapAgentJobHistory call site, asserting on the emitted timeline
    /// body - because only an executing cmdlet has the SessionState that GetOfsSeparator
    /// reads (codex TB-013 r3: a bare instance swallows the access and defaults to a
    /// space; codex r4: do not unseal the production cmdlet for a test subclass).
    /// </summary>
    [TestClass]
    public class TimelineStatusColorTest
    {
        private static string Convert(object status)
        {
            ConvertToDbaTimelineCommand host = new ConvertToDbaTimelineCommand();
            return host.ConvertTimelineStatusColor(status);
        }

        /// <summary>Runs the REAL sealed cmdlet end-to-end: one AgentJobHistory-shaped
        /// record through the pipeline (optionally under a custom session $OFS) and returns
        /// the emitted timeline BODY string, whose third column is the Style produced by
        /// ConvertTimelineStatusColor at the production MapAgentJobHistory call site.</summary>
        private static string InvokeTimelineBody(object status, string ofs)
        {
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry("ConvertTo-DbaTimeline", typeof(ConvertToDbaTimelineCommand), null));
            System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss);
            runspace.Open();
            try
            {
                if (ofs != null)
                {
                    runspace.SessionStateProxy.SetVariable("OFS", ofs);
                }
                PSObject record = new PSObject();
                record.Properties.Add(new PSNoteProperty("TypeName", "AgentJobHistory"));
                record.Properties.Add(new PSNoteProperty("SqlInstance", "srv1"));
                record.Properties.Add(new PSNoteProperty("InstanceName", "MSSQLSERVER"));
                record.Properties.Add(new PSNoteProperty("Job", "job1"));
                record.Properties.Add(new PSNoteProperty("Status", status));
                record.Properties.Add(new PSNoteProperty("StartDate", new System.DateTime(2026, 1, 1, 8, 0, 0)));
                record.Properties.Add(new PSNoteProperty("EndDate", new System.DateTime(2026, 1, 1, 9, 0, 0)));
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddCommand("ConvertTo-DbaTimeline").AddParameter("InputObject", new object[] { record });
                    Collection<PSObject> output = shell.Invoke();
                    Assert.AreEqual(3, output.Count, "header, body array, footer");
                    object[] body = (object[])output[1].BaseObject;
                    Assert.AreEqual(1, body.Length, "one process block emits one body string");
                    return (string)body[0];
                }
            }
            finally
            {
                runspace.Dispose();
            }
        }

        private static string StyleColumn(string bodyRow)
        {
            // Body row shape: ['vLabel','hLabel','style',start, end], - take the third
            // single-quoted column so a color appearing in a label cannot false-match.
            string[] columns = bodyRow.Split('\'');
            Assert.IsTrue(columns.Length >= 6, "the row carries at least three quoted columns: " + bodyRow);
            return columns[5];
        }

        [TestMethod]
        public void StatusColor_FiveStatusesAreCaseInsensitive()
        {
            // Codex r3: every one of the five needs an alternate-casing pin, or a
            // case-SENSITIVE comparison on the untested ones would falsely pass.
            Assert.AreEqual("#FF3D3D", Convert("Failed"));
            Assert.AreEqual("#FF3D3D", Convert("failed"));
            Assert.AreEqual("#FF3D3D", Convert("FAILED"));
            Assert.AreEqual("#36B300", Convert("Succeeded"));
            Assert.AreEqual("#36B300", Convert("sUcCeEdEd"));
            Assert.AreEqual("#FFFF00", Convert("Retry"));
            Assert.AreEqual("#FFFF00", Convert("RETRY"));
            Assert.AreEqual("#C2C2C2", Convert("Canceled"));
            Assert.AreEqual("#C2C2C2", Convert("canceled"));
            Assert.AreEqual("#00CCFF", Convert("In Progress"));
            Assert.AreEqual("#00CCFF", Convert("in progress"));
            Assert.AreEqual("#00CCFF", Convert("IN PROGRESS"));
        }

        [TestMethod]
        public void StatusColor_EverythingElseIsTheMagentaDefault()
        {
            // The British spelling is NOT the American switch case - real Agent data
            // never produces it, but the pin keeps a well-meaning "fix" honest.
            Assert.AreEqual("#FF00CC", Convert("Cancelled"));
            Assert.AreEqual("#FF00CC", Convert("whatever"));
            Assert.AreEqual("#FF00CC", Convert(" Failed "), "no trimming - PS switch equality is exact apart from case");
            Assert.AreEqual("#FF00CC", Convert(true), "a non-string scalar converts to its string form (True) and misses every case");
        }

        [TestMethod]
        public void StatusColor_BindingRejectionShapesRenderEmpty()
        {
            // The PS helper's Mandatory [string]$Status REJECTS these bindings; in the
            // calculated property that error leaves the Style field EMPTY, never magenta.
            // Opus TB-013 claimed arrays DO bind via the $OFS join like other collections -
            // REFUTED by a fresh both-editions probe 2026-07-16 (opus asked for the probe):
            // single-element, multi-element and PSObject-wrapped arrays all throw
            // ParameterBindingArgumentTransformationException on the direct call, and the
            // calculated-property call site renders Style EMPTY for every array shape.
            // The binder's array/non-array asymmetry is real, however unmechanical it looks.
            Assert.AreEqual("", Convert(null));
            Assert.AreEqual("", Convert(""));
            Assert.AreEqual("", Convert(new object[] { "Failed" }), "arrays never bind to a scalar [string] parameter, even single-element");
            Assert.AreEqual("", Convert(new string[0]));
            // Opus TB-013 (adopted in narrowed form): also pin the array rejection through
            // the REAL pipeline, so the full DotAccess/PSObject path is exercised end-to-end.
            Assert.AreEqual("", StyleColumn(InvokeTimelineBody(new object[] { "Failed" }, null)), "a single-element array renders an empty Style through the real call site");
            Assert.AreEqual("", StyleColumn(InvokeTimelineBody(new object[] { "in", "progress" }, null)), "a multi-element array renders an empty Style through the real call site");
        }

        [TestMethod]
        public void StatusColor_NonArrayCollectionsBindViaTheOfsJoin()
        {
            // Codex r1: arrays are REJECTED by the scalar [string] binder, but non-array
            // collections DO bind, converting with the $OFS join (lab-proven by the
            // command's W-row; re-probed both editions 2026-07-16). Codex r3/r4: these
            // pins drive the real cmdlet end-to-end - a bare instance swallows the
            // SessionState access and defaults to a space, so it cannot distinguish a
            // real $OFS read from a hard-coded separator.
            ArrayList single = new ArrayList();
            single.Add("Succeeded");
            Assert.AreEqual("#36B300", StyleColumn(InvokeTimelineBody(single, null)), "single-element non-array collection binds and resolves");
            // The JOIN discriminator (codex r2): {"in","progress"} resolves cyan ONLY if
            // the elements space-join to "in progress" - any wrong conversion misses the
            // case and gives magenta instead. PS ground truth both editions: #00CCFF.
            System.Collections.Generic.List<string> joinParts = new System.Collections.Generic.List<string>();
            joinParts.Add("in");
            joinParts.Add("progress");
            Assert.AreEqual("#00CCFF", StyleColumn(InvokeTimelineBody(joinParts, null)), "multi-element collection OFS-joins with the default space");
        }

        [TestMethod]
        public void StatusColor_TheJoinConsultsTheSessionOfs()
        {
            // Codex r3: prove the separator comes from the session $OFS, not a hard-coded
            // space. Ground truth probed on both editions 2026-07-16 ($OFS is honored by
            // the binder's collection-to-[string] conversion, including inside the
            // calculated-property call site):
            //   $OFS = "rog": {"in p","ress"} joins to "in progress" -> #00CCFF. Only an
            //   implementation READING $OFS can produce cyan here; a hard-coded space
            //   yields "in p ress" -> magenta.
            System.Collections.Generic.List<string> glued = new System.Collections.Generic.List<string>();
            glued.Add("in p");
            glued.Add("ress");
            Assert.AreEqual("#00CCFF", StyleColumn(InvokeTimelineBody(glued, "rog")), "a custom $OFS is read from the session and used as the join separator");
            //   $OFS = ",": {"in","progress"} joins to "in,progress" and misses -> #FF00CC.
            System.Collections.Generic.List<string> commaParts = new System.Collections.Generic.List<string>();
            commaParts.Add("in");
            commaParts.Add("progress");
            Assert.AreEqual("#FF00CC", StyleColumn(InvokeTimelineBody(commaParts, ",")), "a custom $OFS breaks the space-joined match");
            // The bare-instance pin of GetOfsSeparator's swallow-and-default CATCH path -
            // outside the engine the SessionState access throws and must default to a
            // single space. Opus proposed dropping it (same expected value as the hosted
            // default), codex r6 counter-ruled and won: the VALUE coincides but the CODE
            // PATH is unique - a catch block returning "" or null fails only here, and no
            // hosted test can reach it. Not caller-reachable parity; a fallback contract.
            System.Collections.Generic.List<string> fallbackParts = new System.Collections.Generic.List<string>();
            fallbackParts.Add("in");
            fallbackParts.Add("progress");
            Assert.AreEqual("#00CCFF", Convert(fallbackParts), "engine-less fallback separator is the documented single space");
        }

        [TestMethod]
        public void StatusColor_PsObjectWrappingIsTransparent()
        {
            Assert.AreEqual("#36B300", Convert(PSObject.AsPSObject("Succeeded")));
            Assert.AreEqual("", Convert(PSObject.AsPSObject(new object[] { "Failed" })), "the array check unwraps PSObject first");
        }
    }
}
