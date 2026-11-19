using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Threading;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Dataplat.Dbatools.Csv.Reader;

namespace Dataplat.Dbatools.Csv.Tests
{
    [TestClass]
    public partial class CsvSchemaInferenceTest
    {
        private string _tempDir;

        [TestInitialize]
        public void Setup()
        {
            _tempDir = Path.Combine(Path.GetTempPath(), "CsvSchemaInferenceTests_" + Guid.NewGuid().ToString("N"));
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
        public void TestInferSchema_RealFile_MixedTypes()
        {
            string csvPath = Path.Combine(_tempDir, "mixed_types.csv");
            File.WriteAllText(csvPath, @"Id,Name,Price,Quantity,IsActive,Created,UniqueId
1,Widget A,19.99,100,true,2024-01-15,550e8400-e29b-41d4-a716-446655440000
2,Widget B,29.50,50,false,2024-02-20,6ba7b810-9dad-11d1-80b4-00c04fd430c8
3,Gadget C,99.00,25,yes,2024-03-25,f47ac10b-58cc-4372-a567-0e02b2c3d479
4,Thing D,5.99,1000,no,2024-04-30,7c9e6679-7425-40de-944b-e07fc1f90ae7
");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            Assert.AreEqual(7, columns.Count);
            Assert.AreEqual("int", columns[0].SqlDataType);           // Id
            Assert.IsTrue(columns[1].SqlDataType.StartsWith("varchar("));  // Name
            Assert.IsTrue(columns[2].SqlDataType.StartsWith("decimal("));  // Price
            Assert.AreEqual("int", columns[3].SqlDataType);           // Quantity
            Assert.AreEqual("bit", columns[4].SqlDataType);           // IsActive
            Assert.AreEqual("datetime2", columns[5].SqlDataType);     // Created
            Assert.AreEqual("uniqueidentifier", columns[6].SqlDataType); // UniqueId
        }

        [TestMethod]
        public void TestInferSchema_RealFile_LargeIntegers()
        {
            string csvPath = Path.Combine(_tempDir, "large_ints.csv");
            var sb = new StringBuilder();
            sb.AppendLine("SmallInt,RegularInt,BigInt,TooBig");
            sb.AppendLine("100,2000000000,9000000000000000000,99999999999999999999");
            sb.AppendLine("200,1500000000,8000000000000000000,88888888888888888888");
            File.WriteAllText(csvPath, sb.ToString());

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            Assert.AreEqual("int", columns[0].SqlDataType);      // SmallInt fits in int
            Assert.AreEqual("int", columns[1].SqlDataType);      // RegularInt fits in int
            Assert.AreEqual("bigint", columns[2].SqlDataType);   // BigInt needs bigint
            Assert.IsTrue(columns[3].SqlDataType.StartsWith("varchar(") ||
                          columns[3].SqlDataType.StartsWith("decimal(")); // TooBig overflows
        }

        [TestMethod]
        public void TestInferSchema_RealFile_DecimalPrecision()
        {
            string csvPath = Path.Combine(_tempDir, "decimals.csv");
            File.WriteAllText(csvPath, @"Price,Tax,Total,Tiny
19.99,1.50,21.49,0.001
199.99,15.00,214.99,0.002
1999.99,150.00,2149.99,0.003
");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            // All should be decimal with appropriate precision
            Assert.IsTrue(columns[0].SqlDataType.Contains("decimal"));
            Assert.IsTrue(columns[1].SqlDataType.Contains("decimal"));
            Assert.IsTrue(columns[2].SqlDataType.Contains("decimal"));
            Assert.IsTrue(columns[3].SqlDataType.Contains("decimal"));
            Assert.AreEqual(3, columns[3].Scale); // Tiny has 3 decimal places
        }

        [TestMethod]
        public void TestInferSchema_RealFile_NegativeNumbers()
        {
            string csvPath = Path.Combine(_tempDir, "negatives.csv");
            File.WriteAllText(csvPath, @"Temperature,Balance,Change
-10,1000.50,-5.25
25,-500.00,10.00
-40,-1234.56,-0.01
");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            Assert.AreEqual("int", columns[0].SqlDataType);  // Temperature - integers
            Assert.IsTrue(columns[1].SqlDataType.Contains("decimal")); // Balance
            Assert.IsTrue(columns[2].SqlDataType.Contains("decimal")); // Change
        }

        [TestMethod]
        public void TestInferSchema_RealFile_UnicodeStrings()
        {
            string csvPath = Path.Combine(_tempDir, "unicode.csv");
            File.WriteAllText(csvPath, @"Name,City,Description
José García,São Paulo,Développeur senior
田中太郎,東京,ソフトウェアエンジニア
Müller,München,Geschäftsführer
", Encoding.UTF8);

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            Assert.IsTrue(columns[0].SqlDataType.StartsWith("nvarchar("));
            Assert.IsTrue(columns[0].IsUnicode);
            Assert.IsTrue(columns[1].SqlDataType.StartsWith("nvarchar("));
            Assert.IsTrue(columns[2].SqlDataType.StartsWith("nvarchar("));
        }

        [TestMethod]
        public void TestInferSchema_RealFile_DateFormats()
        {
            string csvPath = Path.Combine(_tempDir, "dates.csv");
            File.WriteAllText(csvPath, @"ISO,US,WithTime
2024-01-15,01/15/2024,2024-01-15 14:30:00
2024-02-20,02/20/2024,2024-02-20 09:15:30
2024-03-25,03/25/2024,2024-03-25 18:45:00
");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            Assert.AreEqual("datetime2", columns[0].SqlDataType);
            Assert.AreEqual("datetime2", columns[1].SqlDataType);
            Assert.AreEqual("datetime2", columns[2].SqlDataType);
        }

        [TestMethod]
        public void TestInferSchema_RealFile_BooleanVariants()
        {
            string csvPath = Path.Combine(_tempDir, "booleans.csv");
            File.WriteAllText(csvPath, @"TrueFalse,YesNo,OnOff,TF,YN
true,yes,on,t,y
false,no,off,f,n
TRUE,YES,ON,T,Y
FALSE,NO,OFF,F,N
");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            foreach (var col in columns)
            {
                Assert.AreEqual("bit", col.SqlDataType, String.Format("Column {0} should be bit", col.ColumnName));
            }
        }

        [TestMethod]
        public void TestInferSchema_RealFile_NullableColumns()
        {
            string csvPath = Path.Combine(_tempDir, "nullable.csv");
            File.WriteAllText(csvPath, @"Id,Name,OptionalValue
1,John,100
2,Jane,
3,,200
4,Bob,
");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            Assert.IsFalse(columns[0].IsNullable); // Id has all values
            Assert.IsTrue(columns[1].IsNullable);  // Name has empty
            Assert.IsTrue(columns[2].IsNullable);  // OptionalValue has empty
        }

        [TestMethod]
        public void TestInferSchema_RealFile_VeryLongStrings()
        {
            string csvPath = Path.Combine(_tempDir, "longstrings.csv");
            string longString = new string('x', 5000);
            string veryLongString = new string('y', 10000);
            File.WriteAllText(csvPath, String.Format("Short,Long,VeryLong\nabc,{0},{1}\n", longString, veryLongString));

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            Assert.AreEqual("varchar(3)", columns[0].SqlDataType);
            Assert.AreEqual("varchar(5000)", columns[1].SqlDataType);
            Assert.AreEqual("varchar(max)", columns[2].SqlDataType); // > 8000
        }



        [TestMethod]
        public void TestInferSchema_FullScan_10000Rows()
        {
            string csvPath = Path.Combine(_tempDir, "large.csv");
            using (var writer = new StreamWriter(csvPath))
            {
                writer.WriteLine("Id,Value,Category");
                for (int i = 0; i < 10000; i++)
                {
                    // Mix of values to test type detection
                    string category = i % 10 == 0 ? "A" : (i % 10 == 1 ? "B" : "C");
                    writer.WriteLine(String.Format("{0},{1:F2},{2}", i, i * 1.5m, category));
                }
            }

            var progressValues = new List<double>();
            var columns = CsvSchemaInference.InferSchema(csvPath, null, p => progressValues.Add(p));

            Assert.AreEqual(3, columns.Count);
            Assert.AreEqual("int", columns[0].SqlDataType);
            Assert.IsTrue(columns[1].SqlDataType.Contains("decimal"));
            Assert.IsTrue(columns[2].SqlDataType.StartsWith("varchar("));

            // Progress should have been reported
            Assert.IsTrue(progressValues.Count > 0);
            Assert.AreEqual(1.0, progressValues.Last(), 0.01);

            // Verify row counts
            Assert.AreEqual(10000, columns[0].TotalCount);
        }

        [TestMethod]
        public void TestInferSchema_FullScan_WithCancellation()
        {
            string csvPath = Path.Combine(_tempDir, "cancellable.csv");
            using (var writer = new StreamWriter(csvPath))
            {
                writer.WriteLine("Id,Value");
                for (int i = 0; i < 1000; i++)
                {
                    writer.WriteLine(String.Format("{0},{1}", i, i * 10));
                }
            }

            // Test 1: Pre-cancelled token should throw immediately
            var preCancelledCts = new CancellationTokenSource();
            preCancelledCts.Cancel();

            try
            {
                CsvSchemaInference.InferSchema(csvPath, null, null, preCancelledCts.Token);
                Assert.Fail("Should have thrown OperationCanceledException for pre-cancelled token");
            }
            catch (OperationCanceledException)
            {
                // Expected
            }

            // Test 2: Stream-based inference with cancellation
            var cts = new CancellationTokenSource();

            try
            {
                // Create data in memory
                var sb = new StringBuilder();
                sb.AppendLine("Id,Value");
                for (int i = 0; i < 10000; i++)
                {
                    sb.AppendLine(String.Format("{0},{1}", i, i * 10));
                }

                using (var stream = new MemoryStream(Encoding.UTF8.GetBytes(sb.ToString())))
                {
                    // Cancel after very short time to trigger during read
                    cts.CancelAfter(1);

                    // This may or may not throw depending on timing - just verify it handles gracefully
                    var columns = CsvSchemaInference.InferSchemaFromSample(stream, null, 10000, cts.Token);

                    // If we got here, data was small enough to complete before cancellation
                    // That's acceptable - cancellation is best-effort
                }
            }
            catch (OperationCanceledException)
            {
                // Expected if cancellation kicked in
            }
        }



        [TestMethod]
        public void TestInferSchema_SampleVsFullScan_ConsistentResults()
        {
            string csvPath = Path.Combine(_tempDir, "consistent.csv");
            // Use consistent value ranges so sample and full scan produce same type classifications
            using (var writer = new StreamWriter(csvPath))
            {
                writer.WriteLine("Id,Price,Name");
                for (int i = 0; i < 5000; i++)
                {
                    // Keep all values in same range (1-100, price ~20)
                    writer.WriteLine(String.Format("{0},{1:F2},Product{2}", (i % 100) + 1, 19.99m + (i % 10) * 0.01m, i % 10));
                }
            }

            var sampleColumns = CsvSchemaInference.InferSchemaFromSample(csvPath, null, 100);
            var fullColumns = CsvSchemaInference.InferSchema(csvPath);

            // Base type categories should match (int vs decimal vs string), precision may vary
            Assert.AreEqual("int", sampleColumns[0].SqlDataType);
            Assert.AreEqual("int", fullColumns[0].SqlDataType);
            Assert.IsTrue(sampleColumns[1].SqlDataType.Contains("decimal"));
            Assert.IsTrue(fullColumns[1].SqlDataType.Contains("decimal"));
            Assert.IsTrue(sampleColumns[2].SqlDataType.StartsWith("varchar("));
            Assert.IsTrue(fullColumns[2].SqlDataType.StartsWith("varchar("));
        }

    }
}
