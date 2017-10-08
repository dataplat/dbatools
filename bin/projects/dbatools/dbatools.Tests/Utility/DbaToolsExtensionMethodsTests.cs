using System;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Sqlcollaborative.Dbatools.Utility
{
    [TestClass]
    public class DbaToolsExtensionMethodsTests
    {
        [TestMethod]
        public void TestGetBytes()
        {
            Assert.IsTrue(new byte[] { 1, 0 }.EqualsArray(DbaPasswordHashVersion.Sql2000.GetBytes()));
            Assert.IsTrue(new byte[] { 2, 0 }.EqualsArray(DbaPasswordHashVersion.Sql2012.GetBytes()));
        }

        [TestMethod]
        [ExpectedException(typeof(ArgumentOutOfRangeException))]
        public void TestGetBytesBadVersion()
        {
            ((DbaPasswordHashVersion)3).GetBytes();
        }


        [TestMethod]
        public void TestCopyArray()
        {
            Assert.IsTrue((new[] { 1, 2, 3 }).EqualsArray(new[] { 1, 2, 3 }));
        }

        [TestMethod]
        public void TestCopyArrayUnequalLengths()
        {
            Assert.IsFalse((new[] { 1, 2, 3 }).EqualsArray(new[] { 1, 2 }));
        }

        [TestMethod]
        public void TestCopyArrayUnequalValues()
        {
            Assert.IsFalse((new[] { 1, 2, 3 }).EqualsArray(new[] { 1, 2, 4 }));
        }
    }
}