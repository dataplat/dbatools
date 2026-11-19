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
        public void TestParallelProcessing_ConcurrentGetValueAccess()
        {
            // Stress test: Multiple threads calling GetValue while Read() advances
            // This tests the thread-safety of _convertedValues access
            var sb = new StringBuilder();
            sb.AppendLine("Id,Name,Value");
            const int rowCount = 500;
            for (int i = 0; i < rowCount; i++)
            {
                sb.AppendLine(String.Format("{0},Name{0},{1}", i, i * 10));
            }

            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                MaxDegreeOfParallelism = 4
            };

            using (var reader = CreateReaderFromString(sb.ToString(), options))
            {
                var errors = new System.Collections.Concurrent.ConcurrentBag<Exception>();
                int recordsProcessed = 0;

                while (reader.Read())
                {
                    System.Threading.Interlocked.Increment(ref recordsProcessed);

                    // Spawn multiple threads to read values concurrently
                    var tasks = new System.Threading.Tasks.Task[4];
                    for (int t = 0; t < tasks.Length; t++)
                    {
                        int threadId = t;
                        tasks[t] = System.Threading.Tasks.Task.Run(() =>
                        {
                            try
                            {
                                // Read all values multiple times
                                for (int iteration = 0; iteration < 10; iteration++)
                                {
                                    var val0 = reader.GetValue(0);
                                    var val1 = reader.GetValue(1);
                                    var val2 = reader.GetValue(2);

                                    // Also test GetValues
                                    var values = new object[3];
                                    reader.GetValues(values);

                                    // Access CurrentRecordIndex
                                    var idx = reader.CurrentRecordIndex;
                                }
                            }
                            catch (Exception ex) when (!(ex is ObjectDisposedException))
                            {
                                errors.Add(ex);
                            }
                        });
                    }

                    System.Threading.Tasks.Task.WaitAll(tasks);
                }

                Assert.AreEqual(rowCount, recordsProcessed, "Should process all records");
                Assert.AreEqual(0, errors.Count, String.Format("Should have no errors, but got: {0}", string.Join(", ", errors)));
            }
        }

        [TestMethod]
        public void TestParallelProcessing_HighConcurrencyStress()
        {
            // High-concurrency stress test with many worker threads
            var sb = new StringBuilder();
            sb.AppendLine("A,B,C,D,E,F,G,H,I,J");
            const int rowCount = 1000;
            for (int i = 0; i < rowCount; i++)
            {
                sb.AppendLine(String.Format("{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}", i, i + 1, i + 2, i + 3, i + 4, i + 5, i + 6, i + 7, i + 8, i + 9));
            }

            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                MaxDegreeOfParallelism = Environment.ProcessorCount
            };

            using (var reader = CreateReaderFromString(sb.ToString(), options))
            {
                var errors = new System.Collections.Concurrent.ConcurrentBag<Exception>();
                var allValues = new System.Collections.Concurrent.ConcurrentBag<long>();

                while (reader.Read())
                {
                    long recordIndex = reader.CurrentRecordIndex;
                    allValues.Add(recordIndex);

                    // Concurrent reads from many threads
                    System.Threading.Tasks.Parallel.For(0, 8, threadIdx =>
                    {
                        try
                        {
                            var values = new object[10];
                            int count = reader.GetValues(values);
                            Assert.AreEqual(10, count, "Should return all 10 values");
                        }
                        catch (Exception ex) when (!(ex is ObjectDisposedException))
                        {
                            errors.Add(ex);
                        }
                    });
                }

                Assert.AreEqual(rowCount, allValues.Count, "Should process all records");
                Assert.AreEqual(0, errors.Count, String.Format("Should have no errors: {0}", string.Join("; ", errors)));

                // Verify all record indices were captured (0 to rowCount-1)
                var sortedIndices = allValues.OrderBy(x => x).ToList();
                for (int i = 0; i < rowCount; i++)
                {
                    Assert.AreEqual(i, sortedIndices[i], String.Format("Record index {0} should be present", i));
                }
            }
        }

        [TestMethod]
        public void TestParallelProcessing_CurrentRecordIndexConsistency()
        {
            // Test that CurrentRecordIndex remains consistent during parallel processing
            var sb = new StringBuilder();
            sb.AppendLine("Id,Value");
            const int rowCount = 200;
            for (int i = 0; i < rowCount; i++)
            {
                sb.AppendLine(String.Format("{0},{1}", i, i * 100));
            }

            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                MaxDegreeOfParallelism = 4
            };

            using (var reader = CreateReaderFromString(sb.ToString(), options))
            {
                long lastIndex = -1;

                while (reader.Read())
                {
                    long currentIndex = reader.CurrentRecordIndex;

                    // Verify record indices are strictly increasing
                    Assert.IsTrue(currentIndex > lastIndex,
                        String.Format("Record index should increase: last={0}, current={1}", lastIndex, currentIndex));

                    // Read the index multiple times from different threads
                    var indices = new System.Collections.Concurrent.ConcurrentBag<long>();
                    System.Threading.Tasks.Parallel.For(0, 4, _ =>
                    {
                        indices.Add(reader.CurrentRecordIndex);
                    });

                    // All reads should return the same index (no torn reads)
                    var uniqueIndices = indices.Distinct().ToList();
                    Assert.AreEqual(1, uniqueIndices.Count,
                        String.Format("All concurrent reads should return same index, got: {0}", string.Join(", ", uniqueIndices)));

                    lastIndex = currentIndex;
                }

                Assert.AreEqual(rowCount - 1, lastIndex, "Should have processed all records");
            }
        }

        [TestMethod]
        public void TestParallelProcessing_DisposeDuringRead()
        {
            // Test that disposing the reader while threads are accessing it doesn't crash
            var sb = new StringBuilder();
            sb.AppendLine("Id,Name,Value");
            for (int i = 0; i < 100; i++)
            {
                sb.AppendLine(String.Format("{0},Name{0},{1}", i, i * 10));
            }

            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                MaxDegreeOfParallelism = 4
            };

            var errors = new System.Collections.Concurrent.ConcurrentBag<Exception>();
            using (var readStarted = new System.Threading.ManualResetEventSlim(false))
            using (var continueReading = new System.Threading.ManualResetEventSlim(false))
            {
                var reader = CreateReaderFromString(sb.ToString(), options);
                try
                {
                    // Start reading in the background and wait until the reader has entered the loop.
                    var readTask = System.Threading.Tasks.Task.Run(() =>
                    {
                        try
                        {
                            while (reader.Read())
                            {
                                readStarted.Set();
                                if (!continueReading.Wait(TimeSpan.FromSeconds(5)))
                                {
                                    errors.Add(new TimeoutException("Timed out waiting to continue dispose test."));
                                    return;
                                }
                            }
                        }
                        catch (ObjectDisposedException)
                        {
                            // Expected when reader is disposed
                        }
                        catch (Exception ex)
                        {
                            errors.Add(ex);
                        }
                    });

                    Assert.IsTrue(readStarted.Wait(TimeSpan.FromSeconds(5)), "Reader should start before dispose.");
                    reader.Dispose();
                    continueReading.Set();

                    Assert.IsTrue(readTask.Wait(TimeSpan.FromSeconds(5)), "Read task should finish after dispose.");
                }
                finally
                {
                    continueReading.Set();
                    reader.Dispose();
                }
            }

            // Should not have unexpected errors (ObjectDisposedException is fine)
            foreach (var error in errors)
            {
                Assert.Fail(String.Format("Unexpected error during dispose: {0}", error));
            }
        }

        [TestMethod]
        public void TestParallelProcessing_RepeatedGetValuesStress()
        {
            // Stress test repeated GetValues calls to detect race conditions in Array.Copy
            var sb = new StringBuilder();
            sb.AppendLine("Col1,Col2,Col3,Col4,Col5");
            const int rowCount = 300;
            for (int i = 0; i < rowCount; i++)
            {
                sb.AppendLine(String.Format("A{0},B{0},C{0},D{0},E{0}", i));
            }

            var options = new CsvReaderOptions
            {
                EnableParallelProcessing = true,
                MaxDegreeOfParallelism = 4
            };

            using (var reader = CreateReaderFromString(sb.ToString(), options))
            {
                int recordCount = 0;
                var inconsistencies = new System.Collections.Concurrent.ConcurrentBag<string>();

                while (reader.Read())
                {
                    recordCount++;
                    string expectedPrefix = String.Format("A{0}", reader.CurrentRecordIndex);

                    // Multiple threads calling GetValues simultaneously
                    System.Threading.Tasks.Parallel.For(0, 10, iteration =>
                    {
                        var values = new object[5];
                        reader.GetValues(values);

                        // Check that all values are from the same record (consistent snapshot)
                        string val0 = values[0]?.ToString() ?? "";
                        string val1 = values[1]?.ToString() ?? "";

                        // Extract the numeric suffix
                        if (val0.StartsWith("A") && val1.StartsWith("B"))
                        {
                            string suffix0 = val0.Substring(1);
                            string suffix1 = val1.Substring(1);

                            if (suffix0 != suffix1)
                            {
                                inconsistencies.Add(String.Format("Inconsistent record: {0} vs {1}", val0, val1));
                            }
                        }
                    });
                }

                Assert.AreEqual(rowCount, recordCount, "Should process all records");
                Assert.AreEqual(0, inconsistencies.Count,
                    String.Format("Should have consistent snapshots: {0}", string.Join("; ", inconsistencies.Take(5))));
            }
        }

    }
}
