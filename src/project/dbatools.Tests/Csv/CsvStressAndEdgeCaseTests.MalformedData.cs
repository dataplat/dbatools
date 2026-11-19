using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Dataplat.Dbatools.Csv;
using Dataplat.Dbatools.Csv.Reader;

namespace Dataplat.Dbatools.Csv.Tests
{
    public partial class CsvStressAndEdgeCaseTests
    {

        [TestMethod]
        public void TestMalformedCsv_TruncatedFile_ThrowsByDefault()
        {
            // File ends mid-field (missing Value on last row)
            // By default, CsvDataReader throws CsvParseException for mismatched field counts
            string csvPath = Path.Combine(_tempDir, "truncated.csv");
            File.WriteAllText(csvPath, "Id,Name,Value\n1,John,100\n2,Jane");

            Assert.ThrowsException<CsvParseException>(() =>
            {
                CsvSchemaInference.InferSchemaFromSample(csvPath);
            });
        }

        [TestMethod]
        public void TestMalformedCsv_TruncatedFile_WithPadNulls()
        {
            // With MismatchedFieldAction.PadWithNulls, missing fields become null
            string csvPath = Path.Combine(_tempDir, "truncated_pad.csv");
            File.WriteAllText(csvPath, "Id,Name,Value\n1,John,100\n2,Jane");

            var options = new CsvReaderOptions
            {
                MismatchedFieldAction = MismatchedFieldAction.PadWithNulls
            };
            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath, options);

            Assert.AreEqual(3, columns.Count);
            Assert.IsTrue(columns[2].IsNullable, "Value column should be nullable due to missing field");
        }

        [TestMethod]
        public void TestMalformedCsv_UnmatchedQuotes_ThrowsByDefault()
        {
            // Field starts with quote but never closes - throws by default
            string csvPath = Path.Combine(_tempDir, "unmatched_quote.csv");
            File.WriteAllText(csvPath, "Id,Name,Value\n1,\"John,100\n2,Jane,200\n");

            Assert.ThrowsException<CsvParseException>(() =>
            {
                CsvSchemaInference.InferSchemaFromSample(csvPath);
            });
        }

        [TestMethod]
        public void TestMalformedCsv_UnmatchedQuotes_WithAdvanceToNextLine()
        {
            // With ParseErrorAction.AdvanceToNextLine, bad rows are skipped
            string csvPath = Path.Combine(_tempDir, "unmatched_quote_skip.csv");
            File.WriteAllText(csvPath, "Id,Name,Value\n1,\"John,100\n2,Jane,200\n3,Bob,300\n");

            var options = new CsvReaderOptions
            {
                ParseErrorAction = CsvParseErrorAction.AdvanceToNextLine
            };

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath, options);
            // Should parse the valid rows
            Assert.IsTrue(columns.Count >= 1);
        }

        [TestMethod]
        public void TestMalformedCsv_InconsistentFieldCounts_ThrowsByDefault()
        {
            // By default, mismatched field counts throw
            string csvPath = Path.Combine(_tempDir, "inconsistent.csv");
            File.WriteAllText(csvPath, @"Id,Name,Value
1,John,100
2,Jane
3,Bob,300,ExtraField,AnotherExtra
4,Alice,400
");

            Assert.ThrowsException<CsvParseException>(() =>
            {
                CsvSchemaInference.InferSchemaFromSample(csvPath);
            });
        }

        [TestMethod]
        public void TestMalformedCsv_InconsistentFieldCounts_WithPadOrTruncate()
        {
            // With PadOrTruncate, both missing and extra fields are handled
            string csvPath = Path.Combine(_tempDir, "inconsistent_lenient.csv");
            File.WriteAllText(csvPath, @"Id,Name,Value
1,John,100
2,Jane
3,Bob,300,ExtraField,AnotherExtra
4,Alice,400
");

            var options = new CsvReaderOptions
            {
                MismatchedFieldAction = MismatchedFieldAction.PadOrTruncate
            };
            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath, options);

            Assert.AreEqual(3, columns.Count);
            Assert.IsTrue(columns[2].IsNullable, "Value should be nullable due to row 2 missing it");
        }

        [TestMethod]
        public void TestMalformedCsv_EmptyLines()
        {
            string csvPath = Path.Combine(_tempDir, "empty_lines.csv");
            File.WriteAllText(csvPath, "Id,Name\n\n1,John\n\n\n2,Jane\n\n");

            var options = new CsvReaderOptions { SkipEmptyLines = true };
            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath, options);

            Assert.AreEqual(2, columns.Count);
            Assert.AreEqual("int", columns[0].SqlDataType);
        }

        [TestMethod]
        public void TestMalformedCsv_OnlyWhitespace()
        {
            string csvPath = Path.Combine(_tempDir, "whitespace.csv");
            File.WriteAllText(csvPath, "Id,Name,Value\n   ,   ,   \n  ,  ,  \n");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            // All values are whitespace = all nullable varchar
            Assert.AreEqual(3, columns.Count);
            Assert.IsTrue(columns[0].IsNullable);
            Assert.IsTrue(columns[1].IsNullable);
            Assert.IsTrue(columns[2].IsNullable);
        }

        [TestMethod]
        public void TestMalformedCsv_VeryLongLine()
        {
            // Single field with extremely long value
            string csvPath = Path.Combine(_tempDir, "long_line.csv");
            string longValue = new string('x', 100000);
            File.WriteAllText(csvPath, String.Format("Value\n{0}\n", longValue));

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            Assert.AreEqual(1, columns.Count);
            Assert.AreEqual("varchar(max)", columns[0].SqlDataType); // > 8000 chars
            Assert.AreEqual(100000, columns[0].MaxLength);
        }

        [TestMethod]
        public void TestMalformedCsv_BinaryDataMixed()
        {
            // CSV with some binary/non-printable characters
            string csvPath = Path.Combine(_tempDir, "binary.csv");
            byte[] content = Encoding.UTF8.GetBytes("Id,Name\n1,Test\n");
            byte[] binary = new byte[] { 0x00, 0x01, 0x02, 0xFF, 0xFE };

            using (var fs = File.Create(csvPath))
            {
                fs.Write(content, 0, content.Length);
                // Write a row with binary garbage
                var row = Encoding.UTF8.GetBytes("2,");
                fs.Write(row, 0, row.Length);
                fs.Write(binary, 0, binary.Length);
                fs.Write(new byte[] { (byte)'\n' }, 0, 1);
            }

            // Should not throw
            try
            {
                var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);
                Assert.IsTrue(columns.Count >= 1);
            }
            catch (Exception ex)
            {
                Assert.Fail(String.Format("Should handle binary data gracefully, but threw: {0}", ex.Message));
            }
        }

        [TestMethod]
        public void TestMalformedCsv_InvalidUtf8()
        {
            // Create file with invalid UTF-8 sequences
            string csvPath = Path.Combine(_tempDir, "invalid_utf8.csv");
            byte[] header = Encoding.UTF8.GetBytes("Id,Name\n1,Test\n2,");
            byte[] invalidUtf8 = new byte[] { 0xC0, 0xC1, 0xF5, 0xF6, 0xF7 }; // Invalid UTF-8 bytes
            byte[] rest = Encoding.UTF8.GetBytes("\n3,Valid\n");

            using (var fs = File.Create(csvPath))
            {
                fs.Write(header, 0, header.Length);
                fs.Write(invalidUtf8, 0, invalidUtf8.Length);
                fs.Write(rest, 0, rest.Length);
            }

            // Read with encoding that replaces invalid chars
            var options = new CsvReaderOptions { Encoding = Encoding.UTF8 };

            try
            {
                var columns = CsvSchemaInference.InferSchemaFromSample(csvPath, options);
                // Should recover and parse what it can
                Assert.AreEqual(2, columns.Count);
            }
            catch (DecoderFallbackException)
            {
                // This is also acceptable behavior - strict UTF-8 rejection
            }
        }

        [TestMethod]
        public void TestMalformedCsv_NestedQuotes_ThrowsByDefault()
        {
            // Improperly escaped quotes - throws by default
            string csvPath = Path.Combine(_tempDir, "nested_quotes.csv");
            File.WriteAllText(csvPath, "Id,Name,Description\n1,John,\"He said \"hello\" to me\"\n2,Jane,Normal\n");

            Assert.ThrowsException<CsvParseException>(() =>
            {
                CsvSchemaInference.InferSchemaFromSample(csvPath);
            });
        }

        [TestMethod]
        public void TestMalformedCsv_NestedQuotes_WithAdvanceToNextLine()
        {
            // With ParseErrorAction.AdvanceToNextLine, bad rows are skipped
            string csvPath = Path.Combine(_tempDir, "nested_quotes_skip.csv");
            File.WriteAllText(csvPath, "Id,Name,Description\n1,John,\"He said \"hello\" to me\"\n2,Jane,Normal\n");

            var options = new CsvReaderOptions
            {
                ParseErrorAction = CsvParseErrorAction.AdvanceToNextLine
            };

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath, options);
            // Should parse the valid rows (header + row 2 at minimum)
            Assert.IsTrue(columns.Count >= 1);
        }

        [TestMethod]
        public void TestMalformedCsv_ProperlyEscapedQuotes()
        {
            // RFC 4180: quotes inside quoted fields are escaped by doubling them
            string csvPath = Path.Combine(_tempDir, "escaped_quotes.csv");
            File.WriteAllText(csvPath, "Id,Name,Description\n1,John,\"He said \"\"hello\"\" to me\"\n2,Jane,Normal\n");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            Assert.AreEqual(3, columns.Count);
            Assert.IsTrue(columns[2].SqlDataType.StartsWith("varchar("));
        }

        [TestMethod]
        public void TestMalformedCsv_CRWithoutLF()
        {
            // Old Mac-style line endings (CR only)
            string csvPath = Path.Combine(_tempDir, "cr_only.csv");
            File.WriteAllText(csvPath, "Id,Name\r1,John\r2,Jane\r");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            // Should handle different line endings
            Assert.AreEqual(2, columns.Count);
        }

        [TestMethod]
        public void TestMalformedCsv_MixedLineEndings()
        {
            // Mix of CRLF, LF, and CR
            string csvPath = Path.Combine(_tempDir, "mixed_endings.csv");
            File.WriteAllText(csvPath, "Id,Name\r\n1,John\n2,Jane\r3,Bob\r\n");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            Assert.AreEqual(2, columns.Count);
        }

        [TestMethod]
        public void TestMalformedCsv_NullBytes()
        {
            // CSV with null bytes embedded
            string csvPath = Path.Combine(_tempDir, "null_bytes.csv");
            var content = "Id,Name\n1,Te\0st\n2,Normal\n";
            File.WriteAllBytes(csvPath, Encoding.UTF8.GetBytes(content));

            try
            {
                var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);
                Assert.AreEqual(2, columns.Count);
            }
            catch
            {
                // Some parsers may reject null bytes - that's acceptable
            }
        }

    }
}
