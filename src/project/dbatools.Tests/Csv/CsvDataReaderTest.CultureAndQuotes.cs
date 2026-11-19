using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Dataplat.Dbatools.Csv;
using Dataplat.Dbatools.Csv.Reader;

namespace Dataplat.Dbatools.Csv.Tests
{
    public partial class CsvDataReaderTest
    {

        [TestMethod]
        public void TestCultureInfo_GermanDecimals()
        {
            // Addresses LumenWorks issue #66
            // German uses comma as decimal separator, semicolon as delimiter
            string csv = "Name;Price\nApple;1,50\nBanana;2,75";
            var germanCulture = new System.Globalization.CultureInfo("de-DE");
            var options = new CsvReaderOptions
            {
                Delimiter = ";",
                Culture = germanCulture,
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Price", typeof(decimal) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual(1.50m, reader.GetDecimal(1));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual(2.75m, reader.GetDecimal(1));
            }
        }



        [TestMethod]
        public void TestLenientQuoteMode_UnmatchedQuote()
        {
            // Addresses LumenWorks issues #47 and #56
            // Quote at start but not enclosing the field
            string csv = "ID;Name\n6224613;\"SINUS POLSKA\", MIEDZYRZECZ";
            var options = new CsvReaderOptions
            {
                Delimiter = ";",
                QuoteMode = QuoteMode.Lenient
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("6224613", reader.GetString(0));
                // In lenient mode, unmatched quote is treated as literal
                Assert.AreEqual("\"SINUS POLSKA\", MIEDZYRZECZ", reader.GetString(1));
            }
        }

        [TestMethod]
        public void TestLenientQuoteMode_BackslashEscape()
        {
            // Lenient mode handles backslash escapes
            string csv = "Name,Quote\nJohn,\"He said \\\"Hello\\\"\"";
            var options = new CsvReaderOptions { QuoteMode = QuoteMode.Lenient };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("He said \"Hello\"", reader.GetString(1));
            }
        }



        [TestMethod]
        public void TestMismatchedFields_ThrowException()
        {
            string csv = "A,B,C\n1,2\n4,5,6";
            var options = new CsvReaderOptions { MismatchedFieldAction = MismatchedFieldAction.ThrowException };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.ThrowsException<CsvParseException>(() => reader.Read());
            }
        }

        [TestMethod]
        public void TestMismatchedFields_PadWithNulls()
        {
            string csv = "A,B,C\n1,2\n4,5,6";
            var options = new CsvReaderOptions { MismatchedFieldAction = MismatchedFieldAction.PadWithNulls };

            using (var reader = CreateReaderFromString(csv, options))
            {
                // First row has 2 fields but expects 3 - should pad with null
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("1", reader.GetString(0));
                Assert.AreEqual("2", reader.GetString(1));
                Assert.IsTrue(reader.IsDBNull(2), "Missing field should be padded with null");

                // Second row is complete
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("4", reader.GetString(0));
                Assert.AreEqual("5", reader.GetString(1));
                Assert.AreEqual("6", reader.GetString(2));
            }
        }

        [TestMethod]
        public void TestMismatchedFields_TruncateExtra()
        {
            string csv = "A,B\n1,2,3,4\n5,6";
            var options = new CsvReaderOptions { MismatchedFieldAction = MismatchedFieldAction.TruncateExtra };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.AreEqual(2, reader.FieldCount);

                // First row has 4 fields but only 2 columns - should truncate
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("1", reader.GetString(0));
                Assert.AreEqual("2", reader.GetString(1));

                // Second row is normal
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("5", reader.GetString(0));
                Assert.AreEqual("6", reader.GetString(1));
            }
        }

        [TestMethod]
        public void TestMismatchedFields_PadOrTruncate()
        {
            string csv = "A,B,C\n1,2\n4,5,6,7,8";
            var options = new CsvReaderOptions { MismatchedFieldAction = MismatchedFieldAction.PadOrTruncate };

            using (var reader = CreateReaderFromString(csv, options))
            {
                // First row: too few fields - pad
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("1", reader.GetString(0));
                Assert.AreEqual("2", reader.GetString(1));
                Assert.IsTrue(reader.IsDBNull(2));

                // Second row: too many fields - truncate
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("4", reader.GetString(0));
                Assert.AreEqual("5", reader.GetString(1));
                Assert.AreEqual("6", reader.GetString(2));
            }
        }



        [TestMethod]
        public void TestNormalizeSmartQuotes()
        {
            // Addresses LumenWorks issue #25
            // Smart/curly quotes from Word/Excel should be normalized to straight quotes
            string csv = "Name,Description\nJohn,\u201CHello World\u201D";  // "Hello World" with curly quotes
            var options = new CsvReaderOptions { NormalizeQuotes = true };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                // The curly quotes should be normalized to straight quotes and treated as field delimiters
                Assert.AreEqual("Hello World", reader.GetString(1));
            }
        }

        [TestMethod]
        public void TestNormalizeSmartQuotes_EscapedSmartQuotesWithinQuotedField()
        {
            string csv = "A,B\n\"\u201C\u201D\",\"\"";
            var options = new CsvReaderOptions { NormalizeQuotes = true };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("\"", reader.GetString(0));
                Assert.AreEqual(string.Empty, reader.GetString(1));
                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestNormalizeSmartQuotes_LenientUnclosedQuotedFieldNormalizesAccumulator()
        {
            string csv = "\u201CAlpha \u201Cbroken\n";
            var options = new CsvReaderOptions
            {
                HasHeaderRow = false,
                NormalizeQuotes = true,
                QuoteMode = QuoteMode.Lenient
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("\"Alpha \"broken", reader.GetString(0));
                Assert.IsFalse(reader.Read());
            }
        }

    }
}
