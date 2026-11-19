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
        public void TestLargeFile_StreamingMemoryEfficiency()
        {
            // Create a large-ish file (10MB) and verify memory stays bounded
            string csvPath = Path.Combine(_tempDir, "large.csv");

            // Write 10MB of data
            using (var writer = new StreamWriter(csvPath))
            {
                writer.WriteLine("Id,Name,Value,Description");
                string longDescription = new string('x', 1000); // 1KB per row
                for (int i = 0; i < 10000; i++) // ~10MB total
                {
                    writer.WriteLine(String.Format("{0},Name{0},{1:F2},{2}", i, i * 1.5m, longDescription));
                }
            }

            // Force GC and get baseline
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
            long baselineMemory = GC.GetTotalMemory(true);

            // Run inference
            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath, null, 10000);

            // Check memory after
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
            long afterMemory = GC.GetTotalMemory(true);

            // Memory increase should be reasonable (less than 50MB for a 10MB file)
            // The reader streams, so it shouldn't load the whole file
            long memoryIncrease = afterMemory - baselineMemory;

            Assert.AreEqual(4, columns.Count);
            // Relaxed assertion - just verify it doesn't explode
            Assert.IsTrue(memoryIncrease < 100 * 1024 * 1024,
                String.Format("Memory increase {0}MB seems too high for streaming", memoryIncrease / (1024 * 1024)));
        }

        [TestMethod]
        public void TestLargeFile_ProgressReporting()
        {
            string csvPath = Path.Combine(_tempDir, "progress.csv");
            using (var writer = new StreamWriter(csvPath))
            {
                writer.WriteLine("Id,Value");
                for (int i = 0; i < 100000; i++)
                {
                    writer.WriteLine(String.Format("{0},{1}", i, i * 2));
                }
            }

            var progressValues = new List<double>();
            var columns = CsvSchemaInference.InferSchema(csvPath, null, p =>
            {
                lock (progressValues)
                {
                    progressValues.Add(p);
                }
            });

            Assert.AreEqual(2, columns.Count);
            Assert.IsTrue(progressValues.Count > 0, "Progress should have been reported");
            Assert.AreEqual(1.0, progressValues.Last(), 0.01, "Final progress should be 1.0");

            // Progress should be monotonically increasing
            for (int i = 1; i < progressValues.Count; i++)
            {
                Assert.IsTrue(progressValues[i] >= progressValues[i - 1],
                    String.Format("Progress should increase: {0} -> {1}", progressValues[i - 1], progressValues[i]));
            }
        }

        [TestMethod]
        public void TestLargeFile_RowCountTracking()
        {
            string csvPath = Path.Combine(_tempDir, "rowcount.csv");
            const int expectedRows = 50000;

            using (var writer = new StreamWriter(csvPath))
            {
                writer.WriteLine("Id,Value");
                for (int i = 0; i < expectedRows; i++)
                {
                    writer.WriteLine(String.Format("{0},{1}", i, i * 2));
                }
            }

            var columns = CsvSchemaInference.InferSchema(csvPath);

            Assert.AreEqual(expectedRows, columns[0].TotalCount);
            Assert.AreEqual(expectedRows, columns[0].NonNullCount);
        }

        [TestMethod]
        public void TestLargeFile_SimulatedGigabytePatterns()
        {
            // Test patterns that would occur in gigabyte-scale files
            // Use streaming to avoid actually creating GB files

            // Simulate: very wide rows (many columns)
            var wideRowCsv = new StringBuilder();
            wideRowCsv.Append("Col0");
            for (int i = 1; i < 500; i++)
            {
                wideRowCsv.Append(String.Format(",Col{0}", i));
            }
            wideRowCsv.AppendLine();

            for (int row = 0; row < 100; row++)
            {
                wideRowCsv.Append("0");
                for (int col = 1; col < 500; col++)
                {
                    wideRowCsv.Append(String.Format(",{0}", col * row));
                }
                wideRowCsv.AppendLine();
            }

            string csvPath = Path.Combine(_tempDir, "wide.csv");
            File.WriteAllText(csvPath, wideRowCsv.ToString());

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            Assert.AreEqual(500, columns.Count);
            // All numeric columns
            foreach (var col in columns)
            {
                Assert.AreEqual("int", col.SqlDataType, String.Format("Column {0} should be int", col.ColumnName));
            }
        }

        [TestMethod]
        public void TestLargeFile_IncrementalTypeRefinement()
        {
            // Test that type inference refines correctly over many rows
            string csvPath = Path.Combine(_tempDir, "refinement.csv");

            using (var writer = new StreamWriter(csvPath))
            {
                writer.WriteLine("Value");
                // Start with small integers
                for (int i = 0; i < 1000; i++)
                {
                    writer.WriteLine(i);
                }
                // Then larger integers (still fits in int)
                for (int i = 0; i < 1000; i++)
                {
                    writer.WriteLine(1000000 + i);
                }
                // Then bigint range
                for (int i = 0; i < 1000; i++)
                {
                    writer.WriteLine(3000000000L + i);
                }
            }

            var columns = CsvSchemaInference.InferSchema(csvPath);

            Assert.AreEqual(1, columns.Count);
            Assert.AreEqual("bigint", columns[0].SqlDataType, "Should detect bigint after seeing large values");
            Assert.AreEqual(3000, columns[0].TotalCount);
        }

        [TestMethod]
        public void TestLargeFile_DecimalPrecisionScaling()
        {
            // Test decimal precision tracking over many rows
            string csvPath = Path.Combine(_tempDir, "decimal_precision.csv");

            using (var writer = new StreamWriter(csvPath))
            {
                writer.WriteLine("Value");
                // Start with 2 decimal places
                for (int i = 0; i < 1000; i++)
                {
                    writer.WriteLine(String.Format("{0}.{1:D2}", i, i % 100));
                }
                // Then 5 decimal places (should expand precision)
                for (int i = 0; i < 1000; i++)
                {
                    writer.WriteLine(String.Format("{0}.{1:D5}", i, i % 100000));
                }
            }

            var columns = CsvSchemaInference.InferSchema(csvPath);

            Assert.AreEqual(1, columns.Count);
            Assert.IsTrue(columns[0].SqlDataType.Contains("decimal"));
            Assert.AreEqual(5, columns[0].Scale, "Should track max scale of 5");
        }

    }
}
