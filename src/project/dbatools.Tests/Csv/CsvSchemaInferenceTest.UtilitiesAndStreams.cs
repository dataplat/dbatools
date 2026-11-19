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
    public partial class CsvSchemaInferenceTest
    {

        [TestMethod]
        public void TestGenerateCreateTableStatement_ComplexTable()
        {
            string csvPath = Path.Combine(_tempDir, "complex.csv");
            File.WriteAllText(csvPath, @"Id,Name,Price,IsActive,Created,UniqueId
1,Widget,19.99,true,2024-01-15,550e8400-e29b-41d4-a716-446655440000
2,,29.50,false,2024-02-20,6ba7b810-9dad-11d1-80b4-00c04fd430c8
");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);
            string sql = CsvSchemaInference.GenerateCreateTableStatement(columns, "Products", "sales");

            Assert.IsTrue(sql.Contains("CREATE TABLE [sales].[Products]"));
            Assert.IsTrue(sql.Contains("[Id] int NOT NULL"));
            Assert.IsTrue(sql.Contains("[Name]") && sql.Contains("NULL")); // Name is nullable
            Assert.IsTrue(sql.Contains("[Price] decimal"));
            Assert.IsTrue(sql.Contains("[IsActive] bit"));
            Assert.IsTrue(sql.Contains("[Created] datetime2"));
            Assert.IsTrue(sql.Contains("[UniqueId] uniqueidentifier"));
        }

        [TestMethod]
        public void TestToColumnTypes_Mapping()
        {
            string csvPath = Path.Combine(_tempDir, "types.csv");
            File.WriteAllText(csvPath, @"IntCol,DecCol,BoolCol,DateCol,GuidCol,StrCol
1,1.5,true,2024-01-01,550e8400-e29b-41d4-a716-446655440000,text
");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);
            var typeMap = CsvSchemaInference.ToColumnTypes(columns);

            Assert.AreEqual(typeof(int), typeMap["IntCol"]);
            Assert.AreEqual(typeof(decimal), typeMap["DecCol"]);
            Assert.AreEqual(typeof(bool), typeMap["BoolCol"]);
            Assert.AreEqual(typeof(DateTime), typeMap["DateCol"]);
            Assert.AreEqual(typeof(Guid), typeMap["GuidCol"]);
            Assert.AreEqual(typeof(string), typeMap["StrCol"]);
        }

        [TestMethod]
        public void TestInferredColumn_Properties()
        {
            string csvPath = Path.Combine(_tempDir, "props.csv");
            File.WriteAllText(csvPath, @"Name,Value
John,100
Jane,200
Bob,300
");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            // Check Name column
            Assert.AreEqual("Name", columns[0].ColumnName);
            Assert.AreEqual(0, columns[0].Ordinal);
            Assert.AreEqual(4, columns[0].MaxLength); // "John" is longest
            Assert.IsFalse(columns[0].IsNullable);
            Assert.IsFalse(columns[0].IsUnicode);
            Assert.AreEqual(3, columns[0].TotalCount);
            Assert.AreEqual(3, columns[0].NonNullCount);
        }



        [TestMethod]
        public void TestInferSchema_FromStream()
        {
            string csv = "Id,Name,Value\n1,John,100\n2,Jane,200\n";
            using (var stream = new MemoryStream(Encoding.UTF8.GetBytes(csv)))
            {
                var columns = CsvSchemaInference.InferSchemaFromSample(stream);

                Assert.AreEqual(3, columns.Count);
                Assert.AreEqual("int", columns[0].SqlDataType);
            }
        }

        [TestMethod]
        public void TestInferSchema_FromTextReader()
        {
            string csv = "Id,Name,Value\n1,John,100\n2,Jane,200\n";
            using (var reader = new StringReader(csv))
            {
                var columns = CsvSchemaInference.InferSchemaFromSample(reader);

                Assert.AreEqual(3, columns.Count);
                Assert.AreEqual("int", columns[0].SqlDataType);
            }
        }



        [TestMethod]
        public void TestInferSchema_SalesData()
        {
            string csvPath = Path.Combine(_tempDir, "sales.csv");
            File.WriteAllText(csvPath, @"OrderId,CustomerId,ProductName,Quantity,UnitPrice,Discount,OrderDate,ShipCountry
10248,VINET,Queso Cabrales,12,14.00,0.00,1996-07-04,France
10249,TOMSP,Tofu,9,18.60,0.00,1996-07-05,Germany
10250,HANAR,Sir Rodney's Scones,40,8.00,0.05,1996-07-08,Brazil
10251,VICTE,Manjimup Dried Apples,35,42.40,0.15,1996-07-08,France
10252,SUPRD,Filo Mix,48,5.60,0.10,1996-07-09,Belgium
");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            Assert.AreEqual(8, columns.Count);
            Assert.AreEqual("int", columns[0].SqlDataType);      // OrderId
            Assert.IsTrue(columns[1].SqlDataType.StartsWith("varchar(")); // CustomerId
            Assert.IsTrue(columns[2].SqlDataType.StartsWith("varchar(")); // ProductName
            Assert.AreEqual("int", columns[3].SqlDataType);      // Quantity
            Assert.IsTrue(columns[4].SqlDataType.Contains("decimal")); // UnitPrice
            Assert.IsTrue(columns[5].SqlDataType.Contains("decimal")); // Discount
            Assert.AreEqual("datetime2", columns[6].SqlDataType); // OrderDate
            Assert.IsTrue(columns[7].SqlDataType.StartsWith("varchar(")); // ShipCountry
        }

        [TestMethod]
        public void TestInferSchema_EmployeeData()
        {
            string csvPath = Path.Combine(_tempDir, "employees.csv");
            File.WriteAllText(csvPath, @"EmployeeId,FirstName,LastName,Email,HireDate,Salary,IsManager,DepartmentCode
E001,John,Smith,john.smith@company.com,2020-03-15,75000.00,true,IT
E002,Jane,Doe,jane.doe@company.com,2019-07-22,85000.00,true,HR
E003,Bob,Johnson,bob.j@company.com,2021-01-10,65000.00,false,IT
E004,Alice,Williams,alice.w@company.com,2018-11-05,95000.00,true,FIN
");

            var columns = CsvSchemaInference.InferSchemaFromSample(csvPath);

            Assert.AreEqual(8, columns.Count);
            Assert.IsTrue(columns[0].SqlDataType.StartsWith("varchar(")); // EmployeeId (has letter prefix)
            Assert.AreEqual("datetime2", columns[4].SqlDataType); // HireDate
            Assert.IsTrue(columns[5].SqlDataType.Contains("decimal")); // Salary
            Assert.AreEqual("bit", columns[6].SqlDataType); // IsManager
        }

    }
}
