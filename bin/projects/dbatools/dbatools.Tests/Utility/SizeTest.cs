using System;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Sqlcollaborative.Dbatools.Utility
{
    [TestClass]
    public class SizeTest
    {
        [TestMethod]
        public void TestDefaultContrustor()
        {
            var size = new Size();
            Assert.AreEqual(0, size.Byte);
            Assert.AreEqual("0 B", size.ToString());
            // Make sure the defaults come from the utility host.
            Assert.AreEqual(UtilityHost.SizeStyle, size.Style);
            Assert.AreEqual(UtilityHost.SizeDigits, size.Digits);
            // Make sure the default are what we explicitly what we expect them to be.
            Assert.AreEqual(SizeStyle.Dynamic, size.Style);
            Assert.AreEqual(2, size.Digits);
        }

        [TestMethod]
        public void TestGetHash()
        {
            var size = 10234453626262624;
            var byteSize = size ;
            Assert.AreEqual(size.GetHashCode(), byteSize.GetHashCode());
        }

        [TestMethod]
        public void TestCompareToObjOfSize()
        {
            var sizes = new Object[] { new Size(42), new Size(56), new Size(42) };
            Assert.AreEqual(-1, ((Size)sizes[0]).CompareTo(sizes[1]));
            Assert.AreEqual(0, ((Size)sizes[0]).CompareTo(sizes[2]));
            Assert.AreEqual(1, ((Size)sizes[1]).CompareTo(sizes[2]));
        }

        [TestMethod]
        public void TestCompareToObjOfInt()
        {
            var sizes = new[] { new Size(42), new Size(56), new Size(42) };
            Assert.AreEqual(-1, sizes[0].CompareTo(sizes[1].Byte));
            Assert.AreEqual(0, sizes[0].CompareTo(sizes[2].Byte));
            Assert.AreEqual(1, sizes[1].CompareTo(sizes[2].Byte));
        }

        [DataRow(42u, 56u)]
        [DataRow(10000u, 2500000u)]
        [DataRow(2u, 7u)]
        [TestMethod]
        public void TestCompareToObjOfUInt(uint a, uint b)
        {
            Assert.IsTrue(a < b, string.Format("Invalid test data, A ({0}) should be less than B ({1})", a, b));
            var sizes = new[] { (Size)a, (Size)b, (Size)a };
            Assert.AreEqual(-1, sizes[0].CompareTo(b));
            Assert.AreEqual(0, sizes[0].CompareTo(a));
            Assert.AreEqual(1, sizes[1].CompareTo(a));
        }

        [DataRow(42, 56)]
        [DataRow(10000, 2500000)]
        [DataRow(2, 7)]
        [TestMethod]
        public void TestCompareToObjOfDecimal(int a, int b)
        {
            Assert.IsTrue(a < b, string.Format("Invalid test data, A ({0}) should be less than B ({1})", a, b));
            var sizes = new[] { (Size)(decimal)a, (Size)(decimal)b, (Size)(decimal)a };
            Assert.AreEqual(-1, sizes[0].CompareTo((decimal)b));
            Assert.AreEqual(0, sizes[0].CompareTo((decimal)a));
            Assert.AreEqual(1, sizes[1].CompareTo((decimal)a));
        }

        [DataRow(42d, 56d)]
        [DataRow(10000d, 2500000d)]
        [DataRow(2d, 7d)]
        [TestMethod]
        public void TestCompareToObjOfDouble(double a, double b)
        {
            Assert.IsTrue(a < b, string.Format("Invalid test data, A ({0}) should be less than B ({1})", a, b));
            var sizes = new [] { (Size)a, (Size)b, (Size)a };
            Assert.AreEqual(-1, sizes[0].CompareTo(b));
            Assert.AreEqual(0, sizes[0].CompareTo(a));
            Assert.AreEqual(1, sizes[1].CompareTo(a));
        }

        [TestMethod]
        [ExpectedException(typeof(ArgumentException))]
        public void TestCompareToObjOfInvalid()
        {
            var size = new Size();
            try
            {
                size.CompareTo(Guid.Empty);
            }
            catch (ArgumentException ex)
            {
                Assert.AreEqual("Cannot compare a Sqlcollaborative.Dbatools.Utility.Size to a System.Guid", ex.Message);
                throw;
            }
        }


        [DataRow(42, 56)]
        [DataRow(10000, 2500000)]
        [DataRow(2, 7)]
        [TestMethod]
        public void TestCompareToSize(int a, int b)
        {
            Assert.IsTrue(a < b, string.Format("Invalid test data, A ({0}) should be less than B ({1})", a, b));
            var sizes = new[] { new Size(a), new Size(b), new Size(a)};
            Assert.AreEqual(-1, sizes[0].CompareTo(sizes[1]));
            Assert.AreEqual(0, sizes[0].CompareTo(sizes[2]));
            Assert.AreEqual(1, sizes[1].CompareTo(sizes[2]));
        }

        [TestMethod]
        public void TestEqualsTo()
        {
            var sizes = new[] { new Size(42), new Size(56), new Size(42)};
            Assert.IsFalse(sizes[0].Equals(sizes[1]));
            Assert.IsTrue(sizes[0].Equals(sizes[2]));
        }

        [TestMethod]
        public void TestDigitsToString()
        {
            var size = new Size(5607509301657);
            Assert.AreEqual("5.10 TB", size.ToString());
            size.Digits = 1;
            Assert.AreEqual("5.1 TB", size.ToString());
            size.Digits = 0;
            Assert.AreEqual("5 TB", size.ToString());
            size.Digits = -42;
            Assert.AreEqual("5 TB", size.ToString());
        }

        [TestMethod]
        public void TestStyleToString()
        {
            var size = new Size(5607509301657);
            Assert.AreEqual("5.10 TB", size.ToString());
            size.Style = SizeStyle.Gigabyte;
            Assert.AreEqual("5,222.40 GB", size.ToString());
            size.Digits = 1;
            Assert.AreEqual("5,222.4 GB", size.ToString());
            size.Digits = 0;
            Assert.AreEqual("5,222 GB", size.ToString());
            size.Style = SizeStyle.Megabyte;
            Assert.AreEqual("5,347,738 MB", size.ToString());
            size.Style = SizeStyle.Kilobyte;
            Assert.AreEqual("5,476,083,302 KB", size.ToString());
            size.Style = SizeStyle.Byte;
            Assert.AreEqual("5607509301657 B", size.ToString());
            size.Style = SizeStyle.Plain;
            Assert.AreEqual("5607509301657", size.ToString());
            // Because the first time we were using dynamic styling.
            size.Style = SizeStyle.Terabyte;
            Assert.AreEqual("5 TB", size.ToString());
        }

        [TestMethod]
        public void TestTerabytes()
        {
            var size = new Size(5607509301657);
            Assert.AreEqual("5.10 TB", size.ToString());
        }

        [TestMethod]
        public void TestGigabytes()
        {
            var size = new Size(72 * (long)Math.Pow(1024, 3));
            Assert.AreEqual("72.00 GB", size.ToString());
        }

        [TestMethod]
        public void TestMegabytes()
        {
            var size = new Size(49 * (long)Math.Pow(1024, 2));
            Assert.AreEqual("49.00 MB", size.ToString());
        }

        [TestMethod]
        public void TestKilobytes()
        {
            var size = new Size(52 * (long)Math.Pow(1024, 1));
            Assert.AreEqual("52.00 KB", size.ToString());
        }

        [TestMethod]
        public void TestBytes()
        {
            var size = new Size(526);
            Assert.AreEqual("526 B", size.ToString());
            size.Digits = 34;
            Assert.AreEqual("526 B", size.ToString());
        }

        [TestMethod]
        public void TestUnlimited()
        {
            var size = new Size(-1);
            Assert.AreEqual("Unlimited", size.ToString());
        }

        [TestMethod]
        public void TestZeroBytes()
        {
            var size = new Size(0);
            Assert.AreEqual("0 B", size.ToString());
        }

        [TestMethod]
        public void TestNegativeBytes()
        {
            var size = new Size(-2);
            Assert.AreEqual("", size.ToString());
        }

        [TestMethod]
        public void TestLargeDecimal()
        {
            Size size = 1000000000000000m;
            Assert.AreEqual(909, size.Terabyte, 0.9);
            Assert.AreEqual(953674316, size.Megabyte, 0.9);
            Assert.AreEqual("909.49 TB", size.ToString());
            decimal reverse = size;
            Assert.AreEqual(1000000000000000m, reverse);
        }

        [TestMethod]
        public void TestLargeDouble()
        {
            Size size = 1000000000000000d;
            Assert.AreEqual(909, size.Terabyte, 0.9);
            Assert.AreEqual("909.49 TB", size.ToString());
            double reverse = size;
            Assert.AreEqual(1000000000000000d, reverse);
        }

        [TestMethod]
        public void TestInt32Cast()
        {
            int iSize = 1000000000;
            Size size = iSize;
            Assert.AreEqual(iSize, size.Byte);
            Assert.AreEqual(953, size.Megabyte, 0.9);
            Assert.AreEqual("953.67 MB", size.ToString());
            int reverse = size;
            Assert.AreEqual(1000000000, reverse);
        }

        [DataRow(1)]
        [DataRow(50)]
        [DataRow(230)]
        [DataRow(53687091200)] // 50 GB
        [DataRow(1000000000000000)]
        [TestMethod]
        public void TestGetHashCode(long iSize)
        {
            var size = new Size(iSize);
            Assert.AreEqual(iSize.GetHashCode(), size.GetHashCode());
        }

        [DataRow(2, 2, 4)]
        [DataRow(1024, 1024, 2048)]
        [DataRow(1024, -1024, 0)]
        [TestMethod]
        public void TestAddition(long a, long b, long result)
        {
            Assert.AreEqual(new Size(result), new Size(a) + new Size(b));
        }

        [DataRow(2, 2, 0)]
        [DataRow(1024, 1024, 0)]
        [DataRow(1024, -1024, 2048)]
        [TestMethod]
        public void TestSubtraction(long a, long b, long result)
        {
            Assert.AreEqual(new Size(result), new Size(a) - new Size(b));
        }

        [DataRow(2, 2, 4)]
        [DataRow(2, 3, 6)]
        [DataRow(1024, 1024, 1048576)]
        [DataRow(1024, -1024, -1048576)]
        [TestMethod]
        public void TestMultiplication(long a, long b, long result)
        {
            Assert.AreEqual(new Size(result), new Size(a) * new Size(b));
        }

        [DataRow(2, 2, 1)]
        [DataRow(2, 3, 0)]
        [DataRow(1024, 1024, 1)]
        [DataRow(1024, -1024, -1)]
        [TestMethod]
        public void TestDivision(long a, long b, long result)
        {
            Assert.AreEqual(new Size(result), new Size(a) / new Size(b));
        }
    }
}
