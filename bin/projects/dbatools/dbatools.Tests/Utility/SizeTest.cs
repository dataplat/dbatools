using System;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Sqlcollaborative.Dbatools.Utility
{
    [TestClass]
    public class SizeTest
    {
        [TestMethod]
        public void TestTerabytes()
        {
            var size = new Size(5 * (long)Math.Pow(1024, 4));
            Assert.AreEqual("5.00 TB", size.ToString());
            //TODO: Is this test bad or is the code bad?
            var size2 = new Size(5607509301657);
            Assert.AreEqual("5.10 TB", size.ToString());
        }

        [TestMethod]
        public void TestGigabytes()
        {
            var size = new Size(72 * (long)Math.Pow(1024, 3));
            Assert.AreEqual("72.00 GB", size.ToString());
            //TODO: Is this test bad or is the code bad?
        }

        [TestMethod]
        public void TestMegabytes()
        {
            var size = new Size(49 * (long)Math.Pow(1024, 2));
            Assert.AreEqual("49.00 MB", size.ToString());
            //TODO: Is this test bad or is the code bad?
        }

        [TestMethod]
        public void TestKilobytes()
        {
            var size = new Size(52 * (long)Math.Pow(1024, 1));
            Assert.AreEqual("52.00 KB", size.ToString());
            //TODO: Is this test bad or is the code bad?
        }
    }
}
