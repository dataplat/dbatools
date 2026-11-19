using System;
using System.Linq;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Dataplat.Dbatools.Csv.TypeConverters;

namespace Dataplat.Dbatools.Csv.Tests
{
    [TestClass]
    public partial class TypeConverterTest
    {

        [DataRow("true", true)]
        [DataRow("True", true)]
        [DataRow("TRUE", true)]
        [DataRow("false", false)]
        [DataRow("False", false)]
        [DataRow("FALSE", false)]
        [DataRow("1", true)]
        [DataRow("0", false)]
        [DataRow("yes", true)]
        [DataRow("no", false)]
        [DataRow("y", true)]
        [DataRow("n", false)]
        [DataRow("on", true)]
        [DataRow("off", false)]
        [DataTestMethod]
        public void TestBooleanConverter(string input, bool expected)
        {
            var converter = BooleanConverter.Default;
            Assert.IsTrue(converter.TryConvert(input, out bool result));
            Assert.AreEqual(expected, result);
        }

        [TestMethod]
        public void TestBooleanConverterInvalidInput()
        {
            var converter = BooleanConverter.Default;
            Assert.IsFalse(converter.TryConvert("invalid", out bool _));
            Assert.IsFalse(converter.TryConvert("", out bool _));
            Assert.IsFalse(converter.TryConvert(null, out bool _));
        }



        [DataRow("550e8400-e29b-41d4-a716-446655440000")]
        [DataRow("550E8400-E29B-41D4-A716-446655440000")]
        [DataRow("{550e8400-e29b-41d4-a716-446655440000}")]
        [DataRow("550e8400e29b41d4a716446655440000")]
        [DataTestMethod]
        public void TestGuidConverter(string input)
        {
            var converter = GuidConverter.Default;
            Assert.IsTrue(converter.TryConvert(input, out Guid result));
            Assert.AreEqual(Guid.Parse("550e8400-e29b-41d4-a716-446655440000"), result);
        }

        [TestMethod]
        public void TestGuidConverterInvalidInput()
        {
            var converter = GuidConverter.Default;
            Assert.IsFalse(converter.TryConvert("invalid", out Guid _));
            Assert.IsFalse(converter.TryConvert("", out Guid _));
            Assert.IsFalse(converter.TryConvert(null, out Guid _));
        }



        [TestMethod]
        public void TestDateTimeConverterISO()
        {
            var converter = DateTimeConverter.Default;
            Assert.IsTrue(converter.TryConvert("2024-01-15", out DateTime result));
            Assert.AreEqual(2024, result.Year);
            Assert.AreEqual(1, result.Month);
            Assert.AreEqual(15, result.Day);
        }

        [TestMethod]
        public void TestDateTimeConverterWithTime()
        {
            var converter = DateTimeConverter.Default;
            Assert.IsTrue(converter.TryConvert("2024-01-15 10:30:45", out DateTime result));
            Assert.AreEqual(10, result.Hour);
            Assert.AreEqual(30, result.Minute);
            Assert.AreEqual(45, result.Second);
        }

        [TestMethod]
        public void TestDateTimeConverterDayMonthYear()
        {
            // Addresses issue #9694: Oracle date format (dd-MM-yyyy)
            var converter = DateTimeConverter.DayMonthYear;
            Assert.IsTrue(converter.TryConvert("31-05-2024 00:00:00", out DateTime result));
            Assert.AreEqual(2024, result.Year);
            Assert.AreEqual(5, result.Month);
            Assert.AreEqual(31, result.Day);
        }

        [TestMethod]
        public void TestDateTimeConverterCustomFormat()
        {
            var converter = DateTimeConverter.WithFormats(new[] { "dd/MMM/yyyy" });
            Assert.IsTrue(converter.TryConvert("15/Jan/2024", out DateTime result));
            Assert.AreEqual(2024, result.Year);
            Assert.AreEqual(1, result.Month);
            Assert.AreEqual(15, result.Day);
        }

        [TestMethod]
        public void TestDateTimeConverterSwissCulture()
        {
            // de-CH uses dd.MM.yyyy format - month and day must not be swapped
            var culture = System.Globalization.CultureInfo.GetCultureInfo("de-CH");
            var converter = DateTimeConverter.Default;

            // Day=1, Month=5 - ambiguous (both <= 12), must parse as May 1st not Jan 5th
            Assert.IsTrue(converter.TryConvert("01.05.2026 12:00:00", culture, out object result));
            var dt = (DateTime)result;
            Assert.AreEqual(2026, dt.Year);
            Assert.AreEqual(5, dt.Month, "Month should be 5 (May), not 1");
            Assert.AreEqual(1, dt.Day, "Day should be 1, not 5");

            // Day=2, Month=4 - ambiguous
            Assert.IsTrue(converter.TryConvert("02.04.2026 17:09:41", culture, out result));
            dt = (DateTime)result;
            Assert.AreEqual(4, dt.Month, "Month should be 4 (April), not 2");
            Assert.AreEqual(2, dt.Day, "Day should be 2, not 4");

            // Day=14, Month=4 - unambiguous (14 > 12, can only be day)
            Assert.IsTrue(converter.TryConvert("14.04.2026 17:09:41", culture, out result));
            dt = (DateTime)result;
            Assert.AreEqual(4, dt.Month);
            Assert.AreEqual(14, dt.Day);

            // Day=11, Month=6 - ambiguous
            Assert.IsTrue(converter.TryConvert("11.06.2026 17:10:08", culture, out result));
            dt = (DateTime)result;
            Assert.AreEqual(6, dt.Month, "Month should be 6 (June), not 11");
            Assert.AreEqual(11, dt.Day, "Day should be 11, not 6");
        }

        [TestMethod]
        public void TestDateTimeConverterGermanCulture()
        {
            // de-DE also uses dd.MM.yyyy format
            var culture = System.Globalization.CultureInfo.GetCultureInfo("de-DE");
            var converter = DateTimeConverter.Default;

            Assert.IsTrue(converter.TryConvert("05.03.2026", culture, out object result));
            var dt = (DateTime)result;
            Assert.AreEqual(3, dt.Month, "Month should be 3 (March), not 5");
            Assert.AreEqual(5, dt.Day, "Day should be 5, not 3");
        }

        [TestMethod]
        public void TestDateTimeConverterFrenchCulture()
        {
            // fr-FR uses dd/MM/yyyy format
            var culture = System.Globalization.CultureInfo.GetCultureInfo("fr-FR");
            var converter = DateTimeConverter.Default;

            Assert.IsTrue(converter.TryConvert("05/03/2026", culture, out object result));
            var dt = (DateTime)result;
            Assert.AreEqual(3, dt.Month, "Month should be 3 (March), not 5");
            Assert.AreEqual(5, dt.Day, "Day should be 5, not 3");
        }

    }
}
