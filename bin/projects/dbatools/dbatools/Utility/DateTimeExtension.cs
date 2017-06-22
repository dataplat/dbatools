using System;

namespace Sqlcollaborative.Dbatools.Utility
{
    /// <summary>
    /// Extends DateTime
    /// </summary>
    public static class DateTimeExtension
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
    }
}