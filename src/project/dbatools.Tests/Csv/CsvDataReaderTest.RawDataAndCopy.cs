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
        public void TestGetCurrentRawData_BasicRecord()
        {
            // LumenWorks compatibility: GetCurrentRawData() returns reconstructed CSV line
            string csv = "Name,Age,City\nJohn,30,New York\nJane,25,Boston";

            using (var reader = CreateReaderFromString(csv))
            {
                Assert.IsTrue(reader.Read());
                string rawData = reader.GetCurrentRawData();
                Assert.AreEqual("John,30,New York", rawData);

                Assert.IsTrue(reader.Read());
                rawData = reader.GetCurrentRawData();
                Assert.AreEqual("Jane,25,Boston", rawData);
            }
        }

        [TestMethod]
        public void TestGetCurrentRawData_QuotedFields()
        {
            // Fields containing delimiters should be quoted in output
            string csv = "Name,Description\nTest,\"Value, with comma\"\nOther,Simple";

            using (var reader = CreateReaderFromString(csv))
            {
                Assert.IsTrue(reader.Read());
                string rawData = reader.GetCurrentRawData();
                // The reconstructed data should quote the field containing comma
                Assert.IsTrue(rawData.Contains("\"Value, with comma\""), String.Format("Expected quoted field, got: {0}", rawData));

                Assert.IsTrue(reader.Read());
                rawData = reader.GetCurrentRawData();
                Assert.AreEqual("Other,Simple", rawData);
            }
        }

        [TestMethod]
        public void TestGetCurrentRawData_NoCurrentRecord()
        {
            // Before Read() is called, should return empty string
            string csv = "Name,Age\nJohn,30";

            using (var reader = CreateReaderFromString(csv))
            {
                string rawData = reader.GetCurrentRawData();
                Assert.AreEqual(string.Empty, rawData);
            }
        }

        [TestMethod]
        public void TestGetCurrentRawData_CustomDelimiter()
        {
            // Should use configured delimiter in reconstructed output
            string csv = "Name|Age|City\nJohn|30|NYC";
            var options = new CsvReaderOptions { Delimiter = "|" };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                string rawData = reader.GetCurrentRawData();
                Assert.AreEqual("John|30|NYC", rawData);
            }
        }

        [TestMethod]
        public void TestCopyCurrentRecordTo_BasicUsage()
        {
            // LumenWorks compatibility: CopyCurrentRecordTo copies field values to array
            string csv = "Name,Age,City\nJohn,30,New York";

            using (var reader = CreateReaderFromString(csv))
            {
                Assert.IsTrue(reader.Read());

                string[] values = new string[3];
                reader.CopyCurrentRecordTo(values);

                Assert.AreEqual("John", values[0]);
                Assert.AreEqual("30", values[1]);
                Assert.AreEqual("New York", values[2]);
            }
        }

        [TestMethod]
        public void TestCopyCurrentRecordTo_WithOffset()
        {
            // Should support copying to array with offset
            string csv = "Name,Age\nJohn,30";

            using (var reader = CreateReaderFromString(csv))
            {
                Assert.IsTrue(reader.Read());

                string[] values = new string[5];
                values[0] = "prefix";
                reader.CopyCurrentRecordTo(values, 2);

                Assert.AreEqual("prefix", values[0]);
                Assert.IsNull(values[1]);
                Assert.AreEqual("John", values[2]);
                Assert.AreEqual("30", values[3]);
            }
        }

        [TestMethod]
        public void TestCopyCurrentRecordTo_NullArray()
        {
            string csv = "Name\nJohn";

            using (var reader = CreateReaderFromString(csv))
            {
                Assert.IsTrue(reader.Read());
                Assert.ThrowsException<ArgumentNullException>(() =>
                {
                    reader.CopyCurrentRecordTo(null);
                });
            }
        }

        [TestMethod]
        public void TestCopyCurrentRecordTo_NegativeIndex()
        {
            string csv = "Name\nJohn";

            using (var reader = CreateReaderFromString(csv))
            {
                Assert.IsTrue(reader.Read());
                Assert.ThrowsException<ArgumentOutOfRangeException>(() =>
                {
                    reader.CopyCurrentRecordTo(new string[1], -1);
                });
            }
        }

        [TestMethod]
        public void TestCopyCurrentRecordTo_InsufficientCapacity()
        {
            string csv = "Name,Age,City\nJohn,30,NYC";

            using (var reader = CreateReaderFromString(csv))
            {
                Assert.IsTrue(reader.Read());
                Assert.ThrowsException<ArgumentException>(() =>
                {
                    reader.CopyCurrentRecordTo(new string[2]); // Need 3, have 2
                });
            }
        }

        [TestMethod]
        public void TestCopyCurrentRecordTo_NoCurrentRecord()
        {
            string csv = "Name\nJohn";

            using (var reader = CreateReaderFromString(csv))
            {
                // Don't call Read()
                Assert.ThrowsException<InvalidOperationException>(() =>
                {
                    reader.CopyCurrentRecordTo(new string[1]);
                });
            }
        }

    }
}
