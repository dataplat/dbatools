using System;
using System.IO;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Dataplat.Dbatools.Csv.Writer;

namespace Dataplat.Dbatools.Csv.Tests
{
    [TestClass]
    public class CsvWriterTest
    {
        #region Basic Writing Tests

        [TestMethod]
        public void TestBasicWriting()
        {
            var sb = new StringBuilder();
            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw))
            {
                writer.WriteHeader("Name", "Age", "City");
                writer.WriteRow("John", 30, "New York");
                writer.WriteRow("Jane", 25, "Boston");
            }

            string result = sb.ToString();
            Assert.IsTrue(result.Contains("Name,Age,City"));
            Assert.IsTrue(result.Contains("John,30,New York"));
            Assert.IsTrue(result.Contains("Jane,25,Boston"));
        }

        [TestMethod]
        public void TestNoHeader()
        {
            var sb = new StringBuilder();
            var options = new CsvWriterOptions { WriteHeader = false };

            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw, options))
            {
                writer.WriteHeader("Name", "Age");
                writer.WriteRow("John", 30);
            }

            string result = sb.ToString();
            Assert.IsFalse(result.Contains("Name"));
            Assert.IsTrue(result.Contains("John,30"));
        }

        #endregion

        #region Delimiter Tests

        [TestMethod]
        public void TestTabDelimiter()
        {
            var sb = new StringBuilder();
            var options = new CsvWriterOptions { Delimiter = "\t" };

            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw, options))
            {
                writer.WriteHeader("Name", "Age");
                writer.WriteRow("John", 30);
            }

            string result = sb.ToString();
            Assert.IsTrue(result.Contains("Name\tAge"));
            Assert.IsTrue(result.Contains("John\t30"));
        }

        [TestMethod]
        public void TestPipeDelimiter()
        {
            var sb = new StringBuilder();
            var options = new CsvWriterOptions { Delimiter = "|" };

            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw, options))
            {
                writer.WriteHeader("Name", "Age");
                writer.WriteRow("John", 30);
            }

            string result = sb.ToString();
            Assert.IsTrue(result.Contains("Name|Age"));
        }

        #endregion

        #region Quoting Tests

        [TestMethod]
        public void TestQuotingNeeded()
        {
            var sb = new StringBuilder();
            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw))
            {
                writer.WriteHeader("Name", "Description");
                writer.WriteRow("John", "Hello, World");
            }

            string result = sb.ToString();
            // Should quote the field containing a comma
            Assert.IsTrue(result.Contains("\"Hello, World\""));
        }

        [TestMethod]
        public void TestQuotingAlways()
        {
            var sb = new StringBuilder();
            var options = new CsvWriterOptions { QuotingBehavior = CsvQuotingBehavior.Always };

            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw, options))
            {
                writer.WriteHeader("Name", "Age");
                writer.WriteRow("John", 30);
            }

            string result = sb.ToString();
            Assert.IsTrue(result.Contains("\"Name\",\"Age\""));
            Assert.IsTrue(result.Contains("\"John\",\"30\""));
        }

        [TestMethod]
        public void TestQuotingNever()
        {
            var sb = new StringBuilder();
            var options = new CsvWriterOptions { QuotingBehavior = CsvQuotingBehavior.Never };

            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw, options))
            {
                writer.WriteHeader("Name", "Age");
                writer.WriteRow("John", 30);
            }

            string result = sb.ToString();
            Assert.IsFalse(result.Contains("\""));
        }

        [TestMethod]
        public void TestEscapeQuotes()
        {
            var sb = new StringBuilder();
            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw))
            {
                writer.WriteHeader("Name", "Quote");
                writer.WriteRow("John", "He said \"Hello\"");
            }

            string result = sb.ToString();
            // Quotes should be doubled
            Assert.IsTrue(result.Contains("\"He said \"\"Hello\"\"\""));
        }

        #endregion

        #region Null Value Tests

        [TestMethod]
        public void TestNullValueEmpty()
        {
            var sb = new StringBuilder();
            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw))
            {
                writer.WriteHeader("Name", "Age");
                writer.WriteRow("John", null);
            }

            string result = sb.ToString();
            Assert.IsTrue(result.Contains("John,"));
        }

        [TestMethod]
        public void TestNullValueCustom()
        {
            var sb = new StringBuilder();
            var options = new CsvWriterOptions { NullValue = "NULL" };

            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw, options))
            {
                writer.WriteHeader("Name", "Age");
                writer.WriteRow("John", null);
            }

            string result = sb.ToString();
            Assert.IsTrue(result.Contains("John,NULL"));
        }

        [TestMethod]
        public void TestDBNullValue()
        {
            var sb = new StringBuilder();
            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw))
            {
                writer.WriteHeader("Name", "Age");
                writer.WriteRow("John", DBNull.Value);
            }

            string result = sb.ToString();
            Assert.IsTrue(result.Contains("John,"));
        }

        #endregion

        #region Date Time Tests

        [TestMethod]
        public void TestDateTimeFormatting()
        {
            var sb = new StringBuilder();
            var options = new CsvWriterOptions { DateTimeFormat = "yyyy-MM-dd" };

            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw, options))
            {
                writer.WriteHeader("Name", "Created");
                writer.WriteRow("John", new DateTime(2024, 1, 15, 10, 30, 0));
            }

            string result = sb.ToString();
            Assert.IsTrue(result.Contains("2024-01-15"));
        }

        [TestMethod]
        public void TestDateTimeFormattingWithTime()
        {
            var sb = new StringBuilder();
            var options = new CsvWriterOptions { DateTimeFormat = "yyyy-MM-dd HH:mm:ss" };

            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw, options))
            {
                writer.WriteHeader("Name", "Created");
                writer.WriteRow("John", new DateTime(2024, 1, 15, 10, 30, 45));
            }

            string result = sb.ToString();
            Assert.IsTrue(result.Contains("2024-01-15 10:30:45"));
        }

        #endregion

        #region Row Count Tests

        [TestMethod]
        public void TestRowsWritten()
        {
            var sb = new StringBuilder();
            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw))
            {
                writer.WriteHeader("Name", "Age");
                Assert.AreEqual(0, writer.RowsWritten);

                writer.WriteRow("John", 30);
                Assert.AreEqual(1, writer.RowsWritten);

                writer.WriteRow("Jane", 25);
                Assert.AreEqual(2, writer.RowsWritten);
            }
        }

        #endregion

        #region Boolean Formatting Tests

        [TestMethod]
        public void TestBooleanFormatting()
        {
            var sb = new StringBuilder();
            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw))
            {
                writer.WriteHeader("Name", "Active");
                writer.WriteRow("John", true);
                writer.WriteRow("Jane", false);
            }

            string result = sb.ToString();
            Assert.IsTrue(result.Contains("John,true"));
            Assert.IsTrue(result.Contains("Jane,false"));
        }

        #endregion

        #region Newline Tests

        [TestMethod]
        public void TestCustomNewline()
        {
            var sb = new StringBuilder();
            var options = new CsvWriterOptions { NewLine = "\n" };

            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw, options))
            {
                writer.WriteHeader("Name");
                writer.WriteRow("John");
            }

            string result = sb.ToString();
            Assert.IsFalse(result.Contains("\r"));
            Assert.IsTrue(result.Contains("\n"));
        }

        #endregion

        #region Dictionary Row Tests

        [TestMethod]
        public void TestDictionaryRow()
        {
            var sb = new StringBuilder();
            using (var sw = new StringWriter(sb))
            using (var writer = new CsvWriter(sw))
            {
                var row = new System.Collections.Generic.Dictionary<string, object>
                {
                    { "Name", "John" },
                    { "Age", 30 },
                    { "City", "NYC" }
                };
                writer.WriteRow(row);
            }

            string result = sb.ToString();
            Assert.IsTrue(result.Contains("Name,Age,City") || result.Contains("Name") && result.Contains("John"));
        }

        #endregion
    }
}
