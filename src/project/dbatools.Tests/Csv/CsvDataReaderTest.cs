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
    [TestClass]
    public partial class CsvDataReaderTest
    {

        [TestMethod]
        public void TestBasicReading()
        {
            string csv = "Name,Age,City\nJohn,30,New York\nJane,25,Boston";
            using (var reader = CreateReaderFromString(csv))
            {
                Assert.AreEqual(3, reader.FieldCount);
                Assert.AreEqual("Name", reader.GetName(0));
                Assert.AreEqual("Age", reader.GetName(1));
                Assert.AreEqual("City", reader.GetName(2));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
                Assert.AreEqual("30", reader.GetString(1));
                Assert.AreEqual("New York", reader.GetString(2));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("Jane", reader.GetString(0));
                Assert.AreEqual("25", reader.GetString(1));
                Assert.AreEqual("Boston", reader.GetString(2));

                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestNoHeaderRow()
        {
            string csv = "John,30,New York\nJane,25,Boston";
            var options = new CsvReaderOptions { HasHeaderRow = false };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual(3, reader.FieldCount);
                Assert.AreEqual("Column0", reader.GetName(0));
                Assert.AreEqual("John", reader.GetString(0));
            }
        }

        [TestMethod]
        public void TestNoHeaderRowSetColumnTypeBeforeRead()
        {
            // This tests the fix for the NoHeaderRow issue where SetColumnType
            // was failing because columns weren't created until Read() was called.
            string csv = "John,30,New York\nJane,25,Boston";
            var options = new CsvReaderOptions { HasHeaderRow = false };

            using (var reader = CreateReaderFromString(csv, options))
            {
                // SetColumnType should work BEFORE Read() is called
                // This requires columns to be initialized during Initialize()
                reader.SetColumnType("Column0", typeof(string));
                reader.SetColumnType("Column1", typeof(int));
                reader.SetColumnType("Column2", typeof(string));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual(3, reader.FieldCount);
                Assert.AreEqual("Column0", reader.GetName(0));
                Assert.AreEqual("John", reader.GetString(0));
                Assert.AreEqual(30, reader.GetInt32(1));  // Converted to int
                Assert.AreEqual("New York", reader.GetString(2));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("Jane", reader.GetString(0));
                Assert.AreEqual(25, reader.GetInt32(1));  // Converted to int
                Assert.AreEqual("Boston", reader.GetString(2));

                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestNoHeaderRowHasColumnBeforeRead()
        {
            // Test that HasColumn works before Read() when HasHeaderRow = false
            string csv = "John,30,New York\nJane,25,Boston";
            var options = new CsvReaderOptions { HasHeaderRow = false };

            using (var reader = CreateReaderFromString(csv, options))
            {
                // HasColumn should work BEFORE Read() is called
                Assert.IsTrue(reader.HasColumn("Column0"));
                Assert.IsTrue(reader.HasColumn("Column1"));
                Assert.IsTrue(reader.HasColumn("Column2"));
                Assert.IsFalse(reader.HasColumn("Column3"));

                // FieldCount should also work
                Assert.AreEqual(3, reader.FieldCount);

                // GetFieldHeaders should work
                var headers = reader.GetFieldHeaders();
                Assert.AreEqual(3, headers.Length);
                Assert.AreEqual("Column0", headers[0]);
                Assert.AreEqual("Column1", headers[1]);
                Assert.AreEqual("Column2", headers[2]);
            }
        }

        [TestMethod]
        public void TestEmptyFile()
        {
            string csv = "";
            using (var reader = CreateReaderFromString(csv))
            {
                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestHeaderOnly()
        {
            string csv = "Name,Age,City";
            using (var reader = CreateReaderFromString(csv))
            {
                Assert.AreEqual(3, reader.FieldCount);
                Assert.IsFalse(reader.Read());
            }
        }



        [TestMethod]
        public void TestTabDelimiter()
        {
            string csv = "Name\tAge\tCity\nJohn\t30\tNew York";
            var options = new CsvReaderOptions { Delimiter = "\t" };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.AreEqual(3, reader.FieldCount);
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
                Assert.AreEqual("30", reader.GetString(1));
                Assert.AreEqual("New York", reader.GetString(2));
            }
        }

        [TestMethod]
        public void TestPipeDelimiter()
        {
            string csv = "Name|Age|City\nJohn|30|New York";
            var options = new CsvReaderOptions { Delimiter = "|" };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.AreEqual(3, reader.FieldCount);
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
            }
        }

        [TestMethod]
        public void TestMultiCharacterDelimiter()
        {
            // Addresses issue #6488: Add custom multi-character delimiter support
            string csv = "Name^!Age^!City\nJohn^!30^!New York";
            var options = new CsvReaderOptions { Delimiter = "^!" };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.AreEqual(3, reader.FieldCount);
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
                Assert.AreEqual("30", reader.GetString(1));
                Assert.AreEqual("New York", reader.GetString(2));
            }
        }



        [TestMethod]
        public void TestQuotedFields()
        {
            string csv = "Name,Description\nJohn,\"Hello, World\"\nJane,\"Line1\nLine2\"";
            using (var reader = CreateReaderFromString(csv))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("Hello, World", reader.GetString(1));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("Line1\nLine2", reader.GetString(1));
            }
        }

        [TestMethod]
        public void TestEscapedQuotes()
        {
            string csv = "Name,Quote\nJohn,\"He said \"\"Hello\"\"\"";
            using (var reader = CreateReaderFromString(csv))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("He said \"Hello\"", reader.GetString(1));
            }
        }



        [TestMethod]
        public void TestSkipRows()
        {
            // Addresses issue #7173: Import-DbaCsv "FirstRow" Feature
            string csv = "This is a header comment\nAnother comment line\nName,Age\nJohn,30";
            var options = new CsvReaderOptions { SkipRows = 2 };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.AreEqual(2, reader.FieldCount);
                Assert.AreEqual("Name", reader.GetName(0));
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
            }
        }

        [TestMethod]
        public void TestSkipEmptyLines()
        {
            string csv = "Name,Age\n\nJohn,30\n\nJane,25\n";
            var options = new CsvReaderOptions { SkipEmptyLines = true };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("Jane", reader.GetString(0));
                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestCommentLines()
        {
            string csv = "Name,Age\n# This is a comment\nJohn,30";
            var options = new CsvReaderOptions { Comment = '#' };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
                Assert.IsFalse(reader.Read());
            }
        }


        private CsvDataReader CreateReaderFromString(string csv, CsvReaderOptions options = null)
        {
            var stream = new MemoryStream(Encoding.UTF8.GetBytes(csv));
            var textReader = new StreamReader(stream);
            return new CsvDataReader(textReader, options);
        }

    }
}
