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
            // Make sure the defautl are what we explicitly what we expect them to be.
            Assert.AreEqual(SizeStyle.Dynamic, size.Style);
            Assert.AreEqual(2, size.Digits);
        }

        [TestMethod]
        public void TestGetHash()
        {
            var size = 10234453626262624;
            var byteSize = new Size(size);
            Assert.AreEqual(size.GetHashCode(), byteSize.GetHashCode());
        }
        
        [TestMethod]
        public void TestCompareToObjOfSize()
        {
            var sizes = new Object[] { new Size(42), new Size(56), new Size(42)};
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

        [TestMethod]
        public void TestCompareToObjOfUInt()
        {
            var sizes = new[] { new Size(42), new Size(56), new Size(42) };
            Assert.AreEqual(-1, sizes[0].CompareTo(56u));
            Assert.AreEqual(0, sizes[0].CompareTo(42u));
            Assert.AreEqual(1, sizes[1].CompareTo(42u));
        }

        [TestMethod]
        public void TestCompareToObjOfDecimal()
        {
            var sizes = new[] { new Size(42), new Size(56), new Size(42) };
            Assert.AreEqual(-1, sizes[0].CompareTo(56m));
            Assert.AreEqual(0, sizes[0].CompareTo(42m));
            Assert.AreEqual(1, sizes[1].CompareTo(42m));
        }

        [TestMethod]
        public void TestCompareToObjOfDouble()
        {
            var sizes = new[] { new Size(42), new Size(56), new Size(42) };
            Assert.AreEqual(-1, sizes[0].CompareTo(56D));
            Assert.AreEqual(0, sizes[0].CompareTo(42D));
            Assert.AreEqual(1, sizes[1].CompareTo(42D));
        }


        [TestMethod]
        public void TestCompareToSize()
        {
            var sizes = new[] { new Size(42), new Size(56), new Size(42)};
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
    }
}
