using System;
using System.Linq;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Dataplat.Dbatools.Csv.TypeConverters;

namespace Dataplat.Dbatools.Csv.Tests
{
    public partial class TypeConverterTest
    {

        [TestMethod]
        public void TestInt32Converter()
        {
            var converter = Int32Converter.Default;

            Assert.IsTrue(converter.TryConvert("42", out int result));
            Assert.AreEqual(42, result);

            Assert.IsTrue(converter.TryConvert("-100", out result));
            Assert.AreEqual(-100, result);

            Assert.IsFalse(converter.TryConvert("not a number", out _));
        }

        [TestMethod]
        public void TestInt64Converter()
        {
            var converter = Int64Converter.Default;

            Assert.IsTrue(converter.TryConvert("9999999999", out long result));
            Assert.AreEqual(9999999999L, result);
        }

        [TestMethod]
        public void TestDoubleConverter()
        {
            var converter = DoubleConverter.Default;

            Assert.IsTrue(converter.TryConvert("3.14159", out double result));
            Assert.AreEqual(3.14159, result, 0.00001);

            Assert.IsTrue(converter.TryConvert("-1.5e10", out result));
            Assert.AreEqual(-1.5e10, result, 0.01);
        }

        [TestMethod]
        public void TestDecimalConverter()
        {
            var converter = DecimalConverter.Default;

            Assert.IsTrue(converter.TryConvert("123.45", out decimal result));
            Assert.AreEqual(123.45m, result);

            Assert.IsTrue(converter.TryConvert("1234567890.123456", out result));
            Assert.AreEqual(1234567890.123456m, result);
        }

        [TestMethod]
        public void TestDecimalConverterScientificNotation()
        {
            var converter = DecimalConverter.Default;

            // Test case from issue #35
            Assert.IsTrue(converter.TryConvert("1.2345678E5", out decimal result));
            Assert.AreEqual(123456.78m, result);

            // Additional scientific notation tests
            Assert.IsTrue(converter.TryConvert("1.5e10", out result));
            Assert.AreEqual(15000000000m, result);

            Assert.IsTrue(converter.TryConvert("2.5E-3", out result));
            Assert.AreEqual(0.0025m, result);

            Assert.IsTrue(converter.TryConvert("-3.14E2", out result));
            Assert.AreEqual(-314m, result);
        }

        [TestMethod]
        public void TestDecimalConverterThousandsSeparator()
        {
            var converter = DecimalConverter.Default;

            // Test thousands separator (culture-aware)
            Assert.IsTrue(converter.TryConvert("1,234.56", out decimal result));
            Assert.AreEqual(1234.56m, result);

            // Test multiple thousands separators
            Assert.IsTrue(converter.TryConvert("1,234,567.89", out result));
            Assert.AreEqual(1234567.89m, result);

            // Test negative with thousands separator
            Assert.IsTrue(converter.TryConvert("-1,234.56", out result));
            Assert.AreEqual(-1234.56m, result);
        }

        [TestMethod]
        public void TestDecimalConverterEdgeCases()
        {
            var converter = DecimalConverter.Default;

            // Test zero
            Assert.IsTrue(converter.TryConvert("0", out decimal result));
            Assert.AreEqual(0m, result);

            // Test zero in scientific notation
            Assert.IsTrue(converter.TryConvert("0.0E0", out result));
            Assert.AreEqual(0m, result);

            // Test very small number
            Assert.IsTrue(converter.TryConvert("1E-28", out result));
            Assert.AreEqual(0.0000000000000000000000000001m, result);

            // Test near maximum value (decimal.MaxValue is ~7.9E+28)
            Assert.IsTrue(converter.TryConvert("1E+28", out result));
            Assert.AreEqual(10000000000000000000000000000m, result);

            // Test overflow - should fail gracefully
            Assert.IsFalse(converter.TryConvert("1E+30", out _));

            // Test invalid scientific notation
            Assert.IsFalse(converter.TryConvert("1E", out _));
            Assert.IsFalse(converter.TryConvert("E5", out _));
        }

        [TestMethod]
        public void TestDecimalConverterDifferentCultures()
        {
            // Test with German culture (uses comma as decimal separator)
            var germanConverter = new DecimalConverter();
            germanConverter.FormatProvider = System.Globalization.CultureInfo.GetCultureInfo("de-DE");

            Assert.IsTrue(germanConverter.TryConvert("1234,56", out decimal result));
            Assert.AreEqual(1234.56m, result);

            // Test with French culture (uses culture-specific thousands separator, comma as decimal)
            var frenchCulture = System.Globalization.CultureInfo.GetCultureInfo("fr-FR");
            var frenchConverter = new DecimalConverter();
            frenchConverter.FormatProvider = frenchCulture;

            string frenchValue = string.Format(frenchCulture, "1{0}234,56", frenchCulture.NumberFormat.NumberGroupSeparator);
            Assert.IsTrue(frenchConverter.TryConvert(frenchValue, out result));
            Assert.AreEqual(1234.56m, result);
        }

        [TestMethod]
        public void TestMoneyConverter()
        {
            var converter = MoneyConverter.Default;

            // Test basic decimal values
            Assert.IsTrue(converter.TryConvert("123.45", out decimal result));
            Assert.AreEqual(123.45m, result);

            // Test negative values
            Assert.IsTrue(converter.TryConvert("-99.99", out result));
            Assert.AreEqual(-99.99m, result);
        }

        [TestMethod]
        public void TestMoneyConverterWithCurrencySymbols()
        {
            var converter = new MoneyConverter();
            converter.FormatProvider = System.Globalization.CultureInfo.GetCultureInfo("en-US");

            // Test US dollar sign
            Assert.IsTrue(converter.TryConvert("$123.45", out decimal result));
            Assert.AreEqual(123.45m, result);

            // Test negative with dollar sign
            Assert.IsTrue(converter.TryConvert("-$99.99", out result));
            Assert.AreEqual(-99.99m, result);

            // Test parentheses for negative (accounting format)
            Assert.IsTrue(converter.TryConvert("($50.00)", out result));
            Assert.AreEqual(-50.00m, result);
        }

        [TestMethod]
        public void TestMoneyConverterWithThousandsSeparator()
        {
            var converter = new MoneyConverter();
            converter.FormatProvider = System.Globalization.CultureInfo.GetCultureInfo("en-US");

            // Test with thousands separator
            Assert.IsTrue(converter.TryConvert("$1,234.56", out decimal result));
            Assert.AreEqual(1234.56m, result);

            // Test large number with currency
            Assert.IsTrue(converter.TryConvert("$1,234,567.89", out result));
            Assert.AreEqual(1234567.89m, result);
        }

        [TestMethod]
        public void TestMoneyConverterScientificNotation()
        {
            var converter = MoneyConverter.Default;

            // NumberStyles.Currency does NOT include AllowExponent
            Assert.IsFalse(converter.TryConvert("1.5E3", out decimal _));
            Assert.IsFalse(converter.TryConvert("2.5E-2", out decimal _));
        }

        [TestMethod]
        public void TestMoneyConverterInvalidInput()
        {
            var converter = MoneyConverter.Default;

            Assert.IsFalse(converter.TryConvert("invalid", out _));
            Assert.IsFalse(converter.TryConvert("", out _));
            Assert.IsFalse(converter.TryConvert(null, out _));
        }

    }
}
