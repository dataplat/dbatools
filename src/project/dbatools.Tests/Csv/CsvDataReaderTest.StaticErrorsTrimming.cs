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
        public void TestStaticColumns()
        {
            // Addresses issue #6676: Static column mappings for storing/tagging metadata
            string csv = "Name,Age\nJohn,30\nJane,25";
            var options = new CsvReaderOptions
            {
                StaticColumns = new System.Collections.Generic.List<StaticColumn>
                {
                    new StaticColumn("FileName", "test.csv"),
                    new StaticColumn("ImportDate", DateTime.Today, typeof(DateTime))
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.AreEqual(4, reader.FieldCount);
                Assert.AreEqual("Name", reader.GetName(0));
                Assert.AreEqual("Age", reader.GetName(1));
                Assert.AreEqual("FileName", reader.GetName(2));
                Assert.AreEqual("ImportDate", reader.GetName(3));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
                Assert.AreEqual("test.csv", reader.GetValue(2));
                Assert.AreEqual(DateTime.Today, reader.GetValue(3));
            }
        }

        [TestMethod]
        public void TestRowNumberStaticColumn()
        {
            string csv = "Name\nJohn\nJane\nBob";
            var options = new CsvReaderOptions
            {
                StaticColumns = new System.Collections.Generic.List<StaticColumn>
                {
                    StaticColumn.RowNumber("RowNum")
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual(1L, reader.GetValue(1));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual(2L, reader.GetValue(1));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual(3L, reader.GetValue(1));
            }
        }



        [TestMethod]
        public void TestParseErrorCollection()
        {
            // Addresses issue #6899: View/log bad rows during import
            string csv = "Name,Age\nJohn,30\nBadRow\nJane,25";
            var options = new CsvReaderOptions
            {
                CollectParseErrors = true,
                ParseErrorAction = CsvParseErrorAction.AdvanceToNextLine
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                int rowCount = 0;
                while (reader.Read())
                {
                    rowCount++;
                }

                // Should have read 2 valid rows (John and Jane)
                Assert.AreEqual(2, rowCount);
            }
        }

        [TestMethod]
        public void TestNullValue()
        {
            string csv = "Name,Age\nJohn,NULL\nJane,25";
            var options = new CsvReaderOptions { NullValue = "NULL" };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.IsTrue(reader.IsDBNull(1));

                Assert.IsTrue(reader.Read());
                Assert.IsFalse(reader.IsDBNull(1));
            }
        }



        [TestMethod]
        public void TestTrimAll()
        {
            string csv = "Name,Age\n  John  ,  30  ";
            var options = new CsvReaderOptions { TrimmingOptions = ValueTrimmingOptions.All };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
                Assert.AreEqual("30", reader.GetString(1));
            }
        }

        [TestMethod]
        public void TestNoTrimming()
        {
            string csv = "Name,Age\n  John  ,  30  ";
            var options = new CsvReaderOptions { TrimmingOptions = ValueTrimmingOptions.None };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("  John  ", reader.GetString(0));
                Assert.AreEqual("  30  ", reader.GetString(1));
            }
        }

    }
}
