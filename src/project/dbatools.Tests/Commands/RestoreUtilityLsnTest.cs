using System;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// Host cmdlet for RestoreUtility.ConvertDbaLsn: the helper needs a live PSCmdlet for
    /// its Write-Message/Stop-Function plumbing (InnerCommand routes through the host's
    /// streams), so the tests run it inside a real in-process runspace instead of mocking.
    /// Mirrors the sole caller's shape (Invoke-DbaAdvancedRestore catches the throw):
    /// DbaBaseCmdlet host per the BP-002 mandatory-base-class rule, which also supplies
    /// the EnableException parameter surface (codex TB-011 r1).
    /// </summary>
    [Cmdlet("Test", "LsnConversionHost")]
    public sealed class TestLsnConversionHostCommand : DbaBaseCmdlet
    {
        [Parameter(Mandatory = true)]
        [AllowEmptyString]
        public string LSN { get; set; }

        /// <summary>Bypass the binder and hand ConvertDbaLsn a literal null: the PS binder
        /// converts $null to "" for [string] parameters, so this is the only way to reach
        /// the PsString(null) normalization from a test.</summary>
        [Parameter]
        public SwitchParameter PassNullLsn { get; set; }

        protected override void ProcessRecord()
        {
            try
            {
                LsnConversion result = RestoreUtility.ConvertDbaLsn(this, PassNullLsn.IsPresent ? null : LSN, EnableException.IsPresent);
                WriteObject(result == null ? "NULL" : result.Hexadecimal + "|" + result.Numeric);
            }
            catch (InnerCommandException ex)
            {
                WriteObject("INNERSTOP:" + ex.Message);
            }
        }
    }

    /// <summary>
    /// TB-011 coverage for RestoreUtility.ConvertDbaLsn, the C# parity port of
    /// private/functions/Convert-DbaLSN.ps1. Expected values are ground-truthed against the
    /// PS helper executed on both editions (probe 2026-07-16): the hex-to-numeric section
    /// padding (10/5), the numeric-to-hex branch's PRESERVED len-14 substring off-by-one
    /// (drops the middle section's LEADING digit - silent corruption whenever that digit is
    /// nonzero), the 16-digit-minimum numeric regex, verbatim case preservation of hex
    /// input, and both Stop-Function modes (EnableException throws for the caller to catch
    /// and suppresses the warning display, 3>$null parity; non-EnableException returns
    /// null with the warning DISPLAYED). Only the hex branch is reachable from the sole
    /// caller (Invoke-DbaAdvancedRestore pre-filters pure numerics), but the numeric
    /// branch is carried and pinned too - including a sect1 above int.MaxValue that
    /// discriminates the (long, int) binder resolution the port hardcodes as long.Parse
    /// (opus TB-011: byte-range probes alone would pass under an (int, int) binding).
    /// </summary>
    [TestClass]
    public class RestoreUtilityLsnTest
    {
        private static PowerShell NewHostedShell()
        {
            InitialSessionState iss = InitialSessionState.CreateDefault2();
            iss.Commands.Add(new SessionStateCmdletEntry("Test-LsnConversionHost", typeof(TestLsnConversionHostCommand), null));
            System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(iss);
            runspace.Open();
            PowerShell shell = PowerShell.Create();
            shell.Runspace = runspace;
            return shell;
        }

        private static string InvokeOne(PowerShell shell, string lsn, bool enableException)
        {
            shell.Commands.Clear();
            shell.AddCommand("Test-LsnConversionHost").AddParameter("LSN", lsn);
            if (enableException)
                shell.AddParameter("EnableException", true);
            Collection<PSObject> output = shell.Invoke();
            Assert.AreEqual(1, output.Count, "the host cmdlet emits exactly one marker string");
            return (string)output[0].BaseObject;
        }

        [TestMethod]
        public void ConvertDbaLsn_HexToNumeric_PadsSections10And5()
        {
            using (PowerShell shell = NewHostedShell())
            {
                // sect1 unpadded, sect2 PadLeft(10), sect3 PadLeft(5) - helper lines 30-34.
                Assert.AreEqual("0000002f:000044aa:002b|47000001757800043", InvokeOne(shell, "0000002f:000044aa:002b", true));
                // Uppercase hex parses and the Hexadecimal field keeps the input VERBATIM.
                Assert.AreEqual("0000002F:000044AA:002B|47000001757800043", InvokeOne(shell, "0000002F:000044AA:002B", true));
                shell.Runspace.Dispose();
            }
        }

        [TestMethod]
        public void ConvertDbaLsn_NumericToHex_PreservesTheLen14OffByOne()
        {
            using (PowerShell shell = NewHostedShell())
            {
                // Benign shape: the middle 10-digit section starts with 0, so dropping the
                // leading digit (Substring(len-14, 9)) is invisible and the value round-trips.
                Assert.AreEqual("0000002f:000044aa:002b|47000001757800043", InvokeOne(shell, "47000001757800043", true));
                // DISCRIMINATING pin of the preserved bug: middle section 4026531840
                // (0xf0000000) loses its leading 4, leaving 026531840 = 0x194d800. A
                // "corrected" len-15/10-digit implementation would emit f0000000 here and
                // fail. PS ground truth both editions: 00000001:0194d800:0001.
                Assert.AreEqual("00000001:0194d800:0001|1402653184000001", InvokeOne(shell, "1402653184000001", true));
                // BINDER pin (opus TB-011): sect1 = 4000000000 exceeds int.MaxValue, so
                // this discriminates the (long, int) overload the PS binder resolves
                // [System.Convert]::ToString($string, 16) to - an (int, int) or narrower
                // binding throws here instead of emitting ee6b2800. PS ground truth both
                // editions: ee6b2800:000044aa:002b.
                Assert.AreEqual("ee6b2800:000044aa:002b|4000000000000001757800043", InvokeOne(shell, "4000000000000001757800043", true));
                shell.Runspace.Dispose();
            }
        }

        [TestMethod]
        public void ConvertDbaLsn_15DigitNumericMissesBothBranches()
        {
            using (PowerShell shell = NewHostedShell())
            {
                // The numeric regex is ^[0-9]{15}[0-9]+$ - SIXTEEN digits minimum. A
                // 15-digit LSN falls through to the Stop-Function branch (PS parity).
                StringAssert.StartsWith(InvokeOne(shell, "123456789012345", true), "INNERSTOP:");
                shell.Runspace.Dispose();
            }
        }

        [TestMethod]
        public void ConvertDbaLsn_InvalidInput_EnableExceptionThrowsForTheCallerToCatch()
        {
            using (PowerShell shell = NewHostedShell())
            {
                string marker = InvokeOne(shell, "notanlsn", true);
                Assert.AreEqual("INNERSTOP:LSN passed in is neither Numeric nor in the correct hexadecimal format", marker, "the sole caller catches this throw and re-stops with its own InvalidArgument message");
                // The empty string also lands here (PS binds an unbound/$null [string] to
                // "", PsString parity on the port side) - ground-truthed both editions.
                StringAssert.StartsWith(InvokeOne(shell, "", true), "INNERSTOP:");
                // Literal null pins the PsString(null) normalization itself (codex r3):
                // the PS binder converts $null to "" before a [string] parameter ever
                // sees it, so the host's -PassNullLsn switch bypasses the binder. Without
                // PsString this would be an ArgumentNullException from Regex.IsMatch, not
                // the Stop-Function error branch.
                shell.Commands.Clear();
                shell.AddCommand("Test-LsnConversionHost").AddParameter("LSN", "ignored").AddParameter("PassNullLsn", true).AddParameter("EnableException", true);
                Collection<PSObject> nullOutput = shell.Invoke();
                Assert.AreEqual(1, nullOutput.Count);
                StringAssert.StartsWith((string)nullOutput[0].BaseObject, "INNERSTOP:", "null must normalize to the error branch, not throw ArgumentNullException");
                shell.Runspace.Dispose();
            }
        }

        [TestMethod]
        public void ConvertDbaLsn_InvalidInput_NonEnableExceptionReturnsNullAndWarns()
        {
            using (PowerShell shell = NewHostedShell())
            {
                // Caller-unreachable mode (the caller always passes EnableException) but
                // offline-observable: Stop-Function returns instead of throwing, the helper
                // returns null, and the friendly warning DISPLAYS (the 3>$null suppression
                // applies only under EnableException).
                Assert.AreEqual("NULL", InvokeOne(shell, "notanlsn", false));
                Assert.AreEqual(1, shell.Streams.Warning.Count, "non-EnableException mode shows the Stop-Function warning");
                StringAssert.Contains(shell.Streams.Warning[0].Message, "LSN passed in is neither Numeric nor in the correct hexadecimal format");
                shell.Runspace.Dispose();
            }
        }
    }
}
