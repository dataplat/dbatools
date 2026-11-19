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
        public void TestParallelProcessing_BasicReading()
        {
            // Test that parallel processing produces the same results as sequential
            string csv = "Name,Age,City\nJohn,30,New York\nJane,25,Boston\nBob,35,Chicago";
            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                MaxDegreeOfParallelism = 2
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.AreEqual(3, reader.FieldCount);

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
                Assert.AreEqual("30", reader.GetString(1));
                Assert.AreEqual("New York", reader.GetString(2));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("Jane", reader.GetString(0));
                Assert.AreEqual("25", reader.GetString(1));
                Assert.AreEqual("Boston", reader.GetString(2));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("Bob", reader.GetString(0));
                Assert.AreEqual("35", reader.GetString(1));
                Assert.AreEqual("Chicago", reader.GetString(2));

                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestParallelProcessing_LargeFile()
        {
            // Generate a larger CSV file to test parallel processing performance
            var sb = new StringBuilder();
            sb.AppendLine("Id,Name,Value,Description");
            const int rowCount = 1000;
            for (int i = 0; i < rowCount; i++)
            {
                sb.AppendLine(String.Format("{0},Name{0},{1},Description for row {0}", i, i * 10));
            }

            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                MaxDegreeOfParallelism = 4,
                ParallelBatchSize = 50
            };

            using (var reader = CreateReaderFromString(sb.ToString(), options))
            {
                int count = 0;
                while (reader.Read())
                {
                    // Verify data integrity - check that records are delivered in order
                    Assert.AreEqual(count.ToString(), reader.GetString(0));
                    Assert.AreEqual(String.Format("Name{0}", count), reader.GetString(1));
                    Assert.AreEqual((count * 10).ToString(), reader.GetString(2));
                    count++;
                }
                Assert.AreEqual(rowCount, count);
            }
        }

        [TestMethod]
        public void TestParallelProcessing_WithTypeConversion()
        {
            string csv = "Id,Amount,Active\n1,100.50,true\n2,200.75,false\n3,300.25,true";
            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                MaxDegreeOfParallelism = 2,
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Id", typeof(int) },
                    { "Amount", typeof(decimal) },
                    { "Active", typeof(bool) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual(1, reader.GetInt32(0));
                Assert.AreEqual(100.50m, reader.GetDecimal(1));
                Assert.AreEqual(true, reader.GetBoolean(2));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual(2, reader.GetInt32(0));
                Assert.AreEqual(200.75m, reader.GetDecimal(1));
                Assert.AreEqual(false, reader.GetBoolean(2));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual(3, reader.GetInt32(0));
                Assert.AreEqual(300.25m, reader.GetDecimal(1));
                Assert.AreEqual(true, reader.GetBoolean(2));

                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestParallelProcessing_WithQuotedFields()
        {
            string csv = "Name,Description\n\"John Doe\",\"A \"\"quoted\"\" value\"\n\"Jane Smith\",\"Line1\nLine2\"";
            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                MaxDegreeOfParallelism = 2
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John Doe", reader.GetString(0));
                Assert.AreEqual("A \"quoted\" value", reader.GetString(1));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("Jane Smith", reader.GetString(0));
                Assert.AreEqual("Line1\nLine2", reader.GetString(1));

                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestParallelProcessing_SingleThread()
        {
            // Test with MaxDegreeOfParallelism = 1 (effectively sequential but using pipeline)
            string csv = "A,B,C\n1,2,3\n4,5,6";
            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                MaxDegreeOfParallelism = 1
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("1", reader.GetString(0));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("4", reader.GetString(0));

                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestParallelProcessing_EmptyFile()
        {
            string csv = "Name,Age\n";
            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.AreEqual(2, reader.FieldCount);
                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestParallelProcessing_SkipEmptyLines()
        {
            string csv = "Name,Age\n\nJohn,30\n\nJane,25\n";
            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                SkipEmptyLines = true
            };

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
        public void TestParallelProcessing_CommentLines()
        {
            string csv = "Name,Age\n# This is a comment\nJohn,30\n# Another comment\nJane,25";
            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                Comment = '#'
            };

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
        public void TestParallelProcessing_NullValues()
        {
            string csv = "Name,Age\nJohn,NULL\nJane,25";
            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                NullValue = "NULL"
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
                Assert.IsTrue(reader.IsDBNull(1));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("Jane", reader.GetString(0));
                Assert.AreEqual("25", reader.GetString(1));

                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestParallelProcessing_MismatchedFields_PadWithNulls()
        {
            string csv = "A,B,C\n1,2\n4,5,6";
            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                MismatchedFieldAction = MismatchedFieldAction.PadWithNulls
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("1", reader.GetString(0));
                Assert.AreEqual("2", reader.GetString(1));
                Assert.IsTrue(reader.IsDBNull(2));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("4", reader.GetString(0));
                Assert.AreEqual("5", reader.GetString(1));
                Assert.AreEqual("6", reader.GetString(2));

                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestParallelProcessing_NoHeaderRow()
        {
            string csv = "John,30,New York\nJane,25,Boston";
            var options = new CsvReaderOptions
            {
                HasHeaderRow = false,
                EnableParallelProcessing = true
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual(3, reader.FieldCount);
                Assert.AreEqual("Column0", reader.GetName(0));
                Assert.AreEqual("John", reader.GetString(0));
                Assert.AreEqual("30", reader.GetString(1));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("Jane", reader.GetString(0));

                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestParallelProcessing_StaticColumns()
        {
            string csv = "Name,Age\nJohn,30\nJane,25";
            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                StaticColumns = new System.Collections.Generic.List<StaticColumn>
                {
                    new StaticColumn("Source", "TestFile")
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.AreEqual(3, reader.FieldCount);

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
                Assert.AreEqual("TestFile", reader.GetString(2));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("Jane", reader.GetString(0));
                Assert.AreEqual("TestFile", reader.GetString(2));

                Assert.IsFalse(reader.Read());
            }
        }

        [TestMethod]
        public void TestParallelProcessing_Disabled()
        {
            // Verify sequential mode still works correctly
            string csv = "Name,Age\nJohn,30\nJane,25";
            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = false  // Explicitly disabled (default)
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("Jane", reader.GetString(0));

                Assert.IsFalse(reader.Read());
            }
        }

    }
}
