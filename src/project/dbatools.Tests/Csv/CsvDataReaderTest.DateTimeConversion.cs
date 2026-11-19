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
        public void TestDateTimeConversion()
        {
            string csv = "Name,Created\nJohn,2024-01-15 10:30:00";
            var options = new CsvReaderOptions
            {
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Created", typeof(DateTime) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                DateTime dt = reader.GetDateTime(1);
                Assert.AreEqual(2024, dt.Year);
                Assert.AreEqual(1, dt.Month);
                Assert.AreEqual(15, dt.Day);
            }
        }

        [TestMethod]
        public void TestDateTimeConversionWithCustomFormats()
        {
            // Addresses issue #43: Import-DbaCsv ignores -DateTimeFormats switch
            // Test that dd/MM/yyyy format is correctly parsed when specified in DateTimeFormats
            string csv = "Character Column,Test Date Time,Character Column 2\nTest data,04/02/2026 15:14:21,ABC123\nTest Data2,04/02/2026 15:14:21,MNB675";
            var options = new CsvReaderOptions
            {
                DateTimeFormats = new[] { "dd/MM/yyyy HH:mm:ss" },
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Test Date Time", typeof(DateTime) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                DateTime dt = reader.GetDateTime(1);
                Assert.AreEqual(2026, dt.Year);
                Assert.AreEqual(2, dt.Month, "Month should be February (2), not April (4)");
                Assert.AreEqual(4, dt.Day, "Day should be 4");
                Assert.AreEqual(15, dt.Hour);
                Assert.AreEqual(14, dt.Minute);
                Assert.AreEqual(21, dt.Second);

                Assert.IsTrue(reader.Read());
                dt = reader.GetDateTime(1);
                Assert.AreEqual(2026, dt.Year);
                Assert.AreEqual(2, dt.Month, "Month should be February (2), not April (4)");
                Assert.AreEqual(4, dt.Day, "Day should be 4");
            }
        }

        [TestMethod]
        public void TestDateTimeConversionWithCulture()
        {
            // Test that Culture parameter is respected for DateTime parsing
            string csv = "Name,Date\nJohn,04/02/2026";
            var options = new CsvReaderOptions
            {
                Culture = new System.Globalization.CultureInfo("en-GB"),
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Date", typeof(DateTime) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                DateTime dt = reader.GetDateTime(1);
                Assert.AreEqual(2026, dt.Year);
                Assert.AreEqual(2, dt.Month, "With en-GB culture, 04/02/2026 should be February 4th");
                Assert.AreEqual(4, dt.Day);
            }
        }

        [TestMethod]
        public void TestDateTimeConversionWithMultipleFormats()
        {
            // Test multiple date formats - should try each format until one succeeds
            string csv = "Name,Date1,Date2,Date3\nJohn,2026-02-04,04/02/2026,Feb 4 2026";
            var options = new CsvReaderOptions
            {
                DateTimeFormats = new[]
                {
                    "yyyy-MM-dd",        // ISO format
                    "dd/MM/yyyy",        // European format
                    "MMM d yyyy"         // Month name format
                },
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Date1", typeof(DateTime) },
                    { "Date2", typeof(DateTime) },
                    { "Date3", typeof(DateTime) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());

                // All three dates should parse to the same day
                DateTime dt1 = reader.GetDateTime(1);
                Assert.AreEqual(2026, dt1.Year);
                Assert.AreEqual(2, dt1.Month);
                Assert.AreEqual(4, dt1.Day);

                DateTime dt2 = reader.GetDateTime(2);
                Assert.AreEqual(2026, dt2.Year);
                Assert.AreEqual(2, dt2.Month);
                Assert.AreEqual(4, dt2.Day);

                DateTime dt3 = reader.GetDateTime(3);
                Assert.AreEqual(2026, dt3.Year);
                Assert.AreEqual(2, dt3.Month);
                Assert.AreEqual(4, dt3.Day);
            }
        }

        [TestMethod]
        public void TestDateTimeConversionWithCustomFormatsAndCulture()
        {
            // Test combining custom formats with custom culture
            // French culture uses different date/time separators and names
            string csv = "Name,Date\nPierre,04/02/2026 15:14:21";
            var options = new CsvReaderOptions
            {
                Culture = new System.Globalization.CultureInfo("fr-FR"),
                DateTimeFormats = new[] { "dd/MM/yyyy HH:mm:ss" },
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Date", typeof(DateTime) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                DateTime dt = reader.GetDateTime(1);
                Assert.AreEqual(2026, dt.Year);
                Assert.AreEqual(2, dt.Month);
                Assert.AreEqual(4, dt.Day);
                Assert.AreEqual(15, dt.Hour);
                Assert.AreEqual(14, dt.Minute);
                Assert.AreEqual(21, dt.Second);
            }
        }

        [TestMethod]
        public void TestDateTimeConversionWithNullValue()
        {
            // Test that NULL values are handled correctly with custom formats
            string csv = "Name,Date\nJohn,2026-02-04\nJane,NULL";
            var options = new CsvReaderOptions
            {
                DateTimeFormats = new[] { "yyyy-MM-dd" },
                NullValue = "NULL",
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Date", typeof(DateTime?) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.IsFalse(reader.IsDBNull(1));
                DateTime dt = reader.GetDateTime(1);
                Assert.AreEqual(2026, dt.Year);
                Assert.AreEqual(2, dt.Month);
                Assert.AreEqual(4, dt.Day);

                Assert.IsTrue(reader.Read());
                Assert.IsTrue(reader.IsDBNull(1), "NULL value should be DBNull");
            }
        }

        [TestMethod]
        public void TestDateTimeConversionWithEmptyValue()
        {
            // Test that empty values are treated as DBNull
            string csv = "Name,Date\nJohn,2026-02-04\nJane,";
            var options = new CsvReaderOptions
            {
                DateTimeFormats = new[] { "yyyy-MM-dd" },
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Date", typeof(DateTime?) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                Assert.IsFalse(reader.IsDBNull(1));

                Assert.IsTrue(reader.Read());
                Assert.IsTrue(reader.IsDBNull(1), "Empty value should be DBNull");
            }
        }

        [TestMethod]
        public void TestDateTimeConversionFormatPrecedence()
        {
            // Test that formats are tried in order and first match wins
            // Ambiguous date 01/02/2026 could be Jan 2 or Feb 1
            string csv = "Name,Date\nTest,01/02/2026";
            var options = new CsvReaderOptions
            {
                // First format is MM/dd/yyyy (US), second is dd/MM/yyyy (EU)
                DateTimeFormats = new[] { "MM/dd/yyyy", "dd/MM/yyyy" },
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Date", typeof(DateTime) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                DateTime dt = reader.GetDateTime(1);
                // Should parse as January 2nd (first format)
                Assert.AreEqual(2026, dt.Year);
                Assert.AreEqual(1, dt.Month, "Should use first format MM/dd/yyyy, so month is January (1)");
                Assert.AreEqual(2, dt.Day);
            }
        }

        [TestMethod]
        public void TestDateTimeConversionWithTimeZoneFormat()
        {
            // Test ISO 8601 format with time zone
            string csv = "Name,Timestamp\nJohn,2026-02-04T15:14:21Z";
            var options = new CsvReaderOptions
            {
                DateTimeFormats = new[] { "yyyy-MM-ddTHH:mm:ssZ" },
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Timestamp", typeof(DateTime) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                DateTime dt = reader.GetDateTime(1);
                Assert.AreEqual(2026, dt.Year);
                Assert.AreEqual(2, dt.Month);
                Assert.AreEqual(4, dt.Day);
                Assert.AreEqual(15, dt.Hour);
                Assert.AreEqual(14, dt.Minute);
                Assert.AreEqual(21, dt.Second);
            }
        }

        [TestMethod]
        public void TestDateTimeConversionWithUSCulture()
        {
            // Test US culture with default parsing (MM/dd/yyyy)
            string csv = "Name,Date\nJohn,02/04/2026";
            var options = new CsvReaderOptions
            {
                Culture = new System.Globalization.CultureInfo("en-US"),
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Date", typeof(DateTime) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                DateTime dt = reader.GetDateTime(1);
                Assert.AreEqual(2026, dt.Year);
                Assert.AreEqual(2, dt.Month, "With en-US culture, 02/04/2026 should be February 4th");
                Assert.AreEqual(4, dt.Day);
            }
        }

        [TestMethod]
        public void TestDateTimeConversionWithShortDateFormat()
        {
            // Test various short date formats
            string csv = "Name,Date1,Date2,Date3\nJohn,2026-2-4,2026.02.04,20260204";
            var options = new CsvReaderOptions
            {
                DateTimeFormats = new[]
                {
                    "yyyy-M-d",          // No leading zeros
                    "yyyy.MM.dd",        // Dot separator
                    "yyyyMMdd"           // No separators
                },
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Date1", typeof(DateTime) },
                    { "Date2", typeof(DateTime) },
                    { "Date3", typeof(DateTime) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());

                DateTime dt1 = reader.GetDateTime(1);
                Assert.AreEqual(2026, dt1.Year);
                Assert.AreEqual(2, dt1.Month);
                Assert.AreEqual(4, dt1.Day);

                DateTime dt2 = reader.GetDateTime(2);
                Assert.AreEqual(2026, dt2.Year);
                Assert.AreEqual(2, dt2.Month);
                Assert.AreEqual(4, dt2.Day);

                DateTime dt3 = reader.GetDateTime(3);
                Assert.AreEqual(2026, dt3.Year);
                Assert.AreEqual(2, dt3.Month);
                Assert.AreEqual(4, dt3.Day);
            }
        }

        [TestMethod]
        public void TestDateTimeConversionWithoutCustomFormats()
        {
            // Verify that without custom formats, standard parsing still works
            string csv = "Name,Date\nJohn,2026-02-04T15:14:21";
            var options = new CsvReaderOptions
            {
                // No DateTimeFormats specified - should use default converter
                ColumnTypes = new System.Collections.Generic.Dictionary<string, Type>
                {
                    { "Date", typeof(DateTime) }
                }
            };

            using (var reader = CreateReaderFromString(csv, options))
            {
                Assert.IsTrue(reader.Read());
                DateTime dt = reader.GetDateTime(1);
                Assert.AreEqual(2026, dt.Year);
                Assert.AreEqual(2, dt.Month);
                Assert.AreEqual(4, dt.Day);
            }
        }

    }
}
