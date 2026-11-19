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
    /// <summary>
    /// Stress tests and edge case tests for CSV processing.
    /// Covers: concurrent schema inference, malformed data, large file handling, and memory efficiency.
    /// </summary>
    [TestClass]
    public partial class CsvStressAndEdgeCaseTests
    {
        private string _tempDir;

        [TestInitialize]
        public void Setup()
        {
            _tempDir = Path.Combine(Path.GetTempPath(), "CsvStressTests_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_tempDir);
        }

        [TestCleanup]
        public void Cleanup()
        {
            if (Directory.Exists(_tempDir))
            {
                try { Directory.Delete(_tempDir, true); } catch { }
            }
        }


        [TestMethod]
        public void TestConcurrentSchemaInference_MultipleFilesInParallel()
        {
            // Create multiple CSV files with different schemas
            var files = new List<string>();
            for (int i = 0; i < 10; i++)
            {
                string csvPath = Path.Combine(_tempDir, String.Format("concurrent_{0}.csv", i));
                var sb = new StringBuilder();
                sb.AppendLine(String.Format("Id,Name,Value{0}", i));
                for (int j = 0; j < 100; j++)
                {
                    sb.AppendLine(String.Format("{0},Name{0},{1:F2}", j, j * 1.5m));
                }
                File.WriteAllText(csvPath, sb.ToString());
                files.Add(csvPath);
            }

            var errors = new ConcurrentBag<Exception>();
            var results = new ConcurrentDictionary<int, List<InferredColumn>>();

            // Run schema inference in parallel on different files
            Parallel.For(0, files.Count, new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount }, i =>
            {
                try
                {
                    var columns = CsvSchemaInference.InferSchemaFromSample(files[i]);
                    results[i] = columns;

                    // Verify each file's schema is correct
                    Assert.AreEqual(3, columns.Count, String.Format("File {0} should have 3 columns", i));
                    Assert.AreEqual("int", columns[0].SqlDataType, String.Format("File {0} Id should be int", i));
                    Assert.IsTrue(columns[2].SqlDataType.Contains("decimal"), String.Format("File {0} Value{0} should be decimal", i));
                }
                catch (Exception ex)
                {
                    errors.Add(ex);
                }
            });

            Assert.AreEqual(0, errors.Count, String.Format("Errors occurred: {0}", string.Join(", ", errors.Select(e => e.Message))));
            Assert.AreEqual(files.Count, results.Count, "All files should have been processed");
        }

        [TestMethod]
        public void TestConcurrentSchemaInference_SameFileConcurrentReads()
        {
            // Create a single CSV file
            string csvPath = Path.Combine(_tempDir, "shared.csv");
            var sb = new StringBuilder();
            sb.AppendLine("Id,Name,Value,Date");
            for (int i = 0; i < 1000; i++)
            {
                sb.AppendLine(String.Format("{0},Name{0},{1:F2},2024-{2:D2}-{3:D2}", i, i * 2.5m, (i % 12) + 1, (i % 28) + 1));
            }
            File.WriteAllText(csvPath, sb.ToString());

            var errors = new ConcurrentBag<Exception>();
            var results = new ConcurrentBag<List<InferredColumn>>();

            // Multiple threads reading the same file (separate file handles)
            Parallel.For(0, 20, new ParallelOptions { MaxDegreeOfParallelism = 8 }, i =>
            {
                try
                {
                    var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);
                    results.Add(columns);

                    // All should get the same schema
                    Assert.AreEqual(4, columns.Count);
                    Assert.AreEqual("int", columns[0].SqlDataType);
                    Assert.IsTrue(columns[2].SqlDataType.Contains("decimal"));
                    Assert.AreEqual("datetime2", columns[3].SqlDataType);
                }
                catch (Exception ex)
                {
                    errors.Add(ex);
                }
            });

            Assert.AreEqual(0, errors.Count, String.Format("Errors: {0}", string.Join("; ", errors.Select(e => e.Message))));
            Assert.AreEqual(20, results.Count);

            // Verify all results are consistent
            var firstResult = results.First();
            foreach (var result in results)
            {
                for (int i = 0; i < firstResult.Count; i++)
                {
                    Assert.AreEqual(firstResult[i].SqlDataType, result[i].SqlDataType,
                        String.Format("Column {0} type mismatch between parallel runs", i));
                }
            }
        }

        [TestMethod]
        public void TestConcurrentSchemaInference_WithCancellation()
        {
            // Create a large file
            string csvPath = Path.Combine(_tempDir, "cancellable.csv");
            var sb = new StringBuilder();
            sb.AppendLine("Id,Value");
            for (int i = 0; i < 50000; i++)
            {
                sb.AppendLine(String.Format("{0},{1:F2}", i, i * 1.5m));
            }
            File.WriteAllText(csvPath, sb.ToString());

            var completedCount = 0;
            var cancelledCount = 0;
            var errorCount = 0;

            Parallel.For(0, 10, i =>
            {
                var cts = new CancellationTokenSource();

                // Cancel some operations randomly
                if (i % 2 == 0)
                {
                    cts.CancelAfter(1); // Cancel almost immediately
                }

                try
                {
                    using (var stream = File.OpenRead(csvPath))
                    {
                        var columns = CsvSchemaInference.InferSchemaFromSample(stream, null, 50000, cts.Token);
                        Interlocked.Increment(ref completedCount);
                    }
                }
                catch (OperationCanceledException)
                {
                    Interlocked.Increment(ref cancelledCount);
                }
                catch
                {
                    Interlocked.Increment(ref errorCount);
                }
            });

            // Some should complete, some should be cancelled
            Assert.IsTrue(completedCount + cancelledCount == 10, "All operations should either complete or be cancelled");
            Assert.AreEqual(0, errorCount, "No unexpected errors should occur");
        }

        [TestMethod]
        public void TestColumnTypeAnalyzer_NoSharedStateBetweenInferences()
        {
            // Ensure separate inference calls don't share state
            string csvPath1 = Path.Combine(_tempDir, "file1.csv");
            string csvPath2 = Path.Combine(_tempDir, "file2.csv");

            // File 1: Integers
            File.WriteAllText(csvPath1, "Value\n1\n2\n3\n");

            // File 2: Strings (should not be affected by file1's integer detection)
            File.WriteAllText(csvPath2, "Value\nabc\ndef\nghi\n");

            // Run concurrently
            var task1 = Task.Run(() => CsvSchemaInference.InferSchemaFromSample(csvPath1));
            var task2 = Task.Run(() => CsvSchemaInference.InferSchemaFromSample(csvPath2));

            Task.WaitAll(task1, task2);

            Assert.AreEqual("int", task1.Result[0].SqlDataType, "File 1 should detect integers");
            Assert.IsTrue(task1.Result[0].SqlDataType == "int");
            Assert.IsTrue(task2.Result[0].SqlDataType.StartsWith("varchar("), "File 2 should detect strings");
        }

    }
}
