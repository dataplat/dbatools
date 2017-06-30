using System;
using System.Collections.Generic;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Sqlcollaborative.Dbatools.Utility
{
    [TestClass]
    public class DbaPasswordHashTests
    {
        private sealed class PasswordData
        {
            public string PlainText { get; }
            public string Hash { get; }

            public PasswordData(string plaintext, string hash)
            {
                PlainText = plaintext;
                Hash = hash;
            }
        }

        private readonly IList<PasswordData> _passwords = new List<PasswordData>
        {
            new PasswordData("secretP@ssword", "020044A236AE0264C666A1403706613D91C40BC8264FCE7FB713BDF8770AD951503C95999AF3DBB53FD04A1785B86357EF09EA1E3403F6921D32249AF2C4E9DCB8F09BBC476C"),
            new PasswordData("zippy", "0100F440586023344450835A2B693974B79D93D9E08D9D451ADA1C74C460DA4C5371BC7970AF422C52F88784D002"),
            new PasswordData("ZIPPY", "0100BA51E20BFEC81D855CE4E97F102067F24B29943D92DAC328"),//"FEC81D855CE4E97F102067F24B29943D92DAC328"),
        };

        /// <seealso>
        ///     <cref>https://stackoverflow.com/a/26304129/95195</cref>
        /// </seealso>
        private byte[] HexadecimalStringToByteArray_BestEffort(string input)
        {
            var outputLength = input.Length / 2;
            var output = new byte[outputLength];
            var numeral = new char[2];
            for (var i = 0; i < outputLength; i++)
            {
                input.CopyTo(i * 2, numeral, 0, 2);
                output[i] = Convert.ToByte(new string(numeral), 16);
            }
            return output;
        }

        [TestMethod]
        public void TestHashVerify()
        {
            foreach (var password in _passwords)
            {
                var hashBytes = HexadecimalStringToByteArray_BestEffort(password.Hash);
                var passwordHash = new DbaPasswordHash(hashBytes);
                var generatedHash = DbaPasswordHash.GenerateHash(password.PlainText, passwordHash.Salt, passwordHash.HashVersion, passwordHash.RawHashUpperCase != null);
                Assert.IsTrue(hashBytes.EqualsArray(generatedHash), $"Password hash for {password.PlainText} is incorrect.");
                Assert.IsTrue(passwordHash.VerifyPassword(password.PlainText), $"Verifying password {password.PlainText} against hash failed.");
            }
        }

        [TestMethod]
        public void TestHashVerifyFail()
        {
            var password = _passwords[0];
            var hashBytes = HexadecimalStringToByteArray_BestEffort(password.Hash);
            var passwordHash = new DbaPasswordHash(hashBytes);
            var generatedHash = DbaPasswordHash.GenerateHash("Not the password", passwordHash.Salt);
            Assert.AreNotEqual(hashBytes, generatedHash);
            Assert.IsFalse(passwordHash.VerifyPassword("Not the Password"));
        }

        [TestMethod]
        [ExpectedException(typeof(ArgumentOutOfRangeException))]
        public void TestIncorrectVersion()
        {
            var hashBytes = HexadecimalStringToByteArray_BestEffort("0300");
            // ReSharper disable once ObjectCreationAsStatement
            new DbaPasswordHash(hashBytes);
        }

        [TestMethod]
        [ExpectedException(typeof(ArgumentOutOfRangeException))]
        public void TestGenerateHashIncorrectVersion()
        {
            DbaPasswordHash.GenerateHash("password", version: (DbaPasswordHashVersion)7);
        }

        [TestMethod]
        public void TestInCorrectPasswordLength2012()
        {
            try
            {
                // ReSharper disable once ObjectCreationAsStatement
                new DbaPasswordHash(HexadecimalStringToByteArray_BestEffort("0200FFFFFFFFFF"));
            }
            catch (ArgumentOutOfRangeException ex)
            {
                Assert.AreEqual("Password hash for a Sql Server 2012+ password must be 70 bytes long\r\nParameter name: rawHash", ex.Message);
                return;
            }
            Assert.Fail("This should have thrown.");
        }

        [TestMethod]
        public void TestInCorrectPasswordLength2005()
        {
            try
            {
                // ReSharper disable once ObjectCreationAsStatement
                new DbaPasswordHash(HexadecimalStringToByteArray_BestEffort("0100FFFFFFFFFF"));
            }
            catch (ArgumentOutOfRangeException ex)
            {
                Assert.AreEqual("Password hash for a Sql Server 2005 or 2008 password must be 26 or 46 bytes long\r\nParameter name: rawHash", ex.Message);
                return;
            }
            Assert.Fail("This should have thrown.");
        }

        /// <summary>
        /// We don't actually randomly generate a salt in the main test so do that here.
        /// </summary>
        [TestMethod]
        public void TestPassworWithRandomHash()
        {
            var password = "secretPassword";
            var passwordHash = DbaPasswordHash.GenerateHash(password);
            var passwordHash2000 = DbaPasswordHash.GenerateHash(password, version: DbaPasswordHashVersion.Sql2000);
            Assert.AreNotEqual(passwordHash2000, passwordHash);
            var hashObj = new DbaPasswordHash(passwordHash);
            var hashObj2000 = new DbaPasswordHash(passwordHash2000);
            Assert.IsTrue(hashObj.VerifyPassword(password));
            Assert.IsTrue(hashObj2000.VerifyPassword(password));
        }

        [TestMethod]
        public void TestCaseInsensitivePasswordPasswordHash()
        {
            var password = "s3cretP@ssword";
            var hash = DbaPasswordHash.GenerateHash(password, version: DbaPasswordHashVersion.Sql2000, caseInsensitive: true);
            Assert.AreEqual(DbaPasswordHash.Sha1CaseInsensitivePasswordHashLength, hash.Length);
            var hashObj = new DbaPasswordHash(hash);
            Assert.IsTrue(hashObj.VerifyPassword(password));
            Assert.IsTrue(hashObj.VerifyPassword(password.ToLower()));
            Assert.IsTrue(hashObj.VerifyPassword(password.ToLowerInvariant()));
            Assert.IsTrue(hashObj.VerifyPassword(password.ToUpper()));
            Assert.IsTrue(hashObj.VerifyPassword(password.ToUpperInvariant()));
        }

        /// <summary>
        /// Assert that we can't create a SQL Server 2012+ style password hash that is case insensitive.
        /// </summary>
        [TestMethod]
        [ExpectedException(typeof(ArgumentException))]
        public void TestCaseInsensitiveV2PasswordException()
        {
            var password = "secretPassword";
            DbaPasswordHash.GenerateHash(password, version: DbaPasswordHashVersion.Sql2012, caseInsensitive: true);
        }
    }
}
