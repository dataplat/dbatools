using System;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// JavaScript dates use Gregorian components on every host calendar.
    /// Invalid inputs retain the established empty result.
    /// </summary>
    [TestClass]
    public class TimelineJsDateTest
    {
        private static string Convert(object inputDate)
        {
            return ConvertToDbaTimelineCommand.ConvertToJsDate(inputDate);
        }

        [TestMethod]
        public void JsDate_DocExampleAndPaddingShapes()
        {
            // Verify the established zero-based month and padded date/time fields.
            CultureInfo original = Thread.CurrentThread.CurrentCulture;
            try
            {
                Thread.CurrentThread.CurrentCulture = CultureInfo.InvariantCulture;
                // The helper doc's own example: month 8 renders as unpadded 0-based 7, the
                // time parts keep their leading zeros.
                Assert.AreEqual("new Date(2018, 7, 14, 07, 40, 42)", Convert(new DateTime(2018, 8, 14, 7, 40, 42)));
                // January is month 0; midnight keeps double zeros; day pads.
                Assert.AreEqual("new Date(2026, 0, 05, 00, 00, 09)", Convert(new DateTime(2026, 1, 5, 0, 0, 9)));
                // December is 11 - a 1-based "fix" emits 12 here and fails.
                Assert.AreEqual("new Date(2026, 11, 31, 23, 59, 59)", Convert(new DateTime(2026, 12, 31, 23, 59, 59)));
                // October: the subtraction UNPADS the month ("10" -> 9), dd/HH/mm/ss stay padded.
                Assert.AreEqual("new Date(2026, 9, 02, 13, 05, 00)", Convert(new DateTime(2026, 10, 2, 13, 5, 0)));
            }
            finally
            {
                Thread.CurrentThread.CurrentCulture = original;
            }
        }

        [TestMethod]
        public void JsDate_StringInputConvertsInvariantLikeTheDatetimeBinder()
        {
            CultureInfo original = Thread.CurrentThread.CurrentCulture;
            try
            {
                Thread.CurrentThread.CurrentCulture = CultureInfo.InvariantCulture;
                // The PS [datetime] parameter cast is a LanguagePrimitives conversion;
                // probed: an ISO-ish string binds and renders identically on both editions.
                Assert.AreEqual("new Date(2026, 6, 16, 08, 30, 00)", Convert("2026-07-16 08:30:00"));
                // The INVARIANT discriminator (opus TB-017, probe-settled): under en-GB a
                // dd/MM string still FAILS the PS binder (renders empty) because the
                // binder's conversion is invariant, not culture-current - a port passing
                // CurrentCulture to ConvertTo would parse it and fail this pin.
                Thread.CurrentThread.CurrentCulture = new CultureInfo("en-GB");
                Assert.AreEqual("", Convert("16/07/2026 08:30:00"), "the [datetime] binder parses invariant - a culture-current dd/MM string never binds");
            }
            finally
            {
                Thread.CurrentThread.CurrentCulture = original;
            }
        }

        [TestMethod]
        public void JsDate_UnconvertibleNullAndArraysRenderEmpty()
        {
            // PS: the Mandatory [datetime] cast fails statement-terminating inside the
            // calculated property and the whole field is EMPTY (probed both editions).
            Assert.AreEqual("", Convert(null));
            Assert.AreEqual("", Convert("not a date"));
            // Opus TB-017 (probe-settled): the PS binder rejects ARRAYS for the scalar
            // [datetime] exactly as it does for the [string] sibling - but unlike the
            // sibling, no explicit guard is needed here because LanguagePrimitives ALSO
            // refuses array-to-DateTime (single-element and empty both threw, both
            // editions), so the catch renders the same empty. These pins keep that true.
            Assert.AreEqual("", Convert(new object[] { new DateTime(2018, 8, 14, 7, 40, 42) }), "arrays never bind to a scalar [datetime] parameter, even single-element");
            Assert.AreEqual("", Convert(new DateTime[0]));
            Assert.AreEqual("", Convert(PSObject.AsPSObject(new object[] { new DateTime(2018, 8, 14, 7, 40, 42) })), "PSObject wrapping does not change the rejection");
        }

        [TestMethod]
        public void JsDate_ArrayStartDateRendersEmptyThroughTheRealPipeline()
        {
            // Opus TB-017: one end-to-end pin through the real cmdlet, mirroring the
            // sibling helper's hosted array pins - an array-valued StartDate must render
            // an EMPTY StartDate column in the emitted body row (PS calc-prop ground
            // truth both editions), never a fabricated new Date(...).
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry("ConvertTo-DbaTimeline", typeof(ConvertToDbaTimelineCommand), null));
            System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss);
            runspace.Open();
            try
            {
                PSObject record = new PSObject();
                record.Properties.Add(new PSNoteProperty("TypeName", "AgentJobHistory"));
                record.Properties.Add(new PSNoteProperty("SqlInstance", "srv1"));
                record.Properties.Add(new PSNoteProperty("InstanceName", "MSSQLSERVER"));
                record.Properties.Add(new PSNoteProperty("Job", "job1"));
                record.Properties.Add(new PSNoteProperty("Status", "Failed"));
                record.Properties.Add(new PSNoteProperty("StartDate", new object[] { new DateTime(2026, 1, 1, 8, 0, 0) }));
                record.Properties.Add(new PSNoteProperty("EndDate", new DateTime(2026, 1, 1, 9, 0, 0)));
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddCommand("ConvertTo-DbaTimeline").AddParameter("InputObject", new object[] { record });
                    Collection<PSObject> output = shell.Invoke();
                    Assert.AreEqual(3, output.Count, "header, body array, footer");
                    object[] body = (object[])output[1].BaseObject;
                    string bodyRow = (string)body[0];
                    // Row template: ['v','h','style',{start}, {end}], - an empty start
                    // leaves nothing between the style quote's comma and the end's comma.
                    StringAssert.Contains(bodyRow, "',, new Date(", "the array-valued StartDate renders EMPTY while EndDate still renders");
                }
            }
            finally
            {
                runspace.Dispose();
            }
        }

        [TestMethod]
        public void JsDate_UsesGregorianComponentsOnEveryHostCalendar()
        {
            CultureInfo original = Thread.CurrentThread.CurrentCulture;
            try
            {
                Thread.CurrentThread.CurrentCulture = new CultureInfo("th-TH");
                Assert.AreEqual("new Date(2018, 7, 14, 07, 40, 42)", Convert(new DateTime(2018, 8, 14, 7, 40, 42)));
                Thread.CurrentThread.CurrentCulture = new CultureInfo("ar-SA");
                Assert.AreEqual("new Date(2018, 7, 14, 07, 40, 42)", Convert(new DateTime(2018, 8, 14, 7, 40, 42)));
            }
            finally
            {
                Thread.CurrentThread.CurrentCulture = original;
            }
        }

        [TestMethod]
        public void JsDate_SqlSentinelDatesRenderOnEveryHostCalendar()
        {
            CultureInfo original = Thread.CurrentThread.CurrentCulture;
            try
            {
                Thread.CurrentThread.CurrentCulture = new CultureInfo("ar-SA");
                Assert.AreEqual("new Date(1800, 0, 01, 00, 00, 00)", Convert(new DateTime(1800, 1, 1, 0, 0, 0)));
                Assert.AreEqual("new Date(1753, 0, 01, 00, 00, 00)", Convert(new DateTime(1753, 1, 1, 0, 0, 0)), "the SQL datetime minimum sentinel");
            }
            finally
            {
                Thread.CurrentThread.CurrentCulture = original;
            }
        }
    }
}
