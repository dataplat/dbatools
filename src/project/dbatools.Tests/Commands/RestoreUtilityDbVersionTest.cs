using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// TB-014 coverage for RestoreUtility.ConvertDbVersionToSqlVersion, the C# parity port
    /// of private/functions/Convert-DbVersionToSqlVersion.ps1 (ported earlier alongside the
    /// restore ecosystem; this row adds the missing pins). Expected values ground-truthed on
    /// both editions (probe 2026-07-16). The load-bearing semantic: the PS switch compares
    /// its INTEGER case literals against the [string] subject with the SUBJECT's type
    /// winning, so only the exact digit string matches - "0869" and " 869" pass through
    /// VERBATIM (a numeric-parse implementation would map them to SQL Server 2017 and
    /// fail these pins); unknown and empty inputs also pass through unchanged.
    /// </summary>
    [TestClass]
    public class RestoreUtilityDbVersionTest
    {
        [TestMethod]
        public void DbVersion_MapsAllFifteenKnownVersions()
        {
            Assert.AreEqual("SQL Server 2017", RestoreUtility.ConvertDbVersionToSqlVersion("869"));
            Assert.AreEqual("SQL Server vNext CTP1", RestoreUtility.ConvertDbVersionToSqlVersion("856"));
            Assert.AreEqual("SQL Server 2016", RestoreUtility.ConvertDbVersionToSqlVersion("852"));
            Assert.AreEqual("SQL Server 2016 Prerelease", RestoreUtility.ConvertDbVersionToSqlVersion("829"));
            Assert.AreEqual("SQL Server 2014", RestoreUtility.ConvertDbVersionToSqlVersion("782"));
            Assert.AreEqual("SQL Server 2012", RestoreUtility.ConvertDbVersionToSqlVersion("706"));
            Assert.AreEqual("SQL Server 2012 CTP1", RestoreUtility.ConvertDbVersionToSqlVersion("684"));
            Assert.AreEqual("SQL Server 2008 R2", RestoreUtility.ConvertDbVersionToSqlVersion("661"));
            Assert.AreEqual("SQL Server 2008 R2", RestoreUtility.ConvertDbVersionToSqlVersion("660"));
            Assert.AreEqual("SQL Server 2008 SP2+", RestoreUtility.ConvertDbVersionToSqlVersion("655"));
            Assert.AreEqual("SQL Server 2005", RestoreUtility.ConvertDbVersionToSqlVersion("612"));
            Assert.AreEqual("SQL Server 2005", RestoreUtility.ConvertDbVersionToSqlVersion("611"));
            Assert.AreEqual("SQL Server 2000", RestoreUtility.ConvertDbVersionToSqlVersion("539"));
            Assert.AreEqual("SQL Server 7.0", RestoreUtility.ConvertDbVersionToSqlVersion("515"));
            Assert.AreEqual("SQL Server 6.5", RestoreUtility.ConvertDbVersionToSqlVersion("408"));
        }

        [TestMethod]
        public void DbVersion_ComparesAsStringsNotNumbers()
        {
            // PS switch: the [string] subject's type wins the -eq conversion, so the int
            // case 869 becomes "869" and only that exact digit string matches.
            Assert.AreEqual("0869", RestoreUtility.ConvertDbVersionToSqlVersion("0869"), "a leading zero misses every case and passes through verbatim");
            Assert.AreEqual(" 869", RestoreUtility.ConvertDbVersionToSqlVersion(" 869"), "no leading trimming");
            // Codex r1: the leading pin alone lets a TrimEnd() implementation false-pass.
            Assert.AreEqual("869 ", RestoreUtility.ConvertDbVersionToSqlVersion("869 "), "no trailing trimming");
        }

        [TestMethod]
        public void DbVersion_UnknownAndEmptyPassThroughUnchanged()
        {
            Assert.AreEqual("999", RestoreUtility.ConvertDbVersionToSqlVersion("999"));
            Assert.AreEqual("", RestoreUtility.ConvertDbVersionToSqlVersion(""), "unbound PS [string] is empty and rides the default case");
            // Opus TB-014: the C#-only null entry must normalize like the PS binder does
            // (PsString on entry), not leak a null through the default arm.
            Assert.AreEqual("", RestoreUtility.ConvertDbVersionToSqlVersion(null), "PS binds an unbound/null [string] to empty");
        }
    }
}
