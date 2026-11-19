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
        public void TestNumericConversion()
        {
            string csv = "Int,Long,Double,Decimal\n42,9999999999,3.14159,123.45";
            var options = new CsvReaderOptions
            {
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Int", typeof(int) },
                    { "Long", typeof(long) },
                    { "Double", typeof(double) },
                    { "Decimal", typeof(decimal) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual(42, reader.GetInt32(0));
                Assert.AreEqual(9999999999L, reader.GetInt64(1));
                Assert.AreEqual(3.14159, reader.GetDouble(2), 0.00001);
                Assert.AreEqual(123.45m, reader.GetDecimal(3));
            }
        }

    }
}
