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
        }

        [TestMethod]
        public void TestGetHash()
        {
            var size = 10234453626262624;
            var byteSize = new Size(size);
            Assert.AreEqual(size.GetHashCode(), byteSize.GetHashCode());
        }
        
        [TestMethod]
        public void TestCompareTo()
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
    }
}
