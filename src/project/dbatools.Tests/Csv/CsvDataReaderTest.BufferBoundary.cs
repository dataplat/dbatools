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
        public void TestEscapedQuoteAtBufferBoundary()
        {
            // Place a "" escape pair so the first " lands at the last byte of a 128-byte buffer.
            // Header: "A","B","C"\n = 14 bytes
            // Record prefix: "a"," = 4 bytes
            // Total before padding content: 18 bytes
            // We need the first " of "" at byte offset 127 (0-based), so padding = 127 - 18 = 109 a's
            string header = "\"A\",\"B\",\"C\"\n";
            string prefix = "\"a\",\"";
            int paddingLen = 127 - header.Length - prefix.Length;
            string padding = new string('x', paddingLen);
            string record = prefix + padding + "\"\"rest\",\"c\"\n";
            string csv = header + record;

            var options = new CsvReaderOptions
            {
                HasHeaderRow = true,
                BufferSize = 128
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual(3, reader.FieldCount);
                Assert.AreEqual("a", reader.GetString(0));
                Assert.AreEqual(padding + "\"rest", reader.GetString(1));
                Assert.AreEqual("c", reader.GetString(2));
                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestEscapedQuoteAtBufferBoundaryMultipleSizes()
        {
            int[] bufferSizes = new int[] { 128, 256, 512, 1024 };

            foreach (int bufSize in bufferSizes)
            {
                string header = "\"A\",\"B\",\"C\"\n";
                string prefix = "\"a\",\"";
                int paddingLen = bufSize - 1 - header.Length - prefix.Length;
                if (paddingLen < 0) continue;
                string padding = new string('x', paddingLen);
                string record = prefix + padding + "\"\"rest\",\"c\"\n";
                string csv = header + record;

                var options = new CsvReaderOptions
                {
                    HasHeaderRow = true,
                    BufferSize = bufSize
                };

                using (var reader = CreateReaderFromString(csv, options))
                {
                    Assert.IsTrue(reader.Read(), String.Format("BufferSize={0}: Read() should return true", bufSize));
                    Assert.AreEqual(3, reader.FieldCount, String.Format("BufferSize={0}: should have 3 fields", bufSize));
                    Assert.AreEqual("a", reader.GetString(0), String.Format("BufferSize={0}: field A", bufSize));
                    Assert.AreEqual(padding + "\"rest", reader.GetString(1), String.Format("BufferSize={0}: field B", bufSize));
                    Assert.AreEqual("c", reader.GetString(2), String.Format("BufferSize={0}: field C", bufSize));
                    Assert.IsFalse(reader.Read(), String.Format("BufferSize={0}: no more rows", bufSize));
                }
            }
        }

        [TestMethod]
        public void TestEscapedQuoteAtBufferBoundaryLenientMode()
        {
            string header = "\"A\",\"B\",\"C\"\n";
            string prefix = "\"a\",\"";
            int paddingLen = 127 - header.Length - prefix.Length;
            string padding = new string('x', paddingLen);
            string record = prefix + padding + "\"\"rest\",\"c\"\n";
            string csv = header + record;

            var options = new CsvReaderOptions
            {
                HasHeaderRow = true,
                BufferSize = 128,
                QuoteMode = QuoteMode.Lenient
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual(3, reader.FieldCount);
                Assert.AreEqual("a", reader.GetString(0));
                Assert.AreEqual(padding + "\"rest", reader.GetString(1));
                Assert.AreEqual("c", reader.GetString(2));
                Assert.IsFalse(reader.Read());
            }
        }

    }
}
