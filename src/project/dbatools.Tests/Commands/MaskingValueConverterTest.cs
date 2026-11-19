using System;
using System.Collections.Generic;
using Dataplat.Dbatools.Commands;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Commands.Test
{
    /// <summary>
    /// TB-012 coverage for MaskingValueConverter, the C# parity port of
    /// private/functions/Convert-DbaMaskingValue.ps1. Every expected value is
    /// ground-truthed against the PS helper on both editions (probe 2026-07-16); the
    /// discriminating pins are the PS-truthiness folds (bit 0 and bool $false become NULL,
    /// never "0"), the begin-gate throws on falsy scalars, the dead elseif ('' emits
    /// "$null"/"NULL" even without Nullable), the unanchored numeric regex passing
    /// digit-bearing strings through raw, the ""-vs-null ErrorMessage split between the
    /// process path and the begin NULL object, and the non-escaped uniqueidentifier quote.
    /// </summary>
    [TestClass]
    public class MaskingValueConverterTest
    {
        private static MaskingValue One(object[] value, string dataType, bool nullable)
        {
            List<MaskingValue> results = MaskingValueConverter.Convert(value, dataType, nullable);
            Assert.AreEqual(1, results.Count, "expected a single result");
            return results[0];
        }

        [TestMethod]
        public void Convert_BeginGate_FalsyScalarsThrowBeforeAnyItemIsExamined()
        {
            // PS truthiness on the whole [object[]]: @(0), @($false), @("") all unwrap falsy.
            Assert.ThrowsException<InvalidOperationException>(delegate { MaskingValueConverter.Convert(new object[] { 0 }, "bit", false); });
            Assert.ThrowsException<InvalidOperationException>(delegate { MaskingValueConverter.Convert(new object[] { false }, "bit", false); });
            Assert.ThrowsException<InvalidOperationException>(delegate { MaskingValueConverter.Convert(new object[] { "" }, "varchar", false); });
            Assert.ThrowsException<InvalidOperationException>(delegate { MaskingValueConverter.Convert(null, "varchar", false); });
            InvalidOperationException valueGate = Assert.ThrowsException<InvalidOperationException>(delegate { MaskingValueConverter.Convert(new object[] { 0 }, "bit", false); });
            Assert.AreEqual("Please enter a value", valueGate.Message);
            // Missing data type is the SECOND gate - value must be truthy to reach it.
            InvalidOperationException dataTypeGate = Assert.ThrowsException<InvalidOperationException>(delegate { MaskingValueConverter.Convert(new object[] { "x" }, null, false); });
            Assert.AreEqual("Please enter a data type", dataTypeGate.Message);
            // GATE ORDER pin (opus F5): with both violated, the VALUE gate reports first
            // - PS ground truth both editions: "Please enter a value".
            InvalidOperationException bothGates = Assert.ThrowsException<InvalidOperationException>(delegate { MaskingValueConverter.Convert(null, null, false); });
            Assert.AreEqual("Please enter a value", bothGates.Message);
        }

        [TestMethod]
        public void Convert_Nullable_SkipsBothGatesAndEmitsTheBeginNullObject()
        {
            // $null.Count is 0 in PS: the begin block emits the one object whose
            // ErrorMessage is a TRUE null (process-path objects carry "").
            MaskingValue fromNull = One(null, "varchar", true);
            Assert.AreEqual("$null", fromNull.OriginalValue);
            Assert.AreEqual("NULL", fromNull.NewValue);
            Assert.IsNull(fromNull.ErrorMessage, "the begin object is the only true-null ErrorMessage");
            // Nullable also skips the DATA TYPE gate entirely; "" falls to the default
            // branch, so a truthy item still converts.
            MaskingValue noType = One(new object[] { "x" }, null, true);
            Assert.AreEqual("'x'", noType.NewValue);
            Assert.AreEqual("", noType.DataType, "DataType rides raw; unbound PS [string] is empty");
        }

        [TestMethod]
        public void Convert_FalsyItems_FoldToNullLiteral()
        {
            // PRESERVED BUG pins: bit 0 and bool $false can NEVER emit "0" - PS item
            // truthiness folds them to NULL first. Reachable via -Nullable (scalar) or
            // inside a truthy multi-element array.
            MaskingValue zero = One(new object[] { 0 }, "bit", true);
            Assert.AreEqual("$null", zero.OriginalValue, "the falsy item's OriginalValue is the LITERAL string $null");
            Assert.AreEqual("NULL", zero.NewValue);
            Assert.AreEqual("", zero.ErrorMessage, "process-path objects carry empty-string ErrorMessage, not null");

            List<MaskingValue> mixed = MaskingValueConverter.Convert(new object[] { 0, 1 }, "bit", false);
            Assert.AreEqual("NULL", mixed[0].NewValue);
            Assert.AreEqual("1", mixed[1].NewValue);

            // DEAD-ELSEIF record: '' is falsy, so it lands here too - "$null"/"NULL" even
            // WITHOUT Nullable - and the source's elseif ($item -eq '') can never run.
            List<MaskingValue> withEmpty = MaskingValueConverter.Convert(new object[] { "", "x" }, "varchar", false);
            Assert.AreEqual("$null", withEmpty[0].OriginalValue);
            Assert.AreEqual("NULL", withEmpty[0].NewValue);
            Assert.AreEqual("'x'", withEmpty[1].NewValue);
        }

        [TestMethod]
        public void Convert_BitBranch_MatchesPsEqSemantics()
        {
            Assert.AreEqual("0", One(new object[] { "0" }, "bit", false).NewValue, "the STRING 0 is truthy and hits the regex");
            Assert.AreEqual("1", One(new object[] { true }, "bit", false).NewValue, "bool true: -eq 'true' converts the RHS to bool");
            Assert.AreEqual("1", One(new object[] { "TRUE" }, "bit", false).NewValue, "-eq is case-insensitive");
            Assert.AreEqual("0", One(new object[] { "false" }, "bit", false).NewValue);
            MaskingValue bad = One(new object[] { 5 }, "bit", false);
            Assert.AreEqual("Value '5' is not valid BIT or BOOL", bad.ErrorMessage, "int 5 -eq 'true' fails conversion QUIETLY (no throw)");
            Assert.AreEqual("", bad.NewValue);
        }

        [TestMethod]
        public void Convert_NumericBranch_IsUnanchoredAndRaw()
        {
            Assert.AreEqual("12.5", One(new object[] { 12.5d }, "decimal", false).NewValue, "interpolation parity: invariant double rendering");
            Assert.AreEqual("12,5", One(new object[] { "12,5" }, "decimal", false).NewValue, "comma variant passes through raw");
            // The regex \b\d+([\.,]\d+)? is UNANCHORED: any digit-bearing string passes
            // RAW and UNQUOTED - preserved injection-shaped behavior, pinned so a future
            // "hardening" is a conscious break.
            Assert.AreEqual("1;DROP", One(new object[] { "1;DROP" }, "int", false).NewValue);
            Assert.AreEqual("Value 'abc' is not valid integer/decimal format", One(new object[] { "abc" }, "int", false).ErrorMessage);
        }

        [TestMethod]
        public void Convert_DateFamily_InvariantFormatsPerBranch()
        {
            Assert.AreEqual("'2020-01-02 13:45:12.345'", One(new object[] { "2020-01-02 13:45:12.345" }, "datetime", false).NewValue);
            Assert.AreEqual("'2020-01-02 13:45:12.3456789'", One(new object[] { "2020-01-02 13:45:12.3456789" }, "datetime2", false).NewValue);
            Assert.AreEqual("'2020-01-02'", One(new object[] { "2020-01-02" }, "date", false).NewValue);
            // US slash form is accepted by the second regex and parses invariantly (month first).
            Assert.AreEqual("'2020-01-02'", One(new object[] { "01/02/2020" }, "date", false).NewValue);
            // A real DateTime item: the -match stringification is the ENGINE conversion
            // (invariant MM/dd/yyyy ...), which always matches the slash regex.
            DateTime item = new DateTime(2020, 1, 2, 13, 45, 12, 345).AddTicks(6789);
            Assert.AreEqual("'2020-01-02 13:45:12.345'", One(new object[] { item }, "datetime", false).NewValue);
            Assert.AreEqual("Value 'nodate' is not valid DATE or DATETIME format (yyyy-MM-dd)", One(new object[] { "nodate" }, "datetime", false).ErrorMessage);
            // smalldatetime: -like with no wildcard = equality; seconds precision.
            Assert.AreEqual("'2020-01-02 13:45:12'", One(new object[] { "2020-01-02 13:45:12.999" }, "smalldatetime", false).NewValue);
        }

        [TestMethod]
        public void Convert_TimeBranch_UsesSevenFractionDigits()
        {
            // The one date-family branch WITHOUT the invariant argument (source line 168).
            Assert.AreEqual("'13:45:12.0000000'", One(new object[] { "13:45:12" }, "time", false).NewValue);
            Assert.AreEqual("Value '134512' is not valid TIME format (HH:mm:ss)", One(new object[] { "134512" }, "time", false).ErrorMessage);
        }

        [TestMethod]
        public void Convert_TimeBranch_FollowsTheCurrentCultureTimeSeparator()
        {
            // Discriminating pin of the source's missing invariant argument (codex r1):
            // under a culture whose TimeSeparator is ".", the ":" glyphs in the custom
            // format map to "." - PS ground truth both editions: '13.45.12.0000000' -
            // while the datetime branch (explicit invariant) is unaffected. A port that
            // "fixed" the time branch to invariant would emit ':' here and fail.
            System.Globalization.CultureInfo original = System.Threading.Thread.CurrentThread.CurrentCulture;
            try
            {
                System.Globalization.CultureInfo custom = (System.Globalization.CultureInfo)new System.Globalization.CultureInfo("en-US").Clone();
                custom.DateTimeFormat.TimeSeparator = ".";
                System.Threading.Thread.CurrentThread.CurrentCulture = custom;

                Assert.AreEqual("'13.45.12.0000000'", One(new object[] { "13:45:12" }, "time", false).NewValue);
                Assert.AreEqual("'2020-01-02 13:45:12.345'", One(new object[] { "2020-01-02 13:45:12.345" }, "datetime", false).NewValue, "the invariant datetime branch must NOT follow the culture");
                // Default-branch discriminator (opus F4): the source's .ToString() METHOD
                // call is current-culture while "$item" interpolation is invariant. Under
                // a comma-decimal culture a double splits the two paths - PS ground truth
                // both editions (de-DE): varchar '12,5' vs decimal 12.5. A port that used
                // the invariant PsString in the default branch would emit '12.5' and fail.
                System.Globalization.CultureInfo comma = (System.Globalization.CultureInfo)new System.Globalization.CultureInfo("en-US").Clone();
                comma.NumberFormat.NumberDecimalSeparator = ",";
                System.Threading.Thread.CurrentThread.CurrentCulture = comma;
                Assert.AreEqual("'12,5'", One(new object[] { 12.5d }, "varchar", false).NewValue, "default branch follows the culture");
                Assert.AreEqual("12.5", One(new object[] { 12.5d }, "decimal", false).NewValue, "numeric-branch interpolation stays invariant");
            }
            finally
            {
                System.Threading.Thread.CurrentThread.CurrentCulture = original;
            }
        }

        [TestMethod]
        public void Convert_QuoteHandling_DefaultEscapesUniqueidentifierDoesNot()
        {
            Assert.AreEqual("'O''Brien'", One(new object[] { "O'Brien" }, "varchar", false).NewValue, "default branch doubles quotes");
            Assert.AreEqual("'a'b'", One(new object[] { "a'b" }, "uniqueidentifier", false).NewValue, "uniqueidentifier does NOT escape - preserved broken-SQL shape");
        }

        [TestMethod]
        public void Convert_XmlBranch_IsSilentlyEmpty()
        {
            MaskingValue xml = One(new object[] { "<a/>" }, "xml", false);
            Assert.AreEqual("", xml.NewValue, "xml emits no value ([string]$null is '' in PS)");
            Assert.AreEqual("", xml.ErrorMessage, "and no error - silently unusable, preserved");
            Assert.AreEqual("<a/>", xml.OriginalValue);
        }

        [TestMethod]
        public void Convert_MultipleItemsEmitInOrderWithRawDataType()
        {
            List<MaskingValue> results = MaskingValueConverter.Convert(new object[] { "a", "b" }, "VARCHAR", false);
            Assert.AreEqual(2, results.Count);
            Assert.AreEqual("'a'", results[0].NewValue);
            Assert.AreEqual("'b'", results[1].NewValue);
            Assert.AreEqual("VARCHAR", results[0].DataType, "DataType property carries the RAW argument, never lowercased");
        }
    }
}
