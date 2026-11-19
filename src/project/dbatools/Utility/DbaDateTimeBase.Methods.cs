using System;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Utility
{
    public partial class DbaDateTimeBase
    {
        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime Add(TimeSpan value)
        {
            return _timestamp.Add(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddDays(double value)
        {
            return _timestamp.AddDays(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddHours(double value)
        {
            return _timestamp.AddHours(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddMilliseconds(double value)
        {
            return _timestamp.AddMilliseconds(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddMinutes(double value)
        {
            return _timestamp.AddMinutes(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="months"></param>
        /// <returns></returns>
        public DateTime AddMonths(int months)
        {
            return _timestamp.AddMonths(months);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddSeconds(double value)
        {
            return _timestamp.AddSeconds(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddTicks(long value)
        {
            return _timestamp.AddTicks(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public DateTime AddYears(int value)
        {
            return _timestamp.AddYears(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public int CompareTo(System.Object value)
        {
            return _timestamp.CompareTo(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public int CompareTo(DateTime value)
        {
            return _timestamp.CompareTo(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public override bool Equals(System.Object value)
        {
            return _timestamp.Equals(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="value"></param>
        /// <returns></returns>
        public bool Equals(DateTime value)
        {
            return _timestamp.Equals(value);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public string[] GetDateTimeFormats()
        {
            return _timestamp.GetDateTimeFormats();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="provider"></param>
        /// <returns></returns>
        public string[] GetDateTimeFormats(System.IFormatProvider provider)
        {
            return _timestamp.GetDateTimeFormats(provider);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="format"></param>
        /// <returns></returns>
        public string[] GetDateTimeFormats(char format)
        {
            return _timestamp.GetDateTimeFormats(format);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="format"></param>
        /// <param name="provider"></param>
        /// <returns></returns>
        public string[] GetDateTimeFormats(char format, System.IFormatProvider provider)
        {
            return _timestamp.GetDateTimeFormats(format, provider);
        }

        /// <summary>
        /// Retrieve base DateTime object, this is a wrapper for
        /// </summary>
        /// <returns>Base DateTime object</returns>
        public DateTime GetBaseObject()
        {
            return _timestamp;
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public override int GetHashCode()
        {
            return _timestamp.GetHashCode();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
        public System.TypeCode GetTypeCode()
        {
            return _timestamp.GetTypeCode();
        }

        /// <summary>
        /// 
        /// </summary>
        /// <returns></returns>
    }
}
