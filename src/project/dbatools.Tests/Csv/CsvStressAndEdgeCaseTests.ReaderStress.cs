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
        public void TestReader_RapidOpenClose()
        {
            // Rapidly open and close readers to test resource cleanup
            string csvPath = Path.Combine(_tempDir, "rapid.csv");
            File.WriteAllText(csvPath, "Id,Name\n1,John\n2,Jane\n");

            var errors = new ConcurrentBag<Exception>();

            Parallel.For(0, 100, i =>
            {
                try
                {
                    for (int j = 0; j < 10; j++)
                    {
                        using (var stream = File.OpenRead(csvPath))
                        using (var reader = new CsvDataReader(stream, null))
                        {
                            while (reader.Read())
                            {
                                var _ = reader.GetString(0);
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    errors.Add(ex);
                }
            });

            Assert.AreEqual(0, errors.Count, String.Format("Errors: {0}", string.Join("; ", errors.Select(e => e.Message))));
        }

        [TestMethod]
        public void TestReader_ConcurrentFieldAccess()
        {
            // Test concurrent access to different fields of the same record
            string csvPath = Path.Combine(_tempDir, "concurrent_fields.csv");
            var sb = new StringBuilder();
            sb.AppendLine("A,B,C,D,E,F,G,H,I,J");
            for (int i = 0; i < 1000; i++)
            {
                sb.AppendLine(String.Format("{0},B{0},C{0},D{0},E{0},F{0},G{0},H{0},I{0},J{0}", i));
            }
            File.WriteAllText(csvPath, sb.ToString());

            var errors = new ConcurrentBag<Exception>();

            using (var reader = new CsvDataReader(csvPath, null))
            {
                while (reader.Read())
                {
                    // Access different fields concurrently
                    Parallel.For(0, reader.FieldCount, i =>
                    {
                        try
                        {
                            var value = reader.GetString(i);
                            Assert.IsNotNull(value);
                        }
                        catch (Exception ex) when (!(ex is ObjectDisposedException))
                        {
                            errors.Add(ex);
                        }
                    });
                }
            }

            Assert.AreEqual(0, errors.Count, String.Format("Errors: {0}", string.Join("; ", errors.Select(e => e.Message))));
        }

        [TestMethod]
        public void TestReader_DisposeWhileReading()
        {
            // Test that dispose during read doesn't cause crashes
            string csvPath = Path.Combine(_tempDir, "dispose.csv");
            var sb = new StringBuilder();
            sb.AppendLine("Id,Value");
            for (int i = 0; i < 10000; i++)
            {
                sb.AppendLine(String.Format("{0},{1}", i, i * 2));
            }
            File.WriteAllText(csvPath, sb.ToString());

            var errors = new ConcurrentBag<Exception>();

            for (int trial = 0; trial < 10; trial++)
            {
                var reader = new CsvDataReader(csvPath, null);
                var readTask = Task.Run(() =>
                {
                    try
                    {
                        while (reader.Read())
                        {
                            var _ = reader.GetString(0);
                        }
                    }
                    catch (ObjectDisposedException)
                    {
                        // Expected when disposed during read
                    }
                    catch (CsvParseException cpe) when (cpe.ParseError != null && cpe.ParseError.Exception is ObjectDisposedException)
                    {
                        // Same dispose race, wrapped: the parse-error handler
                        // (CsvDataReader.Conversion.cs) re-wraps the mid-parse
                        // ObjectDisposedException via the (message, CsvParseError) ctor,
                        // which carries it only in ParseError.Exception. Genuine parse
                        // errors still fall through to the errors bag below.
                    }
                    // The former wrapped-NRE tolerance is deliberately GONE (codex: a test that
                    // accepts the defect cannot verify its fix). Since the active-read-count
                    // dispose contract, the ONLY legal outcomes of a dispose race are clean
                    // completion, ObjectDisposedException, or the wrapped-ODE shape above -
                    // any NRE (raw or wrapped) now lands in the errors bag and fails the test.
                    catch (Exception ex)
                    {
                        errors.Add(ex);
                    }
                });

                // Dispose after a short delay
                Thread.Sleep(1);
                reader.Dispose();

                try
                {
                    readTask.Wait(1000);
                }
                catch
                {
                    // Timeout is fine
                }
            }

            // Full ToString + the CsvParseException's carried ParseError.Exception (which
            // the (message, CsvParseError) ctor does NOT surface as InnerException) so a
            // failure names the actual racy shape instead of the bare "CSV parse error".
            Assert.AreEqual(0, errors.Count, String.Format("Errors: {0}", string.Join(" ||| ", errors.Select(e =>
                e is CsvParseException cpeDetail && cpeDetail.ParseError != null && cpeDetail.ParseError.Exception != null
                    ? e.ToString() + " [ParseError.Exception: " + cpeDetail.ParseError.Exception.ToString() + "]"
                    : e.ToString()))));
        }



        private CsvDataReader CreateReaderFromString(string csv, CsvReaderOptions options = null)
        {
            var stream = new MemoryStream(Encoding.UTF8.GetBytes(csv));
            var textReader = new StreamReader(stream);
            return new CsvDataReader(textReader, options);
        }

    }
}
