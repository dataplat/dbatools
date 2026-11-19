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
        public void TestGetOrdinal()
        {
            string csv = "Name,Age,City\nJohn,30,NYC";
            using (var reader = CreateReaderFromString(csv))
            {
                Assert.AreEqual(0, reader.GetOrdinal("Name"));
                Assert.AreEqual(1, reader.GetOrdinal("Age"));
                Assert.AreEqual(2, reader.GetOrdinal("City"));
            }
        }

        [TestMethod]
        public void TestGetOrdinalCaseInsensitive()
        {
            string csv = "Name,Age,City\nJohn,30,NYC";
            using (var reader = CreateReaderFromString(csv))
            {
                Assert.AreEqual(0, reader.GetOrdinal("name"));
                Assert.AreEqual(0, reader.GetOrdinal("NAME"));
            }
        }

        [TestMethod]
        public void TestGetOrdinalNotFound()
        {
            string csv = "Name,Age\nJohn,30";
            using (var reader = CreateReaderFromString(csv))
            {
                Assert.ThrowsException<ArgumentException>(() => reader.GetOrdinal("NonExistent"));
            }
        }

        [TestMethod]
        public void TestGetValues()
        {
            string csv = "Name,Age\nJohn,30";
            using (var reader = CreateReaderFromString(csv))
            {
                Assert.IsTrue(reader.Read());

                object[] values = new object[2];
                int count = reader.GetValues(values);

                Assert.AreEqual(2, count);
                Assert.AreEqual("John", values[0]);
                Assert.AreEqual("30", values[1]);
            }
        }

        [TestMethod]
        public void TestGetSchemaTable()
        {
            string csv = "Name,Age\nJohn,30";
            using (var reader = CreateReaderFromString(csv))
            {
                var schema = reader.GetSchemaTable();

                Assert.AreEqual(2, schema.Rows.Count);
                Assert.AreEqual("Name", schema.Rows[0]["ColumnName"]);
                Assert.AreEqual("Age", schema.Rows[1]["ColumnName"]);
                Assert.AreEqual(typeof(string), schema.Rows[0]["DataType"]);
            }
        }



        [TestMethod]
        public void TestDistinguishEmptyFromNull_WhenEnabled()
        {
            // Addresses LumenWorks issue #68
            // Unquoted empty = null, quoted empty = empty string
            string csv = "A,B,C\n1,,3\n4,\"\",6";
            var options = new CsvReaderOptions { DistinguishEmptyFromNull = true };

            using (var reader = CreateReaderFromString(csv, options))
            {
                // Row 1: 1,,3 - middle field is unquoted empty -> should be DBNull
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("1", reader.GetString(0));
                Assert.IsTrue(reader.IsDBNull(1), "Unquoted empty should be DBNull");
                Assert.AreEqual("3", reader.GetString(2));

                // Row 2: 4,"",6 - middle field is quoted empty -> should be empty string
                Assert.IsTrue(reader.Read());
                Assert.AreEqual("4", reader.GetString(0));
                Assert.IsFalse(reader.IsDBNull(1), "Quoted empty should NOT be DBNull");
                Assert.AreEqual("", reader.GetValue(1));
                Assert.AreEqual("6", reader.GetString(2));
            }
        }

        [TestMethod]
        public void TestDistinguishEmptyFromNull_WhenDisabled()
        {
            // Default behavior - both become DBNull
            string csv = "A,B,C\n1,,3\n4,\"\",6";
            var options = new CsvReaderOptions { DistinguishEmptyFromNull = false };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.IsTrue(reader.IsDBNull(1), "Unquoted empty should be DBNull");

                Assert.IsTrue(reader.Read());
                Assert.IsTrue(reader.IsDBNull(1), "Quoted empty should also be DBNull when DistinguishEmptyFromNull is false");
            }
        }



        [TestMethod]
        public void TestDuplicateHeaders_ThrowException()
        {
            // Default behavior should throw
            string csv = "Name,Age,Name\nJohn,30,Smith";
            var options = new CsvReaderOptions { DuplicateHeaderBehavior = DuplicateHeaderBehavior.ThrowException };

            Assert.ThrowsException<CsvParseException>(() =>
            {
                using (var reader = CreateReaderFromString(csv, options))
                {
                    // Accessing FieldCount triggers header reading
                    var _ = reader.FieldCount;
                }
            });
        }

        [TestMethod]
        public void TestDuplicateHeaders_Rename()
        {
            // Addresses LumenWorks issue #39
            string csv = "Name,Age,Name,Name\nJohn,30,Smith,Jr";
            var options = new CsvReaderOptions { DuplicateHeaderBehavior = DuplicateHeaderBehavior.Rename };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.AreEqual(4, reader.FieldCount);
                Assert.AreEqual("Name", reader.GetName(0));
                Assert.AreEqual("Age", reader.GetName(1));
                Assert.AreEqual("Name_2", reader.GetName(2));
                Assert.AreEqual("Name_3", reader.GetName(3));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
                Assert.AreEqual("Smith", reader.GetString(2));
                Assert.AreEqual("Jr", reader.GetString(3));
            }
        }

        [TestMethod]
        public void TestDuplicateHeaders_UseFirstOccurrence()
        {
            string csv = "Name,Age,Name\nJohn,30,Smith";
            var options = new CsvReaderOptions
            {
                DuplicateHeaderBehavior = DuplicateHeaderBehavior.UseFirstOccurrence,
                MismatchedFieldAction = MismatchedFieldAction.TruncateExtra
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.AreEqual(2, reader.FieldCount);
                Assert.AreEqual("Name", reader.GetName(0));
                Assert.AreEqual("Age", reader.GetName(1));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("John", reader.GetString(0));
                Assert.AreEqual("30", reader.GetString(1));
            }
        }



        [TestMethod]
        public void TestEmptyHeader_GeneratesDefaultName()
        {
            // LumenWorks compatibility: empty headers become Column#
            // Reproduces the issue from dbatools where Import-DbaCsv failed
            // with empty headers causing SQL errors
            string csv = ",ValidHeader\nValue1,Value2";

            using (var reader = CreateReaderFromString(csv))
            {
                Assert.AreEqual(2, reader.FieldCount);
                Assert.AreEqual("Column0", reader.GetName(0));  // Empty header -> Column0
                Assert.AreEqual("ValidHeader", reader.GetName(1));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("Value1", reader.GetString(0));
                Assert.AreEqual("Value2", reader.GetString(1));
            }
        }

        [TestMethod]
        public void TestMultipleEmptyHeaders_GeneratesUniqueNames()
        {
            // Multiple empty headers should each get a unique name based on their index
            string csv = ",,ValidHeader,\nA,B,C,D";

            using (var reader = CreateReaderFromString(csv))
            {
                Assert.AreEqual(4, reader.FieldCount);
                Assert.AreEqual("Column0", reader.GetName(0));
                Assert.AreEqual("Column1", reader.GetName(1));
                Assert.AreEqual("ValidHeader", reader.GetName(2));
                Assert.AreEqual("Column3", reader.GetName(3));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("A", reader.GetString(0));
                Assert.AreEqual("B", reader.GetString(1));
                Assert.AreEqual("C", reader.GetString(2));
                Assert.AreEqual("D", reader.GetString(3));
            }
        }

        [TestMethod]
        public void TestWhitespaceOnlyHeader_GeneratesDefaultName()
        {
            // Whitespace-only headers should also be treated as empty
            string csv = "   ,ValidHeader\nValue1,Value2";

            using (var reader = CreateReaderFromString(csv))
            {
                Assert.AreEqual(2, reader.FieldCount);
                Assert.AreEqual("Column0", reader.GetName(0));  // Whitespace -> Column0
                Assert.AreEqual("ValidHeader", reader.GetName(1));
            }
        }

        [TestMethod]
        public void TestCustomDefaultHeaderName()
        {
            // Users can customize the default header name prefix
            string csv = ",ValidHeader\nValue1,Value2";
            var options = new CsvReaderOptions { DefaultHeaderName = "Field" };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.AreEqual(2, reader.FieldCount);
                Assert.AreEqual("Field0", reader.GetName(0));  // Custom prefix
                Assert.AreEqual("ValidHeader", reader.GetName(1));
            }
        }

        [TestMethod]
        public void TestEmptyHeaderWithTrimming()
        {
            // When trimming is enabled, whitespace headers should still become Column#
            string csv = "  ,  ValidHeader  \nValue1,Value2";
            var options = new CsvReaderOptions { TrimmingOptions = ValueTrimmingOptions.All };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.AreEqual(2, reader.FieldCount);
                Assert.AreEqual("Column0", reader.GetName(0));  // Trimmed empty -> Column0
                Assert.AreEqual("ValidHeader", reader.GetName(1));  // Trimmed
            }
        }

        [TestMethod]
        public void TestEmptyHeaderInMiddle()
        {
            // Empty header in the middle of other headers
            string csv = "First,,Last\nA,B,C";

            using (var reader = CreateReaderFromString(csv))
            {
                Assert.AreEqual(3, reader.FieldCount);
                Assert.AreEqual("First", reader.GetName(0));
                Assert.AreEqual("Column1", reader.GetName(1));  // Middle empty -> Column1
                Assert.AreEqual("Last", reader.GetName(2));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual("A", reader.GetString(0));
                Assert.AreEqual("B", reader.GetString(1));
                Assert.AreEqual("C", reader.GetString(2));
            }
        }

        [TestMethod]
        public void TestDefaultHeaderNameValidation_RejectsNull()
        {
            Assert.ThrowsException<ArgumentNullException>(() =>
            {
                new CsvReaderOptions { DefaultHeaderName = null };
            });
        }

        [TestMethod]
        public void TestDefaultHeaderNameValidation_RejectsEmpty()
        {
            Assert.ThrowsException<ArgumentException>(() =>
            {
                new CsvReaderOptions { DefaultHeaderName = "" };
            });
        }

        [TestMethod]
        public void TestDefaultHeaderNameValidation_RejectsWhitespace()
        {
            Assert.ThrowsException<ArgumentException>(() =>
            {
                new CsvReaderOptions { DefaultHeaderName = "   " };
            });
        }

    }
}
