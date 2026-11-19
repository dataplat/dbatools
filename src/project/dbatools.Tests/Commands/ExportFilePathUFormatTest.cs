using System;
using System.Globalization;
using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// Coverage for ExportDbaScriptCommand.FormatUFormat, the absorbed timestamp half of
    /// private/functions/Get-ExportFilePath.ps1 (TB-036). The PS
    /// source builds the export filename timestamp with
    /// Get-Date -UFormat (Get-DbatoolsConfigValue Formatting.UFormat). The shipped config
    /// default is "%Y%m%d%H%M%S", which this port renders byte-identically to Get-Date on
    /// both editions (probed 2026-07-17). Formatting.UFormat is a user-settable string, so a
    /// customized value with tokens outside {Y y m d H M S %%} diverges from Get-Date - the
    /// port emits the token literally with its %, PowerShell expands known tokens and drops
    /// the % on unknown ones. That divergence is a documented, config-reachable limitation
    /// (filed to the W1-006 owner); the characterization test below pins the CURRENT port
    /// behavior so a future change to close the gap is visible rather than silent.
    /// </summary>
    [TestClass]
    public class ExportFilePathUFormatTest
    {
        private static readonly DateTime Moment = new DateTime(2026, 3, 7, 9, 4, 5, DateTimeKind.Unspecified);

        [TestMethod]
        public void UFormat_DefaultConfigMatchesGetDate()
        {
            // Get-Date -UFormat "%Y%m%d%H%M%S" on this moment yields 20260307090405 on both
            // editions - the exact shipped-default contract the caller relies on.
            Assert.AreEqual("20260307090405", ExportDbaScriptCommand.FormatUFormat(Moment, "%Y%m%d%H%M%S"));
        }

        [TestMethod]
        public void UFormat_ImplementedTokensAndLiteralsAndPercent()
        {
            Assert.AreEqual("2026-03-07", ExportDbaScriptCommand.FormatUFormat(Moment, "%Y-%m-%d"));
            Assert.AreEqual("260307", ExportDbaScriptCommand.FormatUFormat(Moment, "%y%m%d"));
            Assert.AreEqual("09:04:05", ExportDbaScriptCommand.FormatUFormat(Moment, "%H:%M:%S"));
            // %% collapses to a single percent, matching Get-Date.
            Assert.AreEqual("100% done", ExportDbaScriptCommand.FormatUFormat(Moment, "100%% done"));
            // A trailing bare % has no following char: emitted verbatim.
            Assert.AreEqual("x%", ExportDbaScriptCommand.FormatUFormat(Moment, "x%"));
        }

        [TestMethod]
        public void UFormat_UnsupportedTokensDivergeFromGetDate_pinnedAsShipped()
        {
            // KNOWN-to-Get-Date tokens the port does not implement: Get-Date expands them
            // (%Z->"+01", %A->"Saturday", %j->"066"); the port emits the token literally.
            Assert.AreEqual("%Z", ExportDbaScriptCommand.FormatUFormat(Moment, "%Z"));
            Assert.AreEqual("%A", ExportDbaScriptCommand.FormatUFormat(Moment, "%A"));
            Assert.AreEqual("%j", ExportDbaScriptCommand.FormatUFormat(Moment, "%j"));
            // UNKNOWN-to-Get-Date token: Get-Date drops the % and emits "Q"; the port keeps "%Q".
            Assert.AreEqual("%Q", ExportDbaScriptCommand.FormatUFormat(Moment, "%Q"));
        }
    }
}
