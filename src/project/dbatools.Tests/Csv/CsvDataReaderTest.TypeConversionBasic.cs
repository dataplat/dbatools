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
        public void TestBooleanConversion()
        {
            // Addresses issue #8409: 1 and 0 should convert to boolean
            string csv = "Name,Active\nJohn,1\nJane,0\nBob,true\nAlice,false";
            var options = new CsvReaderOptions
            {
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Active", typeof(bool) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.AreEqual(true, reader.GetBoolean(1));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual(false, reader.GetBoolean(1));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual(true, reader.GetBoolean(1));

                Assert.IsTrue(reader.Read());
                Assert.AreEqual(false, reader.GetBoolean(1));
            }
        }

        [TestMethod]
        public void TestGuidConversion()
        {
            // Addresses issue #9433: GUID target column support
            string csv = "Id,Name\n550e8400-e29b-41d4-a716-446655440000,Test";
            var options = new CsvReaderOptions
            {
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Id", typeof(Guid) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Guid expected = Guid.Parse("550e8400-e29b-41d4-a716-446655440000");
                Assert.AreEqual(expected, reader.GetGuid(0));
            }
        }

    }
}
