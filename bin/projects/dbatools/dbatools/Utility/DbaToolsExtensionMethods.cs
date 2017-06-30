using System;
using System.Collections.Generic;
using System.Linq;

namespace Sqlcollaborative.Dbatools.Utility
{
    /// <summary>
    /// Extension methods used by other classes.
    /// </summary>
    public static class DbaToolsExtensionMethods
    {
        /// <summary>
        /// Adds a compareTo method to DateTime to compare with DbaDateTimeBase
        /// </summary>
        /// <param name="Base">The extended DateTime object</param>
        /// <param name="comparedTo">The DbaDateTimeBase to compare with</param>
        /// <returns></returns>
        public static int CompareTo(this DateTime Base, DbaDateTimeBase comparedTo)
        {
            return Base.CompareTo(comparedTo);
        }

        /// <summary>
        /// Gets a little endian byte array representation of the version code.
        /// </summary>
        /// <returns>either <c>0x0100</c> for SQL 2000-2008 or <c>0x0200</c> for SQL 2012-SQL 2017</returns>
        /// <exception cref="ArgumentOutOfRangeException"></exception>
        /// <remarks>Originally written because I didn't take endianness into account</remarks>
        public static byte[] GetBytes(this DbaPasswordHashVersion version)
        {
            switch (version)
            {
                case DbaPasswordHashVersion.Sql2000:
                    return new byte[] { 1, 0 };
                case DbaPasswordHashVersion.Sql2012:
                    return new byte[] { 2, 0 };
                default:
                    throw new ArgumentOutOfRangeException(nameof(version), version, "Cannot call GetBytes on an invalid password has version.");
            }
        }

        /// <summary>
        /// Tests if an array equals another array.
        /// </summary>
        /// <param name="self">This array.</param>
        /// <param name="comparison">The array we are comparing to.</param>
        /// <typeparam name="T">Type of array contents.</typeparam>
        /// <returns><c>True</c> if the arrays are equal in size and contents. <c>False</c> otherwise.</returns>
        public static bool EqualsArray<T>(this IList<T> self, IList<T> comparison)
        {
            if (self.Count != comparison.Count)
            {
                return false;
            }
            return !self.Where((t, i) => !t.Equals(comparison[i])).Any();
        }
    }
}