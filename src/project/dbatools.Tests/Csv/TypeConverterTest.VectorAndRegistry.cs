using System;
using System.Linq;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Dataplat.Dbatools.Csv.TypeConverters;

namespace Dataplat.Dbatools.Csv.Tests
{
    public partial class TypeConverterTest
    {

        [TestMethod]
        public void TestVectorConverterJsonArrayFormat()
        {
            var converter = VectorConverter.Default;

            // Test JSON array format
            Assert.IsTrue(converter.TryConvert("[0.1, 0.2, 0.3]", out float[] result));
            Assert.AreEqual(3, result.Length);
            Assert.AreEqual(0.1f, result[0], 0.0001f);
            Assert.AreEqual(0.2f, result[1], 0.0001f);
            Assert.AreEqual(0.3f, result[2], 0.0001f);
        }

        [TestMethod]
        public void TestVectorConverterCommaSeparated()
        {
            var converter = VectorConverter.Default;

            // Test comma-separated format (no brackets)
            Assert.IsTrue(converter.TryConvert("0.5, 1.0, 1.5", out float[] result));
            Assert.AreEqual(3, result.Length);
            Assert.AreEqual(0.5f, result[0], 0.0001f);
            Assert.AreEqual(1.0f, result[1], 0.0001f);
            Assert.AreEqual(1.5f, result[2], 0.0001f);
        }

        [TestMethod]
        public void TestVectorConverterScientificNotation()
        {
            var converter = VectorConverter.Default;

            // Test scientific notation in vectors
            Assert.IsTrue(converter.TryConvert("[1.5e-3, 2.0E2, -3.5e1]", out float[] result));
            Assert.AreEqual(3, result.Length);
            Assert.AreEqual(0.0015f, result[0], 0.000001f);
            Assert.AreEqual(200.0f, result[1], 0.0001f);
            Assert.AreEqual(-35.0f, result[2], 0.0001f);
        }

        [TestMethod]
        public void TestVectorConverterNegativeValues()
        {
            var converter = VectorConverter.Default;

            // Test negative values
            Assert.IsTrue(converter.TryConvert("[-0.5, -1.0, -1.5]", out float[] result));
            Assert.AreEqual(3, result.Length);
            Assert.AreEqual(-0.5f, result[0], 0.0001f);
            Assert.AreEqual(-1.0f, result[1], 0.0001f);
            Assert.AreEqual(-1.5f, result[2], 0.0001f);
        }

        [TestMethod]
        public void TestVectorConverterLargeEmbedding()
        {
            var converter = VectorConverter.Default;

            // Test realistic embedding size (e.g., OpenAI ada-002 uses 1536 dimensions)
            // Create a sample with 100 dimensions for testing
            string vectorString = "[" + string.Join(", ", Enumerable.Range(0, 100).Select(i => (i * 0.01f).ToString("F3"))) + "]";

            Assert.IsTrue(converter.TryConvert(vectorString, out float[] result));
            Assert.AreEqual(100, result.Length);
            Assert.AreEqual(0.0f, result[0], 0.0001f);
            Assert.AreEqual(0.99f, result[99], 0.0001f);
        }

        [TestMethod]
        public void TestVectorConverterWhitespaceHandling()
        {
            var converter = VectorConverter.Default;

            // Test various whitespace scenarios
            Assert.IsTrue(converter.TryConvert("  [  0.1  ,  0.2  ,  0.3  ]  ", out float[] result));
            Assert.AreEqual(3, result.Length);

            Assert.IsTrue(converter.TryConvert("0.1,0.2,0.3", out result)); // No spaces
            Assert.AreEqual(3, result.Length);
        }

        [TestMethod]
        public void TestVectorConverterInvalidInput()
        {
            var converter = VectorConverter.Default;

            // Test invalid inputs
            Assert.IsFalse(converter.TryConvert("", out _));
            Assert.IsFalse(converter.TryConvert(null, out _));
            Assert.IsFalse(converter.TryConvert("[]", out _)); // Empty array
            Assert.IsFalse(converter.TryConvert("[not, a, number]", out _));
            Assert.IsFalse(converter.TryConvert("[0.1, invalid, 0.3]", out _));
            Assert.IsFalse(converter.TryConvert("[", out _)); // Malformed
        }

        [TestMethod]
        public void TestVectorConverterSingleValue()
        {
            var converter = VectorConverter.Default;

            // Test single-value vector
            Assert.IsTrue(converter.TryConvert("[42.5]", out float[] result));
            Assert.AreEqual(1, result.Length);
            Assert.AreEqual(42.5f, result[0], 0.0001f);
        }



        [TestMethod]
        public void TestRegistryDefaultConverters()
        {
            var registry = TypeConverterRegistry.Default;

            Assert.IsNotNull(registry.GetConverter<bool>());
            Assert.IsNotNull(registry.GetConverter<Guid>());
            Assert.IsNotNull(registry.GetConverter<DateTime>());
            Assert.IsNotNull(registry.GetConverter<int>());
            Assert.IsNotNull(registry.GetConverter<long>());
            Assert.IsNotNull(registry.GetConverter<double>());
            Assert.IsNotNull(registry.GetConverter<decimal>());
        }

        [TestMethod]
        public void TestRegistryTryConvert()
        {
            var registry = TypeConverterRegistry.Default;

            Assert.IsTrue(registry.TryConvert("true", typeof(bool), out object result));
            Assert.AreEqual(true, result);

            Assert.IsTrue(registry.TryConvert("42", typeof(int), out result));
            Assert.AreEqual(42, result);
        }

        [TestMethod]
        public void TestRegistryNullableTypes()
        {
            var registry = TypeConverterRegistry.Default;

            // Empty string should return null for nullable types
            Assert.IsTrue(registry.TryConvert("", typeof(int?), out object result));
            Assert.IsNull(result);

            // Valid value should convert
            Assert.IsTrue(registry.TryConvert("42", typeof(int?), out result));
            Assert.AreEqual(42, result);
        }

        [TestMethod]
        public void TestRegistryCustomConverter()
        {
            var registry = TypeConverterRegistry.Default.Clone();
            var customBoolConverter = new BooleanConverter
            {
                CustomTrueValues = new System.Collections.Generic.HashSet<string> { "si", "oui" }
            };
            registry.Register(customBoolConverter);

            Assert.IsTrue(registry.TryConvert("si", typeof(bool), out object result));
            Assert.AreEqual(true, result);
        }

    }
}
